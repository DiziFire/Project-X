#import <Foundation/Foundation.h>
#import "APIManager.h"

@interface APIManager (PlanExtensions)

/**
 * Checks if the current user has an active plan
 * @return YES if the user has an active plan, NO otherwise
 */
- (BOOL)userHasPlan;

/**
 * Gets the user's registration date
 * @return The date when the user registered, or nil if not available
 */
- (NSDate *)userRegistrationDate;

/**
 * Refreshes the user's plan status from the server
 */
- (void)refreshUserPlanStatus;

@end 