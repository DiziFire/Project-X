#import <UIKit/UIKit.h>

@interface SignupViewController : UIViewController

@property (nonatomic, copy) void (^signupCompletionHandler)(void);

@end