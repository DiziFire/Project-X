#import "StorageManager.h"
#import "ProfileManager.h"
#import "ProjectXLogging.h"

// Constants for proper size calculations
// Use only marketing units (1000-based) as used by Apple
#define BYTES_PER_KB (1000ULL)
#define BYTES_PER_MB (1000ULL * 1000ULL)
#define BYTES_PER_GB (1000ULL * 1000ULL * 1000ULL)
#define BYTES_PER_TB (1000ULL * 1000ULL * 1000ULL * 1000ULL)

// Standard APFS block size
#define DEFAULT_BLOCK_SIZE (4096ULL)

@implementation StorageManager {
    NSMutableDictionary *_storageSettings;
    BOOL _isEnabled;
}

+ (instancetype)sharedManager {
    static StorageManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _storageSettings = [NSMutableDictionary dictionary];
        
        // Load from settings
        NSUserDefaults *defaults = [[NSUserDefaults alloc] 
                                   initWithSuiteName:@"com.hydra.projectx.settings"];
        _isEnabled = [defaults boolForKey:@"StorageSystemEnabled"];
        
        // Load current profile
        [self loadFromCurrentProfile];
    }
    return self;
}

- (void)loadFromCurrentProfile {
    // Get active profile ID
    NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *currentProfileInfo = [NSDictionary dictionaryWithContentsOfFile:profilesPath];
    
    if (currentProfileInfo && currentProfileInfo[@"ProfileId"]) {
        NSString *profileId = currentProfileInfo[@"ProfileId"];
        [self loadFromProfile:profileId];
    } else {
        // Default values if no profile
        [self setDefaultStorage];
    }
}

- (void)setDefaultStorage {
    // Use the storage generation method to ensure consistent values
    NSString *capacity = [self randomizeStorageCapacity];
    NSDictionary *storageInfo = [self generateStorageForCapacity:capacity];
    
    _storageSettings[@"TotalStorage"] = storageInfo[@"TotalStorage"];
    _storageSettings[@"FreeStorage"] = storageInfo[@"FreeStorage"];
    _storageSettings[@"FilesystemType"] = storageInfo[@"FilesystemType"];
}

- (NSString *)randomizeStorageCapacity {
    // 50% chance for 64GB, 50% for 128GB
    int randomValue = arc4random_uniform(100);
    NSString *capacity;
    if (randomValue < 50) {
        capacity = @"64";
    } else {
        capacity = @"128";
    }
    return capacity;
}

- (NSDictionary *)generateStorageForCapacity:(NSString *)capacity {
    NSMutableDictionary *storage = [NSMutableDictionary dictionary];
    
    double totalGB = [capacity doubleValue];
    double freePercent;
    
    // Calculate realistic free space based on capacity
    if (totalGB <= 32) {
        // 64GB devices typically have less free space (15-30%)
        freePercent = (arc4random_uniform(15) + 15) / 100.0;
    } else {
        // 128GB devices (25-40%)
        freePercent = (arc4random_uniform(15) + 25) / 100.0;
    }
    
    double freeGB = totalGB * freePercent;
    
    // Add some variability to the decimal points
    double decimalVariation = (arc4random_uniform(10) / 10.0);
    freeGB = freeGB + decimalVariation;
    
    // Round to one decimal place
    freeGB = round(freeGB * 10) / 10;
    
    storage[@"TotalStorage"] = capacity;
    storage[@"FreeStorage"] = [NSString stringWithFormat:@"%.1f", freeGB];
    storage[@"FilesystemType"] = @"0x1A"; // APFS for modern iOS
    
    return storage;
}

#pragma mark - Basic Storage Values

- (NSString *)totalStorageCapacity {
    return _storageSettings[@"TotalStorage"];
}

- (NSString *)freeStorageSpace {
    // Get the base free space
    NSString *baseSpace = _storageSettings[@"FreeStorage"];
    
    // Return the exact value without random variations to ensure consistency
    return baseSpace;
}

- (NSString *)filesystemType {
    return _storageSettings[@"FilesystemType"];
}

#pragma mark - Advanced Storage Values

- (uint64_t)totalStorageCapacityInBinaryBytes {
    // For backward compatibility, convert using marketing units
    NSString *totalGB = [self totalStorageCapacity];
    return [self convertGBStringToBytes:totalGB];
}

- (uint64_t)totalStorageCapacityInMarketingBytes {
    NSString *totalGB = [self totalStorageCapacity];
    return [self convertGBStringToBytes:totalGB];
}

- (uint64_t)freeStorageSpaceInBinaryBytes {
    // For backward compatibility, convert using marketing units
    NSString *freeGB = [self freeStorageSpace];
    return [self convertGBStringToBytes:freeGB];
}

- (uint64_t)freeStorageSpaceInMarketingBytes {
    NSString *freeGB = [self freeStorageSpace];
    return [self convertGBStringToBytes:freeGB];
}

- (uint64_t)normalizedTotalStorageForDisplay:(BOOL)useMarketingUnits {
    // useMarketingUnits parameter kept for backward compatibility
    uint64_t rawBytes = [self totalStorageCapacityInMarketingBytes];
    return [self normalizeStorageBytes:rawBytes];
}

- (uint64_t)normalizedFreeStorageForDisplay:(BOOL)useMarketingUnits {
    // useMarketingUnits parameter kept for backward compatibility
    return [self freeStorageSpaceInMarketingBytes];
}

#pragma mark - Unit Conversion Helpers

- (uint64_t)convertGBStringToBytes:(NSString *)gbString {
    if (!gbString) return 0;
    
    double gbValue = [gbString doubleValue];
    if (gbValue <= 0) return 0;
    
    // Use only marketing (1000-based) conversion
    return (uint64_t)(gbValue * BYTES_PER_GB);
}

- (uint64_t)normalizeStorageBytes:(uint64_t)bytes {
    if (bytes == 0) return 0;
    
    // For user-facing displays, iOS rounds to nice numbers
    // System capacity is often shown as 64GB, 128GB, etc.
    
    // Get the GB value
    double gbValue = (double)bytes / BYTES_PER_GB;
    
    // Round to nearest common capacity
    if (gbValue > 1000) {
        // For 1TB+ devices, round to nearest 128GB
        gbValue = round(gbValue / 128.0) * 128.0;
    } else if (gbValue > 500) {
        // For 512GB devices, round to nearest 64GB
        gbValue = round(gbValue / 64.0) * 64.0;
    } else if (gbValue > 200) {
        // For 256GB devices, round to nearest 64GB
        gbValue = round(gbValue / 32.0) * 32.0;
    } else if (gbValue > 100) {
        // For 128GB devices, round to nearest 16GB
        gbValue = round(gbValue / 16.0) * 16.0;
    } else if (gbValue > 50) {
        // For 64GB devices, round to nearest 8GB
        gbValue = round(gbValue / 8.0) * 8.0;
    } else {
        // For 64GB devices, round to nearest 4GB
        gbValue = round(gbValue / 4.0) * 4.0;
    }
    
    // Convert back to bytes
    return (uint64_t)(gbValue * BYTES_PER_GB);
}

// For backward compatibility - these methods are kept but simplified
- (uint64_t)convertGBStringToBytes:(NSString *)gbString useBinaryUnits:(BOOL)useBinary {
    return [self convertGBStringToBytes:gbString];
}

- (uint64_t)normalizeStorageBytes:(uint64_t)bytes useMarketingUnits:(BOOL)useMarketingUnits {
    return [self normalizeStorageBytes:bytes];
}

#pragma mark - Storage Settings

- (void)setTotalStorageCapacity:(NSString *)capacity {
    _storageSettings[@"TotalStorage"] = capacity;
    [self saveToCurrentProfile];
}

- (void)setFreeStorageSpace:(NSString *)freeSpace {
    _storageSettings[@"FreeStorage"] = freeSpace;
    [self saveToCurrentProfile];
}

- (void)setFilesystemType:(NSString *)fsType {
    _storageSettings[@"FilesystemType"] = fsType;
    [self saveToCurrentProfile];
}

#pragma mark - Profile Management

- (void)saveToCurrentProfile {
    // Get active profile ID
    NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *currentProfileInfo = [NSDictionary dictionaryWithContentsOfFile:profilesPath];
    
    if (currentProfileInfo && currentProfileInfo[@"ProfileId"]) {
        NSString *profileId = currentProfileInfo[@"ProfileId"];
        [self saveToProfile:profileId];
    }
}

- (void)saveToProfile:(NSString *)profileId {
    if (!profileId) return;
    
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *storagePath = [profileDir stringByAppendingPathComponent:@"storage.plist"];
    
    [_storageSettings writeToFile:storagePath atomically:YES];
}

- (BOOL)loadFromProfile:(NSString *)profileId {
    if (!profileId) return NO;
    
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *storagePath = [profileDir stringByAppendingPathComponent:@"storage.plist"];
    
    NSDictionary *savedSettings = [NSDictionary dictionaryWithContentsOfFile:storagePath];
    if (savedSettings) {
        [_storageSettings removeAllObjects];
        [_storageSettings addEntriesFromDictionary:savedSettings];
        return YES;
    }
    
    // If no saved settings, use defaults
    [self setDefaultStorage];
    return NO;
}

#pragma mark - Status Control

- (BOOL)isStorageSpoofingEnabled {
    return _isEnabled;
}

- (void)setStorageSpoofingEnabled:(BOOL)enabled {
    _isEnabled = enabled;
    
    // Save to settings
    NSUserDefaults *defaults = [[NSUserDefaults alloc] 
                               initWithSuiteName:@"com.hydra.projectx.settings"];
    [defaults setBool:enabled forKey:@"StorageSystemEnabled"];
    [defaults synchronize];
}

@end
