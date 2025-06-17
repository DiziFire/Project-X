#import <Foundation/Foundation.h>

@interface SystemUUIDManager : NSObject

+ (instancetype)sharedManager;

// Boot UUID Generation
- (NSString *)generateBootUUID;
- (NSString *)currentBootUUID;
- (void)setCurrentBootUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end 