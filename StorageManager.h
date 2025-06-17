#import <Foundation/Foundation.h>

@interface StorageManager : NSObject

/**
 * Singleton access to the storage manager
 */
+ (instancetype)sharedManager;

#pragma mark - Storage Generation

/**
 * Generate realistic storage values for a given capacity
 * @param capacity The total capacity in GB (e.g. "64", "128", "256")
 * @return Dictionary with TotalStorage, FreeStorage, and FilesystemType
 */
- (NSDictionary *)generateStorageForCapacity:(NSString *)capacity;

/**
 * Randomly choose a realistic device capacity
 * @return String representation of capacity in GB (32, 64, 128, 256, 512, or 1024)
 */
- (NSString *)randomizeStorageCapacity;

#pragma mark - Basic Storage Values

/**
 * Get the total storage capacity as a string (in GB)
 */
- (NSString *)totalStorageCapacity;

/**
 * Get the free storage space as a string (in GB)
 */
- (NSString *)freeStorageSpace;

/**
 * Get the filesystem type (hex string, e.g. "0x1A" for APFS)
 */
- (NSString *)filesystemType;

#pragma mark - Advanced Storage Values

/**
 * Get total storage in bytes (binary units - 1024-based)
 */
- (uint64_t)totalStorageCapacityInBinaryBytes;

/**
 * Get total storage in bytes (marketing units - 1000-based)
 */
- (uint64_t)totalStorageCapacityInMarketingBytes;

/**
 * Get free storage in bytes (binary units - 1024-based)
 */
- (uint64_t)freeStorageSpaceInBinaryBytes;

/**
 * Get free storage in bytes (marketing units - 1000-based)
 */
- (uint64_t)freeStorageSpaceInMarketingBytes;

/**
 * Get normalized total storage bytes for app display
 * @param useMarketingUnits YES to use 1000-based units, NO for 1024-based
 * @return Storage size in bytes
 */
- (uint64_t)normalizedTotalStorageForDisplay:(BOOL)useMarketingUnits;

/**
 * Get normalized free storage bytes for app display
 * @param useMarketingUnits YES to use 1000-based units, NO for 1024-based
 * @return Storage size in bytes
 */
- (uint64_t)normalizedFreeStorageForDisplay:(BOOL)useMarketingUnits;

#pragma mark - Storage Settings

/**
 * Set the total storage capacity
 * @param capacity String representation of capacity in GB
 */
- (void)setTotalStorageCapacity:(NSString *)capacity;

/**
 * Set the free storage space
 * @param freeSpace String representation of free space in GB
 */
- (void)setFreeStorageSpace:(NSString *)freeSpace;

/**
 * Set the filesystem type
 * @param fsType Hex string representing filesystem type
 */
- (void)setFilesystemType:(NSString *)fsType;

#pragma mark - Profile Management

/**
 * Save storage settings to a specific profile
 * @param profileId The profile ID to save to
 */
- (void)saveToProfile:(NSString *)profileId;

/**
 * Load storage settings from a specific profile
 * @param profileId The profile ID to load from
 * @return YES if settings were loaded, NO if defaults were used
 */
- (BOOL)loadFromProfile:(NSString *)profileId;

/**
 * Save settings to current active profile
 */
- (void)saveToCurrentProfile;

#pragma mark - Status Control

/**
 * Check if storage spoofing is enabled
 * @return YES if enabled, NO otherwise
 */
- (BOOL)isStorageSpoofingEnabled;

/**
 * Enable or disable storage spoofing
 * @param enabled YES to enable, NO to disable
 */
- (void)setStorageSpoofingEnabled:(BOOL)enabled;

@end
