#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UptimeManager : NSObject

// Singleton accessor
+ (instancetype)sharedManager;

// System Uptime Generation (legacy)
- (NSString *)generateUptime;
- (NSTimeInterval)currentUptime;
- (void)setCurrentUptime:(NSTimeInterval)uptime;

// Boot Time Generation (legacy)
- (NSString *)generateBootTime;
- (NSDate *)currentBootTime;
- (void)setCurrentBootTime:(NSDate *)bootTime;

// New profile-specific methods
- (NSString *)generateUptimeForProfile:(NSString *)profilePath;
- (NSTimeInterval)currentUptimeForProfile:(NSString *)profilePath;
- (NSString *)generateBootTimeForProfile:(NSString *)profilePath;
- (NSDate *)currentBootTimeForProfile:(NSString *)profilePath;
- (void)generateConsistentUptimeAndBootTimeForProfile:(NSString *)profilePath;

// Data validation
- (BOOL)validateBootTimeConsistencyForProfile:(NSString *)profilePath;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end

NS_ASSUME_NONNULL_END 