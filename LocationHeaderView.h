#import <UIKit/UIKit.h>

@interface LocationHeaderView : UIView

+ (UIView *)createHeaderViewWithTitle:(NSString *)title 
                     navigationItem:(UINavigationItem *)navigationItem 
                      updateHandler:(void (^)(void))updateHandler;

@end 