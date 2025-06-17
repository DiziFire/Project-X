#import <Foundation/Foundation.h>

@interface IPMonitorService : NSObject

+ (instancetype)sharedInstance;
- (void)startMonitoring;
- (void)stopMonitoring;
- (BOOL)isMonitoring;
- (NSString *)loadLastKnownIP;

@end