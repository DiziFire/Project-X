#import "DeviceSpecificSpoofingViewController.h"
#import "ProfileManagerViewController.h"

@implementation DeviceSpecificSpoofingViewController (ProfileManagerDelegate)

- (void)profileManagerViewController:(ProfileManagerViewController *)viewController didUpdateProfiles:(NSArray<Profile *> *)profiles {
    [self refreshProfileUI];
}
- (void)profileManagerViewController:(ProfileManagerViewController *)viewController didSelectProfile:(Profile *)profile {
    [self refreshProfileUI];
}

@end
