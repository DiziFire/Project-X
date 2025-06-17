#import <UIKit/UIKit.h>

@interface ToolViewController : UIViewController

// Ping test properties and methods
- (void)startPingTest:(NSString *)host;
- (void)cancelPingTest;

// Speed test properties and methods
- (void)startSpeedTest;
- (void)cancelSpeedTest;

@end 