#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "ProjectXLogging.h"
#import "WiFiManager.h"
#import "MethodSwizzler.h"
#import <ellekit/ellekit.h>
#import <Network/Network.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <net/if.h>

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// Forward declarations for private API methods
@interface NWPath (WeaponXPrivate)
- (NSString *)_getSSID;
- (id)_getBSSID;
- (NSInteger)quality;
- (double)latency;
- (id)gatherDiagnostics;
- (BOOL)isExpensive;
- (BOOL)isConstrained;
@end

@interface URLSessionTaskTransactionMetrics : NSObject
@property (nonatomic, readonly) NSURLRequest *request;
@property (nonatomic, readonly) NSURLResponse *response;
@property (nonatomic, readonly) NSDate *fetchStartDate;
@property (nonatomic, readonly) NSDate *domainLookupStartDate;
@property (nonatomic, readonly) NSDate *domainLookupEndDate;
@property (nonatomic, readonly) NSDate *connectStartDate;
@property (nonatomic, readonly) NSDate *connectEndDate;
@property (nonatomic, readonly) NSDate *secureConnectionStartDate;
@property (nonatomic, readonly) NSDate *secureConnectionEndDate;
@property (nonatomic, readonly) NSDate *requestStartDate;
@property (nonatomic, readonly) NSDate *requestEndDate;
@property (nonatomic, readonly) NSDate *responseStartDate;
@property (nonatomic, readonly) NSDate *responseEndDate;
@end

@interface URLSessionTaskMetrics : NSObject
@property (nonatomic, readonly) NSArray<URLSessionTaskTransactionMetrics *> *transactionMetrics;
@property (nonatomic, readonly) NSDate *taskInterval;
@property (nonatomic, readonly) int64_t countOfBytesReceived;
@property (nonatomic, readonly) int64_t countOfBytesSent;
@end

// MobileWiFi framework typedefs and functions (private API)
typedef struct __WiFiDeviceClient *WiFiDeviceClientRef;
typedef struct __WiFiNetwork *WiFiNetworkRef;
typedef struct __WiFiManager *WiFiManagerRef;

// Function pointers for the original functions we'll hook
static CFDictionaryRef (*orig_CNCopyCurrentNetworkInfo)(CFStringRef interfaceName);
static id (*orig_dictionaryWithScanResult)(id self, SEL _cmd, id arg1);

// MobileWiFi.framework function pointers
static WiFiManagerRef (*orig_WiFiManagerClientCreate)(CFAllocatorRef allocator, int flags);
static WiFiNetworkRef (*orig_WiFiDeviceClientCopyCurrentNetwork)(WiFiDeviceClientRef client);
static CFStringRef (*orig_WiFiNetworkGetSSID)(WiFiNetworkRef network);
static CFStringRef (*orig_WiFiNetworkGetBSSID)(WiFiNetworkRef network);

// Cache of WiFi info from the most recent successful lookup
static NSMutableDictionary *cachedWifiInfo = nil;
static NSString *cachedProfileId = nil;
static NSDate *cacheTimestamp = nil;
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes in seconds

// Forward declarations
static NSString *getCurrentBundleID(void);
static NSDictionary *loadScopedApps(void);
static BOOL isInScopedAppsList(void);

#pragma mark - Profile Detection Helpers

// Helper function to check if we should spoof for this bundle ID (with caching)
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

// Helper function to directly get current profile ID from plist
static NSString *getCurrentProfileID(void) {
    // Direct access to the current profile info plist
    NSString *centralInfoPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
    
    NSString *profileId = centralInfo[@"ProfileId"];
    if (profileId) {
        return profileId;
    }
    
    // Fallback to legacy location if needed
    NSString *legacyInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
    NSDictionary *legacyInfo = [NSDictionary dictionaryWithContentsOfFile:legacyInfoPath];
    profileId = legacyInfo[@"ProfileId"];
    
    if (profileId) {
        return profileId;
    }
    
    // Last resort - scan for profiles
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *profilesDir = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
    NSError *error = nil;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:profilesDir error:&error];
    
    if (!error && contents.count > 0) {
        // Find the first numeric directory
        for (NSString *item in contents) {
            if ([item isEqualToString:@"profiles.plist"] || 
                [item isEqualToString:@"current_profile_info.plist"]) {
                continue;
            }
            
            BOOL isDir = NO;
            NSString *fullPath = [profilesDir stringByAppendingPathComponent:item];
            [fileManager fileExistsAtPath:fullPath isDirectory:&isDir];
            
            if (isDir) {
                profileId = item;
                break;
            }
        }
    }
    
    return profileId ?: @"default";
}

// Get current WiFi info from appropriate profile
static NSDictionary *getProfileWiFiInfo(void) {
    // Skip cache if it's more than 5 minutes old
    BOOL shouldRefresh = NO;
    if (!cacheTimestamp || [[NSDate date] timeIntervalSinceDate:cacheTimestamp] > kCacheValidityDuration) {
        shouldRefresh = YES;
    }
    
    // Get current profile ID (use cache if available)
    NSString *profileId = cachedProfileId;
    if (!profileId || shouldRefresh) {
        profileId = getCurrentProfileID();
        cachedProfileId = profileId;
        cacheTimestamp = [NSDate date];
    }
    
    if (!profileId) {
        return nil;
    }
    
    // If cache is valid and we have WiFi info, return it
    if (!shouldRefresh && cachedWifiInfo && cachedWifiInfo[@"ssid"] && cachedWifiInfo[@"bssid"]) {
        return cachedWifiInfo;
    }
    
    // Build path to WiFi info file in profile directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    NSString *wifiInfoPath = [identityDir stringByAppendingPathComponent:@"wifi_info.plist"];
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    
    // First try wifi_info.plist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:wifiInfoPath]) {
        NSDictionary *wifiInfo = [NSDictionary dictionaryWithContentsOfFile:wifiInfoPath];
        if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
            return wifiInfo;
        }
    }
    
    // Then try device_ids.plist
    if ([fileManager fileExistsAtPath:deviceIdsPath]) {
        NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
        if (deviceIds[@"SSID"] && deviceIds[@"BSSID"]) {
            NSMutableDictionary *wifiInfo = [NSMutableDictionary dictionary];
            wifiInfo[@"ssid"] = deviceIds[@"SSID"];
            wifiInfo[@"bssid"] = deviceIds[@"BSSID"];
            wifiInfo[@"networkType"] = @"Infrastructure";
            
            return wifiInfo;
        }
        
        // If WiFi value is stored as a formatted string
        NSString *wifiValue = deviceIds[@"WiFi"];
        if (wifiValue && [wifiValue containsString:@"("]) {
            NSRange openParenRange = [wifiValue rangeOfString:@"("];
            NSRange closeParenRange = [wifiValue rangeOfString:@")"];
            
            if (openParenRange.location != NSNotFound && closeParenRange.location != NSNotFound) {
                NSString *ssid = [wifiValue substringToIndex:openParenRange.location - 1];
                NSString *bssid = [wifiValue substringWithRange:NSMakeRange(openParenRange.location + 1, 
                                                                closeParenRange.location - openParenRange.location - 1)];
                
                NSMutableDictionary *wifiInfo = [NSMutableDictionary dictionary];
                wifiInfo[@"ssid"] = ssid;
                wifiInfo[@"bssid"] = bssid;
                wifiInfo[@"networkType"] = @"Infrastructure";
                
                return wifiInfo;
            }
        }
    }
    
    // Fallback - try to get from WiFiManager if available
    if (NSClassFromString(@"WiFiManager")) {
        id wifiManager = [NSClassFromString(@"WiFiManager") sharedManager];
        if ([wifiManager respondsToSelector:@selector(currentWiFiInfo)]) {
            NSDictionary *wifiInfo = [wifiManager currentWiFiInfo];
            if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
                return wifiInfo;
            }
        }
        
        // Generate new info if needed
        if ([wifiManager respondsToSelector:@selector(generateWiFiInfo)]) {
            NSDictionary *wifiInfo = [wifiManager generateWiFiInfo];
            if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
                // Save it to the profile for future use
                if ([fileManager fileExistsAtPath:identityDir] || 
                    [fileManager createDirectoryAtPath:identityDir withIntermediateDirectories:YES attributes:nil error:nil]) {
                    [wifiInfo writeToFile:wifiInfoPath atomically:YES];
                    
                    // Also update device_ids.plist
                    NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath];
                    if (!deviceIds) deviceIds = [NSMutableDictionary dictionary];
                    deviceIds[@"SSID"] = wifiInfo[@"ssid"];
                    deviceIds[@"BSSID"] = wifiInfo[@"bssid"];
                    deviceIds[@"WiFi"] = [NSString stringWithFormat:@"%@ (%@)", wifiInfo[@"ssid"], wifiInfo[@"bssid"]];
                    [deviceIds writeToFile:deviceIdsPath atomically:YES];
                }
                
                return wifiInfo;
            }
        }
    }
    
    // Return nil if all methods failed
    return nil;
}

#pragma mark - Core Hook Functions

// Implementation of CNCopyCurrentNetworkInfo hook
static CFDictionaryRef replaced_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    // Get the original result first
    CFDictionaryRef originalDict = orig_CNCopyCurrentNetworkInfo ? orig_CNCopyCurrentNetworkInfo(interfaceName) : NULL;
    
    @try {
        // Get the bundle ID for scope checking
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Check if we should spoof for this bundle
        if (!shouldSpoofForBundle(bundleID)) {
            return originalDict;
        }
        
        // Try to use cached info first
        if (cachedWifiInfo && cachedWifiInfo[@"ssid"] && cachedWifiInfo[@"bssid"]) {
            NSMutableDictionary *spoofedInfo = [NSMutableDictionary dictionary];
            spoofedInfo[@"SSID"] = cachedWifiInfo[@"ssid"];
            spoofedInfo[@"BSSID"] = cachedWifiInfo[@"bssid"];
            spoofedInfo[@"NetworkType"] = cachedWifiInfo[@"networkType"] ?: @"Infrastructure";
            
            return CFBridgingRetain(spoofedInfo);
        }
        
        // Get WiFi info from profile
        NSDictionary *wifiInfo = getProfileWiFiInfo();
        if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
            // Update cache
            if (!cachedWifiInfo) {
                cachedWifiInfo = [NSMutableDictionary dictionary];
            }
            [cachedWifiInfo setDictionary:wifiInfo];
            
            // Create spoofed dictionary
            NSMutableDictionary *spoofedInfo = [NSMutableDictionary dictionary];
            spoofedInfo[@"SSID"] = wifiInfo[@"ssid"];
            spoofedInfo[@"BSSID"] = wifiInfo[@"bssid"];
            spoofedInfo[@"NetworkType"] = wifiInfo[@"networkType"] ?: @"Infrastructure";
            
            return CFBridgingRetain(spoofedInfo);
        }
    } @catch (NSException *exception) {
        // Silent exception handling
    }
    
    // Return original if spoofing failed
    return originalDict;
}

// Implementation of NEHotspotHelper dictionaryWithScanResult: hook
static id replaced_dictionaryWithScanResult(id self, SEL _cmd, id arg1) {
    // Call original first
    id originalResult = nil;
    if (orig_dictionaryWithScanResult) {
        originalResult = orig_dictionaryWithScanResult(self, _cmd, arg1);
    }
    
    @try {
        // Get bundle ID for scope checking
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Check if we should spoof
        if (!shouldSpoofForBundle(bundleID)) {
            return originalResult;
        }
        
        // Ensure we have a valid dictionary to work with
        if (!originalResult || ![originalResult isKindOfClass:[NSDictionary class]]) {
            return originalResult;
        }
        
        // Create mutable copy for modification
        NSMutableDictionary *modifiedResult = [NSMutableDictionary dictionaryWithDictionary:originalResult];
        
        // Try to use cached info first
        if (cachedWifiInfo && cachedWifiInfo[@"ssid"] && cachedWifiInfo[@"bssid"]) {
            modifiedResult[@"SSID"] = cachedWifiInfo[@"ssid"];
            modifiedResult[@"BSSID"] = cachedWifiInfo[@"bssid"];
            
            // Add WiFi standard information if available from cached info
            if (cachedWifiInfo[@"wifiStandard"]) {
                NSString *standard = cachedWifiInfo[@"wifiStandard"];
                if ([standard containsString:@"ax"]) {
                    modifiedResult[@"WifiStandard"] = @6; // 802.11ax
                } else if ([standard containsString:@"ac"]) {
                    modifiedResult[@"WifiStandard"] = @5; // 802.11ac
                } else if ([standard containsString:@"n"]) {
                    modifiedResult[@"WifiStandard"] = @4; // 802.11n
                }
            }
            
            return modifiedResult;
        }
        
        // Get WiFi info from profile
        NSDictionary *wifiInfo = getProfileWiFiInfo();
        if (wifiInfo && wifiInfo[@"ssid"] && wifiInfo[@"bssid"]) {
            // Update cache
            if (!cachedWifiInfo) {
                cachedWifiInfo = [NSMutableDictionary dictionary];
            }
            [cachedWifiInfo setDictionary:wifiInfo];
            
            // Modify result
            modifiedResult[@"SSID"] = wifiInfo[@"ssid"];
            modifiedResult[@"BSSID"] = wifiInfo[@"bssid"];
            
            return modifiedResult;
        }
    } @catch (NSException *exception) {
        // Silent exception handling
    }
    
    // Return original if spoofing failed
    return originalResult;
}

#pragma mark - Swizzle Implementations for NEHotspotNetwork

// Swizzle replacements for NEHotspotNetwork
@implementation NEHotspotNetwork (WeaponXHooks)

- (NSString *)weaponx_SSID {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return [self weaponx_SSID]; // Call original
    }
    
    // Try to use cached info first
    if (cachedWifiInfo && cachedWifiInfo[@"ssid"]) {
        return cachedWifiInfo[@"ssid"];
    }
    
    // Get WiFi info from profile
    NSDictionary *wifiInfo = getProfileWiFiInfo();
    if (wifiInfo && wifiInfo[@"ssid"]) {
        // Update cache
        if (!cachedWifiInfo) {
            cachedWifiInfo = [NSMutableDictionary dictionary];
        }
        [cachedWifiInfo setDictionary:wifiInfo];
        
        return wifiInfo[@"ssid"];
    }
    
    // Call original as fallback
    return [self weaponx_SSID];
}

- (NSString *)weaponx_BSSID {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return [self weaponx_BSSID]; // Call original
    }
    
    // Try to use cached info first
    if (cachedWifiInfo && cachedWifiInfo[@"bssid"]) {
        return cachedWifiInfo[@"bssid"];
    }
    
    // Get WiFi info from profile
    NSDictionary *wifiInfo = getProfileWiFiInfo();
    if (wifiInfo && wifiInfo[@"bssid"]) {
        // Update cache
        if (!cachedWifiInfo) {
            cachedWifiInfo = [NSMutableDictionary dictionary];
        }
        [cachedWifiInfo setDictionary:wifiInfo];
        
        return wifiInfo[@"bssid"];
    }
    
    // Call original as fallback
    return [self weaponx_BSSID];
}

// Additional NEHotspotNetwork property hook for signal strength
- (NSNumber *)weaponx_signalStrength {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return [self weaponx_signalStrength]; // Call original
    }
    
    // Return a realistic signal strength (0.7-0.9 range for good strength)
    double strength = 0.7 + ((double)arc4random_uniform(20) / 100.0);
    return @(strength);
}

// Additional NEHotspotNetwork property hook for secure flag
- (BOOL)weaponx_secure {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return [self weaponx_secure]; // Call original
    }
    
    // Most networks are secure, so default to YES (true)
    return YES;
}

@end

#pragma mark - MobileWiFi Framework Hooks

// Hook implementation for WiFiManagerClientCreate
static WiFiManagerRef replaced_WiFiManagerClientCreate(CFAllocatorRef allocator, int flags) {
    // Call original implementation
    WiFiManagerRef result = orig_WiFiManagerClientCreate(allocator, flags);
    return result;
}

// Hook implementation for WiFiDeviceClientCopyCurrentNetwork
static WiFiNetworkRef replaced_WiFiDeviceClientCopyCurrentNetwork(WiFiDeviceClientRef client) {
    // Call original implementation
    WiFiNetworkRef result = orig_WiFiDeviceClientCopyCurrentNetwork(client);
    return result;
}

// Hook implementation for WiFiNetworkGetSSID
static CFStringRef replaced_WiFiNetworkGetSSID(WiFiNetworkRef network) {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return orig_WiFiNetworkGetSSID(network);
    }
    
    // Try to use cached info first
    if (cachedWifiInfo && cachedWifiInfo[@"ssid"]) {
        return (__bridge CFStringRef)cachedWifiInfo[@"ssid"];
    }
    
    // Get WiFi info from profile
    NSDictionary *wifiInfo = getProfileWiFiInfo();
    if (wifiInfo && wifiInfo[@"ssid"]) {
        // Update cache
        if (!cachedWifiInfo) {
            cachedWifiInfo = [NSMutableDictionary dictionary];
        }
        [cachedWifiInfo setDictionary:wifiInfo];
        
        return (__bridge CFStringRef)wifiInfo[@"ssid"];
    }
    
    // Call original as fallback
    return orig_WiFiNetworkGetSSID(network);
}

// Hook implementation for WiFiNetworkGetBSSID
static CFStringRef replaced_WiFiNetworkGetBSSID(WiFiNetworkRef network) {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return orig_WiFiNetworkGetBSSID(network);
    }
    
    // Try to use cached info first
    if (cachedWifiInfo && cachedWifiInfo[@"bssid"]) {
        return (__bridge CFStringRef)cachedWifiInfo[@"bssid"];
    }
    
    // Get WiFi info from profile
    NSDictionary *wifiInfo = getProfileWiFiInfo();
    if (wifiInfo && wifiInfo[@"bssid"]) {
        // Update cache
        if (!cachedWifiInfo) {
            cachedWifiInfo = [NSMutableDictionary dictionary];
        }
        [cachedWifiInfo setDictionary:wifiInfo];
        
        return (__bridge CFStringRef)wifiInfo[@"bssid"];
    }
    
    // Call original as fallback
    return orig_WiFiNetworkGetBSSID(network);
}

#pragma mark - Hook Installation

static void initializeHooks(void) {
    // Install CNCopyCurrentNetworkInfo hook using ellekit
    void *symbol = dlsym(RTLD_DEFAULT, "CNCopyCurrentNetworkInfo");
    if (symbol) {
        int result = EKHook(symbol, 
                           (void *)replaced_CNCopyCurrentNetworkInfo, 
                           (void **)&orig_CNCopyCurrentNetworkInfo);
        
        if (result != 0) {
            // Try to find the symbol in the framework
            void *captiveNetworkLib = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW);
            if (captiveNetworkLib) {
                symbol = dlsym(captiveNetworkLib, "CNCopyCurrentNetworkInfo");
                if (symbol) {
                    EKHook(symbol, 
                          (void *)replaced_CNCopyCurrentNetworkInfo, 
                          (void **)&orig_CNCopyCurrentNetworkInfo);
                }
                dlclose(captiveNetworkLib);
            }
        }
    }
    
    // Install NEHotspotHelper hook using method swizzling
    Class neHotspotHelperClass = NSClassFromString(@"NEHotspotHelper");
    if (neHotspotHelperClass) {
        Method dictionaryMethod = class_getClassMethod(neHotspotHelperClass, @selector(dictionaryWithScanResult:));
        if (dictionaryMethod) {
            orig_dictionaryWithScanResult = (id (*)(id, SEL, id))method_getImplementation(dictionaryMethod);
            method_setImplementation(dictionaryMethod, (IMP)replaced_dictionaryWithScanResult);
        }
    }
    
    // Install NEHotspotNetwork swizzles
    Class neHotspotNetworkClass = NSClassFromString(@"NEHotspotNetwork");
    if (neHotspotNetworkClass) {
        [MethodSwizzler swizzleClass:neHotspotNetworkClass 
                   originalSelector:@selector(SSID) 
                   swizzledSelector:@selector(weaponx_SSID)];
        
        [MethodSwizzler swizzleClass:neHotspotNetworkClass 
                   originalSelector:@selector(BSSID) 
                   swizzledSelector:@selector(weaponx_BSSID)];
        
        // Add additional property swizzles
        [MethodSwizzler swizzleClass:neHotspotNetworkClass 
                   originalSelector:@selector(signalStrength) 
                   swizzledSelector:@selector(weaponx_signalStrength)];
                   
        [MethodSwizzler swizzleClass:neHotspotNetworkClass 
                   originalSelector:@selector(secure) 
                   swizzledSelector:@selector(weaponx_secure)];
    }
    
    // Install MobileWiFi framework hooks
    void *mobileWiFiLib = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_NOW);
    if (mobileWiFiLib) {
        // Hook WiFiManagerClientCreate
        symbol = dlsym(mobileWiFiLib, "WiFiManagerClientCreate");
        if (symbol) {
            EKHook(symbol, 
                  (void *)replaced_WiFiManagerClientCreate, 
                  (void **)&orig_WiFiManagerClientCreate);
        }
        
        // Hook WiFiDeviceClientCopyCurrentNetwork
        symbol = dlsym(mobileWiFiLib, "WiFiDeviceClientCopyCurrentNetwork");
        if (symbol) {
            EKHook(symbol, 
                  (void *)replaced_WiFiDeviceClientCopyCurrentNetwork, 
                  (void **)&orig_WiFiDeviceClientCopyCurrentNetwork);
        }
        
        // Hook WiFiNetworkGetSSID
        symbol = dlsym(mobileWiFiLib, "WiFiNetworkGetSSID");
        if (symbol) {
            EKHook(symbol, 
                  (void *)replaced_WiFiNetworkGetSSID, 
                  (void **)&orig_WiFiNetworkGetSSID);
        }
        
        // Hook WiFiNetworkGetBSSID
        symbol = dlsym(mobileWiFiLib, "WiFiNetworkGetBSSID");
        if (symbol) {
            EKHook(symbol, 
                  (void *)replaced_WiFiNetworkGetBSSID, 
                  (void **)&orig_WiFiNetworkGetBSSID);
        }
        
        dlclose(mobileWiFiLib);
    }
}

#pragma mark - Notification Handlers

static void settingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    PXLog(@"[WeaponX] Received settings notification: %@", notificationName);
    
    // Clear cached info to force refresh
    if (cachedWifiInfo) {
        [cachedWifiInfo removeAllObjects];
    }
    
    // Also reset profile ID cache to ensure we get the latest
    cachedProfileId = nil;
    cacheTimestamp = nil;
}

#pragma mark - NWPathMonitor Hooks (Network Framework)

// Hook for NWPath methods
%hook NWPath

- (BOOL)usesInterfaceType:(NSInteger)type {
    // We don't modify this as it would break connectivity detection
    return %orig;
}

- (NSString *)_getSSID {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return %orig;
    }
    
    // Return spoofed SSID if available
    NSDictionary *wifiInfo = getProfileWiFiInfo();
    if (wifiInfo && wifiInfo[@"ssid"]) {
        return wifiInfo[@"ssid"];
    }
    
    // Fallback to original if no spoofed data
    return %orig;
}

- (id)_getBSSID {
    // Check if we should spoof
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!shouldSpoofForBundle(bundleID)) {
        return %orig;
    }
    
    // Return spoofed BSSID if available
    NSDictionary *wifiInfo = getProfileWiFiInfo();
    if (wifiInfo && wifiInfo[@"bssid"]) {
        return wifiInfo[@"bssid"];
    }
    
    // Fallback to original if no spoofed data
    return %orig;
}

- (NSInteger)quality {
    return %orig;
}

- (double)latency {
    return %orig;
}

- (BOOL)isExpensive {
    return %orig;
}

- (BOOL)isConstrained {
    return %orig;
}

- (id)gatherDiagnostics {
    return %orig;
}

%end

// Hook NWPathMonitor class
%hook NWPathMonitor

- (void)setPathUpdateHandler:(void (^)(id path))handler {
    if (handler) {
        // Create a wrapper that can modify the path if needed
        void (^newHandler)(id path) = ^(id path) {
            // Original handler still needs to be called with the path
            // We're not modifying it here as the path itself is hooked separately
            handler(path);
        };
        %orig(newHandler);
    } else {
        %orig;
    }
}

- (id)currentPath {
    // The path object itself is hooked via the NWPath hook above
    return %orig;
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        @try {
            PXLog(@"[WiFiHook] Initializing WiFi hooks");
            
            // Get the bundle ID for scope checking
            NSString *bundleID = getCurrentBundleID();
            
            // Skip if we can't get bundle ID
            if (!bundleID || [bundleID length] == 0) {
                return;
            }
            
            // Skip if this is a system process (except allowed ones)
            if ([bundleID hasPrefix:@"com.apple."] && 
                ![bundleID isEqualToString:@"com.apple.mobilesafari"] &&
                ![bundleID isEqualToString:@"com.apple.webapp"]) {
                PXLog(@"[WiFiHook] Not hooking system process: %@", bundleID);
                return;
            }
            
            // Skip our own apps
            if ([bundleID isEqualToString:@"com.hydra.projectx"] || 
                [bundleID isEqualToString:@"com.hydra.weaponx"]) {
                PXLog(@"[WiFiHook] Not hooking own app: %@", bundleID);
                return;
            }
            
            // CRITICAL: Only install hooks if this app is actually scoped
            if (!isInScopedAppsList()) {
                // App is NOT scoped - no hooks, no interference, no crashes
                PXLog(@"[WiFiHook] App %@ is not scoped, skipping hook installation", bundleID);
                return;
            }
            
            PXLog(@"[WiFiHook] App %@ is scoped, setting up WiFi hooks", bundleID);
            
            // Initialize cache dictionaries
            cachedBundleDecisions = [NSMutableDictionary dictionary];
            
            // Initialize hooks
            initializeHooks();
            
            // Initialize Objective-C hooks for scoped apps only
            %init;
            
            // Register for settings change notifications
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                settingsChanged,
                CFSTR("com.hydra.projectx.settings.changed"),
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );
            
            // Also register for WiFi-specific toggle notifications
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                settingsChanged,
                CFSTR("com.hydra.projectx.toggleWifiSpoof"),
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
            
            PXLog(@"[WiFiHook] WiFi hooks successfully initialized for scoped app: %@", bundleID);
            
        } @catch (NSException *e) {
            PXLog(@"[WiFiHook] ❌ Exception in constructor: %@", e);
        }
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
                PXLog(@"[WiFiHook] Could not find scoped apps file");
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