#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@interface URLMonitor : NSObject

// Shared instance
+ (instancetype)sharedInstance;

// Initialize network monitoring
+ (void)setupNetworkMonitoring;

// Check if monitoring is currently active
+ (BOOL)isMonitoringActive;

// Get current network status
+ (BOOL)isNetworkConnected;

// Get remaining monitoring time in seconds
+ (NSTimeInterval)getRemainingMonitoringTime;

// Activate monitoring with a timeout (in seconds)
+ (void)activateMonitoringWithTimeout:(NSTimeInterval)timeout;

// Deactivate monitoring immediately
+ (void)deactivateMonitoring;

@end

NS_ASSUME_NONNULL_END 