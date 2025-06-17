#import <Foundation/Foundation.h>

@interface DyldCacheUUIDManager : NSObject

+ (instancetype)sharedManager;

// Dyld Cache UUID Generation
- (NSString *)generateDyldCacheUUID;
- (NSString *)currentDyldCacheUUID;
- (void)setCurrentDyldCacheUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end 