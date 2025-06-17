#import "Foundation/Foundation.h"

@interface AppGroupUUIDManager : NSObject

+ (instancetype)sharedManager;

// App Group UUID Generation
- (NSString *)generateAppGroupUUID;
- (NSString *)currentAppGroupUUID;
- (void)setCurrentAppGroupUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end 