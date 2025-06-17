#import <Foundation/Foundation.h>

@interface IDFVManager : NSObject

+ (instancetype)sharedManager;

// IDFV Generation
- (NSString *)generateIDFV;
- (NSString *)currentIDFV;
- (void)setCurrentIDFV:(NSString *)idfv;

// Validation
- (BOOL)isValidIDFV:(NSString *)idfv;

// Error Handling
- (NSError *)lastError;

@end