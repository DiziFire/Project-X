#include <stdlib.h>
#import "APIManager.h"
#import "SecureTimeManager.h"
#import "TokenManager.h"
#import <UIKit/UIKit.h>
#import <IOKit/IOKitLib.h>
#import <sys/utsname.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h> // For chmod
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <SystemConfiguration/SystemConfiguration.h> // For network reachability

@interface APIManager () <NSURLSessionDelegate>
@property (nonatomic, strong) NSString *csrfToken;
@property (nonatomic, strong) NSString *currentScreen;
@property (nonatomic, strong) NSString *authToken;

// Add a method to check network reachability
- (BOOL)isNetworkAvailable;
@end

@implementation APIManager {
    NSURLSession *_session;
    SCNetworkReachabilityRef reachabilityRef;
    BOOL _isRefreshingPlan; // Add flag to track if plan refresh is in progress
    NSMutableDictionary *_csrfTokens;
    NSDate *_lastCsrfTokenFetchTime;
    NSMutableArray *_queuedHeartbeats; // Add this line for the queued heartbeats
}

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static APIManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize base URL
        _baseURLString = @"https://hydra.weaponx.us";
        
        // Create a session configuration with custom timeout
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30.0;  // 30 second timeout
        config.timeoutIntervalForResource = 60.0; // 60 second timeout for resources
        
        // Create a custom URL session
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
        
        // Initialize CSRF token cache
        _csrfTokens = [NSMutableDictionary dictionary];
        
        // Initialize heartbeat queue
        _queuedHeartbeats = [NSMutableArray array];
        
        // Register for network status change notifications
        [self registerForNetworkStatusChanges];
        
        // Set initial network status
        [self isNetworkAvailable]; // This will set initial state and post appropriate notifications
        
        // Initialize session configuration
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        
        // Initialize network availability to YES by default, will check later
        self.isOnline = YES;
        
        // Setup enhanced network monitoring
        // Initialize network status
    }
    return self;
}

#pragma mark - App State Handling

// Handle app becoming active
- (void)applicationDidBecomeActive:(NSNotification *)notification {
    NSLog(@"[WeaponX] 🔄 App became active - checking authentication");
    
    // Check previous network status
    BOOL wasOnline = self.isOnline;
    
    // Update network status
    BOOL isOnlineNow = [self isNetworkAvailable];
    
    // If we were offline but now we're online, verify plan data
    if (!wasOnline && isOnlineNow) {
        NSLog(@"[WeaponX] 🌐 Network status changed: OFFLINE -> ONLINE");
        
        // Post network status changed notification
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXNetworkStatusChanged" 
                                                          object:nil 
                                                        userInfo:@{@"isOnline": @(YES)}];
        
        // Post the specific "network became available" notification
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXNetworkBecameAvailable" 
                                                          object:nil];
        
        // Verify plan data since we're back online
        NSString *token = [self getAuthToken];
        if (token) {
            NSLog(@"[WeaponX] 🔄 Verifying plan data after coming back online");
            [self refreshPlanData:token];
        }
    } 
    else if (wasOnline && !isOnlineNow) {
        NSLog(@"[WeaponX] 🌐 Network status changed: ONLINE -> OFFLINE");
        
        // Post network status changed notification
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXNetworkStatusChanged" 
                                                          object:nil 
                                                        userInfo:@{@"isOnline": @(NO)}];
        
        // Post the specific "network became unavailable" notification
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXNetworkBecameUnavailable" 
                                                          object:nil];
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults objectForKey:@"WeaponXAuthToken"];
    NSString *userId = [defaults objectForKey:@"WeaponXServerUserId"];
    
    // Check if we need to reset plan data hash
    BOOL needsReVerification = [defaults boolForKey:@"WeaponXNeedsReVerification"];
    if (needsReVerification && isOnlineNow && token) {
        NSLog(@"[WeaponX] 🔄 Re-verification needed, refreshing plan data");
        [self refreshPlanData:token];
    }
    
    NSLog(@"[WeaponX] 🔍 Stored user ID: %@, Has token: %@", 
          userId ?: @"none", 
          token ? @"YES" : @"NO");
    
    if (token) {
        NSLog(@"[WeaponX] 🔑 Found stored token: %@...", 
              [token substringToIndex:MIN(10, token.length)]);
        
        // Update presence status to "online"
        if (userId) {
            NSLog(@"[WeaponX] 📡 Updating user presence for userId: %@", userId);
            [self updateUserPresence:userId status:@"online" completion:^(BOOL success, NSError *error) {
                if (success) {
                    NSLog(@"[WeaponX] ✅ Successfully updated presence to online");
                    
                    // Explicitly start heartbeat with confirmed userId
                    NSLog(@"[WeaponX] 🔄 Starting heartbeat from applicationDidBecomeActive with userId: %@", userId);
                    [self startHeartbeat:userId];
                } else {
                    NSLog(@"[WeaponX] ⚠️ Failed to update presence: %@", error);
                }
            }];
        } else {
            NSLog(@"[WeaponX] ⚠️ Have token but no userId - fetching user data");
            // We have a token but no user ID, fetch the user data
            [self fetchUserDataWithToken:token completion:^(NSDictionary *userData, NSError *error) {
                if (userData && userData[@"id"]) {
                    NSString *fetchedUserId = [NSString stringWithFormat:@"%@", userData[@"id"]];
                    NSLog(@"[WeaponX] ✅ Fetched user data - starting heartbeat with userId: %@", fetchedUserId);
                    [self startHeartbeat:fetchedUserId];
                } else {
                    NSLog(@"[WeaponX] ❌ Could not get user data to start heartbeat: %@", error);
                }
            }];
        }
    } else {
        NSLog(@"[WeaponX] ⚠️ No authentication token found - heartbeat will not start");
    }
}

// Handle app resigning active
- (void)applicationWillResignActive:(NSNotification *)notification {
    NSLog(@"[WeaponX] App will resign active");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults objectForKey:@"WeaponXAuthToken"];
    
    if (token) {
        // Send one final online update before app goes to background
        [self updateUserPresence:token status:@"away" completion:nil];
    }
    
    // Invalidate the heartbeat timer
    if (self.heartbeatTimer) {
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
        NSLog(@"[WeaponX] Heartbeat timer invalidated");
    }
    
    self.isOnline = NO;
}

#pragma mark - Heartbeat

#pragma mark - Heartbeat Methods

// New method to track the current screen/tab
- (void)setCurrentScreen:(NSString *)screenName {
    if (!screenName) {
        return;
    }
    
    // Only log if the screen has changed
    if (!_currentScreen || ![_currentScreen isEqualToString:screenName]) {
        _currentScreen = screenName;
        NSLog(@"[WeaponX] 📱 Current screen set to: %@", screenName);
        
        // If there's an active user session, send a heartbeat immediately to update the screen info
        NSString *userId = [[NSUserDefaults standardUserDefaults] objectForKey:@"HeartbeatUserId"];
        if (userId) {
            // Send a heartbeat but with a short delay to avoid too many requests
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSLog(@"[WeaponX] 📡 Sending heartbeat due to screen change: %@", screenName);
                [self heartbeatTimerFired];
            });
        }
    }
}

- (NSString *)getCurrentScreen {
    return _currentScreen ?: @"Unknown";
}

- (void)startHeartbeat:(NSString *)userId {
    // Check if we received the same user ID within the last 2 seconds
    static NSString *lastUserId = nil;
    static NSDate *lastStartTime = nil;
    
    NSDate *now = [NSDate date];
    BOOL isDuplicate = NO;
    
    if (lastStartTime && lastUserId && [lastUserId isEqualToString:userId]) {
        NSTimeInterval timeSinceLastStart = [now timeIntervalSinceDate:lastStartTime];
        if (timeSinceLastStart < 2.0) {
            NSLog(@"[WeaponX] ⚠️ Duplicate heartbeat request detected within %.2f seconds, ignoring", timeSinceLastStart);
            isDuplicate = YES;
        }
    }
    
    // Update tracking for future calls
    lastUserId = userId;
    lastStartTime = now;
    
    // If this is a duplicate call, just return
    if (isDuplicate) {
        return;
    }
    
    NSLog(@"[WeaponX] 🔄 Starting heartbeat for user ID: %@", userId);
    
    // First invalidate any existing timer
    if (self.heartbeatTimer) {
        NSLog(@"[WeaponX] 🛑 Invalidating existing heartbeat timer");
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    }
    
    // Store the user ID for future heartbeats
    NSLog(@"[WeaponX] 💾 Storing user ID for heartbeats: %@", userId);
    [[NSUserDefaults standardUserDefaults] setObject:userId forKey:@"HeartbeatUserId"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Start with a 5-second delay to allow app to fully initialize
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"[WeaponX] ⏰ Starting heartbeat timer with 60-second interval");
        self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 
                                                          target:self 
                                                        selector:@selector(heartbeatTimerFired) 
                                                        userInfo:nil 
                                                         repeats:YES];
        
        // Send first heartbeat immediately
        [self heartbeatTimerFired];
    });
}

- (void)heartbeatTimerFired {
    static BOOL isProcessingHeartbeat = NO;
    static NSDate *lastHeartbeatTime = nil;
    
    NSDate *now = [NSDate date];
    
    // If we're already processing a heartbeat, don't start another one
    if (isProcessingHeartbeat) {
        NSLog(@"[WeaponX] ⚠️ Already processing a heartbeat, skipping this one");
        return;
    }
    
    // Check if we've sent a heartbeat recently (within 60 seconds)
    if (lastHeartbeatTime) {
        NSTimeInterval timeSinceLastHeartbeat = [now timeIntervalSinceDate:lastHeartbeatTime];
        if (timeSinceLastHeartbeat < 60.0) {
            NSLog(@"[WeaponX] ⚠️ Last heartbeat was %.2f seconds ago, skipping this one (1-minute minimum interval)", timeSinceLastHeartbeat);
            return;
        }
    }
    
    // Set the processing flag and update the last heartbeat time
    isProcessingHeartbeat = YES;
    lastHeartbeatTime = now;
    
    NSLog(@"[WeaponX] ⏱️ Heartbeat timer fired");
    
    // Get the stored user ID for heartbeat
    NSString *userId = [[NSUserDefaults standardUserDefaults] objectForKey:@"HeartbeatUserId"];
    if (!userId) {
        NSLog(@"[WeaponX] ❌ No HeartbeatUserId found, falling back to WeaponXServerUserId");
        userId = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXServerUserId"];
    }
    
    // If we have a valid user ID, send the heartbeat
    if (userId) {
        NSLog(@"[WeaponX] ✅ Retrieved valid user ID for heartbeat: %@", userId);
        [self sendHeartbeat:userId];
    } else {
        NSLog(@"[WeaponX] ⚠️ No user ID available for heartbeat - THIS IS A PROBLEM");
    }
    
    // Clear the processing flag
    isProcessingHeartbeat = NO;
}

- (void)sendHeartbeat:(NSString *)userId {
    if (!userId) {
        NSLog(@"[WeaponX] ❌ Cannot send heartbeat: No user ID provided");
        return;
    }
    
    // Check network availability first
    if (![self isNetworkAvailable]) {
        NSLog(@"[WeaponX] 🌐 Network unavailable, skipping heartbeat");
        return;
    }
    
    NSLog(@"[WeaponX] 📡 Sending heartbeat for user ID: %@", userId);
    
    // Get auth token
    NSString *token = [[TokenManager sharedInstance] getCurrentToken];
    
    if (!token) {
        NSLog(@"[WeaponX] ❌ No auth token available for heartbeat");
        return;
    }
    
    NSLog(@"[WeaponX] 🔑 Using token for heartbeat: %@...", [token substringToIndex:MIN(10, token.length)]);
    
    // First, get the public IP address, then continue with heartbeat
    [self fetchPublicIPAddress:^(NSString *publicIP) {
    // First fetch a CSRF token to use with the heartbeat request
    [self fetchCSRFTokenWithExtendedCompletion:^(BOOL success, NSString *csrfToken) {
        // Check network again after fetching IP to ensure it's still available
        if (![self isNetworkAvailable]) {
            NSLog(@"[WeaponX] 🌐 Network became unavailable during heartbeat preparation, aborting");
            return;
        }
        
        if (!success || !csrfToken) {
            NSLog(@"[WeaponX] ⚠️ Failed to get CSRF token for heartbeat, trying anyway");
                [self sendHeartbeatRequestWithToken:token userId:userId csrfToken:nil publicIP:publicIP];
        } else {
            NSLog(@"[WeaponX] ✅ Got CSRF token for heartbeat: %@...", [csrfToken substringToIndex:MIN(10, csrfToken.length)]);
                [self sendHeartbeatRequestWithToken:token userId:userId csrfToken:csrfToken publicIP:publicIP];
        }
        }];
    }];
}

// New method to separate the actual request from the token fetching with public IP
- (void)sendHeartbeatRequestWithToken:(NSString *)token userId:(NSString *)userId csrfToken:(NSString *)csrfToken publicIP:(NSString *)publicIP {
    // Check network availability first
    if (![self isNetworkAvailable]) {
        NSLog(@"[WeaponX] 🌐 Network unavailable - queuing heartbeat for later");
        
        // Initialize queue if needed
        if (!_queuedHeartbeats) {
            _queuedHeartbeats = [NSMutableArray array];
        }
        
        // Add to queue
        [_queuedHeartbeats addObject:@{
            @"token": token ?: @"",
            @"userId": userId ?: @"",
            @"csrfToken": csrfToken ?: @"",
            @"publicIP": publicIP ?: @"",
            @"timestamp": @([[NSDate date] timeIntervalSince1970])
        }];
        
        NSLog(@"[WeaponX] 📋 Queued heartbeat - queue size: %lu", (unsigned long)_queuedHeartbeats.count);
        return;
    }
    
    // Try the better heartbeat endpoint first
    NSString *betterUrl = [NSString stringWithFormat:@"%@/better-heartbeat.php", self.baseURL];
    NSLog(@"[WeaponX] 🌐 Trying better heartbeat URL: %@", betterUrl);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:betterUrl]];
    [request setHTTPMethod:@"POST"];
    
    // Set headers
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:userId forHTTPHeaderField:@"X-User-Id"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    // Add CSRF token if available 
    if (csrfToken) {
        [request setValue:csrfToken forHTTPHeaderField:@"X-XSRF-TOKEN"];
    }
    
    // Get system version
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    
    // Get app version
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [infoDictionary objectForKey:@"CFBundleVersion"];
    NSString *actualAppVersion = [NSString stringWithFormat:@"%@-%@", appVersion ?: @"1.0.0", buildNumber ?: @"1"];
    
    // Don't send X-App-Version header for heartbeats to bypass version checks
    
    // Get device model and name - use our detailed device model method
    NSString *deviceModel = [self getDetailedDeviceModel];
    NSString *deviceName = [[UIDevice currentDevice] name];
    
    // Get device unique identifiers (UUID and serial number)
    NSDictionary *deviceIdentifiers = [self getDeviceIdentifiers];
    
    // Get current screen or tab information
    NSString *currentScreen = [self getCurrentScreen];
    
    // Create request parameters dictionary with priority for current screen
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{
        @"user_id": userId,
        @"status": @"online",
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"system_version": systemVersion ?: @"Unknown",
        @"app_version": actualAppVersion ?: @"Unknown", // Use the actual version in the payload
        @"real_app_version": actualAppVersion ?: @"Unknown", // Also include actual version in a new field
        @"device_model": deviceModel ?: @"iOS Device",
        @"device_name": deviceName ?: @"Unknown Device",
        @"public_ip": publicIP ?: @"", // Add the public IP parameter
        @"current_screen": currentScreen ?: @"Unknown" // Add current screen as a top-level parameter
    }];
    
    // Add device identifiers to the params if available
    if (deviceIdentifiers[@"device_uuid"]) {
        params[@"device_uuid"] = deviceIdentifiers[@"device_uuid"];
    }
    
    if (deviceIdentifiers[@"device_serial"]) {
        params[@"device_serial"] = deviceIdentifiers[@"device_serial"];
    }
    
    // Serialize to JSON
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&error];
    
    if (error) {
        NSLog(@"[WeaponX] ❌ Error serializing heartbeat JSON: %@", error);
        return;
    }
    
    // Log that we're including current screen in heartbeat
    NSLog(@"[WeaponX] 📱 Including current screen in heartbeat: %@", currentScreen);
    
    [request setHTTPBody:jsonData];
    
    // Create and start the task
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Heartbeat request error: %@", error);
            return;
        }
        
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📊 Heartbeat response status: %ld", (long)httpResponse.statusCode);
        
        // Log all response headers for debugging
        NSLog(@"[WeaponX] 📋 Heartbeat response headers: %@", httpResponse.allHeaderFields);
            
            if (data) {
                NSError *jsonError;
                NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Error parsing heartbeat response: %@", jsonError);
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[WeaponX] 📝 Raw response: %@", responseString);
                
                // Check if this is a CSRF token issue and refresh token if needed
                if (httpResponse.statusCode == 419) {
                    NSLog(@"[WeaponX] ⚠️ CSRF token mismatch detected - refreshing token and retrying");
                    [self fetchCSRFTokenWithExtendedCompletion:^(BOOL success, NSString *newToken) {
                        if (success) {
                            NSLog(@"[WeaponX] ✅ Got fresh CSRF token, retrying heartbeat");
                            [self sendHeartbeatRequestWithToken:token userId:userId csrfToken:newToken publicIP:publicIP];
                        }
                    }];
                }
                
                // If the better heartbeat endpoint failed, try the regular heartbeat endpoint
                NSString *fallbackUrl = [NSString stringWithFormat:@"%@/heartbeat.php", self.baseURL];
                NSLog(@"[WeaponX] 🌐 Falling back to regular heartbeat URL: %@", fallbackUrl);
                
                NSMutableURLRequest *fallbackRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fallbackUrl]];
                [fallbackRequest setHTTPMethod:@"POST"];
                [fallbackRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
                [fallbackRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
                [fallbackRequest setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
                [fallbackRequest setValue:userId forHTTPHeaderField:@"X-User-Id"];
                [fallbackRequest setHTTPBody:jsonData];
                
                NSURLSessionDataTask *fallbackTask = [[NSURLSession sharedSession] dataTaskWithRequest:fallbackRequest completionHandler:^(NSData *fallbackData, NSURLResponse *fallbackResponse, NSError *fallbackError) {
                    if (fallbackError) {
                        NSLog(@"[WeaponX] ❌ Fallback heartbeat request error: %@", fallbackError);
                        return;
                    }
                    
                    NSHTTPURLResponse *fallbackHttpResponse = (NSHTTPURLResponse *)fallbackResponse;
                    NSLog(@"[WeaponX] 📊 Fallback heartbeat response status: %ld", (long)fallbackHttpResponse.statusCode);
                    
                    if (fallbackData) {
                        NSError *fallbackJsonError;
                        NSDictionary *fallbackResponseDict = [NSJSONSerialization JSONObjectWithData:fallbackData options:0 error:&fallbackJsonError];
                        
                        if (!fallbackJsonError && fallbackResponseDict) {
                            NSLog(@"[WeaponX] ✅ Fallback heartbeat response: %@", fallbackResponseDict);
                        }
                    }
                }];
                
                [fallbackTask resume];
                return;
                
                // Check for session termination
                if ([responseDict[@"device_status"] isEqualToString:@"terminated"]) {
                    NSLog(@"[WeaponX] ⚠️ Server indicated session termination (device_status=terminated)");
                    
                    // Implement session termination
                        dispatch_async(dispatch_get_main_queue(), ^{
                        // Show alert to user
                        UIAlertController *alert = [UIAlertController 
                            alertControllerWithTitle:@"Session Terminated" 
                            message:@"Your session has been terminated by the server administrator." 
                            preferredStyle:UIAlertControllerStyleAlert];
                            
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            // Clear all user data
                            [self clearAllUserData];
                            
                            // Stop heartbeat
                            [self stopHeartbeat];
                            
                            // Post notification that user was logged out
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserLoggedOut" object:nil];
                            
                            // Exit and relaunch app if possible
                            [self exitAndRelaunchApp];
                        }]];
                        
                        [self presentAlertOnTopViewController:alert];
                    });
                    
                    return;
                }
                // Also check for terminate_session flag for backward compatibility
                else if ([responseDict[@"terminate_session"] boolValue]) {
                    NSLog(@"[WeaponX] ⚠️ Server indicated terminate_session flag");
                    
                    // Implement session termination
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Show alert to user
                        UIAlertController *alert = [UIAlertController 
                            alertControllerWithTitle:@"Session Terminated" 
                            message:@"Your session has been terminated by the server administrator." 
                            preferredStyle:UIAlertControllerStyleAlert];
                            
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            // Clear all user data
                            [self clearAllUserData];
                            
                            // Stop heartbeat
                            [self stopHeartbeat];
                            
                            // Post notification that user was logged out
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserLoggedOut" object:nil];
                            
                            // Exit and relaunch app if possible
                            [self exitAndRelaunchApp];
                        }]];
                        
                        [self presentAlertOnTopViewController:alert];
                    });
                    
                    return;
                }
                // Check for unauthorized or unauthenticated responses
                else if (httpResponse.statusCode == 401 || 
                         [responseDict[@"message"] isEqualToString:@"Unauthenticated"] ||
                         [responseDict[@"error"] isEqualToString:@"Unauthenticated"]) {
                    NSLog(@"[WeaponX] ⚠️ Server indicated authentication failure: %@", responseDict);
                    
                    // Log additional debug info
                    NSLog(@"[WeaponX] 🔍 Authentication failure details:");
                    NSLog(@"[WeaponX] 🔑 Token used: %@...", [token substringToIndex:MIN(10, token.length)]);
                    NSLog(@"[WeaponX] 👤 User ID: %@", userId);
                    
                    // Handle authentication failure properly
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Show alert to user
                        UIAlertController *alert = [UIAlertController 
                            alertControllerWithTitle:@"Session Expired" 
                            message:@"Your session has expired or been terminated. Please log in again." 
                            preferredStyle:UIAlertControllerStyleAlert];
                        
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            // Clear all user data
                            [self clearAllUserData];
                            
                            // Stop heartbeat
                            [self stopHeartbeat];
                            
                            // Post notification that user was logged out
                            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserLoggedOut" object:nil];
                            
                            // Exit and relaunch app if possible
                            [self exitAndRelaunchApp];
                        }]];
                        
                        [self presentAlertOnTopViewController:alert];
                    });
                    
                    return;
                }
            }
                
            NSLog(@"[WeaponX] ✅ Heartbeat response: %@", responseDict);
                
            // Check for session termination
            if ([responseDict[@"device_status"] isEqualToString:@"terminated"]) {
                NSLog(@"[WeaponX] ⚠️ Server indicated session termination");
                
                // Implement session termination
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Show alert to user
                    UIAlertController *alert = [UIAlertController 
                        alertControllerWithTitle:@"Session Terminated" 
                        message:@"Your session has been terminated by the server administrator." 
                        preferredStyle:UIAlertControllerStyleAlert];
                        
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        // Clear all user data
                        [self clearAllUserData];
                        
                        // Stop heartbeat
                        [self stopHeartbeat];
                        
                        // Post notification that user was logged out
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserLoggedOut" object:nil];
                        
                        // Exit and relaunch app if possible
                        [self exitAndRelaunchApp];
                    }]];
                    
                    [self presentAlertOnTopViewController:alert];
                });
                
                return;
            }
            // Also check for terminate_session flag for backward compatibility
            else if ([responseDict[@"terminate_session"] boolValue]) {
                NSLog(@"[WeaponX] ⚠️ Server indicated terminate_session flag");
                
                // Implement session termination
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Show alert to user
                    UIAlertController *alert = [UIAlertController 
                        alertControllerWithTitle:@"Session Terminated" 
                        message:@"Your session has been terminated by the server administrator." 
                        preferredStyle:UIAlertControllerStyleAlert];
                        
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                        // Clear all user data
                        [self clearAllUserData];
                        
                        // Stop heartbeat
                        [self stopHeartbeat];
                        
                        // Post notification that user was logged out
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserLoggedOut" object:nil];
                        
                        // Exit and relaunch app if possible
                        [self exitAndRelaunchApp];
                    }]];
                    
                    [self presentAlertOnTopViewController:alert];
                });
                
                return;
            }
            // Check for unauthorized or unauthenticated responses
            else if (httpResponse.statusCode == 401 || 
                     [responseDict[@"message"] isEqualToString:@"Unauthenticated"] ||
                     [responseDict[@"error"] isEqualToString:@"Unauthenticated"]) {
                NSLog(@"[WeaponX] ⚠️ Server indicated authentication failure: %@", responseDict);
                
                // Log additional debug info
                NSLog(@"[WeaponX] 🔍 Authentication failure details:");
                NSLog(@"[WeaponX] 🔑 Token used: %@...", [token substringToIndex:MIN(10, token.length)]);
                NSLog(@"[WeaponX] 👤 User ID: %@", userId);
                
                // TEMPORARY: Skip logout for debugging
                NSLog(@"[WeaponX] 🔧 DEBUG: Ignoring authentication failure for debugging");
                return;
            }
            } else if (httpResponse.statusCode == 419) {
            // CSRF token issue with no response data
            NSLog(@"[WeaponX] ⚠️ CSRF token mismatch detected (419) - refreshing token and retrying");
            [self fetchCSRFTokenWithExtendedCompletion:^(BOOL success, NSString *newToken) {
                if (success) {
                    NSLog(@"[WeaponX] ✅ Got fresh CSRF token, retrying heartbeat");
                    [self sendHeartbeatRequestWithToken:token userId:userId csrfToken:newToken publicIP:publicIP];
                }
            }];
        }
    }];
    
    [task resume];
}

// Legacy method to maintain backwards compatibility
- (void)sendHeartbeatRequestWithToken:(NSString *)token userId:(NSString *)userId csrfToken:(NSString *)csrfToken {
    // Call the new method with nil publicIP
    [self sendHeartbeatRequestWithToken:token userId:userId csrfToken:csrfToken publicIP:nil];
}

#pragma mark - URL Configuration

- (void)setBaseURL:(NSString *)baseURL {
    if (![baseURL hasPrefix:@"http"]) {
        baseURL = [NSString stringWithFormat:@"https://%@", baseURL];
    }
    
    // Remove trailing slash if present
    if ([baseURL hasSuffix:@"/"]) {
        baseURL = [baseURL substringToIndex:baseURL.length - 1];
    }
    
    self.baseURLString = baseURL;
    
    // Save to user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:baseURL forKey:@"WeaponXBaseURL"];
    [defaults synchronize];
}

- (NSString *)baseURL {
    return self.baseURLString;
}

- (NSString *)baseUrl {
    return self.baseURLString;
}

#pragma mark - CSRF Token Handling

- (void)fetchCSRFTokenWithCompletion:(void (^)(NSString *))completion {
    [self fetchCSRFTokenWithExtendedCompletion:^(BOOL success, NSString *token) {
                    if (completion) {
            completion(token);
        }
    }];
}

- (void)fetchCSRFTokenWithForceRefresh:(BOOL)forceRefresh completion:(void (^)(NSString *))completion {
    [self fetchCSRFTokenWithForceRefreshAndExtendedCompletion:forceRefresh completion:^(BOOL success, NSString *token) {
        if (completion) {
            completion(token);
        }
    }];
}

- (void)fetchCSRFTokenWithExtendedCompletion:(void (^)(BOOL success, NSString *token))completion {
    [self fetchCSRFTokenWithForceRefreshAndExtendedCompletion:NO completion:completion];
}

- (void)fetchCSRFTokenWithForceRefreshAndExtendedCompletion:(BOOL)forceRefresh completion:(void (^)(BOOL success, NSString *token))completion {
    NSLog(@"[WeaponX] 🔑 Fetching CSRF token... (forceRefresh: %@)", forceRefresh ? @"YES" : @"NO");
    
    // Check if we already have a cached token that's not expired
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *cachedToken = [defaults objectForKey:@"WeaponXCachedCSRFToken"];
    NSDate *tokenExpiry = [defaults objectForKey:@"WeaponXCachedCSRFTokenExpiry"];
    
    // Use cached token if not forcing refresh, it exists and isn't expired
    if (!forceRefresh && cachedToken && tokenExpiry && [tokenExpiry timeIntervalSinceNow] > 0) {
        NSLog(@"[WeaponX] ✅ Using cached CSRF token (expires in %.1f minutes)", 
              [tokenExpiry timeIntervalSinceNow] / 60.0);
              
        if (completion) {
            completion(YES, cachedToken);
        }
        return;
    }
    
    // If we're offline but have a cached token and not forcing refresh, use it anyway (even if expired)
    if (!forceRefresh && ![self isNetworkAvailable] && cachedToken) {
        NSLog(@"[WeaponX] ⚠️ Offline but using expired cached CSRF token as fallback");
        if (completion) {
            completion(YES, cachedToken);
        }
        return;
    }
    
    // Clear any existing cookies to ensure we get a fresh token
    if (forceRefresh) {
        NSLog(@"[WeaponX] 🧹 Clearing cookies to get fresh CSRF token");
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        NSArray *cookies = [cookieStorage cookies];
        for (NSHTTPCookie *cookie in cookies) {
            if ([cookie.name isEqualToString:@"XSRF-TOKEN"] || 
                [cookie.name isEqualToString:@"weaponx_session"]) {
                [cookieStorage deleteCookie:cookie];
            }
        }
    }
    
    NSURL *url = [NSURL URLWithString:self.baseURLString];
    if (!url) {
        NSLog(@"[WeaponX] ❌ Invalid base URL for CSRF token fetch");
        if (completion) {
            completion(NO, nil);
        }
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    // Use our custom session with SSL handling
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Error fetching CSRF token: %@", error);
            
            // If there's an error but we have a cached token, use it as fallback
            if (!forceRefresh && cachedToken) {
                NSLog(@"[WeaponX] ⚠️ Failed to get fresh CSRF token, using cached one as fallback");
                if (completion) {
                    completion(YES, cachedToken);
                }
                return;
            }
            
            if (completion) {
                completion(NO, nil);
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📊 CSRF token response status: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] 📋 CSRF token response headers: %@", httpResponse.allHeaderFields);
        
        // Get cookies from response
        NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:[httpResponse allHeaderFields] forURL:url];
        
        // Look for XSRF-TOKEN cookie
        NSString *csrfToken = nil;
        for (NSHTTPCookie *cookie in cookies) {
            NSLog(@"[WeaponX] 🍪 Cookie: %@ = %@", cookie.name, cookie.value);
            if ([cookie.name isEqualToString:@"XSRF-TOKEN"]) {
                // URL decode the cookie value
                csrfToken = [cookie.value stringByRemovingPercentEncoding];
                NSLog(@"[WeaponX] 🔑 Found CSRF token in cookies: %@...", 
                      csrfToken.length > 10 ? [csrfToken substringToIndex:10] : csrfToken);
                break;
            }
        }
        
        // Also check for Set-Cookie header directly
        if (!csrfToken) {
            NSString *setCookie = httpResponse.allHeaderFields[@"Set-Cookie"];
            if (setCookie) {
                NSArray *cookieParts = [setCookie componentsSeparatedByString:@"; "];
                for (NSString *part in cookieParts) {
                    if ([part hasPrefix:@"XSRF-TOKEN="]) {
                        csrfToken = [part substringFromIndex:[@"XSRF-TOKEN=" length]];
                        csrfToken = [csrfToken stringByRemovingPercentEncoding];
                        NSLog(@"[WeaponX] 🔑 Found CSRF token in Set-Cookie header: %@...", 
                              csrfToken.length > 10 ? [csrfToken substringToIndex:10] : csrfToken);
                        break;
                    }
                }
            }
        }
        
        if (csrfToken) {
            // Cache the token for future use (valid for 30 minutes)
            NSDate *newExpiry = [NSDate dateWithTimeIntervalSinceNow:30 * 60]; // 30 minutes
            [defaults setObject:csrfToken forKey:@"WeaponXCachedCSRFToken"];
            [defaults setObject:newExpiry forKey:@"WeaponXCachedCSRFTokenExpiry"];
            [defaults synchronize];
            
            // Store in the instance variable for immediate use
            self.csrfToken = csrfToken;
            
            if (completion) {
                completion(YES, csrfToken);
            }
        } else {
            NSLog(@"[WeaponX] ⚠️ No CSRF token found in response");
            
            // If no token in response but we have a cached one and not forcing refresh, use it as fallback
            if (!forceRefresh && cachedToken) {
                NSLog(@"[WeaponX] ⚠️ Using cached CSRF token as fallback");
                if (completion) {
                    completion(YES, cachedToken);
                }
                return;
            }
        
            if (completion) {
                completion(NO, nil);
            }
        }
    }];
    
    [task resume];
}

- (NSString *)getCSRFTokenForUrl:(NSString *)urlString {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *storedToken = [defaults objectForKey:@"WeaponXCSRFToken"];
    
    // Check if we have a stored token first
    if (storedToken) {
        NSLog(@"[WeaponX] Using stored CSRF token");
        return storedToken;
    }
    
    // Otherwise check cookies
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return nil;
    }
    
    NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", url.scheme, url.host]];
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [cookieStorage cookiesForURL:baseURL];
    
    for (NSHTTPCookie *cookie in cookies) {
        if ([cookie.name isEqualToString:@"XSRF-TOKEN"]) {
            NSString *csrfToken = cookie.value;
            csrfToken = [csrfToken stringByRemovingPercentEncoding]; // URL decode if needed
            
            // Cache the token for future use
            [defaults setObject:csrfToken forKey:@"WeaponXCSRFToken"];
            [defaults synchronize];
            
            NSLog(@"[WeaponX] Found CSRF token in cookies: %@", csrfToken);
            return csrfToken;
        }
    }
    
    NSLog(@"[WeaponX] No CSRF token found for URL: %@", urlString);
    return nil;
}

#pragma mark - Authentication Methods

- (void)loginWithEmail:(NSString *)email password:(NSString *)password completion:(void (^)(NSDictionary *userData, NSString *token, NSError *error))completion {
    // First check if current version is banned
    if ([self isCurrentVersionBanned]) {
        NSLog(@"[WeaponX] ⛔️ Attempted login with banned app version");
        
        // Show version banned alert
        [self showVersionBannedAlert:nil completion:^{
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"com.weaponx.error" code:426 userInfo:@{
                    NSLocalizedDescriptionKey: @"This app version is no longer supported. Please update to continue."
                }];
                completion(nil, nil, error);
            }
        }];
        return;
    }
    
    // Check if device is banned
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"WeaponXDeviceBanned"]) {
        NSString *banReason = [defaults objectForKey:@"WeaponXBanReason"] ?: @"This device has been banned.";
        NSString *bannedAt = [defaults objectForKey:@"WeaponXBannedAt"] ?: @"";
        
        NSLog(@"[WeaponX] ⛔️ Attempted login on banned device: %@", banReason);
        
        // Show banned alert
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController 
                alertControllerWithTitle:@"Device Banned" 
                message:banReason
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            
            [self presentAlertOnTopViewController:alert];
        });
        
        // Create and return an error
        NSError *banError = [NSError errorWithDomain:@"com.weaponx.error" code:403 userInfo:@{
            NSLocalizedDescriptionKey: banReason,
            @"banned_at": bannedAt
        }];
        
        if (completion) {
            completion(nil, nil, banError);
        }
        
        return;
    }
    
    // Clear any existing authentication data
    [self clearAllUserData];
    
    // Get device identifiers to include in login
    NSDictionary *deviceIdentifiers = [self getDeviceIdentifiers];
    
    // Always fetch a fresh CSRF token for login to avoid token mismatch
    [self fetchCSRFTokenWithForceRefresh:YES completion:^(NSString *csrfToken) {
        [self performLoginWithEmail:email password:password deviceIdentifiers:deviceIdentifiers csrfToken:csrfToken retryCount:0 completion:completion];
    }];
}

- (void)performLoginWithEmail:(NSString *)email 
                    password:(NSString *)password 
            deviceIdentifiers:(NSDictionary *)deviceIdentifiers 
                   csrfToken:(NSString *)csrfToken 
                  retryCount:(NSInteger)retryCount 
                  completion:(void (^)(NSDictionary *userData, NSString *token, NSError *error))completion {
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{
        @"email": email,
        @"password": password,
        @"device_name": [[UIDevice currentDevice] name],
        @"device_model": [self getDetailedDeviceModel],
        @"system_version": [[UIDevice currentDevice] systemVersion],
    }];
    
    // Add device identifiers to the params if available
    if (deviceIdentifiers[@"device_uuid"]) {
        params[@"device_uuid"] = deviceIdentifiers[@"device_uuid"];
    }
    
    if (deviceIdentifiers[@"device_serial"]) {
        params[@"device_serial"] = deviceIdentifiers[@"device_serial"];
    }
    
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonError];
    
    if (jsonError) {
        NSLog(@"[WeaponX] ❌ Error creating login JSON: %@", jsonError);
        if (completion) {
                completion(nil, nil, jsonError);
        }
        return;
    }
    
    NSString *loginURL = [NSString stringWithFormat:@"%@/api/login", self.baseURLString];
    NSLog(@"[WeaponX] 🔑 Attempting login to: %@", loginURL);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:loginURL]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    // Add CSRF token if available
    if (csrfToken) {
        NSLog(@"[WeaponX] 🔒 Using CSRF token for login: %@...", [csrfToken substringToIndex:MIN(10, csrfToken.length)]);
        [request setValue:csrfToken forHTTPHeaderField:@"X-XSRF-TOKEN"];
    } else {
        NSLog(@"[WeaponX] ⚠️ No CSRF token available for login");
    }
    
    [request setHTTPBody:jsonData];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Login network error: %@", error);
            if (completion) {
                    completion(nil, nil, error);
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📊 Login response status: %ld", (long)httpResponse.statusCode);
        
        // Log all response headers for debugging
        NSLog(@"[WeaponX] 📋 Login response headers: %@", httpResponse.allHeaderFields);
        
        // Handle CSRF token mismatch (419) with a retry
        if (httpResponse.statusCode == 419 && retryCount < 2) {
            NSLog(@"[WeaponX] ⚠️ CSRF token mismatch (419), retrying with fresh token (attempt %ld of 2)", (long)retryCount + 1);
            
            // Get a new CSRF token and retry login
            [self fetchCSRFTokenWithForceRefresh:YES completion:^(NSString *newToken) {
                if (newToken) {
                    NSLog(@"[WeaponX] ✅ Got new CSRF token for retry: %@...", [newToken substringToIndex:MIN(10, newToken.length)]);
                    [self performLoginWithEmail:email password:password deviceIdentifiers:deviceIdentifiers csrfToken:newToken retryCount:retryCount + 1 completion:completion];
                } else {
                    NSLog(@"[WeaponX] ❌ Failed to get new CSRF token for retry");
                    NSError *tokenError = [NSError errorWithDomain:@"com.weaponx.error" code:419 userInfo:@{
                        NSLocalizedDescriptionKey: @"CSRF token mismatch and failed to get new token."
                    }];
                    if (completion) {
                        completion(nil, nil, tokenError);
                    }
                }
            }];
            return;
        }
        
        if (!data) {
            NSLog(@"[WeaponX] ⚠️ No data in login response");
            NSError *noDataError = [NSError errorWithDomain:@"com.weaponx.error" code:0 userInfo:@{
                NSLocalizedDescriptionKey: @"No data received from server"
            }];
            if (completion) {
                completion(nil, nil, noDataError);
            }
            return;
        }
        
        // Log raw response for debugging
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"[WeaponX] 📝 Raw login response: %@", responseString);
            
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
            NSLog(@"[WeaponX] ❌ Error parsing login response: %@", jsonError);
                if (completion) {
                        completion(nil, nil, jsonError);
                }
                return;
            }
            
        NSLog(@"[WeaponX] 📦 Login response: %@", responseDict);
        
        // Check for error response
        if (httpResponse.statusCode >= 400 || responseDict[@"error"]) {
            NSString *errorMessage = responseDict[@"error"] ?: responseDict[@"message"] ?: @"Login failed";
            NSLog(@"[WeaponX] ❌ Login error: %@", errorMessage);
            
            NSError *loginError = [NSError errorWithDomain:@"com.weaponx.error" code:httpResponse.statusCode userInfo:@{
                NSLocalizedDescriptionKey: errorMessage,
                @"response": responseDict
            }];
            
                        if (completion) {
                completion(nil, nil, loginError);
                        }
                return;
            }
            
        // Extract token from response
        NSString *token = responseDict[@"token"];
            if (!token) {
            NSLog(@"[WeaponX] ⚠️ No token in login response");
            NSError *noTokenError = [NSError errorWithDomain:@"com.weaponx.error" code:0 userInfo:@{
                NSLocalizedDescriptionKey: @"No authentication token received"
            }];
                if (completion) {
                completion(nil, nil, noTokenError);
                }
                return;
            }
            
        NSLog(@"[WeaponX] ✅ Login successful, token: %@...", [token substringToIndex:MIN(10, token.length)]);
        
        // Save token to keychain
        [self saveToken:token];
        
        // Extract user data
        NSDictionary *userData = responseDict[@"user"];
        if (!userData) {
            NSLog(@"[WeaponX] ⚠️ No user data in login response");
            // Continue anyway with empty user data
            userData = @{};
        }
        
        // Save user ID
        NSString *userId = [userData[@"id"] stringValue];
        if (userId) {
            [[NSUserDefaults standardUserDefaults] setObject:userId forKey:@"WeaponXUserId"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        
        if (completion) {
            completion(userData, token, nil);
        }
    }];
    
    [task resume];
}

- (void)registerWithName:(NSString *)name email:(NSString *)email password:(NSString *)password completion:(void (^)(NSDictionary *userData, NSString *token, NSError *error))completion {
    // First check if current version is banned
    if ([self isCurrentVersionBanned]) {
        NSLog(@"[WeaponX] ⛔️ Attempted registration with banned app version");
        
        // Show version banned alert
        [self showVersionBannedAlert:nil completion:^{
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"com.weaponx.error" code:426 userInfo:@{
                    NSLocalizedDescriptionKey: @"This app version is no longer supported. Please update to continue."
                }];
                completion(nil, nil, error);
            }
        }];
        return;
    }
    
    // Check if device is banned
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"WeaponXDeviceBanned"]) {
        NSString *banReason = [defaults objectForKey:@"WeaponXBanReason"] ?: @"This device has been banned.";
        NSString *bannedAt = [defaults objectForKey:@"WeaponXBannedAt"] ?: @"";
        
        NSLog(@"[WeaponX] ⛔️ Attempted registration on banned device: %@", banReason);
        
        // Show banned alert
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController 
                alertControllerWithTitle:@"Registration Not Allowed" 
                message:[NSString stringWithFormat:@"%@ Registration is not permitted on banned devices.", banReason]
                preferredStyle:UIAlertControllerStyleAlert];
                
            UIAlertAction *okAction = [UIAlertAction 
                actionWithTitle:@"OK" 
                style:UIAlertActionStyleDefault 
                handler:nil];
                
            [alert addAction:okAction];
            
            [self presentAlertController:alert];
        });
        
        // Call completion with error
        NSError *banError = [NSError errorWithDomain:@"WeaponXErrorDomain" 
                                                code:403 
                                            userInfo:@{
                                                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ Registration is not permitted on banned devices.", banReason],
                                                @"banned_at": bannedAt,
                                                @"status": @"banned"
                                            }];
                
                if (completion) {
            completion(nil, nil, banError);
                }
        
        return;
}

    // Get device identifiers to include in registration
    NSDictionary *deviceIdentifiers = [self getDeviceIdentifiers];
    
    // First fetch CSRF token
    [self fetchCSRFTokenWithCompletion:^(NSString *csrfToken) {
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{
            @"name": name,
            @"email": email,
            @"password": password
        }];
        
        // Add device UUID and serial if available
        if (deviceIdentifiers[@"device_uuid"]) {
            params[@"device_uuid"] = deviceIdentifiers[@"device_uuid"];
        }
        
        if (deviceIdentifiers[@"device_serial"]) {
            params[@"device_serial"] = deviceIdentifiers[@"device_serial"];
        }
        
        NSString *fullURL = [NSString stringWithFormat:@"%@%@", self.baseURLString, @"/api/register"];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullURL]];
        [request setHTTPMethod:@"POST"];
        
        // Enable cookie handling
        request.HTTPShouldHandleCookies = YES;
        
        // Set headers
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
        
        // Add CSRF token if available
        if (csrfToken) {
            [request setValue:csrfToken forHTTPHeaderField:@"X-XSRF-TOKEN"];
            NSLog(@"[WeaponX] Added CSRF token to register request: %@", csrfToken);
        } else {
            NSLog(@"[WeaponX] No CSRF token available for register request");
        }
        
        // Add request body
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonError];
        
        if (jsonError) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, nil, jsonError);
                });
            }
            return;
        }
        
        [request setHTTPBody:jsonData];
        
        NSLog(@"[WeaponX] Sending register request to %@", fullURL);
        NSLog(@"[WeaponX] Headers: %@", [request allHTTPHeaderFields]);
        NSString *bodyString = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        NSLog(@"[WeaponX] Body: %@", bodyString);
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
                NSLog(@"[WeaponX] Register API Error: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[WeaponX] Register API Response Status: %ld", (long)httpResponse.statusCode);
        
        if (data) {
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[WeaponX] Register API Response: %@", responseString);
                
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                    NSLog(@"[WeaponX] JSON Parsing Error: %@", jsonError);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                            completion(nil, nil, jsonError);
                    });
                }
                return;
            }
            
            // Check if the response indicates the device is banned
            if (responseDict[@"status"] && [responseDict[@"status"] isEqualToString:@"banned"]) {
                // Store ban information in user defaults
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setBool:YES forKey:@"WeaponXDeviceBanned"];
                [defaults setObject:responseDict[@"ban_reason"] ?: @"This device has been banned." forKey:@"WeaponXBanReason"];
                [defaults setObject:responseDict[@"banned_at"] ?: @"" forKey:@"WeaponXBannedAt"];
                [defaults synchronize];
                
                NSLog(@"[WeaponX] Device banned during registration attempt");
                
                // Create ban error
                NSError *banError = [NSError errorWithDomain:@"WeaponXErrorDomain" 
                                                    code:403 
                                                userInfo:@{
                                                    NSLocalizedDescriptionKey: responseDict[@"message"] ?: @"Registration not allowed: This device has been banned.",
                                                    @"banned_at": responseDict[@"banned_at"] ?: @"",
                                                    @"status": @"banned"
                                                }];
                
                // Show banned alert
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController 
                        alertControllerWithTitle:@"Registration Not Allowed" 
                        message:responseDict[@"message"] ?: @"This device has been banned. Registration is not permitted."
                        preferredStyle:UIAlertControllerStyleAlert];
                        
                    UIAlertAction *okAction = [UIAlertAction 
                        actionWithTitle:@"OK" 
                        style:UIAlertActionStyleDefault 
                        handler:nil];
                        
                    [alert addAction:okAction];
                    
                    [self presentAlertController:alert];
                    
                    if (completion) {
                        completion(nil, nil, banError);
                    }
                });
                
                return;
            }
            
                // Extract token
                NSString *token = responseDict[@"token"] ?: responseDict[@"access_token"] ?: 
                                responseDict[@"data"][@"token"] ?: responseDict[@"data"][@"access_token"];
                
                // Basic user data from register response
                NSDictionary *userData = responseDict[@"user"] ?: responseDict[@"data"][@"user"] ?: responseDict[@"data"];
                
                // If we have a token, log in the user right away
                if (token) {
                    // Save token to user defaults
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setObject:token forKey:@"WeaponXAuthToken"];
                    
                    // SERVER-PROVIDED ID ONLY: Save user ID directly from response
                    if (userData && userData[@"id"]) {
                        NSString *userId = [NSString stringWithFormat:@"%@", userData[@"id"]];
                        NSLog(@"[WeaponX] Setting server user ID from register response: %@", userId);
                        [defaults setObject:userId forKey:@"WeaponXServerUserId"];
                        
                        // Use TokenManager to properly store the token with associated userId
                        [[TokenManager sharedInstance] saveToken:token withUserId:userId];
                    }
                    
                    // Save basic user info
                    if (userData) {
                        [defaults setObject:userData forKey:@"WeaponXUserInfo"];
                        
                        // Also save username and email directly
                        if (userData[@"name"]) {
                            [defaults setObject:userData[@"name"] forKey:@"UserName"];
                        }
                        if (userData[@"email"]) {
                            [defaults setObject:userData[@"email"] forKey:@"UserEmail"];
                        }
                    }
                    
                    [defaults synchronize];
                    
                    // Fetch complete session info
                    [self fetchSessionInfoWithToken:token completion:^(NSDictionary *sessionInfo, NSError *sessionError) {
                        if (sessionError) {
                            NSLog(@"[WeaponX] Warning: Error fetching session info after registration: %@", sessionError.localizedDescription);
            } else {
                            NSLog(@"[WeaponX] Successfully fetched session info after registration");
                        }
                        
                        // Complete with user data
            if (completion) {
                            completion(userData, token, nil);
                        }
                    }];
                } else {
                    // No token, try to login with the credentials
                    NSLog(@"[WeaponX] No token in register response, attempting auto-login");
                    [self loginWithEmail:email password:password completion:completion];
            }
        } else {
            // No data returned
            NSError *noDataError = [NSError errorWithDomain:@"APIManagerErrorDomain" 
                                                      code:0 
                                                      userInfo:@{NSLocalizedDescriptionKey: @"No data returned from registration API"}];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, nil, noDataError);
                });
            }
        }
    }];
    
    [task resume];
    }];
}

// Helper method to get device unique identifiers
- (NSDictionary *)getDeviceIdentifiers {
    NSMutableDictionary *identifiers = [NSMutableDictionary dictionary];
    
    // Get device UUID (identifierForVendor)
    NSUUID *uuid = [[UIDevice currentDevice] identifierForVendor];
    if (uuid) {
        identifiers[@"device_uuid"] = [uuid UUIDString];
    }
    
    // Get device serial number from iOKit (for jailbroken devices)
    NSString *serialNumber = nil;
    
    // Use IOKit to get serial number if possible (requires jailbroken device)
    // This method will work on jailbroken iOS 15-16 with Dopamine rootless jailbreak
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
    if (platformExpert) {
        CFTypeRef serialNumberRef = IORegistryEntryCreateCFProperty(platformExpert, CFSTR("IOPlatformSerialNumber"), kCFAllocatorDefault, 0);
        if (serialNumberRef) {
            serialNumber = (__bridge_transfer NSString *)serialNumberRef;
            IOObjectRelease(platformExpert);
        }
    }
    
    if (serialNumber) {
        identifiers[@"device_serial"] = serialNumber;
    }
    
    return identifiers;
}

// New method to get detailed device model
- (NSString *)getDetailedDeviceModel {
    // First try to get the machine model from system info
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *modelIdentifier = [NSString stringWithCString:systemInfo.machine 
                                                  encoding:NSUTF8StringEncoding];
    
    // Map the identifier to a human-readable device model
    NSDictionary *deviceNamesByCode = @{
        // iPhones
        @"iPhone1,1": @"iPhone",
        @"iPhone1,2": @"iPhone 3G",
        @"iPhone2,1": @"iPhone 3GS",
        @"iPhone3,1": @"iPhone 4",
        @"iPhone3,2": @"iPhone 4",
        @"iPhone3,3": @"iPhone 4",
        @"iPhone4,1": @"iPhone 4S",
        @"iPhone5,1": @"iPhone 5",
        @"iPhone5,2": @"iPhone 5",
        @"iPhone5,3": @"iPhone 5C",
        @"iPhone5,4": @"iPhone 5C",
        @"iPhone6,1": @"iPhone 5S",
        @"iPhone6,2": @"iPhone 5S",
        @"iPhone7,1": @"iPhone 6 Plus",
        @"iPhone7,2": @"iPhone 6",
        @"iPhone8,1": @"iPhone 6S",
        @"iPhone8,2": @"iPhone 6S Plus",
        @"iPhone8,4": @"iPhone SE",
        @"iPhone9,1": @"iPhone 7",
        @"iPhone9,2": @"iPhone 7 Plus",
        @"iPhone9,3": @"iPhone 7",
        @"iPhone9,4": @"iPhone 7 Plus",
        @"iPhone10,1": @"iPhone 8",
        @"iPhone10,2": @"iPhone 8 Plus",
        @"iPhone10,3": @"iPhone X",
        @"iPhone10,4": @"iPhone 8",
        @"iPhone10,5": @"iPhone 8 Plus",
        @"iPhone10,6": @"iPhone X",
        @"iPhone11,2": @"iPhone XS",
        @"iPhone11,4": @"iPhone XS Max",
        @"iPhone11,6": @"iPhone XS Max",
        @"iPhone11,8": @"iPhone XR",
        @"iPhone12,1": @"iPhone 11",
        @"iPhone12,3": @"iPhone 11 Pro",
        @"iPhone12,5": @"iPhone 11 Pro Max",
        @"iPhone13,1": @"iPhone 12 Mini",
        @"iPhone13,2": @"iPhone 12",
        @"iPhone13,3": @"iPhone 12 Pro",
        @"iPhone13,4": @"iPhone 12 Pro Max",
        @"iPhone14,2": @"iPhone 13 Pro",
        @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,4": @"iPhone 13 Mini",
        @"iPhone14,5": @"iPhone 13",
        @"iPhone14,6": @"iPhone SE (3rd generation)",
        @"iPhone14,7": @"iPhone 14",
        @"iPhone14,8": @"iPhone 14 Plus",
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        @"iPhone16,1": @"iPhone 15 Pro",
        @"iPhone16,2": @"iPhone 15 Pro Max",
        
        // iPads
        @"iPad1,1": @"iPad",
        @"iPad2,1": @"iPad 2",
        @"iPad2,2": @"iPad 2",
        @"iPad2,3": @"iPad 2",
        @"iPad2,4": @"iPad 2",
        @"iPad2,5": @"iPad Mini",
        @"iPad2,6": @"iPad Mini",
        @"iPad2,7": @"iPad Mini",
        @"iPad3,1": @"iPad 3",
        @"iPad3,2": @"iPad 3",
        @"iPad3,3": @"iPad 3",
        @"iPad3,4": @"iPad 4",
        @"iPad3,5": @"iPad 4",
        @"iPad3,6": @"iPad 4",
        @"iPad4,1": @"iPad Air",
        @"iPad4,2": @"iPad Air",
        @"iPad4,3": @"iPad Air",
        @"iPad4,4": @"iPad Mini 2",
        @"iPad4,5": @"iPad Mini 2",
        @"iPad4,6": @"iPad Mini 2",
        @"iPad4,7": @"iPad Mini 3",
        @"iPad4,8": @"iPad Mini 3",
        @"iPad4,9": @"iPad Mini 3",
        @"iPad5,1": @"iPad Mini 4",
        @"iPad5,2": @"iPad Mini 4",
        @"iPad5,3": @"iPad Air 2",
        @"iPad5,4": @"iPad Air 2",
        @"iPad6,3": @"iPad Pro (9.7-inch)",
        @"iPad6,4": @"iPad Pro (9.7-inch)",
        @"iPad6,7": @"iPad Pro (12.9-inch)",
        @"iPad6,8": @"iPad Pro (12.9-inch)",
        @"iPad6,11": @"iPad (5th generation)",
        @"iPad6,12": @"iPad (5th generation)",
        @"iPad7,1": @"iPad Pro (12.9-inch) (2nd generation)",
        @"iPad7,2": @"iPad Pro (12.9-inch) (2nd generation)",
        @"iPad7,3": @"iPad Pro (10.5-inch)",
        @"iPad7,4": @"iPad Pro (10.5-inch)",
        @"iPad7,5": @"iPad (6th generation)",
        @"iPad7,6": @"iPad (6th generation)",
        @"iPad7,11": @"iPad (7th generation)",
        @"iPad7,12": @"iPad (7th generation)",
        @"iPad8,1": @"iPad Pro (11-inch)",
        @"iPad8,2": @"iPad Pro (11-inch)",
        @"iPad8,3": @"iPad Pro (11-inch)",
        @"iPad8,4": @"iPad Pro (11-inch)",
        @"iPad8,5": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,6": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,7": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,8": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,9": @"iPad Pro (11-inch) (2nd generation)",
        @"iPad8,10": @"iPad Pro (11-inch) (2nd generation)",
        @"iPad8,11": @"iPad Pro (12.9-inch) (4th generation)",
        @"iPad8,12": @"iPad Pro (12.9-inch) (4th generation)",
        
        // iPod Touch
        @"iPod1,1": @"iPod Touch",
        @"iPod2,1": @"iPod Touch (2nd generation)",
        @"iPod3,1": @"iPod Touch (3rd generation)",
        @"iPod4,1": @"iPod Touch (4th generation)",
        @"iPod5,1": @"iPod Touch (5th generation)",
        @"iPod7,1": @"iPod Touch (6th generation)",
        @"iPod9,1": @"iPod Touch (7th generation)",
        
        // Simulator
        @"i386": @"Simulator",
        @"x86_64": @"Simulator",
        @"arm64": @"Simulator"
    };
    
    NSString *deviceName = deviceNamesByCode[modelIdentifier];
    
    if (!deviceName) {
        if ([modelIdentifier rangeOfString:@"iPhone"].location != NSNotFound) {
            deviceName = @"iPhone";
        } else if ([modelIdentifier rangeOfString:@"iPad"].location != NSNotFound) {
            deviceName = @"iPad";
        } else if ([modelIdentifier rangeOfString:@"iPod"].location != NSNotFound) {
            deviceName = @"iPod Touch";
        } else {
            deviceName = @"iOS Device";
        }
    }
    
    NSLog(@"[WeaponX] Device model identifier: %@, mapped to: %@", modelIdentifier, deviceName);
    return deviceName;
}

// Add this new method somewhere appropriate in the file, like near the end before @end
- (void)fetchPublicIPAddress:(void (^)(NSString *))completion {
    // Use a public IP service like ipify
    NSURL *url = [NSURL URLWithString:@"https://api.ipify.org?format=json"];
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *ipAddress = nil;
        
        if (!error && data) {
            NSError *jsonError;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (!jsonError && jsonResponse[@"ip"]) {
                ipAddress = jsonResponse[@"ip"];
                NSLog(@"[WeaponX] ✅ Successfully retrieved public IP: %@", ipAddress);
                completion(ipAddress);
                return;
            } else {
                NSLog(@"[WeaponX] ⚠️ Could not parse IP data: %@", jsonError);
            }
        } else {
            NSLog(@"[WeaponX] ❌ Failed to get public IP: %@", error);
            
            // Check if network is still available before trying alternate service
            if (![self isNetworkAvailable]) {
                NSLog(@"[WeaponX] 🌐 Network is no longer available, skipping alternate IP service");
                completion(nil);
                return;
            }
            
            // Try alternate service if first one fails
            NSURL *altUrl = [NSURL URLWithString:@"https://ifconfig.me/ip"];
            NSURLSessionDataTask *altTask = [session dataTaskWithURL:altUrl completionHandler:^(NSData *altData, NSURLResponse *altResponse, NSError *altError) {
                if (!altError && altData) {
                    NSString *ipString = [[NSString alloc] initWithData:altData encoding:NSUTF8StringEncoding];
                    ipString = [ipString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (ipString.length > 0) {
                        NSLog(@"[WeaponX] ✅ Retrieved public IP from alternate source: %@", ipString);
                        completion(ipString);
                        return;
                    }
                }
                completion(nil);
            }];
            [altTask resume];
            return;
        }
        
        // Fallback if we reach here (no IP from primary source, but no error either)
        completion(ipAddress);
    }];
    
    [task resume];
}

- (void)fetchCSRFToken:(void (^)(NSString *))completion {
    [self fetchCSRFTokenWithExtendedCompletion:^(BOOL success, NSString *token) {
            if (completion) {
            completion(success ? token : nil);
        }
    }];
}

// Method to present an alert controller
- (void)presentAlertController:(UIAlertController *)alertController {
    // Get the top view controller to present the alert
    UIViewController *topController = [self getTopViewController];
    if (topController) {
        [topController presentViewController:alertController animated:YES completion:nil];
    } else {
        NSLog(@"[WeaponX] ❌ Failed to present alert - no top view controller found");
    }
}

// Helper method to get the topmost view controller
- (UIViewController *)getTopViewController {
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        NSSet *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *candidateWindow in windowScene.windows) {
                    if (candidateWindow.isKeyWindow) {
                        keyWindow = candidateWindow;
                        break;
                    }
                }
                // If no key window was found, use the first window in the scene
                if (!keyWindow && windowScene.windows.count > 0) {
                    keyWindow = windowScene.windows.firstObject;
                }
                break;
            }
        }
    
        // Fallback if no key window found - use compiler pragmas to suppress deprecation warnings
        if (!keyWindow) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (UIWindow *candidateWindow in [UIApplication sharedApplication].windows) {
                if (candidateWindow.isKeyWindow) {
                    keyWindow = candidateWindow;
                    break;
                }
            }
            #pragma clang diagnostic pop
        }
        } else {
        // For iOS 12 and earlier, use the deprecated keyWindow property
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    
    if (!keyWindow) {
        NSLog(@"[WeaponX] ❌ No window found to present alert");
        return nil;
    }
    
    UIViewController *rootViewController = keyWindow.rootViewController;
    UIViewController *topController = rootViewController;
    
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    return topController;
}

// Logout method
- (void)logoutWithToken:(NSString *)token completion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] Logging out user with token: %@", token);
    
    NSString *urlString = [self apiUrlForEndpoint:@"api/logout"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Logout failed with error: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] Logout response status code: %ld", (long)httpResponse.statusCode);
        
        // Clear all user data on successful logout
        dispatch_async(dispatch_get_main_queue(), ^{
            [self clearAllUserData];
            
            if (completion) {
                completion(YES, nil);
            }
            
            // Exit and relaunch the app after successful logout
            [self exitAndRelaunchApp];
        });
    }];
    
    [task resume];
}

// Session info method
- (void)fetchSessionInfoWithToken:(NSString *)token completion:(void (^)(NSDictionary *sessionInfo, NSError *error))completion {
    // Create URL for the session info endpoint
    NSString *urlString = [self apiUrlForEndpoint:@"session-info"];
    
    // Create request
    NSURLRequest *request = [self prepareRequestWithToken:token method:@"GET" url:urlString];
    
    // Send request
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSDictionary *responseObject = nil;
        
        if (data) {
            responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }
        
        // Handle 401 Unauthorized
        if (httpResponse.statusCode == 401) {
            [self handleUnauthorizedResponse:httpResponse completion:^(BOOL tokenReset, NSString *newToken) {
                if (tokenReset && newToken) {
                    // Retry with new token
                    [self fetchSessionInfoWithToken:newToken completion:completion];
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSError *authError = [NSError errorWithDomain:@"APIManagerErrorDomain" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Authentication required"}];
                        completion(nil, authError);
                    });
                }
            }];
            return;
        }
        
        // Process successful response
        if (httpResponse.statusCode == 200 && responseObject) {
            // Extract server timestamp if available
            if (responseObject[@"server_time"]) {
                // Convert server timestamp to NSTimeInterval and record it
                NSString *serverTimeString = responseObject[@"server_time"];
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
                NSDate *serverTime = [dateFormatter dateFromString:serverTimeString];
                
                if (serverTime) {
                    // Record server timestamp for secure time synchronization
                    [[SecureTimeManager sharedManager] recordServerTimestamp:[serverTime timeIntervalSince1970]];
                    
                    NSLog(@"[WeaponX] 🔄 Synchronized with server time: %@", serverTimeString);
                }
            }
            
            // Record successful verification time
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:[NSDate date] forKey:@"WeaponXLastServerConfirmationDate"];
            [defaults synchronize];
            
            // Reset usage counters since we've successfully verified with server
            [[SecureTimeManager sharedManager] resetUsageCounters];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(responseObject, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *errorMessage = responseObject[@"message"] ?: @"Unknown error";
                NSError *apiError = [NSError errorWithDomain:@"APIManagerErrorDomain" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
                completion(nil, apiError);
            });
        }
    }];
    
    [task resume];
}

// User data method
- (void)fetchUserDataWithToken:(NSString *)token completion:(void (^)(NSDictionary *userData, NSError *error))completion {
    NSLog(@"[WeaponX] Fetching user data with token: %@", token);
    
    NSString *urlString = [self apiUrlForEndpoint:@"api/user"];
    NSURLRequest *request = [self prepareRequestWithToken:token method:@"GET" url:urlString];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to fetch user data: %@", error);
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if ([self handleUnauthorizedResponse:httpResponse completion:^(BOOL tokenReset, NSString *newToken) {
            if (tokenReset && newToken) {
                [self fetchUserDataWithToken:newToken completion:completion];
            }
        }]) {
            return;
        }
        
        if (httpResponse.statusCode == 200) {
            NSError *jsonError = nil;
            NSDictionary *userData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Failed to parse user data JSON: %@", jsonError);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, jsonError);
                    });
                }
                return;
            }
            
            // Save user data to NSUserDefaults
            [[NSUserDefaults standardUserDefaults] setObject:userData forKey:@"WeaponXUserData"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            NSLog(@"[WeaponX] ✅ Successfully fetched user data");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(userData, nil);
                });
                        }
                    } else {
            NSError *statusError = [NSError errorWithDomain:@"WeaponXAPIError" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch user data"}];
            
                        if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, statusError);
                });
            }
        }
    }];
    
    [task resume];
}

// Plan data method
- (void)fetchUserPlanWithToken:(NSString *)token completion:(void (^)(NSDictionary *planData, NSError *error))completion {
    NSLog(@"[WeaponX] Fetching user plan with token: %@", token);
    
    NSString *urlString = [self apiUrlForEndpoint:@"api/user/plan"];
    NSURLRequest *request = [self prepareRequestWithToken:token method:@"GET" url:urlString];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to fetch user plan: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if ([self handleUnauthorizedResponse:httpResponse completion:^(BOOL tokenReset, NSString *newToken) {
            if (tokenReset && newToken) {
                [self fetchUserPlanWithToken:newToken completion:completion];
            }
        }]) {
            return;
        }
        
        if (httpResponse.statusCode == 200) {
            NSError *jsonError = nil;
            NSDictionary *planData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Failed to parse user plan JSON: %@", jsonError);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, jsonError);
                    });
                }
                return;
            }
            
            NSLog(@"[WeaponX] ✅ Successfully fetched user plan");
            
            // Store the plan data with a secure hash to prevent tampering
            [self storePlanDataSecurely:planData];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(planData, nil);
                });
            }
        } else {
            NSError *statusError = [NSError errorWithDomain:@"WeaponXAPIError" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch user plan"}];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, statusError);
                });
            }
        }
    }];
    
    [task resume];
}

// Fetch all available plans
- (void)fetchAllPlansWithToken:(NSString *)token completion:(void (^)(NSArray *plans, NSError *error))completion {
    NSLog(@"[WeaponX] Fetching all available plans with token: %@", token);
    
    NSString *urlString = [self apiUrlForEndpoint:@"api/plans"];
    NSURLRequest *request = [self prepareRequestWithToken:token method:@"GET" url:urlString];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to fetch plans: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if ([self handleUnauthorizedResponse:httpResponse completion:^(BOOL tokenReset, NSString *newToken) {
            if (tokenReset && newToken) {
                [self fetchAllPlansWithToken:newToken completion:completion];
            }
        }]) {
            return;
        }
        
        if (httpResponse.statusCode == 200) {
            NSError *jsonError = nil;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Failed to parse plans JSON: %@", jsonError);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, jsonError);
                    });
                }
                return;
            }
            
            // Extract plans array from response
            NSArray *plans = nil;
            
            if (responseDict[@"plans"] && [responseDict[@"plans"] isKindOfClass:[NSArray class]]) {
                plans = responseDict[@"plans"];
            } else if (responseDict[@"data"] && [responseDict[@"data"] isKindOfClass:[NSArray class]]) {
                plans = responseDict[@"data"];
            } else if ([responseDict isKindOfClass:[NSArray class]]) {
                plans = (NSArray *)responseDict;
            }
            
            if (!plans) {
                NSLog(@"[WeaponX] ⚠️ No plans found in response: %@", responseDict);
                plans = @[];
            }
            
            NSLog(@"[WeaponX] ✅ Successfully fetched %lu plans", (unsigned long)plans.count);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(plans, nil);
                });
            }
        } else {
            NSError *statusError = [NSError errorWithDomain:@"WeaponXAPIError" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch plans"}];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, statusError);
                });
            }
        }
    }];
    
    [task resume];
}

// Purchase a plan
- (void)purchasePlanWithToken:(NSString *)token planId:(NSString *)planId completion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] Purchasing plan with ID: %@ using token: %@", planId, token);
    
    // First fetch a CSRF token to use with the purchase request
    [self fetchCSRFTokenWithExtendedCompletion:^(BOOL success, NSString *csrfToken) {
        if (!success || !csrfToken) {
            NSLog(@"[WeaponX] ⚠️ Failed to get CSRF token for plan purchase");
            // Fall back to regular request without CSRF token
            [self performPlanPurchaseWithToken:token planId:planId csrfToken:nil completion:completion];
        } else {
            NSLog(@"[WeaponX] ✅ Got CSRF token for plan purchase: %@...", [csrfToken substringToIndex:MIN(10, csrfToken.length)]);
            [self performPlanPurchaseWithToken:token planId:planId csrfToken:csrfToken completion:completion];
        }
    }];
}

// Actual plan purchase implementation
- (void)performPlanPurchaseWithToken:(NSString *)token planId:(NSString *)planId csrfToken:(NSString *)csrfToken completion:(void (^)(BOOL success, NSError *error))completion {
    // Use the web endpoint instead of the API endpoint
    NSString *urlString = [NSString stringWithFormat:@"%@/account/plans/purchase", self.baseURLString];
    NSLog(@"[WeaponX] 🌐 Plan purchase URL (Web endpoint): %@", urlString);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    
    // Add CSRF token if available
    if (csrfToken) {
        [request setValue:csrfToken forHTTPHeaderField:@"X-XSRF-TOKEN"];
        NSLog(@"[WeaponX] 🔒 Using CSRF token: %@...", [csrfToken substringToIndex:MIN(10, csrfToken.length)]);
    }
    
    // Log the request we're going to send
    NSLog(@"[WeaponX] 📝 Plan purchase request body: plan_id=%@", planId);
    
    NSDictionary *params = @{@"plan_id": planId};
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonError];
    
    if (jsonError) {
        NSLog(@"[WeaponX] ❌ Failed to create purchase JSON: %@", jsonError);
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, jsonError);
            });
        }
        return;
    }
    
    [request setHTTPBody:jsonData];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to purchase plan: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if ([self handleUnauthorizedResponse:httpResponse completion:^(BOOL tokenReset, NSString *newToken) {
            if (tokenReset && newToken) {
                [self purchasePlanWithToken:newToken planId:planId completion:completion];
            }
        }]) {
            return;
        }
        
        if (httpResponse.statusCode == 200 || httpResponse.statusCode == 201) {
            NSLog(@"[WeaponX] ✅ Successfully purchased plan");
            // Check if the response is redirecting - this would indicate success for web endpoint
            NSString *location = [httpResponse.allHeaderFields objectForKey:@"Location"];
            if (location) {
                NSLog(@"[WeaponX] 🔄 Redirect location: %@", location);
            }
            
            // For web endpoint, try to extract success message from response
            if (data) {
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[WeaponX] 📝 Plan purchase response: %@", responseString);
                
                // Check if we got JSON or HTML
                if ([responseString hasPrefix:@"{"]) {
                    // JSON response
                    NSError *jsonError = nil;
                    NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (!jsonError && responseDict) {
                        NSLog(@"[WeaponX] ✅ Plan purchase JSON response: %@", responseDict);
                    }
                } else {
                    // HTML response - check for success indicators
                    if ([responseString containsString:@"success"] || [responseString containsString:@"successfully"]) {
                        NSLog(@"[WeaponX] ✅ Found success message in HTML response");
                    }
                }
            }
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES, nil);
                });
            }
        } else {
            NSString *errorMessage = @"Failed to purchase plan";
            
            // Try to extract error message from response
            if (data) {
                // Log the raw response first
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[WeaponX] 📝 Plan purchase error response: %@", responseString);
                
                // Check if it's JSON or HTML
                if ([responseString hasPrefix:@"{"]) {
                    // Try to parse JSON
                    NSError *jsonError = nil;
                    NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    
                    if (jsonError) {
                        NSLog(@"[WeaponX] ❌ Failed to parse error response JSON: %@", jsonError);
                    } else {
                        NSLog(@"[WeaponX] ⚠️ Plan purchase error details: %@", responseDict);
                        if (responseDict[@"message"]) {
                            errorMessage = [NSString stringWithFormat:@"%@", responseDict[@"message"]];
                        } else if (responseDict[@"error"]) {
                            errorMessage = [NSString stringWithFormat:@"%@", responseDict[@"error"]];
                        }
                    }
                } else {
                    // HTML response - try to extract error message
                    NSLog(@"[WeaponX] ⚠️ Received HTML response for error");
                    
                    // Look for common error indicators in HTML
                    if ([responseString containsString:@"error"]) {
                        NSLog(@"[WeaponX] ⚠️ Found error indicator in HTML response");
                        // Could implement regex to extract error message here
                    }
                }
            }
            
            // Log more detailed information about the failed request
            NSLog(@"[WeaponX] ❌ Failed to purchase plan with status code: %ld", (long)httpResponse.statusCode);
            NSLog(@"[WeaponX] ❌ Plan purchase request headers: %@", [request allHTTPHeaderFields]);
            NSLog(@"[WeaponX] ❌ Plan purchase response headers: %@", [httpResponse allHeaderFields]);
            
            NSError *statusError = [NSError errorWithDomain:@"WeaponXAPIError" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            
            NSLog(@"[WeaponX] ❌ Failed to purchase plan: %@", errorMessage);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, statusError);
                });
            }
        }
    }];
    
    [task resume];
}

// User presence/status method
- (void)updateUserPresence:(NSString *)token status:(NSString *)status completion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] Updating user presence with status: %@", status);
    
    NSString *urlString = [self apiUrlForEndpoint:@"api/user/presence"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    
    NSDictionary *params = @{@"status": status};
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonError];
    
    if (jsonError) {
        NSLog(@"[WeaponX] ❌ Failed to create presence JSON: %@", jsonError);
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, jsonError);
            });
        }
        return;
    }
    
    [request setHTTPBody:jsonData];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Presence update failed with error: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if ([self handleUnauthorizedResponse:httpResponse completion:^(BOOL tokenReset, NSString *newToken) {
            if (tokenReset && newToken) {
                [self updateUserPresence:newToken status:status completion:completion];
            }
        }]) {
            return;
        }
        
        if (httpResponse.statusCode == 200 || httpResponse.statusCode == 204) {
            NSLog(@"[WeaponX] ✅ Successfully updated user presence");
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES, nil);
                });
        }
    } else {
            NSError *statusError = [NSError errorWithDomain:@"WeaponXAPIError" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: @"Failed to update user presence"}];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, statusError);
            });
        }
    }
    }];
    
    [task resume];
}

// Stop heartbeat
- (void)stopHeartbeat {
        NSLog(@"[WeaponX] Stopping heartbeat timer");
    
    if (self.heartbeatTimer != nil) {
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
        NSLog(@"[WeaponX] ✅ Heartbeat timer stopped");
    }
}

// Prepare request with token
- (NSURLRequest *)prepareRequestWithToken:(NSString *)token method:(NSString *)method url:(NSString *)urlString {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:method];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    if (token) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    
    return request;
}

// Handle unauthorized response
- (BOOL)handleUnauthorizedResponse:(NSHTTPURLResponse *)response completion:(void (^)(BOOL tokenReset, NSString *newToken))completion {
    if (response.statusCode == 401) {
        NSLog(@"[WeaponX] ⚠️ Received 401 Unauthorized response");
        
        // Clear user data and token
        [self clearAllUserData];
        
        // Notify via completion handler
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, nil);
            });
        }
        
        // Present an alert to the user
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Session Expired"
                                                                           message:@"Your login session has expired. Please log in again."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentAlertOnTopViewController:alert];
        });
        
        return YES;
    }
    
    return NO;
}

// API URL for endpoint
- (NSString *)apiUrlForEndpoint:(NSString *)endpoint {
    NSString *baseUrl = [self baseURL];
    
    // Ensure endpoint doesn't start with a slash if the baseUrl ends with one
    if ([baseUrl hasSuffix:@"/"] && [endpoint hasPrefix:@"/"]) {
        endpoint = [endpoint substringFromIndex:1];
    }
    
    // Ensure there's a slash between baseUrl and endpoint if needed
    if (![baseUrl hasSuffix:@"/"] && ![endpoint hasPrefix:@"/"]) {
        return [NSString stringWithFormat:@"%@/%@", baseUrl, endpoint];
    }
    
    return [NSString stringWithFormat:@"%@%@", baseUrl, endpoint];
}

// Clear all user data
- (void)clearAllUserData {
    NSLog(@"[WeaponX] Clearing all user data");
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"WeaponXAuthToken"];
    [defaults removeObjectForKey:@"WeaponXUserData"];
    [defaults removeObjectForKey:@"WeaponXUserID"];
    [defaults synchronize];
    
    // Stop heartbeat if it's running
    [self stopHeartbeat];
    
    NSLog(@"[WeaponX] ✅ All user data cleared");
}

// Check if user is logged in
- (BOOL)isUserLoggedIn {
    NSString *token = [self currentAuthToken];
    return (token != nil && ![token isEqualToString:@""]);
}

// Get current auth token
- (NSString *)currentAuthToken {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"WeaponXAuthToken"];
}

// Get current user data
- (NSDictionary *)currentUserData {
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"WeaponXUserData"];
}

// Method to exit and relaunch the current app - optimized for iOS 15 and Dopamine 2
- (void)exitAndRelaunchApp {
    NSLog(@"[WeaponX] 🔄 Attempting to exit and relaunch app for iOS 15 with Dopamine 2");
    
    // Get the bundle identifier of the host application
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSLog(@"[WeaponX] Current app bundle ID: %@", bundleID);
    
    // Use killall command to kill the current app process
    NSString *executableName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
    
    if (!executableName) {
        NSLog(@"[WeaponX] ⚠️ Could not determine executable name for current app");
        return;
    }
    
    NSLog(@"[WeaponX] Preparing to restart app with executable name: %@", executableName);
    
    // For Dopamine 2 on iOS 15, we'll use a direct approach
    // Simply use posix_spawn to call uicache to refresh the app
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Check for Dopamine 2 specifics - the rootless jailbreak path
        const char *executable_str = [executableName UTF8String];
        
        // First check the Dopamine rootless path
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/killall"]) {
            // On Dopamine 2, use the rootless paths
            pid_t pid;
            const char *killall_path = "/var/jb/usr/bin/killall";
            char *const argv[] = {(char *)"killall", (char *)"-9", (char *)executable_str, NULL};
            posix_spawn(&pid, killall_path, NULL, NULL, argv, NULL);
        } else {
            // Standard jailbreak path
            pid_t pid;
            const char *killall_path = "/usr/bin/killall";
            char *const argv[] = {(char *)"killall", (char *)"-9", (char *)executable_str, NULL};
            posix_spawn(&pid, killall_path, NULL, NULL, argv, NULL);
        }
        
        // Try to tell the OS to restart our application with openURL
        NSURL *launchURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleID]];
        
        if (@available(iOS 10.0, *)) {
            [[UIApplication sharedApplication] openURL:launchURL options:@{} completionHandler:nil];
        } else {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [[UIApplication sharedApplication] openURL:launchURL];
            #pragma clang diagnostic pop
        }
        
        // Directly exit the app as a last resort
        exit(0);
    });
}

// Add this helper method before the exitAndRelaunchApp method
- (UIWindow *)keyWindow {
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        NSSet *connectedScenes = [UIApplication sharedApplication].connectedScenes;
    for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *candidateWindow in windowScene.windows) {
                    if (candidateWindow.isKeyWindow) {
                        keyWindow = candidateWindow;
                    break;
                }
            }
                // If no key window was found, use the first window in the scene
                if (!keyWindow && windowScene.windows.count > 0) {
                    keyWindow = windowScene.windows.firstObject;
                }
                break;
            }
        }
    
        // Fallback if no key window found - use compiler pragmas to suppress deprecation warnings
    if (!keyWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (UIWindow *candidateWindow in [UIApplication sharedApplication].windows) {
                if (candidateWindow.isKeyWindow) {
                    keyWindow = candidateWindow;
                break;
            }
        }
        #pragma clang diagnostic pop
    }
    } else {
        // For iOS 12 and earlier, use the deprecated keyWindow property
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    
    return keyWindow;
}

// Method to save authentication token
- (void)saveToken:(NSString *)token {
    NSLog(@"[WeaponX] 💾 Saving authentication token");
    
    // Save to user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:token forKey:@"WeaponXAuthToken"];
    [defaults synchronize];
    
    // Also save to TokenManager for better security
    [[TokenManager sharedInstance] saveToken:token withUserId:nil];
}

// Method to present an alert on the top view controller
- (void)presentAlertOnTopViewController:(UIAlertController *)alertController {
    // Get the top view controller to present the alert
    UIViewController *topController = [self getTopViewController];
    if (topController) {
        [topController presentViewController:alertController animated:YES completion:nil];
    } else {
        NSLog(@"[WeaponX] ❌ Failed to present alert - no top view controller found");
    }
}

#pragma mark - App Update Methods

- (void)checkForUpdatesWithCurrentVersion:(NSString *)version buildNumber:(NSInteger)buildNumber completion:(void (^)(NSDictionary *updateInfo, NSError *error))completion {
    NSLog(@"[WeaponX] Checking for app updates with current version: %@ (build %ld)", version, (long)buildNumber);
    
    // Use the /api/plans endpoint which we know exists on the server
    NSString *urlString = [self apiUrlForEndpoint:@"api/plans"];
    NSLog(@"[WeaponX] Update URL: %@", urlString);
    
    // Create request to get plans (we're just using this as a connectivity test)
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Set auth token if available
    NSString *authToken = [self currentAuthToken];
    if (authToken) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", authToken] forHTTPHeaderField:@"Authorization"];
    }
    
    // Log the request details
    NSLog(@"[WeaponX] Update check request - Method: %@, URL: %@", request.HTTPMethod, urlString);
    
    // Create session task
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Error checking for updates: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        // Log the response information
        NSLog(@"[WeaponX] Update check response status: %ld", (long)httpResponse.statusCode);
        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[WeaponX] Update check response body: %@", responseString);
        }
        
        if (httpResponse.statusCode == 200) {
            // For now, we'll create a static update response while we configure the server properly
            NSMutableDictionary *updateInfo = [NSMutableDictionary dictionary];
            
            // Hard-coded update info for testing
            NSString *latestVersion = @"1.0.1";
            NSInteger latestBuild = 520; // The one we created earlier
            
            // Compare with current version to determine if update is needed
            BOOL updateAvailable = NO;
            
            // Simple version comparison - compare version string components
            NSArray *currentVersionComponents = [version componentsSeparatedByString:@"."];
            NSArray *latestVersionComponents = [latestVersion componentsSeparatedByString:@"."];
            
            // Compare major version
            NSInteger currentMajor = currentVersionComponents.count > 0 ? [currentVersionComponents[0] integerValue] : 0;
            NSInteger latestMajor = latestVersionComponents.count > 0 ? [latestVersionComponents[0] integerValue] : 0;
            
            if (latestMajor > currentMajor) {
                updateAvailable = YES;
            } else if (latestMajor == currentMajor) {
                // Compare minor version
                NSInteger currentMinor = currentVersionComponents.count > 1 ? [currentVersionComponents[1] integerValue] : 0;
                NSInteger latestMinor = latestVersionComponents.count > 1 ? [latestVersionComponents[1] integerValue] : 0;
                
                if (latestMinor > currentMinor) {
                    updateAvailable = YES;
                } else if (latestMinor == currentMinor) {
                    // Compare patch version
                    NSInteger currentPatch = currentVersionComponents.count > 2 ? [currentVersionComponents[2] integerValue] : 0;
                    NSInteger latestPatch = latestVersionComponents.count > 2 ? [latestVersionComponents[2] integerValue] : 0;
                    
                    if (latestPatch > currentPatch) {
                        updateAvailable = YES;
                    } else if (latestPatch == currentPatch) {
                        // Same version, check build number
                        if (latestBuild > buildNumber) {
                            updateAvailable = YES;
                        }
                    }
                }
            }
            
            // Construct the update info
            updateInfo[@"status"] = @"success";
            updateInfo[@"update_available"] = @(updateAvailable);
            
            if (updateAvailable) {
                NSMutableDictionary *versionInfo = [NSMutableDictionary dictionary];
                versionInfo[@"version"] = latestVersion;
                versionInfo[@"build_number"] = @(latestBuild);
                versionInfo[@"changelog"] = @"• Fixed app update functionality\n• Improved stability and performance\n• Added new features";
                versionInfo[@"is_required"] = @(NO); // Make it optional for now
                versionInfo[@"release_date"] = @"2025-03-08";
                versionInfo[@"human_size"] = @"1.2 MB";
                
                // Construct the download URL
                // For now, we'll use a placeholder that we'll need to configure on the server
                NSString *downloadUrl = [NSString stringWithFormat:@"%@/app/download/4", self.baseURLString];
                versionInfo[@"download_url"] = downloadUrl;
                
                updateInfo[@"version"] = versionInfo;
            } else {
                updateInfo[@"message"] = @"You are using the latest version";
            }
            
            NSLog(@"[WeaponX] ✅ Update check completed: %@", updateInfo);
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(updateInfo, nil);
                });
            }
        } else {
            NSLog(@"[WeaponX] ❌ Update check failed with status code %ld", (long)httpResponse.statusCode);
            
            // Try to parse error message from response if available
            NSString *errorMessage = @"Failed to check for updates";
            if (data) {
                NSError *jsonError = nil;
                NSDictionary *errorData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (!jsonError && errorData[@"message"]) {
                    errorMessage = [NSString stringWithFormat:@"Server error: %@", errorData[@"message"]];
                }
            }
            
            NSError *statusError = [NSError errorWithDomain:@"WeaponXUpdateErrorDomain" 
                                                       code:httpResponse.statusCode 
                                                   userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, statusError);
                });
            }
        }
    }];
    
    [task resume];
}

- (void)downloadAppUpdate:(NSString *)downloadUrl destination:(NSURL *)destinationPath completion:(void (^)(NSURL *fileURL, NSError *error))completion {
    NSLog(@"[WeaponX] Starting download of app update from: %@", downloadUrl);
    
    // Create NSURLSessionConfiguration with adjusted SSL settings
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    // Create a custom session with a delegate that will handle SSL challenges
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config 
                                                         delegate:self 
                                                    delegateQueue:nil];
    
    // Create download task with the custom session
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:downloadUrl] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Download error: %@", error);
            
            // Check for SSL-specific errors
            if ([error.domain isEqualToString:NSURLErrorDomain] && 
                (error.code == -1200 || error.code == -1202 || error.code == -1203)) {
                NSLog(@"[WeaponX] ❌ SSL Certificate error detected: %@", error.localizedDescription);
                
                // Create a more user-friendly error message for SSL issues
                NSString *sslErrorMessage = @"There was a problem with the server's security certificate. Please try again later or contact support.";
                NSError *sslError = [NSError errorWithDomain:@"WeaponXDownloadErrorDomain" 
                                                      code:error.code 
                                                  userInfo:@{NSLocalizedDescriptionKey: sslErrorMessage}];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, sslError);
                });
                return;
            }
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] Download response status: %ld", (long)httpResponse.statusCode);
        
        
        // Handle HTTP error responses
        if (httpResponse.statusCode != 200) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to download update with status code %ld", (long)httpResponse.statusCode];
            NSLog(@"[WeaponX] ❌ %@", errorMessage);
            
            // If we get a 403 or 404, it means the URL is wrong (forbidden or not found)
            if (httpResponse.statusCode == 403 || httpResponse.statusCode == 404) {
                errorMessage = [NSString stringWithFormat:@"The update file could not be accessed (status %ld). Please contact support.", (long)httpResponse.statusCode];
            }
            
            NSError *statusError = [NSError errorWithDomain:@"WeaponXDownloadErrorDomain" 
                                                       code:httpResponse.statusCode 
                                                   userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            
            NSLog(@"[WeaponX] ❌ Download failed with status code %ld", (long)httpResponse.statusCode);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, statusError);
                });
            }
            return;
        }
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // Create directory if it doesn't exist
        NSError *dirError = nil;
        if (![fileManager createDirectoryAtURL:[destinationPath URLByDeletingLastPathComponent] 
                    withIntermediateDirectories:YES 
                                     attributes:nil 
                                          error:&dirError]) {
            NSLog(@"[WeaponX] ❌ Error creating directory: %@", dirError);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, dirError);
                });
            }
            return;
        }
        
        // Remove existing file if it exists
        if ([fileManager fileExistsAtPath:destinationPath.path]) {
            NSError *removeError = nil;
            if (![fileManager removeItemAtURL:destinationPath error:&removeError]) {
                NSLog(@"[WeaponX] ❌ Error removing existing file: %@", removeError);
                // Continue anyway
            }
        }
        
        // Move downloaded file to destination
        NSError *moveError = nil;
        if ([fileManager moveItemAtURL:location toURL:destinationPath error:&moveError]) {
            NSLog(@"[WeaponX] ✅ Download completed and saved to: %@", destinationPath.path);
            
            // Check if the file size makes sense
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:destinationPath.path error:nil];
            NSNumber *fileSize = attributes[NSFileSize];
            if (fileSize && [fileSize longLongValue] > 0) {
                NSLog(@"[WeaponX] File size: %@ bytes", fileSize);
            } else {
                NSLog(@"[WeaponX] ⚠️ Warning: Downloaded file size is zero or could not be determined");
            }
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(destinationPath, nil);
                });
            }
        } else {
            NSLog(@"[WeaponX] ❌ Error moving downloaded file: %@", moveError);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, moveError);
                });
            }
        }
    }];
    
    [downloadTask resume];
}

// Add NSURLSessionDelegate method to handle authentication challenges
#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    NSLog(@"[WeaponX] 🔒 Received authentication challenge: %@", challenge.protectionSpace.authenticationMethod);
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSLog(@"[WeaponX] 🔒 Handling server trust challenge for host: %@", challenge.protectionSpace.host);
        
        // Accept certificates for any weaponx.us domain or hydra domain
        if ([challenge.protectionSpace.host containsString:@"weaponx.us"] || 
            [challenge.protectionSpace.host containsString:@"hydra"]) {
            NSLog(@"[WeaponX] 🔒 Accepting certificate for trusted domain: %@", challenge.protectionSpace.host);
            NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
            return;
        }
    }
    
    // For any other challenges, use the default handling
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

#pragma mark - Secure Plan Data Methods

// Store plan data with a secure hash to prevent tampering
- (void)storePlanDataSecurely:(NSDictionary *)planData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // First, store the actual plan data
    [defaults setObject:planData forKey:@"WeaponXUserPlan"];
    
    // Create a secure hash of the plan data
    NSString *planHash = [self createSecureHashForPlanData:planData];
    
    // Store the hash separately
    [defaults setObject:planHash forKey:@"WeaponXUserPlanHash"];
    
    // Store the timestamp when this data was saved for offline grace period
    [defaults setObject:[NSDate date] forKey:@"WeaponXUserPlanTimestamp"];
    
    // Reset any re-verification flag since we just verified the plan
    [defaults setBool:NO forKey:@"WeaponXNeedsReVerification"];
    
    [defaults synchronize];
    
    NSLog(@"[WeaponX] 🔐 Stored plan data securely with hash and timestamp");
    
    // Check if the plan data indicates the user has an active plan
    BOOL hasActivePlan = NO;
    
    // Try to determine if the user has an active plan based on the response format
    if (planData[@"has_plan"]) {
        hasActivePlan = [planData[@"has_plan"] boolValue];
    } else if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *plan = planData[@"plan"];
        if (plan[@"id"]) {
            hasActivePlan = YES;
        }
    }
    
    NSLog(@"[WeaponX] 📋 Has active plan: %@", hasActivePlan ? @"YES" : @"NO");
    
    // Store the plan status for offline use
    [defaults setBool:hasActivePlan forKey:@"WeaponXHasActivePlan"];
    [defaults synchronize];
}

// Create a secure hash for plan data to prevent tampering
- (NSString *)createSecureHashForPlanData:(NSDictionary *)planData {
    // Convert plan data to JSON string
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:planData options:0 error:&error];
    if (!jsonData) {
        NSLog(@"[WeaponX] ❌ Error creating JSON from plan data: %@", error);
        return nil;
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    // Add a secret key that only the app knows
    NSString *secretKey = @"3kR8pLq2X7vY9cD6mA4hB1jF5sG0wN"; // Would be better if this was obfuscated
    NSString *dataToHash = [NSString stringWithFormat:@"%@_%@", jsonString, secretKey];
    
    // Create SHA256 hash
    NSData *dataBytes = [dataToHash dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(dataBytes.bytes, (CC_LONG)dataBytes.length, hash);
    
    // Convert to hex string
    NSMutableString *hashString = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hashString appendFormat:@"%02x", hash[i]];
    }
    
    return hashString;
}

// Verify the integrity of stored plan data and check offline access validity

// Get or create a device-specific salt for hashing
- (NSString *)getDeviceSpecificSalt {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *storedSalt = [defaults objectForKey:@"WeaponXDeviceSalt"];
    
    if (storedSalt) {
        return storedSalt;
    }
    
    // Create a new random salt
    NSMutableData *saltData = [NSMutableData dataWithLength:32]; // 32 bytes of random data
    int result = SecRandomCopyBytes(kSecRandomDefault, 32, saltData.mutableBytes);
    
    if (result != 0) {
        // Fallback if secure random generation fails
        NSLog(@"[WeaponX] ⚠️ Failed to generate secure random salt, using fallback");
        arc4random_buf(saltData.mutableBytes, 32);
    }
    
    // Convert to base64 string
    NSString *newSalt = [saltData base64EncodedStringWithOptions:0];
    
    // Store the salt
    [defaults setObject:newSalt forKey:@"WeaponXDeviceSalt"];
            [defaults synchronize];
            
    return newSalt;
}

// Method to refresh the user's plan from the server
- (void)refreshUserPlan {
    NSLog(@"[WeaponX] 🔄 Refreshing user plan data");
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXAuthToken"];
    if (token) {
        [self refreshPlanData:token];
    } else {
        NSLog(@"[WeaponX] ⚠️ Cannot refresh plan data - no auth token available");
    }
}

// Refresh plan data from the server with a specific token
- (void)refreshPlanData:(NSString *)token {
    // Use a lock to prevent multiple concurrent refreshes
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t refreshSemaphore;
    
    dispatch_once(&onceToken, ^{
        refreshSemaphore = dispatch_semaphore_create(1);
    });
    
    // Try to acquire the lock with a short timeout
    if (dispatch_semaphore_wait(refreshSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC))) != 0) {
        NSLog(@"[WeaponX] ⚠️ Plan refresh already in progress, skipping this request");
        return;
    }
    
    // Set the refresh flag
    _isRefreshingPlan = YES;
    
    NSLog(@"[WeaponX] 🔄 Refreshing plan data from server with token");
    
    // Check network availability first
    if (![self isNetworkAvailable]) {
        NSLog(@"[WeaponX] ⚠️ Cannot refresh plan data - network unavailable");
        _isRefreshingPlan = NO;
        dispatch_semaphore_signal(refreshSemaphore);
        
        // When offline, post notification to let the app know to use cached data
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"WeaponXPlanRefreshFailedOffline" 
                object:nil];
        });
        return;
    }
    
    if (!token) {
        NSLog(@"[WeaponX] ❌ Cannot refresh plan data - token is nil");
        _isRefreshingPlan = NO;
        dispatch_semaphore_signal(refreshSemaphore);
        return;
    }
    
    // Build URL
    NSString *planEndpoint = [NSString stringWithFormat:@"%@/api/v1/user/plan", self.baseURLString];
    NSURL *url = [NSURL URLWithString:planEndpoint];
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:10.0]; // Set a reasonable timeout
    
    NSLog(@"[WeaponX] 🌐 Sending plan data request to: %@", planEndpoint);
    
    // Create a data task with our custom session that handles SSL trust
    NSURLSessionDataTask *dataTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Always signal semaphore when finished to prevent deadlocks
        dispatch_block_t cleanup = ^{
            self->_isRefreshingPlan = NO;
            dispatch_semaphore_signal(refreshSemaphore);
        };
        
        // Handle errors
        if (error) {
            NSLog(@"[WeaponX] ❌ Plan data refresh failed with error: %@", error);
            
            // Specifically check for network connectivity errors
            BOOL isConnectivityError = NO;
            if ([error.domain isEqualToString:NSURLErrorDomain]) {
                if (error.code == NSURLErrorNotConnectedToInternet ||      // -1009
                    error.code == NSURLErrorNetworkConnectionLost ||       // -1005
                    error.code == NSURLErrorCannotConnectToHost ||         // -1004
                    error.code == NSURLErrorCannotFindHost ||              // -1003
                    error.code == NSURLErrorTimedOut) {                    // -1001
                    isConnectivityError = YES;
                }
            }
            
            // Check current plan status for fallback
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            BOOL currentPlanStatus = [defaults boolForKey:@"WeaponXHasActivePlan"];
            
            if (currentPlanStatus) {
                NSLog(@"[WeaponX] ⚠️ Network error but keeping existing active plan status for continuity");
                
                // If it's a connectivity error, also record the offline status
                if (isConnectivityError) {
                    [defaults setObject:[NSDate date] forKey:@"WeaponXLastOfflineDetection"];
                    [defaults synchronize];
                    
                    // Post offline notification
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] 
                            postNotificationName:@"WeaponXPlanRefreshFailedOffline" 
                            object:nil];
                    });
                }
    } else {
                // Set the flag to indicate there's no active plan (default behavior)
                [defaults setBool:NO forKey:@"WeaponXHasActivePlan"];
                [defaults synchronize];
            }
            
            cleanup();
            return;
        }
        
        // Get HTTP status code
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSInteger statusCode = httpResponse.statusCode;
        
        // Handle 401/403 errors (unauthorized or forbidden)
        if (statusCode == 401 || statusCode == 403) {
            NSLog(@"[WeaponX] 🚫 Unauthorized or forbidden response when checking plan (status code: %ld)", (long)statusCode);
            // Force a re-login
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] 
                    postNotificationName:@"WeaponXUserDidLogout" 
                    object:nil 
                    userInfo:@{@"force_login": @YES}];
            });
            
            cleanup();
            return;
        }
        
        // Handle 404 errors gracefully - user might not have an active plan
        if (statusCode == 404) {
            NSLog(@"[WeaponX] ⚠️ Received 404 from plan API, checking alternative plan sources");
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            
            // Check user data for plan information
            NSDictionary *userData = [defaults objectForKey:@"WeaponXUserData"];
            if (userData && [userData objectForKey:@"plan_expires_at"]) {
                NSString *expiryDateString = [userData objectForKey:@"plan_expires_at"];
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                NSDate *expiryDate = [formatter dateFromString:expiryDateString];
                
                // If we have a valid expiry date in the future, consider the plan active
                if (expiryDate && [expiryDate timeIntervalSinceNow] > 0) {
                    NSLog(@"[WeaponX] ✅ User has active plan based on expiry date: %@", expiryDateString);
                    
                    // Calculate days remaining
                    NSTimeInterval secondsRemaining = [expiryDate timeIntervalSinceNow];
                    NSInteger daysRemaining = (NSInteger)(secondsRemaining / 86400.0); // 86400 seconds in a day
                    
                    // Create a plan dictionary with the information we have
                    NSMutableDictionary *planDict = [NSMutableDictionary dictionary];
                    [planDict setObject:[userData objectForKey:@"plan_id"] ?: @1 forKey:@"id"];
                    [planDict setObject:expiryDateString forKey:@"expires_at"];
                    [planDict setObject:@(daysRemaining) forKey:@"days_remaining"];
                    
                    // Determine plan name
                    NSInteger planId = [[userData objectForKey:@"plan_id"] integerValue];
                    NSString *planName = @"ACTIVE";
                    if (planId == 1) {
                        planName = @"TRIAL";
                    } else if (planId > 1) {
                        planName = [NSString stringWithFormat:@"PLAN %ld", (long)planId];
                    }
                    
                    [planDict setObject:planName forKey:@"name"];
                    [planDict setObject:@"ACTIVE" forKey:@"status"];
                    
                    // Create the full plan data dictionary
                    NSDictionary *planData = @{
                        @"has_plan": @YES,
                        @"plan": planDict,
                        @"status": @"success"
                    };
                    
                    // Store the plan data
                    [self storePlanData:planData];
                    
                    // Mark the user as having an active plan
                    [defaults setBool:YES forKey:@"WeaponXHasActivePlan"];
                    [defaults setBool:YES forKey:@"WeaponXServerConfirmedActivePlan"];
                    [defaults synchronize];
                    
                    // Post notification about updated plan data
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXPlanDataUpdated" 
                                                                          object:nil 
                                                                        userInfo:@{@"has_plan": @YES}];
                    });
                    
                    cleanup();
                    return;
                }
            }
            
            // If we didn't find valid plan data in user data, use the regular 404 logic
            NSLog(@"[WeaponX] ℹ️ User has no active plan (404 response and no valid plan info in user data)");
            
            [defaults setBool:NO forKey:@"WeaponXHasActivePlan"];
            [defaults setBool:NO forKey:@"WeaponXServerConfirmedActivePlan"];
            [defaults synchronize];
            
            // Store fallback plan data indicating no plan
            [self storePlanData:@{@"plan": @{@"name": @"NO_PLAN"}}];
            
            // Post notification about updated plan data (no plan)
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXPlanDataUpdated" 
                                                                  object:nil 
                                                                userInfo:@{@"has_plan": @(NO)}];
            });
            
            cleanup();
            return;
        }
        
        // If no data, return error
        if (!data) {
            NSLog(@"[WeaponX] ❌ Plan data response was empty");
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            BOOL currentPlanStatus = [defaults boolForKey:@"WeaponXHasActivePlan"];
            
            if (currentPlanStatus) {
                NSLog(@"[WeaponX] ⚠️ Empty response but keeping existing active plan status for continuity");
                // Don't change the plan status
            } else {
                // Set the flag to indicate there's no active plan
                [defaults setBool:NO forKey:@"WeaponXHasActivePlan"];
            [defaults synchronize];
            }
            
            cleanup();
            return;
        }
        
        // Process data
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] ❌ Failed to parse plan data JSON: %@", jsonError);
            
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            BOOL currentPlanStatus = [defaults boolForKey:@"WeaponXHasActivePlan"];
            
            if (currentPlanStatus) {
                NSLog(@"[WeaponX] ⚠️ JSON error but keeping existing active plan status for continuity");
                // Don't change the plan status
            } else {
                // Set the flag to indicate there's no active plan
                [defaults setBool:NO forKey:@"WeaponXHasActivePlan"];
            [defaults synchronize];
        }
        
            cleanup();
            return;
        }
        
        // Store the plan data
        [self storePlanData:json];
        
        // Check if the plan is active
        BOOL hasPlan = NO;
        NSString *planName = @"None";
        NSString *planStatus = @"INACTIVE";
        
        if (json[@"plan"] && [json[@"plan"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *plan = json[@"plan"];
            
            // Extract expiration date if available
            NSString *expirationDateStr = nil;
            if (plan[@"expiration_date"]) {
                expirationDateStr = [plan[@"expiration_date"] description];
            }
            
            // Check if there's a valid expiration date in the future
            BOOL hasValidExpiration = NO;
            if (expirationDateStr.length > 0) {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"yyyy-MM-dd"];
                NSDate *expirationDate = [formatter dateFromString:expirationDateStr];
                
                if (expirationDate && [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
                    hasValidExpiration = YES;
                    NSLog(@"[WeaponX] ✅ Plan has valid expiration date in the future: %@", expirationDateStr);
                }
            }
            
            // First check plan name
            if (plan[@"name"]) {
                planName = [plan[@"name"] description];
                hasPlan = ![planName isEqualToString:@"NO_PLAN"];
            }
            
            // Then check status field if exists
            if (plan[@"status"]) {
                planStatus = [plan[@"status"] description];
                // If status explicitly says "ACTIVE", use that
                if ([planStatus isEqualToString:@"ACTIVE"]) {
                    hasPlan = YES;
                }
            }
            
            // If we have days remaining or valid expiration, consider the plan active
            // regardless of what the status field says
            if (hasValidExpiration || (plan[@"days_remaining"] && [plan[@"days_remaining"] integerValue] > 0)) {
                hasPlan = YES;
                NSLog(@"[WeaponX] ✅ Plan considered active because days remaining or valid expiration date");
                
                // Force the plan status to be consistent with days remaining
                if ([planStatus isEqualToString:@"INACTIVE"] && hasPlan) {
                    NSLog(@"[WeaponX] ⚠️ Correcting inconsistent plan status: marked as INACTIVE but has days remaining");
                    planStatus = @"ACTIVE";
                    
                    // Update the status in the stored plan data to ensure consistency
                    NSMutableDictionary *updatedPlan = [plan mutableCopy];
                    updatedPlan[@"status"] = planStatus;
                    
                    NSMutableDictionary *updatedJson = [json mutableCopy];
                    updatedJson[@"plan"] = updatedPlan;
                    
                    // Re-store with corrected status
                    [self storePlanData:updatedJson];
                }
            }
        }
        
        // Update the flag indicating whether the user has an active plan
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:hasPlan forKey:@"WeaponXHasActivePlan"];
        [defaults setBool:hasPlan forKey:@"WeaponXServerConfirmedActivePlan"];
        [defaults setObject:[NSDate date] forKey:@"WeaponXLastServerConfirmationDate"];
            [defaults synchronize];
        
        NSLog(@"[WeaponX] ✅ Plan data refreshed successfully - Plan: %@, Status: %@, Has Plan: %@", 
              planName, planStatus, hasPlan ? @"YES" : @"NO");
        
        // Post notification that plan data was updated
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXPlanDataUpdated" 
                                                                object:nil 
                                                              userInfo:@{@"has_plan": @(hasPlan)}];
        });
        
        cleanup();
    }];
    
    [dataTask resume];
}

// Verify the integrity of stored plan data and check offline access validity
- (BOOL)verifyPlanDataIntegrity {
    NSLog(@"[WeaponX] 🔍 Verifying plan data integrity");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Check for debug bypass flag (for testing only)
    if ([defaults boolForKey:@"WeaponXDebugBypassPlanCheck"]) {
        NSLog(@"[WeaponX] ⚠️ DEBUG MODE: Bypassing plan integrity check");
        return YES;
    }
    
    // If we have a server-confirmed active plan and it was confirmed recently (within 4 hours),
    // we can trust it without further verification
    if ([defaults boolForKey:@"WeaponXServerConfirmedActivePlan"]) {
        NSDate *lastConfirmation = [defaults objectForKey:@"WeaponXLastServerConfirmationDate"];
        if (lastConfirmation) {
            NSTimeInterval timeSinceConfirmation = [[NSDate date] timeIntervalSinceDate:lastConfirmation];
            // If confirmed within the last 4 hours, trust it
            if (timeSinceConfirmation < 4 * 60 * 60) {
                NSLog(@"[WeaponX] ✅ Using server-confirmed plan status (confirmed %0.1f hours ago)", 
                      timeSinceConfirmation / 3600.0);
                return YES;
            }
        }
    }
    
    // Get stored plan data and hash
    NSDictionary *storedPlanData = [defaults objectForKey:@"WeaponXUserPlan"];
    NSString *storedHash = [defaults objectForKey:@"WeaponXUserPlanHash"];
    
    // If we don't have stored plan data or hash, we need to refresh
    if (!storedPlanData || !storedHash) {
        NSLog(@"[WeaponX] ⚠️ Missing stored plan data or hash");
        
        // If we're online, try to refresh the plan data
        if ([self isNetworkAvailable]) {
            NSLog(@"[WeaponX] 🔄 Network available, triggering plan refresh");
            NSString *token = [defaults objectForKey:@"WeaponXAuthToken"];
            if (token) {
                [self refreshPlanData:token];
            }
            return NO;
        } else {
            // If offline and no stored data, we can't verify
            NSLog(@"[WeaponX] ❌ Offline with no stored plan data - cannot verify");
                return NO;
        }
    }
    
    // Generate hash for the stored plan data
    NSString *generatedHash = [self createSecureHashForPlanData:storedPlanData];
    
    // Compare the stored hash with the generated hash
    if ([storedHash isEqualToString:generatedHash]) {
        NSLog(@"[WeaponX] ✅ Plan data integrity verified - hash matches");
        
        // Check if the stored data suggests an active plan exists
        BOOL hasActivePlan = [defaults boolForKey:@"WeaponXHasActivePlan"];
        
        if (hasActivePlan) {
            NSLog(@"[WeaponX] ✅ User has an active plan according to verified data");
            return YES;
        } else {
            NSLog(@"[WeaponX] ℹ️ User does not have an active plan according to verified data");
                return NO;
        }
            } else {
        NSLog(@"[WeaponX] ⚠️ Plan data integrity check failed - hash mismatch");
        
        // If the stored data suggests an active plan exists, we'll allow temporary access
        // while triggering a refresh in the background
        BOOL storedActivePlan = [defaults boolForKey:@"WeaponXHasActivePlan"];
        
        if (storedActivePlan) {
            NSLog(@"[WeaponX] ⚠️ Hash mismatch but stored data indicates active plan - allowing temporary access");
            
            // If we're online, trigger a refresh
            if ([self isNetworkAvailable]) {
                NSLog(@"[WeaponX] 🔄 Network available, triggering plan refresh due to hash mismatch");
                NSString *token = [defaults objectForKey:@"WeaponXAuthToken"];
                if (token) {
                    [self refreshPlanData:token];
                }
            }
            
            // Allow access but flag for re-verification
            [defaults setBool:YES forKey:@"WeaponXNeedsReVerification"];
            [defaults synchronize];
            
                return YES;
        } else {
            NSLog(@"[WeaponX] ❌ Hash mismatch and no active plan indicated - denying access");
            return NO;
        }
    }
    
    // If we're offline, check the timestamp to see if we're still within the grace period
    if (![self isNetworkAvailable]) {
        NSDate *lastVerification = [defaults objectForKey:@"WeaponXUserPlanTimestamp"];
        if (lastVerification) {
            NSTimeInterval timeSinceVerification = [[NSDate date] timeIntervalSinceDate:lastVerification];
            
            // Allow a grace period of 24 hours for offline access
            if (timeSinceVerification < 24 * 60 * 60) {
                NSLog(@"[WeaponX] ✅ Offline access granted - within 24 hour grace period (%0.1f hours)", 
                      timeSinceVerification / 3600.0);
                return YES;
            } else {
                NSLog(@"[WeaponX] ❌ Offline access denied - exceeded 24 hour grace period (%0.1f hours)", 
                      timeSinceVerification / 3600.0);
                
                // Show an alert to the user
                [self showOfflineGraceExpiredAlert];
                
                return NO;
            }
        } else {
            NSLog(@"[WeaponX] ❌ Offline access denied - no verification timestamp");
            return NO;
        }
    }
    
    // Default fallback - should not reach here
    NSLog(@"[WeaponX] ❌ Plan verification failed - reached end of method without decision");
    return NO;
}

// Reset plan data hash when needed (e.g., after detecting tampering)
- (void)resetPlanDataHash {
    NSLog(@"[WeaponX] 🔄 Resetting plan data hash");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Get the current stored plan data
    NSDictionary *storedPlanData = [defaults objectForKey:@"WeaponXUserPlan"];
    
    // If we have valid plan data, regenerate the hash
    if (storedPlanData && [storedPlanData isKindOfClass:[NSDictionary class]]) {
        // Create a new hash for the data
        NSString *newHash = [self createSecureHashForPlanData:storedPlanData];
        
        if (newHash) {
            // Store the new hash
            [defaults setObject:newHash forKey:@"WeaponXUserPlanHash"];
            [defaults setObject:[NSDate date] forKey:@"WeaponXUserPlanTimestamp"];
            [defaults synchronize];
            
            NSLog(@"[WeaponX] ✅ Plan data hash reset successfully");
        } else {
            NSLog(@"[WeaponX] ❌ Failed to create new hash for plan data");
        }
    } else {
        NSLog(@"[WeaponX] ⚠️ No valid plan data found to reset hash");
        
        // Clear any existing hash since we don't have valid data
        [defaults removeObjectForKey:@"WeaponXUserPlanHash"];
        [defaults synchronize];
    }
}

// Show an alert when offline grace period has expired
- (void)showOfflineGraceExpiredAlert {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController 
                                   alertControllerWithTitle:@"Offline Access Expired"
                                   message:@"You've been offline for more than 24 hours. Please connect to the internet to verify your subscription."
                                   preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction 
                                  actionWithTitle:@"OK" 
                                  style:UIAlertActionStyleDefault
                                  handler:nil];
        
        [alert addAction:okAction];
        
        // Find the top-most view controller to present the alert using the scene-aware approach
        UIViewController *topController = nil;
        
        // Get key window in a way that works for iOS 13+ with multiple scenes
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *window in scene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                    if (keyWindow) break;
                    
                    // If no key window found, use the first window in the active scene
                    if (scene.windows.count > 0) {
                        keyWindow = scene.windows.firstObject;
                    }
                }
            }
            } else {
            // Fallback for older iOS versions - use a pragma to suppress the deprecation warning
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            keyWindow = [UIApplication sharedApplication].keyWindow;
            #pragma clang diagnostic pop
        }
        
        if (keyWindow) {
            topController = keyWindow.rootViewController;
            while (topController.presentedViewController) {
                topController = topController.presentedViewController;
            }
        }
        
        if (topController) {
            [topController presentViewController:alert animated:YES completion:nil];
        }
    });
}

#pragma mark - Support Ticket APIs

- (void)getTicketCategories:(void (^)(NSArray *categories, NSError *error))completion {
    [self authorizedRequestWithMethod:@"GET" path:@"/api/support/categories" parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSArray *categories = responseObject[@"categories"];
        if (completion) {
            completion(categories, nil);
        }
    }];
}

- (void)getUserTickets:(void (^)(NSArray *tickets, NSError *error))completion {
    [self authorizedRequestWithMethod:@"GET" path:@"/api/support/tickets" parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSArray *tickets = responseObject[@"tickets"];
        if (completion) {
            completion(tickets, nil);
        }
    }];
}

- (void)getTicketDetails:(NSNumber *)ticketId completion:(void (^)(NSDictionary *ticket, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/support/tickets/%@", ticketId];
    [self authorizedRequestWithMethod:@"GET" path:path parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSDictionary *ticket = responseObject[@"ticket"];
        if (completion) {
            completion(ticket, nil);
        }
    }];
}

- (void)createTicket:(NSString *)subject content:(NSString *)content categoryId:(NSNumber *)categoryId priority:(NSString *)priority attachments:(NSArray<UIImage *> *)attachments completion:(void (^)(BOOL success, NSString *message, NSNumber *ticketId, NSError *error))completion {
    NSString *boundary = [self generateBoundaryString];
    
    // Create the request
    NSMutableURLRequest *request = [self authorizedURLRequestWithMethod:@"POST" path:@"/api/support/tickets"];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    
    // Create body data
    NSMutableData *body = [NSMutableData data];
    
    // Add text fields
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"subject\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", subject ?: @""] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"content\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", content ?: @""] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"priority\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", priority ?: @"medium"] dataUsingEncoding:NSUTF8StringEncoding]];
    
    if (categoryId) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Disposition: form-data; name=\"category_id\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@\r\n", categoryId] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    // Add images
    if (attachments && attachments.count > 0) {
        NSInteger maxAttachments = MIN(attachments.count, 3); // Max 3 attachments
        for (NSInteger i = 0; i < maxAttachments; i++) {
            UIImage *image = attachments[i];
            NSData *imageData = UIImageJPEGRepresentation(image, 0.8); // Compress to reduce file size
            
            if (imageData) {
                [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"attachments[%ld]\"; filename=\"image%ld.jpg\"\r\n", (long)i, (long)i] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[@"Content-Type: image/jpeg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:imageData];
                [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            }
        }
    }
    
    // End the request body
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Set the request body
    [request setHTTPBody:body];
    
    // Send the request
    [self sendRequest:request completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, @"Error creating ticket", nil, error);
            }
            return;
        }
        
        
        BOOL success = [responseObject[@"success"] boolValue];
        NSString *message = responseObject[@"message"] ?: @"Ticket created successfully";
        NSNumber *ticketId = responseObject[@"ticket_id"];
        
        if (completion) {
            completion(success, message, ticketId, nil);
        }
    }];
}

- (void)replyToTicket:(NSNumber *)ticketId content:(NSString *)content attachment:(UIImage *)attachment completion:(void (^)(BOOL success, NSString *message, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/support/tickets/%@/reply", ticketId];
    NSString *boundary = [self generateBoundaryString];
    
    // Create the request
    NSMutableURLRequest *request = [self authorizedURLRequestWithMethod:@"POST" path:path];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    
    // Create body data
    NSMutableData *body = [NSMutableData data];
    
    // Add content field
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"content\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", content ?: @""] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Add image if provided
    if (attachment) {
        NSData *imageData = UIImageJPEGRepresentation(attachment, 0.8); // Compress to reduce file size
        
        if (imageData) {
            [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
            [body appendData:[@"Content-Disposition: form-data; name=\"attachment\"; filename=\"reply_image.jpg\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            [body appendData:[@"Content-Type: image/jpeg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            [body appendData:imageData];
            [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    // End the request body
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Set the request body
    [request setHTTPBody:body];
    
    // Send the request
    [self sendRequest:request completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, @"Error replying to ticket", error);
            }
            return;
        }
        
        BOOL success = [responseObject[@"success"] boolValue];
        NSString *message = responseObject[@"message"] ?: @"Reply added successfully";
        
        if (completion) {
            completion(success, message, nil);
        }
    }];
}

- (void)reopenTicket:(NSNumber *)ticketId completion:(void (^)(BOOL success, NSString *message, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/support/tickets/%@/reopen", ticketId];
    
    [self authorizedRequestWithMethod:@"POST" path:path parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, @"Error reopening ticket", error);
            }
            return;
        }
        
        BOOL success = [responseObject[@"success"] boolValue];
        NSString *message = responseObject[@"message"] ?: @"Ticket reopened successfully";
        
        if (completion) {
            completion(success, message, nil);
        }
    }];
}

// Helper method to generate a boundary string for multipart form data
- (NSString *)generateBoundaryString {
    return [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
}

// Method to create an authorized URL request (for multipart form data)
- (NSMutableURLRequest *)authorizedURLRequestWithMethod:(NSString *)method path:(NSString *)path {
    NSURL *url = [self urlForPath:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:method];
    
    // Add auth token if available
    NSString *token = [TokenManager sharedInstance].getCurrentToken;
    if (token) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    
    return request;
}

- (void)createTicket:(NSString *)subject content:(NSString *)content categoryId:(NSNumber *)categoryId priority:(NSString *)priority completion:(void (^)(BOOL success, NSString *message, NSNumber *ticketId, NSError *error))completion {
    // Call the implementation with attachments, passing nil for attachments
    [self createTicket:subject content:content categoryId:categoryId priority:priority attachments:nil completion:completion];
}

- (void)replyToTicket:(NSNumber *)ticketId content:(NSString *)content completion:(void (^)(BOOL success, NSString *message, NSError *error))completion {
    // Call the implementation with attachment, passing nil for attachment
    [self replyToTicket:ticketId content:content attachment:nil completion:completion];
}

- (void)closeTicket:(NSNumber *)ticketId completion:(void (^)(BOOL success, NSString *message, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/support/tickets/%@/close", ticketId];
    
    [self authorizedRequestWithMethod:@"POST" path:path parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, @"Error closing ticket", error);
            }
            return;
        }
        
        BOOL success = [responseObject[@"success"] boolValue];
        NSString *message = responseObject[@"message"] ?: @"Ticket closed successfully";
        
        if (completion) {
            completion(success, message, nil);
        }
    }];
}

#pragma mark - Broadcast APIs

- (void)getBroadcasts:(void (^)(NSArray *broadcasts, NSInteger unreadCount, NSError *error))completion {
    [self authorizedRequestWithMethod:@"GET" path:@"/api/broadcasts" parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, 0, error);
            }
            return;
        }
        
        NSArray *broadcasts = responseObject[@"broadcasts"] ?: @[];
        NSInteger unreadCount = [responseObject[@"unread_count"] integerValue];
        
        if (completion) {
            completion(broadcasts, unreadCount, nil);
        }
    }];
}

#pragma mark - Missing Method Implementations

- (void)registerDeviceToken:(NSString *)token deviceType:(NSString *)deviceType completion:(void (^)(BOOL success, NSError *error))completion {
    if (!token || token.length == 0) {
        NSError *error = [NSError errorWithDomain:@"APIManager" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Device token is empty"}];
    if (completion) {
            completion(NO, error);
        }
        return;
    }
    
    // Get the auth token
    NSString *authToken = [self getAuthToken];
    if (!authToken) {
        NSError *error = [NSError errorWithDomain:@"APIManager" code:401 userInfo:@{NSLocalizedDescriptionKey: @"User not authenticated"}];
        NSLog(@"[WeaponX] ❌ ERROR: Cannot register device token - user not authenticated");
        if (completion) {
            completion(NO, error);
        }
        return;
    }
    
    // Create URL for API endpoint
    NSString *path = @"/api/devices/register-token";
    NSURL *url = [self urlForPath:path];
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", authToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Add device identification
    NSString *deviceId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (deviceId) {
        [request setValue:deviceId forHTTPHeaderField:@"X-Device-ID"];
        NSLog(@"[WeaponX] 📱 Added device ID to push token registration: %@", deviceId);
    }
    
    // Create the request body
    NSDictionary *params = @{
        @"token": token,
        @"device_type": deviceType ?: @"ios"
    };
    
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonError];
    
    if (jsonError) {
        NSLog(@"[WeaponX] ❌ Error creating device token JSON: %@", jsonError);
        if (completion) {
            completion(NO, jsonError);
        }
        return;
    }
    
    [request setHTTPBody:jsonData];
    
    NSLog(@"[WeaponX] 📲 Registering push token: %@", token);
    NSLog(@"[WeaponX] 🔗 URL: %@", url.absoluteString);
    
    // Send the request
    [self sendRequest:request completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Error registering device token: %@", error);
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        
        BOOL success = [responseObject[@"success"] boolValue];
        NSLog(@"[WeaponX] ✅ Device token registration %@", success ? @"successful" : @"failed");
        
        if (completion) {
            completion(success, nil);
        }
    }];
}

- (void)getBroadcastDetails:(NSNumber *)broadcastId completion:(void (^)(NSDictionary *broadcast, NSError *error))completion {
    if (!broadcastId) {
    if (completion) {
            NSError *error = [NSError errorWithDomain:@"APIManager" code:400 userInfo:@{
                NSLocalizedDescriptionKey: @"Broadcast ID is required"
            }];
            completion(nil, error);
        }
        return;
    }
    
    NSString *path = [NSString stringWithFormat:@"/api/broadcasts/%@", broadcastId];
    
    [self authorizedRequestWithMethod:@"GET" path:path parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSDictionary *broadcast = responseObject[@"broadcast"];
        
        if (!broadcast) {
            NSError *parsingError = [NSError errorWithDomain:@"APIManager" code:500 userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to parse broadcast details from response"
            }];
            if (completion) {
                completion(nil, parsingError);
            }
            return;
        }
        
        if (completion) {
            completion(broadcast, nil);
        }
    }];
}

- (void)markBroadcastAsRead:(NSNumber *)broadcastId completion:(void (^)(BOOL success, NSError *error))completion {
    if (!broadcastId) {
    if (completion) {
            NSError *error = [NSError errorWithDomain:@"APIManager" code:400 userInfo:@{
                NSLocalizedDescriptionKey: @"Broadcast ID is required"
            }];
            completion(NO, error);
        }
        return;
    }
    
    NSString *path = [NSString stringWithFormat:@"/api/broadcasts/%@/read", broadcastId];
    
    [self authorizedRequestWithMethod:@"POST" path:path parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        
        if (completion) {
            completion(YES, nil);
        }
    }];
}

- (void)getNotificationCount:(void (^)(NSInteger unreadBroadcasts, NSInteger unreadTicketReplies, NSInteger totalCount, NSError *error))completion {
    // Get the auth token
    NSString *token = [self getAuthToken];
    if (!token) {
        NSError *error = [NSError errorWithDomain:@"APIManager" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Authentication token is missing"}];
        NSLog(@"[WeaponX] ❌ ERROR: Authentication token is missing for getNotificationCount");
    if (completion) {
            completion(0, 0, 0, error);
        }
        return;
    }
    
    // Create URL for API endpoint
    NSString *path = @"/api/notifications/count";
    NSURL *url = [self urlForPath:path];
    
    NSLog(@"[WeaponX] 🔔 Fetching notification counts from URL: %@", url.absoluteString);
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Send the request
    [self sendRequest:request completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Error fetching notification counts: %@", error);
            if (completion) {
                completion(0, 0, 0, error);
            }
            return;
        }
        
        // Extract the notification counts from the response
        NSInteger unreadBroadcasts = [responseObject[@"unread_broadcasts"] integerValue];
        NSInteger unreadTicketReplies = [responseObject[@"unread_ticket_replies"] integerValue];
        NSInteger totalCount = [responseObject[@"total_count"] integerValue];
        
        NSLog(@"[WeaponX] 🔔 Notification counts - Broadcasts: %ld, Tickets: %ld, Total: %ld",
              (long)unreadBroadcasts, (long)unreadTicketReplies, (long)totalCount);
        
        if (completion) {
            completion(unreadBroadcasts, unreadTicketReplies, totalCount, nil);
        }
    }];
}

- (void)authorizedRequestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters completion:(void (^)(NSDictionary *responseObject, NSError *error))completion {
    // Create a URL from the base URL and path
    NSURL *url = [self urlForPath:path];
    
    // Create a request with the URL
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:method];
    
    // Add authorization token if available
    NSString *token = [TokenManager sharedInstance].getCurrentToken;
    if (token) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    
    // Add parameters to the request if necessary
    if (parameters && [method isEqualToString:@"POST"]) {
        // For POST requests, serialize the parameters as JSON in the body
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] ❌ Error serializing parameters to JSON: %@", jsonError);
            if (completion) {
                completion(nil, jsonError);
            }
            return;
        }
        
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:jsonData];
    } else if (parameters && [method isEqualToString:@"GET"]) {
        // For GET requests, add parameters to the URL as query parameters
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSMutableArray *queryItems = [NSMutableArray array];
        
        for (NSString *key in parameters) {
            [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:[parameters[key] description]]];
        }
        
        components.queryItems = queryItems;
        request.URL = components.URL;
    }
    
    // Send the request
    [self sendRequest:request completion:completion];
}

// Method to send a request and process the response
- (void)sendRequest:(NSURLRequest *)request completion:(void (^)(NSDictionary *responseObject, NSError *error))completion {
    NSLog(@"[WeaponX] 🚀 Sending request to: %@", request.URL);
    
    // Create a session task to send the request
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Check for network errors
        if (error) {
            NSLog(@"[WeaponX] ❌ Network error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, error);
                }
            });
            return;
        }
        
        // Check the response
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] 📊 Response status code: %ld", (long)httpResponse.statusCode);
        
        // Process the response data
        NSDictionary *responseObject = nil;
        NSError *jsonError = nil;
        
        if (data) {
            responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Error parsing JSON response: %@", jsonError);
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[WeaponX] 📝 Raw response: %@", responseString);
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(nil, jsonError);
                    }
                });
                return;
            }
        }
        
        // Check for server error status codes
        if (httpResponse.statusCode >= 400) {
            NSLog(@"[WeaponX] ⚠️ Server returned error status: %ld, response: %@", (long)httpResponse.statusCode, responseObject);
            
            // Check for unauthorized response
            if (httpResponse.statusCode == 401) {
                [self handleUnauthorizedResponse:httpResponse completion:^(BOOL tokenReset, NSString *newToken) {
                    if (tokenReset && newToken) {
                        // Retry the request with the new token
                        NSMutableURLRequest *newRequest = [request mutableCopy];
                        [newRequest setValue:[NSString stringWithFormat:@"Bearer %@", newToken] forHTTPHeaderField:@"Authorization"];
                        [self sendRequest:newRequest completion:completion];
                    } else {
                        // Token reset failed, return the original error
                        NSError *authError = [NSError errorWithDomain:@"APIManager" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Unauthorized"}];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (completion) {
                                completion(responseObject, authError);
                            }
                        });
                    }
                }];
                return;
            }
            
            // For other error status codes, create an error object
            NSString *errorMessage = responseObject[@"message"] ?: [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode];
            NSError *serverError = [NSError errorWithDomain:@"APIManager" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(responseObject, serverError);
                }
            });
            return;
        }
        
        // Return the response object on success
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(responseObject, nil);
            }
        });
    }];
    
    [task resume];
}

- (NSURL *)urlForPath:(NSString *)path {
    // Make sure we have a base URL
    if (!self.baseURLString || [self.baseURLString length] == 0) {
        NSLog(@"[WeaponX] ⚠️ No base URL set for API request");
        return nil;
    }
    
    // Ensure the path starts with a slash
    NSString *formattedPath = path;
    if (![path hasPrefix:@"/"]) {
        formattedPath = [NSString stringWithFormat:@"/%@", path];
    }
    
    // Create the full URL string
    NSString *fullURLString = [NSString stringWithFormat:@"%@%@", self.baseURLString, formattedPath];
    
    // Create and return the URL
    NSURL *url = [NSURL URLWithString:fullURLString];
    
    NSLog(@"[WeaponX] 🌐 Created URL: %@", url);
    return url;
}

#pragma mark - Version Ban Methods

- (BOOL)isCurrentVersionBanned {
    // Get current app version (not build number)
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *minAllowedVersion = [defaults objectForKey:@"WeaponXMinimumAllowedVersion"];
    
    if (minAllowedVersion && minAllowedVersion.length > 0) {
        // Compare versions using NSComparisonResult
        NSComparisonResult result = [currentVersion compare:minAllowedVersion options:NSNumericSearch];
        
        // If current version is less than minimum allowed version
        if (result == NSOrderedAscending) {
            NSLog(@"[WeaponX] ⛔️ Current version %@ is banned (minimum allowed: %@)", currentVersion, minAllowedVersion);
            return YES;
        }
    }
    
    return NO;
}

- (void)showVersionBannedAlert:(UIViewController *)viewController completion:(void (^)(void))completion {
    // Create alert message
    NSString *message = @"SERVER IS DOWN FOR THIS APP VERSION\nDOWNLOAD LATEST VERSION";
    
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"Update Required" 
        message:message 
        preferredStyle:UIAlertControllerStyleAlert];
        
    // Add download button
    [alert addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self openSileoForUpdate:@"com.hydra.projectx"];
        if (completion) completion();
    }]];
    
    // Find root view controller to present alert (iOS 13+ compatible)
    UIViewController *rootVC = viewController;
    if (!rootVC) {
        if (@available(iOS 13.0, *)) {
            NSSet<UIScene *> *scenes = [[UIApplication sharedApplication] connectedScenes];
            for (UIScene *scene in scenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *window in windowScene.windows) {
                        if (window.isKeyWindow) {
                            rootVC = window.rootViewController;
                            break;
                        }
                    }
                }
                if (rootVC) break;
            }
        }
    }
    
    if (rootVC) {
        [rootVC presentViewController:alert animated:YES completion:nil];
    }
}

- (void)checkVersionBanWithCompletion:(void (^)(BOOL isBanned, NSError *error))completion {
    // Get current app version
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    // Prepare API path
    NSString *path = @"api/v1/app/version-check";
    NSDictionary *parameters = @{
        @"version": currentVersion,
        @"platform": @"ios"
    };
    
    // Make the API request
    [self authorizedRequestWithMethod:@"GET" path:path parameters:parameters completion:^(id responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        
        // Check if version is banned
        BOOL isBanned = NO;
        
        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            NSDictionary *response = (NSDictionary *)responseObject;
            
            // Check for minimum allowed version
            if (response[@"min_allowed_version"]) {
                NSString *minAllowedVersion = response[@"min_allowed_version"];
                NSLog(@"[WeaponX] Server returned minimum allowed version: %@", minAllowedVersion);
                
                // Store the minimum allowed version
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:minAllowedVersion forKey:@"WeaponXMinimumAllowedVersion"];
                [defaults synchronize];
                
                // Compare with current version
                NSComparisonResult result = [currentVersion compare:minAllowedVersion options:NSNumericSearch];
                if (result == NSOrderedAscending) {
                    isBanned = YES;
                }
            }
            
            // Check for direct ban flag
            if (response[@"is_banned"] && [response[@"is_banned"] boolValue]) {
                isBanned = YES;
            }
        }
        
        if (completion) {
            completion(isBanned, nil);
        }
    }];
}

#pragma mark - App Store and Sileo Helpers

- (void)openSileoForUpdate:(NSString *)packageID {
    NSString *sileoURL = [NSString stringWithFormat:@"sileo://package/%@", packageID ?: @"com.hydra.projectx"];
    
    NSURL *url = [NSURL URLWithString:sileoURL];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        // Use modern API for iOS 10+
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        NSLog(@"[WeaponX] Opened Sileo URL: %@", sileoURL);
    } else {
        NSLog(@"[WeaponX] Cannot open Sileo URL: %@", sileoURL);
        // Fallback to Safari if Sileo isn't installed
        NSString *safariURL = @"https://hydra.weaponx.us/repo/";
        // Use modern API for iOS 10+
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:safariURL] options:@{} completionHandler:nil];
    }
}

- (void)getSubcategoriesForCategory:(NSNumber *)categoryId completion:(void (^)(NSArray *subcategories, NSError *error))completion {
    NSString *path = [NSString stringWithFormat:@"/api/support/categories/%@/subcategories", categoryId];
    
    [self authorizedRequestWithMethod:@"GET" path:path parameters:nil completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        NSArray *subcategories = responseObject[@"subcategories"];
        if (completion) {
            completion(subcategories, nil);
        }
    }];
}

- (void)createTicketWithSubcategory:(NSString *)subject 
                            content:(NSString *)content 
                         categoryId:(NSNumber *)categoryId 
                      subcategoryId:(NSNumber *)subcategoryId 
                          priority:(NSString *)priority 
                       attachments:(NSArray<UIImage *> *)attachments 
                        completion:(void (^)(BOOL success, NSString *message, NSNumber *ticketId, NSError *error))completion {
    
    NSString *boundary = [self generateBoundaryString];
    
    // Create the request
    NSMutableURLRequest *request = [self authorizedURLRequestWithMethod:@"POST" path:@"/api/support/tickets"];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    
    // Create body data
    NSMutableData *body = [NSMutableData data];
    
    // Add text fields
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"subject\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", subject ?: @""] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"content\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", content ?: @""] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"category_id\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", categoryId ?: @""] dataUsingEncoding:NSUTF8StringEncoding]];
    
    if (subcategoryId) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[@"Content-Disposition: form-data; name=\"subcategory_id\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@\r\n", subcategoryId] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"priority\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"%@\r\n", priority ?: @"medium"] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Add images if provided
    if (attachments && attachments.count > 0) {
        for (int i = 0; i < attachments.count; i++) {
            UIImage *image = attachments[i];
            NSData *imageData = UIImageJPEGRepresentation(image, 0.8); // Compress to reduce file size
            
            if (imageData) {
                [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"attachments[%d]\"; filename=\"image%d.jpg\"\r\n", i, i] dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:[@"Content-Type: image/jpeg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
                [body appendData:imageData];
                [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            }
        }
    }
    
    // End the request body
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Set the request body
    [request setHTTPBody:body];
    
    // Send the request
    [self sendRequest:request completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            if (completion) {
                completion(NO, @"Error creating ticket", nil, error);
            }
            return;
        }
        
        BOOL success = [responseObject[@"success"] boolValue];
        NSString *message = responseObject[@"message"] ?: @"Ticket created successfully";
        NSNumber *ticketId = responseObject[@"ticket_id"];
        
        if (completion) {            completion(success, message, ticketId, nil);
        }
    }];
}

- (NSString *)getAuthToken {
    if (self.authToken) {
        return self.authToken;
    }
    
    // If not available in memory, try to get from user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Fix: Use the correct key for the auth token
    NSString *savedToken = [defaults objectForKey:@"WeaponXAuthToken"];
    
    // Cache it for future use
    if (savedToken) {
        self.authToken = savedToken;
    }
    
    return savedToken;
}

#pragma mark - Device Management

- (void)getUserDevices:(void (^)(NSArray *devices, NSInteger deviceLimit, NSError *error))completion {
    // Get the auth token from the instance variable
    NSString *token = [self getAuthToken];
    if (!token) {
        NSError *error = [NSError errorWithDomain:@"com.weaponx.api" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Authentication token is missing"}];
        NSLog(@"[WeaponX] ❌ ERROR: Authentication token is missing for getUserDevices");
        completion(nil, 0, error);
        return;
    }
    
    // Create URL for API endpoint
    NSString *path = @"/api/devices";
    NSURL *url = [self urlForPath:path];
    
    NSLog(@"[WeaponX] 🔍 Fetching devices from URL: %@", url.absoluteString);
    NSLog(@"[WeaponX] 🔑 Using auth token: %@...%@", 
          [token length] > 10 ? [token substringToIndex:5] : token,
          [token length] > 10 ? [token substringFromIndex:[token length] - 5] : @"");
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    // Add device identification
    NSString *deviceId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (deviceId) {
        [request setValue:deviceId forHTTPHeaderField:@"X-Device-ID"];
        NSLog(@"[WeaponX] 📱 Added device ID to header: %@", deviceId);
    }
    
    NSLog(@"[WeaponX] 📡 Getting user devices from: %@", url.absoluteString);
    NSLog(@"[WeaponX] 📋 Request headers: %@", [request allHTTPHeaderFields]);
    
    // Send the request
    [self sendRequest:request completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Error getting devices: %@", error);
            completion(nil, 0, error);
            return;
        }
        
        NSLog(@"[WeaponX] 📥 Device API response: %@", responseObject);
        
        // Extract devices array with better error handling
        NSArray *devices = nil;
        
        // Try different paths in the response object to find devices array
        if (responseObject[@"data"] && [responseObject[@"data"] isKindOfClass:[NSDictionary class]]) {
            // Standard API response format
            if (responseObject[@"data"][@"devices"] && [responseObject[@"data"][@"devices"] isKindOfClass:[NSArray class]]) {
                devices = responseObject[@"data"][@"devices"];
            }
        } 
        
        // Fallback to direct devices key if data.devices not found
        if (!devices && responseObject[@"devices"] && [responseObject[@"devices"] isKindOfClass:[NSArray class]]) {
            devices = responseObject[@"devices"];
        }
        
        // If still no devices found, create an empty array
        if (!devices) {
            devices = @[];
            NSLog(@"[WeaponX] ⚠️ No devices found in API response");
        }
        
        // Process devices to normalize data format
        NSMutableArray *processedDevices = [NSMutableArray arrayWithCapacity:devices.count];
        for (NSDictionary *device in devices) {
            // Create a mutable copy to add/modify fields
            NSMutableDictionary *normalizedDevice = [NSMutableDictionary dictionaryWithDictionary:device];
            
            // Ensure we have an is_active field based on status
            if (device[@"status"] && ![device[@"status"] isKindOfClass:[NSNull class]]) {
                NSString *status = device[@"status"];
                BOOL isActive = [status isEqualToString:@"online"] || [status isEqualToString:@"active"];
                normalizedDevice[@"is_active"] = @(isActive);
            }
            
            // Ensure last_seen and last_seen_at are consistent
            if (device[@"last_seen_at"] && ![device[@"last_seen_at"] isKindOfClass:[NSNull class]]) {
                normalizedDevice[@"last_seen"] = device[@"last_seen_at"];
            } else if (device[@"last_active_at"] && ![device[@"last_active_at"] isKindOfClass:[NSNull class]]) {
                normalizedDevice[@"last_seen"] = device[@"last_active_at"];
                normalizedDevice[@"last_seen_at"] = device[@"last_active_at"];
            } else if (device[@"last_seen"] && ![device[@"last_seen"] isKindOfClass:[NSNull class]]) {
                normalizedDevice[@"last_seen_at"] = device[@"last_seen"];
            }
            
            [processedDevices addObject:normalizedDevice];
        }
        
        // Get device limit from response or use default
        NSInteger deviceLimit = 1; // Default to 1
        
        if (responseObject[@"device_limit"] && ![responseObject[@"device_limit"] isKindOfClass:[NSNull class]]) {
            deviceLimit = [responseObject[@"device_limit"] integerValue];
        } else if (responseObject[@"data"] && responseObject[@"data"][@"device_limit"]) {
            deviceLimit = [responseObject[@"data"][@"device_limit"] integerValue];
        } else if (responseObject[@"plan"] && responseObject[@"plan"][@"max_devices"]) {
            deviceLimit = [responseObject[@"plan"][@"max_devices"] integerValue];
        }
        
        NSLog(@"[WeaponX] ✅ Successfully got devices: %lu, limit: %ld", (unsigned long)processedDevices.count, (long)deviceLimit);
        
        completion(processedDevices, deviceLimit, nil);
    }];
}

- (void)removeUserDevice:(NSString *)deviceUUID completion:(void (^)(BOOL success, NSError *error))completion {
    // Get the auth token from the instance variable
    NSString *token = [self getAuthToken];
    if (!token || !deviceUUID) {
        NSError *error = [NSError errorWithDomain:@"com.weaponx.api" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Authentication token or device UUID is missing"}];
        completion(NO, error);
        return;
    }
    
    // Create URL for API endpoint - use the correct endpoint that matches the server
    NSString *path = [NSString stringWithFormat:@"/api/devices/%@/revoke", deviceUUID];
    NSURL *url = [self urlForPath:path];
    
    // Create request - use POST instead of DELETE to match server routes
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    // Add force_remove=true parameter to ensure the device is removed even if linked to multiple accounts
    NSString *jsonBodyString = @"{\"force_remove\": true}";
    NSData *jsonData = [jsonBodyString dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:jsonData];
    
    NSLog(@"[WeaponX] Removing device with UUID: %@", deviceUUID);
    NSLog(@"[WeaponX] Request URL: %@", url.absoluteString);
    NSLog(@"[WeaponX] Request method: %@", [request HTTPMethod]);
    NSLog(@"[WeaponX] Request body: %@", jsonBodyString);
    
    // Send the request
    [self sendRequest:request completion:^(NSDictionary *responseObject, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] Error removing device: %@", error);
            completion(NO, error);
            return;
        }
        
        // Check if we got a success or error response from the API
        BOOL success = NO;
        
        if (responseObject && [responseObject isKindOfClass:[NSDictionary class]]) {
            // Check if the response has a status field indicating success
            if ([responseObject[@"status"] isEqualToString:@"success"]) {
                success = YES;
            } else if (responseObject[@"message"]) {
                // If there's an error message in the response, use it
                NSString *errorMessage = responseObject[@"message"];
                NSLog(@"[WeaponX] API Error: %@", errorMessage);
                error = [NSError errorWithDomain:@"com.weaponx.api" code:400 userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            }
        }
        
        NSLog(@"[WeaponX] Response from server: %@", responseObject);
        
        if (success) {
        NSLog(@"[WeaponX] Successfully removed device with UUID: %@", deviceUUID);
        completion(YES, nil);
        } else {
            // If we got here but success is still NO, create a generic error
            if (!error) {
                error = [NSError errorWithDomain:@"com.weaponx.api" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Failed to remove device for unknown reasons"}];
            }
            completion(NO, error);
        }
    }];
}

#pragma mark - Network Reachability

- (BOOL)isNetworkAvailable {
    // Use SCNetworkReachability to check network status
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "hydra.weaponx.us");
    SCNetworkReachabilityFlags flags;
    BOOL isReachable = NO;
    
    if (SCNetworkReachabilityGetFlags(reachability, &flags)) {
        isReachable = 
            (flags & kSCNetworkReachabilityFlagsReachable) && 
            !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
        
        // For cellular connections, check if intervention is required
        if ((flags & kSCNetworkReachabilityFlagsIsWWAN)) {
            isReachable = isReachable && 
                !(flags & kSCNetworkReachabilityFlagsInterventionRequired);
        }
    }
    
    if (reachability) {
        CFRelease(reachability);
    }
    
    // Store the current network status
    static BOOL lastNetworkStatus = NO;
    
    // Only post notification if status changed
    if (lastNetworkStatus != isReachable) {
        NSLog(@"[WeaponX] 🌐 Network status changed: %@ -> %@", 
              lastNetworkStatus ? @"Online" : @"Offline", 
              isReachable ? @"Online" : @"Offline");
        
        lastNetworkStatus = isReachable;
        
        // Post appropriate notifications on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            // Post general status change notification
            NSDictionary *userInfo = @{@"isOnline": @(isReachable)};
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXNetworkStatusChanged" 
                                                              object:nil 
                                                            userInfo:userInfo];
            
            // Post specific notifications for became available/unavailable
            if (isReachable) {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXNetworkBecameAvailable" 
                                                                  object:nil];
            } else {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXNetworkBecameUnavailable" 
                                                                  object:nil];
            }
        });
    }
    
    return isReachable;
}

#pragma mark - Debugging and Troubleshooting

// Method to enable bypass flags for development and troubleshooting
- (void)enableBypassFlagsForTesting:(BOOL)enable {
    NSLog(@"[WeaponX] %@ bypass flags for testing/development", enable ? @"Enabling" : @"Disabling");
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enable forKey:@"WeaponXBypassPlanVerification"];
    [defaults setBool:enable forKey:@"WeaponXBypassTabRestrictions"];
    [defaults synchronize];
    
    if (enable) {
        // Set a long offline grace period (30 days)
        NSDate *farFutureDate = [NSDate dateWithTimeIntervalSinceNow:30 * 24 * 60 * 60];
        [defaults setObject:farFutureDate forKey:@"WeaponXUserPlanTimestamp"];
        [defaults synchronize];
        
        NSLog(@"[WeaponX] ✅ Testing bypass flags enabled - app should now work without restrictions");
    } else {
        NSLog(@"[WeaponX] ✅ Testing bypass flags disabled - app will enforce normal restrictions");
    }
}

#pragma mark - SSL Certificate Testing

// Method to test SSL certificate validation explicitly
- (void)testSSLCertificateWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    NSLog(@"[WeaponX] 🔒 Testing SSL certificate for %@", self.baseURLString);
    
    NSURL *url = [NSURL URLWithString:self.baseURLString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"WeaponXErrorDomain" code:400 
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid base URL"}];
        completion(NO, error);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    // Use our custom session with SSL handling
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ SSL certificate test failed: %@", error);
            NSLog(@"[WeaponX] ❌ Error domain: %@, code: %ld", error.domain, (long)error.code);
            
            // Check for specific SSL errors
            if ([error.domain isEqualToString:NSURLErrorDomain]) {
                if (error.code == NSURLErrorSecureConnectionFailed ||
                    error.code == NSURLErrorServerCertificateHasBadDate ||
                    error.code == NSURLErrorServerCertificateUntrusted ||
                    error.code == NSURLErrorServerCertificateHasUnknownRoot ||
                    error.code == NSURLErrorServerCertificateNotYetValid) {
                    NSLog(@"[WeaponX] 🔒 SSL Certificate error detected - check your certificate trust settings");
                } else if (error.code == NSURLErrorNotConnectedToInternet) {
                    NSLog(@"[WeaponX] 🌐 Network unavailable - this is not an SSL issue");
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, error);
            });
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] ✅ SSL certificate test successful! Status code: %ld", (long)httpResponse.statusCode);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, nil);
        });
    }];
    
    [task resume];
}

// Method to check if we're within the offline grace period
- (BOOL)isWithinOfflineGracePeriod {
    // Check if network is available - if so, we don't need to worry about grace period
    if ([self isNetworkAvailable]) {
        return YES;
    }
    
    // Use SecureTimeManager for enhanced time security
    SecureTimeManager *timeManager = [SecureTimeManager sharedManager];
    
    // Get timestamp of last successful plan verification
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDate *lastVerificationDate = [defaults objectForKey:@"WeaponXLastServerConfirmationDate"];
    
    // If we've never verified, we're not within grace period
    if (!lastVerificationDate) {
        NSLog(@"[WeaponX] ⚠️ No previous verification timestamp - not within grace period");
        return NO;
    }
    
    // Use timestamp validation with grace period
    NSTimeInterval lastVerificationTimestamp = [lastVerificationDate timeIntervalSince1970];
    BOOL isValid = [timeManager isTimestampValid:lastVerificationTimestamp withGracePeriod:24]; // 24-hour grace period
    
    // Check elapsed usage time as a secondary measure
    BOOL isWithinUsageLimits = [timeManager isWithinUsageLimits:24]; // 24 hours of total usage allowed
    
    // Check for time manipulation
    BOOL timeManipulationDetected = [timeManager isTimeManipulationDetected];
    
    NSLog(@"[WeaponX] 🛡️ Enhanced offline access check - Valid timestamp: %@, Within usage limits: %@, Time manipulation: %@",
          isValid ? @"YES" : @"NO", 
          isWithinUsageLimits ? @"YES" : @"NO",
          timeManipulationDetected ? @"DETECTED" : @"NONE");
    
    // Access is allowed only if timestamp is valid, usage is within limits, and no manipulation detected
    return isValid && isWithinUsageLimits && !timeManipulationDetected;
}

// MARK: - Plan Verification Methods

// Method to verify plan data integrity

// Add method to store plan data with proper hash
- (void)storePlanData:(NSDictionary *)planData {
    if (!planData) {
        NSLog(@"[WeaponX] ❌ Cannot store nil plan data");
        return;
    }
    
    NSLog(@"[WeaponX] 💾 Storing plan data to user defaults");
    
    // Store the plan data
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:planData forKey:@"WeaponXUserPlan"];
    
    // Generate and store hash for integrity checking
    NSString *planHash = [self createSecureHashForPlanData:planData];
    [defaults setObject:planHash forKey:@"WeaponXUserPlanHash"];
    
    // Store the verification timestamp (current time)
    [defaults setObject:[NSDate date] forKey:@"WeaponXUserPlanTimestamp"];
    
    // Reset verification flags since we've just stored new data
    [defaults setBool:NO forKey:@"WeaponXNeedsReVerification"];
    [defaults setBool:NO forKey:@"WeaponXOfflineGraceAlertShown"];
    
    // Synchronize to ensure data is written immediately
    [defaults synchronize];
}

// Method to check if we're within the offline grace period
// ... existing code ...

// Find the sendHeartbeat method and update it
- (void)sendHeartbeat:(NSString *)token withScreenName:(NSString *)screenName {
    if (!token || token.length == 0) {
        NSLog(@"[WeaponX] ❌ Cannot send heartbeat - no token provided");
        return;
    }
    
    // Check network availability first
    if (![self isNetworkAvailable]) {
        NSLog(@"[WeaponX] 🌐 Network unavailable - queuing heartbeat for later");
        
        // Initialize queue if needed
        if (!_queuedHeartbeats) {
            _queuedHeartbeats = [NSMutableArray array];
        }
        
        // Store heartbeat data for later
        NSDictionary *heartbeatData = @{
            @"token": token ?: @"",
            @"screen": screenName ?: @"Unknown",
            @"timestamp": [NSDate date]
        };
        
        // Add to queue for later processing
        [_queuedHeartbeats addObject:heartbeatData];
        
        // Limit queue size to prevent memory issues
        if (_queuedHeartbeats.count > 10) {
            [_queuedHeartbeats removeObjectAtIndex:0];
        }
        
        return;
    }
    
    NSLog(@"[WeaponX] ⏱️ Heartbeat timer fired");
    
    // Get user ID from token
    NSString *userId = [self getUserIdFromToken:token];
    if (!userId) {
        NSLog(@"[WeaponX] ❌ Invalid token for heartbeat - cannot extract user ID");
        return;
    }
    
    NSLog(@"[WeaponX] ✅ Retrieved valid user ID for heartbeat: %@", userId);
    NSLog(@"[WeaponX] 📡 Sending heartbeat for user ID: %@", userId);
    
    // Log token (partial for security)
    NSString *partialToken = nil;
    if (token.length > 10) {
        partialToken = [NSString stringWithFormat:@"%@...", [token substringToIndex:10]];
    } else {
        partialToken = @"[token too short]";
    }
    NSLog(@"[WeaponX] 🔑 Using token for heartbeat: %@", partialToken);
    
    // Get the public IP address for tracking
    [self getPublicIPWithCompletion:^(NSString *ipAddress, NSError *error) {
        // Continue with heartbeat even if IP fetching fails
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to get public IP: %@", error);
        }
        
        // Get CSRF token for the request
        [self getCsrfTokenWithCompletion:^(NSString *csrfToken, NSError *tokenError) {
            if (tokenError) {
                NSLog(@"[WeaponX] ❌ Failed to get CSRF token for heartbeat: %@", tokenError);
                return;
            }
            
            NSLog(@"[WeaponX] ✅ Got CSRF token for heartbeat: %@", [csrfToken substringToIndex:MIN(10, csrfToken.length)]);
            
            // Build URL
            NSString *heartbeatURL = [NSString stringWithFormat:@"%@/api/heartbeat", self.baseURLString];
            NSLog(@"[WeaponX] 🌐 Heartbeat URL: %@", heartbeatURL);
            
            // Get device info
            NSString *modelName = [self getDeviceModel];
            NSString *systemVersion = [UIDevice currentDevice].systemVersion;
            NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            NSString *buildNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
            
            // Get mapped device name for better readability
            NSString *deviceIdentifier = [self deviceModelIdentifier];
            NSString *deviceName = [self mapDeviceModelToReadableName:deviceIdentifier];
            NSLog(@"[WeaponX] Device model identifier: %@, mapped to: %@", deviceIdentifier, deviceName);
            
            // Include screen name if provided
            if (screenName) {
                NSLog(@"[WeaponX] 📱 Including current screen in heartbeat: %@", screenName);
            }
            
            // Create parameters
            NSMutableDictionary *parameters = [@{
                @"user_id": userId,
                @"device_type": @"iOS",
                @"app_version": [NSString stringWithFormat:@"%@ (%@)", appVersion, buildNumber],
                @"system_version": systemVersion,
                @"device_model": deviceName ?: modelName,
                @"_token": csrfToken
            } mutableCopy];
            
            // Add IP address if available
            if (ipAddress) {
                parameters[@"ip_address"] = ipAddress;
            }
            
            // Add screen name if available
            if (screenName) {
                parameters[@"current_screen"] = screenName;
            }
            
            // Serialize parameters
            NSError *jsonError;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Failed to serialize heartbeat JSON: %@", jsonError);
                return;
            }
            
            // Create request
            NSURL *url = [NSURL URLWithString:heartbeatURL];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            [request setHTTPMethod:@"POST"];
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
            [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
            [request setHTTPBody:jsonData];
            
            // Create data task
            NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error) {
                    NSLog(@"[WeaponX] ❌ Heartbeat request error: %@", error);
                    
                    // If this was a network error, queue the heartbeat for retry
                    if ([error.domain isEqualToString:NSURLErrorDomain] && 
                        (error.code == NSURLErrorNotConnectedToInternet || 
                         error.code == NSURLErrorNetworkConnectionLost)) {
                        
                        // Queue for retry
                        if (!self->_queuedHeartbeats) {
                            self->_queuedHeartbeats = [NSMutableArray array];
                        }
                        
                        // Create data for retry
                        NSDictionary *heartbeatData = @{
                            @"token": token,
                            @"screen": screenName ?: @"Unknown",
                            @"timestamp": [NSDate date]
                        };
                        
                        // Add to queue
                        [self->_queuedHeartbeats addObject:heartbeatData];
                        
                        // Limit queue size
                        if (self->_queuedHeartbeats.count > 10) {
                            [self->_queuedHeartbeats removeObjectAtIndex:0];
                        }
                    }
                    
                    return;
                }
                
                // Check response
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                    NSLog(@"[WeaponX] ✅ Heartbeat sent successfully");
                } else {
                    NSLog(@"[WeaponX] ⚠️ Heartbeat returned unexpected status code: %ld", (long)httpResponse.statusCode);
                    
                    // Try to parse error response
                    if (data) {
                        NSError *jsonError;
                        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                        
                        if (!jsonError && responseDict) {
                            NSLog(@"[WeaponX] ℹ️ Heartbeat response: %@", responseDict);
                        }
                    }
                }
            }];
            
            [task resume];
        }];
    }];
}

// Add method to process queued heartbeats
- (void)processQueuedHeartbeats {
    if (![self isNetworkAvailable] || !_queuedHeartbeats || _queuedHeartbeats.count == 0) {
        return;
    }
    
    NSLog(@"[WeaponX] 🔄 Processing %ld queued heartbeats", (long)_queuedHeartbeats.count);
    
    // Create a local copy to avoid modification during iteration
    NSArray *heartbeatsToProcess = [_queuedHeartbeats copy];
    [_queuedHeartbeats removeAllObjects];
    
    // Process each heartbeat
    for (NSDictionary *heartbeatData in heartbeatsToProcess) {
        NSString *token = heartbeatData[@"token"];
        NSString *screenName = heartbeatData[@"screen"];
        
        // Skip very old heartbeats (older than 1 hour)
        NSDate *timestamp = heartbeatData[@"timestamp"];
        if (timestamp && [[NSDate date] timeIntervalSinceDate:timestamp] > 3600) {
            NSLog(@"[WeaponX] ⏱️ Skipping old heartbeat from %@", timestamp);
            continue;
        }
        
        // Send the heartbeat with a slight delay to avoid flooding the server
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self sendHeartbeat:token withScreenName:screenName];
        });
    }
}

// Make sure to add this in init method or wherever appropriate
- (void)registerForNetworkStatusChanges {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNetworkBecameAvailable:)
                                                 name:@"WeaponXNetworkBecameAvailable"
                                               object:nil];
}

// Add handler for network becoming available
- (void)handleNetworkBecameAvailable:(NSNotification *)notification {
    NSLog(@"[WeaponX] 🌐 Network became available in APIManager - processing queued operations");
    
    // Process any queued heartbeats
    [self processQueuedHeartbeats];
    
    // Check if token refresh is needed
    [self checkAndRefreshTokenIfNeeded];
    
    // Check if plan data needs refresh
    [self checkAndRefreshPlanDataIfNeeded];
}

// Add supporting method for token checking
- (void)checkAndRefreshTokenIfNeeded {
    // Get current token
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXAuthToken"];
    if (!token) {
        return; // No token to refresh
    }
    
    // Check if token refresh is needed (implement your logic)
    BOOL needsRefresh = NO; // implement your logic here
    
    if (needsRefresh) {
        // Call token refresh method
        // [self refreshToken:token];
    }
}

// Add supporting method for plan data refresh
- (void)checkAndRefreshPlanDataIfNeeded {
    // Get current token
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXAuthToken"];
    if (!token) {
        return; // No token to use for refresh
    }
    
    // Check if we need to refresh plan data
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL needsReVerification = [defaults boolForKey:@"WeaponXNeedsReVerification"];
    
    if (needsReVerification) {
        // Refresh plan data
        [self refreshPlanData:token];
    }
}

// Helper method to extract user ID from token
- (NSString *)getUserIdFromToken:(NSString *)token {
    if (!token || token.length == 0) {
        return nil;
    }
    
    // Split token by pipe character (|)
    NSArray *components = [token componentsSeparatedByString:@"|"];
    
    // First part should be the user ID
    if (components.count > 0) {
        NSString *userId = components[0];
        
        // Validate that it's a number
        NSCharacterSet *nonNumberSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([userId rangeOfCharacterFromSet:nonNumberSet].location == NSNotFound) {
            return userId;
        }
    }
    
    // If token format is not as expected, try getting from UserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *userInfo = [defaults objectForKey:@"WeaponXUserInfo"];
    
    if (userInfo && [userInfo isKindOfClass:[NSDictionary class]]) {
        id userId = [userInfo objectForKey:@"id"];
        
        if (userId) {
            return [NSString stringWithFormat:@"%@", userId];
        }
    }
    
    return nil;
}

// Helper method to get device model identifier
- (NSString *)deviceModelIdentifier {
    struct utsname systemInfo;
    uname(&systemInfo);
    
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

// Helper method to map device identifier to readable name
- (NSString *)mapDeviceModelToReadableName:(NSString *)identifier {
    // Common device mappings
    NSDictionary *deviceMap = @{
        // iPhones
        @"iPhone9,1": @"iPhone 7",
        @"iPhone9,3": @"iPhone 7",
        @"iPhone9,2": @"iPhone 7 Plus",
        @"iPhone9,4": @"iPhone 7 Plus",
        @"iPhone10,1": @"iPhone 8",
        @"iPhone10,4": @"iPhone 8",
        @"iPhone10,2": @"iPhone 8 Plus",
        @"iPhone10,5": @"iPhone 8 Plus",
        @"iPhone10,3": @"iPhone X",
        @"iPhone10,6": @"iPhone X",
        @"iPhone11,2": @"iPhone XS",
        @"iPhone11,4": @"iPhone XS Max",
        @"iPhone11,6": @"iPhone XS Max",
        @"iPhone11,8": @"iPhone XR",
        @"iPhone12,1": @"iPhone 11",
        @"iPhone12,3": @"iPhone 11 Pro",
        @"iPhone12,5": @"iPhone 11 Pro Max",
        @"iPhone13,1": @"iPhone 12 mini",
        @"iPhone13,2": @"iPhone 12",
        @"iPhone13,3": @"iPhone 12 Pro",
        @"iPhone13,4": @"iPhone 12 Pro Max",
        @"iPhone14,4": @"iPhone 13 mini",
        @"iPhone14,5": @"iPhone 13",
        @"iPhone14,2": @"iPhone 13 Pro",
        @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,7": @"iPhone 14",
        @"iPhone14,8": @"iPhone 14 Plus",
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        @"iPhone16,1": @"iPhone 15 Pro",
        @"iPhone16,2": @"iPhone 15 Pro Max",
        
        // iPads
        @"iPad5,1": @"iPad mini 4",
        @"iPad5,2": @"iPad mini 4",
        @"iPad5,3": @"iPad Air 2",
        @"iPad5,4": @"iPad Air 2",
        @"iPad6,3": @"iPad Pro (9.7-inch)",
        @"iPad6,4": @"iPad Pro (9.7-inch)",
        @"iPad6,7": @"iPad Pro (12.9-inch)",
        @"iPad6,8": @"iPad Pro (12.9-inch)",
        @"iPad6,11": @"iPad (5th generation)",
        @"iPad6,12": @"iPad (5th generation)",
        @"iPad7,1": @"iPad Pro (12.9-inch) (2nd generation)",
        @"iPad7,2": @"iPad Pro (12.9-inch) (2nd generation)",
        @"iPad7,3": @"iPad Pro (10.5-inch)",
        @"iPad7,4": @"iPad Pro (10.5-inch)",
        @"iPad7,5": @"iPad (6th generation)",
        @"iPad7,6": @"iPad (6th generation)",
        @"iPad7,11": @"iPad (7th generation)",
        @"iPad7,12": @"iPad (7th generation)",
        @"iPad8,1": @"iPad Pro (11-inch)",
        @"iPad8,2": @"iPad Pro (11-inch)",
        @"iPad8,3": @"iPad Pro (11-inch)",
        @"iPad8,4": @"iPad Pro (11-inch)",
        @"iPad8,5": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,6": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,7": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,8": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,9": @"iPad Pro (11-inch) (2nd generation)",
        @"iPad8,10": @"iPad Pro (11-inch) (2nd generation)",
        @"iPad8,11": @"iPad Pro (12.9-inch) (4th generation)",
        @"iPad8,12": @"iPad Pro (12.9-inch) (4th generation)",
        
        // iPod touch
        @"iPod9,1": @"iPod touch (7th generation)"
    };
    
    return deviceMap[identifier] ?: identifier;
}

// Helper method to get the public IP address
- (void)getPublicIPWithCompletion:(void (^)(NSString *ipAddress, NSError *error))completion {
    // Check network availability first to avoid unnecessary requests
    if (![self isNetworkAvailable]) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain 
                                                 code:NSURLErrorNotConnectedToInternet 
                                             userInfo:@{NSLocalizedDescriptionKey: @"Network is unavailable"}];
            completion(nil, error);
        }
        return;
    }
    
    // If we already have the IP cached and it's less than 1 hour old, use it
    static NSString *cachedIP = nil;
    static NSDate *lastIPCheckTime = nil;
    
    if (cachedIP && lastIPCheckTime && [[NSDate date] timeIntervalSinceDate:lastIPCheckTime] < 3600) {
        if (completion) {
            completion(cachedIP, nil);
        }
        return;
    }
    
    // Create a request to the IP service
    NSURL *url = [NSURL URLWithString:@"https://api.ipify.org/?format=json"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url 
                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                        timeoutInterval:10.0];
    
    // Create data task
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request 
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to get public IP: %@", error);
            
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        // Check response
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"[WeaponX] ⚠️ IP service returned unexpected status code: %ld", (long)httpResponse.statusCode);
            
            if (completion) {
                NSError *statusError = [NSError errorWithDomain:@"com.hydra.projectx.errors" 
                                                          code:httpResponse.statusCode 
                                                      userInfo:@{NSLocalizedDescriptionKey: @"IP service returned unexpected status code"}];
                completion(nil, statusError);
            }
            return;
        }
        
        // Parse JSON response
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data 
                                                                     options:0 
                                                                       error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] ❌ Failed to parse IP service response: %@", jsonError);
            
            if (completion) {
                completion(nil, jsonError);
            }
            return;
        }
        
        // Extract IP address
        NSString *ipAddress = jsonResponse[@"ip"];
        
        if (!ipAddress) {
            NSLog(@"[WeaponX] ⚠️ IP service response did not contain IP address");
            
            if (completion) {
                NSError *noIPError = [NSError errorWithDomain:@"com.hydra.projectx.errors" 
                                                        code:-1 
                                                    userInfo:@{NSLocalizedDescriptionKey: @"IP service response did not contain IP address"}];
                completion(nil, noIPError);
            }
            return;
        }
        
        // Cache the IP address
        cachedIP = ipAddress;
        lastIPCheckTime = [NSDate date];
        
        NSLog(@"[WeaponX] ✅ Got public IP address: %@", ipAddress);
        
        // Return the IP address
        if (completion) {
            completion(ipAddress, nil);
        }
    }];
    
    [task resume];
}

// Helper method to get device model
- (NSString *)getDeviceModel {
    UIDevice *device = [UIDevice currentDevice];
    return [NSString stringWithFormat:@"%@ %@", device.model, device.systemVersion];
}

// Helper method to get CSRF token
- (void)getCsrfTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion {
    NSLog(@"[WeaponX] 🔑 Fetching CSRF token...");
    
    // Check if we have a cached token that's less than 30 minutes old
    NSDate *now = [NSDate date];
    if (_csrfTokens && _lastCsrfTokenFetchTime) {
        NSString *cachedToken = [_csrfTokens objectForKey:self.baseURLString];
        NSTimeInterval timeSinceLastFetch = [now timeIntervalSinceDate:_lastCsrfTokenFetchTime];
        
        if (cachedToken && timeSinceLastFetch < 30 * 60) { // 30 minutes
            NSLog(@"[WeaponX] ✅ Using cached CSRF token (expires in %.1f minutes)", (30 - (timeSinceLastFetch / 60)));
            if (completion) {
                completion(cachedToken, nil);
            }
            return;
        }
    }
    
    // Check network availability
    if (![self isNetworkAvailable]) {
        NSLog(@"[WeaponX] ⚠️ Network unavailable - cannot fetch CSRF token");
        
        // Use cached token even if expired when offline
        NSString *cachedToken = [_csrfTokens objectForKey:self.baseURLString];
        if (cachedToken) {
            NSLog(@"[WeaponX] ⚠️ Using expired CSRF token due to network unavailability");
            if (completion) {
                completion(cachedToken, nil);
            }
            return;
        }
        
        // No cached token available
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain 
                                            code:NSURLErrorNotConnectedToInternet 
                                        userInfo:@{NSLocalizedDescriptionKey: @"Network is unavailable"}];
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    
    // Initialize token cache if needed
    if (!_csrfTokens) {
        _csrfTokens = [NSMutableDictionary dictionary];
    }
    
    // Get the token from the server
    NSString *tokenURL = [NSString stringWithFormat:@"%@/csrf-token", self.baseURLString];
    NSURL *url = [NSURL URLWithString:tokenURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to fetch CSRF token: %@", error);
            
            // Use cached token even if expired on error
            NSString *cachedToken = [self->_csrfTokens objectForKey:self.baseURLString];
            if (cachedToken) {
                NSLog(@"[WeaponX] ⚠️ Using expired CSRF token due to server error");
                if (completion) {
                    completion(cachedToken, nil);
                }
                return;
            }
            
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        // Check response
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"[WeaponX] ⚠️ CSRF token endpoint returned unexpected status code: %ld", (long)httpResponse.statusCode);
            
            // Use cached token even if expired on error
            NSString *cachedToken = [self->_csrfTokens objectForKey:self.baseURLString];
            if (cachedToken) {
                NSLog(@"[WeaponX] ⚠️ Using expired CSRF token due to server error");
                if (completion) {
                    completion(cachedToken, nil);
                }
                return;
            }
            
            NSError *statusError = [NSError errorWithDomain:@"com.hydra.projectx.errors" 
                                                    code:httpResponse.statusCode 
                                                userInfo:@{NSLocalizedDescriptionKey: @"CSRF token endpoint returned unexpected status code"}];
            if (completion) {
                completion(nil, statusError);
            }
            return;
        }
        
        // Parse JSON response
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] ❌ Failed to parse CSRF token response: %@", jsonError);
            
            // Use cached token even if expired on error
            NSString *cachedToken = [self->_csrfTokens objectForKey:self.baseURLString];
            if (cachedToken) {
                NSLog(@"[WeaponX] ⚠️ Using expired CSRF token due to JSON parse error");
                if (completion) {
                    completion(cachedToken, nil);
                }
                return;
            }
            
            if (completion) {
                completion(nil, jsonError);
            }
            return;
        }
        
        // Extract token
        NSString *token = jsonResponse[@"token"];
        
        if (!token) {
            NSLog(@"[WeaponX] ⚠️ CSRF token response did not contain token");
            
            // Use cached token even if expired on error
            NSString *cachedToken = [self->_csrfTokens objectForKey:self.baseURLString];
            if (cachedToken) {
                NSLog(@"[WeaponX] ⚠️ Using expired CSRF token due to missing token in response");
                if (completion) {
                    completion(cachedToken, nil);
                }
                return;
            }
            
            NSError *noTokenError = [NSError errorWithDomain:@"com.hydra.projectx.errors" 
                                                    code:-1 
                                                userInfo:@{NSLocalizedDescriptionKey: @"CSRF token response did not contain token"}];
            if (completion) {
                completion(nil, noTokenError);
            }
            return;
        }
        
        // Cache the token
        self->_csrfTokens[self.baseURLString] = token;
        self->_lastCsrfTokenFetchTime = [NSDate date];
        
        NSLog(@"[WeaponX] ✅ Got fresh CSRF token");
        
        // Return the token
        if (completion) {
            completion(token, nil);
        }
    }];
    
    [task resume];
}

// Look for the method that handles plan data API responses
// Find something like "handleUserPlanResponse" or similar
// Specifically searching for code around this log: "User has no active plan (404 response)"

// ... existing code ...

// Add this update to the method handling the 404 response for plan data
- (void)handleUserPlanAPIResponse:(NSURLResponse *)response data:(NSData *)data error:(NSError *)error completion:(void (^)(NSDictionary *planData, NSError *error))completion {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    
    // Check if we have a 404 response but the user might still have a plan
    if (httpResponse.statusCode == 404) {
        // Instead of immediately assuming no plan, check user data for plan info
        NSLog(@"[WeaponX] ⚠️ Received 404 from plan API, checking alternative plan sources");
        
        // Check if we have plan data in user defaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *existingPlanData = [defaults objectForKey:@"WeaponXUserPlan"];
        NSDictionary *userData = [defaults objectForKey:@"WeaponXUserData"];
        
        // Check if user data contains plan expiry
        if (userData && [userData objectForKey:@"plan_expires_at"]) {
            NSString *expiryDateString = [userData objectForKey:@"plan_expires_at"];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            NSDate *expiryDate = [formatter dateFromString:expiryDateString];
            
            // If we have a valid expiry date in the future, consider the plan active
            if (expiryDate && [expiryDate timeIntervalSinceNow] > 0) {
                NSLog(@"[WeaponX] ✅ User has active plan based on expiry date: %@", expiryDateString);
                
                // Create synthetic plan data
                NSMutableDictionary *syntheticPlanData = [NSMutableDictionary dictionary];
                [syntheticPlanData setObject:@YES forKey:@"has_plan"];
                
                // Calculate days remaining
                NSTimeInterval secondsRemaining = [expiryDate timeIntervalSinceNow];
                NSInteger daysRemaining = (NSInteger)(secondsRemaining / 86400.0); // 86400 seconds in a day
                
                // Create plan dictionary
                NSMutableDictionary *planDict = [NSMutableDictionary dictionary];
                [planDict setObject:[userData objectForKey:@"plan_id"] ?: @1 forKey:@"id"];
                [planDict setObject:expiryDateString forKey:@"expires_at"];
                [planDict setObject:@(daysRemaining) forKey:@"days_remaining"];
                
                // If we know the plan name from existing data, use it
                if (existingPlanData && 
                    [existingPlanData objectForKey:@"plan"] && 
                    [[existingPlanData objectForKey:@"plan"] isKindOfClass:[NSDictionary class]] &&
                    [[[existingPlanData objectForKey:@"plan"] objectForKey:@"name"] length] > 0) {
                    [planDict setObject:[[existingPlanData objectForKey:@"plan"] objectForKey:@"name"] forKey:@"name"];
                } else {
                    // Default to a generic name based on plan ID
                    NSInteger planId = [[userData objectForKey:@"plan_id"] integerValue];
                    NSString *planName = @"ACTIVE";
                    
                    if (planId == 1) {
                        planName = @"TRIAL";
                    } else if (planId > 1) {
                        planName = [NSString stringWithFormat:@"PLAN %ld", (long)planId];
                    }
                    
                    [planDict setObject:planName forKey:@"name"];
                }
                
                [syntheticPlanData setObject:planDict forKey:@"plan"];
                [syntheticPlanData setObject:@"success" forKey:@"status"];
                
                // Use the synthetic plan data
                if (completion) {
                    completion(syntheticPlanData, nil);
                }
                return;
            }
        }
        
        // If we still have existing plan data with valid expiry, use that instead
        if (existingPlanData && 
            [existingPlanData objectForKey:@"plan"] && 
            [[existingPlanData objectForKey:@"plan"] isKindOfClass:[NSDictionary class]]) {
            
            NSDictionary *plan = [existingPlanData objectForKey:@"plan"];
            if ([plan objectForKey:@"expires_at"]) {
                NSString *expiryDateString = [plan objectForKey:@"expires_at"];
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                NSDate *expiryDate = [formatter dateFromString:expiryDateString];
                
                if (expiryDate && [expiryDate timeIntervalSinceNow] > 0) {
                    NSLog(@"[WeaponX] ✅ User has active plan based on cached plan data: %@", expiryDateString);
                    // Use the existing plan data
                    if (completion) {
                        completion(existingPlanData, nil);
                    }
                    return;
                }
            }
        }
        
        // Now create a "no plan" response, since we couldn't find valid plan data
        NSLog(@"[WeaponX] ℹ️ No valid plan found in alternative sources after 404 response");
        NSDictionary *noPlanDict = @{
            @"has_plan": @NO,
            @"status": @"success",
            @"plan": @{@"name": @"NO_PLAN"}
        };
        
        if (completion) {
            completion(noPlanDict, nil);
        }
        return;
    }
    
    // Handle normal responses (not 404)
    // ... existing code ...
}

#pragma mark - Time Security

- (void)syncTimeWithServer:(void (^)(BOOL success, NSTimeInterval serverTime, NSError *error))completion {
    // Create a dedicated endpoint for time synchronization
    NSString *urlString = [self apiUrlForEndpoint:@"server-time"];
    
    // Check if we have an auth token
    NSString *token = [self getAuthToken];
    NSURLRequest *request;
    
    if (token) {
        // Create authenticated request if we have a token
        request = [self prepareRequestWithToken:token method:@"GET" url:urlString];
    } else {
        // Create an unauthenticated request as fallback
        NSURL *url = [NSURL URLWithString:urlString];
        NSMutableURLRequest *mutableRequest = [NSMutableURLRequest requestWithURL:url];
        [mutableRequest setHTTPMethod:@"GET"];
        request = mutableRequest;
    }
    
    // Add request header to indicate this is a time sync request
    [(NSMutableURLRequest *)request addValue:@"true" forHTTPHeaderField:@"X-Time-Sync-Request"];
    
    // Send request
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to sync with server time: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, 0, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (httpResponse.statusCode == 200 && data) {
            NSError *jsonError = nil;
            NSDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Failed to parse server time JSON: %@", jsonError);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(NO, 0, jsonError);
                    });
                }
                return;
            }
            
            // Check if response contains server time
            if (responseObject[@"server_time"]) {
                // Extract server timestamp
                NSString *serverTimeString = responseObject[@"server_time"];
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
                NSDate *serverTime = [dateFormatter dateFromString:serverTimeString];
                
                if (serverTime) {
                    NSTimeInterval serverTimestamp = [serverTime timeIntervalSince1970];
                    
                    // Record server timestamp for secure time synchronization
                    [[SecureTimeManager sharedManager] recordServerTimestamp:serverTimestamp];
                    
                    NSLog(@"[WeaponX] 🔄 Explicitly synchronized with server time: %@", serverTimeString);
                    
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(YES, serverTimestamp, nil);
                        });
                    }
                } else {
                    NSError *parseError = [NSError errorWithDomain:@"WeaponXTimeError" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse server time format"}];
                    NSLog(@"[WeaponX] ❌ Failed to parse server time format");
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(NO, 0, parseError);
                        });
                    }
                }
            } else {
                NSError *missingTimeError = [NSError errorWithDomain:@"WeaponXTimeError" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Server response missing time data"}];
                NSLog(@"[WeaponX] ❌ Server response missing time data");
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(NO, 0, missingTimeError);
                    });
                }
            }
        } else {
            NSError *statusError = [NSError errorWithDomain:@"WeaponXTimeError" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch server time"}];
            NSLog(@"[WeaponX] ❌ Failed to fetch server time, status code: %ld", (long)httpResponse.statusCode);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, 0, statusError);
                });
            }
        }
    }];
    
    [task resume];
}

// ... existing code ...

// Process user data received from the server
- (NSDictionary *)processUserData:(NSDictionary *)userData {
    if (!userData) {
        NSLog(@"[WeaponX] ⚠️ Warning: processUserData called with nil userData");
        return nil;
    }
    
    // Create a mutable copy to modify
    NSMutableDictionary *processedUserData = [NSMutableDictionary dictionaryWithDictionary:userData];
    
    // Make sure required fields are present
    if (!processedUserData[@"id"]) {
        NSLog(@"[WeaponX] ⚠️ Error: User data missing required ID field");
        return nil;
    }
    
    // Use decorated_name if available (includes 🔥 for premium users)
    if (processedUserData[@"decorated_name"]) {
        NSLog(@"[WeaponX] 🔥 Using decorated name: %@", processedUserData[@"decorated_name"]);
        processedUserData[@"name"] = processedUserData[@"decorated_name"];
    } else if (!processedUserData[@"name"]) {
        // Fallback to default name if missing
        processedUserData[@"name"] = @"User";
    }
    
    // Format user ID as string
    NSString *userId = [NSString stringWithFormat:@"%@", processedUserData[@"id"]];
    processedUserData[@"id"] = userId;
    
    // Also save username and email directly
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:processedUserData[@"name"] forKey:@"UserName"];
    [defaults setObject:processedUserData[@"email"] forKey:@"UserEmail"];
    [defaults setObject:userId forKey:@"WeaponXUserID"];
    [defaults synchronize];
    
    return [NSDictionary dictionaryWithDictionary:processedUserData];
}
@end
