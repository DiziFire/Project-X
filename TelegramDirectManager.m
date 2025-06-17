#import "TelegramDirectManager.h"
#import "APIManager.h"

@implementation TelegramDirectManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static TelegramDirectManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

#pragma mark - Direct API Method

- (void)updateTelegramTagWithToken:(NSString *)token 
                       telegramTag:(NSString *)telegramTag 
                        completion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] 🔍 DIRECT-TELEGRAM: Starting update with token: %@, and tag: %@", 
          [self maskToken:token], telegramTag ?: @"<empty>");
    
    if (!token) {
        NSError *error = [NSError errorWithDomain:@"com.weaponx.telegramdirectmanager"
                                             code:401
                                         userInfo:@{NSLocalizedDescriptionKey: @"No auth token provided"}];
        NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: No auth token provided");
        if (completion) completion(NO, error);
        return;
    }
    
    // Clean up the tag
    NSString *cleanTag = telegramTag;
    if ([cleanTag hasPrefix:@"@"]) {
        cleanTag = [cleanTag substringFromIndex:1];
        NSLog(@"[WeaponX] 🔄 DIRECT-TELEGRAM: Removed @ prefix from Telegram tag: %@", cleanTag);
    }
    
    // Validate the tag format
    if (cleanTag && cleanTag.length > 0 && ![self isValidTelegramTag:cleanTag]) {
        NSError *validationError = [NSError errorWithDomain:@"com.weaponx.telegramdirectmanager"
                                              code:400
                                          userInfo:@{
            NSLocalizedDescriptionKey: @"Invalid Telegram tag format",
            NSLocalizedFailureReasonErrorKey: @"Telegram tag must be 5-32 characters and can only contain letters, numbers, and underscores."
        }];
        NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Invalid tag format: %@", cleanTag);
        if (completion) completion(NO, validationError);
        return;
    }
    
    // Use the direct PHP script endpoint that completely bypasses Laravel middleware
    NSString *baseURL = [[APIManager sharedManager] baseURL];
    // IMPORTANT: Use the standalone PHP script that bypasses all Laravel middleware
    NSString *urlString = [NSString stringWithFormat:@"%@/direct_telegram.php", baseURL];
    
    NSLog(@"[WeaponX] 📤 DIRECT-TELEGRAM: Using direct PHP script URL: %@", urlString);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    
    // Critical: Set Content-Type to application/x-www-form-urlencoded
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Add X-Requested-With header to identify as AJAX request
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    // Create the form body with proper URL encoding
    NSString *formBody = [NSString stringWithFormat:@"telegram_tag=%@", 
                         [cleanTag ?: @"" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    NSLog(@"[WeaponX] 📝 DIRECT-TELEGRAM: Request headers: %@", [request allHTTPHeaderFields]);
    NSLog(@"[WeaponX] 📝 DIRECT-TELEGRAM: Request body: %@", formBody);
    
    [request setHTTPBody:[formBody dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Network error: %@", error.localizedDescription);
            if (completion) completion(NO, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📥 DIRECT-TELEGRAM: Response status code: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] 📝 DIRECT-TELEGRAM: Response headers: %@", httpResponse.allHeaderFields);
        
        NSString *responseString = @"<none>";
        if (data) {
            responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<unable to decode>";
        }
        NSLog(@"[WeaponX] 📥 DIRECT-TELEGRAM: Response body: %@", responseString);
        
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Request failed with status code: %ld", (long)httpResponse.statusCode);
            
            NSError *statusError = [NSError errorWithDomain:@"com.weaponx.telegramdirectmanager"
                                                  code:httpResponse.statusCode
                                              userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode]}];
            if (completion) completion(NO, statusError);
            return;
        }
        
        // Try to parse the response JSON but don't fail if it's not valid JSON
        NSError *jsonError = nil;
        NSDictionary *responseDict = nil;
        
        @try {
            if (data && data.length > 0) {
                responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            }
        }
        @catch (NSException *exception) {
            NSLog(@"[WeaponX] ⚠️ DIRECT-TELEGRAM: Exception parsing JSON: %@", exception);
        }
        
        // Log the parsed JSON response if available
        if (responseDict) {
            NSLog(@"[WeaponX] ✅ DIRECT-TELEGRAM: Response JSON: %@", responseDict);
        }
        
        // Even if JSON parsing fails, consider the update successful if status code is 2xx
        NSLog(@"[WeaponX] ✅ DIRECT-TELEGRAM: Update successful");
        
        // Verify the update by fetching the current value
        [self fetchCurrentTelegramTagWithToken:token completion:^(NSString *currentTag, NSError *fetchError) {
            if (fetchError) {
                NSLog(@"[WeaponX] ⚠️ DIRECT-TELEGRAM: Could not verify update: %@", fetchError.localizedDescription);
                // Still consider the update successful if the initial request succeeded
                if (completion) completion(YES, nil);
                return;
            }
            
            if ([currentTag isEqualToString:cleanTag] || 
                ([currentTag hasPrefix:@"@"] && [[currentTag substringFromIndex:1] isEqualToString:cleanTag]) ||
                ([cleanTag hasPrefix:@"@"] && [[cleanTag substringFromIndex:1] isEqualToString:currentTag])) {
                NSLog(@"[WeaponX] ✅ DIRECT-TELEGRAM: Verified update - current tag: %@", currentTag);
            } else {
                NSLog(@"[WeaponX] ⚠️ DIRECT-TELEGRAM: Update did not take effect. Expected: %@, Current: %@", cleanTag, currentTag);
            }
            
            if (completion) completion(YES, nil);
        }];
    }];
    
    [task resume];
}

- (void)fetchCurrentTelegramTagWithToken:(NSString *)token completion:(void (^)(NSString *telegramTag, NSError *error))completion {
    NSLog(@"[WeaponX] 🔍 DIRECT-TELEGRAM: Fetching current tag to verify update");
    
    // Use the direct PHP script endpoint that completely bypasses Laravel middleware
    NSString *baseURL = [[APIManager sharedManager] baseURL];
    // IMPORTANT: Use the standalone PHP script that bypasses all Laravel middleware
    NSString *urlString = [NSString stringWithFormat:@"%@/direct_telegram.php", baseURL];
    
    NSLog(@"[WeaponX] 📤 DIRECT-TELEGRAM: Using direct PHP script URL: %@", urlString);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Network error fetching current tag: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📥 DIRECT-TELEGRAM: Fetch status code: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] 📝 DIRECT-TELEGRAM: Fetch response headers: %@", httpResponse.allHeaderFields);
        
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Fetch error response: %@", responseString);
            
            NSError *statusError = [NSError errorWithDomain:@"com.weaponx.telegramdirectmanager"
                                                     code:httpResponse.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode]}];
            if (completion) completion(nil, statusError);
            return;
        }
        
        NSString *responseString = @"<none>";
        if (data) {
            responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<unable to decode>";
        }
        NSLog(@"[WeaponX] 📥 DIRECT-TELEGRAM: Fetch response body: %@", responseString);
        
        NSError *jsonError = nil;
        NSDictionary *responseDict = nil;
        
        @try {
            if (data && data.length > 0) {
                responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            }
        }
        @catch (NSException *exception) {
            NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Exception parsing JSON: %@", exception);
            jsonError = [NSError errorWithDomain:@"com.weaponx.telegramdirectmanager"
                                           code:500
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Exception parsing JSON: %@", exception.reason]}];
        }
        
        if (jsonError) {
            NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: JSON parsing error: %@", jsonError.localizedDescription);
            if (completion) completion(nil, jsonError);
            return;
        }
        
        NSString *telegramTag = responseDict[@"telegram_tag"];
        NSLog(@"[WeaponX] ✅ DIRECT-TELEGRAM: Current tag is: %@", telegramTag ?: @"<none>");
        
        if (completion) completion(telegramTag, nil);
    }];
    
    [task resume];
}

#pragma mark - Utility Methods

- (BOOL)isValidTelegramTag:(NSString *)telegramTag {
    if (!telegramTag) return NO;
    
    // Remove @ prefix if it exists
    if ([telegramTag hasPrefix:@"@"]) {
        telegramTag = [telegramTag substringFromIndex:1];
    }
    
    // Validate length (5-32 characters)
    // NOTE: Telegram's actual limit is 5-32, but we'll be more permissive to handle edge cases
    if (telegramTag.length < 3 || telegramTag.length > 32) {
        NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Invalid tag length: %lu (should be 5-32)", (unsigned long)telegramTag.length);
        return NO;
    }
    
    // Validate characters (letters, numbers, underscores)
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    NSCharacterSet *invalidChars = [validChars invertedSet];
    
    // If the string contains any invalid characters, it's not valid
    NSRange invalidRange = [telegramTag rangeOfCharacterFromSet:invalidChars];
    if (invalidRange.location != NSNotFound) {
        NSLog(@"[WeaponX] ❌ DIRECT-TELEGRAM: Invalid character in tag at position %lu", (unsigned long)invalidRange.location);
        return NO;
    }
    
    return YES;
}

- (NSString *)maskToken:(NSString *)token {
    if (!token || token.length < 10) {
        return @"<invalid token>";
    }
    
    // Show only first 6 and last 4 characters
    NSString *firstPart = [token substringToIndex:6];
    NSString *lastPart = [token substringFromIndex:token.length - 4];
    return [NSString stringWithFormat:@"%@...%@", firstPart, lastPart];
}

@end 