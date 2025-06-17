// Extension for SecurityTabViewController to handle IP Monitor Info button
#import "SecurityTabViewController.h"
#import <UIKit/UIKit.h>

@implementation SecurityTabViewController (IPMonitorInfo)

- (void)showIPMonitorInfo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Check & Monitor IP Status"
                                                                   message:@"This section allows you to check your current IP status and enable monitoring for changes in your network IP. When enabled, the app will notify you if your IP changes, helping you stay aware of your network security."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
