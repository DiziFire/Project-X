#import "ProjectXInstaller.h"

@implementation ProjectXInstaller

+ (void)installAppWithAdamId:(NSString *)adamId 
                 appExtVrsId:(NSString *)appExtVrsId 
                  completion:(void (^)(BOOL success))completion {
    
    // Log the installation attempt
    NSLog(@"[ProjectX] 🚀 Direct installation - Adam ID: %@, App Ext Vrs ID: %@", adamId, appExtVrsId);
    
    // Construct the App Store URL using the MuffinStore format
    NSString *urlString = [NSString stringWithFormat:@"itms-apps://buy.itunes.apple.com/WebObjects/MZBuy.woa/wa/buyProduct?id=%@&mt=8&appExtVrsId=%@",
                          adamId, appExtVrsId];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSLog(@"[ProjectX] 🔍 Opening App Store URL: %@", url);
    
    // Open the URL directly without any confirmation
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        NSLog(@"[ProjectX] %@ URL opening %@", success ? @"✅" : @"❌", success ? @"succeeded" : @"failed");
        
        if (completion) {
            completion(success);
        }
    }];
}

+ (void)installAppWithAdamId:(NSString *)adamId 
                 appExtVrsId:(NSString *)appExtVrsId 
                    bundleID:(NSString *)bundleID 
                     appName:(NSString *)appName 
                     version:(NSString *)version
                  completion:(void (^)(BOOL success))completion {
    
    // Log the installation attempt with full details
    NSLog(@"[ProjectX] 🚀 Direct installation - Adam ID: %@, App Ext Vrs ID: %@, Bundle ID: %@, App Name: %@, Version: %@",
          adamId, appExtVrsId, bundleID, appName, version);
    
    // Call the simpler method to perform the actual installation
    [self installAppWithAdamId:adamId appExtVrsId:appExtVrsId completion:completion];
}

@end
