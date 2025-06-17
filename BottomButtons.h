#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(id)identifier;
@property(readonly) NSString *bundleExecutable;
@end

@interface LSApplicationWorkspace
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(id)arg1;
@end

@interface FBProcessManager : NSObject
+ (id)sharedInstance;
- (void)killApplication:(id)arg1;
@end

@interface BKSProcessAssertion : NSObject
- (id)initWithPID:(int)pid flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(void (^)(BOOL))handler;
@end

@interface BottomButtons : NSObject

+ (instancetype)sharedInstance;

// UI Components
- (UIView *)createBottomButtonsView;

// App Termination
- (void)terminateApplicationWithBundleID:(NSString *)bundleID;

@end