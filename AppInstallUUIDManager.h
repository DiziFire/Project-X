#import <Foundation/Foundation.h>

@interface AppInstallUUIDManager : NSObject

@property (nonatomic, strong, readonly) NSError *error;
@property (nonatomic, strong, readonly) NSString *currentIdentifier;

+ (instancetype)sharedManager;

// App Install UUID Generation and Management
- (NSString *)generateAppInstallUUID;
- (NSString *)currentAppInstallUUID;
- (void)setCurrentAppInstallUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
- (NSError *)lastError;

@end 