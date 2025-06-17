#import <Foundation/Foundation.h>

@interface IDFAManager : NSObject

+ (instancetype)sharedManager;

// IDFA Generation
- (NSString *)generateIDFA;
- (NSString *)currentIDFA;
- (void)setCurrentIDFA:(NSString *)idfa;

// Validation
- (BOOL)isValidIDFA:(NSString *)idfa;

// Error Handling
- (NSError *)lastError;

@end