#import <UIKit/UIKit.h>

@interface TelegramUI : UIView

/**
 * Initializes the Telegram UI component
 * @param frame The frame rectangle for the view
 * @param primaryColor The primary color used for labels and buttons
 * @return A new TelegramUI instance
 */
- (instancetype)initWithFrame:(CGRect)frame primaryColor:(UIColor *)primaryColor;

/**
 * Updates the UI with the current Telegram tag
 * @param telegramTag The current Telegram tag (can be nil)
 */
- (void)updateWithTelegramTag:(NSString *)telegramTag;

/**
 * Sets the action block to be called when the user wants to update their Telegram tag
 * @param actionBlock The block to execute, with the new tag as parameter
 */
- (void)setUpdateActionBlock:(void (^)(NSString *newTag))actionBlock;

/**
 * Sets the authentication token to use for API calls
 * @param token The auth token
 */
- (void)setAuthToken:(NSString *)token;

@end 