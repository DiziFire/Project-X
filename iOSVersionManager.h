#import <Foundation/Foundation.h>

@interface iOSVersionManager : NSObject

+ (instancetype)sharedManager;

// iOS Version Generation
- (NSDictionary *)generateiOSVersion;
- (NSDictionary *)currentiOSVersion;
- (void)setCurrentiOSVersion:(NSDictionary *)versionInfo;

// Validation
- (BOOL)isValidiOSVersion:(NSDictionary *)versionInfo;

// Error Handling
- (NSError *)lastError;

@end
