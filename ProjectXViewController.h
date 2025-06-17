#import <UIKit/UIKit.h>
#import "ProfileButtonsView.h"
#import "ProfileManagerViewController.h"
#import "ProfileCreationViewController.h"
#import "ProfileManager.h"
#import "ProgressHUDView.h"

@interface ProjectXViewController : UIViewController <ProfileCreationViewControllerDelegate, ProfileManagerViewControllerDelegate>


@property (nonatomic, strong) ProfileButtonsView *profileButtonsView;
@property (nonatomic, strong) NSMutableArray<Profile *> *profiles;
@property (nonatomic, strong) UIView *profileIndicatorView;

// Profile Management Methods
- (void)setupProfileButtons;
- (void)setupProfileManagement;
- (void)showProfileCreation;
- (void)showProfileManager;

// Profile Creation Delegate Method
- (void)profileCreationViewController:(UIViewController *)viewController didCreateProfile:(NSString *)profileName;

@end