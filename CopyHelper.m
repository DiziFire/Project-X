#import "CopyHelper.h"
#import <UIKit/UIKit.h>

static const void *const kCopyTextKey = &kCopyTextKey;

@implementation CopyHelper

+ (instancetype)sharedHelper {
    static CopyHelper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CopyHelper alloc] init];
    });
    return instance;
}

+ (UIButton *)createCopyButtonWithText:(NSString *)text {
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    // Use modern button configuration
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.image = [UIImage systemImageNamed:@"doc.on.doc"];
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    config.baseForegroundColor = [UIColor systemBlueColor];
    config.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
    copyButton.configuration = config;
    
    // Store the text to copy in the button's accessibilityValue
    copyButton.accessibilityValue = text;
    
    // Add action
    [copyButton addTarget:self action:@selector(copyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    return copyButton;
}

+ (void)copyButtonTapped:(UIButton *)sender {
    NSString *textToCopy = sender.accessibilityValue;
    if (textToCopy) {
        // Copy to clipboard
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:textToCopy];
        
        // Enhanced visual feedback for copy action
        UIColor *originalColor = sender.tintColor;
        
        // Create a checkmark configuration for success feedback
        UIButtonConfiguration *originalConfig = sender.configuration;
        UIButtonConfiguration *successConfig = [originalConfig copy];
        successConfig.image = [UIImage systemImageNamed:@"checkmark"];
        successConfig.baseForegroundColor = [UIColor systemGreenColor];
        
        // Animate the change
        [UIView animateWithDuration:0.2 animations:^{
            sender.configuration = successConfig;
        } completion:^(BOOL finished) {
            // Show success state for a moment
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Animate back to original state
                [UIView animateWithDuration:0.2 animations:^{
                    UIButtonConfiguration *revertConfig = [originalConfig copy];
                    revertConfig.baseForegroundColor = originalColor;
                    sender.configuration = revertConfig;
                }];
            });
        }];
    }
}

- (void)copyTextToClipboard:(NSString *)text {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = text;
}

+ (void)copyTextToClipboard:(NSString *)text fromButton:(UIButton *)button {
    // Add to clipboard
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = text;
    
    // Create and show a brief animation for feedback
    UIView *buttonSuperview = button.superview;
    
    UILabel *copyLabel = [[UILabel alloc] init];
    copyLabel.text = @"Copied!";
    copyLabel.font = [UIFont systemFontOfSize:12];
    copyLabel.textColor = [UIColor whiteColor];
    copyLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    copyLabel.textAlignment = NSTextAlignmentCenter;
    copyLabel.layer.cornerRadius = 4.0;
    copyLabel.clipsToBounds = YES;
    copyLabel.alpha = 0.0;
    
    // Calculate position
    CGRect buttonFrameInSuperview = [buttonSuperview convertRect:button.frame fromView:button.superview];
    copyLabel.frame = CGRectMake(buttonFrameInSuperview.origin.x - 40, 
                                buttonFrameInSuperview.origin.y - 30, 
                                80, 25);
    
    [buttonSuperview addSubview:copyLabel];
    
    // Animate
    [UIView animateWithDuration:0.3 animations:^{
        copyLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (finished) {
            // Fade out after delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{
                    copyLabel.alpha = 0.0;
                } completion:^(BOOL finished) {
                    [copyLabel removeFromSuperview];
                }];
            });
        }
    }];
}

#pragma mark - Private

@end