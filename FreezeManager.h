#import "Foundation/Foundation.h"
#import "UIKit/UIKit.h"
#import "BottomButtons.h"

@interface FreezeManager : NSObject

+ (instancetype)sharedManager;

// App Management
- (void)killApplication:(NSString *)bundleID;
- (void)freezeApplication:(NSString *)bundleID;
- (void)unfreezeApplication:(NSString *)bundleID;
- (BOOL)isApplicationFrozen:(NSString *)bundleID;

@end