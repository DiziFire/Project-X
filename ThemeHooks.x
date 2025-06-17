#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ProjectXLogging.h"
#import <objc/runtime.h>
#import <ellekit/ellekit.h>

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// Cache for bundle decisions and theme values
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSString *cachedThemeValue = nil;
static NSDate *cacheTimestamp = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes in seconds

// Forward declarations
static NSString *getCurrentBundleID(void);
static NSDictionary *loadScopedApps(void);
static BOOL isInScopedAppsList(void);

// Define the possible theme values
typedef NS_ENUM(NSInteger, WeaponXThemeStyle) {
    WeaponXThemeStyleUnspecified,
    WeaponXThemeStyleLight,
    WeaponXThemeStyleDark
};

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
                PXLog(@"[ThemeHooks] Could not find scoped apps file");
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

// Helper function to check if we should spoof theme for this bundle ID (with caching)
static BOOL shouldSpoofForBundle(NSString *bundleID) {
    if (!bundleID) return NO;
    
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
    
    // Skip spoofing for system apps
    if ([bundleID hasPrefix:@"com.apple."] && 
        ![bundleID isEqualToString:@"com.apple.mobilesafari"] &&
        ![bundleID isEqualToString:@"com.apple.webapp"]) {
        cachedBundleDecisions[bundleID] = @NO;
        cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
        return NO;
    }
    
    // Check if the current app is a scoped app
    BOOL isScoped = isInScopedAppsList();
    
    // Cache the decision
    cachedBundleDecisions[bundleID] = @(isScoped);
    cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    
    return isScoped;
}

// Helper function to get theme value from profile
static WeaponXThemeStyle getThemeStyleFromProfile(void) {
    // Skip cache if it's more than 5 minutes old
    BOOL shouldRefresh = NO;
    if (!cacheTimestamp || [[NSDate date] timeIntervalSinceDate:cacheTimestamp] > kCacheValidityDuration) {
        shouldRefresh = YES;
    }
    
    // Use cached value if available and not expired
    if (!shouldRefresh && cachedThemeValue) {
        if ([cachedThemeValue isEqualToString:@"Dark"]) {
            return WeaponXThemeStyleDark;
        } else if ([cachedThemeValue isEqualToString:@"Light"]) {
            return WeaponXThemeStyleLight;
        }
    }
    
    // Read theme value directly from profile files
    NSString *themeValue = nil;
    
    // Try to get the current profile directory
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
                // Try to read theme from device_ids.plist
                NSString *identityDir = [[profileBasePath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
                NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
                themeValue = deviceIds[@"DeviceTheme"];
                
                if (themeValue) {
                    break;
                }
                
                // Try to read from device_theme.plist
                NSString *deviceThemePath = [identityDir stringByAppendingPathComponent:@"device_theme.plist"];
                NSDictionary *deviceTheme = [NSDictionary dictionaryWithContentsOfFile:deviceThemePath];
                themeValue = deviceTheme[@"value"];
                
                if (themeValue) {
                    break;
                }
            }
        }
    }
    
    // Fallback to default if nothing found
    if (!themeValue) {
        themeValue = @"Light"; // Default to light theme
    }
    
    // Update cache
    cachedThemeValue = themeValue;
    cacheTimestamp = [NSDate date];
    
    // Return the appropriate theme style
    if ([themeValue isEqualToString:@"Dark"]) {
        return WeaponXThemeStyleDark;
    } else if ([themeValue isEqualToString:@"Light"]) {
        return WeaponXThemeStyleLight;
    }
    
    return WeaponXThemeStyleUnspecified;
}

// UIUserInterfaceStyle mapping function
static UIUserInterfaceStyle mapThemeStyleToUIUserInterfaceStyle(WeaponXThemeStyle themeStyle) {
    switch (themeStyle) {
        case WeaponXThemeStyleDark:
            return UIUserInterfaceStyleDark;
        case WeaponXThemeStyleLight:
            return UIUserInterfaceStyleLight;
        case WeaponXThemeStyleUnspecified:
        default:
            return UIUserInterfaceStyleUnspecified;
    }
}

// Hook definitions
%group ThemeHooks

// Hook UITraitCollection to intercept userInterfaceStyle
%hook UITraitCollection

// Method for getting userInterfaceStyle property
- (UIUserInterfaceStyle)userInterfaceStyle {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Check if spoofing is needed for this app
    if (bundleID && shouldSpoofForBundle(bundleID)) {
        WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
        
        if (themeStyle != WeaponXThemeStyleUnspecified) {
            UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
            
            // Log the first time we spoof for an app (to reduce spam)
            static NSMutableSet *loggedApps = nil;
            if (!loggedApps) {
                loggedApps = [NSMutableSet set];
            }
            
            if (![loggedApps containsObject:bundleID]) {
                [loggedApps addObject:bundleID];
                PXLog(@"[WeaponX] 🎨 Spoofing device theme for %@ to: %@", 
                      bundleID, 
                      (spoofedStyle == UIUserInterfaceStyleDark) ? @"Dark" : @"Light");
            }
            
            return spoofedStyle;
        }
    }
    
    // Return original value if not spoofing
    return %orig;
}

// For iOS 17, there's a new named retrieval method
- (UIUserInterfaceStyle)effectiveUserInterfaceStyle {
    if (@available(iOS 17.0, *)) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Check if spoofing is needed for this app
        if (bundleID && shouldSpoofForBundle(bundleID)) {
            WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
            
            if (themeStyle != WeaponXThemeStyleUnspecified) {
                return mapThemeStyleToUIUserInterfaceStyle(themeStyle);
            }
        }
    }
    
    // Return original value if not spoofing
    return %orig;
}

%end

// Hook UIScreen to intercept system-wide theme setting
%hook UIScreen

- (UITraitCollection *)traitCollection {
    UITraitCollection *originalTraitCollection = %orig;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Check if we need to spoof
    if (bundleID && shouldSpoofForBundle(bundleID)) {
        WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
        
        if (themeStyle != WeaponXThemeStyleUnspecified) {
            // Create a trait collection with our spoofed interface style
            UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
            
            UITraitCollection *interfaceStyleTrait = [UITraitCollection traitCollectionWithUserInterfaceStyle:spoofedStyle];
            
            // Merge with original trait collection to preserve other traits
            return [UITraitCollection traitCollectionWithTraitsFromCollections:@[originalTraitCollection, interfaceStyleTrait]];
        }
    }
    
    return originalTraitCollection;
}

%end

// Hook UIView for apps that check theme at the view level
%hook UIView

- (UITraitCollection *)traitCollection {
    UITraitCollection *originalTraitCollection = %orig;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Check if we need to spoof
    if (bundleID && shouldSpoofForBundle(bundleID)) {
        WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
        
        if (themeStyle != WeaponXThemeStyleUnspecified) {
            // Create a trait collection with our spoofed interface style
            UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
            
            UITraitCollection *interfaceStyleTrait = [UITraitCollection traitCollectionWithUserInterfaceStyle:spoofedStyle];
            
            // Merge with original trait collection to preserve other traits
            return [UITraitCollection traitCollectionWithTraitsFromCollections:@[originalTraitCollection, interfaceStyleTrait]];
        }
    }
    
    return originalTraitCollection;
}

%end

// Hook UIViewController for apps that check theme at the controller level
%hook UIViewController

- (UITraitCollection *)traitCollection {
    UITraitCollection *originalTraitCollection = %orig;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Check if we need to spoof
    if (bundleID && shouldSpoofForBundle(bundleID)) {
        WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
        
        if (themeStyle != WeaponXThemeStyleUnspecified) {
            // Create a trait collection with our spoofed interface style
            UIUserInterfaceStyle spoofedStyle = mapThemeStyleToUIUserInterfaceStyle(themeStyle);
            
            UITraitCollection *interfaceStyleTrait = [UITraitCollection traitCollectionWithUserInterfaceStyle:spoofedStyle];
            
            // Merge with original trait collection to preserve other traits
            return [UITraitCollection traitCollectionWithTraitsFromCollections:@[originalTraitCollection, interfaceStyleTrait]];
        }
    }
    
    return originalTraitCollection;
}

%end

// Hook any WebKit bridges for web detection of dark mode
%hook WKWebView

// Hook preferredColorScheme for WebKit
- (void)_setPreferredColorScheme:(NSInteger)colorScheme {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    // Check if we need to spoof
    if (bundleID && shouldSpoofForBundle(bundleID)) {
        WeaponXThemeStyle themeStyle = getThemeStyleFromProfile();
        
        if (themeStyle != WeaponXThemeStyleUnspecified) {
            // Map our theme style to WebKit's color scheme values (0 = light, 1 = dark)
            NSInteger spoofedColorScheme = (themeStyle == WeaponXThemeStyleDark) ? 1 : 0;
            %orig(spoofedColorScheme);
            return;
        }
    }
    
    %orig;
}

%end

%end // End of ThemeHooks group

// Notification handler to refresh theme settings when toggled
static void themeSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    PXLog(@"[WeaponX] Received settings notification: %@", notificationName);
    
    // Clear cached info to force refresh
    cachedThemeValue = nil;
    cacheTimestamp = nil;
    
    // Clear the bundle decisions cache too
    [cachedBundleDecisions removeAllObjects];
}

// Constructor to initialize hooks
%ctor {
    @autoreleasepool {
        @try {
            PXLog(@"[ThemeHooks] Initializing theme hooks");
            
            NSString *bundleID = getCurrentBundleID();
            
            // Skip if we can't get bundle ID
            if (!bundleID || [bundleID length] == 0) {
                return;
            }
            
            // Don't hook system processes and our own apps
            if ([bundleID hasPrefix:@"com.apple."] || 
                [bundleID isEqualToString:@"com.hydra.projectx"] || 
                [bundleID isEqualToString:@"com.hydra.weaponx"]) {
                PXLog(@"[ThemeHooks] Not hooking system process: %@", bundleID);
                return;
            }
            
            // CRITICAL: Only install hooks if this app is actually scoped
            if (!isInScopedAppsList()) {
                // App is NOT scoped - no hooks, no interference, no crashes
                PXLog(@"[ThemeHooks] App %@ is not scoped, skipping hook installation", bundleID);
                return;
            }
            
            PXLog(@"[ThemeHooks] App %@ is scoped, setting up theme hooks", bundleID);
            
            // Initialize hooks for scoped apps only
            %init(ThemeHooks);
            
            // Register for theme spoofing toggle notification
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                themeSettingsChanged,
                CFSTR("com.hydra.projectx.toggleDeviceThemeSpoof"),
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );
            
            // Also register for general settings and profile change notifications
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                themeSettingsChanged,
                CFSTR("com.hydra.projectx.settings.changed"),
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );
            
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                themeSettingsChanged,
                CFSTR("com.hydra.projectx.profileChanged"),
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );
            
            PXLog(@"[ThemeHooks] Theme hooks successfully initialized for scoped app: %@", bundleID);
            
        } @catch (NSException *e) {
            PXLog(@"[ThemeHooks] ❌ Exception in constructor: %@", e);
        }
    }
} 