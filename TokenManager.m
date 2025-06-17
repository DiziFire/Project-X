#import "TokenManager.h"
#import <SystemConfiguration/SystemConfiguration.h>

// Token-related keys for NSUserDefaults
static NSString *const kWeaponXAuthToken = @"WeaponXAuthToken";
static NSString *const kWeaponXServerUserId = @"WeaponXServerUserId";
static NSString *const kWeaponXTokenUserId = @"WeaponXTokenUserId";
static NSString *const kWeaponXLastTokenReset = @"WeaponXLastTokenReset";
static NSString *const kWeaponXTokenExpirationDate = @"WeaponXTokenExpirationDate";
static NSString *const kAuthSuiteName = @"com.hydra.projectx.authentication";

@interface TokenManager()
@property (nonatomic, strong) NSUserDefaults *authDefaults;
@end

@implementation TokenManager

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static TokenManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _authDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAuthSuiteName];
        
        // Migrate data from standard defaults if needed
        [self migrateFromStandardDefaults];
    }
    return self;
}

#pragma mark - Migration

- (void)migrateFromStandardDefaults {
    NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
    
    // Check if we've already migrated
    if ([self.authDefaults objectForKey:@"MigrationCompleted"]) {
        return;
    }
    
    // Migrate token data
    NSString *token = [standardDefaults objectForKey:kWeaponXAuthToken];
    if (token) {
        [self.authDefaults setObject:token forKey:kWeaponXAuthToken];
    }
    
    // Migrate user ID
    NSString *userId = [standardDefaults objectForKey:kWeaponXServerUserId];
    if (userId) {
        [self.authDefaults setObject:userId forKey:kWeaponXServerUserId];
    }
    
    // Migrate token user ID
    NSString *tokenUserId = [standardDefaults objectForKey:kWeaponXTokenUserId];
    if (tokenUserId) {
        [self.authDefaults setObject:tokenUserId forKey:kWeaponXTokenUserId];
    }
    
    // Migrate last token reset
    NSNumber *lastReset = [standardDefaults objectForKey:kWeaponXLastTokenReset];
    if (lastReset) {
        [self.authDefaults setObject:lastReset forKey:kWeaponXLastTokenReset];
    }
    
    // Migrate token expiration date
    NSDate *expirationDate = [standardDefaults objectForKey:kWeaponXTokenExpirationDate];
    if (expirationDate) {
        [self.authDefaults setObject:expirationDate forKey:kWeaponXTokenExpirationDate];
    }
    
    // Mark migration as completed
    [self.authDefaults setBool:YES forKey:@"MigrationCompleted"];
    [self.authDefaults synchronize];
}

#pragma mark - Token Validation

/**
 * Convenience method to get the current token
 */
- (NSString *)token {
    return [self getCurrentToken];
}

- (BOOL)isTokenValid {
    NSString *token = [self getCurrentToken];
    if (!token || token.length == 0) {
        return NO;
    }
    
    // Check if token is expired
    if (![self isTokenExpired]) {
        return YES;
    }
    
    // Check if device is offline
    if (![self isNetworkReachable]) {
        // If offline, check if we're within the grace period (24 hours after expiration)
        if ([self isWithinOfflineGracePeriod]) {
            return YES;
        }
        return NO;
    }
    
    // Token is expired, try to refresh it
    NSString *userId = [self getServerUserId];
    if (userId) {
        [self refreshTokenIfNeeded];
        // Return NO here as the refresh is asynchronous
        return NO;
    }
    
    return NO;
}

- (BOOL)isNetworkReachable {
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "hydra.weaponx.us");
    
    SCNetworkReachabilityFlags flags;
    BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
    
    CFRelease(reachability);
    
    if (!success) {
        return NO;
    }
    
    BOOL isReachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    
    return isReachable && !needsConnection;
}

- (BOOL)isWithinOfflineGracePeriod {
    // Check if we're within the grace period for offline token usage
    // The grace period is 24 hours after token expiration
    
    NSDate *expirationDate = [self.authDefaults objectForKey:kWeaponXTokenExpirationDate];
    
    // Fallback to standard defaults if not found in auth defaults
    if (!expirationDate) {
        expirationDate = [[NSUserDefaults standardUserDefaults] objectForKey:kWeaponXTokenExpirationDate];
    }
    
    // If no expiration date is set, we're not within the grace period
    if (!expirationDate) {
        return NO;
    }
    
    // Calculate the end of the grace period (24 hours after expiration)
    NSDate *graceEndDate = [expirationDate dateByAddingTimeInterval:24 * 60 * 60]; // 24 hours in seconds
    
    // Check if current date is before the end of the grace period
    NSDate *currentDate = [NSDate date];
    
    // If current date is before grace period end, we're within the grace period
    if ([currentDate compare:graceEndDate] == NSOrderedAscending) {
        return YES;
    }
    
    return NO;
}

- (BOOL)isTokenExpired {
    NSDate *expirationDate = [self.authDefaults objectForKey:kWeaponXTokenExpirationDate];
    
    // Fallback to standard defaults if not found in auth defaults
    if (!expirationDate) {
        expirationDate = [[NSUserDefaults standardUserDefaults] objectForKey:kWeaponXTokenExpirationDate];
    }
    
    // If no expiration date is set, consider the token as potentially expired
    if (!expirationDate) {
        return YES;
    }
    
    // Check if current date is past the expiration date
    NSDate *currentDate = [NSDate date];
    
    // If the token will expire in the next 30 minutes, consider it as expired
    // to proactively refresh it
    NSTimeInterval timeUntilExpiration = [expirationDate timeIntervalSinceDate:currentDate];
    NSTimeInterval refreshThreshold = 30 * 60; // 30 minutes in seconds
    
    if (timeUntilExpiration <= refreshThreshold) {
        return YES;
    }
    
    return NO;
}

- (void)refreshTokenIfNeeded {
    if ([self isTokenExpired]) {
        NSString *userId = [self getServerUserId];
        if (userId) {
            [self resetTokenForUserId:userId completion:^(NSString *newToken, NSError *error) {
                if (error) {
                    // Removed NSLog: Failed to refresh token
                } else if (newToken) {
                    // Removed NSLog: Successfully refreshed token
                    // Update token expiration date
                    [self updateTokenExpirationDate];
                }
            }];
        }
    }
}

- (void)updateTokenExpirationDate {
    // Set token expiration date to 24 hours from now (matching server config)
    NSDate *expirationDate = [[NSDate date] dateByAddingTimeInterval:24 * 60 * 60]; // 24 hours in seconds
    
    [self.authDefaults setObject:expirationDate forKey:kWeaponXTokenExpirationDate];
    [self.authDefaults synchronize];
    
    // Removed NSLog: Token expiration date set
}

- (NSString *)getCurrentToken {
    NSString *token = [self.authDefaults objectForKey:kWeaponXAuthToken];
    
    // Fallback to standard defaults if not found in auth defaults
    if (!token) {
        token = [[NSUserDefaults standardUserDefaults] objectForKey:kWeaponXAuthToken];
    }
    
    return token;
}

- (NSString *)getServerUserId {
    NSString *serverUserId = [self.authDefaults objectForKey:kWeaponXServerUserId];
    if (serverUserId) {
        return serverUserId;
    }
    
    // If no server user ID found, use token ID as fallback
    NSString *tokenId = [self getTokenUserId];
    if (tokenId) {
        return tokenId;
    }
    
    return nil;
}

- (NSString *)getTokenUserId {
    NSString *tokenUserId = [self.authDefaults objectForKey:kWeaponXTokenUserId];
    
    // Fallback to standard defaults if not found in auth defaults
    if (!tokenUserId) {
        tokenUserId = [[NSUserDefaults standardUserDefaults] objectForKey:kWeaponXTokenUserId];
    }
    
    return tokenUserId;
}

#pragma mark - Token Operations

- (void)saveToken:(NSString *)token withUserId:(NSString *)userId {
    if (!token || token.length == 0) {
        // Removed NSLog: Cannot save empty token
        return;
    }
    
    // Save the token
    [self.authDefaults setObject:token forKey:kWeaponXAuthToken];
    
    // Save the server user ID - This is the REAL user ID
    if (userId) {
        [self.authDefaults setObject:userId forKey:kWeaponXServerUserId];
        // Removed NSLog: Server user ID saved
    } else {
        // Removed NSLog: WARNING: No user ID provided when saving token
    }
    
    // Extract and save the token ID (for debugging only)
    NSArray *tokenParts = [token componentsSeparatedByString:@"|"];
    if (tokenParts.count > 0) {
        NSString *tokenId = tokenParts[0];
        [self.authDefaults setObject:tokenId forKey:kWeaponXTokenUserId];
        
        // Check for mismatch and log warning - this is expected and not a real issue
        if (userId && ![tokenId isEqualToString:userId]) {
            // Removed NSLog: INFO: Token ID doesn't match user ID
        }
    }
    
    // Update token expiration date
    [self updateTokenExpirationDate];
    
    [self.authDefaults synchronize];
    
    // Also save to standard defaults for backward compatibility
    // This ensures other components that haven't been updated yet still work
    NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
    [standardDefaults setObject:token forKey:kWeaponXAuthToken];
    if (userId) {
        [standardDefaults setObject:userId forKey:kWeaponXServerUserId];
    }
    NSDate *expirationDate = [self.authDefaults objectForKey:kWeaponXTokenExpirationDate];
    if (expirationDate) {
        [standardDefaults setObject:expirationDate forKey:kWeaponXTokenExpirationDate];
    }
    [standardDefaults synchronize];
}

- (void)resetTokenForUserId:(NSString *)userId completion:(void (^)(NSString *newToken, NSError *error))completion {
    if (!userId || userId.length == 0) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"TokenManagerErrorDomain" 
                                                 code:1 
                                             userInfo:@{NSLocalizedDescriptionKey: @"No user ID provided"}];
            completion(nil, error);
        }
        return;
    }
    
    // Check if we've recently attempted a token reset to prevent excessive requests
    NSNumber *lastResetTime = [self.authDefaults objectForKey:kWeaponXLastTokenReset];
    
    // Fallback to standard defaults if not found in auth defaults
    if (!lastResetTime) {
        lastResetTime = [[NSUserDefaults standardUserDefaults] objectForKey:kWeaponXLastTokenReset];
    }
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    // Increase rate limit from 2 seconds to 10 seconds to prevent excessive reset attempts
    if (lastResetTime && (currentTime - lastResetTime.doubleValue < 10.0)) {
        // Get the current token to return anyway, so the caller can try to use it
        NSString *currentToken = [self getCurrentToken];
        if (currentToken && currentToken.length > 0) {
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"TokenManagerErrorDomain" 
                                                     code:2 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Rate limited token reset"}];
                completion(currentToken, error);
            }
        } else {
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"TokenManagerErrorDomain" 
                                                     code:2 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Rate limited token reset"}];
                completion(nil, error);
            }
        }
        return;
    }
    
    // Update last reset time
    [self.authDefaults setObject:@(currentTime) forKey:kWeaponXLastTokenReset];
    [self.authDefaults synchronize];
    
    // Also update in standard defaults for backward compatibility
    [[NSUserDefaults standardUserDefaults] setObject:@(currentTime) forKey:kWeaponXLastTokenReset];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Construct the reset URL
    NSString *baseUrl = [self apiBaseUrl];
    NSString *resetUrl = [NSString stringWithFormat:@"%@/reset-usertoken.php?user_id=%@", baseUrl, userId];
    
    // Clear URL cache before making the request
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:resetUrl]];
    
    // Add useful headers for debugging
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:userId forHTTPHeaderField:@"X-Expected-User-Id"];
    
    // Add app version info to help with troubleshooting
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [infoDictionary objectForKey:@"CFBundleVersion"];
    [request setValue:[NSString stringWithFormat:@"%@-%@", appVersion, buildNumber] forHTTPHeaderField:@"X-App-Version"];
    
    // Add the current token ID for diagnostic purposes
    NSString *currentToken = [self getCurrentToken];
    if (currentToken) {
        NSArray *tokenParts = [currentToken componentsSeparatedByString:@"|"];
        if (tokenParts.count > 0) {
            [request setValue:tokenParts[0] forHTTPHeaderField:@"X-Current-Token-Id"];
        }
    }
    
    // Add cache control headers
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:[NSString stringWithFormat:@"%lld", (long long)currentTime] forHTTPHeaderField:@"X-Timestamp"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *httpError = [NSError errorWithDomain:@"TokenManagerErrorDomain" 
                                                             code:httpResponse.statusCode 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to reset token"}];
                    completion(nil, httpError);
                });
            }
            return;
        }
        
        if (data) {
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, jsonError);
                    });
                }
                return;
            }
            
            // Try to extract the new token from the response
            NSString *newToken = nil;
            
            // Check if response is properly formatted with a data object containing new_token
            if ([responseDict isKindOfClass:[NSDictionary class]]) {
                // First, check for the new Laravel response format: { success: true, message: '...', data: { new_token: '...' } }
                id dataObj = responseDict[@"data"];
                
                if ([dataObj isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *data = (NSDictionary *)dataObj;
                    id newTokenObj = data[@"new_token"];
                    
                    if (newTokenObj) {
                        newToken = [NSString stringWithFormat:@"%@", newTokenObj];
                    }
                } 
                // Fallback to direct property for backward compatibility
                else if (responseDict[@"new_token"]) {
                    newToken = [NSString stringWithFormat:@"%@", responseDict[@"new_token"]];
                }
                // Old format check
                else if (responseDict[@"token"]) {
                    newToken = [NSString stringWithFormat:@"%@", responseDict[@"token"]];
                }
            }
            
            if (newToken) {
                // Extract the token ID (not user ID) from the new token
                NSString *tokenId = nil;
                NSArray *tokenParts = [newToken componentsSeparatedByString:@"|"];
                if (tokenParts.count > 0) {
                    tokenId = tokenParts[0];
                }
                
                if (tokenId && ![tokenId isEqualToString:userId]) {
                    // ALWAYS store the user ID for proper authentication
                    [self.authDefaults setObject:userId forKey:kWeaponXServerUserId];
                    
                    // Store token ID for debugging
                    if (tokenId) {
                        [self.authDefaults setObject:tokenId forKey:kWeaponXTokenUserId];
                    }
                    
                    [self.authDefaults synchronize];
                } else if (tokenId) {
                    NSLog(@"[WeaponX] Unusual: Token ID matches user ID: %@", tokenId);
                }
                
                // Save the new token - this will also store the IDs
                [self saveToken:newToken withUserId:userId];
                
                // Add a delay before returning the new token to ensure server propagation
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    // Removed NSLog: Waiting 2 seconds after token reset
                    if (completion) {
                        completion(newToken, nil);
                    }
                });
                return;
            }
            
            // Removed NSLog: Token reset response did not contain a new token
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *dataError = [NSError errorWithDomain:@"TokenManagerErrorDomain" 
                                                            code:0 
                                                        userInfo:@{NSLocalizedDescriptionKey: @"No new token in response"}];
                    completion(nil, dataError);
                });
            }
        } else {
            // Removed NSLog: No data received from token reset endpoint
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *noDataError = [NSError errorWithDomain:@"TokenManagerErrorDomain" 
                                                              code:0 
                                                          userInfo:@{NSLocalizedDescriptionKey: @"No data received"}];
                    completion(nil, noDataError);
                });
            }
        }
    }];
    
    [task resume];
}

- (void)clearToken {
    [self.authDefaults removeObjectForKey:kWeaponXAuthToken];
    [self.authDefaults removeObjectForKey:kWeaponXServerUserId];
    [self.authDefaults removeObjectForKey:kWeaponXTokenUserId];
    [self.authDefaults removeObjectForKey:kWeaponXLastTokenReset];
    [self.authDefaults removeObjectForKey:kWeaponXTokenExpirationDate];
    [self.authDefaults synchronize];
    // Removed NSLog: Token cleared
}

#pragma mark - Token ID Extraction

- (NSString *)extractUserIdFromToken:(NSString *)token {
    if (!token || token.length == 0) {
        // Removed NSLog: Cannot extract user ID from empty token
        return nil;
    }
    
    // IMPORTANT: The token ID (first part before pipe) is NOT the user ID
    // It's the token's database ID, not the user's ID
    // We should ALWAYS use the stored server user ID instead
    
    NSString *serverUserId = [self getServerUserId];
    if (serverUserId) {
        // Removed NSLog: Using stored server user ID
        return serverUserId;
    }
    
    // Extract token ID for debugging purposes only
    NSArray *tokenParts = [token componentsSeparatedByString:@"|"];
    if (tokenParts.count > 0) {
        NSString *tokenId = tokenParts[0];
        // Removed NSLog: WARNING: No server user ID found, using token ID as fallback
        // Removed NSLog: WARNING: This may cause authentication issues
        
        // Save to defaults for future reference
        [self.authDefaults setObject:tokenId forKey:kWeaponXTokenUserId];
        [self.authDefaults synchronize];
        
        return tokenId;
    }
    
    // Removed NSLog: Failed to extract any ID from token format
    return nil;
}

// Helper method to mask token for logging
- (NSString *)maskToken:(NSString *)token {
    if (!token || token.length == 0) {
        return @"[empty]";
    }
    
    NSArray *tokenParts = [token componentsSeparatedByString:@"|"];
    if (tokenParts.count > 1) {
        NSString *tokenId = tokenParts[0];
        NSString *tokenValue = tokenParts[1];
        
        // Only show first and last few characters of the token value
        NSString *masked;
        if (tokenValue.length > 6) {
            masked = [NSString stringWithFormat:@"%@|%@...%@", 
                      tokenId, 
                      [tokenValue substringToIndex:1],
                      [tokenValue substringFromIndex:tokenValue.length - 5]];
        } else {
            masked = [NSString stringWithFormat:@"%@|%@", tokenId, @"*****"];
        }
        
        return masked;
    }
    
    // If token format is unexpected, just mask it
    if (token.length > 10) {
        return [NSString stringWithFormat:@"%@...%@", 
                [token substringToIndex:3],
                [token substringFromIndex:token.length - 3]];
    }
    
    return @"***";
}

#pragma mark - Request Helpers

- (NSDictionary *)getAuthorizationHeaders {
    NSString *token = [self getCurrentToken];
    NSString *serverUserId = [self getServerUserId];
    NSString *tokenUserId = [self getTokenUserId];
    
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    
    if (token) {
        // Make sure token is properly formatted for Authorization header
        if (![token hasPrefix:@"Bearer "]) {
            [headers setObject:[NSString stringWithFormat:@"Bearer %@", token] forKey:@"Authorization"];
        } else {
            [headers setObject:token forKey:@"Authorization"];
        }
    }
    
    // Always use server user ID if available for proper identification
    if (serverUserId) {
        [headers setObject:serverUserId forKey:@"X-User-Id"];
    } else if (tokenUserId) {
        // Fallback only if no server user ID is available
        [headers setObject:tokenUserId forKey:@"X-User-Id"];
    }
    
    // Add token ID for debugging only
    if (tokenUserId && serverUserId && ![tokenUserId isEqualToString:serverUserId]) {
        [headers setObject:tokenUserId forKey:@"X-Token-Id"];
    }
    
    // Add Content-Type and Accept headers
    [headers setObject:@"application/json" forKey:@"Content-Type"];
    [headers setObject:@"application/json" forKey:@"Accept"];
    
    // Add cache control headers
    [headers setObject:@"no-cache" forKey:@"Cache-Control"];
    [headers setObject:[NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]] forKey:@"X-Timestamp"];
    
    return headers;
}

- (BOOL)handleUnauthorizedResponse:(NSHTTPURLResponse *)response forUserId:(NSString *)userId completion:(void (^)(BOOL tokenReset))completion {
    if (response.statusCode != 401) {
        // Not an unauthorized response
        if (completion) {
            completion(NO);
        }
        return NO;
    }
    
    // If no user ID provided, try to get from stored value
    if (!userId) {
        userId = [self getServerUserId];
    }
    
    if (!userId) {
        if (completion) {
            completion(NO);
        }
        return NO;
    }
    
    // Try to reset the token
    [self resetTokenForUserId:userId completion:^(NSString *newToken, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO);
            }
        } else if (newToken) {
            // Force invalidate NSURLCache to ensure no cached responses are used
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            
            if (completion) {
                // Add a delay to allow token to propagate on server
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    completion(YES);
                });
            }
        } else {
            if (completion) {
                completion(NO);
            }
        }
    }];
    
    return YES;
}

#pragma mark - Helpers

- (NSString *)apiBaseUrl {
    // Return the base URL for the API - always use production URL
    return @"https://hydra.weaponx.us";
}

@end