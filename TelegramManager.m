#import "TelegramManager.h"
#import "APIManager.h"
#import "TelegramDirectManager.h"

@implementation TelegramManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static TelegramManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

#pragma mark - API Methods

- (void)fetchTelegramTagWithToken:(NSString *)token completion:(void (^)(NSString *telegramTag, NSError *error))completion {
    // Try the direct PHP script first for optimal results
    [[TelegramDirectManager sharedManager] fetchCurrentTelegramTagWithToken:token completion:^(NSString *telegramTag, NSError *error) {
        if (!error && telegramTag != nil) {
            NSLog(@"[WeaponX] ✅ TELEGRAM: Fetched tag using direct script: %@", telegramTag);
            if (completion) completion(telegramTag, nil);
            return;
        }
        
        NSLog(@"[WeaponX] ⚠️ TELEGRAM: Direct script fetch failed, falling back to API: %@", error.localizedDescription);
        
        // If direct script fails, fall back to the original API method
        [self fetchTelegramTagUsingApiWithToken:token completion:completion];
    }];
}

- (void)fetchTelegramTagUsingApiWithToken:(NSString *)token completion:(void (^)(NSString *telegramTag, NSError *error))completion {
    NSLog(@"[WeaponX] 🔍 TELEGRAM DEBUG: Starting fetchTelegramTagUsingApiWithToken");
    
    NSString *urlString = [NSString stringWithFormat:@"%@/api/user/telegram", [APIManager sharedManager].baseURL];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Network error fetching telegram tag: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSError *statusError = [NSError errorWithDomain:@"com.weaponx.telegrammanager"
                                                       code:httpResponse.statusCode
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode]}];
            NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: HTTP error fetching telegram tag: %@", statusError.localizedDescription);
            if (completion) completion(nil, statusError);
            return;
        }
        
        NSError *jsonError = nil;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: JSON error parsing response: %@", jsonError.localizedDescription);
            if (completion) completion(nil, jsonError);
            return;
        }
        
        NSString *telegramTag = responseDict[@"telegram_tag"];
        NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Fetched telegram tag: %@", telegramTag ?: @"<none>");
        
        if (completion) completion(telegramTag, nil);
    }];
    
    [task resume];
}

- (void)updateTelegramTag:(NSString *)token 
               telegramTag:(NSString *)telegramTag 
                completion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] 🔍 TELEGRAM DEBUG: Starting updateTelegramTag with token: %@ and telegram tag: %@", 
          [self maskToken:token], telegramTag ?: @"<empty>");
    
    if (!token) {
        NSError *error = [NSError errorWithDomain:@"com.weaponx.telegrammanager"
                                             code:401
                                         userInfo:@{NSLocalizedDescriptionKey: @"No auth token provided"}];
        NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: No auth token provided for Telegram update");
        if (completion) completion(NO, error);
        return;
    }
    
    // Use the TelegramDirectManager to perform the update with our standalone PHP script
    [[TelegramDirectManager sharedManager] updateTelegramTagWithToken:token 
                                                         telegramTag:telegramTag 
                                                          completion:^(BOOL success, NSError *directError) {
        if (success) {
            NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Direct script update succeeded!");
            if (completion) completion(YES, nil);
            return;
        }
        
        NSLog(@"[WeaponX] ⚠️ TELEGRAM DEBUG: Direct script update failed with error: %@. Trying legacy methods...", directError.localizedDescription);
        
        // If direct script fails, try with legacy methods
        [self attemptLegacyTelegramUpdate:token telegramTag:telegramTag completion:completion];
    }];
}

- (void)attemptLegacyTelegramUpdate:(NSString *)token 
                       telegramTag:(NSString *)telegramTag 
                        completion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] 🔍 TELEGRAM DEBUG: Attempting legacy update methods...");
    
    // First try updating directly using the CSRF-exempt /direct/telegram endpoint
    [self updateTelegramTagUsingDirectRoute:token telegramTag:telegramTag completion:^(BOOL success, NSError *directError) {
        if (success) {
            NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Direct route update succeeded!");
            if (completion) completion(YES, nil);
            return;
        }
        
        NSLog(@"[WeaponX] ⚠️ TELEGRAM DEBUG: Direct route failed with error: %@. Trying CSRF token method...", directError.localizedDescription);
        
        // If direct route fails, try with CSRF token method
        // First we need to get a valid CSRF token from the server
        [self fetchCsrfTokenWithAuthToken:token completion:^(NSString *csrfToken, NSError *error) {
            if (error) {
                NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Failed to get CSRF token: %@", error.localizedDescription);
                if (completion) completion(NO, error);
                return;
            }
            
            NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Successfully obtained CSRF token: %@", csrfToken);
            
            // Now make the request to update the Telegram tag with the CSRF token
            NSString *urlString = [NSString stringWithFormat:@"%@/api/user/telegram", [APIManager sharedManager].baseURL];
            NSLog(@"[WeaponX] 📤 TELEGRAM DEBUG: Sending Telegram update request to: %@", urlString);
            
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
            [request setHTTPMethod:@"POST"];
            [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
            [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
            [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
            [request setValue:csrfToken forHTTPHeaderField:@"X-CSRF-TOKEN"];
            
            // Create the form body
            NSString *formBody = [NSString stringWithFormat:@"telegram_tag=%@", 
                                 [telegramTag ?: @"" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
            
            NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: Telegram update request body: %@", formBody);
            NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: Request headers: %@", [request allHTTPHeaderFields]);
            
            [request setHTTPBody:[formBody dataUsingEncoding:NSUTF8StringEncoding]];
            
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error) {
                    NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Network error updating telegram tag: %@", error.localizedDescription);
                    if (completion) completion(NO, error);
                    return;
                }
                
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSLog(@"[WeaponX] 📥 TELEGRAM DEBUG: Telegram update response code: %ld", (long)httpResponse.statusCode);
                NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: Response headers: %@", httpResponse.allHeaderFields);
                
                if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
                    NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"[WeaponX] 📥 TELEGRAM DEBUG: Response body: %@", responseString);
                    NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Telegram update error response: %@", responseString);
                    
                    NSError *statusError = [NSError errorWithDomain:@"com.weaponx.telegrammanager"
                                                             code:httpResponse.statusCode
                                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode]}];
                    if (completion) completion(NO, statusError);
                    return;
                }
                
                NSError *jsonError = nil;
                NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (jsonError) {
                    NSLog(@"[WeaponX] ⚠️ TELEGRAM DEBUG: JSON parsing error: %@", jsonError.localizedDescription);
                    // Still consider the update successful if we got a 2xx status code
                    if (completion) completion(YES, nil);
                    return;
                }
                
                NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Update successful with response: %@", responseDict);
                if (completion) completion(YES, nil);
            }];
            
            [task resume];
        }];
    }];
}

#pragma mark - Direct Route Method

- (void)updateTelegramTagUsingDirectRoute:(NSString *)token 
                             telegramTag:(NSString *)telegramTag 
                              completion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] 🔍 TELEGRAM DEBUG: Attempting direct route update for Telegram tag: %@", telegramTag ?: @"<empty>");
    
    // Use the '/direct/telegram' endpoint which is configured to bypass CSRF verification
    NSString *urlString = [NSString stringWithFormat:@"%@/direct/telegram", [APIManager sharedManager].baseURL];
    NSLog(@"[WeaponX] 📤 TELEGRAM DEBUG: Sending direct route Telegram update request to: %@", urlString);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    // Create the form body
    NSString *formBody = [NSString stringWithFormat:@"telegram_tag=%@", 
                         [telegramTag ?: @"" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: Direct route request body: %@", formBody);
    NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: Direct route request headers: %@", [request allHTTPHeaderFields]);
    
    [request setHTTPBody:[formBody dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Network error with direct route: %@", error.localizedDescription);
            if (completion) completion(NO, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📥 TELEGRAM DEBUG: Direct route response code: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: Direct route response headers: %@", httpResponse.allHeaderFields);
        
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[WeaponX] 📥 TELEGRAM DEBUG: Direct route response body: %@", responseString);
            NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Direct route error response: %@", responseString);
            
            NSError *statusError = [NSError errorWithDomain:@"com.weaponx.telegrammanager"
                                                     code:httpResponse.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %ld", (long)httpResponse.statusCode]}];
            if (completion) completion(NO, statusError);
            return;
        }
        
        NSError *jsonError = nil;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] ⚠️ TELEGRAM DEBUG: JSON parsing error from direct route: %@", jsonError.localizedDescription);
            // Still consider the update successful if we got a 2xx status code
            if (completion) completion(YES, nil);
            return;
        }
        
        NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Direct route update successful with response: %@", responseDict);
        if (completion) completion(YES, nil);
    }];
    
    [task resume];
}

#pragma mark - CSRF Token Handling

- (void)fetchCsrfTokenWithAuthToken:(NSString *)authToken completion:(void (^)(NSString *csrfToken, NSError *error))completion {
    NSLog(@"[WeaponX] 🔍 TELEGRAM DEBUG: Starting fetchCsrfTokenWithAuthToken");
    
    NSString *endpoint = [[APIManager sharedManager] apiUrlForEndpoint:@"csrf-token"];
    NSString *urlString = [endpoint stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", authToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    NSLog(@"[WeaponX] 📤 TELEGRAM DEBUG: Fetching CSRF token with URL: %@", urlString);
    NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: CSRF token request headers: %@", [request allHTTPHeaderFields]);
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Network error fetching CSRF token: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📥 TELEGRAM DEBUG: CSRF token response code: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] 📝 TELEGRAM DEBUG: CSRF token response headers: %@", httpResponse.allHeaderFields);
        
        // Try extracting CSRF token from cookies in response
        NSDictionary *headers = [httpResponse allHeaderFields];
        NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:headers forURL:[NSURL URLWithString:urlString]];
        NSString *csrfToken = nil;
        
        NSLog(@"[WeaponX] 🍪 TELEGRAM DEBUG: Found %lu cookies in response", (unsigned long)cookies.count);
        for (NSHTTPCookie *cookie in cookies) {
            NSLog(@"[WeaponX] 🍪 TELEGRAM DEBUG: Cookie: %@ = %@", cookie.name, cookie.value);
            if ([cookie.name isEqualToString:@"XSRF-TOKEN"]) {
                // Laravel stores the token URL-encoded in this cookie
                csrfToken = [cookie.value stringByRemovingPercentEncoding];
                NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Found CSRF token in cookie: %@", csrfToken);
                break;
            }
        }
        
        // Get the response body for debugging
        NSString *responseString = @"<none>";
        if (data) {
            responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<unable to decode>";
            NSLog(@"[WeaponX] 📥 TELEGRAM DEBUG: CSRF token response body: %@", responseString);
        }
        
        if (!csrfToken) {
            NSLog(@"[WeaponX] 🔍 TELEGRAM DEBUG: No CSRF token in cookies, trying JSON response");
            // If we can't find the cookie, try parsing response JSON that might contain the token
            if (data.length > 0) {
                NSError *jsonError = nil;
                NSDictionary *responseDict = nil;
                
                @try {
                    responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                }
                @catch (NSException *exception) {
                    NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Exception parsing JSON for CSRF token: %@", exception);
                }
                
                if (!jsonError && responseDict[@"csrf_token"]) {
                    csrfToken = responseDict[@"csrf_token"];
                    NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: Found CSRF token in JSON response: %@", csrfToken);
                } else if (jsonError) {
                    NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: JSON parsing error for CSRF token: %@", jsonError.localizedDescription);
                }
            }
        }
        
        if (!csrfToken) {
            // As a fallback, try a hardcoded value or use a special indicator for direct route
            NSLog(@"[WeaponX] ⚠️ TELEGRAM DEBUG: No CSRF token found, using fallback");
            csrfToken = @"direct-route";
        }
        
        NSLog(@"[WeaponX] ✅ TELEGRAM DEBUG: CSRF token obtained: %@", csrfToken);
        if (completion) completion(csrfToken, nil);
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
    if (telegramTag.length < 5 || telegramTag.length > 32) {
        NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Invalid tag length: %lu (should be 5-32)", (unsigned long)telegramTag.length);
        return NO;
    }
    
    // Validate characters (letters, numbers, underscores)
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    NSCharacterSet *invalidChars = [validChars invertedSet];
    
    // If the string contains any invalid characters, it's not valid
    NSRange invalidRange = [telegramTag rangeOfCharacterFromSet:invalidChars];
    if (invalidRange.location != NSNotFound) {
        NSLog(@"[WeaponX] ❌ TELEGRAM DEBUG: Invalid character in tag at position %lu", (unsigned long)invalidRange.location);
        return NO;
    }
    
    return YES;
}

- (NSString *)formatTelegramTagForDisplay:(NSString *)telegramTag {
    if (!telegramTag || [telegramTag isEqualToString:@""]) {
        return @"";
    }
    
    // Remove @ prefix if it exists, then add it back
    if ([telegramTag hasPrefix:@"@"]) {
        telegramTag = [telegramTag substringFromIndex:1];
    }
    
    return [NSString stringWithFormat:@"@%@", telegramTag];
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