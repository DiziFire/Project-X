#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

@interface CopyHelper : NSObject

// Creates and returns a button configured for copying text
+ (UIButton *)createCopyButtonWithText:(NSString *)text;

// Copies the given text to clipboard and shows a brief success animation
+ (void)copyTextToClipboard:(NSString *)text fromButton:(UIButton *)button;

+ (instancetype)sharedHelper;
- (void)copyTextToClipboard:(NSString *)text;

+ (void)copyButtonTapped:(UIButton *)sender;

@end