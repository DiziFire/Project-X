#import <UIKit/UIKit.h>

@interface MatrixRainView : UIView

@property (nonatomic, assign) BOOL showHookingInfo;
@property (nonatomic, strong) NSArray *hookingInfo;

- (void)startAnimation;
- (void)stopAnimation;
- (void)updateHookingInfo:(NSArray *)info;

@end 