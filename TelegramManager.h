#import <Foundation/Foundation.h>

@interface TelegramManager : NSObject

+ (instancetype)sharedManager;

/**
 * Fetches the user's Telegram tag from the server
 * @param token The authentication token
 * @param completion Block called when the operation completes, with the Telegram tag (or nil) and error
 */
- (void)fetchTelegramTagWithToken:(NSString *)token 
                       completion:(void (^)(NSString *telegramTag, NSError *error))completion;

/**
 * Updates the user's Telegram tag on the server
 * @param token The authentication token
 * @param telegramTag The new Telegram tag value
 * @param completion Block called when the operation completes with success status and error
 */
- (void)updateTelegramTag:(NSString *)token 
               telegramTag:(NSString *)telegramTag 
                completion:(void (^)(BOOL success, NSError *error))completion;

/**
 * Validates if a Telegram tag follows the required format (letters, numbers, underscores, 5-32 chars)
 * @param telegramTag The tag to validate
 * @return YES if the tag is valid, NO otherwise
 */
- (BOOL)isValidTelegramTag:(NSString *)telegramTag;

/**
 * Format a Telegram tag for display (adding @ prefix)
 * @param telegramTag The tag to format
 * @return The formatted tag with @ prefix (or empty string if nil)
 */
- (NSString *)formatTelegramTagForDisplay:(NSString *)telegramTag;

@end 