#import "IPMonitorService.h"
#import "IPStatusViewController.h"
#import "ProjectXLogging.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>
#import <UIKit/UIKit.h>

@interface IPMonitorService ()

@property (nonatomic, assign) BOOL isMonitoring;
@property (nonatomic, strong) NSTimer *monitoringTimer;
@property (nonatomic, strong) NSString *lastKnownIP;
@property (nonatomic, strong) NSUserDefaults *securitySettings;
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, assign) NSTimeInterval lastCheckTime;
@property (nonatomic, assign) NSTimeInterval adaptiveInterval;
@property (nonatomic, assign) NSInteger checkCount;
@property (nonatomic, assign) NSInteger toggleCount;
@property (nonatomic, assign) NSInteger consensusCount;

@end

@implementation IPMonitorService

static IPMonitorService *sharedInstance = nil;

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[IPMonitorService alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        PXLog(@"[IPMonitor] Initializing IP Monitor Service");
        self.securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        self.isMonitoring = NO;
        self.monitoringTimer = nil;
        self.lastKnownIP = [self loadLastKnownIP];
        self.reachability = NULL;
        self.lastCheckTime = 0;
        self.adaptiveInterval = 60.0; // Start with 60 seconds
        self.checkCount = 0;
        self.toggleCount = 0;
        self.consensusCount = 0;
        
        // Load cached IP if available
        NSString *cachedIP = [self loadCachedIP];
        NSDate *cacheTime = [self loadCacheTime];
        
        // If cache is less than 5 minutes old, use it
        if (cachedIP && cacheTime && [[NSDate date] timeIntervalSinceDate:cacheTime] < 300) {
            self.lastKnownIP = cachedIP;
            PXLog(@"[IPMonitor] Using cached IP: %@", cachedIP);
        }
        
        // Setup network monitoring
        [self setupNetworkMonitoring];
        
        // Start monitoring if enabled
        if ([self isIPMonitoringEnabled]) {
            PXLog(@"[IPMonitor] IP Monitoring enabled at startup");
            [self startMonitoring];
        } else {
            PXLog(@"[IPMonitor] IP Monitoring disabled at startup");
        }
    }
    return self;
}

- (void)dealloc {
    PXLog(@"[IPMonitor] Deallocating IP Monitor Service");
    [self stopMonitoring];
    if (self.reachability) {
        SCNetworkReachabilityUnscheduleFromRunLoop(self.reachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFRelease(self.reachability);
        self.reachability = NULL;
    }
}

- (BOOL)isIPMonitoringEnabled {
    self.toggleCount++;
    BOOL enabled = [self.securitySettings boolForKey:@"ipMonitorEnabled"];
    if (self.toggleCount % 10 == 0) {
        PXLog(@"[IPMonitor] Monitoring enabled status checked %ld times, current: %@", (long)self.toggleCount, enabled ? @"YES" : @"NO");
    }
    return enabled;
}

- (NSString *)loadLastKnownIP {
    NSString *ip = [self.securitySettings stringForKey:@"lastKnownIP"];
    PXLog(@"[IPMonitor] Loading last known IP: %@", ip ?: @"None");
    return ip;
}

- (void)saveLastKnownIP:(NSString *)ip {
    if (ip) {
        PXLog(@"[IPMonitor] Saving last known IP: %@", ip);
        [self.securitySettings setObject:ip forKey:@"lastKnownIP"];
        [self.securitySettings synchronize];
        
        // Also save to cache with timestamp
        [self saveIPToCache:ip];
    }
}



- (void)saveIPToCache:(NSString *)ip {
    [self.securitySettings setObject:ip forKey:@"CachedIP"];
    [self.securitySettings setObject:[NSDate date] forKey:@"IPCacheTime"];
    [self.securitySettings synchronize];
}

- (NSString *)loadCachedIP {
    return [self.securitySettings stringForKey:@"CachedIP"];
}

- (NSDate *)loadCacheTime {
    return [self.securitySettings objectForKey:@"IPCacheTime"];
}

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    IPMonitorService *service = (__bridge IPMonitorService *)info;
    [service handleReachabilityChange:flags];
}

- (void)setupNetworkMonitoring {
    // Create a zero address to monitor all network interfaces
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    
    // Create reachability reference
    self.reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    
    if (self.reachability) {
        // Set callback
        SCNetworkReachabilityContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        if (SCNetworkReachabilitySetCallback(self.reachability, ReachabilityCallback, &context)) {
            // Schedule on main run loop
            SCNetworkReachabilityScheduleWithRunLoop(self.reachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        }
    }
}

- (void)handleReachabilityChange:(SCNetworkReachabilityFlags)flags {
    BOOL isReachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL isWWAN = (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
    
    PXLog(@"[IPMonitor] Network reachability changed - Reachable: %@, WWAN: %@, Monitoring: %@", 
          isReachable ? @"YES" : @"NO",
          isWWAN ? @"YES" : @"NO",
          self.isMonitoring ? @"YES" : @"NO");
    
    if (isReachable && self.isMonitoring) {
        // Only check IP when network becomes reachable and monitoring is active
        PXLog(@"[IPMonitor] Network became reachable, checking for IP change");
        [self checkForIPChange];
    }
}

- (void)startMonitoring {
    if (self.isMonitoring) {
        PXLog(@"[IPMonitor] Start monitoring called but already monitoring");
        return;
    }
    
    PXLog(@"[IPMonitor] Starting IP monitoring");
    self.isMonitoring = YES;
    
    // Get initial IP
    [self fetchCurrentIPWithConsensus:^(NSString *ip, NSError *error) {
        if (ip) {
            PXLog(@"[IPMonitor] Initial IP fetch successful: %@", ip);
            self.lastKnownIP = ip;
            [self saveLastKnownIP:ip];
        } else if (error) {
            PXLogError(error, @"IPMonitor initial IP fetch");
        }
    }];
    
    // Start adaptive polling
    [self startAdaptivePolling];
}

- (void)stopMonitoring {
    if (!self.isMonitoring) {
        PXLog(@"[IPMonitor] Stop monitoring called but not currently monitoring");
        return;
    }
    
    PXLog(@"[IPMonitor] Stopping IP monitoring");
    self.isMonitoring = NO;
    
    // Invalidate timer
    if (self.monitoringTimer) {
        [self.monitoringTimer invalidate];
        self.monitoringTimer = nil;
        PXLog(@"[IPMonitor] Monitoring timer invalidated");
    }
}

- (BOOL)isMonitoring {
    BOOL active = _isMonitoring;
    BOOL enabled = [self isIPMonitoringEnabled];
    return active && enabled;
}

- (void)startAdaptivePolling {
    // Cancel existing timer if any
    if (self.monitoringTimer) {
        [self.monitoringTimer invalidate];
        self.monitoringTimer = nil;
    }
    
    PXLog(@"[IPMonitor] Starting adaptive polling with interval: %.1f seconds", self.adaptiveInterval);
    
    // Create a new timer with the current adaptive interval
    self.monitoringTimer = [NSTimer scheduledTimerWithTimeInterval:self.adaptiveInterval 
                                                          target:self 
                                                        selector:@selector(adaptiveCheckForIPChange:) 
                                                        userInfo:nil 
                                                         repeats:YES];
    
    // Add to common run loop modes to ensure it runs even during scrolling
    [[NSRunLoop mainRunLoop] addTimer:self.monitoringTimer forMode:NSRunLoopCommonModes];
    PXLog(@"[IPMonitor] Timer added to main run loop with common modes");
}

- (void)adaptiveCheckForIPChange:(NSTimer *)timer {
    static NSString *lastCheckedIP = nil;
    
    // Implement time-based throttling to prevent excessive checks
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastCheckTime < 5.0) { // Minimum 5 seconds between checks
        return;
    }
    
    self.lastCheckTime = now;
    self.checkCount++;
    
    if (self.checkCount % 5 == 0) {
        PXLog(@"[IPMonitor] Adaptive check #%ld for IP change, current interval: %.1f seconds", 
              (long)self.checkCount, self.adaptiveInterval);
    }
    
    [self fetchCurrentIPWithConsensus:^(NSString *ip, NSError *error) {
        if (ip) {
            if (lastCheckedIP && ![lastCheckedIP isEqualToString:ip]) {
                // IP changed, decrease interval (but not below 30 seconds)
                self.adaptiveInterval = MAX(30.0, self.adaptiveInterval * 0.5);
                
                PXLog(@"[IPMonitor] IP CHANGED from %@ to %@, decreasing check interval to %.1f seconds", 
                      lastCheckedIP, ip, self.adaptiveInterval);
                
                // Show alert for IP change
                [self showIPChangeAlertWithOldIP:lastCheckedIP newIP:ip];
                
                // Save the new IP
                self.lastKnownIP = ip;
                [self saveLastKnownIP:ip];
            } else if (lastCheckedIP && [lastCheckedIP isEqualToString:ip]) {
                // IP unchanged, increase interval (but not above 300 seconds)
                self.adaptiveInterval = MIN(300.0, self.adaptiveInterval * 1.5);
                
                if (self.checkCount % 5 == 0) {
                    PXLog(@"[IPMonitor] IP unchanged (%@), increasing check interval to %.1f seconds", 
                          ip, self.adaptiveInterval);
                }
            }
            
            // Update timer interval
            [self startAdaptivePolling];
            
            // Store the current IP for next comparison
            lastCheckedIP = ip;
        }
    }];
}

- (void)checkForIPChange {
    // Implement time-based throttling to prevent excessive checks
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastCheckTime < 5.0) { // Minimum 5 seconds between checks
        return;
    }
    
    self.lastCheckTime = now;
    self.checkCount++;
    
    PXLog(@"[IPMonitor] Manual check for IP change triggered by network change");
    
    [self fetchCurrentIPWithConsensus:^(NSString *ip, NSError *error) {
        if (ip) {
            PXLog(@"[IPMonitor] IP fetch result: %@, previous IP: %@", ip, self.lastKnownIP);
            if (self.lastKnownIP && ![self.lastKnownIP isEqualToString:ip]) {
                PXLog(@"[IPMonitor] IP change detected during manual check: %@ -> %@", self.lastKnownIP, ip);
                [self showIPChangeAlertWithOldIP:self.lastKnownIP newIP:ip];
                self.lastKnownIP = ip;
                [self saveLastKnownIP:ip];
            }
        } else if (error) {
            PXLogError(error, @"IPMonitor manual IP check");
        }
    }];
}

- (void)fetchCurrentIPWithConsensus:(void (^)(NSString *ip, NSError *error))completion {
    PXLog(@"[IPMonitor] Starting IP fetch with consensus from multiple services");
    
    // Define the services to check - prioritize the fastest ones
    NSArray *services = @[
        @{@"url": @"https://ifconfig.me/ip", @"isJSON": @NO},
        @{@"url": @"https://api.myip.com", @"isJSON": @YES, @"key": @"ip"},
        @{@"url": @"http://ip-api.com/json", @"isJSON": @YES, @"key": @"query"}
    ];
    
    // Create a dictionary to count occurrences of each IP
    NSMutableDictionary *ipCounts = [NSMutableDictionary dictionary];
    NSMutableArray *errors = [NSMutableArray array];
    
    PXLog(@"[IPMonitor] Querying %lu IP services", (unsigned long)services.count);
    
    // Create a dispatch group to track all requests
    dispatch_group_t group = dispatch_group_create();
    
    // Create a serial queue for thread safety
    dispatch_queue_t queue = dispatch_queue_create("com.yourapp.ipconsensus", DISPATCH_QUEUE_SERIAL);
    
    // Use a shared session configuration with optimized settings
    static NSURLSessionConfiguration *sharedConfig = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        sharedConfig.timeoutIntervalForRequest = 8.0;  // 8 seconds timeout
        sharedConfig.timeoutIntervalForResource = 20.0; // 20 seconds resource timeout
        sharedConfig.HTTPMaximumConnectionsPerHost = 3; // Limit concurrent connections
    });
    
    // Create a shared session
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sharedConfig];
    
    // Check each service
    for (NSDictionary *service in services) {
        dispatch_group_enter(group);
        
        [self fetchIPFromService:service[@"url"] 
                         isJSON:[service[@"isJSON"] boolValue] 
                           key:service[@"key"]
                     withSession:session
                     completion:^(NSString *ip, NSError *error) {
            dispatch_async(queue, ^{
                if (ip) {
                    // Increment count for this IP
                    NSNumber *count = ipCounts[ip];
                    if (count) {
                        ipCounts[ip] = @([count integerValue] + 1);
                    } else {
                        ipCounts[ip] = @1;
                    }
                } else if (error) {
                    [errors addObject:error];
                }
                
                dispatch_group_leave(group);
            });
        }];
    }
    
    // When all requests complete, find the most common IP
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // Find the IP with the highest count
        NSString *mostCommonIP = nil;
        NSInteger highestCount = 0;
        
        PXLog(@"[IPMonitor] All IP services responded, analyzing results");
        
        for (NSString *ip in ipCounts) {
            NSInteger count = [ipCounts[ip] integerValue];
            if (count > highestCount) {
                highestCount = count;
                mostCommonIP = ip;
            }
        }
        
        // If we have a consensus (at least 2 services returned the same IP)
        if (highestCount >= 2) {
            self.consensusCount++;
            PXLog(@"[IPMonitor] IP consensus reached (%ld services agree): %@", (long)highestCount, mostCommonIP);
            completion(mostCommonIP, nil);
        } else {
            // No consensus, use the first successful result if available
            if (mostCommonIP) {
                PXLog(@"[IPMonitor] No consensus reached, using first result: %@", mostCommonIP);
                completion(mostCommonIP, nil);
            } else {
                // All services failed
                PXLog(@"[IPMonitor] ERROR: All IP services failed, %lu errors", (unsigned long)errors.count);
                NSError *consensusError = [NSError errorWithDomain:@"com.yourapp.ipconsensus" 
                                                             code:1001 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"All IP services failed", 
                                                                    @"underlyingErrors": errors}];
                completion(nil, consensusError);
            }
        }
    });
}

- (void)fetchIPFromService:(NSString *)urlString 
                    isJSON:(BOOL)isJSON 
                      key:(NSString *)jsonKey 
                withSession:(NSURLSession *)session
                completion:(void (^)(NSString *ip, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    PXLog(@"[IPMonitor] Fetching IP from service: %@", urlString);
    
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            PXLog(@"[IPMonitor] Error fetching from %@: %@", urlString, error.localizedDescription);
            completion(nil, error);
            return;
        }
        
        if (isJSON) {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) {
                completion(nil, jsonError);
                return;
            }
            
            NSString *ip = json[jsonKey];
            if (!ip || ip.length == 0) {
                PXLog(@"[IPMonitor] IP not found in JSON response from %@", urlString);
                NSError *missingError = [NSError errorWithDomain:@"com.yourapp.ipconsensus" 
                                                           code:1002 
                                                       userInfo:@{NSLocalizedDescriptionKey: @"IP not found in JSON response"}];
                completion(nil, missingError);
                return;
            }
            
            PXLog(@"[IPMonitor] Successfully fetched IP from %@: %@", urlString, ip);
            completion(ip, nil);
        } else {
            NSString *ip = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            ip = [ip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            if (!ip || ip.length == 0) {
                PXLog(@"[IPMonitor] Empty IP response from %@", urlString);
                NSError *emptyError = [NSError errorWithDomain:@"com.yourapp.ipconsensus" 
                                                          code:1003 
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Empty IP response"}];
                completion(nil, emptyError);
                return;
            }
            
            PXLog(@"[IPMonitor] Successfully fetched IP from %@: %@", urlString, ip);
            completion(ip, nil);
        }
    }];
    
    [task resume];
}

- (void)showIPChangeAlertWithOldIP:(NSString *)oldIP newIP:(NSString *)newIP {
    PXLog(@"[IPMonitor] Attempting to show IP change alert: %@ -> %@", oldIP, newIP);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IP Address Changed"
                                                                     message:[NSString stringWithFormat:@"Your IP address has changed from %@ to %@", oldIP, newIP]
                                                              preferredStyle:UIAlertControllerStyleAlert];
        
        // Add "Check New IP" button
        [alert addAction:[UIAlertAction actionWithTitle:@"Check New IP" 
                                                 style:UIAlertActionStyleDefault 
                                               handler:^(UIAlertAction * _Nonnull action) {
            // Create and present the IPStatusViewController
            IPStatusViewController *ipStatusVC = [[IPStatusViewController alloc] init];
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:ipStatusVC];
            
            // Find the top view controller to present the alert
            UIViewController *topVC = [self topViewController];
            if (topVC) {
                [topVC presentViewController:navController animated:YES completion:nil];
            }
        }]];
        
        // Add "Turn OFF IP Monitoring" button
        [alert addAction:[UIAlertAction actionWithTitle:@"Turn OFF IP Monitoring" 
                                                 style:UIAlertActionStyleDestructive 
                                               handler:^(UIAlertAction * _Nonnull action) {
            // Disable IP monitoring
            [self.securitySettings setBool:NO forKey:@"ipMonitorEnabled"];
            [self.securitySettings synchronize];
            
            // Stop the monitoring service
            [self stopMonitoring];
            
            // Show confirmation alert
            UIAlertController *confirmationAlert = [UIAlertController alertControllerWithTitle:@"IP Monitoring Disabled"
                                                                                     message:@"IP monitoring has been turned off. You will no longer receive alerts about IP changes."
                                                                              preferredStyle:UIAlertControllerStyleAlert];
            
            [confirmationAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            
            // Find the top view controller to present the confirmation alert
            UIViewController *topVC = [self topViewController];
            if (topVC) {
                [topVC presentViewController:confirmationAlert animated:YES completion:nil];
            }
        }]];
        
        // Add "OK" button
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        // Find the top view controller to present the alert
        UIViewController *topVC = [self topViewController];
        if (topVC) {
            PXLog(@"[IPMonitor] Presenting IP change alert on view controller: %@", NSStringFromClass([topVC class]));
            [topVC presentViewController:alert animated:YES completion:^{
                PXLog(@"[IPMonitor] IP change alert presented successfully");
            }];
        } else {
            PXLog(@"[IPMonitor] ERROR: Could not find top view controller to present IP change alert");
        }
    });
}

- (UIViewController *)topViewController {
    PXLog(@"[IPMonitor] Finding top view controller for alert presentation");
    // Modern approach for iOS 13+ that works with multiple scenes
    UIWindow *window = nil;
    
    // Get the key window for iOS 15+
    NSSet<UIScene *> *scenes = [[UIApplication sharedApplication] connectedScenes];
    for (UIScene *scene in scenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            // Try to find the key window
            for (UIWindow *w in windowScene.windows) {
                if (w.isKeyWindow) {
                    window = w;
                    break;
                }
            }
            // If no key window found, use the first window
            if (!window && windowScene.windows.count > 0) {
                window = windowScene.windows.firstObject;
            }
            break;
        }
    }
    
    // If no window found, try to get any window from any scene
    if (!window) {
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.windows.count > 0) {
                    window = windowScene.windows.firstObject;
                    break;
                }
            }
        }
    }
    
    // If still no window, return nil
    if (!window) {
        PXLog(@"[IPMonitor] ERROR: No window found for alert presentation");
        return nil;
    }
    
    PXLog(@"[IPMonitor] Found window for alert presentation: %@", window);
    
    return [self topViewControllerWithRootViewController:window.rootViewController];
}

- (UIViewController *)topViewControllerWithRootViewController:(UIViewController *)rootViewController {
    if (!rootViewController) {
        PXLog(@"[IPMonitor] ERROR: Root view controller is nil");
        return nil;
    }
    
    PXLog(@"[IPMonitor] Finding top view controller from root: %@", NSStringFromClass([rootViewController class]));
    
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)rootViewController;
        return [self topViewControllerWithRootViewController:tabBarController.selectedViewController];
    }
    
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController;
        return [self topViewControllerWithRootViewController:navigationController.visibleViewController];
    }
    
    if (rootViewController.presentedViewController) {
        UIViewController *presentedViewController = rootViewController.presentedViewController;
        return [self topViewControllerWithRootViewController:presentedViewController];
    }
    
    return rootViewController;
}

@end
