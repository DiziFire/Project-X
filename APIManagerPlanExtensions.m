#import "APIManagerPlanExtensions.h"
#import "TokenManager.h"

@implementation APIManager (PlanExtensions)

- (BOOL)userHasPlan {
    // Use the existing Layer 1 security system that is used for tab restrictions
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Check WeaponXHasActivePlan flag which is used by the tab restriction system
    BOOL hasActivePlan = [defaults boolForKey:@"WeaponXHasActivePlan"];
    
    // Check WeaponXRestrictedAccess flag - if access is restricted, user doesn't have a plan
    BOOL isRestricted = [defaults boolForKey:@"WeaponXRestrictedAccess"];
    
    // If the user has an active plan or is not restricted, they have a plan
    return hasActivePlan || !isRestricted;
}

- (NSDate *)userRegistrationDate {
    // First check if plan data already exists in secure storage
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Layer 1 security: Check WeaponXUserPlanInfo first (it's more reliable)
    NSDictionary *userPlanInfo = [defaults objectForKey:@"WeaponXUserPlanInfo"];
    if (userPlanInfo && userPlanInfo[@"user"] && [userPlanInfo[@"user"] isKindOfClass:[NSDictionary class]]) {
        // If we have user plan data, use the created_at from there if available
        NSString *registrationDateStr = userPlanInfo[@"user"][@"created_at"];
        if (registrationDateStr) {
            NSLog(@"[WeaponX] 📢 Using registration date from plan data: %@", registrationDateStr);
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
            NSDate *registrationDate = [dateFormatter dateFromString:registrationDateStr];
            if (registrationDate) {
                return registrationDate;
            }
        }
    }
    
    // Fallback to user info if plan info doesn't have it
    NSDictionary *userInfo = [defaults objectForKey:@"WeaponXUserInfo"];
    if (userInfo && [userInfo isKindOfClass:[NSDictionary class]]) {
        NSString *registrationDateStr = userInfo[@"created_at"];
        if (registrationDateStr) {
            NSLog(@"[WeaponX] 📢 Using registration date from user info: %@", registrationDateStr);
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
            NSDate *registrationDate = [dateFormatter dateFromString:registrationDateStr];
            if (registrationDate) {
                return registrationDate;
            }
        }
    }
    
    // If we still don't have a registration date, check if user is new based on plan_id = 0
    NSDictionary *userData = [defaults dictionaryForKey:@"WeaponXUserData"];
    if (userData) {
        NSNumber *planId = userData[@"plan_id"];
        if (planId && [planId intValue] == 0) {
            NSLog(@"[WeaponX] 📢 User has plan_id=0, treating as new user");
            // Return a date within the last 24 hours to ensure they're eligible for trial
            return [NSDate dateWithTimeIntervalSinceNow:-3600]; // 1 hour ago
        }
    }
    
    // Last resort: check updated_at as proxy for creation date
    if (userInfo && userInfo[@"updated_at"]) {
        NSString *updatedDateStr = userInfo[@"updated_at"];
        NSLog(@"[WeaponX] 📢 Falling back to updated_at as proxy for creation date: %@", updatedDateStr);
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        return [dateFormatter dateFromString:updatedDateStr];
    }
    
    // For users with no plan and no registration date, default to treating as new user
    // This ensures they'll at least see the trial banner
    return [NSDate date];
}

- (void)refreshUserPlanStatus {
    // Get user ID and token for authentication
    NSString *userId = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXUserID"];
    NSString *token = [[TokenManager sharedInstance] token];
    
    if (!userId || !token) {
        NSLog(@"Missing userId or token for refreshing plan status");
        return;
    }
    
    // Create request to get user plan info
    NSString *url = [NSString stringWithFormat:@"%@/api/user/%@/plan", [self baseURL], userId];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    
    // Create a URL session for this request
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Error refreshing plan status: %@", error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"Server error refreshing plan status: %ld", (long)httpResponse.statusCode);
            return;
        }
        
        // Parse response
        NSError *jsonError;
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"Error parsing plan status response: %@", jsonError);
            return;
        }
        
        // Save the updated plan info
        if (responseDict[@"data"] && [responseDict[@"data"] isKindOfClass:[NSDictionary class]]) {
            [[NSUserDefaults standardUserDefaults] setObject:responseDict[@"data"] 
                                                      forKey:@"WeaponXUserPlanInfo"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            // Post notification that plan status has changed
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"UserPlanStatusChanged" 
                                                                    object:nil];
            });
        }
    }];
    
    [task resume];
}

@end 