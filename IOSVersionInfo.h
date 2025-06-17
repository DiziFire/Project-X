#import <Foundation/Foundation.h>

@interface IOSVersionInfo : NSObject

+ (instancetype)sharedManager;

// Generate a random iOS version and build number pair
- (NSDictionary *)generateIOSVersionInfo;

// Get current iOS version info
- (NSDictionary *)currentIOSVersionInfo;

// Set specific iOS version info
- (void)setCurrentIOSVersionInfo:(NSDictionary *)versionInfo;

// Get available iOS version options
- (NSArray *)availableIOSVersions;

// Validation
- (BOOL)isValidIOSVersionInfo:(NSDictionary *)versionInfo;

// Error Handling
- (NSError *)lastError;

@end 