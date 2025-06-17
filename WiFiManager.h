#import <Foundation/Foundation.h>

@interface WiFiManager : NSObject

// Singleton access
+ (instancetype)sharedManager;

// Core functionality
- (NSDictionary *)generateWiFiInfo;
- (NSDictionary *)currentWiFiInfo;
- (void)setCurrentWiFiInfo:(NSDictionary *)wifiInfo;

// Individual property getters/setters
- (NSString *)currentSSID;
- (NSString *)currentBSSID;
- (NSString *)currentNetworkType;
- (NSString *)currentWiFiStandard;
- (BOOL)currentAutoJoinStatus;
- (NSDate *)lastConnectionTime;

// Validation
- (BOOL)isValidSSID:(NSString *)ssid;
- (BOOL)isValidBSSID:(NSString *)bssid;

// Error Handling
- (NSError *)lastError;

@end 