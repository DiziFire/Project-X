#import <UIKit/UIKit.h>

@protocol ProfileCreationViewControllerDelegate <NSObject>

- (void)profileCreationViewController:(UIViewController *)viewController didCreateProfile:(NSString *)profileName;

@end

@interface ProfileCreationViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic, weak) id<ProfileCreationViewControllerDelegate> delegate;

@end 