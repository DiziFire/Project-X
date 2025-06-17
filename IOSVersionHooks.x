#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ProjectXLogging.h"
#import "IOSVersionInfo.h"
#import <WebKit/WebKit.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <ellekit/ellekit.h>
#import <mach/mach_time.h>

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// Add a macro for logging with a recognizable prefix
// Set DEBUG_LOG to 0 to reduce logging in production
#define DEBUG_LOG 0

#if DEBUG_LOG
#define IOSVERSION_LOG(fmt, ...) NSLog((@"[iosversion] " fmt), ##__VA_ARGS__)
#else
// Only log important messages when DEBUG_LOG is off
#define IOSVERSION_LOG(fmt, ...) if ([fmt hasPrefix:@"❌"] || [fmt hasPrefix:@"⚠️"]) NSLog((@"[iosversion] " fmt), ##__VA_ARGS__)
#endif

// Forward declarations
static NSString *getCurrentBundleID(void);
static NSDictionary *loadScopedApps(void);
static BOOL isInScopedAppsList(void);
static BOOL isCriticalSystemProcess(NSString *bundleID);
static void modifyUserAgentString(NSString **userAgentString, NSString *originalVersion, NSString *spoofedVersion);
static BOOL isSystemVersionFile(NSString *path);
static NSDictionary *spoofSystemVersionPlist(NSDictionary *originalPlist);

// Function declarations for file access hooks
NSData* replaced_NSData_dataWithContentsOfFile(Class self, SEL _cmd, NSString *path);
NSDictionary* replaced_NSDictionary_dictionaryWithContentsOfFile(Class self, SEL _cmd, NSString *path);
id replaced_NSString_stringWithContentsOfFile(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);

// Original sysctlbyname function pointer for hooking
static int (*original_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

// Original function pointers for direct file access hooks
static NSData* (*original_NSData_dataWithContentsOfFile)(Class self, SEL _cmd, NSString *path);
static NSDictionary* (*original_NSDictionary_dictionaryWithContentsOfFile)(Class self, SEL _cmd, NSString *path);
static id (*original_NSString_stringWithContentsOfFile)(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);

// Global variables
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes
static NSMutableDictionary *versionCache = nil;
static NSTimeInterval lastVersionLoad = 0;

// Throttling variables to prevent excessive function calls
static uint64_t lastSystemVersionCallTime = 0;
static NSString *cachedSystemVersionResult = nil;
static uint64_t lastDictCallTime = 0;
static CFDictionaryRef cachedDictResult = NULL;

// Define constants
#define VERSION_CACHE_VALID_PERIOD 1800.0 // 30 minutes
#define THROTTLE_INTERVAL_NSEC 100000000  // 100ms in nanoseconds

// SystemVersion.plist path constants
#define SYSTEM_VERSION_PATH @"/System/Library/CoreServices/SystemVersion.plist"
#define ROOTLESS_SYSTEM_VERSION_PATH @"/var/jb/System/Library/CoreServices/SystemVersion.plist"

#pragma mark - Helper Functions

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
                PXLog(@"[IOSVersionHooks] Could not find scoped apps file");
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

// Critical system processes to exclude from spoofing
static NSSet *criticalSystemBundleIDs() {
    static NSSet *criticalBundleIDs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        criticalBundleIDs = [NSSet setWithArray:@[
            @"com.apple.springboard",
            @"com.apple.backboardd",
            @"com.apple.Preferences",
            @"com.apple.UIKit",
            @"com.apple.iokit",
            @"com.apple.mediaserverd",
            @"com.apple.dock",
            @"com.apple.security",
            @"com.apple.powerd",
            @"com.apple.tccd",
            @"com.apple.launchd",
            @"com.apple.trustd",
            @"com.apple.CoreTelephony",
            // Note: The following browser-related bundle IDs are kept in this list
            // but special handling in isCriticalSystemProcess allows spoofing for them
            @"com.apple.mobilesafari",
            @"com.apple.WebKit",
            @"com.apple.WebKit.WebContent",
            @"com.apple.WebKit.Networking"
        ]];
    });
    return criticalBundleIDs;
}

// Helper function to check if we should spoof for this bundle ID (with caching)
static BOOL shouldSpoofForBundle(NSString *bundleID) {
    @try {
        // Basic validation
        if (!bundleID) {
            NSLog(@"[iosversion] Skipping iOS version spoofing for nil bundleID");
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
        
        // Skip spoofing for system apps and critical processes
        if (isCriticalSystemProcess(bundleID)) {
            cachedBundleDecisions[bundleID] = @NO;
            cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
            return NO;
        }
        
        // Check if the current app is a scoped app
        BOOL isScoped = isInScopedAppsList();
        
        // Cache the decision
        cachedBundleDecisions[bundleID] = @(isScoped);
        cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
        
        if (isScoped) {
            NSLog(@"[iosversion] iOS Version spoofing enabled for %@", bundleID);
        }
        
        return isScoped;
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in shouldSpoofForBundle: %@", e);
        return NO; // Default to NO for safety
    }
}

// Get the current iOS version information from the profile
static NSDictionary *getIOSVersionInfo() {
    static dispatch_once_t onceToken;
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    // Check if we have a cached version that's still valid
    if (versionCache && (now - lastVersionLoad < VERSION_CACHE_VALID_PERIOD)) {
        return versionCache;
    }
    
    // Read version value directly from profile files
    NSString *formattedVersion = nil;
    
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
                // Try to read iOS version from device_ids.plist
                NSString *identityDir = [[profileBasePath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
                NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
                formattedVersion = deviceIds[@"IOSVersion"];
                
                if (formattedVersion) {
                    break;
                }
                
                // Try to read from ios_version.plist
                NSString *iosVersionPath = [identityDir stringByAppendingPathComponent:@"ios_version.plist"];
                NSDictionary *iosVersion = [NSDictionary dictionaryWithContentsOfFile:iosVersionPath];
                formattedVersion = iosVersion[@"value"];
                
                if (formattedVersion) {
                    break;
                }
            }
        }
    }
    
    if (!formattedVersion) {
        // Fallback: try to use IOSVersionInfo to generate a random version
        @try {
            IOSVersionInfo *versionManager = [NSClassFromString(@"IOSVersionInfo") sharedManager];
            if (versionManager) {
                NSDictionary *randomVersionInfo = [versionManager generateIOSVersionInfo];
                if (randomVersionInfo) {
                    IOSVERSION_LOG(@"Using fallback random iOS version from IOSVersionInfo");
                    
                    // Cache the result
                    versionCache = [randomVersionInfo copy];
                    lastVersionLoad = now;
                    
                    return versionCache;
                }
            }
        } @catch (NSException *e) {
            IOSVERSION_LOG(@"❌ Error using IOSVersionInfo fallback: %@", e);
        }
        
        return nil;
    }
    
    // Parse the formatted version string to extract version and build
    // Format is typically "15.5 (19F77)"
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([0-9.]+)\\s*\\(([^)]+)\\)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:formattedVersion options:0 range:NSMakeRange(0, formattedVersion.length)];
    
    if (match && match.numberOfRanges == 3) {
        NSString *version = [formattedVersion substringWithRange:[match rangeAtIndex:1]];
        NSString *build = [formattedVersion substringWithRange:[match rangeAtIndex:2]];
        
        // CRITICAL FIX: Look up the full version info from IOSVersionInfo database
        NSDictionary *fullVersionInfo = nil;
        @try {
            IOSVersionInfo *versionManager = [NSClassFromString(@"IOSVersionInfo") sharedManager];
            if (versionManager) {
                // Get all available versions from the database
                NSArray *availableVersions = [versionManager availableIOSVersions];
                
                // Find the matching version/build pair in the database
                for (NSDictionary *versionData in availableVersions) {
                    if ([versionData[@"version"] isEqualToString:version] && 
                        [versionData[@"build"] isEqualToString:build]) {
                        fullVersionInfo = versionData;
                        break;
                    }
                }
                
                // If we didn't find an exact match, try to find the closest version
                if (!fullVersionInfo) {
                    for (NSDictionary *versionData in availableVersions) {
                        if ([versionData[@"version"] isEqualToString:version]) {
                            fullVersionInfo = versionData;
                            IOSVERSION_LOG(@"⚠️ Using closest match for version %@ with build %@ instead of %@", 
                                  version, versionData[@"build"], build);
                            break;
                        }
                    }
                }
                
                // Last resort: use the parsed version/build but create kernel info
                if (!fullVersionInfo) {
                    IOSVERSION_LOG(@"⚠️ No exact match found, creating synthetic kernel info for %@ (%@)", version, build);
                    
                    // Create synthetic kernel version based on the iOS version
                    NSString *syntheticKernelVersion;
                    NSString *syntheticDarwin;
                    NSString *syntheticXnu;
                    
                    // Map iOS versions to approximate kernel versions
                    if ([version hasPrefix:@"15."]) {
                        syntheticDarwin = @"21.6.0";
                        syntheticXnu = @"8020.140.41~4";
                        syntheticKernelVersion = [NSString stringWithFormat:@"Darwin Kernel Version %@: Mon Jul 18 22:28:05 PDT 2022; root:xnu-%@/RELEASE_ARM64_T8101", syntheticDarwin, syntheticXnu];
                    } else if ([version hasPrefix:@"16."]) {
                        syntheticDarwin = @"22.6.0";
                        syntheticXnu = @"8796.141.3~6";
                        syntheticKernelVersion = [NSString stringWithFormat:@"Darwin Kernel Version %@: Thu Sep 14 16:33:11 PDT 2023; root:xnu-%@/RELEASE_ARM64_T8101", syntheticDarwin, syntheticXnu];
                    } else if ([version hasPrefix:@"17."]) {
                        syntheticDarwin = @"23.6.0";
                        syntheticXnu = @"10063.141.2~3";
                        syntheticKernelVersion = [NSString stringWithFormat:@"Darwin Kernel Version %@: Tue Jun 11 18:30:45 PDT 2024; root:xnu-%@/RELEASE_ARM64_T6000", syntheticDarwin, syntheticXnu];
                    } else if ([version hasPrefix:@"18."]) {
                        syntheticDarwin = @"24.2.0";
                        syntheticXnu = @"10461.61.1~4";
                        syntheticKernelVersion = [NSString stringWithFormat:@"Darwin Kernel Version %@: Mon Oct 14 20:27:31 PDT 2024; root:xnu-%@/RELEASE_ARM64_T6000", syntheticDarwin, syntheticXnu];
                    } else {
                        // Default fallback for unknown versions
                        syntheticDarwin = @"22.6.0";
                        syntheticXnu = @"8796.141.3~6";
                        syntheticKernelVersion = [NSString stringWithFormat:@"Darwin Kernel Version %@: Thu Sep 14 16:33:11 PDT 2023; root:xnu-%@/RELEASE_ARM64_T8101", syntheticDarwin, syntheticXnu];
                    }
                    
                    fullVersionInfo = @{
                        @"version": version,
                        @"build": build,
                        @"kernel_version": syntheticKernelVersion,
                        @"darwin": syntheticDarwin,
                        @"xnu": syntheticXnu
                    };
                }
            }
        } @catch (NSException *e) {
            IOSVERSION_LOG(@"❌ Error looking up version info from IOSVersionInfo: %@", e);
            
            // Fallback to basic version info without kernel data
            fullVersionInfo = @{
                @"version": version,
                @"build": build
            };
        }
        
        // Use the full version info or fallback to basic info
        NSDictionary *versionInfo = fullVersionInfo ?: @{
            @"version": version,
            @"build": build
        };
        
        // Cache the result
        versionCache = [versionInfo copy];
        lastVersionLoad = now;
        
        // Only log this message once to reduce logging
        dispatch_once(&onceToken, ^{
            IOSVERSION_LOG(@"Using iOS version: %@ with build: %@, kernel: %@", 
                  versionInfo[@"version"], 
                  versionInfo[@"build"],
                  versionInfo[@"kernel_version"] ?: @"Not available");
        });
        
        return versionInfo;
    }
    
    return nil;
}

// Extract just the version number from the full version info
static NSString *getSpoofedSystemVersion() {
    NSDictionary *versionInfo = getIOSVersionInfo();
    return versionInfo ? versionInfo[@"version"] : nil;
}

// Convert version string to NSOperatingSystemVersion struct
static NSOperatingSystemVersion getOperatingSystemVersion(NSString *versionString) {
    NSArray *components = [versionString componentsSeparatedByString:@"."];
    
    NSInteger majorVersion = components.count > 0 ? [components[0] integerValue] : 0;
    NSInteger minorVersion = components.count > 1 ? [components[1] integerValue] : 0;
    NSInteger patchVersion = components.count > 2 ? [components[2] integerValue] : 0;
    
    return (NSOperatingSystemVersion){majorVersion, minorVersion, patchVersion};
}

// Helper function to modify a user agent string with the spoofed iOS version
static void modifyUserAgentString(NSString **userAgentString, NSString *originalVersion, NSString *spoofedVersion) {
    if (!userAgentString || !*userAgentString || !spoofedVersion || !originalVersion) {
        return;
    }
    
    NSString *originalUA = *userAgentString;
    
    // Common patterns to handle:
    // 1. Mobile/15E148 (for older formats)
    // 2. OS 15_4 like Mac (for newer formats)
    // 3. Version/15.4 (for Safari)
    // 4. CPU OS 15_4 (for iPad)
    // 5. Mozilla/5.0 (iPhone; CPU iPhone OS 15_4 like Mac OS X)
    // 6. AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15
    
    // Pattern 1: Mobile/15E148
    NSRegularExpression *mobileRegex = [NSRegularExpression regularExpressionWithPattern:@"(Mobile)/\\d+[A-Z]\\d+" options:0 error:nil];
    NSString *spoofedBuild = getIOSVersionInfo()[@"build"];
    NSString *updatedUA = originalUA;
    
    if (spoofedBuild) {
        updatedUA = [mobileRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1/%@", spoofedBuild]];
    }
    
    // Pattern 2: OS 15_4 like Mac
    NSString *underscoreVersion = [spoofedVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSRegularExpression *osRegex = [NSRegularExpression regularExpressionWithPattern:@"(OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like\\s+Mac)" options:0 error:nil];
    updatedUA = [osRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 3: Version/15.4
    NSRegularExpression *versionRegex = [NSRegularExpression regularExpressionWithPattern:@"(Version/)\\d+\\.\\d+(?:\\.\\d+)?" options:0 error:nil];
    updatedUA = [versionRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@", spoofedVersion]];
    
    // Pattern 4: CPU OS 15_4
    NSRegularExpression *cpuOSRegex = [NSRegularExpression regularExpressionWithPattern:@"(CPU\\s+OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [cpuOSRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 5: CPU iPhone OS 15_4
    NSRegularExpression *iPhoneOSRegex = [NSRegularExpression regularExpressionWithPattern:@"(CPU iPhone OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [iPhoneOSRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    // Pattern 6: Mozilla/5.0 (iPhone; ... OS X)
    NSRegularExpression *mozillaRegex = [NSRegularExpression regularExpressionWithPattern:@"(Mozilla/5\\.0 \\([^;]+; [^;]+; [^\\s]+\\s+OS\\s+)\\d+[_\\.]\\d+(?:[_\\.]\\d+)?(\\s+like)" options:0 error:nil];
    updatedUA = [mozillaRegex stringByReplacingMatchesInString:updatedUA options:0 range:NSMakeRange(0, updatedUA.length) withTemplate:[NSString stringWithFormat:@"$1%@$2", underscoreVersion]];
    
    if (![updatedUA isEqualToString:originalUA]) {
        *userAgentString = updatedUA;
        IOSVERSION_LOG(@"Modified UA: %@ → %@", originalUA, updatedUA);
    } else {
        IOSVERSION_LOG(@"Failed to modify UA: %@", originalUA);
    }
}

#pragma mark - UIDevice Hooks

%hook UIDevice

// Hook the systemVersion method to return our spoofed version
- (NSString *)systemVersion {
    @try {
        // Rate limiting - don't call this function too frequently
        uint64_t currentTime = mach_absolute_time();
        if (cachedSystemVersionResult != nil && 
            (currentTime - lastSystemVersionCallTime) < THROTTLE_INTERVAL_NSEC) {
            return cachedSystemVersionResult;
        }
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            if (spoofedVersion) {
                NSString *originalVersion = %orig;
                
                // Only log occasionally to reduce overhead
                if (lastSystemVersionCallTime == 0 || (currentTime - lastSystemVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                    IOSVERSION_LOG(@"UIDevice.systemVersion: %@ → %@", originalVersion, spoofedVersion);
                }
                
                // Update cache and timestamp
                lastSystemVersionCallTime = currentTime;
                cachedSystemVersionResult = spoofedVersion;
                
                return spoofedVersion;
            }
        }
        
        // Cache the original result too
        NSString *originalResult = %orig;
        lastSystemVersionCallTime = currentTime;
        cachedSystemVersionResult = originalResult;
        return originalResult;
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in systemVersion hook: %@", e);
    }
    
    return %orig;
}

%end

#pragma mark - NSProcessInfo Hooks

%hook NSProcessInfo

// Hook operatingSystemVersion to return our spoofed version
- (NSOperatingSystemVersion)operatingSystemVersion {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            if (spoofedVersion) {
                NSOperatingSystemVersion originalVersion = %orig;
                NSOperatingSystemVersion spoofedStructVersion = getOperatingSystemVersion(spoofedVersion);
                
                NSLog(@"[iosversion] NSProcessInfo.operatingSystemVersion: %ld.%ld.%ld → %ld.%ld.%ld", 
                      (long)originalVersion.majorVersion, 
                      (long)originalVersion.minorVersion, 
                      (long)originalVersion.patchVersion,
                      (long)spoofedStructVersion.majorVersion, 
                      (long)spoofedStructVersion.minorVersion, 
                      (long)spoofedStructVersion.patchVersion);
                
                return spoofedStructVersion;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in operatingSystemVersion hook: %@", e);
    }
    return %orig;
}

// Hook isOperatingSystemAtLeastVersion to handle our spoofed version
- (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            if (spoofedVersion) {
                NSOperatingSystemVersion spoofedStructVersion = getOperatingSystemVersion(spoofedVersion);
                
                // Implement the comparison logic ourselves instead of calling orig
                BOOL result = (spoofedStructVersion.majorVersion > version.majorVersion) ||
                             ((spoofedStructVersion.majorVersion == version.majorVersion) && 
                              (spoofedStructVersion.minorVersion > version.minorVersion)) ||
                             ((spoofedStructVersion.majorVersion == version.majorVersion) && 
                              (spoofedStructVersion.minorVersion == version.minorVersion) && 
                              (spoofedStructVersion.patchVersion >= version.patchVersion));
                
                BOOL originalResult = %orig;
                NSLog(@"[iosversion] NSProcessInfo.isOperatingSystemAtLeastVersion: %ld.%ld.%ld, original: %d → spoofed: %d", 
                      (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion,
                      originalResult, result);
                
                return result;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] Error in isOperatingSystemAtLeastVersion hook: %@", e);
    }
    return %orig;
}

// Additional method to hook for getting raw operating system version string
- (NSString *)operatingSystemVersionString {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            NSDictionary *versionInfo = getIOSVersionInfo();
            if (versionInfo && versionInfo[@"version"]) {
                NSString *originalVersion = %orig;
                NSString *spoofedVersion = [NSString stringWithFormat:@"Version %@ (Build %@)", 
                                           versionInfo[@"version"], 
                                           versionInfo[@"build"]];
                
                IOSVERSION_LOG(@"NSProcessInfo.operatingSystemVersionString: %@ → %@", 
                      originalVersion, spoofedVersion);
                      
                return spoofedVersion;
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in operatingSystemVersionString hook: %@", e);
    }
    
    return %orig;
}

%end

#pragma mark - WKWebView User Agent Hooks

// Hook WKWebView to modify the user agent
%hook WKWebView

+ (WKWebView *)_allowedTopLevelWebView:(WKWebView *)webView {
    WKWebView *resultWebView = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if ((forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) && resultWebView) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                // Get the current user agent
                if ([resultWebView respondsToSelector:@selector(evaluateJavaScript:completionHandler:)]) {
                    [resultWebView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(NSString *userAgent, NSError *error) {
                        if (userAgent && [userAgent isKindOfClass:[NSString class]]) {
                            // Modify the user agent string
                            NSMutableString *modifiedUA = [userAgent mutableCopy];
                            modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                            
                            // Set the new user agent if it changed
                            if (![modifiedUA isEqualToString:userAgent]) {
                                if ([resultWebView respondsToSelector:@selector(setCustomUserAgent:)]) {
                                    [resultWebView setCustomUserAgent:modifiedUA];
                                    IOSVERSION_LOG(@"Set modified user agent for WebView in %@", bundleID);
                                }
                            }
                        }
                    }];
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in _allowedTopLevelWebView: %@", e);
    }
    
    return resultWebView;
}

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKWebView *webView = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if ((forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) && webView) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                // First, if configuration has applicationNameForUserAgent, try to modify it
                if (configuration && [configuration respondsToSelector:@selector(applicationNameForUserAgent)]) {
                    NSString *appName = [configuration applicationNameForUserAgent];
                    if (appName) {
                        NSMutableString *modifiedName = [appName mutableCopy];
                        modifyUserAgentString(&modifiedName, originalVersion, spoofedVersion);
                        
                        if (![modifiedName isEqualToString:appName]) {
                            [configuration setApplicationNameForUserAgent:modifiedName];
                            IOSVERSION_LOG(@"Modified applicationNameForUserAgent: %@ → %@", appName, modifiedName);
                        }
                    }
                }
                
                // Now try to set customUserAgent directly if possible
                if ([webView respondsToSelector:@selector(customUserAgent)] && 
                    [webView respondsToSelector:@selector(setCustomUserAgent:)]) {
                    
                    // Try to get existing customUserAgent first
                NSString *currentUserAgent = [webView customUserAgent];
                if (currentUserAgent) {
                    NSMutableString *modifiedUA = [currentUserAgent mutableCopy];
                    modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                    
                    if (![modifiedUA isEqualToString:currentUserAgent]) {
                        [webView setCustomUserAgent:modifiedUA];
                            IOSVERSION_LOG(@"Set custom user agent on init: %@ → %@", currentUserAgent, modifiedUA);
                        }
                    } else {
                        // If no custom user agent yet, we need to get the default one and modify it
                        [webView evaluateJavaScript:@"navigator.userAgent" completionHandler:^(NSString *userAgent, NSError *error) {
                            if (userAgent && [userAgent isKindOfClass:[NSString class]]) {
                                NSMutableString *modifiedUA = [userAgent mutableCopy];
                                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                                
                                if (![modifiedUA isEqualToString:userAgent]) {
                                    [webView setCustomUserAgent:modifiedUA];
                                    IOSVERSION_LOG(@"Set custom user agent from default: %@ → %@", userAgent, modifiedUA);
                                }
                            }
                        }];
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in initWithFrame: %@", e);
    }
    
    return webView;
}

- (void)setCustomUserAgent:(NSString *)customUserAgent {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if ((forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) && customUserAgent) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                NSMutableString *modifiedUA = [customUserAgent mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:customUserAgent]) {
                    IOSVERSION_LOG(@"Setting modified custom UA: %@ → %@", customUserAgent, modifiedUA);
                    %orig(modifiedUA);
                    return;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
        IOSVERSION_LOG(@"Error in setCustomUserAgent: %@", e);
    }
    
    %orig;
}

// Add hooks for common JavaScript evaluation methods to modify user agent when detected
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(id)completionHandler {
    // Check if this is a user agent detection script
    BOOL isUserAgentScript = [javaScriptString containsString:@"navigator.userAgent"];
    
    // Let the original method run first
    %orig;
    
    // If it's a user agent script, try to update the user agent
    if (isUserAgentScript) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        // Special case for Safari and WebKit processes to force spoofing
        BOOL forceSpoofForWebKit = [bundleID isEqualToString:@"com.apple.mobilesafari"] || 
                                  [bundleID hasPrefix:@"com.apple.WebKit"];
        
        if (forceSpoofForWebKit || shouldSpoofForBundle(bundleID)) {
            // Wait a short time to let the script execute
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *spoofedVersion = getSpoofedSystemVersion();
                NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
                
                if (spoofedVersion && [self respondsToSelector:@selector(customUserAgent)]) {
                    NSString *currentUA = [self customUserAgent];
                    if (currentUA) {
                        NSMutableString *modifiedUA = [currentUA mutableCopy];
                        modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                        
                        if (![modifiedUA isEqualToString:currentUA]) {
                            [self setCustomUserAgent:modifiedUA];
                            IOSVERSION_LOG(@"Updated UA after JS evaluation: %@ → %@", currentUA, modifiedUA);
                        }
                    }
                }
            });
        }
    }
}

%end

#pragma mark - WKWebViewConfiguration Hooks

%hook WKWebViewConfiguration

- (void)setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID) && applicationNameForUserAgent) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion) {
                NSMutableString *modifiedName = [applicationNameForUserAgent mutableCopy];
                modifyUserAgentString(&modifiedName, originalVersion, spoofedVersion);
                
                if (![modifiedName isEqualToString:applicationNameForUserAgent]) {
                    %orig(modifiedName);
                    return;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    %orig;
}

%end

#pragma mark - NSURLRequest User-Agent Hooks

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    @try {
        if ([field isEqualToString:@"User-Agent"] && value) {
            NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
            if (shouldSpoofForBundle(bundleID)) {
                NSString *spoofedVersion = getSpoofedSystemVersion();
                NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
                
                if (spoofedVersion) {
                    NSMutableString *modifiedValue = [value mutableCopy];
                    modifyUserAgentString(&modifiedValue, originalVersion, spoofedVersion);
                    
                    if (![modifiedValue isEqualToString:value]) {
                        %orig(modifiedValue, field);
                        return;
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    %orig;
}

%end

#pragma mark - Safari Specific Hooks

// Hook Safari's SFUserAgentController to modify the user agent string
%hook SFUserAgentController

+ (NSString *)userAgentWithDomain:(NSString *)domain {
    NSString *originalUA = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion && originalUA) {
                NSMutableString *modifiedUA = [originalUA mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:originalUA]) {
                    IOSVERSION_LOG(@"Safari: Modified user agent for domain %@", domain);
                    return modifiedUA;
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"Error modifying Safari user agent: %@", e);
    }
    
    return originalUA;
}

+ (NSString *)defaultUserAgentString {
    NSString *originalUA = %orig;
    
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"]) {
            NSString *spoofedVersion = getSpoofedSystemVersion();
            NSString *originalVersion = [[UIDevice currentDevice] systemVersion];
            
            if (spoofedVersion && originalUA) {
                NSMutableString *modifiedUA = [originalUA mutableCopy];
                modifyUserAgentString(&modifiedUA, originalVersion, spoofedVersion);
                
                if (![modifiedUA isEqualToString:originalUA]) {
                    IOSVERSION_LOG(@"Safari: Modified default user agent");
                    return modifiedUA;
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"Error modifying Safari default user agent: %@", e);
    }
    
    return originalUA;
}

%end

#pragma mark - CoreFoundation Version Dictionary Hook

// Hook CFCopySystemVersionDictionary to spoof iOS version information at the CoreFoundation level
static CFDictionaryRef (*original_CFCopySystemVersionDictionary)(void);
CFDictionaryRef replaced_CFCopySystemVersionDictionary(void) {
    @try {
        // Rate limiting to prevent excessive calls
        uint64_t currentTime = mach_absolute_time();
        if (cachedDictResult != NULL && 
            (currentTime - lastDictCallTime) < THROTTLE_INTERVAL_NSEC) {
            // Return cached result to reduce CPU usage
            return CFRetain(cachedDictResult);
        }
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Create a fallback dictionary if original function is NULL
            CFDictionaryRef originalDict = NULL;
            BOOL usingFallback = NO;
            
            if (original_CFCopySystemVersionDictionary) {
                originalDict = original_CFCopySystemVersionDictionary();
            } else {
                // Create a basic dictionary with current system version
                NSString *actualVersion = [[UIDevice currentDevice] systemVersion];
                CFStringRef versionKey = CFSTR("ProductVersion");
                CFStringRef buildKey = CFSTR("ProductBuildVersion");
                
                // Use a default build number based on version
                NSString *actualBuild = [NSString stringWithFormat:@"%@000", [actualVersion stringByReplacingOccurrencesOfString:@"." withString:@""]];
                
                CFStringRef versionValue = CFStringCreateWithCString(NULL, [actualVersion UTF8String], kCFStringEncodingUTF8);
                CFStringRef buildValue = CFStringCreateWithCString(NULL, [actualBuild UTF8String], kCFStringEncodingUTF8);
                
                CFMutableDictionaryRef fallbackDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                
                if (fallbackDict && versionValue && buildValue) {
                    CFDictionarySetValue(fallbackDict, versionKey, versionValue);
                    CFDictionarySetValue(fallbackDict, buildKey, buildValue);
                    
                    CFRelease(versionValue);
                    CFRelease(buildValue);
                    
                    originalDict = fallbackDict;
                    usingFallback = YES;
                    
                    IOSVERSION_LOG(@"📝 Created fallback dictionary for CFCopySystemVersionDictionary");
                }
            }
            
            if (!originalDict) {
                IOSVERSION_LOG(@"⚠️ Failed to get system version dictionary");
                return NULL;
            }
            
            // Get spoofed version info
            NSDictionary *versionInfo = getIOSVersionInfo();
            if (!versionInfo || !versionInfo[@"version"] || !versionInfo[@"build"]) {
                IOSVERSION_LOG(@"⚠️ Missing version info for CFCopySystemVersionDictionary");
                if (cachedDictResult != NULL) {
                    CFRelease(cachedDictResult);
                }
                cachedDictResult = CFRetain(originalDict);
                lastDictCallTime = currentTime;
                return originalDict;
            }
            
            NSString *spoofedVersion = versionInfo[@"version"];
            NSString *spoofedBuild = versionInfo[@"build"];
            
            // Log original values only occasionally to reduce overhead
            if (lastDictCallTime == 0 || (currentTime - lastDictCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                CFStringRef origVersionKey = CFSTR("ProductVersion");
                CFStringRef origBuildKey = CFSTR("ProductBuildVersion");
                CFStringRef origVersionValue = CFDictionaryGetValue(originalDict, origVersionKey);
                CFStringRef origBuildValue = CFDictionaryGetValue(originalDict, origBuildKey);
                
                if (origVersionValue && origBuildValue) {
                    IOSVERSION_LOG(@"🔍 CFCopySystemVersionDictionary original: version=%@ build=%@", 
                          (__bridge NSString *)origVersionValue,
                          (__bridge NSString *)origBuildValue);
                }
            }
            
            // Create mutable copy to modify
            CFMutableDictionaryRef mutableDict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, originalDict);
            if (!mutableDict) {
                IOSVERSION_LOG(@"⚠️ Failed to create mutable copy of system version dictionary");
                if (cachedDictResult != NULL) {
                    CFRelease(cachedDictResult);
                }
                cachedDictResult = CFRetain(originalDict);
                lastDictCallTime = currentTime;
                return originalDict;
            }
            
            // Update version and build number
            CFStringRef versionKey = CFSTR("ProductVersion");
            CFStringRef buildKey = CFSTR("ProductBuildVersion");
            
            CFStringRef versionValue = CFStringCreateWithCString(NULL, [spoofedVersion UTF8String], kCFStringEncodingUTF8);
            CFStringRef buildValue = CFStringCreateWithCString(NULL, [spoofedBuild UTF8String], kCFStringEncodingUTF8);
            
            if (versionValue) {
                CFDictionarySetValue(mutableDict, versionKey, versionValue);
                CFRelease(versionValue);
            }
            
            if (buildValue) {
                CFDictionarySetValue(mutableDict, buildKey, buildValue);
                CFRelease(buildValue);
            }
            
            // Log the newly set values only occasionally
            if (lastDictCallTime == 0 || (currentTime - lastDictCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                IOSVERSION_LOG(@"✅ CFCopySystemVersionDictionary spoofed: version=%@ build=%@", 
                      spoofedVersion, spoofedBuild);
            }
            
            // Release the original dictionary since we're returning a new one
            if (!usingFallback) {
                CFRelease(originalDict);
            }
            
            // Cache the result and update timestamp
            if (cachedDictResult != NULL) {
                CFRelease(cachedDictResult);
            }
            cachedDictResult = CFRetain(mutableDict);
            lastDictCallTime = currentTime;
            
            return mutableDict;
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in CFCopySystemVersionDictionary hook: %@", e);
    }
    
    // Call original function or return NULL if it's not available
    CFDictionaryRef result = original_CFCopySystemVersionDictionary ? original_CFCopySystemVersionDictionary() : NULL;
    
    // Update cache
    if (result) {
        if (cachedDictResult != NULL) {
            CFRelease(cachedDictResult);
        }
        cachedDictResult = CFRetain(result);
        lastDictCallTime = mach_absolute_time();
    }
    
    return result;
}

#pragma mark - sysctlbyname Hook

// Hook sysctlbyname to spoof iOS kernel version information
int hooked_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // Store last call time and cached result for the common kernel version calls
    static uint64_t lastOsVersionCallTime = 0;
    static char cachedBuildStr[32] = {0}; // Cache the build string
    static size_t cachedBuildStrLen = 0;
    
    // For kern.version - full Darwin kernel version string
    static uint64_t lastKernVersionCallTime = 0;
    static char cachedKernelVersionStr[256] = {0}; // Cache the kernel version string
    static size_t cachedKernelVersionStrLen = 0;
    
    @try {
        // Pre-cache version info only once
        static NSDictionary *cachedVersionInfo = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            cachedVersionInfo = getIOSVersionInfo();
            if (cachedVersionInfo) {
                // Extract build number and cache it
                NSString *buildNumber = cachedVersionInfo[@"build"];
                if (buildNumber) {
                    strlcpy(cachedBuildStr, [buildNumber UTF8String], sizeof(cachedBuildStr));
                    cachedBuildStrLen = strlen(cachedBuildStr) + 1; // +1 for null terminator
                }
                
                // Extract kernel version string and cache it
                NSString *kernelVersion = cachedVersionInfo[@"kernel_version"];
                if (kernelVersion) {
                    strlcpy(cachedKernelVersionStr, [kernelVersion UTF8String], sizeof(cachedKernelVersionStr));
                    cachedKernelVersionStrLen = strlen(cachedKernelVersionStr) + 1; // +1 for null terminator
                }
                
                IOSVERSION_LOG(@"🔄 Pre-cached version info: %@ (%@), kernel: %@", 
                      cachedVersionInfo[@"version"], 
                      cachedVersionInfo[@"build"],
                      cachedVersionInfo[@"kernel_version"]);
            } else {
                IOSVERSION_LOG(@"⚠️ Failed to pre-cache version info");
            }
        });

        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Check if this is a request for full kernel version string
            if (name && strcmp(name, "kern.version") == 0) {
                uint64_t currentTime = mach_absolute_time();
                
                // Ensure we have a valid cached kernel version string
                if (cachedKernelVersionStrLen == 0 && cachedVersionInfo && cachedVersionInfo[@"kernel_version"]) {
                    NSString *kernelVersion = cachedVersionInfo[@"kernel_version"];
                    strlcpy(cachedKernelVersionStr, [kernelVersion UTF8String], sizeof(cachedKernelVersionStr));
                    cachedKernelVersionStrLen = strlen(cachedKernelVersionStr) + 1;
                }
                
                // If we have a valid cached kernel version string
                if (cachedKernelVersionStrLen > 0) {
                    // Check if this is just a length query (oldp is NULL but oldlenp is not)
                    if (!oldp && oldlenp) {
                        *oldlenp = cachedKernelVersionStrLen;
                        
                        // Only log occasionally
                        if (lastKernVersionCallTime == 0 || (currentTime - lastKernVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"ℹ️ Returning required buffer size for kern.version: %zu", cachedKernelVersionStrLen);
                        }
                        
                        lastKernVersionCallTime = currentTime;
                        return 0;
                    }
                    
                    // Make sure we have enough space in the buffer and that both oldp and oldlenp are valid
                    if (oldp && oldlenp && *oldlenp >= cachedKernelVersionStrLen) {
                        memcpy(oldp, cachedKernelVersionStr, cachedKernelVersionStrLen);
                        *oldlenp = cachedKernelVersionStrLen;
                        
                        // Only log occasionally
                        if (lastKernVersionCallTime == 0 || (currentTime - lastKernVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"✅ Successfully spoofed kern.version to %s", cachedKernelVersionStr);
                        }
                        
                        lastKernVersionCallTime = currentTime;
                        return 0; // Success
                    } else if (oldlenp) {
                        // Not enough space, just set the required length
                        *oldlenp = cachedKernelVersionStrLen;
                        
                        // Only log occasionally
                        if (lastKernVersionCallTime == 0 || (currentTime - lastKernVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"⚠️ Buffer too small for kern.version (%zu < %zu)", *oldlenp, cachedKernelVersionStrLen);
                        }
                        
                        lastKernVersionCallTime = currentTime;
                        return 0; // Success (caller will need to provide a bigger buffer)
                    }
                } else {
                    IOSVERSION_LOG(@"❌ Missing cached kernel version string");
                }
            }
            // Check if this is a request for Darwin version number (kern.osrelease)
            else if (name && strcmp(name, "kern.osrelease") == 0 && cachedVersionInfo && cachedVersionInfo[@"darwin"]) {
                uint64_t currentTime = mach_absolute_time();
                
                // Get Darwin version (format: "21.6.0")
                NSString *darwinVersion = cachedVersionInfo[@"darwin"];
                if (darwinVersion) {
                    const char *darwinVersionStr = [darwinVersion UTF8String];
                    size_t darwinVersionLen = strlen(darwinVersionStr) + 1; // +1 for null terminator
                    
                    // Check if this is just a length query
                    if (!oldp && oldlenp) {
                        *oldlenp = darwinVersionLen;
                        return 0;
                    }
                    
                    // Copy the version if buffer is big enough
                    if (oldp && oldlenp && *oldlenp >= darwinVersionLen) {
                        memcpy(oldp, darwinVersionStr, darwinVersionLen);
                        *oldlenp = darwinVersionLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"✅ Successfully spoofed kern.osrelease to %s", darwinVersionStr);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0; // Success
                    } else if (oldlenp) {
                        // Not enough space, just set the required length
                        *oldlenp = darwinVersionLen;
                        return 0;
                    }
                }
            }
            // Check if this is a request for iOS version information
            else if (name && (strcmp(name, "kern.osversion") == 0)) {
                // Rate limiting - don't process too many calls
                uint64_t currentTime = mach_absolute_time();
                
                // Ensure we have a valid cached build string
                if (cachedBuildStrLen == 0 && cachedVersionInfo && cachedVersionInfo[@"build"]) {
                    NSString *buildNumber = cachedVersionInfo[@"build"];
                    strlcpy(cachedBuildStr, [buildNumber UTF8String], sizeof(cachedBuildStr));
                    cachedBuildStrLen = strlen(cachedBuildStr) + 1;
                }
                
                // Skip processing if we have a valid cached build and not enough time has passed
                if (cachedBuildStrLen > 0) {
                    // Check if this is just a length query (oldp is NULL but oldlenp is not)
                    if (!oldp && oldlenp) {
                        *oldlenp = cachedBuildStrLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"ℹ️ Returning required buffer size: %zu", cachedBuildStrLen);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0;
                    }
                    
                    // Make sure we have enough space in the buffer and that both oldp and oldlenp are valid
                    if (oldp && oldlenp && *oldlenp >= cachedBuildStrLen) {
                        memcpy(oldp, cachedBuildStr, cachedBuildStrLen);
                        *oldlenp = cachedBuildStrLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"✅ Successfully spoofed sysctlbyname to %s", cachedBuildStr);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0; // Success
                    } else if (oldlenp) {
                        // Not enough space, just set the required length
                        *oldlenp = cachedBuildStrLen;
                        
                        // Only log occasionally
                        if (lastOsVersionCallTime == 0 || (currentTime - lastOsVersionCallTime) > THROTTLE_INTERVAL_NSEC * 10) {
                            IOSVERSION_LOG(@"⚠️ Buffer too small for sysctlbyname (%zu < %zu)", *oldlenp, cachedBuildStrLen);
                        }
                        
                        lastOsVersionCallTime = currentTime;
                        return 0; // Success (caller will need to provide a bigger buffer)
                    }
                } else {
                    IOSVERSION_LOG(@"❌ Missing cached build number");
                }
            }
        }
    } @catch (NSException *e) {
        IOSVERSION_LOG(@"❌ Error in sysctlbyname hook: %@", e);
    }
    
    // Call the original function for all other cases
    return original_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

#pragma mark - Bundle Version Hooks

%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
    @try {
        NSString *bundleID = [self bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Handle system version info in Info.plist queries
            if ([key isEqualToString:@"MinimumOSVersion"] || 
                [key isEqualToString:@"DTPlatformVersion"] ||
                [key isEqualToString:@"DTSDKName"]) {
                
                NSString *spoofedVersion = getSpoofedSystemVersion();
                if (spoofedVersion) {
                    // For SDK and platform keys, add iOS prefix if needed
                    if ([key isEqualToString:@"DTPlatformVersion"] || 
                        [key isEqualToString:@"DTSDKName"]) {
                        if (![spoofedVersion hasPrefix:@"iOS"]) {
                            return [NSString stringWithFormat:@"iOS%@", spoofedVersion];
                        }
                        return spoofedVersion;
                    }
                    return spoofedVersion;
                }
            }
        }
    } @catch (NSException *e) {
        // Error handling
    }
    
    return %orig;
}

%end

// Original function pointer for CFBundleGetValueForInfoDictionaryKey
static CFTypeRef (*original_CFBundleGetValueForInfoDictionaryKey)(CFBundleRef bundle, CFStringRef key);

// Replacement function for CFBundleGetValueForInfoDictionaryKey
CFTypeRef replaced_CFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key) {
    @try {
        if (!bundle || !key) return NULL;
        
        // Get the bundle ID for CFBundle
        CFStringRef bundleID = CFBundleGetIdentifier(bundle);
        NSString *nsBundleID = bundleID ? (__bridge NSString*)bundleID : nil;
        
        if (shouldSpoofForBundle(nsBundleID)) {
            // Check for system version keys
            if (CFEqual(key, CFSTR("MinimumOSVersion")) || 
                CFEqual(key, CFSTR("DTPlatformVersion")) ||
                CFEqual(key, CFSTR("DTSDKName"))) {
                
                NSString *spoofedVersion = getSpoofedSystemVersion();
                if (spoofedVersion) {
                    // Log what we're spoofing
                    NSLog(@"[iosversion] 💉 Spoofing %@ for bundle %@ to %@", 
                          (__bridge NSString*)key, nsBundleID, spoofedVersion);
                    
                    // Create a CFString from our spoofed version
                    if (CFEqual(key, CFSTR("DTPlatformVersion")) || 
                        CFEqual(key, CFSTR("DTSDKName"))) {
                        
                        if (![spoofedVersion hasPrefix:@"iOS"]) {
                            NSString *prefixedVersion = [NSString stringWithFormat:@"iOS%@", spoofedVersion];
                            return CFStringCreateWithCString(NULL, [prefixedVersion UTF8String], kCFStringEncodingUTF8);
                        }
                    }
                    
                    return CFStringCreateWithCString(NULL, [spoofedVersion UTF8String], kCFStringEncodingUTF8);
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[iosversion] ❌ Error in CFBundleGetValueForInfoDictionaryKey hook: %@", e);
    }
    
    // Call original function if available, otherwise return NULL
    if (original_CFBundleGetValueForInfoDictionaryKey) {
        return original_CFBundleGetValueForInfoDictionaryKey(bundle, key);
    } else {
        // For some keys, provide default values
        if (key && (CFEqual(key, CFSTR("MinimumOSVersion")))) {
            // Return the current device's actual iOS version for MinimumOSVersion
            NSString *actualVersion = [[UIDevice currentDevice] systemVersion];
            return CFStringCreateWithCString(NULL, [actualVersion UTF8String], kCFStringEncodingUTF8);
        }
        
        NSLog(@"[iosversion] ℹ️ No original function for CFBundleGetValueForInfoDictionaryKey, returning NULL");
        return NULL;
    }
}

#pragma mark - Notification Handling

// Settings changed notification handler
static void settingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear cached decisions
    if (cachedBundleDecisions) {
        [cachedBundleDecisions removeAllObjects];
    }
    
    // Clear version cache
    versionCache = nil;
    lastVersionLoad = 0;
}

// Safe check if a bundle ID is a critical system process
static BOOL isCriticalSystemProcess(NSString *bundleID) {
    if (!bundleID) return YES; // Treat nil as critical for safety
    
    // Check against our critical system bundle IDs list
    if ([criticalSystemBundleIDs() containsObject:bundleID]) {
        // Allow spoofing for Safari and WebKit processes, even though they're in the critical list
        // This is necessary to spoof browser user agents
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"] ||
            [bundleID isEqualToString:@"com.apple.WebKit"] ||
            [bundleID isEqualToString:@"com.apple.WebKit.WebContent"] ||
            [bundleID isEqualToString:@"com.apple.WebKit.Networking"]) {
            return NO;
        }
        return YES;
    }
    
    // Check for system app prefixes
    if ([bundleID hasPrefix:@"com.apple."]) {
        // Allow spoofing for Safari and WebKit processes
        if ([bundleID isEqualToString:@"com.apple.mobilesafari"] ||
            [bundleID hasPrefix:@"com.apple.WebKit"]) {
            return NO;
        }
        return YES;
    }
    
    // Check for other known system bundle ID patterns
    if ([bundleID hasPrefix:@"com.hydra.projectx"] ||
        [bundleID isEqualToString:@"com.saurik.Cydia"] ||
        [bundleID isEqualToString:@"org.coolstar.SileoStore"] ||
        [bundleID isEqualToString:@"xyz.willy.Zebra"]) {
        return YES;
    }
    
    return NO;
}

#pragma mark - Constructor

// Cleanup function to be called on process termination
%dtor {
    // Free any retained CF objects to prevent memory leaks
    if (cachedDictResult != NULL) {
        CFRelease(cachedDictResult);
        cachedDictResult = NULL;
    }
    
    // Clear other caches
    cachedSystemVersionResult = nil;
    cachedBundleDecisions = nil;
    versionCache = nil;
}

%ctor {
    @autoreleasepool {
        // Get the bundle ID for scope checking
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Skip for system processes to avoid potential issues
        if (isCriticalSystemProcess(bundleID)) {
            return;
        }
        
        IOSVERSION_LOG(@"Initializing iOS Version Hooks for %@...", bundleID);
        
        // CRITICAL: Only install hooks if this app is actually scoped
        if (!isInScopedAppsList()) {
            // App is NOT scoped - no hooks, no interference, no crashes
            IOSVERSION_LOG(@"App %@ is not scoped, skipping iOS version hook installation", bundleID);
            return;
        }
        
        IOSVERSION_LOG(@"App %@ is scoped, installing iOS version hooks", bundleID);
        
        // Initialize caches
        cachedBundleDecisions = [NSMutableDictionary dictionary];
        versionCache = nil;
        
        // Register for settings change notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            settingsChanged,
            CFSTR("com.hydra.projectx.settings.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Register for iOS version-specific toggle notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            settingsChanged,
            CFSTR("com.hydra.projectx.toggleIOSVersionSpoof"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Register for profile change notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            settingsChanged,
            CFSTR("com.hydra.projectx.profileChanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Force ElleKit hooks to be applied regardless of environment detection
        // This is needed for rootless jailbreaks where EKIsElleKitEnv() might fail
        IOSVERSION_LOG(@"Setting up ElleKit hooks for build number spoofing");
        
        // Hook CoreFoundation version dictionary function
        void *cfFramework = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_NOW);
        if (cfFramework) {
            // Try several possible symbol names for CFCopySystemVersionDictionary
            const char *symbolNames[] = {
                "CFCopySystemVersionDictionary",
                "_CFCopySystemVersionDictionary",
                "__CFCopySystemVersionDictionary"
            };
            
            void *cfCopySystemVersionDictionaryPtr = NULL;
            for (int i = 0; i < 3; i++) {
                cfCopySystemVersionDictionaryPtr = dlsym(cfFramework, symbolNames[i]);
                if (cfCopySystemVersionDictionaryPtr) {
                    IOSVERSION_LOG(@"Found CoreFoundation symbol: %s", symbolNames[i]);
                    break;
                }
            }
            
            if (cfCopySystemVersionDictionaryPtr) {
                EKHook(cfCopySystemVersionDictionaryPtr, (void *)replaced_CFCopySystemVersionDictionary, (void **)&original_CFCopySystemVersionDictionary);
                IOSVERSION_LOG(@"Successfully hooked CFCopySystemVersionDictionary");
            } else {
                // If we can't find the symbol, create a stub implementation
                IOSVERSION_LOG(@"⚠️ Failed to find CFCopySystemVersionDictionary symbols, using fallback");
                
                // Set original function to NULL and handle it in the replacement function
                original_CFCopySystemVersionDictionary = NULL;
                IOSVERSION_LOG(@"Set original_CFCopySystemVersionDictionary to NULL, will use fallback in replacement function");
            }
            
            // Hook CFBundle info dictionary key function - try different symbol names
            const char *bundleSymbolNames[] = {
                "CFBundleGetValueForInfoDictionaryKey",
                "_CFBundleGetValueForInfoDictionaryKey",
                "__CFBundleGetValueForInfoDictionaryKey"
            };
            
            void *cfBundleGetValueForInfoDictionaryKeyPtr = NULL;
            for (int i = 0; i < 3; i++) {
                cfBundleGetValueForInfoDictionaryKeyPtr = dlsym(cfFramework, bundleSymbolNames[i]);
                if (cfBundleGetValueForInfoDictionaryKeyPtr) {
                    IOSVERSION_LOG(@"Found CFBundle symbol: %s", bundleSymbolNames[i]);
                    break;
                }
            }
            
            if (cfBundleGetValueForInfoDictionaryKeyPtr) {
                EKHook(cfBundleGetValueForInfoDictionaryKeyPtr, (void *)replaced_CFBundleGetValueForInfoDictionaryKey, (void **)&original_CFBundleGetValueForInfoDictionaryKey);
                IOSVERSION_LOG(@"Successfully hooked CFBundleGetValueForInfoDictionaryKey");
            } else {
                // If we can't find the symbol, create a stub implementation
                IOSVERSION_LOG(@"⚠️ Failed to find CFBundleGetValueForInfoDictionaryKey symbols, using fallback");
                
                // Set original function to NULL and handle it in the replacement function
                original_CFBundleGetValueForInfoDictionaryKey = NULL;
                IOSVERSION_LOG(@"Set original_CFBundleGetValueForInfoDictionaryKey to NULL, will use fallback in replacement function");
            }
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to open CoreFoundation framework");
        }
        
        // Hook sysctlbyname for kernel version checks
        void *libSystemHandle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW);
        if (libSystemHandle) {
            void *sysctlbynamePtr = dlsym(libSystemHandle, "sysctlbyname");
            if (sysctlbynamePtr) {
                EKHook(sysctlbynamePtr, (void *)hooked_sysctlbyname, (void **)&original_sysctlbyname);
                IOSVERSION_LOG(@"Hooked sysctlbyname");
            } else {
                IOSVERSION_LOG(@"⚠️ Failed to find sysctlbyname symbol");
            }
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to open libSystem.B.dylib");
        }
        
        // Set up hooks for direct file access methods to catch SystemVersion.plist reads
        IOSVERSION_LOG(@"Setting up hooks for direct file access methods");
        
        // Hook NSData dataWithContentsOfFile:
        Class NSDataClass = objc_getClass("NSData");
        SEL dataWithContentsOfFileSelector = @selector(dataWithContentsOfFile:);
        Method dataWithContentsOfFileMethod = class_getClassMethod(NSDataClass, dataWithContentsOfFileSelector);
        if (dataWithContentsOfFileMethod) {
            original_NSData_dataWithContentsOfFile = (NSData* (*)(Class, SEL, NSString *))method_getImplementation(dataWithContentsOfFileMethod);
            method_setImplementation(dataWithContentsOfFileMethod, (IMP)replaced_NSData_dataWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSData dataWithContentsOfFile:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSData dataWithContentsOfFile:");
        }
        
        // Hook NSDictionary dictionaryWithContentsOfFile:
        Class NSDictionaryClass = objc_getClass("NSDictionary");
        SEL dictWithContentsOfFileSelector = @selector(dictionaryWithContentsOfFile:);
        Method dictWithContentsOfFileMethod = class_getClassMethod(NSDictionaryClass, dictWithContentsOfFileSelector);
        if (dictWithContentsOfFileMethod) {
            original_NSDictionary_dictionaryWithContentsOfFile = (NSDictionary* (*)(Class, SEL, NSString *))method_getImplementation(dictWithContentsOfFileMethod);
            method_setImplementation(dictWithContentsOfFileMethod, (IMP)replaced_NSDictionary_dictionaryWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSDictionary dictionaryWithContentsOfFile:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSDictionary dictionaryWithContentsOfFile:");
        }
        
        // Hook NSString stringWithContentsOfFile:encoding:error:
        Class NSStringClass = objc_getClass("NSString");
        SEL stringWithContentsOfFileSelector = @selector(stringWithContentsOfFile:encoding:error:);
        Method stringWithContentsOfFileMethod = class_getClassMethod(NSStringClass, stringWithContentsOfFileSelector);
        if (stringWithContentsOfFileMethod) {
            original_NSString_stringWithContentsOfFile = (id (*)(Class, SEL, NSString *, NSStringEncoding, NSError **))method_getImplementation(stringWithContentsOfFileMethod);
            method_setImplementation(stringWithContentsOfFileMethod, (IMP)replaced_NSString_stringWithContentsOfFile);
            IOSVERSION_LOG(@"Hooked NSString stringWithContentsOfFile:encoding:error:");
        } else {
            IOSVERSION_LOG(@"⚠️ Failed to hook NSString stringWithContentsOfFile:encoding:error:");
        }
        
        // Initialize Objective-C hooks for scoped apps only
        %init;
        
        IOSVERSION_LOG(@"iOS Version Hooks successfully initialized for scoped app: %@", bundleID);
    }
}

#pragma mark - File Access Hooks for SystemVersion.plist

// Function to check if a path is a system version file
static BOOL isSystemVersionFile(NSString *path) {
    if (!path) return NO;
    
    // Normalize path before comparing
    path = [path stringByStandardizingPath];
    return [path isEqualToString:SYSTEM_VERSION_PATH] || 
           [path isEqualToString:ROOTLESS_SYSTEM_VERSION_PATH] ||
           [path hasSuffix:@"SystemVersion.plist"];
}

// Function to spoof a system version plist
static NSDictionary *spoofSystemVersionPlist(NSDictionary *originalPlist) {
    if (!originalPlist) return nil;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) return originalPlist;
    
    // Get our spoofed values
    NSDictionary *versionInfo = getIOSVersionInfo();
    if (!versionInfo || !versionInfo[@"version"] || !versionInfo[@"build"]) {
        return originalPlist;
    }
    
    // Make a copy with our spoofed values
    NSMutableDictionary *modifiedPlist = [originalPlist mutableCopy];
    
    // Modify the values we want to spoof
    [modifiedPlist setValue:versionInfo[@"version"] forKey:@"ProductVersion"];
    [modifiedPlist setValue:versionInfo[@"build"] forKey:@"ProductBuildVersion"];
    
    // Only log occasionally to reduce overhead
    static uint64_t lastPlistLogTime = 0;
    uint64_t currentTime = mach_absolute_time();
    if (lastPlistLogTime == 0 || (currentTime - lastPlistLogTime) > THROTTLE_INTERVAL_NSEC * 10) {
        IOSVERSION_LOG(@"📄 Spoofed SystemVersion.plist access: %@ → %@, %@ → %@",
              originalPlist[@"ProductVersion"], versionInfo[@"version"],
              originalPlist[@"ProductBuildVersion"], versionInfo[@"build"]);
        lastPlistLogTime = currentTime;
    }
    
    return modifiedPlist;
}

// Hook NSData dataWithContentsOfFile: to intercept SystemVersion.plist reads
NSData* replaced_NSData_dataWithContentsOfFile(Class self, SEL _cmd, NSString *path) {
    NSData *originalData = original_NSData_dataWithContentsOfFile(self, _cmd, path);
    
    if (isSystemVersionFile(path)) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // Get the plist as a dictionary from the data
            NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:originalData 
                                                                            options:0 
                                                                             format:NULL 
                                                                              error:NULL];
            if (plist) {
                // Spoof the values
                NSDictionary *spoofedPlist = spoofSystemVersionPlist(plist);
                
                // Convert back to data
                NSData *spoofedData = [NSPropertyListSerialization dataWithPropertyList:spoofedPlist
                                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                                options:0
                                                                                  error:NULL];
                if (spoofedData) {
                    return spoofedData;
                }
            }
        }
    }
    
    return originalData;
}

// Hook NSDictionary dictionaryWithContentsOfFile: to intercept SystemVersion.plist reads
NSDictionary* replaced_NSDictionary_dictionaryWithContentsOfFile(Class self, SEL _cmd, NSString *path) {
    NSDictionary *originalDict = original_NSDictionary_dictionaryWithContentsOfFile(self, _cmd, path);
    
    if (isSystemVersionFile(path) && originalDict) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            return spoofSystemVersionPlist(originalDict);
        }
    }
    
    return originalDict;
}

// Hook NSString stringWithContentsOfFile:encoding:error: to intercept text file reads
id replaced_NSString_stringWithContentsOfFile(Class self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    id originalString = original_NSString_stringWithContentsOfFile(self, _cmd, path, enc, error);
    
    if (isSystemVersionFile(path) && originalString) {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (shouldSpoofForBundle(bundleID)) {
            // For handling XML/plist files as raw strings
            NSDictionary *versionInfo = getIOSVersionInfo();
            if (versionInfo && versionInfo[@"version"] && versionInfo[@"build"]) {
                NSString *modifiedString = [originalString mutableCopy];
                modifiedString = [modifiedString stringByReplacingOccurrencesOfString:
                                      [NSString stringWithFormat:@"<key>ProductVersion</key>\\s*<string>[^<]+</string>"]
                                      withString:[NSString stringWithFormat:@"<key>ProductVersion</key><string>%@</string>", versionInfo[@"version"]]
                                      options:NSRegularExpressionSearch
                                      range:NSMakeRange(0, [modifiedString length])];
                                      
                modifiedString = [modifiedString stringByReplacingOccurrencesOfString:
                                      [NSString stringWithFormat:@"<key>ProductBuildVersion</key>\\s*<string>[^<]+</string>"]
                                      withString:[NSString stringWithFormat:@"<key>ProductBuildVersion</key><string>%@</string>", versionInfo[@"build"]]
                                      options:NSRegularExpressionSearch
                                      range:NSMakeRange(0, [modifiedString length])];
                                      
                return modifiedString;
            }
        }
    }
    
    return originalString;
} 
