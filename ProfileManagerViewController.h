#import <UIKit/UIKit.h>
#import "ProfileManager.h"

@class ProfileManagerViewController;

@protocol ProfileManagerViewControllerDelegate <NSObject>

- (void)profileManagerViewController:(ProfileManagerViewController *)viewController didUpdateProfiles:(NSArray<Profile *> *)profiles;

@optional
- (void)profileManagerViewController:(ProfileManagerViewController *)viewController didSelectProfile:(Profile *)profile;

@end

@interface ProfileManagerViewController : UIViewController

@property (nonatomic, weak) id<ProfileManagerViewControllerDelegate> delegate;
@property (nonatomic, strong) NSMutableArray<Profile *> *profiles;
@property (nonatomic, strong) UITableView *tableView;

- (instancetype)initWithProfiles:(NSMutableArray<Profile *> *)profiles;

@end 