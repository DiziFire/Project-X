#import <Foundation/Foundation.h>

@interface DeviceNameManager : NSObject

+ (instancetype)sharedManager;

// Device Name Generation
- (NSString *)generateDeviceName;
- (NSString *)currentDeviceName;
- (void)setCurrentDeviceName:(NSString *)deviceName;

// Validation
- (BOOL)isValidDeviceName:(NSString *)deviceName;

// Error Handling
- (NSError *)lastError;

@end 