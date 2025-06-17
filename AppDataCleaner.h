#import <Foundation/Foundation.h>

@interface AppDataCleaner : NSObject

+ (instancetype)sharedManager;

#pragma mark - Main Public Methods

// Clear all data for a specific app
- (void)clearDataForBundleID:(NSString *)bundleID 
                 completion:(void (^)(BOOL success, NSError *error))completion;

// Check if app has any data to clear
- (BOOL)hasDataToClear:(NSString *)bundleID;

#pragma mark - Comprehensive Cleanup Methods

- (void)performFullCleanup:(NSString *)bundleID;
- (void)performSecondaryCleanup:(NSString *)bundleID;
- (void)performAggressiveCleanupFor:(NSString *)bundleID;
- (void)completeAppDataWipe:(NSString *)bundleID;

#pragma mark - Enhanced Container Cleaning
- (void)completelyWipeContainer:(NSString *)containerPath;
- (void)cleanIconStatePlist:(NSString *)bundleID;
- (void)cleanSiriAnalyticsDatabase:(NSString *)bundleID;
- (void)cleanLaunchServicesDatabase:(NSString *)bundleID;
- (void)refreshSystemServices;

#pragma mark - Standard App Data Cleaning
- (void)clearAppData:(NSString *)bundleID;
- (void)clearAppCache:(NSString *)bundleID;
- (void)clearAppPreferences:(NSString *)bundleID;
- (void)clearAppCookies:(NSString *)bundleID;
- (void)clearAppWebKitData:(NSString *)bundleID;
- (void)clearAppKeychain:(NSString *)bundleID;
- (void)clearAppGroupData:(NSString *)bundleID;
- (void)clearAppReceiptData:(NSString *)bundleID withBundleUUID:(NSString *)bundleUUID;

#pragma mark - System Storage Cleaning
- (void)clearKeychainData:(NSString *)bundleID;
- (void)clearSharedContainers:(NSString *)bundleID;
- (void)clearUserDefaults:(NSString *)bundleID;
- (void)clearSQLiteDatabases:(NSString *)bundleID;

#pragma mark - Hidden Storage Cleaning
- (void)clearPrivateVarData:(NSString *)bundleID;
- (void)clearSystemLogs:(NSString *)bundleID;
- (void)clearDeviceDatabase:(NSString *)bundleID;
- (void)clearInstallationLogs:(NSString *)bundleID;

#pragma mark - Network & Carrier Cleaning
- (void)clearNetworkConfigurations:(NSString *)bundleID;
- (void)clearCarrierData:(NSString *)bundleID;
- (void)clearNetworkData:(NSString *)bundleID;
- (void)clearDNSCache:(NSString *)bundleID;

#pragma mark - Additional Storage Cleaning
- (void)clearCrashReports:(NSString *)bundleID;
- (void)clearDiagnosticData:(NSString *)bundleID;
- (void)clearICloudData:(NSString *)bundleID;
- (void)clearBluetoothData:(NSString *)bundleID;
- (void)clearPushNotificationData:(NSString *)bundleID;
- (void)clearMediaData:(NSString *)bundleID;
- (void)clearHealthData:(NSString *)bundleID;
- (void)clearSafariData:(NSString *)bundleID;

#pragma mark - Cache & Residual Cleaning
- (void)clearThumbnailCache:(NSString *)bundleID;
- (void)clearWebCache:(NSString *)bundleID;
- (void)clearGameData:(NSString *)bundleID;
- (void)clearTemporaryFiles:(NSString *)bundleID;

#pragma mark - Advanced Cleaning Methods
- (void)clearBinaryPlists:(NSString *)bundleID;
- (void)clearEncryptedData:(NSString *)bundleID;
- (void)clearJailbreakDetectionLogs:(NSString *)bundleID;
- (void)clearPluginKitData:(NSString *)bundleID;
- (void)clearURLCredentialsForBundleID:(NSString *)bundleID;
- (void)clearSpotlightIndexes:(NSString *)bundleID;

#pragma mark - System Integration
- (void)clearSpotlightData:(NSString *)bundleID;
- (void)clearSiriData:(NSString *)bundleID;
- (void)clearSystemLoggerData:(NSString *)bundleID;
- (void)clearASLLogs:(NSString *)bundleID;

#pragma mark - Data Persistence
- (void)clearClipboard;
- (void)clearPasteboardData:(NSString *)bundleID;
- (void)clearURLCache:(NSString *)bundleID;
- (void)clearBackgroundAssets:(NSString *)bundleID;

#pragma mark - State Management
- (void)clearSharedStorage:(NSString *)bundleID;
- (void)clearAppStateData:(NSString *)bundleID;
- (void)_internalClearAppStateData:(NSString *)bundleID;
- (void)_internalClearEncryptedData:(NSString *)bundleID;

#pragma mark - Security Methods
- (BOOL)securelyWipeFile:(NSString *)path;
- (void)secureDataWipe:(NSString *)bundleID;
- (BOOL)verifyDataCleared:(NSString *)bundleID;
- (NSDictionary *)getDataUsage:(NSString *)bundleID;
- (void)fixPermissionsAndRemovePath:(NSString *)path;
- (void)fixPermissionsForPath:(NSString *)path;
- (void)clearKeychainItemsForBundleID:(NSString *)bundleID;

#pragma mark - Container Discovery Methods
- (NSString *)findDataContainerUUIDForBundleID:(NSString *)bundleID;
- (NSString *)findBundleContainerUUIDForBundleID:(NSString *)bundleID;
- (NSArray *)findGroupContainerUUIDsForBundleID:(NSString *)bundleID;
- (NSArray *)findExtensionDataContainersForBundleID:(NSString *)bundleID;
- (BOOL)hasKeychainItemsForBundleID:(NSString *)bundleID;

@end 