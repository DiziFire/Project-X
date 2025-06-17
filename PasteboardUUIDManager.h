#import "Foundation/Foundation.h"

@interface PasteboardUUIDManager : NSObject

+ (instancetype)sharedManager;

// Pasteboard UUID Generation
- (NSString *)generatePasteboardUUID;
- (NSString *)currentPasteboardUUID;
- (void)setCurrentPasteboardUUID:(NSString *)uuid;

// Validation
- (BOOL)isValidUUID:(NSString *)uuid;

// Error handling
@property (nonatomic, readonly) NSError *lastError;

@end 