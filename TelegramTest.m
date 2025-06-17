#import <Foundation/Foundation.h>
#import "TelegramDirectManager.h"

// Color formatting for console output - properly formatted for NSLog
#define ANSI_COLOR_RED     @"\x1b[31m"
#define ANSI_COLOR_GREEN   @"\x1b[32m"
#define ANSI_COLOR_YELLOW  @"\x1b[33m"
#define ANSI_COLOR_BLUE    @"\x1b[34m"
#define ANSI_COLOR_MAGENTA @"\x1b[35m"
#define ANSI_COLOR_CYAN    @"\x1b[36m"
#define ANSI_COLOR_RESET   @"\x1b[0m"

// Only compile the main function when specifically building the test program
// This prevents conflicts with the app's main.m file
#ifdef TELEGRAM_TEST_MAIN

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"==================================================");
        NSLog(@"TELEGRAM TAG UPDATE TEST STARTED");
        NSLog(@"==================================================");
        
        if (argc < 3) {
            NSLog(@"%@", [NSString stringWithFormat:@"%@Usage: %s AUTH_TOKEN NEW_TELEGRAM_TAG%@", 
                       ANSI_COLOR_RED, argv[0], ANSI_COLOR_RESET]);
            return 1;
        }
        
        // Get the auth token and new tag from command line arguments
        NSString *authToken = [NSString stringWithUTF8String:argv[1]];
        NSString *newTelegramTag = [NSString stringWithUTF8String:argv[2]];
        
        NSLog(@"%@", [NSString stringWithFormat:@"%@Using token: %@...%@", 
              ANSI_COLOR_BLUE, [authToken substringToIndex:MIN(6, authToken.length)], ANSI_COLOR_RESET]);
        NSLog(@"%@", [NSString stringWithFormat:@"%@New Telegram tag: %@%@", 
              ANSI_COLOR_BLUE, newTelegramTag, ANSI_COLOR_RESET]);
        
        // Create a dispatch group to wait for completion
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        
        // Step 1: Get current Telegram tag
        NSLog(@"%@", [NSString stringWithFormat:@"%@STEP 1: Fetching current Telegram tag...%@", 
              ANSI_COLOR_CYAN, ANSI_COLOR_RESET]);
        [[TelegramDirectManager sharedManager] fetchCurrentTelegramTagWithToken:authToken completion:^(NSString *currentTag, NSError *error) {
            if (error) {
                NSLog(@"%@", [NSString stringWithFormat:@"%@ERROR: Could not fetch current tag: %@%@", 
                          ANSI_COLOR_RED, error.localizedDescription, ANSI_COLOR_RESET]);
            } else {
                NSLog(@"%@", [NSString stringWithFormat:@"%@Current Telegram tag: %@%@", 
                          ANSI_COLOR_GREEN, currentTag ?: @"<not set>", ANSI_COLOR_RESET]);
            }
            
            // Step 2: Update the Telegram tag
            NSLog(@"%@", [NSString stringWithFormat:@"%@STEP 2: Updating Telegram tag to: %@...%@", 
                      ANSI_COLOR_CYAN, newTelegramTag, ANSI_COLOR_RESET]);
            [[TelegramDirectManager sharedManager] updateTelegramTagWithToken:authToken telegramTag:newTelegramTag completion:^(BOOL success, NSError *updateError) {
                if (updateError) {
                    NSLog(@"%@", [NSString stringWithFormat:@"%@ERROR: Could not update tag: %@%@", 
                              ANSI_COLOR_RED, updateError.localizedDescription, ANSI_COLOR_RESET]);
                } else if (success) {
                    NSLog(@"%@", [NSString stringWithFormat:@"%@Successfully updated Telegram tag%@", 
                              ANSI_COLOR_GREEN, ANSI_COLOR_RESET]);
                } else {
                    NSLog(@"%@", [NSString stringWithFormat:@"%@Update operation completed but may not have succeeded%@", 
                              ANSI_COLOR_YELLOW, ANSI_COLOR_RESET]);
                }
                
                // Step 3: Verify the update
                NSLog(@"%@", [NSString stringWithFormat:@"%@STEP 3: Verifying update...%@", 
                          ANSI_COLOR_CYAN, ANSI_COLOR_RESET]);
                [[TelegramDirectManager sharedManager] fetchCurrentTelegramTagWithToken:authToken completion:^(NSString *verifiedTag, NSError *verifyError) {
                    if (verifyError) {
                        NSLog(@"%@", [NSString stringWithFormat:@"%@ERROR: Could not verify update: %@%@", 
                                  ANSI_COLOR_RED, verifyError.localizedDescription, ANSI_COLOR_RESET]);
                    } else {
                        NSString *cleanNewTag = newTelegramTag;
                        if ([cleanNewTag hasPrefix:@"@"]) {
                            cleanNewTag = [cleanNewTag substringFromIndex:1];
                        }
                        
                        NSString *cleanVerifiedTag = verifiedTag;
                        if ([cleanVerifiedTag hasPrefix:@"@"]) {
                            cleanVerifiedTag = [cleanVerifiedTag substringFromIndex:1];
                        }
                        
                        if ([cleanVerifiedTag isEqualToString:cleanNewTag]) {
                            NSLog(@"%@", [NSString stringWithFormat:@"%@VERIFICATION SUCCESSFUL: Tag is now %@%@", 
                                      ANSI_COLOR_GREEN, verifiedTag, ANSI_COLOR_RESET]);
                        } else {
                            NSLog(@"%@", [NSString stringWithFormat:@"%@VERIFICATION FAILED: Expected %@, but found %@%@", 
                                      ANSI_COLOR_RED, newTelegramTag, verifiedTag, ANSI_COLOR_RESET]);
                        }
                    }
                    
                    NSLog(@"==================================================");
                    NSLog(@"TELEGRAM TAG UPDATE TEST COMPLETED");
                    NSLog(@"==================================================");
                    
                    dispatch_group_leave(group);
                }];
            }];
        }];
        
        // Wait for up to 30 seconds for completion
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC);
        if (dispatch_group_wait(group, timeout) != 0) {
            NSLog(@"%@", [NSString stringWithFormat:@"%@ERROR: Test timed out after 30 seconds%@", 
                      ANSI_COLOR_RED, ANSI_COLOR_RESET]);
            return 1;
        }
        
        return 0;
    }
}

#endif // TELEGRAM_TEST_MAIN 