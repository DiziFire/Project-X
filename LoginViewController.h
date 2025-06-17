#import <UIKit/UIKit.h>

@interface LoginViewController : UIViewController

@property (nonatomic, copy) void (^loginCompletionHandler)(void);
@property (nonatomic, copy) void (^signupCompletionHandler)(void);

// Helper method to complete login process with token and user info
- (void)completeLoginWithToken:(NSString *)token userInfo:(NSDictionary *)userInfo;

@end