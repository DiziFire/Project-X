#import <Foundation/Foundation.h>

@interface AppContainerUUIDManager : NSObject

@property (nonatomic, strong, readonly) NSError *error;
@property (nonatomic, strong, readonly) NSString *currentIdentifier;

+ (instancetype)sharedManager;

// App Container UUID Generation and Management
- (NSString *)generateAppContainerUUID;
- (NSString *)currentAppContainerUUID;
- (void)setCurrentAppContainerUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
- (NSError *)lastError;

@end 