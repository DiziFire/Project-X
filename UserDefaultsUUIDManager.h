#import "Foundation/Foundation.h"

@interface UserDefaultsUUIDManager : NSObject

+ (instancetype)sharedManager;

// UserDefaults UUID Generation
- (NSString *)generateUserDefaultsUUID;
- (NSString *)currentUserDefaultsUUID;
- (void)setCurrentUserDefaultsUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end 