// SecureTimeManager.h - Provides time manipulation protection for WeaponX tweak

#import <Foundation/Foundation.h>

@interface SecureTimeManager : NSObject

/**
 * Singleton instance accessor
 */
+ (instancetype)sharedManager;

/**
 * Records a server timestamp when online verification occurs
 * @param serverTimestamp The timestamp from server (Unix epoch time)
 */
- (void)recordServerTimestamp:(NSTimeInterval)serverTimestamp;

/**
 * Records app launch - increments usage counter
 */
- (void)recordAppLaunch;

/**
 * Records app usage time based on elapsed time, not system time
 * @param sessionStartTime The start time of the current usage session
 */
- (void)recordSessionTime:(NSTimeInterval)sessionDuration;

/**
 * Checks if the app usage is within allowed limits
 * @param maxHours Maximum allowed hours of offline usage
 * @return YES if within limits, NO if usage should be blocked
 */
- (BOOL)isWithinUsageLimits:(NSInteger)maxHours;

/**
 * Detects possible time manipulation by checking for inconsistencies
 * @return YES if time manipulation is detected, NO otherwise
 */
- (BOOL)isTimeManipulationDetected;

/**
 * Detects sudden changes in system time that could indicate manipulation
 * @param allowedDeltaMinutes Maximum allowed time change in minutes 
 * @return YES if anomaly detected, NO otherwise
 */
- (BOOL)isTimeAnomalyDetected:(NSInteger)allowedDeltaMinutes;

/**
 * Resets the usage counters during successful online verification
 */
- (void)resetUsageCounters;

/**
 * Gets the server-synchronized current timestamp (if available)
 * @return Current time as timestamp, synchronized with server if possible
 */
- (NSTimeInterval)currentSynchronizedTimestamp;

/**
 * Records the current system time for anomaly detection
 */
- (void)recordCurrentSystemTime;

/**
 * Gets total cumulative usage time in seconds
 * @return Total usage time
 */
- (NSTimeInterval)totalElapsedUsageTime;

/**
 * Verifies timestamp expiration against server time
 * @param expirationTimestamp Local expiration timestamp to verify
 * @param gracePeriodHours Additional time allowed when offline
 * @return YES if timestamp is valid, NO if expired
 */
- (BOOL)isTimestampValid:(NSTimeInterval)expirationTimestamp withGracePeriod:(NSInteger)gracePeriodHours;

@end 