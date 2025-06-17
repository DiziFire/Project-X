#import "UIKit/UIKit.h"
#import "include/ellekit/ellekit.h"
#include <dlfcn.h>

// Independent implementation to check if apps are frozen
// This avoids any linker dependencies on FreezeManager
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *bundleExecutable;
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@end

// Function pointers for original implementations
static id (*orig_applicationWithBundleIdentifier)(id self, SEL _cmd, NSString *identifier);
static BOOL (*orig_launchWithDelegate)(id self, SEL _cmd, id delegate);
static BOOL (*orig_openApplicationWithBundleID)(id self, SEL _cmd, NSString *bundleID);
static BOOL (*orig_openURL)(id self, SEL _cmd, NSURL *url, NSDictionary *options);
static BOOL (*orig_activateApplication)(id self, SEL _cmd, id application, id icon, int location);
static id (*orig_createApplicationProcessForBundleID)(id self, SEL _cmd, NSString *bundleID);
static void (*orig_willActivateApplication)(id, SEL, id);

// Cache to improve performance and reduce CPU usage
static NSMutableDictionary *frozenStatusCache = nil;
static NSDate *cacheLastUpdated = nil;
static NSTimeInterval cacheRefreshInterval = 2.0; // Refresh cache every 2 seconds

// Direct implementation of isApplicationFrozen without requiring FreezeManager
static BOOL isApplicationFrozen(NSString *bundleID) {
    if (!bundleID) return NO;
    
    // Initialize cache if needed
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        frozenStatusCache = [NSMutableDictionary dictionary];
        cacheLastUpdated = [NSDate date];
    });
    
    // Check if we have a cached result for this bundle ID
    NSNumber *cachedStatus = frozenStatusCache[bundleID];
    
    // If cache is fresh (less than refresh interval) and we have a cached value, use it
    if (cachedStatus && [[NSDate date] timeIntervalSinceDate:cacheLastUpdated] < cacheRefreshInterval) {
        return [cachedStatus boolValue];
    }
    
    // Cache is either stale or missing the bundle ID, refresh the entire cache
    if ([[NSDate date] timeIntervalSinceDate:cacheLastUpdated] >= cacheRefreshInterval) {
        // Use the same UserDefaults suite as FreezeManager 
        NSUserDefaults *freezeDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.freezer"];
        NSDictionary *frozenApps = [freezeDefaults dictionaryForKey:@"FrozenApps"];
        
        // Update our cache
        [frozenStatusCache removeAllObjects];
        for (NSString *key in frozenApps) {
            frozenStatusCache[key] = frozenApps[key];
        }
        
        // Update cache timestamp
        cacheLastUpdated = [NSDate date];
        
        // Now check the updated cache
        cachedStatus = frozenStatusCache[bundleID];
    }
    
    // Return cached value or default to NO
    return [cachedStatus boolValue];
}

// Helper function to check if app should be blocked from launching
static BOOL shouldBlockAppLaunch(NSString *bundleID, NSString *appName) {
    if (!bundleID && !appName) return NO;
    
    // Check directly if the app is frozen by bundle ID
    if (bundleID && isApplicationFrozen(bundleID)) {
        NSLog(@"[FreezeManager] Blocked launch for frozen app with bundleID: %@", bundleID);
        return YES;
    }
    
    // Skip system critical apps
    NSArray *protectedApps = @[@"SpringBoard", @"backboardd", @"installd", @"ProjectX"];
    if (appName && [protectedApps containsObject:appName]) {
        return NO;
    }
    
    // Try to find the bundle ID from app name if only app name is provided
    if (!bundleID && appName) {
        // Try to look up bundle ID from app name
        Class LSApplicationWorkspace_class = NSClassFromString(@"LSApplicationWorkspace");
        if (LSApplicationWorkspace_class) {
            id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
            if (workspace) {
                // Get installed applications
                NSArray *apps = [workspace performSelector:@selector(allInstalledApplications)];
                for (id app in apps) {
                    NSString *executableName = [app performSelector:@selector(bundleExecutable)];
                    if ([executableName isEqualToString:appName]) {
                        NSString *foundBundleID = [app performSelector:@selector(bundleIdentifier)];
                        if (foundBundleID && isApplicationFrozen(foundBundleID)) {
                            NSLog(@"[FreezeManager] Blocked launch for frozen app with name: %@ (bundleID: %@)", appName, foundBundleID);
                            return YES;
                        }
                    }
                }
            }
        }
    }
    
    return NO;
}

// Hook SBApplicationController to prevent frozen apps from launching
static id new_applicationWithBundleIdentifier(id self, SEL _cmd, NSString *identifier) {
    // Check if app is frozen before getting instance
    if (shouldBlockAppLaunch(identifier, nil)) {
        // Instead of returning nil, let the original method run but then block activation
        // This prevents nil being passed to methods expecting valid app objects
        id appInstance = orig_applicationWithBundleIdentifier(self, _cmd, identifier);
        NSLog(@"[FreezeManager] Allowing app instance creation but will block activation: %@", identifier);
        return appInstance;
    }
    
    return orig_applicationWithBundleIdentifier(self, _cmd, identifier);
}

// Hook FBApplicationProcess to prevent frozen apps from spawning
static BOOL new_launchWithDelegate(id self, SEL _cmd, id delegate) {
    NSString *bundleIdentifier = [self performSelector:@selector(bundleIdentifier)];
    NSString *executablePath = [self performSelector:@selector(executablePath)];
    NSString *appName = [executablePath lastPathComponent];
    
    if (shouldBlockAppLaunch(bundleIdentifier, appName)) {
        NSLog(@"[FreezeManager] Blocked process launch for frozen app: %@", bundleIdentifier);
        // Return NO without calling original implementation
        return NO;
    }
    
    return orig_launchWithDelegate(self, _cmd, delegate);
}

// Hook LSApplicationWorkspace to prevent frozen apps from launching
static BOOL new_openApplicationWithBundleID(id self, SEL _cmd, NSString *bundleID) {
    if (shouldBlockAppLaunch(bundleID, nil)) {
        return NO;
    }
    
    return orig_openApplicationWithBundleID(self, _cmd, bundleID);
}

// Additional method to block app launching via URL schemes
static BOOL new_openURL(id self, SEL _cmd, NSURL *url, NSDictionary *options) {
    if (url) {
        NSString *scheme = [url scheme];
        
        // Check if this is an app URL scheme
        if (scheme && ![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
            // Try to find app with this URL scheme
            id appWithScheme = [self performSelector:@selector(applicationForOpeningResource:) withObject:url];
            if (appWithScheme) {
                NSString *bundleID = [appWithScheme performSelector:@selector(bundleIdentifier)];
                NSString *appName = [appWithScheme performSelector:@selector(bundleExecutable)];
                
                if (shouldBlockAppLaunch(bundleID, appName)) {
                    NSLog(@"[FreezeManager] Blocked URL scheme launch for frozen app: %@", bundleID);
                    return NO;
                }
            }
        }
    }
    
    return orig_openURL(self, _cmd, url, options);
}

// Hook SBUIController for iOS 14-15
static BOOL new_activateApplication(id self, SEL _cmd, id application, id icon, int location) {
    if (application) {
        NSString *bundleID = nil;
        NSString *appName = nil;
        
        // Try to get bundle ID using different methods
        if ([application respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID = [application performSelector:@selector(bundleIdentifier)];
        }
        
        // Try to get app name
        if ([application respondsToSelector:@selector(displayName)]) {
            appName = [application performSelector:@selector(displayName)];
        } else if ([application respondsToSelector:@selector(bundleExecutable)]) {
            appName = [application performSelector:@selector(bundleExecutable)];
        }
        
        if (shouldBlockAppLaunch(bundleID, appName)) {
            return NO;
        }
    }
    
    return orig_activateApplication(self, _cmd, application, icon, location);
}

// Additional hook to prevent crashes in SpringBoard's application animation system
static void new_willActivateApplication(id self, SEL _cmd, id application) {
    if (application) {
        NSString *bundleID = nil;
        
        if ([application respondsToSelector:@selector(bundleIdentifier)]) {
            bundleID = [application performSelector:@selector(bundleIdentifier)];
        }
        
        if (bundleID && isApplicationFrozen(bundleID)) {
            NSLog(@"[FreezeManager] Blocked activation animation for frozen app: %@", bundleID);
            // Return without calling original implementation to prevent animation
            return;
        }
    }
    
    // Call original implementation for non-frozen apps
    if (orig_willActivateApplication) {
        orig_willActivateApplication(self, _cmd, application);
    } else {
        NSLog(@"[FreezeManager] Warning: orig_willActivateApplication is NULL");
    }
}

// Hook SBApplicationProcessManager to prevent app spawning
static id new_createApplicationProcessForBundleID(id self, SEL _cmd, NSString *bundleID) {
    if (shouldBlockAppLaunch(bundleID, nil)) {
        NSLog(@"[FreezeManager] Blocked process creation for frozen app: %@", bundleID);
        // Instead of returning nil, create a dummy process object that won't actually launch
        // First get a valid process object for a system app that we can use as a placeholder
        id systemAppProcess = orig_createApplicationProcessForBundleID(self, _cmd, @"com.apple.Preferences");
        
        // Return the system app process but we'll block its launch in other hooks
        return systemAppProcess;
    }
    
    return orig_createApplicationProcessForBundleID(self, _cmd, bundleID);
}

// Setup function that installs all hooks
static void setupFreezeHooks(void) {
    // Only hook in SpringBoard process
    NSString *processName = [NSProcessInfo processInfo].processName;
    if (![processName isEqualToString:@"SpringBoard"]) {
        return;
    }
    
    NSLog(@"[FreezeManager] Initializing SpringBoard launch hooks with ElleKit");
    
    // Get the classes we need to hook
    Class SBApplicationController = NSClassFromString(@"SBApplicationController");
    Class FBApplicationProcess = NSClassFromString(@"FBApplicationProcess");
    Class LSApplicationWorkspace = NSClassFromString(@"LSApplicationWorkspace");
    Class SBUIController = NSClassFromString(@"SBUIController");
    Class SBApplicationProcessManager = NSClassFromString(@"SBApplicationProcessManager");
    
    // Hook SBApplicationController
    if (SBApplicationController) {
        SEL applicationWithBundleIdentifierSEL = @selector(applicationWithBundleIdentifier:);
        Method method = class_getInstanceMethod(SBApplicationController, applicationWithBundleIdentifierSEL);
        if (method) {
            orig_applicationWithBundleIdentifier = (id (*)(id, SEL, NSString *))method_getImplementation(method);
            method_setImplementation(method, (IMP)new_applicationWithBundleIdentifier);
            NSLog(@"[FreezeManager] Successfully hooked SBApplicationController");
        }
    }
    
    // Hook FBApplicationProcess
    if (FBApplicationProcess) {
        SEL launchWithDelegateSEL = @selector(launchWithDelegate:);
        Method method = class_getInstanceMethod(FBApplicationProcess, launchWithDelegateSEL);
        if (method) {
            orig_launchWithDelegate = (BOOL (*)(id, SEL, id))method_getImplementation(method);
            method_setImplementation(method, (IMP)new_launchWithDelegate);
            NSLog(@"[FreezeManager] Successfully hooked FBApplicationProcess");
        }
    }
    
    // Hook LSApplicationWorkspace
    if (LSApplicationWorkspace) {
        SEL openApplicationWithBundleIDSEL = @selector(openApplicationWithBundleID:);
        Method method = class_getInstanceMethod(LSApplicationWorkspace, openApplicationWithBundleIDSEL);
        if (method) {
            orig_openApplicationWithBundleID = (BOOL (*)(id, SEL, NSString *))method_getImplementation(method);
            method_setImplementation(method, (IMP)new_openApplicationWithBundleID);
            NSLog(@"[FreezeManager] Successfully hooked LSApplicationWorkspace openApplicationWithBundleID");
        }
        
        SEL openURLSEL = @selector(openURL:withOptions:);
        Method urlMethod = class_getInstanceMethod(LSApplicationWorkspace, openURLSEL);
        if (urlMethod) {
            orig_openURL = (BOOL (*)(id, SEL, NSURL *, NSDictionary *))method_getImplementation(urlMethod);
            method_setImplementation(urlMethod, (IMP)new_openURL);
            NSLog(@"[FreezeManager] Successfully hooked LSApplicationWorkspace openURL:withOptions:");
        }
    }
    
    // Hook SBUIController
    if (SBUIController) {
        SEL activateApplicationSEL = @selector(activateApplication:fromIcon:location:);
        Method method = class_getInstanceMethod(SBUIController, activateApplicationSEL);
        if (method) {
            orig_activateApplication = (BOOL (*)(id, SEL, id, id, int))method_getImplementation(method);
            method_setImplementation(method, (IMP)new_activateApplication);
            NSLog(@"[FreezeManager] Successfully hooked SBUIController");
        }
        
        // Hook willActivateApplication to prevent animation crashes
        SEL willActivateApplicationSEL = @selector(willActivateApplication:);
        Method willActivateMethod = class_getInstanceMethod(SBUIController, willActivateApplicationSEL);
        if (willActivateMethod) {
            orig_willActivateApplication = (void (*)(id, SEL, id))method_getImplementation(willActivateMethod);
            method_setImplementation(willActivateMethod, (IMP)new_willActivateApplication);
            NSLog(@"[FreezeManager] Successfully hooked SBUIController willActivateApplication");
        }
    }
    
    // Hook SBApplicationProcessManager
    if (SBApplicationProcessManager) {
        SEL createApplicationProcessForBundleIDSEL = @selector(createApplicationProcessForBundleID:);
        Method method = class_getInstanceMethod(SBApplicationProcessManager, createApplicationProcessForBundleIDSEL);
        if (method) {
            orig_createApplicationProcessForBundleID = (id (*)(id, SEL, NSString *))method_getImplementation(method);
            method_setImplementation(method, (IMP)new_createApplicationProcessForBundleID);
            NSLog(@"[FreezeManager] Successfully hooked SBApplicationProcessManager");
        }
    }
}

// Initialize hooks
__attribute__((constructor)) static void initHooks(void) {
    // Set up the hooks
    setupFreezeHooks();
} 