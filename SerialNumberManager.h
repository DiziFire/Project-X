#import <Foundation/Foundation.h>

@interface SerialNumberManager : NSObject

@property (nonatomic, readonly) NSError *lastError;

+ (instancetype)sharedManager;

// Core functionality
- (NSString *)generateSerialNumber;
- (NSString *)currentSerialNumber;
- (void)setCurrentSerialNumber:(NSString *)serialNumber;

// Validation
- (BOOL)isValidSerialNumber:(NSString *)serialNumber;

// Security methods
- (void)clearSensitiveData;
- (BOOL)isEnvironmentSecure;

@end 