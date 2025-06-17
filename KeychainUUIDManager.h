#import "Foundation/Foundation.h"

@interface KeychainUUIDManager : NSObject

+ (instancetype)sharedManager;

// Keychain UUID Generation
- (NSString *)generateKeychainUUID;
- (NSString *)currentKeychainUUID;
- (void)setCurrentKeychainUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end 