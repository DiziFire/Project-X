#import "ProjectXSceneDelegate.h"
#import "ProjectXViewController.h"
#import "TabBarController.h"
#import "UberOrderViewController.h"
#import "DoorDashOrderViewController.h"
#import "ToolViewController.h"

@interface ProjectXSceneDelegate ()
@property (nonatomic, strong) UINavigationController *navigationController;
@end

@implementation ProjectXSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    
    // Ensure we're on the main thread for UI operations
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scene:scene willConnectToSession:session options:connectionOptions];
        });
        return;
    }
    
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.backgroundColor = [UIColor systemBackgroundColor];
    
    // Create the tab bar controller
    TabBarController *tabBarController = [[TabBarController alloc] init];
    
    // Configure for iPad
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // For iPad, don't use UISplitViewController with TabBarController
        // Just use the TabBarController directly to avoid the crash
        self.window.rootViewController = tabBarController;
        
        // Alternatively, if you want to maintain a navigation structure:
        // UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:tabBarController];
        // self.window.rootViewController = navController;
    } else {
        // For iPhone, use the tab bar controller directly
        self.window.rootViewController = tabBarController;
    }
    
    [self.window makeKeyAndVisible];
    
    // Post connection notification
    if (@available(iOS 14.0, *)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ProjectXSceneConnectionNotification" object:nil];
        });
    }
    
    // Handle any URL contexts for deep linking
    if (connectionOptions.URLContexts.count > 0) {
        NSSet<UIOpenURLContext *> *urlContexts = connectionOptions.URLContexts;
        UIOpenURLContext *firstContext = urlContexts.allObjects.firstObject;
        NSURL *url = firstContext.URL;
        
        if ([url.scheme isEqualToString:@"weaponx"]) {
            BOOL handled = NO;
            
            // Try to handle with UberOrderViewController
            if ([url.host isEqualToString:@"store-uber-order"]) {
                handled = [UberOrderViewController handleURLScheme:url];
                
                if (handled) {
                    NSLog(@"[WeaponX] Successfully handled URL scheme for Uber order tracking");
                    
                    // Show the Uber order view controller if needed
                    if ([self.window.rootViewController isKindOfClass:[TabBarController class]]) {
                        TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
                        
                        // Navigate to the Home tab (index 1) where ToolViewController is available
                        [tabBarController setSelectedIndex:1];
                    }
                }
            }
            // Try to handle with DoorDashOrderViewController
            else if ([url.host isEqualToString:@"store-doordash-order"]) {
                handled = [DoorDashOrderViewController handleURLScheme:url];
                
                if (handled) {
                    NSLog(@"[WeaponX] Successfully handled URL scheme for DoorDash order tracking");
                    
                    // Show the DoorDash order view controller directly
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // First navigate to the Home tab which contains the ToolViewController
                        if ([self.window.rootViewController isKindOfClass:[TabBarController class]]) {
                            TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
                            [tabBarController setSelectedIndex:1]; // Home tab
                            
                            // Then present the DoorDash order view controller modally
                            DoorDashOrderViewController *doorDashOrdersVC = [DoorDashOrderViewController sharedInstance];
                            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:doorDashOrdersVC];
                            navController.modalPresentationStyle = UIModalPresentationFullScreen;
                            [tabBarController presentViewController:navController animated:YES completion:nil];
                        }
                    });
                }
            }
            
            if (!handled) {
                NSLog(@"[WeaponX] Failed to handle URL scheme: %@", url);
            }
        }
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    UIOpenURLContext *context = [URLContexts anyObject];
    if (context) {
        NSURL *url = context.URL;
        
        if ([url.scheme isEqualToString:@"weaponx"]) {
            BOOL handled = NO;
            
            // Try to handle with UberOrderViewController
            if ([url.host isEqualToString:@"store-uber-order"]) {
                handled = [UberOrderViewController handleURLScheme:url];
                
                if (handled) {
                    NSLog(@"[WeaponX] Successfully handled URL scheme for Uber order tracking");
                    
                    // Show the Uber order view controller if needed
                    if ([self.window.rootViewController isKindOfClass:[TabBarController class]]) {
                        TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
                        
                        // Navigate to the Home tab (index 1) which contains the ToolViewController
                        [tabBarController setSelectedIndex:1];
                    }
                }
            }
            // Try to handle with DoorDashOrderViewController
            else if ([url.host isEqualToString:@"store-doordash-order"]) {
                handled = [DoorDashOrderViewController handleURLScheme:url];
                
                if (handled) {
                    NSLog(@"[WeaponX] Successfully handled URL scheme for DoorDash order tracking");
                    
                    // Show the DoorDash order view controller directly
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // First navigate to the Home tab which contains the ToolViewController
                        if ([self.window.rootViewController isKindOfClass:[TabBarController class]]) {
                            TabBarController *tabBarController = (TabBarController *)self.window.rootViewController;
                            [tabBarController setSelectedIndex:1]; // Home tab
                            
                            // Then present the DoorDash order view controller modally
                            DoorDashOrderViewController *doorDashOrdersVC = [DoorDashOrderViewController sharedInstance];
                            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:doorDashOrdersVC];
                            navController.modalPresentationStyle = UIModalPresentationFullScreen;
                            [tabBarController presentViewController:navController animated:YES completion:nil];
                        }
                    });
                }
            }
            
            if (!handled) {
                NSLog(@"[WeaponX] Failed to handle URL scheme: %@", url);
            }
        }
    }
}

- (NSUserActivity *)stateRestorationActivityForScene:(UIScene *)scene {
    // Create state restoration activity
    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:@"com.hydra.projectx.state-restoration"];
    activity.title = @"ProjectX State";
    
    // Save view hierarchy state
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        UIViewController *topController = self.navigationController.topViewController;
        if ([topController respondsToSelector:@selector(saveState)]) {
            [topController performSelector:@selector(saveState)];
        }
        
        // Add navigation state
        if (self.navigationController) {
            NSMutableArray *viewControllerTitles = [NSMutableArray array];
            for (UIViewController *controller in self.navigationController.viewControllers) {
                [viewControllerTitles addObject:controller.title ?: @""];
            }
            [activity addUserInfoEntriesFromDictionary:@{
                @"navigation_stack": viewControllerTitles,
                @"selected_index": @(self.navigationController.topViewController ? [self.navigationController.viewControllers indexOfObject:self.navigationController.topViewController] : 0)
            }];
        }
    }
    
    return activity;
}

- (void)scene:(UIScene *)scene restoreInteractionStateWithUserActivity:(NSUserActivity *)activity {
    if ([activity.activityType isEqualToString:@"com.hydra.projectx.state-restoration"]) {
        // Restore navigation state if needed
        NSArray *navigationStack = activity.userInfo[@"navigation_stack"];
        NSNumber *selectedIndex = activity.userInfo[@"selected_index"];
        
        if (navigationStack && selectedIndex && self.navigationController) {
            // Implement navigation stack restoration based on your app's needs
            NSUInteger index = [selectedIndex unsignedIntegerValue];
            if (index < self.navigationController.viewControllers.count) {
                [self.navigationController popToViewController:self.navigationController.viewControllers[index] animated:NO];
            }
        }
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    [self stateRestorationActivityForScene:scene];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SceneWillDisconnect" object:nil];
    self.window = nil;
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SceneDidBecomeActive" object:nil];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    [self stateRestorationActivityForScene:scene];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SceneWillResignActive" object:nil];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SceneWillEnterForeground" object:nil];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [self stateRestorationActivityForScene:scene];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SceneDidEnterBackground" object:nil];
}

- (void)windowScene:(UIWindowScene *)windowScene didUpdateCoordinateSpace:(id<UICoordinateSpace>)previousCoordinateSpace interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection *)previousTraitCollection {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WindowSceneDidUpdate" object:nil userInfo:@{
            @"interfaceOrientation": @(windowScene.interfaceOrientation),
            @"traitCollection": previousTraitCollection
        }];
    }
}

@end 