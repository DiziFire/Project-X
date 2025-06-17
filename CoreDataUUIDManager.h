#import "Foundation/Foundation.h"

@interface CoreDataUUIDManager : NSObject

+ (instancetype)sharedManager;

// Core Data UUID Generation and Management
- (NSString *)generateCoreDataUUID;
- (NSString *)currentCoreDataUUID;
- (void)setCurrentCoreDataUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end
