// UberURLHooks.x - Low-level hooks for capturing Uber order IDs
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <fcntl.h>
#import <errno.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <objc/runtime.h>

// Add this at the very beginning of the file, after the imports
#define DOORDASH_DEBUG 1

// Export function for external use
#define EXPORT __attribute__((visibility("default")))

// Central keys for sharing data between processes
static NSString * const kUberOrderIDsKey = @"UberCapturedOrderIDs";
static NSString * const kDoorDashOrderIDsKey = @"DoorDashCapturedOrderIDs";
static NSString * const kAirplaneModeFileName = @"/tmp/weaponx_airplane_mode_active";

// Simple in-memory state tracking
static BOOL monitoringEnabled = NO;
static NSTimeInterval kMonitoringMaxDuration = 180; // 3 minutes in seconds
static BOOL initialSetupComplete = NO; // Flag to track if initial setup is complete

// Forward declarations
static void saveOrderID(NSString *orderID);
static void saveDoorDashOrderID(NSString *orderID);
static BOOL isMonitoringEnabled(void);
EXPORT void setMonitoringEnabled(BOOL enabled);
static NSString *extractJobIDFromURL(NSURL *url);
static NSString *extractDoorDashOrderIDFromURL(NSURL *url);
static void debugLogURL(NSString *source, NSURL *url, BOOL hasJobId);
static void debugLogDoorDashURL(NSString *source, NSURL *url);
static void disableMonitoringAfterTimeout(void);
static BOOL isAirplaneModeOn(void);
static void setAirplaneModeActive(BOOL active);
static void airplaneModeStatusChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void performDelayedSetup(void);

// Helper function to get the top view controller - moved to the top for proper declaration
UIViewController* getTopViewController(void) {
    UIViewController *rootViewController = nil;
    
    // iOS version check to use the appropriate API
    NSOperatingSystemVersion iOS13 = (NSOperatingSystemVersion){13, 0, 0};
    BOOL isIOS13OrLater = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:iOS13];
    
    if (isIOS13OrLater) {
        // Modern approach for iOS 13+
        UIScene *scene = nil;
        NSSet *connectedScenes = [[UIApplication sharedApplication] connectedScenes];
        
        for (UIScene *aScene in connectedScenes) {
            if (aScene.activationState == UISceneActivationStateForegroundActive) {
                scene = aScene;
                break;
            }
        }
        
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    rootViewController = window.rootViewController;
                    break;
                }
            }
        }
    }
    
    // Fallback for older iOS versions or if no window found above
    if (!rootViewController) {
        // Use application delegate window as fallback
        UIWindow *window = [[UIApplication sharedApplication] delegate].window;
        if (window) {
            rootViewController = window.rootViewController;
        }
        
        // If all else fails, try application windows directly (pre-iOS 13 approach)
        if (!rootViewController) {
            // This method works with iOS 12 and below
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            UIWindow *keyWindow = nil;
            
            if ([UIApplication sharedApplication].windows.count > 0) {
                // Find the key window without directly accessing keyWindow property
                NSArray *windows = [UIApplication sharedApplication].windows;
                for (UIWindow *window in windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
                
                // Fallback to the first window if no key window
                if (!keyWindow && windows.count > 0) {
                    keyWindow = windows[0];
                }
                
                if (keyWindow) {
                    rootViewController = keyWindow.rootViewController;
                }
            }
            #pragma clang diagnostic pop
        }
    }
    
    // Navigate to the top-most presented controller
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }
    
    return rootViewController;
}

// Add explicit function to enable/disable monitoring directly
EXPORT void setMonitoringEnabled(BOOL enabled) {
    NSLog(@"[DoorDashOrder_DEBUG] %@ monitoring explicitly", enabled ? @"Enabling" : @"Disabling");
    
    // Update in-memory state
    monitoringEnabled = enabled;
    
    // Set up timeout if we're enabling
    if (enabled) {
        disableMonitoringAfterTimeout();
    }
    
    NSLog(@"[DoorDashOrder_DEBUG] Monitoring is now %@", monitoringEnabled ? @"ENABLED" : @"DISABLED");
}

%group URLHooks

// Hook canOpenURL: to capture URLs in the apps
%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    if (isMonitoringEnabled()) {
        NSString *urlString = [url absoluteString];
        
        // Check for Uber URLs
        BOOL isUberURL = [urlString hasPrefix:@"uber:"] ||
                        [urlString containsString:@"ubercab"] || 
                        [urlString containsString:@"help.uber.com"];
                        
        // Only look for jobIds in Uber URLs - added security
        if (isUberURL) {
            BOOL hasJobId = [urlString containsString:@"jobId"];
            debugLogURL(@"canOpenURL", url, hasJobId);
        }
        
        // Check for DoorDash URLs
        BOOL isDoorDashURL = [urlString containsString:@"doordash.com"];
        if (isDoorDashURL) {
            debugLogDoorDashURL(@"canOpenURL", url);
        }
    } else {
        NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Monitoring is not enabled, skipping URL check");
    }
    
    // Call original implementation
    return %orig;
}

// Hook openURL: methods as well
- (BOOL)openURL:(NSURL *)url {
    if (isMonitoringEnabled()) {
        NSString *urlString = [url absoluteString];
        
        // Check for Uber URLs
        BOOL isUberURL = [urlString hasPrefix:@"uber:"] ||
                        [urlString containsString:@"ubercab"] || 
                        [urlString containsString:@"help.uber.com"];
                        
        // Only look for jobIds in Uber URLs - added security
        if (isUberURL) {
            BOOL hasJobId = [urlString containsString:@"jobId"];
            debugLogURL(@"openURL", url, hasJobId);
        }
        
        // Check for DoorDash URLs
        BOOL isDoorDashURL = [urlString containsString:@"doordash.com"];
        if (isDoorDashURL) {
            debugLogDoorDashURL(@"openURL", url);
        }
    } else {
        NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Monitoring is not enabled, skipping URL check");
    }
    
    // Call original implementation
    return %orig;
}

- (BOOL)openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options completionHandler:(void (^)(BOOL success))completion {
    if (isMonitoringEnabled()) {
        NSString *urlString = [url absoluteString];
        
        // Check for Uber URLs
        BOOL isUberURL = [urlString hasPrefix:@"uber:"] ||
                        [urlString containsString:@"ubercab"] || 
                        [urlString containsString:@"help.uber.com"];
                        
        // Only look for jobIds in Uber URLs - added security
        if (isUberURL) {
            BOOL hasJobId = [urlString containsString:@"jobId"];
            debugLogURL(@"openURL:options:completionHandler", url, hasJobId);
        }
        
        // Check for DoorDash URLs
        BOOL isDoorDashURL = [urlString containsString:@"doordash.com"];
        if (isDoorDashURL) {
            debugLogDoorDashURL(@"openURL:options:completionHandler", url);
        }
    } else {
        NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Monitoring is not enabled, skipping URL check");
    }
    
    // Call original implementation
    return %orig;
}

%end

// Hook LSApplicationWorkspace for URL handling
%hook LSApplicationWorkspace

- (BOOL)openURL:(NSURL *)url {
    if (isMonitoringEnabled()) {
        NSString *urlString = [url absoluteString];
        
        // Check for Uber URLs
        BOOL isUberURL = [urlString hasPrefix:@"uber:"] ||
                        [urlString containsString:@"ubercab"] || 
                        [urlString containsString:@"help.uber.com"];
                        
        // Only look for jobIds in Uber URLs - added security
        if (isUberURL) {
            BOOL hasJobId = [urlString containsString:@"jobId"];
            debugLogURL(@"LSApplicationWorkspace:openURL", url, hasJobId);
        }
        
        // Check for DoorDash URLs
        BOOL isDoorDashURL = [urlString containsString:@"doordash.com"];
        if (isDoorDashURL) {
            debugLogDoorDashURL(@"LSApplicationWorkspace:openURL", url);
        }
    } else {
        NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Monitoring is not enabled, skipping URL check");
    }
    
    return %orig;
}

%end

// Add NSURLSession hooks to capture network requests
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    if (isMonitoringEnabled()) {
        NSURL *url = request.URL;
        NSString *urlString = [url absoluteString];
        
        // Only process DoorDash URLs that likely contain order information
        if ([urlString containsString:@"doordash.com"]) {
            // Only log URLs that match specific patterns related to orders
            BOOL isOrderRelated = [urlString containsString:@"order_uuid"] || 
                                 [urlString containsString:@"v1/order-tracker"] ||
                                 [urlString containsString:@"order-tracker"] ||
                                 [urlString containsString:@"track.doordash.com"] ||
                                 [urlString containsString:@"post_checkout"] ||
                                 [urlString containsString:@"/orders/"] ||
                                 [urlString containsString:@"order_cart"];
                                 
            if (isOrderRelated) {
                NSLog(@"[DoorDashOrder_DEBUG] 🎯 Checking order-related URL: %@", urlString);
                debugLogDoorDashURL(@"NSURLSession:dataTaskWithRequest", url);
            }
            
            // Check for order_uuid in HTTP body only for POST requests
            if ([[request HTTPMethod] isEqualToString:@"POST"] && [request HTTPBody]) {
                NSString *bodyString = [[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding];
                if (bodyString && [bodyString containsString:@"order_uuid"]) {
                    NSLog(@"[DoorDashOrder_DEBUG] 📋 Found order_uuid in POST body");
                    // Process the body to extract order ID if needed
                }
            }
        }
    } else {
        // Log only once per 100 requests to reduce spam
        static int skippedCount = 0;
        if (skippedCount++ % 100 == 0) {
            NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Monitoring is not enabled, skipping URL checks");
        }
    }
    
    return %orig;
}

%end

// Add a special hook for forcing monitoring on for testing
%hook UIApplication

- (void)_sendMotionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    // Call original implementation first
    %orig;
    
    // Check if this is a shake motion (for enabling monitoring in debugging)
    if (motion == UIEventSubtypeMotionShake) {
        NSLog(@"[DoorDashOrder_DEBUG] 📱 Shake detected, toggling monitoring state for testing");
        
        // Toggle monitoring state
        BOOL currentState = isMonitoringEnabled();
        setMonitoringEnabled(!currentState);
        
        // Show UI feedback if possible
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"URL Monitoring" 
            message:[NSString stringWithFormat:@"Monitoring is now %@", 
                    isMonitoringEnabled() ? @"ENABLED" : @"DISABLED"]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        // Present the alert from the key window using modern approach (iOS 13+)
        UIViewController *topVC = nil;
        
        // Check iOS version for the appropriate method
        if (@available(iOS 13.0, *)) {
            NSSet *connectedScenes = [UIApplication sharedApplication].connectedScenes;
            for (UIScene *scene in connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *window in windowScene.windows) {
                        if (window.isKeyWindow) {
                            topVC = window.rootViewController;
                            break;
                        }
                    }
                    if (topVC) break;
                }
            }
        } else {
            // Fallback for iOS 12 and below
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            #pragma clang diagnostic pop
        }
        
        // Navigate to the topmost view controller
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

// Hook for radiosPreferencesDidChange notification
- (void)setRadiosPreference:(id)preferences {
    %orig;
    
    // Check airplane mode when radio preferences change
    BOOL airplaneMode = isAirplaneModeOn();
    
    if (airplaneMode) {
        NSLog(@"[DoorDashOrder_DEBUG] ✈️ Airplane mode detected via radiosPreference - enabling monitoring");
        setAirplaneModeActive(YES);
    }
}

%end

// Add a hook to automatically detect airplane mode changes
%hook UIDevice

- (void)setProximityMonitoringEnabled:(BOOL)enabled {
    %orig;
    
    // Check for airplane mode status when proximity changes
    // This is a heuristic approach as there's no direct notification for airplane mode
    static BOOL lastAirplaneMode = NO;
    BOOL currentAirplaneMode = isAirplaneModeOn();
    
    if (currentAirplaneMode != lastAirplaneMode) {
        lastAirplaneMode = currentAirplaneMode;
        
        if (currentAirplaneMode) {
            NSLog(@"[DoorDashOrder_DEBUG] ✈️ Airplane mode detected - enabling monitoring");
            setMonitoringEnabled(YES);
        }
    }
}

%end

%end // End URLHooks group

// Simple airplane mode detection - single method approach that only checks one system property
static BOOL isAirplaneModeOn(void) {
    // Make sure we don't run this too early
    if (!initialSetupComplete) return NO;
    
    // Use simple reachability check to detect airplane mode
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "8.8.8.8");
    if (!reachability) {
        return YES; // If we can't create the reachability object, assume offline
    }
    
    SCNetworkReachabilityFlags flags;
    BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    
    if (!success) {
        return YES; // If we can't get flags, assume offline
    }
    
    // Check if network is completely unreachable (likely airplane mode)
    BOOL isReachable = (flags & kSCNetworkReachabilityFlagsReachable);
    return !isReachable;
}

// Function to share airplane mode state between processes
static void setAirplaneModeActive(BOOL active) {
    // Get current time to add to file for uniqueness
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    
    if (active) {
        // Create a file to signify airplane mode is active with timestamp
        NSString *contentWithTimestamp = [NSString stringWithFormat:@"active-%f", timestamp];
        [contentWithTimestamp writeToFile:kAirplaneModeFileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        // Post notification to inform other processes
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                           CFSTR("com.weaponx.airplaneModeActive"),
                                           NULL, NULL, YES);
                                           
        // Enable monitoring in this process only if not already enabled
        if (!monitoringEnabled) {
            NSLog(@"[DoorDashOrder_DEBUG] ✈️ Setting monitoring enabled via airplane mode detection");
            setMonitoringEnabled(YES);
        } else {
            NSLog(@"[DoorDashOrder_DEBUG] ✈️ Monitoring already enabled");
        }
    } else {
        // Remove the file when airplane mode is disabled
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:kAirplaneModeFileName error:nil];
    }
}

// Callback for airplane mode changes
static void airplaneModeStatusChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // Another process notified us that airplane mode is active
    NSLog(@"[DoorDashOrder_DEBUG] ✈️ Received airplane mode notification - enabling monitoring");
    setMonitoringEnabled(YES);
}

// Helper functions
static BOOL isMonitoringEnabled(void) {
    // If another process detected airplane mode, enable monitoring
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:kAirplaneModeFileName]) {
        if (!monitoringEnabled) {
            NSLog(@"[DoorDashOrder_DEBUG] ✈️ Detected airplane mode file marker - enabling monitoring");
            setMonitoringEnabled(YES);
        }
    }
    
    // Return the in-memory state
    return monitoringEnabled;
}

// Independent timer to forcefully disable monitoring after a fixed time
static void disableMonitoringAfterTimeout(void) {
    NSLog(@"[DoorDashOrder_DEBUG] ⏱️ Setting up monitoring auto-disable timer for %d seconds", (int)kMonitoringMaxDuration);
    
    // Use global queue to ensure the timer fires even if app is backgrounded
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    // Using dispatch_after to automatically disable monitoring after the timeout period
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMonitoringMaxDuration * NSEC_PER_SEC)), queue, ^{
        NSLog(@"[DoorDashOrder_DEBUG] ⏱️ Auto-disable timer fired after %d seconds - disabling monitoring", (int)kMonitoringMaxDuration);
        monitoringEnabled = NO; // Simply disable monitoring in memory
        NSLog(@"[DoorDashOrder_DEBUG] 🔴 Monitoring disabled by timer");
        
        // Clean up the shared file but immediately check airplane mode again
        // This ensures we can re-enable if airplane mode is still active
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:kAirplaneModeFileName error:nil];
        
        // Check if airplane mode is still on after timeout - if so, restart monitoring
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), queue, ^{
            if (isAirplaneModeOn()) {
                NSLog(@"[DoorDashOrder_DEBUG] ✈️ Airplane mode still active after timeout - restarting monitoring");
                setAirplaneModeActive(YES);
            }
        });
    });
}

static void saveOrderID(NSString *orderID) {
    if (!orderID || orderID.length == 0) return;
    
    // Create URL scheme with the order ID and timestamp as parameters
    NSString *timestampStr = [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
    NSString *weaponXURLScheme = [NSString stringWithFormat:@"weaponx://store-uber-order?id=%@&timestamp=%@", 
                                  [orderID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                                  timestampStr];
    
    NSURL *weaponXURL = [NSURL URLWithString:weaponXURLScheme];
    
    if (weaponXURL) {
        // Attempt to open the URL scheme to pass data to the WeaponX app
        [[UIApplication sharedApplication] openURL:weaponXURL options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                // Fallback to NSUserDefaults if the URL scheme fails
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                
                // Create the new order entry
                NSDictionary *orderEntry = @{
                    @"orderID": orderID,
                    @"timestamp": [NSDate date]
                };
                
                // Load existing order IDs
                NSMutableArray *orderIDs = [[defaults objectForKey:kUberOrderIDsKey] mutableCopy];
                if (!orderIDs) {
                    orderIDs = [NSMutableArray array];
                }
                
                // Check if order ID already exists
                BOOL exists = NO;
                for (NSDictionary *entry in orderIDs) {
                    if ([entry[@"orderID"] isEqualToString:orderID]) {
                        exists = YES;
                        break;
                    }
                }
                
                // Only add if it doesn't exist
                if (!exists) {
                    [orderIDs insertObject:orderEntry atIndex:0]; // Add to top
                    
                    // Keep only the last 50 entries
                    if (orderIDs.count > 50) {
                        [orderIDs removeObjectsInRange:NSMakeRange(50, orderIDs.count - 50)];
                    }
                    
                    // Save back to NSUserDefaults with both keys for compatibility
                    [defaults setObject:orderIDs forKey:kUberOrderIDsKey];
                    [defaults setObject:orderIDs forKey:@"UberOrderData"]; // Also save to the old key
                    // No need to call synchronize
                }
            }
        }];
    }
    
    // Post Darwin notification to inform other processes that an order was captured
    // This is still useful even with URL scheme, as it might trigger UI updates
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)@"com.weaponx.uberOrderCaptured",
                                         NULL, NULL, YES);
}

static NSString *extractJobIDFromURL(NSURL *url) {
    if (!url) return @"";
    NSString *urlString = [url absoluteString];
    
    // First check if it contains a jobId directly in the URL parameters
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"jobId"]) {
            return item.value;
        }
    }
    
    // Handle case where URL is nested inside another URL parameter (like 'url=...')
    // This is common in Uber's web view navigation pattern
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"url"]) {
            // Decode the nested URL
            NSString *nestedURLString = [item.value stringByRemovingPercentEncoding];
            if (nestedURLString) {
                // Try to parse the nested URL properly
                NSURL *nestedURL = [NSURL URLWithString:nestedURLString];
                if (nestedURL) {
                    NSURLComponents *nestedComponents = [NSURLComponents componentsWithURL:nestedURL resolvingAgainstBaseURL:NO];
                    for (NSURLQueryItem *nestedItem in nestedComponents.queryItems) {
                        if ([nestedItem.name isEqualToString:@"jobId"]) {
                            return nestedItem.value;
                        }
                    }
                }
                
                // If we couldn't parse the nested URL, try regex as a fallback
                if ([nestedURLString containsString:@"jobId="]) {
                    NSString *pattern = @"jobId=([^&]+)";
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
                    NSTextCheckingResult *match = [regex firstMatchInString:nestedURLString options:0 range:NSMakeRange(0, nestedURLString.length)];
                    
                    if (match && match.numberOfRanges > 1) {
                        NSRange range = [match rangeAtIndex:1];
                        NSString *value = [nestedURLString substringWithRange:range];
                        // URL decode the value if needed
                        NSString *jobId = [value stringByRemovingPercentEncoding];
                        return jobId;
                    }
                }
            }
        }
    }
    
    // Final fallback - direct regex on the original URL string
    // This catches any format we haven't explicitly handled above
    if ([urlString containsString:@"jobId="]) {
        NSString *pattern = @"jobId=([^&]+)";
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
        
        if (match && match.numberOfRanges > 1) {
            NSRange range = [match rangeAtIndex:1];
            NSString *value = [urlString substringWithRange:range];
            // URL decode the value
            NSString *jobId = [value stringByRemovingPercentEncoding];
            return jobId;
        }
    }
    
    return @"";
}

static void debugLogURL(NSString *source, NSURL *url, BOOL hasJobId) {
    if (!url) return;
    
    if (hasJobId) {
        NSString *jobId = extractJobIDFromURL(url);
        if (jobId.length > 0) {
            saveOrderID(jobId);
        }
    }
}

static void debugLogDoorDashURL(NSString *source, NSURL *url) {
    if (!url) {
        NSLog(@"[DoorDashOrder_DEBUG] ❌ Null URL passed to debugLogDoorDashURL from %@", source);
        return;
    }
    
    NSLog(@"[DoorDashOrder_DEBUG] 🔎 Checking URL from %@: %@", source, url);
    
    NSString *orderID = extractDoorDashOrderIDFromURL(url);
    
    if (orderID && orderID.length > 0) {
        NSLog(@"[DoorDashOrder] 🍕 Captured DoorDash order ID: %@ from %@", orderID, source);
        saveDoorDashOrderID(orderID);
    } else {
        NSLog(@"[DoorDashOrder_DEBUG] ❓ No DoorDash order ID found in URL from %@", source);
    }
}

static NSString *extractDoorDashOrderIDFromURL(NSURL *url) {
    NSLog(@"[DoorDashOrder_DEBUG] 🔍 Analyzing URL: %@", url);
    
    if (!url) {
        NSLog(@"[DoorDashOrder_DEBUG] ⚠️ URL is nil");
        return nil;
    }
    
    NSString *urlString = [url absoluteString];
    NSLog(@"[DoorDashOrder_DEBUG] 🔗 URL string: %@", urlString);
    
    // Check for order_uuid parameter
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    
    if (!components) {
        NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Failed to create URL components");
        return nil;
    }
    
    if (components.queryItems) {
        NSLog(@"[DoorDashOrder_DEBUG] 📋 Query items: %@", components.queryItems);
        
        for (NSURLQueryItem *item in components.queryItems) {
            NSLog(@"[DoorDashOrder_DEBUG] 🔖 Query param: %@ = %@", item.name, item.value);
            if ([item.name isEqualToString:@"order_uuid"]) {
                NSLog(@"[DoorDashOrder_DEBUG] 🎯 Found order_uuid: %@", item.value);
                return item.value;
            }
        }
    } else {
        NSLog(@"[DoorDashOrder_DEBUG] ℹ️ No query items in URL");
    }
    
    // Check for URL pattern in format https://track.doordash.com/share/{orderID}/track
    if ([urlString containsString:@"track.doordash.com/share/"]) {
        NSLog(@"[DoorDashOrder_DEBUG] 🔍 URL matches track.doordash.com/share/ pattern");
        NSString *pattern = @"track\\.doordash\\.com/share/([^/]+)/track";
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
        
        if (match && match.numberOfRanges > 1) {
            NSRange range = [match rangeAtIndex:1];
            NSString *orderID = [urlString substringWithRange:range];
            NSLog(@"[DoorDashOrder_DEBUG] 🎯 Extracted orderID from URL path: %@", orderID);
            return orderID;
        } else {
            NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Failed to extract orderID from URL path");
        }
    }
    
    // Check for order-tracker endpoint with order_uuid in URL
    if ([urlString containsString:@"order-tracker"]) {
        NSLog(@"[DoorDashOrder_DEBUG] 🔍 URL contains order-tracker");
        // Look for order_uuid in URL parameters
        if ([urlString containsString:@"order_uuid="]) {
            NSLog(@"[DoorDashOrder_DEBUG] 🔍 URL contains order_uuid= parameter");
            NSString *pattern = @"order_uuid=([^&]+)";
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
            
            if (match && match.numberOfRanges > 1) {
                NSRange range = [match rangeAtIndex:1];
                NSString *value = [urlString substringWithRange:range];
                NSString *orderID = [value stringByRemovingPercentEncoding];
                NSLog(@"[DoorDashOrder_DEBUG] 🎯 Extracted orderID from order_uuid parameter: %@", orderID);
                return orderID;
            } else {
                NSLog(@"[DoorDashOrder_DEBUG] ⚠️ Failed to extract orderID from order_uuid parameter");
            }
        }
    }
    
    NSLog(@"[DoorDashOrder_DEBUG] ❌ No order ID found in URL");
    return nil;
}

static void saveDoorDashOrderID(NSString *orderID) {
    if (!orderID || orderID.length == 0) return;
    
    // Log the DoorDash order ID being saved
    NSLog(@"[DoorDashOrder] 🔄 Saving DoorDash order ID: %@", orderID);
    NSLog(@"[DoorDashOrder] 📌 Order URL would be: https://track.doordash.com/share/%@/track", orderID);
    
    // Create URL scheme with the order ID and timestamp as parameters
    NSString *timestampStr = [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
    NSString *weaponXURLScheme = [NSString stringWithFormat:@"weaponx://store-doordash-order?id=%@&timestamp=%@", 
                                  [orderID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                                  timestampStr];
    
    NSURL *weaponXURL = [NSURL URLWithString:weaponXURLScheme];
    
    // Create the new order entry for NSUserDefaults fallback
    NSDate *timestamp = [NSDate date];
    NSDictionary *orderEntry = @{
        @"orderID": orderID,
        @"timestamp": timestamp,
        @"type": @"doordash"
    };
    
    // IMPORTANT: Save to NSUserDefaults BEFORE attempting URL scheme
    // This way the data is always saved, even if URL opening fails
    NSLog(@"[DoorDashOrder] 💾 Saving to NSUserDefaults first as fallback");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Load existing order IDs
    NSMutableArray *orderIDs = [[defaults objectForKey:kDoorDashOrderIDsKey] mutableCopy];
    if (!orderIDs) {
        orderIDs = [NSMutableArray array];
        NSLog(@"[DoorDashOrder] 📋 Created new order ID array in NSUserDefaults");
    }
    
    // Check if order ID already exists
    BOOL exists = NO;
    for (NSDictionary *entry in orderIDs) {
        if ([entry[@"orderID"] isEqualToString:orderID]) {
            exists = YES;
            break;
        }
    }
    
    // Only add if it doesn't exist
    if (!exists) {
        [orderIDs insertObject:orderEntry atIndex:0]; // Add to top
        
        // Keep only the last 50 entries
        if (orderIDs.count > 50) {
            [orderIDs removeObjectsInRange:NSMakeRange(50, orderIDs.count - 50)];
        }
        
        // Save back to NSUserDefaults
        [defaults setObject:orderIDs forKey:kDoorDashOrderIDsKey];
        [defaults synchronize]; // Force synchronize to ensure it's saved
        NSLog(@"[DoorDashOrder] 💾 Saved DoorDash order ID to NSUserDefaults");
    } else {
        NSLog(@"[DoorDashOrder] 🔄 DoorDash order ID already exists in NSUserDefaults, skipping");
    }
    
    // Now try URL scheme approach for immediate UI update
    if (weaponXURL) {
        NSLog(@"[DoorDashOrder] 🔗 Created URL scheme: %@", weaponXURLScheme);
        
        // Attempt to open the URL scheme to pass data to the WeaponX app
        [[UIApplication sharedApplication] openURL:weaponXURL options:@{} completionHandler:^(BOOL success) {
            if (success) {
                NSLog(@"[DoorDashOrder] ✅ Successfully sent DoorDash order ID to WeaponX app via URL scheme");
            } else {
                NSLog(@"[DoorDashOrder] ⚠️ Failed to open URL scheme, but order is already saved in NSUserDefaults");
            }
        }];
    } else {
        NSLog(@"[DoorDashOrder] ❌ Failed to create URL scheme for DoorDash order ID");
    }
    
    // Post Darwin notification to inform other processes that an order was captured
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)@"com.weaponx.doorDashOrderCaptured",
                                         NULL, NULL, YES);
    NSLog(@"[DoorDashOrder] 📡 Posted Darwin notification for DoorDash order ID");
}

// This function will be called after a delay to perform network-dependent setup
static void performDelayedSetup(void) {
    // Set the flag so we know setup is complete
    initialSetupComplete = YES;
    
    NSLog(@"[DoorDashOrder_DEBUG] 🚀 Performing delayed setup for network monitoring");
    
    // Listen for airplane mode notifications from other processes
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                  NULL,
                                  airplaneModeStatusChanged,
                                  CFSTR("com.weaponx.airplaneModeActive"),
                                  NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);
    
    // Check if we should start with monitoring enabled
    // Check airplane mode directly
    BOOL airplaneMode = isAirplaneModeOn();
    
    if (airplaneMode) {
        NSLog(@"[DoorDashOrder_DEBUG] ✈️ Started with Airplane mode ON - enabling monitoring");
        setAirplaneModeActive(YES);
    }
    
    // Create a permanent timer to check for airplane mode changes
    // This ensures we can always re-detect airplane mode even after the timeout
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        BOOL currentAirplaneMode = isAirplaneModeOn();
        if (currentAirplaneMode) {
            NSLog(@"[DoorDashOrder_DEBUG] ✈️ Periodic check detected Airplane mode ON");
            setAirplaneModeActive(YES);
        }
    });
    
    // Store the timer in a static variable to prevent it from being deallocated
    static dispatch_source_t staticTimer = nil;
    if (staticTimer) {
        dispatch_source_cancel(staticTimer);
    }
    staticTimer = timer;
    
    dispatch_resume(timer);
    
    NSLog(@"[DoorDashOrder_DEBUG] ✅ Delayed setup complete");
}

%ctor {
    // Only hook in the Uber or DoorDash applications
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [[[NSProcessInfo processInfo] processName] lowercaseString];
    
    // Define exact matches for both Uber and DoorDash app processes
    NSArray *allowedBundleIDs = @[
        @"com.ubercab.UberClient",
        @"com.ubercab.UberClient.widgetextension",
        @"com.doordash.consumer",
        @"com.dd.doordash",
        @"com.doordash.dasher",
        @"doordash.DoorDashConsumer",
        @"doordash.DoorDashConsumer.LiveActivity" // Add LiveActivity extension
    ];
    
    // Primary check - exact bundle ID match
    BOOL isTargetApp = [allowedBundleIDs containsObject:bundleID];
    
    // Secondary check - process name match
    BOOL isHelixProcess = [processName isEqualToString:@"helix"]; // Uber's internal app name
    BOOL isDoorDashProcess = [processName containsString:@"doordash"] || [processName containsString:@"dasher"];
    
    // Additional safety check for process names
    if ((isHelixProcess || isDoorDashProcess) && !isTargetApp) {
        NSString *execPath = [[[NSBundle mainBundle] executablePath] lowercaseString];
        if (![execPath containsString:@"uber"] && ![execPath containsString:@"doordash"]) {
            isHelixProcess = NO;
            isDoorDashProcess = NO;
        }
    }
    
    // Only initialize hooks if we're 100% sure this is the target app
    if (isTargetApp || isHelixProcess || isDoorDashProcess) {
        // Initialize our hooks
        %init(URLHooks);
        
        NSLog(@"[DoorDashOrder_DEBUG] 🚀 Initialized DoorDash/Uber URL hooks for bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
        NSLog(@"[DoorDashOrder_DEBUG] 👀 Initial monitoring state: %@", monitoringEnabled ? @"ENABLED" : @"DISABLED");
        
        // Delay the network-dependent setup to avoid crashes during app launch
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            performDelayedSetup();
        });
    }
} 