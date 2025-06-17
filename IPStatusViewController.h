// IPStatusViewController.h
#import <UIKit/UIKit.h>

@interface IPStatusViewController : UIViewController

- (void)displayIPStatusFromDictionary:(NSDictionary *)result;
- (void)displayCachedIPStatus;
- (void)displayCachedIPStatusAtIndex:(NSInteger)index;

@end
