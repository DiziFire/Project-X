#import "UptimeManager.h"
#import <sys/sysctl.h>
#import "ProjectXLogging.h"

// File paths for persistent storage
// Removed global paths. All methods now require a profile-specific path.

// Keys for plist dictionaries
static NSString * const kBootTimeKey = @"bootTime";
static NSString * const kUptimeKey = @"uptime";
static NSString * const kCreationTimeKey = @"creationTime";

#ifndef kUptimeVersionKey
#define kUptimeVersionKey @"version"
#endif

@interface UptimeManager ()
@property (nonatomic, strong) NSDate *bootTimeValue;
@property (nonatomic, assign) NSTimeInterval uptimeValue;
@property (nonatomic, strong) NSDate *cacheTime;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) dispatch_queue_t concurrentQueue;
@end

@implementation UptimeManager

#pragma mark - Initialization

+ (instancetype)sharedManager {
    static UptimeManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize with default values
        _bootTimeValue = nil;
        _uptimeValue = 0;
        _cacheTime = nil;
        _concurrentQueue = dispatch_queue_create("com.weaponx.UptimeManager", DISPATCH_QUEUE_CONCURRENT);
        
        // Load saved values if they exist

    }
    return self;
}

#pragma mark - Uptime Generation

- (void)generateConsistentUptimeAndBootTimeForProfile:(NSString *)profilePath {
    @try {
        // Validate profile path
        if (!profilePath || [profilePath length] == 0) {
            NSString *errorMsg = @"Invalid profile path provided";
            self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                             code:1003 
                                         userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
            PXLog(@"[WeaponX] ❌ %@", errorMsg);
            return;
        }
        
        // Ensure profile directory exists
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *dirError = nil;
        if (![fileManager createDirectoryAtPath:profilePath 
                     withIntermediateDirectories:YES 
                                      attributes:nil 
                                           error:&dirError]) {
            // Check if the error is because directory already exists
            if (dirError.code != NSFileWriteFileExistsError && ![fileManager fileExistsAtPath:profilePath]) {
                NSString *errorMsg = [NSString stringWithFormat:@"Failed to create profile directory: %@", dirError.localizedDescription];
                self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                                 code:1004 
                                             userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
                PXLog(@"[WeaponX] ❌ %@", errorMsg);
                return;
            }
        }
        
        // Generate a random uptime between 12-48 hours with added randomness
        NSTimeInterval minUptime = 12 * 3600; // 12 hours
        NSTimeInterval maxUptime = 48 * 3600; // 48 hours
        NSTimeInterval uptimeRange = maxUptime - minUptime;
        NSTimeInterval randomPart = arc4random_uniform((uint32_t)uptimeRange);
        NSTimeInterval extraSeconds = arc4random_uniform(60 * 45);
        NSTimeInterval uptime = minUptime + randomPart + extraSeconds;
        
        // Check real uptime to ensure spoofed value isn't higher
        struct timeval boottv = {0};
        size_t sz = sizeof(boottv);
        int mib[2] = {CTL_KERN, KERN_BOOTTIME};
        int sysctlResult = sysctl(mib, 2, &boottv, &sz, NULL, 0);
        if (sysctlResult == 0) {
            NSDate *realBoot = [NSDate dateWithTimeIntervalSince1970:boottv.tv_sec];
            NSTimeInterval realUptime = [[NSDate date] timeIntervalSinceDate:realBoot];
            if (uptime > realUptime - 60) {
                uptime = realUptime - 60;
            }
            if (uptime < minUptime) uptime = minUptime;
        }
        
        // Calculate boot time based on generated uptime
        NSDate *now = [NSDate date];
        NSDate *bootTime = [NSDate dateWithTimeIntervalSinceNow:-uptime];
        
        // Save boot time to profile-specific file
        NSString *bootTimePath = [profilePath stringByAppendingPathComponent:@"boot_time.plist"];
        NSDictionary *bootTimeDict = @{@"value": bootTime, @"lastUpdated": now, kUptimeVersionKey: @1};
        BOOL bootTimeSuccess = [bootTimeDict writeToFile:bootTimePath atomically:YES];
        if (!bootTimeSuccess) {
            PXLog(@"[WeaponX] ⚠️ Failed to write boot_time.plist to %@", bootTimePath);
        }
        
        // Also save to system_uptime.plist for apps that might look there
        NSString *uptimePath = [profilePath stringByAppendingPathComponent:@"system_uptime.plist"];
        NSString *uptimeString = [NSString stringWithFormat:@"%.0f", uptime];
        NSDictionary *uptimeDict = @{@"value": uptimeString, @"lastUpdated": now, kUptimeVersionKey: @1};
        BOOL uptimeSuccess = [uptimeDict writeToFile:uptimePath atomically:YES];
        if (!uptimeSuccess) {
            PXLog(@"[WeaponX] ⚠️ Failed to write system_uptime.plist to %@", uptimePath);
        }
        
        // Also save to the combined device_ids.plist
        NSString *deviceIdsPath = [profilePath stringByAppendingPathComponent:@"device_ids.plist"];
        NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath];
        if (!deviceIds) {
            deviceIds = [NSMutableDictionary dictionary];
        }
        
        deviceIds[@"BootTime"] = [NSString stringWithFormat:@"%.0f", [bootTime timeIntervalSince1970]];
        deviceIds[@"SystemUptime"] = uptimeString;
        deviceIds[@"LastUpdated"] = now;  // Add timestamp for device_ids.plist too
        BOOL deviceIdsSuccess = [deviceIds writeToFile:deviceIdsPath atomically:YES];
        if (!deviceIdsSuccess) {
            PXLog(@"[WeaponX] ⚠️ Failed to write device_ids.plist to %@", deviceIdsPath);
        }
        
        // Set cache values for use in other methods
        self.bootTimeValue = bootTime;
        self.uptimeValue = uptime;
        self.cacheTime = now;
        
        PXLog(@"[WeaponX] ✅ Generated consistent uptime (%.2f hours) and boot time (%@) for profile path: %@", 
              uptime/3600.0, bootTime, profilePath);
        PXLog(@"[WeaponX] 📄 Files saved: boot_time.plist=%@, system_uptime.plist=%@, device_ids.plist=%@",
              bootTimeSuccess ? @"✅" : @"❌", 
              uptimeSuccess ? @"✅" : @"❌",
              deviceIdsSuccess ? @"✅" : @"❌");
    } @catch (NSException *e) {
        NSString *errorMsg = [NSString stringWithFormat:@"Error generating consistent uptime: %@", e];
        self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                         code:1002 
                                     userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        PXLog(@"[WeaponX] ❌ %@", errorMsg);
    }
}

- (NSString *)generateUptimeForProfile:(NSString *)profilePath {
    // Generate a new spoofed boot time (if needed)
    [self generateConsistentUptimeAndBootTimeForProfile:profilePath];
    // Return the current spoofed uptime as string
    NSTimeInterval uptime = [self currentUptimeForProfile:profilePath];
    return [NSString stringWithFormat:@"%.0f", uptime];
}

- (NSTimeInterval)currentUptimeForProfile:(NSString *)profilePath {
    // Check if path is valid
    if (!profilePath || [profilePath length] == 0) {
        self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                       code:1003 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid profile path"}];
        return 0;
    }
    
    // First try boot_time.plist for the most accurate calculation
    NSString *bootTimePath = [profilePath stringByAppendingPathComponent:@"boot_time.plist"];
    NSDictionary *bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
    if (bootTimeDict && bootTimeDict[@"value"] && [bootTimeDict[@"value"] isKindOfClass:[NSDate class]]) {
        NSDate *bootTime = bootTimeDict[@"value"];
        NSTimeInterval uptime = [[NSDate date] timeIntervalSinceDate:bootTime];
        if (uptime > 0) {
            return uptime;
        }
    }
    
    // If boot_time.plist failed, try system_uptime.plist
    NSString *uptimePath = [profilePath stringByAppendingPathComponent:@"system_uptime.plist"];
    NSDictionary *uptimeDict = [NSDictionary dictionaryWithContentsOfFile:uptimePath];
    if (uptimeDict && uptimeDict[@"value"] && uptimeDict[@"lastUpdated"]) {
        NSString *uptimeString = uptimeDict[@"value"];
        NSDate *lastUpdated = uptimeDict[@"lastUpdated"];
        NSTimeInterval storedUptime = [uptimeString doubleValue];
        
        // Calculate current uptime based on stored value and time elapsed
        NSTimeInterval timeElapsed = [[NSDate date] timeIntervalSinceDate:lastUpdated];
        NSTimeInterval currentUptime = storedUptime + timeElapsed;
        
        if (currentUptime > 0) {
            return currentUptime;
        }
    }
    
    // Try device_ids.plist as a last resort
    NSString *deviceIdsPath = [profilePath stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
    if (deviceIds && deviceIds[@"SystemUptime"]) {
        NSTimeInterval uptime = [deviceIds[@"SystemUptime"] doubleValue];
        if (uptime > 0) {
            return uptime;
        }
    }
    
    // If all lookups failed, generate new values and retry
    PXLog(@"[WeaponX] ⚠️ No valid uptime found for profile %@, generating new values", profilePath);
    [self generateConsistentUptimeAndBootTimeForProfile:profilePath];
    
    // Try again after generating
    bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
    if (bootTimeDict && bootTimeDict[@"value"] && [bootTimeDict[@"value"] isKindOfClass:[NSDate class]]) {
        NSDate *bootTime = bootTimeDict[@"value"];
        NSTimeInterval uptime = [[NSDate date] timeIntervalSinceDate:bootTime];
        return uptime > 0 ? uptime : 0;
    }
    
    // If still failed, return a safe default
    return 12 * 3600; // 12 hours as safe default
}

- (void)setCurrentUptime:(NSTimeInterval)uptime {
    if (uptime <= 0) {
        self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                         code:1001 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Uptime must be greater than 0"}];
        return;
    }
    self.uptimeValue = uptime;
    self.cacheTime = [NSDate date];
    self.bootTimeValue = [NSDate dateWithTimeIntervalSinceNow:-uptime];
    PXLog(@"[WeaponX] 🕒 Set system uptime: %.2f hours", uptime / 3600.0);
}

#pragma mark - Boot Time Generation

- (NSString *)generateBootTimeForProfile:(NSString *)profilePath {
    [self generateConsistentUptimeAndBootTimeForProfile:profilePath];
    NSString *bootTimePath = [profilePath stringByAppendingPathComponent:@"boot_time.plist"];
    NSDictionary *bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
    if (bootTimeDict && bootTimeDict[@"value"]) {
        NSDate *bootTime = bootTimeDict[@"value"];
        if ([bootTime isKindOfClass:[NSDate class]]) {
            return [NSString stringWithFormat:@"%.0f", [bootTime timeIntervalSince1970]];
        }
    }
    return @"0";
}

- (NSDate *)currentBootTimeForProfile:(NSString *)profilePath {
    // Check if path is valid
    if (!profilePath || [profilePath length] == 0) {
        self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                       code:1003 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid profile path"}];
        return nil;
    }
    
    // First check boot_time.plist
    NSString *bootTimePath = [profilePath stringByAppendingPathComponent:@"boot_time.plist"];
    NSDictionary *bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
    if (bootTimeDict && bootTimeDict[@"value"] && [bootTimeDict[@"value"] isKindOfClass:[NSDate class]]) {
        return bootTimeDict[@"value"];
    }
    
    // Try device_ids.plist as a fallback
    NSString *deviceIdsPath = [profilePath stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
    if (deviceIds && deviceIds[@"BootTime"]) {
        NSTimeInterval timestamp = [deviceIds[@"BootTime"] doubleValue];
        if (timestamp > 0) {
            return [NSDate dateWithTimeIntervalSince1970:timestamp];
        }
    }
    
    // If no valid boot time found, generate new values and retry
    PXLog(@"[WeaponX] ⚠️ No valid boot time found for profile %@, generating new values", profilePath);
    [self generateConsistentUptimeAndBootTimeForProfile:profilePath];
    
    // Try again after generating
    bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
    if (bootTimeDict && bootTimeDict[@"value"] && [bootTimeDict[@"value"] isKindOfClass:[NSDate class]]) {
        return bootTimeDict[@"value"];
    }
    
    // If still failed, return current time minus default uptime
    return [NSDate dateWithTimeIntervalSinceNow:-(12 * 3600)]; // 12 hours ago as safe default
}

- (void)setCurrentBootTime:(NSDate *)bootTime {
    if (!bootTime) {
        self.error = [NSError errorWithDomain:@"com.weaponx.UptimeManager" 
                                         code:1002 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Boot time cannot be nil"}];
        return;
    }
    self.bootTimeValue = bootTime;
    self.cacheTime = [NSDate date];
    NSTimeInterval uptime = [[NSDate date] timeIntervalSinceDate:bootTime];
    self.uptimeValue = uptime;
    PXLog(@"[WeaponX] 🕒 Set boot time: %@", bootTime);
}

#pragma mark - Consistent Uptime Generation

// Implementation already defined at the top of file

#pragma mark - Error Handling

- (NSError *)lastError {
    return self.error;
}

#pragma mark - Helper Methods

// Legacy API: stub implementations to satisfy linker, but not used in profile-specific logic
- (NSString *)generateUptime {
    PXLog(@"[WeaponX] WARNING: Called legacy generateUptime; use generateUptimeForProfile:");
    return @"0";
}
- (NSTimeInterval)currentUptime {
    PXLog(@"[WeaponX] WARNING: Called legacy currentUptime; use currentUptimeForProfile:");
    return 0;
}
- (NSString *)generateBootTime {
    PXLog(@"[WeaponX] WARNING: Called legacy generateBootTime; use generateBootTimeForProfile:");
    return @"0";
}
- (NSDate *)currentBootTime {
    PXLog(@"[WeaponX] WARNING: Called legacy currentBootTime; use currentBootTimeForProfile:");
    return nil;
}

- (NSString *)debugSpoofedUptimeInfo {
    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"Spoofed Uptime: %.0f seconds (%.2f hours)\n", self.uptimeValue, self.uptimeValue/3600.0];
    [result appendFormat:@"Spoofed Boot Time: %@ (timestamp: %.0f)\n", self.bootTimeValue, [self.bootTimeValue timeIntervalSince1970]];
    // Try to get real uptime
    struct timeval boottv = {0};
    size_t sz = sizeof(boottv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    int sysctlResult = sysctl(mib, 2, &boottv, &sz, NULL, 0);
    if (sysctlResult == 0) {
        NSDate *realBoot = [NSDate dateWithTimeIntervalSince1970:boottv.tv_sec];
        NSTimeInterval realUptime = [[NSDate date] timeIntervalSinceDate:realBoot];
        [result appendFormat:@"Real Uptime: %.0f seconds (%.2f hours)\n", realUptime, realUptime/3600.0];
        [result appendFormat:@"Real Boot Time: %@ (timestamp: %.0f)\n", realBoot, [realBoot timeIntervalSince1970]];
    }
    [result appendFormat:@"Cache Time: %@\n", self.cacheTime];
    return result;
}

- (BOOL)validateBootTimeConsistencyForProfile:(NSString *)profilePath {
    if (!profilePath || [profilePath length] == 0) {
        return NO;
    }
    
    NSDate *bootTimeFromPlist = nil;
    NSTimeInterval bootTimeFromDeviceIds = 0;
    
    // Read boot time from boot_time.plist
    NSString *bootTimePath = [profilePath stringByAppendingPathComponent:@"boot_time.plist"];
    NSDictionary *bootTimeDict = [NSDictionary dictionaryWithContentsOfFile:bootTimePath];
    if (bootTimeDict && [bootTimeDict[@"value"] isKindOfClass:[NSDate class]]) {
        bootTimeFromPlist = bootTimeDict[@"value"];
    }
    
    // Read boot time from device_ids.plist
    NSString *deviceIdsPath = [profilePath stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
    if (deviceIds && deviceIds[@"BootTime"]) {
        bootTimeFromDeviceIds = [deviceIds[@"BootTime"] doubleValue];
    }
    
    // Check consistency (allow 1 second tolerance)
    if (bootTimeFromPlist && bootTimeFromDeviceIds > 0) {
        NSTimeInterval difference = fabs([bootTimeFromPlist timeIntervalSince1970] - bootTimeFromDeviceIds);
        BOOL isConsistent = difference <= 1.0;
        
        if (!isConsistent) {
            PXLog(@"[WeaponX] ⚠️ Boot time inconsistency detected in profile %@: plist=%.0f, device_ids=%.0f (diff=%.2f)", 
                  profilePath, [bootTimeFromPlist timeIntervalSince1970], bootTimeFromDeviceIds, difference);
        }
        
        return isConsistent;
    }
    
    return NO;
}

@end 