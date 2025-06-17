#import <UIKit/UIKit.h>

@interface ProjectXInstaller : NSObject

/**
 * Installs an app directly using the App Store URL format
 * @param adamId The App Store ID of the app
 * @param appExtVrsId The external version ID of the app
 * @param completion Optional completion block called after URL is opened
 */
+ (void)installAppWithAdamId:(NSString *)adamId 
                 appExtVrsId:(NSString *)appExtVrsId 
                  completion:(void (^)(BOOL success))completion;

/**
 * Installs an app directly using the App Store URL format with additional metadata
 * @param adamId The App Store ID of the app
 * @param appExtVrsId The external version ID of the app
 * @param bundleID The bundle ID of the app
 * @param appName The name of the app
 * @param version The version string of the app
 * @param completion Optional completion block called after URL is opened
 */
+ (void)installAppWithAdamId:(NSString *)adamId 
                 appExtVrsId:(NSString *)appExtVrsId 
                    bundleID:(NSString *)bundleID 
                     appName:(NSString *)appName 
                     version:(NSString *)version
                  completion:(void (^)(BOOL success))completion;

@end
