#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface APIManager : NSObject <NSURLSessionDelegate>

@property (nonatomic, strong) NSString *baseURLString;
@property (nonatomic, strong) NSArray *fallbackEndpoints;
@property (nonatomic, assign) BOOL isOnline;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSURLSession *session;

+ (instancetype)sharedManager;

// Configuration
- (void)setBaseURL:(NSString *)baseURL;
- (NSString *)baseURL;

// Network status
- (BOOL)isNetworkAvailable;
- (BOOL)isWithinOfflineGracePeriod;

// Authentication methods
- (void)loginWithEmail:(NSString *)email password:(NSString *)password completion:(void (^)(NSDictionary *userData, NSString *token, NSError *error))completion;
- (void)registerWithName:(NSString *)name email:(NSString *)email password:(NSString *)password completion:(void (^)(NSDictionary *userData, NSString *token, NSError *error))completion;
- (void)logoutWithToken:(NSString *)token completion:(void (^)(BOOL success, NSError *error))completion;
- (NSString *)getAuthToken;

// Session Info - New consolidated API
- (void)fetchSessionInfoWithToken:(NSString *)token completion:(void (^)(NSDictionary *sessionInfo, NSError *error))completion;

// Time Security - Server synchronization
- (void)syncTimeWithServer:(void (^)(BOOL success, NSTimeInterval serverTime, NSError *error))completion;

// User data methods
- (void)fetchUserDataWithToken:(NSString *)token completion:(void (^)(NSDictionary *userData, NSError *error))completion;

// Plan methods
- (void)fetchUserPlanWithToken:(NSString *)token completion:(void (^)(NSDictionary *planData, NSError *error))completion;
- (void)fetchAllPlansWithToken:(NSString *)token completion:(void (^)(NSArray *plans, NSError *error))completion;
- (void)purchasePlanWithToken:(NSString *)token planId:(NSString *)planId completion:(void (^)(BOOL success, NSError *error))completion;
- (BOOL)verifyPlanDataIntegrity;
- (void)refreshUserPlan;
- (void)refreshPlanData:(NSString *)token;
- (void)storePlanData:(NSDictionary *)planData;

// User Presence/Status methods
- (void)updateUserPresence:(NSString *)token status:(NSString *)status completion:(void (^)(BOOL success, NSError *error))completion;

// Screen tracking methods
- (void)setCurrentScreen:(NSString *)screenName;
- (NSString *)getCurrentScreen;

// Heartbeat methods
- (void)startHeartbeat:(NSString *)userId;
- (void)sendHeartbeat:(NSString *)userId;
- (void)heartbeatTimerFired;
- (void)stopHeartbeat;

// Token Synchronization Helpers
- (NSURLRequest *)prepareRequestWithToken:(NSString *)token method:(NSString *)method url:(NSString *)urlString;
- (BOOL)handleUnauthorizedResponse:(NSHTTPURLResponse *)response completion:(void (^)(BOOL tokenReset, NSString *newToken))completion;

// Helper methods
- (void)fetchCSRFTokenWithCompletion:(void (^)(NSString *token))completion;
- (void)fetchCSRFTokenWithExtendedCompletion:(void (^)(BOOL success, NSString *token))completion;
- (NSString *)getCSRFTokenForUrl:(NSString *)urlString;
- (NSString *)apiUrlForEndpoint:(NSString *)endpoint;

// Utility methods
- (void)clearAllUserData;
- (BOOL)isUserLoggedIn;
- (NSString *)currentAuthToken;
- (NSDictionary *)currentUserData;
- (void)exitAndRelaunchApp;

// App Update methods
- (void)checkForUpdatesWithCurrentVersion:(NSString *)version buildNumber:(NSInteger)buildNumber completion:(void (^)(NSDictionary *updateInfo, NSError *error))completion;
- (void)downloadAppUpdate:(NSString *)downloadUrl destination:(NSURL *)destinationPath completion:(void (^)(NSURL *fileURL, NSError *error))completion;

// Device Management
- (void)registerDeviceToken:(NSString *)token deviceType:(NSString *)deviceType completion:(void (^)(BOOL success, NSError *error))completion;

// Support Ticket APIs
- (void)getTicketCategories:(void (^)(NSArray *categories, NSError *error))completion;
- (void)getUserTickets:(void (^)(NSArray *tickets, NSError *error))completion;
- (void)getTicketDetails:(NSNumber *)ticketId completion:(void (^)(NSDictionary *ticket, NSError *error))completion;
- (void)createTicket:(NSString *)subject content:(NSString *)content categoryId:(NSNumber *)categoryId priority:(NSString *)priority completion:(void (^)(BOOL success, NSString *message, NSNumber *ticketId, NSError *error))completion;
- (void)createTicket:(NSString *)subject content:(NSString *)content categoryId:(NSNumber *)categoryId priority:(NSString *)priority attachments:(NSArray<UIImage *> *)attachments completion:(void (^)(BOOL success, NSString *message, NSNumber *ticketId, NSError *error))completion;
- (void)replyToTicket:(NSNumber *)ticketId content:(NSString *)content completion:(void (^)(BOOL success, NSString *message, NSError *error))completion;
- (void)replyToTicket:(NSNumber *)ticketId content:(NSString *)content attachment:(UIImage *)attachment completion:(void (^)(BOOL success, NSString *message, NSError *error))completion;
- (void)closeTicket:(NSNumber *)ticketId completion:(void (^)(BOOL success, NSString *message, NSError *error))completion;
- (void)reopenTicket:(NSNumber *)ticketId completion:(void (^)(BOOL success, NSString *message, NSError *error))completion;

// Broadcast APIs
- (void)getBroadcasts:(void (^)(NSArray *broadcasts, NSInteger unreadCount, NSError *error))completion;
- (void)getBroadcastDetails:(NSNumber *)broadcastId completion:(void (^)(NSDictionary *broadcast, NSError *error))completion;
- (void)markBroadcastAsRead:(NSNumber *)broadcastId completion:(void (^)(BOOL success, NSError *error))completion;

// Notification APIs
- (void)getNotificationCount:(void (^)(NSInteger unreadBroadcasts, NSInteger unreadTicketReplies, NSInteger totalCount, NSError *error))completion;

// Helper method for authorized API requests
- (void)authorizedRequestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters completion:(void (^)(NSDictionary *responseObject, NSError *error))completion;

// Add these method declarations after the last existing method declaration
- (void)sendRequest:(NSURLRequest *)request completion:(void (^)(NSDictionary *responseObject, NSError *error))completion;
- (NSURL *)urlForPath:(NSString *)path;

// Version Ban methods - only used during login/signup
- (BOOL)isCurrentVersionBanned;
- (void)showVersionBannedAlert:(UIViewController *)viewController completion:(void (^)(void))completion;
- (void)checkVersionBanWithCompletion:(void (^)(BOOL isBanned, NSError *error))completion;
- (void)openSileoForUpdate:(NSString *)packageID;

// Subcategory APIs
- (void)getSubcategoriesForCategory:(NSNumber *)categoryId completion:(void (^)(NSArray *subcategories, NSError *error))completion;
- (void)createTicketWithSubcategory:(NSString *)subject 
                            content:(NSString *)content 
                         categoryId:(NSNumber *)categoryId 
                      subcategoryId:(NSNumber *)subcategoryId 
                          priority:(NSString *)priority 
                       attachments:(NSArray<UIImage *> *)attachments 
                        completion:(void (^)(BOOL success, NSString *message, NSNumber *ticketId, NSError *error))completion;

// Device management methods
- (void)getUserDevices:(void (^)(NSArray *devices, NSInteger deviceLimit, NSError *error))completion;
- (void)removeUserDevice:(NSString *)deviceUUID completion:(void (^)(BOOL success, NSError *error))completion;

@end 