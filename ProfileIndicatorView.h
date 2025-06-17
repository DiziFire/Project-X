#import <UIKit/UIKit.h>

@interface ProfileIndicatorView : UIView

+ (instancetype)sharedInstance;
- (void)show;
- (void)hide;
- (void)updateProfileIndicator;

@end 