// IPStatusCacheManager.h
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface IPStatusCacheManager : NSObject

+ (instancetype)sharedManager;
- (NSDictionary *)loadLastIPStatus;
- (void)saveIPStatus:(NSDictionary *)status;
- (BOOL)isCacheValid;
- (NSArray *)getAllCachedIPStatuses;
- (NSDictionary *)getIPStatusAtIndex:(NSInteger)index;
- (NSInteger)getCacheCount;
- (NSString *)cacheFilePathForIndex:(NSInteger)index;

// New methods for IP location time plist
+ (void)saveIPAndLocationData:(NSDictionary *)data;
+ (NSDictionary *)loadIPAndLocationData;
+ (void)savePublicIP:(NSString *)ip countryCode:(NSString *)countryCode flagEmoji:(NSString *)flagEmoji timestamp:(NSDate *)timestamp;
+ (void)savePinnedLocation:(CLLocationCoordinate2D)coordinates countryCode:(NSString *)countryCode flagEmoji:(NSString *)flagEmoji timestamp:(NSDate *)timestamp;
+ (NSDictionary *)getPublicIPData;
+ (NSDictionary *)getPinnedLocationData;

@end
