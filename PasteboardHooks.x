#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ProjectXLogging.h"
#import "PasteboardUUIDManager.h"
#import <ellekit/ellekit.h>

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// Global variables to track state
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes 
static NSMutableDictionary *customChangeCountMap = nil; // Store custom change counts per app
static NSMutableDictionary *lastKnownPasteboardData = nil; // Cache pasteboard content hash

// Forward declarations
static NSString *getCurrentBundleID(void);
static NSDictionary *loadScopedApps(void);
static BOOL isInScopedAppsList(void);

// Callback function for notifications that clear the cache
static void clearCacheCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear cached decisions
    if (cachedBundleDecisions) {
        [cachedBundleDecisions removeAllObjects];
    }
    
    // Also clear change count map
    if (customChangeCountMap) {
        [customChangeCountMap removeAllObjects];
    }
    
    // Clear cached pasteboard data
    if (lastKnownPasteboardData) {
        [lastKnownPasteboardData removeAllObjects];
    }
}

#pragma mark - Scoped Apps Helper Functions

// Get the current bundle ID
static NSString *getCurrentBundleID(void) {
    @try {
        NSBundle *mainBundle = [NSBundle mainBundle];
        if (!mainBundle) {
            return nil;
        }
        return [mainBundle bundleIdentifier];
    } @catch (NSException *e) {
        return nil;
    }
}

// Load scoped apps from the plist file
static NSDictionary *loadScopedApps(void) {
    @try {
        // Check if cache is valid
        if (scopedAppsCache && scopedAppsCacheTimestamp && 
            [[NSDate date] timeIntervalSinceDate:scopedAppsCacheTimestamp] < kScopedAppsCacheValidDuration) {
            return scopedAppsCache;
        }
        
        // Initialize cache if needed
        if (!scopedAppsCache) {
            scopedAppsCache = [NSMutableDictionary dictionary];
        } else {
            [scopedAppsCache removeAllObjects];
        }
        
        // Try each possible path for the scoped apps file
        NSArray *possiblePaths = @[kScopedAppsPath, kScopedAppsPathAlt1, kScopedAppsPathAlt2];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *validPath = nil;
        
        for (NSString *path in possiblePaths) {
            if ([fileManager fileExistsAtPath:path]) {
                validPath = path;
                break;
            }
        }
        
        if (!validPath) {
            // Don't log this error too frequently to avoid spam
            static NSDate *lastErrorLog = nil;
            if (!lastErrorLog || [[NSDate date] timeIntervalSinceDate:lastErrorLog] > 300.0) { // 5 minutes
                PXLog(@"[PasteboardHooks] Could not find scoped apps file");
                lastErrorLog = [NSDate date];
            }
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Load the plist file safely
        NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:validPath];
        if (!plistDict || ![plistDict isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Get the scoped apps dictionary
        NSDictionary *scopedApps = plistDict[@"ScopedApps"];
        if (!scopedApps || ![scopedApps isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Copy the scoped apps to our cache
        [scopedAppsCache addEntriesFromDictionary:scopedApps];
        scopedAppsCacheTimestamp = [NSDate date];
        
        return scopedAppsCache;
        
    } @catch (NSException *e) {
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache ?: [NSMutableDictionary dictionary];
    }
}

// Check if the current app is in the scoped apps list
static BOOL isInScopedAppsList(void) {
    @try {
        NSString *bundleID = getCurrentBundleID();
        if (!bundleID || [bundleID length] == 0) {
            return NO;
        }
        
        NSDictionary *scopedApps = loadScopedApps();
        if (!scopedApps || scopedApps.count == 0) {
            return NO;
        }
        
        // Check if this bundle ID is in the scoped apps dictionary
        id appEntry = scopedApps[bundleID];
        if (!appEntry || ![appEntry isKindOfClass:[NSDictionary class]]) {
            return NO;
        }
        
        // Check if the app is enabled
        BOOL isEnabled = [appEntry[@"enabled"] boolValue];
        return isEnabled;
        
    } @catch (NSException *e) {
        return NO;
    }
}

// Helper function to check if we should spoof for this bundle ID (with caching)
static BOOL shouldSpoofForBundle(NSString *bundleID) {
    if (!bundleID) return NO;
    
    // Skip system apps, the tweak itself, and system processes - more comprehensive filtering
    if ([bundleID hasPrefix:@"com.apple."] || 
        [bundleID isEqualToString:@"com.hydra.projectx"] ||
        [bundleID containsString:@"springboard"] ||
        [bundleID containsString:@"backboardd"] ||
        [bundleID containsString:@"mediaserverd"] ||
        [bundleID containsString:@"searchd"] ||
        [bundleID containsString:@"assertiond"] ||
        [bundleID containsString:@"useractivityd"] ||
        [bundleID containsString:@"apsd"] ||
        [bundleID containsString:@"identityservicesd"] ||
        [bundleID containsString:@"coreduetd"] ||
        [bundleID containsString:@"sharingd"] ||
        [bundleID containsString:@"mobiletimerd"] ||
        ([bundleID containsString:@"system"] && [bundleID containsString:@"daemon"])) {
        return NO;
    }
    
    // Get the executable path to check if it's a system binary
    NSString *executablePath = [[NSBundle mainBundle] executablePath];
    if (executablePath && 
        ([executablePath hasPrefix:@"/usr/"] || 
         [executablePath hasPrefix:@"/bin/"] || 
         [executablePath hasPrefix:@"/sbin/"])) {
        return NO;
    }
    
    // Check cache first
    if (!cachedBundleDecisions) {
        cachedBundleDecisions = [NSMutableDictionary dictionary];
    } else {
        NSNumber *cachedDecision = cachedBundleDecisions[bundleID];
        NSDate *decisionTimestamp = cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]];
        
        if (cachedDecision && decisionTimestamp && 
            [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
            return [cachedDecision boolValue];
        }
    }
    
    // Check if the current app is a scoped app
    BOOL isScoped = isInScopedAppsList();
    
    // Cache the decision
    cachedBundleDecisions[bundleID] = @(isScoped);
    cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    
    return isScoped;
}

// Add function to get spoofed Pasteboard UUID from manager
static NSString *getSpoofedPasteboardUUID() {
    // Use the PasteboardUUIDManager for consistent values across the app and hooks
    PasteboardUUIDManager *manager = [PasteboardUUIDManager sharedManager];
    NSString *uuid = [manager currentPasteboardUUID];
    
    if (uuid && uuid.length > 0) {
        return uuid;
    }
    
    // Generate a new UUID if none exists
    uuid = [manager generatePasteboardUUID];
    if (uuid && uuid.length > 0) {
        return uuid;
    }
    
    // Try to read directly from plist files
    // First try to get the profile directory from environment or fallback
    NSString *identityDir = nil;
    
    // Try to determine profile directory from common paths
    NSArray *possibleProfilePaths = @[
        @"/var/jb/var/mobile/Library/WeaponX/Profiles",
        @"/var/jb/private/var/mobile/Library/WeaponX/Profiles", 
        @"/var/mobile/Library/WeaponX/Profiles"
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *profileBasePath in possibleProfilePaths) {
        if ([fileManager fileExistsAtPath:profileBasePath]) {
            // Get current profile ID
            NSString *currentProfileInfoPath = [profileBasePath stringByAppendingPathComponent:@"current_profile_info.plist"];
            NSDictionary *currentProfileInfo = [NSDictionary dictionaryWithContentsOfFile:currentProfileInfoPath];
            NSString *profileId = currentProfileInfo[@"ProfileId"];
            
            if (profileId) {
                identityDir = [[profileBasePath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
                break;
            }
        }
    }
    
    if (identityDir) {
        // First try the combined device_ids.plist
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
        NSString *value = deviceIds[@"PasteboardUUID"];
        
        if (value) {
            PXLog(@"[WeaponX] 🔄 Got PasteboardUUID from device_ids.plist: %@", value);
            return value;
        }
        
        // Try the specific uuid file
        NSString *uuidPath = [identityDir stringByAppendingPathComponent:@"pasteboard_uuid.plist"];
        NSDictionary *uuidDict = [NSDictionary dictionaryWithContentsOfFile:uuidPath];
        if (uuidDict && uuidDict[@"value"]) {
            PXLog(@"[WeaponX] 🔄 Got PasteboardUUID from pasteboard_uuid.plist: %@", uuidDict[@"value"]);
            return uuidDict[@"value"];
        }
    }
    
    // If we still don't have a UUID, generate a new one rather than using zeros
    uuid = [[NSUUID UUID] UUIDString];
    PXLog(@"[WeaponX] 🔄 Generated fallback PasteboardUUID: %@", uuid);
    return uuid;
}

// Helper for safe change count management
static NSInteger getCustomChangeCount(NSString *bundleID, NSInteger originalCount) {
    if (!customChangeCountMap) {
        customChangeCountMap = [NSMutableDictionary dictionary];
    }
    
    NSNumber *currentValue = customChangeCountMap[bundleID];
    if (!currentValue) {
        // First time seeing this app, initialize with original count
        NSInteger initialValue = originalCount;
        customChangeCountMap[bundleID] = @(initialValue);
        return initialValue;
    }
    
    return [currentValue integerValue];
}

// Helper to safely increment change count
static void incrementCustomChangeCount(NSString *bundleID) {
    if (!customChangeCountMap) {
        customChangeCountMap = [NSMutableDictionary dictionary];
    }
    
    NSNumber *currentValue = customChangeCountMap[bundleID];
    NSInteger newValue = currentValue ? [currentValue integerValue] + 1 : 1;
    customChangeCountMap[bundleID] = @(newValue);
}

// Helper to compute a hash of pasteboard content for change detection
static NSString *getPasteboardContentHash(UIPasteboard *pasteboard) {
    @try {
        NSMutableString *hashInput = [NSMutableString string];
        
        // Add string items
        NSArray *types = @[@"public.text", @"public.plain-text", @"public.utf8-plain-text"];
        for (NSString *type in types) {
            if ([pasteboard containsPasteboardTypes:@[type]]) {
                NSString *string = [pasteboard valueForPasteboardType:type];
                if (string) {
                    [hashInput appendString:string];
                }
            }
        }
        
        // Add image data hash if possible
        if (pasteboard.image) {
            NSData *imageData = UIImagePNGRepresentation(pasteboard.image);
            if (imageData) {
                [hashInput appendFormat:@"IMG:%lu", (unsigned long)imageData.hash];
            }
        }
        
        // Add URL strings
        if (pasteboard.URL) {
            [hashInput appendString:[pasteboard.URL absoluteString]];
        }
        
        // Compute hash of the combined content
        return [NSString stringWithFormat:@"%lu", (unsigned long)[hashInput hash]];
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception computing pasteboard hash: %@", exception);
        return @"ERROR";
    }
}

// Helper to check if pasteboard content has changed
static BOOL hasPasteboardContentChanged(NSString *bundleID, UIPasteboard *pasteboard) {
    @try {
        if (!lastKnownPasteboardData) {
            lastKnownPasteboardData = [NSMutableDictionary dictionary];
        }
        
        NSString *newHash = getPasteboardContentHash(pasteboard);
        NSString *oldHash = lastKnownPasteboardData[bundleID];
        
        // Update stored hash
        lastKnownPasteboardData[bundleID] = newHash;
        
        // If no previous hash or different hash, it changed
        return !oldHash || ![oldHash isEqualToString:newHash];
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception checking pasteboard changes: %@", exception);
        return NO;
    }
}

#pragma mark - UIPasteboard Hooks

%hook UIPasteboard

// Hook the main pasteboard UUID method
- (NSUUID *)uniquePasteboardUUID {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID)) {
            // Get spoofed Pasteboard UUID
            NSString *uuidString = getSpoofedPasteboardUUID();
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
            PXLog(@"[WeaponX] 🔄 Spoofing Pasteboard UUID with: %@", uuidString);
            return uuid;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in uniquePasteboardUUID hook: %@", exception);
    }
    
    // Call original if we're not spoofing
    return %orig;
}

// Hook name property which can contain identifying information
- (NSString *)name {
    NSString *originalName = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Only spoof on custom-named pasteboards, not the general one
        if (shouldSpoofForBundle(bundleID) && originalName && ![originalName isEqualToString:@"com.apple.UIKit.pboard.general"]) {
            // Get current pasteboard UUID
            NSString *uuidString = getSpoofedPasteboardUUID();
            
            // Create a stable, deterministic name based on the spoofed UUID
            // We only replace the last component to maintain compatibility
            NSArray *components = [originalName componentsSeparatedByString:@"."];
            if (components.count > 0) {
                NSMutableArray *newComponents = [NSMutableArray arrayWithArray:components];
                
                // Replace last component with the first part of our UUID
                NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
                newComponents[newComponents.count - 1] = shortUUID;
                
                NSString *spoofedName = [newComponents componentsJoinedByString:@"."];
                PXLog(@"[WeaponX] 🔄 Spoofing Pasteboard name from '%@' to '%@'", originalName, spoofedName);
                return spoofedName;
            }
            
            // Fallback if components array doesn't have elements (shouldn't happen with valid names)
            // Just append the short UUID to maintain a unique but stable name
            NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
            NSString *spoofedName = [NSString stringWithFormat:@"%@.%@", originalName, shortUUID];
            PXLog(@"[WeaponX] 🔄 Spoofing Pasteboard name (fallback) from '%@' to '%@'", originalName, spoofedName);
            return spoofedName;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in name hook: %@", exception);
    }
    
    return originalName;
}

// Hook the general pasteboard accessor to ensure consistent UUID behavior
+ (UIPasteboard *)generalPasteboard {
    UIPasteboard *original = %orig;
    
    @try {
        // We don't need to do anything here, as uniquePasteboardUUID is hooked above
        // This override just ensures we're tracking all possible entry points
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID)) {
            PXLog(@"[WeaponX] 📋 Accessed general pasteboard from %@", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in generalPasteboard hook: %@", exception);
    }
    
    return original;
}

// Hook the named pasteboard creation method
+ (UIPasteboard *)pasteboardWithName:(NSString *)pasteboardName create:(BOOL)create {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID) && pasteboardName) {
            // Get current pasteboard UUID
            NSString *uuidString = getSpoofedPasteboardUUID();
            
            // Create a stable, deterministic name based on the spoofed UUID
            // We only replace the last component to maintain compatibility
            NSArray *components = [pasteboardName componentsSeparatedByString:@"."];
            if (components.count > 0) {
                NSMutableArray *newComponents = [NSMutableArray arrayWithArray:components];
                
                // Replace last component with the first part of our UUID
                NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
                newComponents[newComponents.count - 1] = shortUUID;
                
                NSString *spoofedName = [newComponents componentsJoinedByString:@"."];
                PXLog(@"[WeaponX] 🔄 Creating pasteboard with spoofed name: %@ (original: %@)", spoofedName, pasteboardName);
                return %orig(spoofedName, create);
            }
            
            // Fallback if components array doesn't have elements
            NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
            NSString *spoofedName = [NSString stringWithFormat:@"%@.%@", pasteboardName, shortUUID];
            PXLog(@"[WeaponX] 🔄 Creating pasteboard with spoofed name (fallback): %@ (original: %@)", spoofedName, pasteboardName);
            return %orig(spoofedName, create);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in pasteboardWithName:create: hook: %@", exception);
    }
    
    return %orig;
}

// Hook the pasteboard URL initialization method
+ (UIPasteboard *)pasteboardWithUniqueName {
    UIPasteboard *original = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID) && original) {
            // We intercept the uniquePasteboardUUID method above
            // So this automatically gets our spoofed value 
            PXLog(@"[WeaponX] 📋 Created pasteboard with unique name from %@", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in pasteboardWithUniqueName hook: %@", exception);
    }
    
    return original;
}

// Hook URL-based pasteboard creation (iOS 10+)
+ (UIPasteboard *)pasteboardWithURL:(NSURL *)url create:(BOOL)create {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID) && url) {
            // Create a modified URL with our UUID to ensure stable but unique URLs
            NSString *uuidString = getSpoofedPasteboardUUID();
            NSString *shortUUID = [uuidString componentsSeparatedByString:@"-"].firstObject;
            
            // Create a new URL with our UUID injected to ensure stability
            NSURL *spoofedURL;
            NSString *originalURLString = [url absoluteString];
            
            if ([originalURLString containsString:@"?"]) {
                // URL already has query parameters, add ours
                spoofedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@&uuid=%@", 
                                                   originalURLString, shortUUID]];
            } else {
                // URL has no query parameters, add our own
                spoofedURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@?uuid=%@", 
                                                   originalURLString, shortUUID]];
            }
            
            if (!spoofedURL) {
                // If URL manipulation failed, fall back to original URL
                spoofedURL = url;
            }
            
            PXLog(@"[WeaponX] 🔄 Creating pasteboard with spoofed URL: %@ (original: %@)", 
                 spoofedURL, url);
            return %orig(spoofedURL, create);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in pasteboardWithURL:create: hook: %@", exception);
    }
    
    return %orig;
}

// Hook change count property used for pasteboard change detection
- (NSInteger)changeCount {
    NSInteger originalCount = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID)) {
            // Get our custom change count
            NSInteger spoofedCount = getCustomChangeCount(bundleID, originalCount);
            
            // Check if content actually changed, and if so, increment our count
            if (hasPasteboardContentChanged(bundleID, self)) {
                incrementCustomChangeCount(bundleID);
                spoofedCount = getCustomChangeCount(bundleID, originalCount);
            }
            
            PXLog(@"[WeaponX] 🔄 Spoofing pasteboard changeCount: %ld (original: %ld)", 
                 (long)spoofedCount, (long)originalCount);
            return spoofedCount;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in changeCount hook: %@", exception);
    }
    
    return originalCount;
}

// Hook persistent property to prevent fingerprinting
- (void)setPersistent:(BOOL)persistent {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID)) {
            // Always allow pasteboard to be persistent to avoid crashes
            // but log the attempt to track fingerprinting
            PXLog(@"[WeaponX] 📋 App %@ trying to set pasteboard persistence: %@", 
                 bundleID, persistent ? @"YES" : @"NO");
            %orig(YES);
            return;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setPersistent: hook: %@", exception);
    }
    
    %orig;
}

// Hook persistent property getter
- (BOOL)isPersistent {
    BOOL originalValue = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID)) {
            // Always report persistent to avoid issues
            PXLog(@"[WeaponX] 📋 App %@ checking pasteboard persistence", bundleID);
            return YES;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in isPersistent hook: %@", exception);
    }
    
    return originalValue;
}

// Hook itemProviders for controlling access to pasteboard data types
- (NSArray *)itemProviders {
    NSArray *originalProviders = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID) && originalProviders) {
            PXLog(@"[WeaponX] 📋 App %@ accessing pasteboard item providers (%lu items)", 
                 bundleID, (unsigned long)originalProviders.count);
            
            // We don't need to modify the providers as we're already spoofing the UUID
            // But we do want to track access for fingerprinting detection
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in itemProviders hook: %@", exception);
    }
    
    return originalProviders;
}

// Hook itemSet method for controlling access to pasteboard data types
- (NSArray *)itemSetWithPreferredPasteboardTypes:(NSArray *)types {
    NSArray *originalItemSet = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID) && originalItemSet) {
            PXLog(@"[WeaponX] 📋 App %@ accessing pasteboard items with preferred types: %@", 
                 bundleID, types);
            
            // We don't modify the items, just track access for fingerprinting detection
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in itemSetWithPreferredPasteboardTypes: hook: %@", exception);
    }
    
    return originalItemSet;
}

// Hook containsPasteboardTypes method which might be used for fingerprinting
- (BOOL)containsPasteboardTypes:(NSArray *)pasteboardTypes {
    BOOL originalResult = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID) && pasteboardTypes) {
            // Log suspicious fingerprinting types
            if ([pasteboardTypes containsObject:@"com.apple.uikit.pboard-uuid"] ||
                [pasteboardTypes containsObject:@"com.apple.uikit.pboard-devices"]) {
                PXLog(@"[WeaponX] ⚠️ Possible fingerprinting: App %@ checking for special types: %@", 
                      bundleID, pasteboardTypes);
            }
            
            // We don't modify the return value as that could break app functionality
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in containsPasteboardTypes: hook: %@", exception);
    }
    
    return originalResult;
}

// Hook valueForPasteboardType to monitor and potentially modify access to types
- (id)valueForPasteboardType:(NSString *)pasteboardType {
    id originalValue = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID) && pasteboardType) {
            // Check for device-specific or identity types
            if ([pasteboardType isEqualToString:@"com.apple.uikit.pboard-uuid"] ||
                [pasteboardType isEqualToString:@"com.apple.uikit.pboard-devices"] ||
                [pasteboardType containsString:@"uuid"] ||
                [pasteboardType containsString:@"device"]) {
                
                PXLog(@"[WeaponX] ⚠️ App %@ accessing potentially identifying pasteboard type: %@",
                      bundleID, pasteboardType);
                
                // Return nil for sensitive types to prevent fingerprinting
                if ([pasteboardType isEqualToString:@"com.apple.uikit.pboard-uuid"]) {
                    NSString *spoofedUUID = getSpoofedPasteboardUUID();
                    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:spoofedUUID];
                    
                    // Use modern API with error handling instead of deprecated method
                    NSError *archiveError = nil;
                    NSData *uuidData = nil;
                    
                    if (@available(iOS 12.0, *)) {
                        uuidData = [NSKeyedArchiver archivedDataWithRootObject:uuid requiringSecureCoding:NO error:&archiveError];
                        if (archiveError) {
                            PXLog(@"[WeaponX] ⚠️ Error archiving UUID data: %@", archiveError);
                        }
                    } else {
                        // Fallback for older iOS versions
                        @try {
                            #pragma clang diagnostic push
                            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                            uuidData = [NSKeyedArchiver archivedDataWithRootObject:uuid];
                            #pragma clang diagnostic pop
                        } @catch (NSException *exception) {
                            PXLog(@"[WeaponX] ⚠️ Exception archiving UUID data: %@", exception);
                        }
                    }
                    
                    if (uuidData) {
                        return uuidData;
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in valueForPasteboardType: hook: %@", exception);
    }
    
    return originalValue;
}

// Hook data setter to monitor content changes and maintain our change count
- (void)setData:(NSData *)data forPasteboardType:(NSString *)pasteboardType {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID)) {
            // Increment our custom change count whenever content changes
            incrementCustomChangeCount(bundleID);
            PXLog(@"[WeaponX] 📋 App %@ setting pasteboard data for type: %@", bundleID, pasteboardType);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setData:forPasteboardType: hook: %@", exception);
    }
    
    %orig;
}

// Hook items setter to monitor content changes
- (void)setItems:(NSArray *)items {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        if (shouldSpoofForBundle(bundleID)) {
            // Increment our custom change count whenever content changes
            incrementCustomChangeCount(bundleID);
            PXLog(@"[WeaponX] 📋 App %@ setting pasteboard items (%lu items)", 
                 bundleID, (unsigned long)items.count);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in setItems: hook: %@", exception);
    }
    
    %orig;
}

%end

#pragma mark - NSNotification Hooks for Pasteboard

// Hook notification posting to intercept pasteboard change notifications
%hook NSNotificationCenter

- (void)postNotification:(NSNotification *)notification {
    @try {
        NSString *name = notification.name;
        
        // Check for UIPasteboard change notifications
        if ([name isEqualToString:UIPasteboardChangedNotification] ||
            [name hasPrefix:@"UIPasteboard"] ||
            [name containsString:@"Pasteboard"]) {
            
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            if (shouldSpoofForBundle(bundleID)) {
                // Let these through but log them for tracking fingerprinting
                PXLog(@"[WeaponX] 📋 Pasteboard notification: %@ in app %@", name, bundleID);
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] ⚠️ Exception in postNotification: hook for notifications: %@", exception);
    }
    
    %orig;
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        // Skip for system processes
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || [bundleID hasPrefix:@"com.apple."]) {
            return;
        }
        
        // Initialize caches
        cachedBundleDecisions = [NSMutableDictionary dictionary];
        customChangeCountMap = [NSMutableDictionary dictionary];
        lastKnownPasteboardData = [NSMutableDictionary dictionary];
        
        // Register for settings change notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            clearCacheCallback,
            CFSTR("com.hydra.projectx.settings.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Register for profile change notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            clearCacheCallback,
            CFSTR("com.hydra.projectx.profileChanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        PXLog(@"[WeaponX] 📋 Initialized PasteboardHooks for %@", bundleID);
    }
} 