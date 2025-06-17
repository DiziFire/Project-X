#import "ProjectX.h"
#import "IdentifierManager.h"
#import "StorageManager.h"
#import "ProjectXLogging.h"
#import "InlineHook.h"
#import <Foundation/Foundation.h>
#import <sys/mount.h>
#import <dlfcn.h>
#import <ellekit/ellekit.h>
#import <IOKit/IOKitLib.h>
#import <execinfo.h>
#import <mach-o/dyld.h>

// Constants for proper size calculations - use only marketing units (1000-based)
#define BYTES_PER_KB (1000ULL)
#define BYTES_PER_MB (1000ULL * 1000ULL)
#define BYTES_PER_GB (1000ULL * 1000ULL * 1000ULL)
#define BYTES_PER_TB (1000ULL * 1000ULL * 1000ULL * 1000ULL)

// Binary units for compensation calculations
#define BYTES_PER_KB_BINARY (1024ULL)
#define BYTES_PER_MB_BINARY (1024ULL * 1024ULL)
#define BYTES_PER_GB_BINARY (1024ULL * 1024ULL * 1024ULL)
#define BYTES_PER_TB_BINARY (1024ULL * 1024ULL * 1024ULL * 1024ULL)

// Compensation factor for technical apps (binary/marketing ratio)
#define BINARY_COMPENSATION_FACTOR (BYTES_PER_GB_BINARY / (double)BYTES_PER_GB)

// Define standard capacities in GB that we want to display correctly
#define CAPACITY_64GB  32
#define CAPACITY_128GB 128

// Standard APFS block size
#define DEFAULT_BLOCK_SIZE (4096ULL)

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// IOKit function pointer
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);

// Forward declarations
static NSString *getCurrentBundleID(void);
static NSDictionary *loadScopedApps(void);
static BOOL isInScopedAppsList(void);

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
                PXLog(@"[StorageHooks] Could not find scoped apps file");
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

// Helper function to get consistent storage values directly from storage.plist
static NSDictionary *getStorageValues() {
    static NSDictionary *cachedStorageValues = nil;
    static NSTimeInterval lastLoadTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    // Increased cache duration from 5 to 30 seconds to reduce I/O and CPU overhead
    if (cachedStorageValues && (now - lastLoadTime < 30.0)) {
        return cachedStorageValues;
    }
    
    // First check if the feature is globally enabled
    BOOL storageSystemEnabled = NO;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.settings"];
    if (defaults) {
        storageSystemEnabled = [defaults boolForKey:@"StorageSystemEnabled"];
    }
    
    if (!storageSystemEnabled && NSClassFromString(@"IdentifierManager")) {
        id manager = [NSClassFromString(@"IdentifierManager") sharedManager];
        if (manager && [manager respondsToSelector:@selector(isIdentifierEnabled:)]) {
            storageSystemEnabled = [manager isIdentifierEnabled:@"StorageSystem"];
        }
    }
    
    // If feature is disabled globally, return nil to abort spoofing
    if (!storageSystemEnabled) {
        return nil;
    }
    
    @try {
        // First try to get active profile ID
        NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
        NSDictionary *currentProfileInfo = [NSDictionary dictionaryWithContentsOfFile:profilesPath];
        NSString *profileId = currentProfileInfo[@"ProfileId"];
        
        if (profileId) {
            // Build path to storage.plist for this profile
            NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
            NSString *storagePath = [profileDir stringByAppendingPathComponent:@"storage.plist"];
            
            // Try to load values from storage.plist
            NSDictionary *storageDict = [NSDictionary dictionaryWithContentsOfFile:storagePath];
            if (storageDict && storageDict[@"TotalStorage"] && storageDict[@"FreeStorage"]) {
                cachedStorageValues = [storageDict copy];
                lastLoadTime = now;
                return cachedStorageValues;
            }
        }
        
        // Fallback to StorageManager if plist not found
        StorageManager *storageManager = [%c(StorageManager) sharedManager];
        if (storageManager) {
            NSString *totalStorage = [storageManager totalStorageCapacity];
            NSString *freeStorage = [storageManager freeStorageSpace];
            
            if (totalStorage && freeStorage) {
                cachedStorageValues = @{
                    @"TotalStorage": totalStorage,
                    @"FreeStorage": freeStorage
                };
                lastLoadTime = now;
                return cachedStorageValues;
            }
        }
    } @catch (NSException *exception) {
        // If any error occurs, use default values
    }
    
    // Final fallback
    cachedStorageValues = @{
        @"TotalStorage": @"128",
        @"FreeStorage": @"38.4"
    };
    lastLoadTime = now;
    return cachedStorageValues;
}

// Helper to convert GB string to bytes using marketing units (1000-based)
static uint64_t __attribute__((unused)) convertGBStringToBytes(NSString *gbString) {
    if (!gbString) return 0;
    
    double gbValue = [gbString doubleValue];
    if (gbValue <= 0) return 0;
    
    // Use marketing units (1000-based)
    return (uint64_t)(gbValue * BYTES_PER_GB);
}

// Helper function to normalize byte values to match what iOS would display
// This ensures consistent representation regardless of how the app reads the data
static uint64_t __attribute__((unused)) normalizeStorageBytes(uint64_t bytes) {
    if (bytes == 0) return 0;
    
    // Get the GB value using marketing units
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

// Helper to calculate block count from bytes and block size
static uint64_t calculateBlockCount(uint64_t bytes, uint32_t blockSize) {
    if (blockSize == 0) {
        // Default to 4K blocks if block size is zero (shouldn't happen, but safety first)
        blockSize = DEFAULT_BLOCK_SIZE;
    }
    
    // Calculate block count, rounding up for partial blocks
    return (bytes + blockSize - 1) / blockSize;
}

// Helper function to check if storage spoofing should be applied
// This centralizes the bundleID checks to avoid repeating them in every hook
static BOOL shouldApplyStorageSpoofing() {
    static NSMutableDictionary *cachedDecisions = nil;
    static NSTimeInterval lastCleanupTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes in seconds
    
    // Initialize cache if needed
    if (!cachedDecisions) {
        cachedDecisions = [NSMutableDictionary dictionary];
    }
    
    // Clean cache every 5 minutes to prevent memory growth
    if (now - lastCleanupTime > kCacheValidityDuration) {
        [cachedDecisions removeAllObjects];
        lastCleanupTime = now;
    }
    
    // Get current bundle ID
    NSString *currentBundleID = getCurrentBundleID();
    if (!currentBundleID || [currentBundleID length] == 0) {
        return NO;
    }
    
    // Check if we have a cached decision for this bundle ID with a valid timestamp
    NSNumber *cachedDecision = cachedDecisions[currentBundleID];
    NSDate *decisionTimestamp = cachedDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]];
        
    if (cachedDecision && decisionTimestamp && 
        [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
        return [cachedDecision boolValue];
    }
    
    // Always exclude system processes and critical system apps
    if ([currentBundleID hasPrefix:@"com.apple."] && 
        ![currentBundleID isEqualToString:@"com.apple.mobilesafari"] &&
        ![currentBundleID isEqualToString:@"com.apple.webapp"]) {
        
        // Cache the negative decision with timestamp
        cachedDecisions[currentBundleID] = @NO;
        cachedDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
        return NO;
    }
    
    // Exclude our own apps
    if ([currentBundleID isEqualToString:@"com.hydra.projectx"] || 
        [currentBundleID isEqualToString:@"com.hydra.weaponx"]) {
        cachedDecisions[currentBundleID] = @NO;
        cachedDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
        return NO;
    }
    
    // Additional blacklist for known problematic apps
    NSArray *problematicApps = @[
        @"com.toyopagroup.picaboo",    // Snapchat 
        @"com.atebits.Tweetie2",       // Twitter/X
        @"com.zhiliaoapp.musically",   // TikTok
        @"net.whatsapp.WhatsApp",      // WhatsApp
        @"ph.telegra.Telegraph",       // Telegram 
        @"ph.telegra.Telegraph.NotificationService", 
        @"ph.telegra.Telegraph.NotificationContent",
        @"com.skype.skype",
        @"com.hammerandchisel.discord",
        @"com.burbn.instagram",        // Instagram
        @"com.facebook.Facebook"       // Facebook
    ];
    
    if ([problematicApps containsObject:currentBundleID]) {
        // Cache the negative decision with timestamp
        cachedDecisions[currentBundleID] = @NO;
        cachedDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
        return NO;
    }
    
    // Check if the current app is a scoped app
    BOOL isScoped = isInScopedAppsList();
    
    // Cache the decision with timestamp
    cachedDecisions[currentBundleID] = @(isScoped);
    cachedDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    
    return isScoped;
}

// Function to get storage values with universal compatibility
static void getStorageValuesForApp(uint64_t *totalBytes, uint64_t *freeBytes) {
    if (!totalBytes || !freeBytes) return;
    
    // Initialize with zeros
    *totalBytes = 0;
    *freeBytes = 0;
    
    @try {
        // Get storage values from plist
        NSDictionary *storageInfo = getStorageValues();
        if (!storageInfo) return;
        
        // Get total storage value as string
        NSString *totalSpaceStr = storageInfo[@"TotalStorage"];
        if (!totalSpaceStr || [totalSpaceStr length] == 0) return;
        
        // Convert to numeric value
        double totalStorageGB = [totalSpaceStr doubleValue];
        if (totalStorageGB <= 0) return;
        
        // Get app info for detection
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        NSString *executablePath = [[NSBundle mainBundle] executablePath] ?: @"";
        NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: 
                           [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"";
        
        // Special app handling flags
        BOOL isSettingsApp = NO;
        BOOL isTechnicalApp = NO;
        
        // Check for Settings app or any settings-related UI
        if ([currentBundleID isEqualToString:@"com.apple.Preferences"] ||
            [executablePath containsString:@"Settings"] ||
            [executablePath containsString:@"Preferences"] ||
            [appName containsString:@"Settings"]) {
            isSettingsApp = YES;
        }
        
        // Check for technical apps that need binary values
        if ([executablePath containsString:@"DiskUsage"] || 
            [executablePath containsString:@"Storage"] || 
            [executablePath containsString:@"FileManager"] ||
            [executablePath containsString:@"SystemInfo"] ||
            [currentBundleID containsString:@"disk"] ||
            [currentBundleID containsString:@"storage"] ||
            [currentBundleID containsString:@"system.info"] ||
            [appName containsString:@"Storage"] ||
            [appName containsString:@"Disk"]) {
            isTechnicalApp = YES;
        }
        
        // Standard capacity values
        uint64_t size64GB_Marketing = 64ULL * BYTES_PER_GB;       // 64,000,000,000 bytes
        uint64_t size64GB_Binary = 64ULL * BYTES_PER_GB_BINARY;   // 68,719,476,736 bytes
        uint64_t size64GB_Settings = 59ULL * BYTES_PER_GB;        // ~59 GB (what Settings shows)
        uint64_t size128GB_Marketing = 128ULL * BYTES_PER_GB;     // 128,000,000,000 bytes 
        uint64_t size128GB_Binary = 128ULL * BYTES_PER_GB_BINARY; // 137,438,953,472 bytes
        uint64_t size128GB_Settings = 119ULL * BYTES_PER_GB;      // ~119 GB (what Settings shows)
        // Determine storage capacity based on device model and app type
        uint64_t storageCapacity = 0;
        if (fabs(totalStorageGB - 64) < 1.0) {
            // 64GB device
            if (isTechnicalApp) {
                storageCapacity = size64GB_Binary;
            } else if (isSettingsApp) {
                storageCapacity = size64GB_Settings;
            } else {
                storageCapacity = size64GB_Marketing;
            }
        } else if (fabs(totalStorageGB - 128) < 1.0) {
            // 128GB device
            if (isTechnicalApp) {
                storageCapacity = size128GB_Binary;
            } else if (isSettingsApp) {
                storageCapacity = size128GB_Settings;
            } else {
                storageCapacity = size128GB_Marketing;
            }
        } else {
            // Custom size
            if (isTechnicalApp) {
                storageCapacity = (uint64_t)(totalStorageGB * BYTES_PER_GB_BINARY);
            } else if (isSettingsApp) {
                storageCapacity = (uint64_t)(totalStorageGB * BYTES_PER_GB * 0.93);
            } else {
                storageCapacity = (uint64_t)(totalStorageGB * BYTES_PER_GB);
            }
        }
        
        // Set total bytes
        *totalBytes = storageCapacity;
        
        // Calculate free space based on percentage
        NSString *freeSpaceStr = storageInfo[@"FreeStorage"];
        if (freeSpaceStr && [freeSpaceStr length] > 0) {
            double freeGbValue = [freeSpaceStr doubleValue];
            if (freeGbValue >= 0 && freeGbValue <= totalStorageGB) {
                // Apply the free space as a percentage of total
                double freePercent = freeGbValue / totalStorageGB;
                *freeBytes = (uint64_t)(*totalBytes * freePercent);
            }
        }
    } @catch (NSException *exception) {
        // If any error occurs, use safe defaults (marketing units for consistency)
        *totalBytes = 128ULL * BYTES_PER_GB;
        *freeBytes = 38ULL * BYTES_PER_GB;
    }
}

// Define struct statfs64 if not defined
#ifndef HAVE_STATFS64
struct statfs64 {
    uint32_t    f_type;     /* type of filesystem */
    uint32_t    f_bsize;    /* optimal transfer block size */
    uint64_t    f_blocks;   /* total data blocks in file system */
    uint64_t    f_bfree;    /* free blocks in fs */
    uint64_t    f_bavail;   /* free blocks avail to non-superuser */
    uint64_t    f_files;    /* total file nodes in file system */
    uint64_t    f_ffree;    /* free file nodes in fs */
    fsid_t      f_fsid;     /* file system id */
    uint32_t    f_flags;    /* mount flags */
    uint32_t    f_namelen;  /* maximum length of filenames */
    char        f_fstypename[MFSNAMELEN]; /* fs type name */
    char        f_mntonname[MNAMELEN];    /* directory on which mounted */
    char        f_mntfromname[MNAMELEN];  /* mounted filesystem */
};
#endif

// Define NSFileSystem constants as strings since they're just string constants
#define NSFileSystemSize @"NSFileSystemSize"
#define NSFileSystemFreeSize @"NSFileSystemFreeSize"
#define NSFileSystemFreeNodes @"NSFileSystemFreeNodes"
#define NSFileSystemFreeOperationCount @"NSFileSystemFreeOperationCount"

// Function pointer for statfs
static int (*orig_statfs)(const char *path, struct statfs *buf);

// Function pointer for statfs64 (64-bit variant)
static int (*orig_statfs64)(const char *path, struct statfs64 *buf);

// Function pointer for getfsstat
static int (*orig_getfsstat)(struct statfs *buf, int bufsize, int flags);

// Function pointer for getfsstat64
static int (*orig_getfsstat64)(struct statfs64 *buf, int bufsize, int flags);

// Helper to modify statfs struct with spoofed values
static void modifyStatfsWithSpoofedValues(struct statfs *buf) {
    if (!buf) return;
    
    // Ensure block size is valid
    if (buf->f_bsize == 0) {
        buf->f_bsize = DEFAULT_BLOCK_SIZE; // Standard block size for APFS
    }
    
    // Get storage values with appropriate units for this app
    uint64_t totalBytes, freeBytes;
    getStorageValuesForApp(&totalBytes, &freeBytes);
    
    // Calculate blocks
    if (totalBytes > 0) {
        buf->f_blocks = calculateBlockCount(totalBytes, buf->f_bsize);
    }
    
    if (freeBytes > 0) {
        buf->f_bfree = calculateBlockCount(freeBytes, buf->f_bsize);
        buf->f_bavail = buf->f_bfree; // Available blocks = free blocks for non-root
    }
}

// Helper to modify statfs64 struct with spoofed values
static void modifyStatfs64WithSpoofedValues(struct statfs64 *buf) {
    if (!buf) return;
    
    // Ensure block size is valid
    if (buf->f_bsize == 0) {
        buf->f_bsize = DEFAULT_BLOCK_SIZE; // Standard block size for APFS
    }
    
    // Get storage values with appropriate units for this app
    uint64_t totalBytes, freeBytes;
    getStorageValuesForApp(&totalBytes, &freeBytes);
    
    // Calculate blocks
    if (totalBytes > 0) {
        buf->f_blocks = calculateBlockCount(totalBytes, buf->f_bsize);
    }
    
    if (freeBytes > 0) {
        buf->f_bfree = calculateBlockCount(freeBytes, buf->f_bsize);
        buf->f_bavail = buf->f_bfree; // Available blocks = free blocks for non-root
    }
}

// Replacement for statfs to spoof filesystem info
static int replaced_statfs(const char *path, struct statfs *buf) {
    // Check for null pointers
    if (!path || !buf) {
        return -1; // EINVAL
    }
    
    // Call original function
    int ret = orig_statfs(path, buf);
    
    if (ret == 0 && buf != NULL && shouldApplyStorageSpoofing()) {
        @try {
            // Only apply spoofing for the main file system paths
            if (path && (
                strcmp(path, "/") == 0 || 
                strcmp(path, "/var") == 0 || 
                strcmp(path, "/private/var") == 0 ||
                strncmp(path, "/var/mobile", 11) == 0 ||
                strncmp(path, "/private/var/mobile", 19) == 0)
            ) {
                modifyStatfsWithSpoofedValues(buf);
            }
        } @catch (NSException *exception) {
            // Ignore exceptions during modification
        }
    }
    
    return ret;
}

// Replacement for statfs64 (64-bit variant)
static int replaced_statfs64(const char *path, struct statfs64 *buf) {
    // Check for null pointers
    if (!path || !buf) {
        return -1; // EINVAL
    }
    
    // Call original function
    int ret = orig_statfs64(path, buf);
    
    if (ret == 0 && buf != NULL && shouldApplyStorageSpoofing()) {
        @try {
            // Only apply spoofing for the main file system paths
            if (path && (
                strcmp(path, "/") == 0 || 
                strcmp(path, "/var") == 0 || 
                strcmp(path, "/private/var") == 0 ||
                strncmp(path, "/var/mobile", 11) == 0 ||
                strncmp(path, "/private/var/mobile", 19) == 0)
            ) {
                modifyStatfs64WithSpoofedValues(buf);
            }
        } @catch (NSException *exception) {
            // Ignore exceptions during modification
        }
    }
    
    return ret;
}

// Replacement for getfsstat
static int replaced_getfsstat(struct statfs *buf, int bufsize, int flags) {
    // Check for null pointer or invalid size
    if (!buf || bufsize <= 0) {
        return -1; // EINVAL
    }
    
    // Call original function
    int ret = orig_getfsstat(buf, bufsize, flags);
    
    if (ret > 0 && buf != NULL && shouldApplyStorageSpoofing()) {
        @try {
            // Loop through all filesystems returned
            for (int i = 0; i < ret; i++) {
                // Safely check mount points - first ensure the string is valid
                const char *mountPoint = buf[i].f_mntonname;
                if (mountPoint && mountPoint[0] != '\0') {
                    // Only modify the root filesystem (/) and related mount points
                    if (strcmp(mountPoint, "/") == 0 || 
                        strcmp(mountPoint, "/var") == 0 || 
                        strcmp(mountPoint, "/private/var") == 0) {
                        
                        modifyStatfsWithSpoofedValues(&buf[i]);
                    }
                }
            }
        } @catch (NSException *exception) {
            // Ignore exceptions during modification
        }
    }
    
    return ret;
}

// Replacement for getfsstat64
static int replaced_getfsstat64(struct statfs64 *buf, int bufsize, int flags) {
    // Check for null pointer or invalid size
    if (!buf || bufsize <= 0) {
        return -1; // EINVAL
    }
    
    // Call original function
    int ret = orig_getfsstat64(buf, bufsize, flags);
    
    if (ret > 0 && buf != NULL && shouldApplyStorageSpoofing()) {
        @try {
            // Loop through all filesystems returned
            for (int i = 0; i < ret; i++) {
                // Safely check mount points - first ensure the string is valid
                const char *mountPoint = buf[i].f_mntonname;
                if (mountPoint && mountPoint[0] != '\0') {
                    // Only modify the root filesystem (/) and related mount points
                    if (strcmp(mountPoint, "/") == 0 || 
                        strcmp(mountPoint, "/var") == 0 || 
                        strcmp(mountPoint, "/private/var") == 0) {
                        
                        modifyStatfs64WithSpoofedValues(&buf[i]);
                    }
                }
            }
        } @catch (NSException *exception) {
            // Ignore exceptions during modification
        }
    }
    
    return ret;
}

// Replacement for IORegistryEntryCreateCFProperty - used for IOKit property lookups
static CFTypeRef replaced_IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    // Call original first
    CFTypeRef result = orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
    
    if (!result || !key || !shouldApplyStorageSpoofing()) {
        return result;
    }
    
    @try {
        if (CFGetTypeID(key) == CFStringGetTypeID()) {
            // Check if this is a disk size query
            if (CFStringCompare(key, CFSTR("Size"), 0) == kCFCompareEqualTo) {
                // Get the IOObjectClass
                io_name_t className = {0};  // Initialize to zero
                kern_return_t kr = IOObjectGetClass(entry, className);
                
                // Safely check class name
                if (kr == KERN_SUCCESS && className[0] != '\0') {
                    BOOL isStorageClass = (strcmp(className, "IOMedia") == 0 || 
                                          strcmp(className, "IOApplePartitionScheme") == 0 ||
                                          strcmp(className, "IOBlockStorageDevice") == 0);
                    
                    if (isStorageClass && CFGetTypeID(result) == CFNumberGetTypeID()) {
                        // Get correct storage values for this app
                        uint64_t totalBytes, freeBytes;
                        getStorageValuesForApp(&totalBytes, &freeBytes);
                        
                        if (totalBytes > 0) {
                            // Release the original result
                            CFRelease(result);
                            
                            // Create a new number with our value
                            return CFNumberCreate(allocator, kCFNumberLongLongType, &totalBytes);
                        }
                    }
                }
            }
            // Handle block size queries as well
            else if (CFStringCompare(key, CFSTR("Preferred Block Size"), 0) == kCFCompareEqualTo) {
                // We should preserve the original block size in most cases
                // but ensure it's a reasonable value (4096 bytes is standard for APFS)
                if (CFGetTypeID(result) == CFNumberGetTypeID()) {
                    uint32_t blockSize = 0;
                    if (CFNumberGetValue((CFNumberRef)result, kCFNumberSInt32Type, &blockSize)) {
                        if (blockSize == 0 || blockSize > 65536) {
                            // If the value seems unreasonable, use a standard block size
                            CFRelease(result);
                            uint32_t standardSize = DEFAULT_BLOCK_SIZE;
                            return CFNumberCreate(allocator, kCFNumberSInt32Type, &standardSize);
                        }
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        // If any exception occurs, return the original result
    }
    
    return result;
}

%hook NSFileManager

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path error:(NSError **)error {
    NSDictionary *originalAttributes = %orig;
    
    if (!originalAttributes || !shouldApplyStorageSpoofing()) {
        return originalAttributes;
    }
    
    @try {
        // Create a mutable copy of the attributes
        NSMutableDictionary *modifiedAttributes = [originalAttributes mutableCopy];
        
        // Get storage values with appropriate units for this app
        uint64_t totalBytes, freeBytes;
        getStorageValuesForApp(&totalBytes, &freeBytes);
        
        // Update the total size
        if (totalBytes > 0) {
            modifiedAttributes[NSFileSystemSize] = @(totalBytes);
        }
        
        // Update the free size
        if (freeBytes > 0) {
            modifiedAttributes[NSFileSystemFreeSize] = @(freeBytes);
        }
        
        return modifiedAttributes;
    } @catch (NSException *exception) {
        // If an error occurs, return original attributes
        return originalAttributes;
    }
}

// Add new method for iOS 13+ support
- (NSURL *)URLForDirectory:(NSSearchPathDirectory)directory inDomain:(NSSearchPathDomainMask)domain appropriateForURL:(NSURL *)url create:(BOOL)shouldCreate error:(NSError **)error {
    NSURL *originalURL = %orig;
    return originalURL;
}

// Hook the direct volume capacity method added in iOS 11+
- (unsigned long long)volumeAvailableCapacityForImportantUsageForURL:(NSURL *)url error:(NSError **)error {
    unsigned long long originalCapacity = %orig;
    
    if (!shouldApplyStorageSpoofing()) {
        return originalCapacity;
    }
    
    @try {
        // Get storage values with appropriate units for this app
        uint64_t totalBytes, freeBytes;
        getStorageValuesForApp(&totalBytes, &freeBytes);
        
        if (freeBytes > 0) {
            return freeBytes;
        }
    } @catch (NSException *exception) {
        // If an error occurs, return original value
    }
    
    return originalCapacity;
}

// Hook the direct total capacity method added in iOS 11+
- (unsigned long long)volumeTotalCapacityForURL:(NSURL *)url error:(NSError **)error {
    unsigned long long originalCapacity = %orig;
    
    if (!shouldApplyStorageSpoofing()) {
        return originalCapacity;
    }
    
    @try {
        // Get storage values with appropriate units for this app
        uint64_t totalBytes, freeBytes;
        getStorageValuesForApp(&totalBytes, &freeBytes);
        
        if (totalBytes > 0) {
            return totalBytes;
        }
    } @catch (NSException *exception) {
        // If an error occurs, return original value
    }
    
    return originalCapacity;
}

// Add iOS 13+ method
- (unsigned long long)volumeAvailableCapacityForOpportunisticUsageForURL:(NSURL *)url error:(NSError **)error {
    unsigned long long originalCapacity = %orig;
    
    if (!shouldApplyStorageSpoofing()) {
        return originalCapacity;
    }
    
    @try {
        // Get storage values with appropriate units for this app
        uint64_t totalBytes, freeBytes;
        getStorageValuesForApp(&totalBytes, &freeBytes);
        
        if (freeBytes > 0) {
            // Calculate 90% of free space with high precision
            return (uint64_t)((double)freeBytes * 0.9);
        }
    } @catch (NSException *exception) {
        // If an error occurs, return original value
    }
    
    return originalCapacity;
}

%end

%hook NSURL

// Hook NSURL's getResourceValue:forKey:error: method for iOS 15+ compatibility
- (BOOL)getResourceValue:(id *)value forKey:(NSURLResourceKey)key error:(NSError **)error {
    BOOL result = %orig;
    
    if (!result || !value || !*value || !key || !shouldApplyStorageSpoofing()) {
        return result;
    }
    
    @try {
        // Get storage values with appropriate units for this app
        uint64_t totalBytes, freeBytes;
        getStorageValuesForApp(&totalBytes, &freeBytes);
        
        // Check if this is a volume resource key related to storage
        if ([key isEqualToString:NSURLVolumeTotalCapacityKey]) {
            if (totalBytes > 0) {
                // First check if the existing value is a number
                if ([*value isKindOfClass:[NSNumber class]]) {
                    *value = @(totalBytes);
                }
            }
        }
        else if ([key isEqualToString:NSURLVolumeAvailableCapacityKey]) {
            if (freeBytes > 0) {
                // First check if the existing value is a number
                if ([*value isKindOfClass:[NSNumber class]]) {
                    *value = @(freeBytes);
                }
            }
        }
        // iOS 11+ key
        else if ([key isEqualToString:@"NSURLVolumeAvailableCapacityForImportantUsageKey"]) {
            if (freeBytes > 0) {
                // First check if the existing value is a number
                if ([*value isKindOfClass:[NSNumber class]]) {
                    *value = @(freeBytes);
                }
            }
        }
        // iOS 11+ key
        else if ([key isEqualToString:@"NSURLVolumeAvailableCapacityForOpportunisticUsageKey"]) {
            if (freeBytes > 0) {
                // First check if the existing value is a number
                if ([*value isKindOfClass:[NSNumber class]]) {
                    *value = @((uint64_t)((double)freeBytes * 0.9)); // Use 90% of available space for opportunistic usage
                }
            }
        }
    } @catch (NSException *exception) {
        // If an error occurs, just leave the value unchanged
    }
    
    return result;
}

// Hook NSURL's resourceValuesForKeys:error: method for iOS 15+ compatibility
- (NSDictionary<NSURLResourceKey, id> *)resourceValuesForKeys:(NSArray<NSURLResourceKey> *)keys error:(NSError **)error {
    NSDictionary<NSURLResourceKey, id> *originalValues = %orig;
    
    if (!originalValues || !keys || !shouldApplyStorageSpoofing()) {
        return originalValues;
    }
    
    @try {
        // Get storage values with appropriate units for this app
        uint64_t totalBytes, freeBytes;
        getStorageValuesForApp(&totalBytes, &freeBytes);
        
        NSMutableDictionary *modifiedValues = [originalValues mutableCopy];
        
        // Check if any of the keys are storage-related
        for (NSURLResourceKey key in keys) {
            if ([key isEqualToString:NSURLVolumeTotalCapacityKey]) {
                if (totalBytes > 0) {
                    modifiedValues[key] = @(totalBytes);
                }
            }
            else if ([key isEqualToString:NSURLVolumeAvailableCapacityKey]) {
                if (freeBytes > 0) {
                    modifiedValues[key] = @(freeBytes);
                }
            }
            // iOS 11+ key
            else if ([key isEqualToString:@"NSURLVolumeAvailableCapacityForImportantUsageKey"]) {
                if (freeBytes > 0) {
                    modifiedValues[key] = @(freeBytes);
                }
            }
            // iOS 11+ key
            else if ([key isEqualToString:@"NSURLVolumeAvailableCapacityForOpportunisticUsageKey"]) {
                if (freeBytes > 0) {
                    modifiedValues[key] = @((uint64_t)((double)freeBytes * 0.9)); // Use 90% of available space for opportunistic usage
                }
            }
        }
        
        return modifiedValues;
    } @catch (NSException *exception) {
        // If an error occurs, return original values
        return originalValues;
    }
}

%end

// Setup hooks - Use %ctor for constructor, runs when module loads
%ctor {
    @autoreleasepool {
        @try {
            PXLog(@"[StorageHooks] Initializing storage hooks");
            
            NSString *currentBundleID = getCurrentBundleID();
            
            // Skip if we can't get bundle ID
            if (!currentBundleID || [currentBundleID length] == 0) {
                return;
            }
            
            // Don't hook system processes and our own apps
            if ([currentBundleID hasPrefix:@"com.apple."] || 
                [currentBundleID isEqualToString:@"com.hydra.projectx"] || 
                [currentBundleID isEqualToString:@"com.hydra.weaponx"]) {
                PXLog(@"[StorageHooks] Not hooking system process: %@", currentBundleID);
                return;
            }
            
            // CRITICAL: Only install hooks if this app is actually scoped
            if (!isInScopedAppsList()) {
                // App is NOT scoped - no hooks, no interference, no crashes
                PXLog(@"[StorageHooks] App %@ is not scoped, skipping hook installation", currentBundleID);
                return;
            }
            
            PXLog(@"[StorageHooks] App %@ is scoped, setting up storage hooks", currentBundleID);
            
            // Hook statfs
            void *handle = dlopen(NULL, RTLD_GLOBAL);
            
            if (handle) {
                orig_statfs = dlsym(handle, "statfs");
                if (orig_statfs) {
                    EKHook((void *)orig_statfs, (void *)replaced_statfs, (void **)&orig_statfs);
                    PXLog(@"[StorageHooks] Hooked statfs successfully");
                }
                
                // Hook statfs64 (if available)
                orig_statfs64 = dlsym(handle, "statfs64");
                if (orig_statfs64) {
                    EKHook((void *)orig_statfs64, (void *)replaced_statfs64, (void **)&orig_statfs64);
                    PXLog(@"[StorageHooks] Hooked statfs64 successfully");
                }
                
                // Hook getfsstat
                orig_getfsstat = dlsym(handle, "getfsstat");
                if (orig_getfsstat) {
                    EKHook((void *)orig_getfsstat, (void *)replaced_getfsstat, (void **)&orig_getfsstat);
                    PXLog(@"[StorageHooks] Hooked getfsstat successfully");
                }
                
                // Hook getfsstat64 (if available)
                orig_getfsstat64 = dlsym(handle, "getfsstat64");
                if (orig_getfsstat64) {
                    EKHook((void *)orig_getfsstat64, (void *)replaced_getfsstat64, (void **)&orig_getfsstat64);
                    PXLog(@"[StorageHooks] Hooked getfsstat64 successfully");
                }
                
                dlclose(handle);
            }
            
            // Hook IOKit functions
            void *ioKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
            if (ioKitHandle) {
                // Get the function pointer for IORegistryEntryCreateCFProperty
                void *ioRegEntryCreateCFPropertyPtr = dlsym(ioKitHandle, "IORegistryEntryCreateCFProperty");
                
                if (ioRegEntryCreateCFPropertyPtr) {
                    EKHook(ioRegEntryCreateCFPropertyPtr, (void *)replaced_IORegistryEntryCreateCFProperty, (void **)&orig_IORegistryEntryCreateCFProperty);
                    PXLog(@"[StorageHooks] Hooked IORegistryEntryCreateCFProperty successfully");
                }
                
                dlclose(ioKitHandle);
            }
            
            // Initialize Objective-C hooks for scoped apps only
            %init;
            
            PXLog(@"[StorageHooks] Storage hooks successfully initialized for scoped app: %@", currentBundleID);
            
        } @catch (NSException *e) {
            PXLog(@"[StorageHooks] ❌ Exception in constructor: %@", e);
        }
    }
} 