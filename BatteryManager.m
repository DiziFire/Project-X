#import "BatteryManager.h"
#import "ProjectXLogging.h"

// Define file paths
#define BATTERY_PLIST_PATH @"/var/jb/var/mobile/Library/Preferences/com.weaponx.battery.plist"
#define kBatteryLevelKey @"BatteryLevel"
#define kLastUpdatedKey @"LastUpdated"

@interface BatteryManager ()
@property (nonatomic, strong) NSString *currentBatteryLevel;
@property (nonatomic, strong) NSError *error;
@end

@implementation BatteryManager

// Singleton pattern
static BatteryManager *sharedManager = nil;

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[BatteryManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize with actual device battery level as default
        _currentBatteryLevel = [NSString stringWithFormat:@"%.2f", [[UIDevice currentDevice] batteryLevel]];
        
        // Enable battery monitoring to ensure we can get the battery level
        [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
        
        // Load saved battery info
        [self loadBatteryInfoFromDisk];
    }
    return self;
}

#pragma mark - Battery Level

- (NSString *)batteryLevel {
    // First try to load from disk in case another process updated it
    [self loadBatteryInfoFromDisk];
    
    // If we don't have a value yet, generate one
    if (!_currentBatteryLevel || _currentBatteryLevel.length == 0) {
        _currentBatteryLevel = [self generateBatteryLevel];
        
        // Save the generated value
        [self saveBatteryInfoToDisk];
    }
    
    // Validate the value is within range
    float storedLevel = [_currentBatteryLevel floatValue];
    if (storedLevel < 0.01 || storedLevel > 1.0) {
        // Fix invalid values
        PXLog(@"[WeaponX] ⚠️ Fixing invalid battery level: %@", _currentBatteryLevel);
        _currentBatteryLevel = [self generateBatteryLevel];
        [self saveBatteryInfoToDisk];
    }
    
    return _currentBatteryLevel;
}

- (void)setBatteryLevel:(NSString *)level {
    _currentBatteryLevel = level;
    
    // Persist changes to disk
    [self saveBatteryInfoToDisk];
}

- (NSString *)generateBatteryLevel {
    // Generate a random battery level between 0.05 (5%) and 1.0 (100%)
    return [self randomizeBatteryLevel];
}

- (NSString *)randomizeBatteryLevel {
    // Algorithm for realistic battery level distribution:
    // - 60% chance of battery level between 30-80%
    // - 20% chance of battery level between 80-100%
    // - 15% chance of battery level between 15-30%
    // - 5% chance of battery level between 5-15%
    
    int randomValue = arc4random_uniform(100);
    float level;
    
    if (randomValue < 60) {
        // 30-80% range (most common)
        level = (30 + arc4random_uniform(51)) / 100.0f;
    } else if (randomValue < 80) {
        // 80-100% range (fully charged state)
        level = (80 + arc4random_uniform(21)) / 100.0f;
    } else if (randomValue < 95) {
        // 15-30% range (low battery state)
        level = (15 + arc4random_uniform(16)) / 100.0f;
    } else {
        // 5-15% range (battery danger zone)
        level = (5 + arc4random_uniform(11)) / 100.0f;
    }
    
    // Format with 2 decimal places
    NSString *levelStr = [NSString stringWithFormat:@"%.2f", level];
    
    PXLog(@"[WeaponX] 🔋 Randomized battery level: %@ (%d%%)",
          levelStr, (int)(level * 100));
    
    // Update our storage
    _currentBatteryLevel = levelStr;
    
    // Save the change
    [self saveBatteryInfoToDisk];
    
    return levelStr;
}

// Generate comprehensive battery info for UI display
- (NSDictionary *)generateBatteryInfo {
    // Generate battery level first
    NSString *batteryLevel = [self randomizeBatteryLevel];
    
    // Store the values
    _currentBatteryLevel = batteryLevel;
    
    // Create a dictionary with all battery info
    NSDictionary *batteryInfo = @{
        @"BatteryLevel": batteryLevel,
        @"BatteryPercentage": @((int)([batteryLevel floatValue] * 100)),
    };
    
    // Save to disk
    [self saveBatteryInfoToDisk];
    
    // Notify listeners about the change
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BatteryInfoUpdated"
                                                      object:self
                                                    userInfo:batteryInfo];
    
    // Also post CF notification for tweak hooks
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.hydra.projectx.battery.updated"),
        NULL,
        (__bridge CFDictionaryRef)batteryInfo,
        YES
    );
    
    return batteryInfo;
}

#pragma mark - Error Handling

// Return the last error that occurred
- (NSError *)lastError {
    return _error;
}

#pragma mark - File Operations

// Private helper to get the path to profile-specific battery_info.plist
- (NSString *)batteryInfoPathForCurrentProfile {
    // First try to get active profile ID
    NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *currentProfileInfo = [NSDictionary dictionaryWithContentsOfFile:profilesPath];
    NSString *profileId = currentProfileInfo[@"ProfileId"];
    
    if (!profileId) {
        _error = [NSError errorWithDomain:@"com.weaponx.BatteryManager"
                                     code:100
                                 userInfo:@{NSLocalizedDescriptionKey: @"No active profile found"}];
        PXLog(@"[WeaponX] ⚠️ Error: No active profile when getting identity path in BatteryManager");
        return nil;
    }
    
    // Use the profile ID to build the path to the identity directory
    NSString *identityDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    
    // Return the path to the battery_info.plist in this profile
    return [identityDir stringByAppendingPathComponent:@"battery_info.plist"];
}

// Load battery values from disk
- (void)loadBatteryInfoFromDisk {
    // First try to load from profile-specific plist
    NSString *profileBatteryPath = [self batteryInfoPathForCurrentProfile];
    if (profileBatteryPath) {
        NSDictionary *batteryInfo = [NSDictionary dictionaryWithContentsOfFile:profileBatteryPath];
        if (batteryInfo && batteryInfo[kBatteryLevelKey]) {
            _currentBatteryLevel = batteryInfo[kBatteryLevelKey];
            return;
        }
    }
    
    // If profile-specific load failed, try global plist
    NSDictionary *batteryInfo = [NSDictionary dictionaryWithContentsOfFile:BATTERY_PLIST_PATH];
    if (batteryInfo) {
        // Extract the values we need
        _currentBatteryLevel = batteryInfo[kBatteryLevelKey] ?: _currentBatteryLevel;
    }
}

// Save battery values to disk (both global and profile-specific)
- (void)saveBatteryInfoToDisk {
    // Basic validation
    if (!_currentBatteryLevel) {
        return;
    }
    
    @try {
        // First save to the global battery plist
        NSMutableDictionary *batteryInfo = [NSMutableDictionary dictionary];
        batteryInfo[kBatteryLevelKey] = _currentBatteryLevel;
        batteryInfo[kLastUpdatedKey] = [NSDate date];
        
        // Create the directory if it doesn't exist
        NSString *directory = [BATTERY_PLIST_PATH stringByDeletingLastPathComponent];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        if (![fileManager fileExistsAtPath:directory]) {
            [fileManager createDirectoryAtPath:directory
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:nil];
        }
        
        // Write the plist
        [batteryInfo writeToFile:BATTERY_PLIST_PATH atomically:YES];
        
        PXLog(@"[WeaponX] 🔋 Saved battery info to global plist: %@%%",
              @([_currentBatteryLevel floatValue] * 100));
    }
    @catch (NSException *exception) {
        // Log the error but don't crash
        PXLog(@"[WeaponX] ⚠️ Error saving battery info: %@", exception);
    }
    
    // Now also save to the profile-specific plist
    NSString *batteryInfoPath = [self batteryInfoPathForCurrentProfile];
    if (batteryInfoPath) {
        @try {
            // Create the directory if needed
            NSString *identityDir = [batteryInfoPath stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:identityDir
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:nil];
            
            // Build the path to the battery info plist
            
            // Prepare the battery info dictionary
            NSMutableDictionary *batteryInfo = [NSMutableDictionary dictionary];
            batteryInfo[kBatteryLevelKey] = _currentBatteryLevel ?: @"0.75";
            batteryInfo[kLastUpdatedKey] = [NSDate date];
            
            // Write to the plist file
            [batteryInfo writeToFile:batteryInfoPath atomically:YES];
            
            // Also update device_ids.plist for the profile if it exists
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSMutableDictionary *deviceIds = [[NSMutableDictionary alloc] initWithContentsOfFile:deviceIdsPath];
            if (deviceIds) {
                // Update the battery values in device_ids.plist
                deviceIds[kBatteryLevelKey] = _currentBatteryLevel;
                [deviceIds writeToFile:deviceIdsPath atomically:YES];
            }
        }
        @catch (NSException *exception) {
            PXLog(@"[WeaponX] ⚠️ Error saving profile battery info: %@", exception);
        }
    }
}

@end 