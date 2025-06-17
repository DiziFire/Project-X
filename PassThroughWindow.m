#import "PassThroughWindow.h"
#import "ProjectXLogging.h"

@implementation PassThroughWindow

// Override hit testing to only catch touches on actual subviews
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *result = [super hitTest:point withEvent:event];
    
    // If the hit test returns the window itself, return nil to pass touch to underlying windows
    if (result == self) {
        return nil;
    }
    
    return result;
}

@end 