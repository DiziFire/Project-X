#import <UIKit/UIKit.h>

@interface UberOrderViewController : UIViewController

// Handles URL scheme for receiving Uber order IDs
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