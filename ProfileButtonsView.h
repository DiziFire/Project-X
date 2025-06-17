#import <UIKit/UIKit.h>

@interface ProfileButtonsView : UIView

@property (nonatomic, copy) void (^onNewProfileTapped)(void);
@property (nonatomic, copy) void (^onManageProfilesTapped)(void);

- (instancetype)initWithFrame:(CGRect)frame;

@end 