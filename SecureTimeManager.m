#import "SecureTimeManager.h"
#import <UIKit/UIKit.h>

// Keys for NSUserDefaults
static NSString *const kLastServerTimestamp = @"WeaponXLastServerTimestamp";
static NSString *const kServerTimeDelta = @"WeaponXServerTimeDelta";
static NSString *const kTotalUsageTime = @"WeaponXTotalUsageTime";
static NSString *const kLastSystemTime = @"WeaponXLastSystemTime";
static NSString *const kAppLaunchCount = @"WeaponXAppLaunchCount";
static NSString *const kUsageHistory = @"WeaponXUsageHistory";
static NSString *const kLastUsageSessionStart = @"WeaponXLastUsageSessionStart";

@interface SecureTimeManager ()

@property (nonatomic, strong) NSUserDefaults *secureDefaults;
@property (nonatomic, strong) NSDate *sessionStartTime;
@property (nonatomic, assign) NSTimeInterval timeDeltaWithServer;
@property (nonatomic, assign) NSTimeInterval lastRecordedSystemTime;

@end

@implementation SecureTimeManager

#pragma mark - Initialization

+ (instancetype)sharedManager {
    static SecureTimeManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _secureDefaults = [NSUserDefaults standardUserDefaults];
        _timeDeltaWithServer = [_secureDefaults doubleForKey:kServerTimeDelta];
        _lastRecordedSystemTime = [_secureDefaults doubleForKey:kLastSystemTime];
        
        // Initialize session start time
        _sessionStartTime = [NSDate date];
        
        // Record current system time for future anomaly checks
        [self recordCurrentSystemTime];
        
        // Setup notifications to track app foreground/background for session timing
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - App Lifecycle Tracking

- (void)appDidEnterBackground:(NSNotification *)notification {
    // Record session time when app goes to background
    NSTimeInterval sessionDuration = [[NSDate date] timeIntervalSinceDate:self.sessionStartTime];
    [self recordSessionTime:sessionDuration];
    
    // Store current timestamp for anomaly detection when app returns
    [self recordCurrentSystemTime];
}

- (void)appWillEnterForeground:(NSNotification *)notification {
    // Check for time anomalies when app comes back to foreground
    if ([self isTimeAnomalyDetected:5]) { // 5-minute threshold for unexpected changes
        NSLog(@"[WeaponX] ⚠️ Time anomaly detected during app resume!");
        // Additional handling could be implemented here
    }
    
    // Reset session start time
    self.sessionStartTime = [NSDate date];
    
    // Record current time for future checks
    [self recordCurrentSystemTime];
}

#pragma mark - Server Time Synchronization

- (void)recordServerTimestamp:(NSTimeInterval)serverTimestamp {
    // Store the server timestamp
    [self.secureDefaults setDouble:serverTimestamp forKey:kLastServerTimestamp];
    
    // Calculate and store the delta between server time and device time
    NSTimeInterval currentDeviceTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval delta = serverTimestamp - currentDeviceTime;
    self.timeDeltaWithServer = delta;
    
    [self.secureDefaults setDouble:delta forKey:kServerTimeDelta];
    [self.secureDefaults synchronize];
    
    NSLog(@"[WeaponX] ⏱️ Server time recorded: %@ (Delta: %.2f seconds)", 
          [NSDate dateWithTimeIntervalSince1970:serverTimestamp], delta);
}

- (NSTimeInterval)currentSynchronizedTimestamp {
    // Get current device time
    NSTimeInterval currentDeviceTime = [[NSDate date] timeIntervalSince1970];
    
    // Apply the delta if we have synchronized with server before
    if ([self.secureDefaults objectForKey:kLastServerTimestamp]) {
        return currentDeviceTime + self.timeDeltaWithServer;
    }
    
    // Fallback to device time if no server sync has occurred
    return currentDeviceTime;
}

#pragma mark - Usage Tracking (Independent of System Time)

- (void)recordAppLaunch {
    // Get current launch count
    NSInteger launchCount = [self.secureDefaults integerForKey:kAppLaunchCount];
    launchCount++;
    
    // Store updated count
    [self.secureDefaults setInteger:launchCount forKey:kAppLaunchCount];
    [self.secureDefaults synchronize];
    
    // Reset session start time
    self.sessionStartTime = [NSDate date];
    
    NSLog(@"[WeaponX] 🚀 App launch recorded: %ld", (long)launchCount);
}

- (void)recordSessionTime:(NSTimeInterval)sessionDuration {
    if (sessionDuration <= 0) return;
    
    // Get current total usage time
    NSTimeInterval totalTime = [self.secureDefaults doubleForKey:kTotalUsageTime];
    totalTime += sessionDuration;
    
    // Store updated total time
    [self.secureDefaults setDouble:totalTime forKey:kTotalUsageTime];
    
    // Record usage in history with real timestamps
    NSMutableArray *history = [NSMutableArray arrayWithArray:[self.secureDefaults arrayForKey:kUsageHistory] ?: @[]];
    [history addObject:@{
        @"duration": @(sessionDuration),
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    }];
    
    // Keep only the last 100 sessions to prevent unlimited growth
    if (history.count > 100) {
        [history removeObjectsInRange:NSMakeRange(0, history.count - 100)];
    }
    
    [self.secureDefaults setObject:history forKey:kUsageHistory];
    [self.secureDefaults synchronize];
    
    NSLog(@"[WeaponX] ⏱️ Session time recorded: %.2f seconds (Total: %.2f hours)", 
          sessionDuration, totalTime / 3600.0);
}

- (NSTimeInterval)totalElapsedUsageTime {
    // Get stored total usage time
    NSTimeInterval totalTime = [self.secureDefaults doubleForKey:kTotalUsageTime];
    
    // Add current session if app is active
    if (self.sessionStartTime) {
        NSTimeInterval currentSessionDuration = [[NSDate date] timeIntervalSinceDate:self.sessionStartTime];
        totalTime += currentSessionDuration;
    }
    
    return totalTime;
}

- (BOOL)isWithinUsageLimits:(NSInteger)maxHours {
    // Convert max hours to seconds
    NSTimeInterval maxSeconds = maxHours * 3600;
    
    // Get total elapsed usage time
    NSTimeInterval totalUsageTime = [self totalElapsedUsageTime];
    
    // Check if usage is within limits
    BOOL withinLimits = (totalUsageTime <= maxSeconds);
    
    NSLog(@"[WeaponX] 📊 Usage check: %.2f/%.2f hours used. Within limits: %@", 
          totalUsageTime / 3600.0, (double)maxHours, withinLimits ? @"YES" : @"NO");
    
    return withinLimits;
}

- (void)resetUsageCounters {
    // Reset total usage time after successful online verification
    [self.secureDefaults setDouble:0.0 forKey:kTotalUsageTime];
    [self.secureDefaults synchronize];
    
    NSLog(@"[WeaponX] 🔄 Usage counters reset after successful verification");
}

#pragma mark - Time Manipulation Detection

- (void)recordCurrentSystemTime {
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    self.lastRecordedSystemTime = currentTime;
    [self.secureDefaults setDouble:currentTime forKey:kLastSystemTime];
    [self.secureDefaults synchronize];
}

- (BOOL)isTimeAnomalyDetected:(NSInteger)allowedDeltaMinutes {
    // If we don't have a previous time reference, we can't detect anomalies
    if (self.lastRecordedSystemTime == 0) {
        [self recordCurrentSystemTime];
        return NO;
    }
    
    // Get current time
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    // Calculate elapsed time since last recorded time
    NSTimeInterval elapsed = currentTime - self.lastRecordedSystemTime;
    
    // Calculate max allowed delta in seconds
    NSTimeInterval maxAllowedDelta = allowedDeltaMinutes * 60;
    
    // For forward time jumps - elapsed time should be positive and reasonable
    // For backward time jumps - elapsed time would be negative
    BOOL isAnomaly = (elapsed < 0) || (elapsed > maxAllowedDelta);
    
    if (isAnomaly) {
        NSLog(@"[WeaponX] ⚠️ Time anomaly detected! Elapsed: %.2f seconds (Max allowed: %.2f)",
              elapsed, maxAllowedDelta);
    }
    
    // Update reference time
    [self recordCurrentSystemTime];
    
    return isAnomaly;
}

- (BOOL)isTimeManipulationDetected {
    // Check for time anomalies with a 60-minute threshold
    BOOL hasTimeAnomaly = [self isTimeAnomalyDetected:60];
    
    // Check server time sync if available
    BOOL hasServerTimeMismatch = NO;
    if ([self.secureDefaults objectForKey:kLastServerTimestamp]) {
        NSTimeInterval serverSyncedTime = [self currentSynchronizedTimestamp];
        NSTimeInterval currentDeviceTime = [[NSDate date] timeIntervalSince1970];
        
        // If device and server time differ by more than 5 minutes, suspect manipulation
        NSTimeInterval timeDifference = fabs(serverSyncedTime - currentDeviceTime);
        hasServerTimeMismatch = (timeDifference > 300); // 5 minutes in seconds
        
        if (hasServerTimeMismatch) {
            NSLog(@"[WeaponX] ⚠️ Server time mismatch detected! Difference: %.2f minutes",
                  timeDifference / 60.0);
        }
    }
    
    // Check system time vs. accumulated usage time for inconsistencies
    NSTimeInterval totalTime = [self.secureDefaults doubleForKey:kTotalUsageTime];
    NSArray *history = [self.secureDefaults arrayForKey:kUsageHistory];
    BOOL hasUsageTimeInconsistency = NO;
    
    if (history.count >= 2) {
        // Get oldest and newest history entries
        NSDictionary *oldestEntry = history.firstObject;
        NSDictionary *newestEntry = history.lastObject;
        
        NSTimeInterval oldestTimestamp = [oldestEntry[@"timestamp"] doubleValue];
        NSTimeInterval newestTimestamp = [newestEntry[@"timestamp"] doubleValue];
        
        // Calculate elapsed time between first and last usage records
        NSTimeInterval elapsedSystemTime = newestTimestamp - oldestTimestamp;
        
        // If total usage time exceeds elapsed system time, suspect manipulation
        hasUsageTimeInconsistency = (totalTime > elapsedSystemTime * 1.5); // Allow 50% buffer
        
        if (hasUsageTimeInconsistency) {
            NSLog(@"[WeaponX] ⚠️ Usage time inconsistency detected! Usage: %.2f hours, Elapsed: %.2f hours",
                  totalTime / 3600.0, elapsedSystemTime / 3600.0);
        }
    }
    
    // Time manipulation is detected if any checks fail
    return hasTimeAnomaly || hasServerTimeMismatch || hasUsageTimeInconsistency;
}

- (BOOL)isTimestampValid:(NSTimeInterval)expirationTimestamp withGracePeriod:(NSInteger)gracePeriodHours {
    // Get current time (server synchronized if available)
    NSTimeInterval currentTime = [self currentSynchronizedTimestamp];
    
    // Add grace period (in seconds)
    NSTimeInterval gracePeriod = gracePeriodHours * 3600;
    NSTimeInterval effectiveExpiration = expirationTimestamp + gracePeriod;
    
    // Check if current time is before the effective expiration
    BOOL isValid = (currentTime < effectiveExpiration);
    
    NSLog(@"[WeaponX] 🔐 Timestamp validation: %@ (Expires: %@, With grace: %@, Now: %@)",
          isValid ? @"VALID" : @"EXPIRED",
          [NSDate dateWithTimeIntervalSince1970:expirationTimestamp],
          [NSDate dateWithTimeIntervalSince1970:effectiveExpiration],
          [NSDate dateWithTimeIntervalSince1970:currentTime]);
    
    return isValid;
}

@end 