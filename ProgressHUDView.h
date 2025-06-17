#import <UIKit/UIKit.h>

@interface ProgressHUDView : UIView

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *detailLabel;

// Show in a view
+ (ProgressHUDView *)showHUDAddedTo:(UIView *)view title:(NSString *)title;
// Hide from a view
+ (void)hideHUDForView:(UIView *)view;
// Update progress
- (void)setProgress:(float)progress animated:(BOOL)animated;
- (void)setDetailText:(NSString *)text;

@end
