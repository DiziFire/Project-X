#import <UIKit/UIKit.h>
#import "ProjectX.h"
#import "TabBarController.h"
#import "APIManager.h"
#import "SupportViewController.h"
#import <UserNotifications/UserNotifications.h>
#import "AppDataCleaner.h"

// Import our guardian
extern void StartWeaponXGuardian(void);

@interface AppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor systemBackgroundColor];
    
    // Set notification delegate
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    
    TabBarController *tabBarController = [[TabBarController alloc] init];
    
    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    
    // Check for existing plan data and verify integrity
    [self performSecurityChecksAtLaunch];
    
    // Add special check for inconsistent plan data
    [self checkForInconsistentPlanData];
    
    // Start heartbeat for online presence when app launches
    [self startHeartbeatIfLoggedIn];
    
    // Register for push notifications after a delay, not during initial launch
    // This prevents the permission prompt from showing immediately on launch
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self registerForPushNotifications];
    });
    
    // Start the guardian to ensure persistent background execution
    StartWeaponXGuardian();
    
    return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Set a flag to indicate the app is resuming from recents
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"WeaponXIsResuming"];
    [defaults synchronize];
    
    // Check authentication status when app is about to enter foreground
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    if ([tabBarController respondsToSelector:@selector(checkAuthenticationStatus)]) {
        [tabBarController checkAuthenticationStatus];
    }
    
    // Special check for inconsistent plan data when resuming from recents
    [self checkForInconsistentPlanData];
    
    // Restart heartbeat when app enters foreground
    [self startHeartbeatIfLoggedIn];
    
    // Reset the resuming flag after a delay to ensure it's used by all components
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [defaults setBool:NO forKey:@"WeaponXIsResuming"];
        [defaults synchronize];
    });
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Use an atomic flag to prevent multiple concurrent auth checks
    static BOOL isCheckingAuth = NO;
    if (isCheckingAuth) {
        return;
    }
    
    isCheckingAuth = YES;
    
    // Make sure we're properly authenticated when app becomes active
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    if ([tabBarController respondsToSelector:@selector(checkAuthenticationStatus)]) {
        [tabBarController checkAuthenticationStatus];
    }
    
    // Ensure heartbeat is active when app becomes active
    [self startHeartbeatIfLoggedIn];
    
    // Add a delay before resetting the flag to avoid rapid rechecks
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        isCheckingAuth = NO;
    });
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Clean up when the app is about to terminate
    
    // Stop heartbeat
    [[APIManager sharedManager] stopHeartbeat];
    
    // Clean up notification center if needed
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Helper method to start heartbeat if user is logged in
- (void)startHeartbeatIfLoggedIn {
    // Get the stored user ID
    NSString *userId = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXServerUserId"];
    NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXAuthToken"];
    
    // Only start heartbeat if we have a valid user ID and token
    if (userId && userId.length > 0 && token && token.length > 0) {
        [[APIManager sharedManager] startHeartbeat:userId];
        
        // Set up notification observers for tracking screen changes
        [self setupScreenChangeTracking];
    }
}

// Example of screen tracking functionality
- (void)setupScreenChangeTracking {
    // We'll primarily rely on tab bar change notifications instead of view controller notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tabBarSelectionChanged:)
                                                 name:@"TabBarSelectionChangedNotification"
                                               object:nil];
    
    // Observe app state changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActiveNotification:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Set initial screen tracking with a delay to ensure UI is initialized
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self detectAndUpdateCurrentScreen];
        
        // Set up a periodic check to ensure screen tracking stays accurate
        NSTimer *screenCheckTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 
                                                                     target:self
                                                                   selector:@selector(detectAndUpdateCurrentScreen) 
                                                                   userInfo:nil 
                                                                    repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:screenCheckTimer forMode:NSRunLoopCommonModes];
    });
}

// New method to directly detect the current screen/tab
- (void)detectAndUpdateCurrentScreen {
    static NSString *lastDetectedScreen = nil;
    static NSDate *lastDetectionTime = nil;
    
    // Add debouncing - don't update if the same screen was detected recently
    NSDate *now = [NSDate date];
    
    if (lastDetectedScreen && lastDetectionTime) {
        NSTimeInterval timeSinceLastDetection = [now timeIntervalSinceDate:lastDetectionTime];
        if (timeSinceLastDetection < 0.5) { // 500ms debounce time
            // Skip detection if it's too soon after the last one
            return;
        }
    }
    
    // Get the root view controller
    UIViewController *rootVC = self.window.rootViewController;
    NSString *screenName = @"Unknown";
    
    // Check for modally presented controllers first (like Account view)
    if (rootVC.presentedViewController) {
        // Check if it's a navigation controller with AccountViewController
        if ([rootVC.presentedViewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *navController = (UINavigationController *)rootVC.presentedViewController;
            if ([navController.viewControllers.firstObject isKindOfClass:NSClassFromString(@"AccountViewController")]) {
                screenName = @"Account Tab (Modal)";
                
                // Check if it's the same as the last detected screen
                if (lastDetectedScreen && [lastDetectedScreen isEqualToString:screenName]) {
                    // Skip update if the screen hasn't changed
                    return;
                }
                
                // Store current detection info
                lastDetectedScreen = screenName;
                lastDetectionTime = now;
                
                [self updateCurrentScreen:screenName];
                return;
            }
        }
    }
    
    // Check if it's a tab bar controller
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)rootVC;
        NSInteger selectedIndex = tabBarController.selectedIndex;
        
        // Map tab indices to descriptive names
        switch (selectedIndex) {
            case 0:
                screenName = @"Map Tab";
                break;
            case 1:
                screenName = @"Home Tab";
                break;
            case 2:
                screenName = @"Security Tab";
                break;
            case 3:
                screenName = @"Account Tab";
                break;
            default:
                screenName = [NSString stringWithFormat:@"Tab %ld", (long)selectedIndex];
                break;
        }
    } else {
        // Not a tab bar controller, just use the class name
        screenName = NSStringFromClass([rootVC class]);
    }
    
    // Check if it's the same as the last detected screen
    if (lastDetectedScreen && [lastDetectedScreen isEqualToString:screenName]) {
        // Skip update if the screen hasn't changed
        return;
    }
    
    // Store current detection info
    lastDetectedScreen = screenName;
    lastDetectionTime = now;
    
    // Update the screen name
    [self updateCurrentScreen:screenName];
}

// Handle tab bar selection changes from notification
- (void)tabBarSelectionChanged:(NSNotification *)notification {
    static NSString *lastTabName = nil;
    static NSDate *lastTabChangeTime = nil;
    
    NSDate *now = [NSDate date];
    
    if (notification.userInfo) {
        NSString *tabName = notification.userInfo[@"tabName"];
        
        // Skip if the tab name is nil or the same as before within a short time window
        if (!tabName || (lastTabName && [lastTabName isEqualToString:tabName] && 
                         lastTabChangeTime && [now timeIntervalSinceDate:lastTabChangeTime] < 0.5)) {
            return;
        }
        
        // Update the tracking variables
        lastTabName = tabName;
        lastTabChangeTime = now;
        
        if (tabName) {
            [self updateCurrentScreen:tabName];
        }
    }
    
    // As a fallback, don't run our own detection immediately to avoid conflicts
    // Instead, schedule it after a slight delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self detectAndUpdateCurrentScreen];
    });
}

- (void)appDidBecomeActiveNotification:(NSNotification *)notification {
    // When app becomes active, detect the current screen
    [self detectAndUpdateCurrentScreen];
}

// Helper method to use APIManager's setCurrentScreen method if it exists
- (void)updateCurrentScreen:(NSString *)screenName {
    // Check if the APIManager responds to setCurrentScreen: before calling it
    APIManager *apiManager = [APIManager sharedManager];
    
    if ([apiManager respondsToSelector:@selector(setCurrentScreen:)]) {
        [apiManager performSelector:@selector(setCurrentScreen:) withObject:screenName];
    }
}

// Helper method to get the top most view controller
- (UIViewController *)topViewController {
    // Modern approach for iOS 13+ to get the key window
    UIWindow *keyWindow = nil;
    
    // Get the connected scenes
    NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
    for (UIScene *scene in scenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && 
            [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow) break;
        }
    }
    
    // Fallback for older iOS versions - without using deprecated APIs
    if (!keyWindow) {
        // Try to find any available window from connected scenes
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.windows.count > 0) {
                    keyWindow = windowScene.windows.firstObject;
                    break;
                }
            }
        }
        
        // Last resort for older iOS versions
        if (!keyWindow) {
            // Use a different approach that doesn't rely on deprecated APIs
            keyWindow = [[UIApplication sharedApplication] delegate].window;
        }
    }
    
    if (!keyWindow) {
        return nil;
    }
    
    UIViewController *rootViewController = keyWindow.rootViewController;
    return [self findTopViewControllerFromController:rootViewController];
}

- (UIViewController *)findTopViewControllerFromController:(UIViewController *)controller {
    if (controller.presentedViewController) {
        return [self findTopViewControllerFromController:controller.presentedViewController];
    } else if ([controller isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)controller;
        return [self findTopViewControllerFromController:navigationController.visibleViewController];
    } else if ([controller isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)controller;
        return [self findTopViewControllerFromController:tabController.selectedViewController];
    } else {
        return controller;
    }
}

// New method to perform security checks at launch
- (void)performSecurityChecksAtLaunch {
    // Check if the device is jailbroken (basic detection)
    if ([self isDeviceJailbroken]) {
        // You could add additional security measures here if desired
    }
    
    // Check authentication and plan status
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *authToken = [defaults objectForKey:@"WeaponXAuthToken"];
    
    if (authToken) {
        // Check if we're offline
        BOOL isOffline = ![[APIManager sharedManager] isNetworkAvailable];
        
        // Verify plan data integrity immediately
        BOOL planDataValid = [[APIManager sharedManager] verifyPlanDataIntegrity];
        
        if (!planDataValid) {
            // If plan data is invalid and we're online, try to refresh it
            if (!isOffline) {
                [[APIManager sharedManager] refreshUserPlan];
            } else {
                // Set a flag to remind us to check when back online
                [defaults setBool:YES forKey:@"WeaponXNeedsReVerification"];
                [defaults synchronize];
                
                // Restrict access to account tab only
                TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
                if ([tabBarController isKindOfClass:[TabBarController class]]) {
                    [tabBarController restrictAccessToAccountTabOnly:YES];
                }
            }
        } else {
            // If we're online and need to re-verify, do it now
            if (!isOffline && [defaults boolForKey:@"WeaponXNeedsReVerification"]) {
                [[APIManager sharedManager] refreshUserPlan];
            }
        }
    }
}

// New method to check for and fix inconsistent plan data
- (void)checkForInconsistentPlanData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isOnline = [[APIManager sharedManager] isNetworkAvailable];
    
    // Check if the user explicitly has no plan
    NSString *planName = [defaults objectForKey:@"UserPlanName"];
    if (planName && [planName isEqualToString:@"NO_PLAN"]) {
        // Double check if there's plan data that contradicts this
        NSDictionary *planData = [defaults objectForKey:@"WeaponXUserPlan"];
        if (planData && [planData[@"has_plan"] boolValue]) {
            // If plan data is invalid and we're online, try to refresh it
            if (!isOnline) {
                NSLog(@"[WeaponX] 🔄 Plan data invalid but offline - attempting to refresh plan data");
                [[APIManager sharedManager] refreshUserPlan];
            } else {
                NSLog(@"[WeaponX] ⚠️ Plan data invalid and online - restricting access");
                // Set a flag to remind us to check when back online
                [defaults setBool:YES forKey:@"WeaponXNeedsReVerification"];
                [defaults synchronize];
                
                // Restrict access to account tab only
                TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
                if ([tabBarController isKindOfClass:[TabBarController class]]) {
                    [tabBarController restrictAccessToAccountTabOnly:YES];
                }
            }
        } else {
            NSLog(@"[WeaponX] User has no plan, skipping inconsistency check");
            return;
        }
    }
    
    // Get all plan-related data
    NSDictionary *planData = [defaults objectForKey:@"WeaponXUserPlan"];
    NSString *planHash = [defaults objectForKey:@"WeaponXUserPlanHash"];
    NSDate *lastVerifiedDate = [defaults objectForKey:@"WeaponXUserPlanTimestamp"];
    BOOL hadActivePlan = [defaults boolForKey:@"WeaponXHasActivePlan"];
    
    // Check for inconsistencies
    BOOL hasInconsistentData = NO;
    
    // Case 1: We have a plan name but no actual plan data or hash
    if (planName && ![planName isEqualToString:@"NO_PLAN"] && 
       (!planData || !planHash)) {
        NSLog(@"[WeaponX] ⚠️ Inconsistent plan data detected: Have plan name but missing plan data or hash");
        
        // Check if we're offline but within grace period
        if (!isOnline && hadActivePlan && lastVerifiedDate) {
            NSTimeInterval timeElapsed = [[NSDate date] timeIntervalSinceDate:lastVerifiedDate];
            NSTimeInterval maxOfflineTime = 24 * 60 * 60; // 24 hours in seconds
            
            if (timeElapsed <= maxOfflineTime) {
                NSLog(@"[WeaponX] 📱 Offline but within grace period - not treating plan name/data mismatch as inconsistent");
                return;
            }
        }
        
        hasInconsistentData = YES;
    }
    
    // Case 2: We have plan data but no name or wrong name
    if (planData) {
        NSString *correctName = nil;
        BOOL shouldHaveName = NO;
        
        // Determine the correct plan name from the data
        if (planData[@"has_plan"] != nil && ![planData[@"has_plan"] boolValue]) {
            correctName = @"NO_PLAN";
            shouldHaveName = YES;
        } else if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *plan = planData[@"plan"];
            if (plan[@"name"]) {
                correctName = plan[@"name"];
                shouldHaveName = YES;
            }
        }
        
        // Check if the name doesn't match what we expect
        if (shouldHaveName && correctName) {
            if (!planName || ![correctName isEqualToString:planName]) {
                NSLog(@"[WeaponX] ⚠️ Inconsistent plan data detected: Plan name doesn't match plan data");
                NSLog(@"[WeaponX] ℹ️ Auto-fixing inconsistent plan name from plan data: %@ -> %@", 
                      planName ?: @"<nil>", correctName);
                [defaults setObject:correctName forKey:@"UserPlanName"];
                [defaults synchronize];
                return;
            }
        }
    }
    
    // Case 3: We have plan data and hash but the integrity check fails
    if (planData && planHash) {
        // Skip integrity check in offline mode if within grace period
        if (!isOnline && hadActivePlan && lastVerifiedDate) {
            NSTimeInterval timeElapsed = [[NSDate date] timeIntervalSinceDate:lastVerifiedDate];
            NSTimeInterval maxOfflineTime = 24 * 60 * 60; // 24 hours in seconds
            
            if (timeElapsed <= maxOfflineTime) {
                NSLog(@"[WeaponX] 📱 Offline but within grace period - not performing integrity check");
                
                // Set the re-verification flag for when we're back online
                [defaults setBool:YES forKey:@"WeaponXNeedsReVerification"];
                [defaults synchronize];
                return;
            }
        }
        
        // Only perform integrity check if we have the right method
        APIManager *apiManager = [APIManager sharedManager];
        if ([apiManager respondsToSelector:@selector(verifyPlanDataIntegrity)]) {
            BOOL isIntegrityValid = [apiManager performSelector:@selector(verifyPlanDataIntegrity)];
            if (!isIntegrityValid) {
                NSLog(@"[WeaponX] ⚠️ Inconsistent plan data detected: Integrity check failed");
                hasInconsistentData = YES;
            }
        }
    }
    
    // If inconsistency is found, clear ALL plan-related data for safety
    if (hasInconsistentData) {
        // If offline with WeaponXHasActivePlan, we might want to preserve some data
        if (!isOnline && hadActivePlan && lastVerifiedDate) {
            NSTimeInterval timeElapsed = [[NSDate date] timeIntervalSinceDate:lastVerifiedDate];
            NSTimeInterval maxOfflineTime = 24 * 60 * 60; // 24 hours in seconds
            
            if (timeElapsed <= maxOfflineTime) {
                NSLog(@"[WeaponX] 📱 Offline with WeaponXHasActivePlan=YES - preserving partial status");
                // Just ensure access until we can refresh
                [defaults setBool:YES forKey:@"WeaponXNeedsReVerification"];
                [defaults synchronize];
                return;
            } else {
                NSLog(@"[WeaponX] 🚫 Offline grace period expired (%.2f hours elapsed) - clearing inconsistent data", 
                      timeElapsed / 3600);
            }
        } else {
            NSLog(@"[WeaponX] 🧹 Clearing inconsistent plan data");
        }
        
        // Clear everything plan-related
        [defaults setObject:@"NO_PLAN" forKey:@"UserPlanName"];
        [defaults removeObjectForKey:@"UserPlanExpiry"];
        [defaults removeObjectForKey:@"UserPlanDaysRemaining"];
        [defaults removeObjectForKey:@"WeaponXUserPlan"];
        [defaults removeObjectForKey:@"WeaponXUserPlanHash"];
        [defaults removeObjectForKey:@"WeaponXUserPlanTimestamp"];
        [defaults removeObjectForKey:@"PlanExpiryDate"];
        [defaults removeObjectForKey:@"PlanDaysRemaining"];
        
        // Flag that access should be restricted until a fresh check is done
        [defaults setBool:YES forKey:@"WeaponXRestrictedAccess"];
        [defaults synchronize];
        
        // Force a refresh of plan data if we have an auth token and we're online
        NSString *authToken = [defaults objectForKey:@"WeaponXAuthToken"];
        if (authToken && isOnline) {
            APIManager *apiManager = [APIManager sharedManager];
            if ([apiManager respondsToSelector:@selector(fetchUserPlanWithToken:completion:)]) {
                NSLog(@"[WeaponX] 🔄 Forcing refresh of plan data from server");
                [apiManager performSelector:@selector(fetchUserPlanWithToken:completion:) 
                                withObject:authToken 
                                withObject:^(NSDictionary *planData, NSError *error) {
                    if (error) {
                        NSLog(@"[WeaponX] ❌ Failed to refresh plan data: %@", error);
                    } else {
                        NSLog(@"[WeaponX] ✅ Successfully refreshed plan data from server");
                        
                        // After successful refresh, remove access restrictions if user has a plan
                        BOOL serverIndicatesActivePlan = NO;
                        
                        if (planData[@"has_plan"] != nil) {
                            serverIndicatesActivePlan = [planData[@"has_plan"] boolValue];
                        } else if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
                            NSDictionary *plan = planData[@"plan"];
                            if (plan[@"name"] && ![plan[@"name"] isEqual:@"No Plan"]) {
                                serverIndicatesActivePlan = YES;
                            }
                        }
                        
                        // Update restriction flag based on server response
                        if (serverIndicatesActivePlan) {
                            NSLog(@"[WeaponX] 🔓 Removing access restrictions based on fresh server data");
                            [defaults setBool:NO forKey:@"WeaponXRestrictedAccess"];
                            [defaults synchronize];
                        }
                    }
                }];
            }
        }
    } else {
        NSLog(@"[WeaponX] ✅ No plan data inconsistencies detected");
    }
}

// Basic jailbreak detection method
- (BOOL)isDeviceJailbroken {
    // Check for common jailbreak files
    NSArray *jailbreakFiles = @[
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/bin/bash",
        @"/usr/sbin/sshd",
        @"/etc/apt",
        @"/usr/bin/ssh",
        @"/private/var/lib/apt"
    ];
    
    for (NSString *path in jailbreakFiles) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    
    // Check for write permissions to system locations
    NSError *error;
    NSString *testFile = @"/private/jailbreak_test";
    NSString *testContent = @"Jailbreak test";
    BOOL result = [testContent writeToFile:testFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (result) {
        // We could write to a system location, this suggests jailbreak
        [[NSFileManager defaultManager] removeItemAtPath:testFile error:nil];
        return YES;
    }
    
    // Check for Cydia URL scheme
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://"]]) {
        return YES;
    }
    
    return NO;
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    // Convert token to string
    NSString *token = [self stringFromDeviceToken:deviceToken];
    NSLog(@"[WeaponX] Device Token: %@", token);
    
    // Save token to defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:token forKey:@"WeaponXPushToken"];
    [defaults synchronize];
    
    // Send token to server if user is logged in
    NSString *authToken = [defaults objectForKey:@"WeaponXAuthToken"];
    if (authToken) {
        [self registerPushTokenWithServer:token];
    }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    NSLog(@"[WeaponX] Push notification received in background: %@", userInfo);
    
    // For background notification handling
    // This method is called when the app is in the background and a notification arrives
    
    // Process the notification data
    NSDictionary *aps = userInfo[@"aps"];
    NSString *notificationType = userInfo[@"type"];
    
    // Handle different notification types for background processing
    if (aps) {
        if ([notificationType isEqualToString:@"broadcast"]) {
            // Optionally pre-fetch broadcast data in the background
            NSNumber *broadcastId = userInfo[@"broadcast_id"];
            if (broadcastId) {
                NSLog(@"[WeaponX] Received broadcast notification in background for broadcast ID: %@", broadcastId);
                // Here you could pre-fetch the broadcast data
            }
        } else if ([notificationType isEqualToString:@"admin_reply"] || [notificationType isEqualToString:@"ticket_reply"]) {
            // Optionally pre-fetch ticket data in the background
            NSNumber *ticketId = userInfo[@"ticket_id"];
            if (ticketId) {
                NSLog(@"[WeaponX] Received ticket reply notification in background for ticket ID: %@", ticketId);
                // Here you could pre-fetch the ticket data
            }
        }
    }
    
    // Update badge count for the support tab
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateSupportTabBadge];
    });
    
    // Indicate that new data was fetched
    completionHandler(UIBackgroundFetchResultNewData);
}

- (void)handleBroadcastNotification:(NSNumber *)broadcastId {
    if (!broadcastId) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update notification badge on Support tab
        [self updateSupportTabBadge];
        
        // If app is active, show the broadcast alert
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Announcement"
                                                                          message:@"A new announcement has been posted. Would you like to view it now?"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"View" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                // Open the broadcast detail view
                [self openBroadcastDetail:broadcastId];
            }]];
            
            [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void)handleTicketReplyNotification:(NSNumber *)ticketId {
    if (!ticketId) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update notification badge on Support tab
        [self updateSupportTabBadge];
        
        // If app is active, show the ticket reply alert
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Support Ticket Update"
                                                                          message:@"There's a new reply to your support ticket. Would you like to view it now?"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"View" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                // Open the ticket detail view
                [self openTicketDetail:ticketId];
            }]];
            
            [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void)updateSupportTabBadge {
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    if ([tabBarController isKindOfClass:[TabBarController class]]) {
        [tabBarController updateNotificationBadge];
    }
}

- (void)openBroadcastDetail:(NSNumber *)broadcastId {
    // Find the TabBarController
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    if (![tabBarController isKindOfClass:[TabBarController class]]) {
        return;
    }
    
    // Support tab should be accessible by all users
    // Switch to the Support tab (index 3)
    [tabBarController setSelectedIndex:3];
    
    // Navigate to broadcast detail
    UINavigationController *supportNav = tabBarController.viewControllers[3];
    if ([supportNav isKindOfClass:[UINavigationController class]]) {
        SupportViewController *supportVC = supportNav.viewControllers.firstObject;
        if ([supportVC isKindOfClass:[SupportViewController class]]) {
            [supportVC openBroadcastDetail:broadcastId];
        }
    }
}

- (void)openTicketDetail:(NSNumber *)ticketId {
    // Find the TabBarController
    TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
    if (![tabBarController isKindOfClass:[TabBarController class]]) {
        return;
    }
    
    // Support tab should be accessible by all users
    // Switch to the Support tab (index 3)
    [tabBarController setSelectedIndex:3];
    
    // Navigate to ticket detail
    UINavigationController *supportNav = tabBarController.viewControllers[3];
    if ([supportNav isKindOfClass:[UINavigationController class]]) {
        SupportViewController *supportVC = supportNav.viewControllers.firstObject;
        if ([supportVC isKindOfClass:[SupportViewController class]]) {
            [supportVC openTicketDetail:ticketId];
        }
    }
}

- (NSString *)stringFromDeviceToken:(NSData *)deviceToken {
    NSUInteger length = deviceToken.length;
    if (length == 0) {
        return nil;
    }
    
    const unsigned char *buffer = deviceToken.bytes;
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(length * 2)];
    
    for (int i = 0; i < length; ++i) {
        [hexString appendFormat:@"%02x", buffer[i]];
    }
    
    return [hexString copy];
}

- (void)registerPushTokenWithServer:(NSString *)token {
    if (!token || token.length == 0) {
        return;
    }
    
    [[APIManager sharedManager] registerDeviceToken:token deviceType:@"ios" completion:^(BOOL success, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] Error registering push token: %@", error);
        } else {
            NSLog(@"[WeaponX] Push token registered successfully");
        }
    }];
}

#pragma mark - UNUserNotificationCenterDelegate Methods

// Called when a notification is delivered to a foreground app
- (void)userNotificationCenter:(UNUserNotificationCenter *)center 
       willPresentNotification:(UNNotification *)notification 
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    
    NSLog(@"[WeaponX] Notification received in foreground: %@", notification.request.content.userInfo);
    
    // Parse the notification content
    NSDictionary *userInfo = notification.request.content.userInfo;
    NSString *notificationType = userInfo[@"type"];
    
    // Update badge count for the support tab
    [self updateSupportTabBadge];
    
    if ([notificationType isEqualToString:@"broadcast"]) {
        // For broadcasts, check if we should show an alert or let the system handle it
        NSNumber *broadcastId = userInfo[@"broadcast_id"];
        
        if (broadcastId) {
            // Show our custom alert for broadcasts
            [self showBroadcastAlertForBroadcastId:broadcastId];
            completionHandler(UNNotificationPresentationOptionNone);
        } else {
            // If no valid broadcast ID, still show the system notification
            completionHandler(UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound | 
                             UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner);
        }
    } else if ([notificationType isEqualToString:@"admin_reply"] || [notificationType isEqualToString:@"ticket_reply"]) {
        // For ticket replies, show an alert even when in foreground
        NSNumber *ticketId = userInfo[@"ticket_id"];
        if (ticketId) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Support Ticket Update"
                                                                              message:@"There's a new reply to your support ticket. Would you like to view it now?"
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"View" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    // Open the ticket detail view
                    [self openTicketDetail:ticketId];
                }]];
                
                [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
            });
            // Don't show the system notification since we're showing our own alert
            completionHandler(UNNotificationPresentationOptionNone);
        } else {
            // If no valid ticket ID, still show the system notification
            completionHandler(UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound | 
                             UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner);
        }
    } else {
        // For other notification types, show the system notification
        completionHandler(UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound | 
                         UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner);
    }
}

// Called to let your app know which action was selected by the user
- (void)userNotificationCenter:(UNUserNotificationCenter *)center 
didReceiveNotificationResponse:(UNNotificationResponse *)response 
         withCompletionHandler:(void (^)(void))completionHandler {
    
    NSLog(@"[WeaponX] User responded to notification: %@", response.notification.request.content.userInfo);
    
    // Get the notification data
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    NSString *notificationType = userInfo[@"type"];
    
    // Handle different action types
    if ([response.actionIdentifier isEqualToString:@"VIEW_BROADCAST"] || 
        [response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        
        if ([notificationType isEqualToString:@"broadcast"]) {
            NSNumber *broadcastId = userInfo[@"broadcast_id"];
            if (broadcastId) {
                [self openBroadcastDetail:broadcastId];
            }
        } else if ([notificationType isEqualToString:@"admin_reply"] || [notificationType isEqualToString:@"ticket_reply"]) {
            NSNumber *ticketId = userInfo[@"ticket_id"];
            if (ticketId) {
                [self openTicketDetail:ticketId];
            }
        }
    }
    
    // Call the completion handler when done
    completionHandler();
}

// Method to request notification permissions and register for push notifications
- (void)registerForPushNotifications {
    // Check if we've already attempted to request permissions before
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasAttemptedPermissionRequest = [defaults boolForKey:@"WeaponXNotificationPermissionRequested"];
    
    // If we've already attempted to request permissions, don't show the prompt again
    if (hasAttemptedPermissionRequest) {
        NSLog(@"[WeaponX] Already attempted notification permission request before, not showing prompt again");
        
        // Just configure categories and register for remote notifications if we have permission
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            // Configure notification categories
            [self configureNotificationCategories];
            
            // Only register for remote notifications if authorized
            if (settings.authorizationStatus == UNAuthorizationStatusAuthorized || 
                settings.authorizationStatus == UNAuthorizationStatusProvisional) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] registerForRemoteNotifications];
                });
            }
        }];
        return;
    }
    
    // First check if we already have notification permission before requesting
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        // If we haven't determined the permission status yet, request it
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
            NSLog(@"[WeaponX] Notification permission not determined, requesting permissions...");
            
            // Mark that we've attempted to request permissions to prevent future prompts
            [defaults setBool:YES forKey:@"WeaponXNotificationPermissionRequested"];
            [defaults synchronize];
            
            [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                                  completionHandler:^(BOOL granted, NSError * _Nullable error) {
                if (granted) {
                    NSLog(@"[WeaponX] Notification permission granted");
                    
                    // Configure notification categories
                    [self configureNotificationCategories];
                    
                    // Register for remote notifications on the main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[UIApplication sharedApplication] registerForRemoteNotifications];
                    });
                } else {
                    NSLog(@"[WeaponX] Notification permission denied: %@", error);
                }
            }];
        } 
        // If already determined, just register for notifications if needed
        else {
            NSLog(@"[WeaponX] Notification authorization status already determined: %ld", (long)settings.authorizationStatus);
            
            // Mark that we've checked permissions to prevent future prompts
            [defaults setBool:YES forKey:@"WeaponXNotificationPermissionRequested"];
            [defaults synchronize];
            
            // Still configure categories even if we already have permissions
            [self configureNotificationCategories];
            
            // Only register for remote notifications if authorized
            if (settings.authorizationStatus == UNAuthorizationStatusAuthorized || 
                settings.authorizationStatus == UNAuthorizationStatusProvisional) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] registerForRemoteNotifications];
                });
            }
        }
    }];
}

// Configure notification categories for actionable notifications
- (void)configureNotificationCategories {
    // Create actions for broadcast notifications
    UNNotificationAction *viewBroadcastAction = [UNNotificationAction actionWithIdentifier:@"VIEW_BROADCAST"
                                                                                     title:@"View"
                                                                                   options:UNNotificationActionOptionForeground];
    
    // Create broadcast category with actions
    UNNotificationCategory *broadcastCategory = [UNNotificationCategory categoryWithIdentifier:@"BROADCAST_CATEGORY"
                                                                                      actions:@[viewBroadcastAction]
                                                                            intentIdentifiers:@[]
                                                                                      options:UNNotificationCategoryOptionNone];
    
    // Create actions for ticket notifications
    UNNotificationAction *viewTicketAction = [UNNotificationAction actionWithIdentifier:@"VIEW_TICKET"
                                                                                  title:@"View"
                                                                                options:UNNotificationActionOptionForeground];
    
    // Create ticket category with actions
    UNNotificationCategory *ticketCategory = [UNNotificationCategory categoryWithIdentifier:@"TICKET_CATEGORY"
                                                                                    actions:@[viewTicketAction]
                                                                          intentIdentifiers:@[]
                                                                                    options:UNNotificationCategoryOptionNone];
    
    // Register the categories with the notification center
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center setNotificationCategories:[NSSet setWithObjects:broadcastCategory, ticketCategory, nil]];
}

// Helper method to show the broadcast alert to avoid code duplication
- (void)showBroadcastAlertForBroadcastId:(NSNumber *)broadcastId {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Announcement"
                                                                      message:@"A new announcement has been posted. Would you like to view it now?"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"View" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            // Open the broadcast detail view
            [self openBroadcastDetail:broadcastId];
        }]];
        
        [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

@end

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    
    // Check if we're running a test command
    if (argc > 2 && [[NSString stringWithUTF8String:argv[1]] isEqualToString:@"clean_test"]) {
        NSLog(@"Running clean test for bundle ID: %s", argv[2]);
        NSString *bundleID = [NSString stringWithUTF8String:argv[2]];
        
        // Initialize the AppDataCleaner
        AppDataCleaner *cleaner = [[AppDataCleaner alloc] init];
        
        // Check if there's data to clean
        if ([cleaner hasDataToClear:bundleID]) {
            NSLog(@"Found data to clean for %@", bundleID);
            
            // Perform the cleaning
            [cleaner clearDataForBundleID:bundleID completion:^(BOOL success, NSError *error) {
                NSLog(@"Cleaning completed with status: %@", success ? @"SUCCESS" : @"FAILURE");
                
                if (error) {
                    NSLog(@"Error during cleaning: %@", error);
                }
                
                // Verify the clean
                [cleaner verifyDataCleared:bundleID];
                
                // Exit after test is complete
                exit(0);
            }];
            
            // Run the run loop until callback completes
            [[NSRunLoop currentRunLoop] run];
        } else {
            NSLog(@"No data found to clean for %@", bundleID);
            exit(0);
        }
    }
    
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}