#import <Foundation/Foundation.h>

@interface TokenManager : NSObject

+ (instancetype)sharedInstance;

/**
 * Gets the current authentication token
 */
- (NSString *)token;

/**
 * Checks if the current token is valid
 */
- (BOOL)isTokenValid;

/**
 * Refreshes the token if needed
 */
- (void)refreshTokenIfNeeded;

/**
 * Saves a token for a specific user ID
 */
- (void)saveToken:(NSString *)token withUserId:(NSString *)userId;

/**
 * Gets the user ID associated with the current token
 */
- (NSString *)getTokenUserId;

/**
 * Clears the authentication token
 */
- (void)clearToken;

/**
 * Resets the token for a specific user ID
 */
- (void)resetTokenForUserId:(NSString *)userId completion:(void (^)(NSString *newToken, NSError *error))completion;

// Token validation
- (NSString *)getCurrentToken;
- (NSString *)getServerUserId;
- (BOOL)isTokenExpired;
- (BOOL)isNetworkReachable;
- (BOOL)isWithinOfflineGracePeriod;

// Token ID extraction
- (NSString *)extractUserIdFromToken:(NSString *)token;

// Request helpers
- (NSDictionary *)getAuthorizationHeaders;
- (BOOL)handleUnauthorizedResponse:(NSHTTPURLResponse *)response forUserId:(NSString *)userId completion:(void (^)(BOOL tokenReset))completion;

// Server URL helper
- (NSString *)apiBaseUrl;

@end