#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIKit.h>
#import "ProjectXLogging.h"
#import <objc/runtime.h>
#import <ellekit/ellekit.h>
#import <netinet/in.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import "NetworkManager.h"

// Constants for connection types
typedef NS_ENUM(NSInteger, NetworkConnectionType) {
    NetworkConnectionTypeAuto = 0,
    NetworkConnectionTypeWiFi = 1,
    NetworkConnectionTypeCellular = 2,
    NetworkConnectionTypeNone = 3
};

// Path to security settings plist
static NSString *const kSecuritySettingsPath = @"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist";

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Cache for quick lookup
static NSInteger cachedConnectionType = -1;
static BOOL cachedNetworkDataSpoofEnabled = NO;
static NSDate *cacheTimestamp = nil;
static const NSTimeInterval kCacheValidDuration = 5.0; // 5 seconds

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 30.0; // 30 seconds

// Shared fake cellular carrier for consistent spoofing
static NSString *const kFakeCarrierName = @"ProjectX";
static NSString *const kFakeMobileCountryCode = @"310";
static NSString *const kFakeMobileNetworkCode = @"260";

// Cache for ISO country code
static NSString *cachedISOCountryCode = nil;
static NSDate *isoCountryCodeCacheTimestamp = nil;
static const NSTimeInterval kISOCountryCodeCacheValidDuration = 60.0; // 60 seconds

// Fake WiFi SSID
static NSString *const kFakeWiFiSSID = @"ProjectX_WiFi";
static NSString *const kFakeBSSID = @"00:11:22:33:44:55";

// Cache for carrier details
static NSString *cachedCarrierName = nil;
static NSString *cachedMobileCountryCode = nil;
static NSString *cachedMobileNetworkCode = nil;
static NSDate *carrierDetailsCacheTimestamp = nil;
static const NSTimeInterval kCarrierDetailsCacheValidDuration = 60.0; // 60 seconds

// Constants for signal strength
static const int kWiFiSignalStrengthExcellent = -45;  // -45 dBm (Excellent)
static const int kWiFiSignalStrengthGood = -60;       // -60 dBm (Good)
static const int kWiFiSignalStrengthFair = -70;       // -70 dBm (Fair)
static const int kWiFiSignalStrengthPoor = -80;       // -80 dBm (Poor)

// Keep track of current signal values for realistic gradual changes
static int currentWiFiSignalStrength = -65;  // Start with a reasonable default
static int currentCellularSignalBars = 4;    // Start with good signal
static NSDate *lastSignalUpdateTime = nil;

// Cellular network type constants (4G/5G)
static NSString *const kCellularNetworkType4G = @"CTRadioAccessTechnologyLTE";
static NSString *const kCellularNetworkType5G = @"CTRadioAccessTechnologyNR";  // iOS 15+ 5G
static NSString *const kCellularNetworkType5GNSA = @"CTRadioAccessTechnologyNRNSA"; // 5G Non-Standalone

// Current cellular network type (changes over time)
static NSString *currentCellularNetworkType = nil;
static NSDate *lastNetworkTypeChangeTime = nil;
static const NSTimeInterval kMinNetworkTypeChangeDuration = 120.0; // Minimum 2 minutes between technology changes

#pragma mark - Helper Functions

// Get the current bundle ID
static NSString *getCurrentBundleID() {
    NSBundle *mainBundle = [NSBundle mainBundle];
    if (!mainBundle) {
        return nil;
    }
    
    NSString *bundleID = [mainBundle bundleIdentifier];
    return bundleID;
}

// Get the current ISO country code from security settings
static NSString *getCurrentISOCountryCode() {
    // Check cache validity
    if (cachedISOCountryCode && isoCountryCodeCacheTimestamp && 
        [[NSDate date] timeIntervalSinceDate:isoCountryCodeCacheTimestamp] < kISOCountryCodeCacheValidDuration) {
        return cachedISOCountryCode;
    }
    
    // Read from security settings
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:kSecuritySettingsPath];
    NSString *isoCode = [settings objectForKey:@"networkISOCountryCode"];
    
    // Use default if not set
    if (!isoCode) {
        isoCode = @"us";
    }
    
    // Update cache
    cachedISOCountryCode = isoCode;
    isoCountryCodeCacheTimestamp = [NSDate date];
    
    PXLog(@"[NetworkHook] Read ISO country code: %@", isoCode);
    return isoCode;
}

// Get the path to the current profile's identity directory
static NSString *getProfileIdentityPath() {
    // Get current profile ID
    NSString *profileId = nil;
    NSString *centralInfoPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
    
    profileId = centralInfo[@"ProfileId"];
    if (!profileId) {
        // If not found, check the legacy active_profile_info.plist
        NSString *activeInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
        NSDictionary *activeInfo = [NSDictionary dictionaryWithContentsOfFile:activeInfoPath];
        profileId = activeInfo[@"ProfileId"];
    }
    
    if (!profileId) {
        // Fallback approach: try to find any profile directory
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *profilesDir = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        NSError *error = nil;
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:profilesDir error:&error];
        
        if (!error && contents.count > 0) {
            // Use the first directory found as a fallback
            for (NSString *item in contents) {
                BOOL isDir = NO;
                NSString *fullPath = [profilesDir stringByAppendingPathComponent:item];
                [fileManager fileExistsAtPath:fullPath isDirectory:&isDir];
                
                if (isDir) {
                    profileId = item;
                    break;
                }
            }
        }
        
        if (!profileId) {
            return nil;
        }
    }
    
    // Build the path to this profile's identity directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    
    return identityDir;
}

// Get the local IP address from the current profile
static NSString *getProfileLocalIPAddress() {
    NSString *identityDir = getProfileIdentityPath();
    if (!identityDir) {
        return @"192.168.1.1"; // Default fallback
    }
    
    // Try to read from network_settings.plist
    NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
    NSDictionary *networkDict = [NSDictionary dictionaryWithContentsOfFile:networkPath];
    
    NSString *localIP = networkDict[@"localIPAddress"];
    
    // If not found in dedicated file, try the combined device_ids.plist
    if (!localIP) {
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
        localIP = deviceIds[@"LocalIPAddress"];
    }
    
    // If still not found, return default IP
    if (!localIP) {
        localIP = @"192.168.1.1";
    }
    
    return localIP;
}

// Get the current local IP address from the system
static NSString * __attribute__((unused)) getCurrentLocalIPAddress() {
    NSString *address = @"192.168.1.1"; // Default fallback
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    // Retrieve the current interfaces - returns 0 on success
    if (getifaddrs(&interfaces) == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on iOS
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}

// Load scoped apps from the plist file
static NSDictionary *loadScopedApps() {
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
        PXLog(@"[NetworkHook] Could not find scoped apps file at any of the expected locations");
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache;
    }
    
    // Load the plist file
    NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:validPath];
    if (!plistDict) {
        PXLog(@"[NetworkHook] Failed to load scoped apps plist from %@", validPath);
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache;
    }
    
    // Get the scoped apps dictionary
    NSDictionary *scopedApps = plistDict[@"ScopedApps"];
    if (!scopedApps) {
        PXLog(@"[NetworkHook] No ScopedApps key found in plist %@", validPath);
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache;
    }
    
    // Copy the scoped apps to our cache
    [scopedAppsCache addEntriesFromDictionary:scopedApps];
    scopedAppsCacheTimestamp = [NSDate date];
    
    PXLog(@"[NetworkHook] Loaded %lu scoped apps from %@", (unsigned long)scopedAppsCache.count, validPath);
    return scopedAppsCache;
}

// Check if the current app is in the scoped apps list
static BOOL isInScopedAppsList() {
    NSString *bundleID = getCurrentBundleID();
    if (!bundleID) {
        return NO;
    }
    
    NSDictionary *scopedApps = loadScopedApps();
    if (!scopedApps || scopedApps.count == 0) {
        return NO;
    }
    
    // Check if this bundle ID is in the scoped apps dictionary
    NSDictionary *appEntry = scopedApps[bundleID];
    if (!appEntry) {
        // Also try case-insensitive match
        NSString *lowercaseBundleID = [bundleID lowercaseString];
        for (NSString *key in scopedApps) {
            if ([[key lowercaseString] isEqualToString:lowercaseBundleID]) {
                appEntry = scopedApps[key];
                break;
            }
        }
        
        if (!appEntry) {
            return NO;
        }
    }
    
    // Check if the app is enabled
    BOOL isEnabled = [appEntry[@"enabled"] boolValue];
    return isEnabled;
}

// Get the current connection type setting from the plist
static NetworkConnectionType getNetworkConnectionType() {
    // Check if cache is valid
    if (cacheTimestamp && [[NSDate date] timeIntervalSinceDate:cacheTimestamp] < kCacheValidDuration) {
        return cachedConnectionType;
    }
    
    // Read directly from plist file for speed
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:kSecuritySettingsPath];
    
    // Check if network data spoofing is enabled
    BOOL networkDataSpoofEnabled = [settings[@"networkDataSpoofEnabled"] boolValue];
    cachedNetworkDataSpoofEnabled = networkDataSpoofEnabled;
    
    if (!networkDataSpoofEnabled) {
        // If spoofing is disabled, return -1 as a signal to use original behavior
        cachedConnectionType = -1;
        cacheTimestamp = [NSDate date];
        return cachedConnectionType;
    }
    
    // Get the connection type value
    NSNumber *typeNumber = settings[@"networkConnectionType"];
    NSInteger type = typeNumber ? [typeNumber integerValue] : NetworkConnectionTypeAuto;
    
    // Update cache
    cachedConnectionType = type;
    cacheTimestamp = [NSDate date];
    
    PXLog(@"[NetworkHook] Read connection type: %ld, spoofing enabled: %@", 
          (long)type, networkDataSpoofEnabled ? @"YES" : @"NO");
    
    return cachedConnectionType;
}

// For Auto mode, decide randomly between WiFi and Cellular
static BOOL shouldUseWiFiForAutoMode() {
    // Use a persistent seed for the current process to ensure consistent behavior
    static BOOL isWiFi = NO;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        isWiFi = arc4random_uniform(2) == 0; // 50% chance
        PXLog(@"[NetworkHook] Auto mode initialized as: %@", isWiFi ? @"WiFi" : @"Cellular");
    });
    
    return isWiFi;
}

// Helper to check if we should spoof connection type for the current app
static BOOL shouldSpoofConnectionType() {
    NetworkConnectionType type = getNetworkConnectionType();
    
    // If spoofing is disabled or set to "None", don't spoof
    if (type == -1 || !cachedNetworkDataSpoofEnabled || type == NetworkConnectionTypeNone) {
        return NO;
    }
    
    // Check if the current app is a scoped app
    BOOL isScoped = isInScopedAppsList();
    
    // If it's a scoped app, we should apply the network spoofing
    if (isScoped) {
        NSString *bundleID = getCurrentBundleID();
        PXLog(@"[NetworkHook] App %@ is a scoped app, applying network spoofing", bundleID);
        return YES;
    }
    
    return NO;
}

// Helper to check if we should show as WiFi
static BOOL shouldShowAsWiFi() {
    NetworkConnectionType type = getNetworkConnectionType();
    
    if (type == NetworkConnectionTypeWiFi) {
        return YES;
    } else if (type == NetworkConnectionTypeAuto && shouldUseWiFiForAutoMode()) {
        return YES;
    }
    
    return NO;
}

// Helper to check if we should show as Cellular
static BOOL shouldShowAsCellular() {
    NetworkConnectionType type = getNetworkConnectionType();
    if (type == NetworkConnectionTypeCellular) {
        return YES;
    } else if (type == NetworkConnectionTypeAuto && !shouldUseWiFiForAutoMode()) {
        return YES;
    }
    return NO;
}

// Get carrier details from the current profile
static NSDictionary *getCarrierDetailsFromProfile() {
    // Check cache validity
    if (cachedCarrierName && cachedMobileCountryCode && cachedMobileNetworkCode && carrierDetailsCacheTimestamp && 
        [[NSDate date] timeIntervalSinceDate:carrierDetailsCacheTimestamp] < kCarrierDetailsCacheValidDuration) {
        return @{
            @"carrierName": cachedCarrierName,
            @"mobileCountryCode": cachedMobileCountryCode,
            @"mobileNetworkCode": cachedMobileNetworkCode
        };
    }
    
    // Default values (fallback)
    NSString *carrierName = kFakeCarrierName;
    NSString *mobileCountryCode = kFakeMobileCountryCode;
    NSString *mobileNetworkCode = kFakeMobileNetworkCode;
    
    // Get the profile identity path
    NSString *identityDir = getProfileIdentityPath();
    if (identityDir) {
        // Build path to carrier_details.plist
        NSString *carrierDetailsPath = [identityDir stringByAppendingPathComponent:@"carrier_details.plist"];
        
        // Check if file exists
        if ([[NSFileManager defaultManager] fileExistsAtPath:carrierDetailsPath]) {
            // Read the carrier details from plist
            NSDictionary *carrierDetails = [NSDictionary dictionaryWithContentsOfFile:carrierDetailsPath];
            if (carrierDetails) {
                // Extract values from plist with fallbacks
                if (carrierDetails[@"carrierName"]) {
                    carrierName = carrierDetails[@"carrierName"];
                }
                
                if (carrierDetails[@"mcc"]) {
                    mobileCountryCode = carrierDetails[@"mcc"];
                } else if (carrierDetails[@"CarrierMCC"]) {
                    // Also try the alternative field name used in device_ids.plist
                    mobileCountryCode = carrierDetails[@"CarrierMCC"];
                }
                
                if (carrierDetails[@"mnc"]) {
                    mobileNetworkCode = carrierDetails[@"mnc"];
                } else if (carrierDetails[@"CarrierMNC"]) {
                    // Also try the alternative field name used in device_ids.plist
                    mobileNetworkCode = carrierDetails[@"CarrierMNC"];
                }
                
                PXLog(@"[NetworkHook] Read carrier details from profile: carrier=%@, MCC=%@, MNC=%@", 
                     carrierName, mobileCountryCode, mobileNetworkCode);
            } else {
                PXLog(@"[NetworkHook] Failed to read carrier details from %@, using default carrier details", carrierDetailsPath);
            }
        } else {
            // If carrier_details.plist not found, try network_settings.plist
            NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:networkPath]) {
                NSDictionary *networkDict = [NSDictionary dictionaryWithContentsOfFile:networkPath];
                if (networkDict) {
                    // Extract values from network_settings.plist
                    if (networkDict[@"carrierName"]) {
                        carrierName = networkDict[@"carrierName"];
                    }
                    
                    if (networkDict[@"mcc"]) {
                        mobileCountryCode = networkDict[@"mcc"];
                    }
                    
                    if (networkDict[@"mnc"]) {
                        mobileNetworkCode = networkDict[@"mnc"];
                    }
                    
                    PXLog(@"[NetworkHook] Read carrier details from network_settings.plist: carrier=%@, MCC=%@, MNC=%@", 
                         carrierName, mobileCountryCode, mobileNetworkCode);
                }
            } else {
                // If network_settings.plist not found, try device_ids.plist
                NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:deviceIdsPath]) {
                    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
                    if (deviceIds) {
                        // Extract values from device_ids.plist
                        if (deviceIds[@"CarrierName"]) {
                            carrierName = deviceIds[@"CarrierName"];
                        }
                        
                        if (deviceIds[@"CarrierMCC"]) {
                            mobileCountryCode = deviceIds[@"CarrierMCC"];
                        }
                        
                        if (deviceIds[@"CarrierMNC"]) {
                            mobileNetworkCode = deviceIds[@"CarrierMNC"];
                        }
                        
                        PXLog(@"[NetworkHook] Read carrier details from device_ids.plist: carrier=%@, MCC=%@, MNC=%@", 
                             carrierName, mobileCountryCode, mobileNetworkCode);
                    }
                } else {
                    PXLog(@"[NetworkHook] Carrier details file not found at %@, using default carrier details", carrierDetailsPath);
                }
            }
        }
    } else {
        PXLog(@"[NetworkHook] Could not find profile identity directory, using default carrier details");
    }
    
    // Update cache
    cachedCarrierName = carrierName;
    cachedMobileCountryCode = mobileCountryCode;
    cachedMobileNetworkCode = mobileNetworkCode;
    carrierDetailsCacheTimestamp = [NSDate date];
    
    return @{
        @"carrierName": carrierName,
        @"mobileCountryCode": mobileCountryCode,
        @"mobileNetworkCode": mobileNetworkCode
    };
}

// Get a realistic WiFi signal strength in dBm that changes gradually over time
static int getWiFiSignalStrength() {
    // Check if we need to update the signal (approximately every 30-60 seconds)
    NSTimeInterval timeSinceLastUpdate = lastSignalUpdateTime ? [[NSDate date] timeIntervalSinceDate:lastSignalUpdateTime] : 60.0;
    
    // Update signal strength every 30-60 seconds with small random fluctuations
    if (timeSinceLastUpdate >= 30.0 || !lastSignalUpdateTime) {
        // Determine the base signal strength based on connection type
        NetworkConnectionType connectionType = getNetworkConnectionType();
        int targetSignal;
        
        if (connectionType == NetworkConnectionTypeWiFi || 
            (connectionType == NetworkConnectionTypeAuto && shouldUseWiFiForAutoMode())) {
            // For WiFi mode, generally have good to excellent signal (realistic for most environments)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 60) {
                // 60% chance of excellent signal
                targetSignal = kWiFiSignalStrengthExcellent + (arc4random_uniform(10) - 5); // -50 to -40 dBm
            } else if (signalBase < 90) {
                // 30% chance of good signal
                targetSignal = kWiFiSignalStrengthGood + (arc4random_uniform(8) - 4);  // -64 to -56 dBm
            } else {
                // 10% chance of fair signal
                targetSignal = kWiFiSignalStrengthFair + (arc4random_uniform(8) - 4);  // -74 to -66 dBm
            }
        } else if (connectionType == NetworkConnectionTypeCellular ||
                  (connectionType == NetworkConnectionTypeAuto && !shouldUseWiFiForAutoMode())) {
            // For cellular mode, have slightly weaker WiFi (realistic for mobile scenarios)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 20) {
                // 20% chance of excellent signal
                targetSignal = kWiFiSignalStrengthExcellent + (arc4random_uniform(10) - 5); // -50 to -40 dBm
            } else if (signalBase < 50) {
                // 30% chance of good signal
                targetSignal = kWiFiSignalStrengthGood + (arc4random_uniform(8) - 4);  // -64 to -56 dBm
            } else if (signalBase < 80) {
                // 30% chance of fair signal
                targetSignal = kWiFiSignalStrengthFair + (arc4random_uniform(8) - 4);  // -74 to -66 dBm
            } else {
                // 20% chance of poor signal
                targetSignal = kWiFiSignalStrengthPoor + (arc4random_uniform(8) - 4);  // -84 to -76 dBm
            }
        } else {
            // For None mode or default, have variable signal (less predictable)
            targetSignal = -45 - (arc4random_uniform(45)); // -45 to -90 dBm
        }
        
        // Move gradually toward the target signal (max +/- 3 dBm change per update)
        int signalDiff = targetSignal - currentWiFiSignalStrength;
        int maxChange = 3; // Maximum dBm change per update
        
        // Limit the change to ensure realistic gradual signal fluctuations
        if (signalDiff > maxChange) {
            currentWiFiSignalStrength += maxChange;
        } else if (signalDiff < -maxChange) {
            currentWiFiSignalStrength -= maxChange;
        } else {
            currentWiFiSignalStrength = targetSignal;
        }
        
        // Add small random fluctuation (+/- 1 dBm) for realism
        currentWiFiSignalStrength += (arc4random_uniform(3) - 1);
        
        // Enforce realistic bounds for WiFi signal strength
        if (currentWiFiSignalStrength > -40) currentWiFiSignalStrength = -40;  // Never too perfect
        if (currentWiFiSignalStrength < -90) currentWiFiSignalStrength = -90;  // Never too terrible
        
        // Update last update time
        lastSignalUpdateTime = [NSDate date];
        
        PXLog(@"[NetworkHook] Updated WiFi signal strength to %d dBm", currentWiFiSignalStrength);
    }
    
    return currentWiFiSignalStrength;
}

// Get realistic cellular signal bars (1-5) that change gradually over time
static int getCellularSignalBars() {
    // Check if we need to update the signal (use the same timing as WiFi for consistency)
    NSTimeInterval timeSinceLastUpdate = lastSignalUpdateTime ? [[NSDate date] timeIntervalSinceDate:lastSignalUpdateTime] : 60.0;
    
    // Update signal bars every 30-60 seconds
    if (timeSinceLastUpdate >= 30.0 || !lastSignalUpdateTime) {
        // Determine the base signal bars based on connection type
        NetworkConnectionType connectionType = getNetworkConnectionType();
        int targetBars;
        
        if (connectionType == NetworkConnectionTypeCellular || 
            (connectionType == NetworkConnectionTypeAuto && !shouldUseWiFiForAutoMode())) {
            // For cellular mode, generally have good signal (3-5 bars)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 40) {
                // 40% chance of 5 bars
                targetBars = 5;
            } else if (signalBase < 80) {
                // 40% chance of 4 bars
                targetBars = 4;
            } else {
                // 20% chance of 3 bars
                targetBars = 3;
            }
        } else if (connectionType == NetworkConnectionTypeWiFi ||
                  (connectionType == NetworkConnectionTypeAuto && shouldUseWiFiForAutoMode())) {
            // For WiFi mode, have slightly weaker cellular (1-4 bars, realistic for indoor WiFi scenarios)
            int signalBase = arc4random_uniform(100);
            if (signalBase < 20) {
                // 20% chance of 4 bars
                targetBars = 4;
            } else if (signalBase < 50) {
                // 30% chance of 3 bars
                targetBars = 3;
            } else if (signalBase < 80) {
                // 30% chance of 2 bars
                targetBars = 2;
            } else {
                // 20% chance of 1 bar
                targetBars = 1;
            }
        } else {
            // For None mode or default, random bars
            targetBars = 1 + (arc4random_uniform(5)); // 1-5 bars
        }
        
        // Move gradually toward the target bars (max +/- 1 bar change per update)
        int barsDiff = targetBars - currentCellularSignalBars;
        
        // Limit the change to ensure realistic gradual signal fluctuations
        if (barsDiff > 1) {
            currentCellularSignalBars += 1;
        } else if (barsDiff < -1) {
            currentCellularSignalBars -= 1;
        } else {
            currentCellularSignalBars = targetBars;
        }
        
        // Enforce bounds
        if (currentCellularSignalBars < 1) currentCellularSignalBars = 1;
        if (currentCellularSignalBars > 5) currentCellularSignalBars = 5;
        
        PXLog(@"[NetworkHook] Updated cellular signal bars to %d", currentCellularSignalBars);
    }
    
    return currentCellularSignalBars;
}

// Get a realistic cellular network type (4G/5G) that changes based on signal strength
static NSString *getCurrentCellularNetworkType() {
    // Initialize the network type if not set
    if (!currentCellularNetworkType) {
        // Default to LTE (4G) initially
        currentCellularNetworkType = kCellularNetworkType4G;
        lastNetworkTypeChangeTime = [NSDate date];
    }
    
    // Only consider changing network type after a minimum duration
    NSTimeInterval timeSinceLastChange = [[NSDate date] timeIntervalSinceDate:lastNetworkTypeChangeTime];
    if (timeSinceLastChange < kMinNetworkTypeChangeDuration) {
        return currentCellularNetworkType;
    }
    
    // Only change network type occasionally (10% chance per check)
    if (arc4random_uniform(100) >= 10) {
        return currentCellularNetworkType;
    }
    
    // Determine probability of 5G based on signal strength
    // Higher signal = higher chance of 5G
    CGFloat probabilityOf5G = 0.0;
    
    // Map signal bars (1-5) to 5G probability
    switch (currentCellularSignalBars) {
        case 5: probabilityOf5G = 0.85; break; // Excellent signal: 85% chance of 5G
        case 4: probabilityOf5G = 0.65; break; // Good signal: 65% chance of 5G
        case 3: probabilityOf5G = 0.40; break; // Fair signal: 40% chance of 5G
        case 2: probabilityOf5G = 0.15; break; // Poor signal: 15% chance of 5G
        case 1: probabilityOf5G = 0.05; break; // Very poor signal: 5% chance of 5G
        default: probabilityOf5G = 0.0;        // No signal: 0% chance of 5G
    }
    
    // Random decision based on probability
    CGFloat random = (CGFloat)arc4random_uniform(100) / 100.0;
    
    NSString *newNetworkType;
    if (random < probabilityOf5G) {
        // Decide between standalone 5G and NSA 5G
        // NSA is more common in early 5G deployments
        if (arc4random_uniform(100) < 70) {
            newNetworkType = kCellularNetworkType5GNSA; // 70% of 5G is NSA
        } else {
            newNetworkType = kCellularNetworkType5G;    // 30% of 5G is standalone
        }
    } else {
        newNetworkType = kCellularNetworkType4G;        // Default to 4G
    }
    
    // Only log if network type actually changed
    if (![newNetworkType isEqualToString:currentCellularNetworkType]) {
        PXLog(@"[NetworkHook] Changed cellular network type from %@ to %@", 
              currentCellularNetworkType, newNetworkType);
        
        // Update stored values
        currentCellularNetworkType = newNetworkType;
        lastNetworkTypeChangeTime = [NSDate date];
    }
    
    return currentCellularNetworkType;
}

#pragma mark - SCNetworkReachability Hooks

// Hook SCNetworkReachabilityGetFlags to modify network type
static Boolean (*original_SCNetworkReachabilityGetFlags)(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags);

Boolean hooked_SCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    if (shouldShowAsWiFi()) {
        return original_SCNetworkReachabilityGetFlags(target, flags);
    }
    Boolean result = original_SCNetworkReachabilityGetFlags(target, flags);
    if (!result || !flags) {
        return result;
    }
    @try {
        if (!shouldSpoofConnectionType()) {
            return result;
        }
        if (shouldShowAsWiFi()) {
            *flags |= kSCNetworkReachabilityFlagsReachable;
            *flags &= ~kSCNetworkReachabilityFlagsIsWWAN;
        } else if (shouldShowAsCellular()) {
            *flags |= kSCNetworkReachabilityFlagsReachable;
            *flags |= kSCNetworkReachabilityFlagsIsWWAN;
        } else {
            *flags &= ~kSCNetworkReachabilityFlagsReachable;
            *flags &= ~kSCNetworkReachabilityFlagsIsWWAN;
        }
    } @catch (NSException *exception) {}
    return result;
}

#pragma mark - CoreTelephony Hooks

// Hook for CTTelephonyNetworkInfo
%hook CTTelephonyNetworkInfo

- (NSDictionary<NSString *, CTCarrier *> *)serviceSubscriberCellularProviders {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    NSDictionary<NSString *, CTCarrier *> *origDict = %orig;
    return origDict;
}

- (CTCarrier *)subscriberCellularProvider {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    return %orig;
}

- (NSString *)currentRadioAccessTechnology {
    if (shouldShowAsWiFi()) {
        return %orig;
    } else if (shouldShowAsCellular()) {
        return getCurrentCellularNetworkType();
    }
    return %orig;
}

- (NSDictionary<NSString *, NSString *> *)serviceCurrentRadioAccessTechnology {
    if (shouldShowAsWiFi()) {
        return %orig;
    } else if (shouldShowAsCellular()) {
        return @{ @"0": getCurrentCellularNetworkType() };
    }
    return %orig;
}

%end

// Hook for CTCarrier
%hook CTCarrier

- (NSString *)carrierName {
    if (shouldShowAsWiFi()) {
        return %orig;
    } else if (shouldShowAsCellular()) {
        return getCarrierDetailsFromProfile()[@"carrierName"];
    }
    return %orig;
}

- (NSString *)mobileCountryCode {
    if (shouldShowAsWiFi()) {
        return %orig;
    } else if (shouldShowAsCellular()) {
        return getCarrierDetailsFromProfile()[@"mobileCountryCode"];
    }
    return %orig;
}

- (NSString *)mobileNetworkCode {
    if (shouldShowAsWiFi()) {
        return %orig;
    } else if (shouldShowAsCellular()) {
        return getCarrierDetailsFromProfile()[@"mobileNetworkCode"];
    }
    return %orig;
}

- (NSString *)isoCountryCode {
    if (shouldShowAsWiFi()) {
        return %orig;
    } else if (shouldShowAsCellular()) {
        return getCurrentISOCountryCode();
    }
    return %orig;
}

- (BOOL)allowsVOIP {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // Allow VOIP in all network modes
    return YES;
}

%end

#pragma mark - NSURLSession and CFNetwork Hooks

// Hook for cellular detection in NSURLSession
%hook NSURLSessionConfiguration

- (BOOL)allowsCellularAccess {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    return %orig;
}

- (BOOL)isDiscretionary {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // Discretionary transfers are typically used for background transfers 
    // that prefer WiFi. Return NO to indicate high priority connection.
    return NO;
}

%end

#pragma mark - getifaddrs Hook for Local IP Address

// Enable getifaddrs hook for local IP spoofing
static int (*original_getifaddrs)(struct ifaddrs **);
static int hooked_getifaddrs(struct ifaddrs **ifap) {
    if (shouldShowAsWiFi()) {
        return original_getifaddrs(ifap);
    }
    int result = original_getifaddrs(ifap);
    if (result == 0 && ifap && *ifap && shouldSpoofConnectionType()) {
        struct ifaddrs *ifa = *ifap;
        NetworkConnectionType type = getNetworkConnectionType();
        NSString *spoofedIP = getProfileLocalIPAddress();
        NSString *spoofedIPv6 = [NetworkManager getSavedLocalIPv6Address];
        if (!spoofedIPv6) {
            spoofedIPv6 = @"fe80::1234:abcd:5678:9abc";
        }
        // Generate plausible carrier IPv4/IPv6 for pdp_ip0
        NSString *carrierIPv4 = @"10.0.0.5";
        NSString *carrierIPv6 = @"2607:f8b0:4005:805::200e"; // Example global IPv6
        while (ifa) {
            if (ifa->ifa_addr) {
                if (ifa->ifa_addr->sa_family == AF_INET) {
                    if (type == NetworkConnectionTypeWiFi || (type == NetworkConnectionTypeAuto && shouldUseWiFiForAutoMode())) {
                        if (strcmp(ifa->ifa_name, "en0") == 0 && spoofedIP) {
                            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
                            sin->sin_addr.s_addr = inet_addr([spoofedIP UTF8String]);
                        }
                        // Optionally, clear pdp_ip0
                        if (strcmp(ifa->ifa_name, "pdp_ip0") == 0) {
                            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
                            sin->sin_addr.s_addr = 0;
                        }
                    } else if (type == NetworkConnectionTypeCellular || (type == NetworkConnectionTypeAuto && !shouldUseWiFiForAutoMode())) {
                        if (strcmp(ifa->ifa_name, "pdp_ip0") == 0 && carrierIPv4) {
                            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
                            sin->sin_addr.s_addr = inet_addr([carrierIPv4 UTF8String]);
                        }
                        // Optionally, clear en0
                        if (strcmp(ifa->ifa_name, "en0") == 0) {
                            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
                            sin->sin_addr.s_addr = 0;
                        }
                    }
                } else if (ifa->ifa_addr->sa_family == AF_INET6) {
                    if (type == NetworkConnectionTypeWiFi || (type == NetworkConnectionTypeAuto && shouldUseWiFiForAutoMode())) {
                        if (strcmp(ifa->ifa_name, "en0") == 0 && spoofedIPv6) {
                            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)ifa->ifa_addr;
                            inet_pton(AF_INET6, [spoofedIPv6 UTF8String], &sin6->sin6_addr);
                        }
                        // Optionally, clear pdp_ip0
                        if (strcmp(ifa->ifa_name, "pdp_ip0") == 0) {
                            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)ifa->ifa_addr;
                            memset(&sin6->sin6_addr, 0, sizeof(sin6->sin6_addr));
                        }
                    } else if (type == NetworkConnectionTypeCellular || (type == NetworkConnectionTypeAuto && !shouldUseWiFiForAutoMode())) {
                        if (strcmp(ifa->ifa_name, "pdp_ip0") == 0 && carrierIPv6) {
                            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)ifa->ifa_addr;
                            inet_pton(AF_INET6, [carrierIPv6 UTF8String], &sin6->sin6_addr);
                        }
                        // Optionally, clear en0
                        if (strcmp(ifa->ifa_name, "en0") == 0) {
                            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)ifa->ifa_addr;
                            memset(&sin6->sin6_addr, 0, sizeof(sin6->sin6_addr));
                        }
                    }
                }
            }
            ifa = ifa->ifa_next;
        }
    }
    return result;
}

#pragma mark - Network.framework Hooks (iOS 12+)

// Attempt to hook NWPathMonitor for newer iOS versions
%group NetworkFrameworkHooks

%hook NWPath

- (BOOL)isExpensive {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // WiFi is not expensive, cellular is
    return shouldShowAsCellular();
}

- (BOOL)usesInterfaceType:(NSInteger)type {
    if (shouldShowAsWiFi()) {
        // Interface type 1 is typically WiFi
        if (type == 1) {
            return YES;
        }
        // Interface type 2 is typically cellular
        else if (type == 2) {
            return NO;
        }
    }
    // For cellular mode
    else {
        // Interface type 1 is typically WiFi
        if (type == 1) {
            return NO;
        }
        // Interface type 2 is typically cellular
        else if (type == 2) {
            return YES;
        }
    }
    
    return %orig;
}

%end

%end

// Notification callback for settings changes
static void networkSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear cache when notification received
    cacheTimestamp = nil;
    isoCountryCodeCacheTimestamp = nil; // Also clear ISO country code cache
    PXLog(@"[NetworkHook] Received settings change notification, cache cleared");
}

// Notification callback for ISO country code changes
static void isoCountryCodeChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear ISO country code cache when notification received
    isoCountryCodeCacheTimestamp = nil;
    PXLog(@"[NetworkHook] Received ISO country code change notification, cache cleared");
}

// Notification callback for scoped apps changes
static void scopedAppsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear cache when notification received
    scopedAppsCacheTimestamp = nil;
    PXLog(@"[NetworkHook] Received scoped apps change notification, cache cleared");
}

// Notification callback for carrier details changes
static void carrierDetailsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear carrier details cache when notification received
    carrierDetailsCacheTimestamp = nil;
    PXLog(@"[NetworkHook] Received carrier details change notification, cache cleared");
}

// Notification callback for signal strength settings changes
static void signalStrengthSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Clear cache when notification received
    lastSignalUpdateTime = nil;
    
    // Also reset the network type change timer to allow immediate change
    lastNetworkTypeChangeTime = nil;
    
    PXLog(@"[NetworkHook] Received signal strength settings change notification, cache cleared");
}

// Hook for WiFi signal strength (CNCopyCurrentNetworkInfo)
static CFDictionaryRef (*original_CNCopyCurrentNetworkInfo)(CFStringRef interfaceName);

static CFDictionaryRef hooked_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    if (shouldShowAsWiFi()) {
        return original_CNCopyCurrentNetworkInfo(interfaceName);
    }
    // Always call the original so WiFiHook.x can spoof as needed
    CFDictionaryRef originalDict = original_CNCopyCurrentNetworkInfo(interfaceName);
    if (!originalDict) return originalDict;
    // Existing WiFi signal strength spoofing logic
    CFMutableDictionaryRef newDict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, originalDict);
    int signalStrength = getWiFiSignalStrength();
    CFNumberRef rssiNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &signalStrength);
    CFDictionarySetValue(newDict, CFSTR("RSSI"), rssiNumber);
    CFRelease(originalDict);
    CFRelease(rssiNumber);
    return newDict;
}

// Add hooks for CoreTelephony signal strength
%hook CTServiceDescriptor

- (NSString *)signalStrengthBars {
    if (shouldShowAsWiFi()) {
        return %orig;
    }
    
    // Return spoofed signal bars
    int bars = getCellularSignalBars();
    NSString *barsString = [NSString stringWithFormat:@"%d", bars];
    
    PXLog(@"[NetworkHook] Spoofed cellular signal bars to %@", barsString);
    
    return barsString;
}

%end

%hook UIStatusBarSignalStrengthItemView

- (void)setCellularSignalStrengthBars:(int)bars {
    if (shouldShowAsWiFi()) {
        %orig;
        return;
    }
    
    // Get spoofed signal bars
    int spoofedBars = getCellularSignalBars();
    
    PXLog(@"[NetworkHook] Spoofed UI cellular signal bars from %d to %d", bars, spoofedBars);
    
    %orig(spoofedBars);
}

%end

#pragma mark - Initialization

%ctor {
    @autoreleasepool {
        // Initialize the scoped apps cache
        scopedAppsCache = [NSMutableDictionary dictionary];
        
        PXLog(@"[NetworkHook] Initializing network connection type hooks");
        
        // Check if the current app is a scoped app
        NSString *bundleID = getCurrentBundleID();
        BOOL isScoped = isInScopedAppsList();
        
        PXLog(@"[NetworkHook] Current app: %@, is scoped: %@", 
              bundleID ?: @"(unknown)", isScoped ? @"YES" : @"NO");
        
        // Only initialize hooks if this is a scoped app
        if (isScoped) {
            // Initialize CoreTelephony hooks
            %init;
            
            // Initialize Network.framework hooks if available
            Class NWPathClass = NSClassFromString(@"NWPath");
            if (NWPathClass) {
                %init(NetworkFrameworkHooks);
                PXLog(@"[NetworkHook] Successfully initialized Network.framework hooks");
            }
            
            // Setup the SCNetworkReachabilityGetFlags hook
            void *SCNetworkReachabilityGetFlagsPtr = dlsym(RTLD_DEFAULT, "SCNetworkReachabilityGetFlags");
            if (SCNetworkReachabilityGetFlagsPtr) {
                // Use ElleKit for hooking (preferred for iOS 15+)
                EKHook(SCNetworkReachabilityGetFlagsPtr, 
                       (void *)hooked_SCNetworkReachabilityGetFlags, 
                       (void **)&original_SCNetworkReachabilityGetFlags);
                PXLog(@"[NetworkHook] Successfully hooked SCNetworkReachabilityGetFlags");
            } else {
                PXLog(@"[NetworkHook] ERROR: Could not find SCNetworkReachabilityGetFlags function!");
            }
            
            // Enable getifaddrs hook for local IP spoofing
            void *getifaddrsPtr = dlsym(RTLD_DEFAULT, "getifaddrs");
            if (getifaddrsPtr) {
                EKHook(getifaddrsPtr, (void *)hooked_getifaddrs, (void **)&original_getifaddrs);
                PXLog(@"[NetworkHook] Successfully hooked getifaddrs for local IP spoofing");
            } else {
                PXLog(@"[NetworkHook] ERROR: Could not find getifaddrs function!");
            }
            
            // Note: We don't hook CNCopySupportedInterfaces or CNCopyCurrentNetworkInfo
            // as they are already handled by WiFiHook.x for SSID/BSSID spoofing
            
            // Register for notification when settings change
            CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
            CFNotificationCenterAddObserver(darwinCenter,
                                           NULL,
                                           networkSettingsChanged,
                                           CFSTR("com.hydra.projectx.networkConnectionTypeChanged"),
                                           NULL,
                                           CFNotificationSuspensionBehaviorDeliverImmediately);
            
            // Register for notification when ISO country code changes
            CFNotificationCenterAddObserver(darwinCenter,
                                           NULL,
                                           isoCountryCodeChanged,
                                           CFSTR("com.hydra.projectx.networkISOCountryCodeChanged"),
                                           NULL,
                                           CFNotificationSuspensionBehaviorDeliverImmediately);
            
            // Register for notification when scoped apps change
            CFNotificationCenterAddObserver(darwinCenter,
                                           NULL,
                                           scopedAppsChanged,
                                           CFSTR("com.hydra.projectx.scopedAppsChanged"),
                                           NULL,
                                           CFNotificationSuspensionBehaviorDeliverImmediately);
            
            // Register for notification when carrier details change
            CFNotificationCenterAddObserver(darwinCenter,
                                           NULL,
                                           carrierDetailsChanged,
                                           CFSTR("com.hydra.projectx.carrierDetailsChanged"),
                                           NULL,
                                           CFNotificationSuspensionBehaviorDeliverImmediately);
            
            // Register for notification when signal strength settings change
            CFNotificationCenterAddObserver(darwinCenter,
                                           NULL,
                                           signalStrengthSettingsChanged,
                                           CFSTR("com.hydra.projectx.signalStrengthSettingsChanged"),
                                           NULL,
                                           CFNotificationSuspensionBehaviorDeliverImmediately);
            
            // Log initial state
            NetworkConnectionType initialType = getNetworkConnectionType();
            if (initialType != -1) {
                NSString *connectionName;
                switch (initialType) {
                    case NetworkConnectionTypeNone:
                        connectionName = @"None";
                        break;
                    case NetworkConnectionTypeWiFi:
                        connectionName = @"WiFi";
                        break;
                    case NetworkConnectionTypeCellular:
                        connectionName = @"Cellular";
                        break;
                    case NetworkConnectionTypeAuto:
                        connectionName = @"Auto";
                        break;
                    default:
                        connectionName = @"Unknown";
                        break;
                }
                
                if (initialType == NetworkConnectionTypeWiFi || 
                    (initialType == NetworkConnectionTypeAuto && shouldUseWiFiForAutoMode())) {
                    NSString *localIP = getProfileLocalIPAddress();
                    PXLog(@"[NetworkHook] Network connection type spoofing enabled with type: %@ (Local IP: %@) for scoped app: %@", 
                          connectionName, localIP, bundleID);
                } else if (initialType == NetworkConnectionTypeCellular ||
                          (initialType == NetworkConnectionTypeAuto && !shouldUseWiFiForAutoMode())) {
                    NSString *isoCode = getCurrentISOCountryCode();
                    PXLog(@"[NetworkHook] Network connection type spoofing enabled with type: %@ (ISO: %@) for scoped app: %@", 
                          connectionName, isoCode, bundleID);
                } else {
                    PXLog(@"[NetworkHook] Network connection type spoofing enabled with type: %@ for scoped app: %@", 
                          connectionName, bundleID);
                }
            } else {
                PXLog(@"[NetworkHook] Network connection type spoofing disabled");
            }
            
            // Setup CNCopyCurrentNetworkInfo hook for WiFi signal strength
            void *CNCopyCurrentNetworkInfoPtr = dlsym(RTLD_DEFAULT, "CNCopyCurrentNetworkInfo");
            if (CNCopyCurrentNetworkInfoPtr) {
                EKHook(CNCopyCurrentNetworkInfoPtr,
                      (void *)hooked_CNCopyCurrentNetworkInfo,
                      (void **)&original_CNCopyCurrentNetworkInfo);
                PXLog(@"[NetworkHook] Successfully hooked CNCopyCurrentNetworkInfo for WiFi signal strength spoofing");
            } else {
                PXLog(@"[NetworkHook] ERROR: Could not find CNCopyCurrentNetworkInfo function!");
            }
        } else {
            PXLog(@"[NetworkHook] App is not scoped, network spoofing will not be applied");
        }
    }
} 