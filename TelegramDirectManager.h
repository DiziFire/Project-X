#import <Foundation/Foundation.h>

@interface TelegramDirectManager : NSObject

/**
 * Returns the shared instance of the TelegramDirectManager
 */
+ (instancetype)sharedManager;

/**
 * Updates the Telegram tag for the authenticated user using the direct API route.
 * This method uses the direct/telegram endpoint which should bypass CSRF validation.
 *
 * @param token The authentication token
 * @param telegramTag The new Telegram tag (with or without @ prefix)
 * @param completion Completion handler called with success/failure result
 */
- (void)updateTelegramTagWithToken:(NSString *)token
                       telegramTag:(NSString *)telegramTag
                        completion:(void (^)(BOOL success, NSError *error))completion;

/**
 * Fetches the current Telegram tag for the authenticated user
 *
 * @param token The authentication token
 * @param completion Completion handler called with the current tag or error
 */
- (void)fetchCurrentTelegramTagWithToken:(NSString *)token
                              completion:(void (^)(NSString *telegramTag, NSError *error))completion;

@end 