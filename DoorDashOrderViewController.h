#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DoorDashOrderViewController : UIViewController

// Handles URL scheme for receiving DoorDash order IDs
+ (BOOL)handleURLScheme:(NSURL *)url;

// Adds a new order ID to the tracking list
+ (void)addOrderID:(NSString *)orderID timestamp:(NSDate *)timestamp;

// Gets singleton instance
+ (instancetype)sharedInstance;

// Gets an array of the most recent order IDs with their timestamps
+ (NSArray *)getRecentOrderIDs:(NSInteger)count;

// Gets the formatted time elapsed since a particular timestamp
+ (NSString *)getTimeElapsedString:(NSDate *)timestamp;

@end

NS_ASSUME_NONNULL_END 