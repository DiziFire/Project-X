// IPStatusCacheManager.m
#import "IPStatusCacheManager.h"
#import "ProjectXLogging.h"
#import <UIKit/UIKit.h>

#define kMaxCacheCount 3
#define kIPStatusCacheKey @"IPStatusCache"
#define kIPStatusPlistPath @"/var/jb/var/mobile/Library/Preferences/com.weaponx.ipstatus.plist"

// Path helper for rootless jailbreak compatibility
static NSString *getIPLocationTimePlistPath() {
    NSString *rootPrefix = @"";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Check for rootless jailbreak
    if ([fileManager fileExistsAtPath:@"/var/jb"]) {
        rootPrefix = @"/var/jb";
    }
    
    NSString *basePath = [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences", rootPrefix];
    return [basePath stringByAppendingPathComponent:@"com.weaponx.iplocationtime.plist"];
}

@interface IPStatusCacheManager ()
@property (nonatomic, strong) NSMutableArray *cacheArray;
@end

@implementation IPStatusCacheManager

+ (instancetype)sharedManager {
    static IPStatusCacheManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadCacheFromDisk];
    }
    return self;
}

- (void)loadCacheFromDisk {
    @try {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:kIPStatusPlistPath]) {
            NSLog(@"[IPStatusCache] No plist file exists at %@", kIPStatusPlistPath);
            self.cacheArray = [NSMutableArray array];
            return;
        }

        // Try to load from the plist file
        NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:kIPStatusPlistPath];
        if (plistDict && plistDict[kIPStatusCacheKey]) {
            self.cacheArray = [plistDict[kIPStatusCacheKey] mutableCopy];
            NSLog(@"[IPStatusCache] Successfully loaded cache from plist file at %@", kIPStatusPlistPath);
            NSLog(@"[IPStatusCache] Loaded %lu entries from cache", (unsigned long)self.cacheArray.count);
        } else {
            // Initialize empty cache if file doesn't exist or doesn't have our key
            self.cacheArray = [NSMutableArray array];
            NSLog(@"[IPStatusCache] Initialized new cache array (no existing data found in plist)");
        }
    } @catch (NSException *exception) {
        NSLog(@"[IPStatusCache] Error loading cache from disk: %@", exception);
        self.cacheArray = [NSMutableArray array];
    }
}

- (void)saveCacheToDisk {
    @try {
        // Create a dictionary to store in the plist
        NSMutableDictionary *plistDict = [NSMutableDictionary dictionary];
        plistDict[kIPStatusCacheKey] = self.cacheArray;
        
        // Create the directory if it doesn't exist
        NSString *directory = [kIPStatusPlistPath stringByDeletingLastPathComponent];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        
        if (![fileManager fileExistsAtPath:directory]) {
            NSLog(@"[IPStatusCache] Creating directory at %@", directory);
            BOOL created = [fileManager createDirectoryAtPath:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                    error:&error];
            if (!created) {
                NSLog(@"[IPStatusCache] Failed to create directory: %@", error);
                return;
            }
        }
        
        // Write the plist
        NSError *writeError = nil;
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plistDict
                                                                     format:NSPropertyListXMLFormat_v1_0
                                                                    options:0
                                                                      error:&writeError];
        if (!plistData) {
            NSLog(@"[IPStatusCache] Failed to serialize plist: %@", writeError);
            return;
        }
        
        BOOL success = [plistData writeToFile:kIPStatusPlistPath atomically:YES];
        
        if (success) {
            NSLog(@"[IPStatusCache] Successfully saved cache to plist file at %@", kIPStatusPlistPath);
            NSLog(@"[IPStatusCache] Saved %lu entries to cache", (unsigned long)self.cacheArray.count);
        } else {
            NSLog(@"[IPStatusCache] Failed to write cache to plist file");
        }
    } @catch (NSException *exception) {
        NSLog(@"[IPStatusCache] Error saving cache to disk: %@", exception);
    }
}

- (NSDictionary *)loadLastIPStatus {
    if (self.cacheArray.count > 0) {
        NSDictionary *cached = self.cacheArray[0];
        NSLog(@"[IPStatusCache] Loaded last IP status from cache (count: %lu)", (unsigned long)self.cacheArray.count);
        return cached;
    }
    NSLog(@"[IPStatusCache] No cached IP status available");
    return nil;
}

- (NSDictionary *)cleanDictionaryForPlist:(NSDictionary *)dict {
    NSMutableDictionary *cleanDict = [NSMutableDictionary dictionary];
    
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSDictionary class]]) {
            // Recursively clean nested dictionaries
            cleanDict[key] = [self cleanDictionaryForPlist:obj];
        } else if ([obj isKindOfClass:[NSArray class]]) {
            // Clean arrays
            NSMutableArray *cleanArray = [NSMutableArray array];
            for (id item in obj) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [cleanArray addObject:[self cleanDictionaryForPlist:item]];
                } else if (![item isKindOfClass:[NSNull class]]) {
                    [cleanArray addObject:item];
                }
            }
            cleanDict[key] = cleanArray;
        } else if (![obj isKindOfClass:[NSNull class]]) {
            // Only add non-null values
            cleanDict[key] = obj;
        }
    }];
    
    return cleanDict;
}

- (void)saveIPStatus:(NSDictionary *)ipStatus {
    if (!ipStatus) {
        NSLog(@"[IPStatusCache] Cannot save nil IP status");
        return;
    }
    
    // Clean the dictionary before saving
    NSDictionary *cleanIPStatus = [self cleanDictionaryForPlist:ipStatus];
    
    // Insert at the beginning of the array
    [self.cacheArray insertObject:cleanIPStatus atIndex:0];
    
    // Remove excess entries if we exceed the maximum
    while (self.cacheArray.count > kMaxCacheCount) {
        [self.cacheArray removeLastObject];
    }
    
    // Save to disk
    [self saveCacheToDisk];
    
    NSLog(@"[IPStatusCache] Saved IP status to cache. Total cached: %lu", (unsigned long)self.cacheArray.count);
}

- (BOOL)isCacheValid {
    return (self.cacheArray && self.cacheArray.count > 0);
}

- (NSArray *)getAllCachedIPStatuses {
    return [self.cacheArray copy];
}

- (NSDictionary *)getIPStatusAtIndex:(NSInteger)index {
    if (index < self.cacheArray.count) {
        NSDictionary *dict = self.cacheArray[index];
        NSLog(@"[IPStatus] Loaded IP status with %lu top-level keys from cache (index: %ld)", (unsigned long)dict.count, (long)index);
        if (dict[@"scamalytics"]) {
            NSLog(@"[IPStatus] Loaded data includes scamalytics information");
        }
        if (dict[@"external_datasources"]) {
            NSLog(@"[IPStatus] Loaded data includes external datasources information");
        }
        return dict;
    }
    NSLog(@"[IPStatus] No cached IP status found at index %ld", (long)index);
    return nil;
}

- (NSInteger)getCacheCount {
    return self.cacheArray.count;
}

- (NSString *)cacheFilePathForIndex:(NSInteger)index {
    // This method now returns the path to the dedicated plist file
    NSLog(@"[IPStatusCache] Cache file path for index %ld: %@", (long)index, kIPStatusPlistPath);
    return kIPStatusPlistPath;
}

#pragma mark - IP and Location Time Management

+ (void)saveIPAndLocationData:(NSDictionary *)data {
    NSString *plistPath = getIPLocationTimePlistPath();
    
    // Create directory if it doesn't exist
    NSString *directory = [plistPath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:directory]) {
        NSError *dirError;
        [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&dirError];
        if (dirError) {
            PXLog(@"[WeaponX] ❌ Failed to create directory for iplocationtime.plist: %@", dirError);
            return;
        }
    }
    
    // Get existing data if available
    NSMutableDictionary *existingData = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath] ?: [NSMutableDictionary dictionary];
    
    // Update with new data
    [existingData addEntriesFromDictionary:data];
    
    // Save back to plist
    BOOL success = [existingData writeToFile:plistPath atomically:YES];
    if (success) {
        PXLog(@"[WeaponX] ✅ Successfully saved IP and location data to %@", plistPath);
    } else {
        PXLog(@"[WeaponX] ❌ Failed to save IP and location data to %@", plistPath);
    }
}

+ (NSDictionary *)loadIPAndLocationData {
    NSString *plistPath = getIPLocationTimePlistPath();
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    
    if (data) {
        PXLog(@"[WeaponX] ✅ Successfully loaded IP and location data from %@", plistPath);
    } else {
        PXLog(@"[WeaponX] ⚠️ No IP and location data found at %@", plistPath);
    }
    
    return data ?: @{};
}

+ (void)savePublicIP:(NSString *)ip countryCode:(NSString *)countryCode flagEmoji:(NSString *)flagEmoji timestamp:(NSDate *)timestamp {
    NSMutableDictionary *ipData = [NSMutableDictionary dictionary];
    
    // Format timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timeString = [formatter stringFromDate:timestamp ?: [NSDate date]];
    
    ipData[@"publicIP"] = ip ?: @"Unknown";
    ipData[@"ipCountryCode"] = countryCode ?: @"";
    ipData[@"ipFlagEmoji"] = flagEmoji ?: @"";
    ipData[@"ipTimestamp"] = timeString;
    ipData[@"ipTimestampRaw"] = @([[NSDate date] timeIntervalSince1970]);
    
    [self saveIPAndLocationData:ipData];
}

+ (void)savePinnedLocation:(CLLocationCoordinate2D)coordinates countryCode:(NSString *)countryCode flagEmoji:(NSString *)flagEmoji timestamp:(NSDate *)timestamp {
    NSMutableDictionary *locationData = [NSMutableDictionary dictionary];
    
    // Format timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timeString = [formatter stringFromDate:timestamp ?: [NSDate date]];
    
    locationData[@"latitude"] = @(coordinates.latitude);
    locationData[@"longitude"] = @(coordinates.longitude);
    locationData[@"locationCountryCode"] = countryCode ?: @"";
    locationData[@"locationFlagEmoji"] = flagEmoji ?: @"";
    locationData[@"locationTimestamp"] = timeString;
    locationData[@"locationTimestampRaw"] = @([[NSDate date] timeIntervalSince1970]);
    
    [self saveIPAndLocationData:locationData];
}

+ (NSDictionary *)getPublicIPData {
    NSDictionary *allData = [self loadIPAndLocationData];
    
    // Extract only IP-related data
    NSMutableDictionary *ipData = [NSMutableDictionary dictionary];
    NSArray *ipKeys = @[@"publicIP", @"ipCountryCode", @"ipFlagEmoji", @"ipTimestamp", @"ipTimestampRaw"];
    
    for (NSString *key in ipKeys) {
        if (allData[key]) {
            ipData[key] = allData[key];
        }
    }
    
    return ipData;
}

+ (NSDictionary *)getPinnedLocationData {
    NSDictionary *allData = [self loadIPAndLocationData];
    
    // Extract only location-related data
    NSMutableDictionary *locationData = [NSMutableDictionary dictionary];
    NSArray *locationKeys = @[@"latitude", @"longitude", @"locationCountryCode", 
                              @"locationFlagEmoji", @"locationTimestamp", @"locationTimestampRaw"];
    
    for (NSString *key in locationKeys) {
        if (allData[key]) {
            locationData[key] = allData[key];
        }
    }
    
    return locationData;
}

@end
