#import "URLMonitor.h"
#import "UberOrderViewController.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

// Use the same key as in UberURLHooks.x
static BOOL isMonitoringEnabled = NO; // Default to disabled
static NSString * const kMonitoringEnabledKey = @"UberMonitoringEnabled";
static NSTimer *autoDisableTimer = nil;
static NSTimer *periodicNetworkCheckTimer = nil;
static NSDate *monitoringStartTime = nil;
static NSTimeInterval monitoringDuration = 180; // 3 minutes in seconds
static BOOL monitoringExplicitlyDisabled = NO; // Track when timer has explicitly disabled monitoring

@interface URLMonitor()
@property (nonatomic, assign) SCNetworkReachabilityRef reachabilityRef;
@end

@implementation URLMonitor

+ (instancetype)sharedInstance {
    static URLMonitor *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[URLMonitor alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Create reachability reference for monitoring
        struct sockaddr_in zeroAddress;
        bzero(&zeroAddress, sizeof(zeroAddress));
        zeroAddress.sin_len = sizeof(zeroAddress);
        zeroAddress.sin_family = AF_INET;
        
        _reachabilityRef = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    }
    return self;
}

- (void)dealloc {
    // Clean up reachability
    if (_reachabilityRef) {
        SCNetworkReachabilityUnscheduleFromRunLoop(_reachabilityRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFRelease(_reachabilityRef);
    }
}

+ (void)setupNetworkMonitoring {
    // Get shared instance to initialize reachability
    URLMonitor *monitor = [URLMonitor sharedInstance];
    
    // Set up callback context
    SCNetworkReachabilityContext context = {0, (__bridge void *)monitor, NULL, NULL, NULL};
    
    // Set callback function
    if (monitor.reachabilityRef) {
        SCNetworkReachabilitySetCallback(monitor.reachabilityRef, NetworkReachabilityCallback, &context);
        SCNetworkReachabilityScheduleWithRunLoop(monitor.reachabilityRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    }
    
    // Check initial state immediately
    [self checkNetworkStatus];
    
    // Set up periodic check every 10 seconds
    if (periodicNetworkCheckTimer) {
        [periodicNetworkCheckTimer invalidate];
    }
    
    periodicNetworkCheckTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                                 target:self
                                                               selector:@selector(checkNetworkStatus)
                                                               userInfo:nil
                                                                repeats:YES];
}

// Check current network status manually
+ (void)checkNetworkStatus {
    BOOL isConnected = [self isNetworkConnected];
    
    // Always notify the Uber app of current status
    // This ensures Uber app hooks are always synced with our state
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (CFStringRef)@"com.weaponx.uberMonitoringChanged",
                                       NULL, NULL, YES);
    
    if (!isConnected) {
        // Network is offline - activate monitoring for 3 minutes
        [self activateMonitoringWithTimeout:180]; // 3 minutes
    }
}

// Callback for network reachability changes
static void NetworkReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    [URLMonitor checkNetworkStatus];
}

+ (BOOL)isNetworkConnectedWithFlags:(SCNetworkReachabilityFlags)flags {
    // Check if the network is reachable
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    
    return (isReachable && !needsConnection);
}

+ (BOOL)isNetworkConnected {
    // Check current network status
    URLMonitor *monitor = [URLMonitor sharedInstance];
    SCNetworkReachabilityFlags flags;
    BOOL success = SCNetworkReachabilityGetFlags(monitor.reachabilityRef, &flags);
    
    if (!success) {
        return YES; // Default to YES if we can't determine
    }
    
    return [self isNetworkConnectedWithFlags:flags];
}

+ (void)activateMonitoringWithTimeout:(NSTimeInterval)timeout {
    // Cancel any existing timer
    if (autoDisableTimer) {
        [autoDisableTimer invalidate];
        autoDisableTimer = nil;
    }
    
    // Save the monitoring duration
    monitoringDuration = timeout;
    
    // Record start time for countdown
    monitoringStartTime = [NSDate date];
    
    // Activate monitoring
    isMonitoringEnabled = YES;
    monitoringExplicitlyDisabled = NO; // Reset explicit disable flag
    
    // Save state to NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:kMonitoringEnabledKey];
    
    // Always notify hooks about state change
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (CFStringRef)@"com.weaponx.uberMonitoringChanged",
                                        NULL, NULL, YES);
    
    // Schedule auto-disable timer - always deactivate after the timeout
    autoDisableTimer = [NSTimer scheduledTimerWithTimeInterval:timeout
                                                       target:self
                                                     selector:@selector(deactivateMonitoring)
                                                     userInfo:nil
                                                      repeats:NO];
    
    // Also post notification to update the UI
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UberMonitoringStatusChanged" object:@(YES)];
}

+ (void)deactivateMonitoring {
    // Always deactivate after timer expires, regardless of network status
    // Deactivate monitoring
    isMonitoringEnabled = NO;
    monitoringExplicitlyDisabled = YES; // Set the flag that monitoring was explicitly disabled
    
    // Reset start time
    monitoringStartTime = nil;
    
    // Save state to NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:NO forKey:kMonitoringEnabledKey];
    
    // Notify hooks about state change
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (CFStringRef)@"com.weaponx.uberMonitoringChanged",
                                        NULL, NULL, YES);
    
    // Also post notification to update the UI in WeaponX app
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UberMonitoringStatusChanged" object:@(NO)];
    
    // Clear timer
    autoDisableTimer = nil;
    
    // Schedule reset of the explicit disable flag after 10 seconds
    // This allows monitoring to resume if network remains offline after this time
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        monitoringExplicitlyDisabled = NO;
    });
}

+ (NSTimeInterval)getRemainingMonitoringTime {
    // If monitoring is not active, return 0
    if (!isMonitoringEnabled || !monitoringStartTime) {
        return 0;
    }
    
    // Calculate elapsed time since monitoring started
    NSTimeInterval elapsedTime = -[monitoringStartTime timeIntervalSinceNow];
    
    // Calculate remaining time
    NSTimeInterval remainingTime = monitoringDuration - elapsedTime;
    
    // Make sure it's not negative
    if (remainingTime < 0) {
        remainingTime = 0;
    }
    
    return remainingTime;
}

+ (BOOL)isMonitoringActive {
    // If monitoring was explicitly disabled by the timer, respect that
    // even if the network is offline
    if (monitoringExplicitlyDisabled) {
        return NO;
    }
    
    // Check if network is offline - force monitoring if offline
    if (![self isNetworkConnected]) {
        // Update NSUserDefaults to reflect network state
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:kMonitoringEnabledKey];
        return YES;
    }
    
    // Read from NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:kMonitoringEnabledKey];
}

@end 