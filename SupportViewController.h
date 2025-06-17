#import <UIKit/UIKit.h>

@interface SupportViewController : UIViewController

@property (nonatomic, strong) UITabBarController *tabBarController;

// Connectivity properties
@property (nonatomic, strong) NSURLSessionDataTask *connectivityTask;
@property (nonatomic, assign) BOOL hasShownOfflineAlert;

// Methods to open specific items from push notifications
- (void)openBroadcastDetail:(NSNumber *)broadcastId;
- (void)openTicketDetail:(NSNumber *)ticketId;

@end