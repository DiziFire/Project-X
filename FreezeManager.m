#import "FreezeManager.h"
#import "IdentifierManager.h"
#import <spawn.h>
#import <sys/wait.h>

@interface FreezeManager ()
@property (nonatomic, strong) BottomButtons *bottomButtons;
@property (nonatomic, strong) IdentifierManager *identifierManager;
@property (nonatomic, strong) NSMutableDictionary *frozenApps;
@end

@implementation FreezeManager

+ (instancetype)sharedManager {
    static FreezeManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        _bottomButtons = [BottomButtons sharedInstance];
        _identifierManager = [IdentifierManager sharedManager];
        _frozenApps = [NSMutableDictionary dictionary];
        
        // Load frozen state from UserDefaults - Use suite name to avoid conflicts
        NSUserDefaults *freezeDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.freezer"];
        NSDictionary *savedState = [freezeDefaults dictionaryForKey:@"FrozenApps"];
        if (savedState) {
            [_frozenApps setDictionary:savedState];
            NSLog(@"[FreezeManager] Loaded frozen app state: %@", savedState);
        } else {
            // Try to load from standard UserDefaults as fallback for backward compatibility
            NSDictionary *oldSavedState = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"FrozenApps"];
            if (oldSavedState) {
                [_frozenApps setDictionary:oldSavedState];
                NSLog(@"[FreezeManager] Loaded frozen app state from standard defaults (legacy): %@", oldSavedState);
                
                // Migrate the data to the new location
                [self saveFrozenState];
                
                // Clear the data from the old location
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"FrozenApps"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
        }
    }
    return self;
}

#pragma mark - App Freezing Management

- (void)freezeApplication:(NSString *)bundleID {
    if (!bundleID) {
        NSLog(@"[FreezeManager] Error: Invalid bundle ID");
        return;
    }
    
    // Skip if the bundleID matches our own tweak's bundle ID
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        NSLog(@"[FreezeManager] Skipping termination of our own tweak");
        return;
    }
    
    // Verify app is installed and enabled
    NSDictionary *appInfo = [self.identifierManager getApplicationInfo:bundleID];
    if (!appInfo || ![appInfo[@"installed"] boolValue]) {
        NSLog(@"[FreezeManager] App is not installed: %@", bundleID);
        return;
    }
    
    if (![self.identifierManager isApplicationEnabled:bundleID]) {
        NSLog(@"[FreezeManager] Skipping freeze for disabled app: %@", bundleID);
        return;
    }
    
    // Kill the application
    [self killApplication:bundleID];
    
    // Update frozen state
    self.frozenApps[bundleID] = @YES;
    [self saveFrozenState];
    
    // Post notification for UI update
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AppFrozenStateChanged"
                                                    object:self
                                                  userInfo:@{@"bundleID": bundleID}];
}

- (void)unfreezeApplication:(NSString *)bundleID {
    if (!bundleID) {
        NSLog(@"[FreezeManager] Error: Invalid bundle ID for unfreeze");
        return;
    }
    
    // Skip if the bundleID matches our own tweak's bundle ID
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        NSLog(@"[FreezeManager] Skipping unfreeze of our own tweak");
        return;
    }
    
    // Verify app is installed and enabled
    NSDictionary *appInfo = [self.identifierManager getApplicationInfo:bundleID];
    if (!appInfo || ![appInfo[@"installed"] boolValue]) {
        NSLog(@"[FreezeManager] App is not installed: %@", bundleID);
        return;
    }
    
    if (![self.identifierManager isApplicationEnabled:bundleID]) {
        NSLog(@"[FreezeManager] App is not enabled: %@", bundleID);
        return;
    }
    
    // Remove from frozen state
    [self.frozenApps removeObjectForKey:bundleID];
    [self saveFrozenState];
    
    // Post notification for UI update
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AppFrozenStateChanged"
                                                    object:self
                                                  userInfo:@{@"bundleID": bundleID}];
}

- (BOOL)isApplicationFrozen:(NSString *)bundleID {
    return [self.frozenApps[bundleID] boolValue];
}

#pragma mark - Helper Methods

- (void)saveFrozenState {
    // Use suite name to avoid conflicts with other settings
    NSUserDefaults *freezeDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.freezer"];
    [freezeDefaults setObject:self.frozenApps forKey:@"FrozenApps"];
    [freezeDefaults synchronize];
    
    NSLog(@"[FreezeManager] Saved frozen app state: %@", self.frozenApps);
}

- (void)killApplication:(NSString *)bundleID {
    if (!bundleID) return;
    
    // Get the executable name from LSApplicationProxy
    LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!appProxy) {
        NSLog(@"[FreezeManager] Could not find application proxy for bundle ID: %@", bundleID);
        return;
    }
    
    NSString *executableName = appProxy.bundleExecutable;
    if (!executableName || ![executableName length]) {
        NSLog(@"[FreezeManager] Could not find executable name for app: %@", bundleID);
        return;
    }
    
    // Skip system critical processes
    NSArray *protectedProcesses = @[@"SpringBoard", @"backboardd", @"ProjectX", @"installd", @"assertiond"];
    if ([protectedProcesses containsObject:executableName]) {
        // NSLog(@"[FreezeManager] Skipping protected process: %@", executableName);
        return;
    }
    
    // Verify executable name is valid UTF-8
    const char *executableStr = [executableName UTF8String];
    if (!executableStr) {
        NSLog(@"[FreezeManager] Invalid executable name encoding for app: %@", bundleID);
        return;
    }
    
    // Check for different killall paths based on jailbreak type
    NSArray *killallPaths = @[
        @"/var/jb/usr/bin/killall",              // Dopamine path
        @"/usr/bin/killall",                     // Traditional/Palera1n path
        @"/var/jb/bin/killall",                  // Alternative Dopamine path
        @"/private/preboot/jb/usr/bin/killall"   // Additional Palera1n path
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *killallPath = nil;
    
    // Find the first available killall binary
    for (NSString *path in killallPaths) {
        if ([fileManager fileExistsAtPath:path]) {
            killallPath = path;
            break;
        }
    }
    
    if (!killallPath) {
        NSLog(@"[FreezeManager] Error: Could not find a valid killall binary path");
        return;
    }
    
    // Kill the app using killall -9 command
    pid_t pid;
    int status;
    const char *killallPathStr = [killallPath UTF8String];
    
    char *const argv[] = {(char *)"killall", (char *)"-9", (char *)executableStr, NULL};
    
    NSLog(@"[FreezeManager] Using killall from: %@ to kill process: %@", killallPath, executableName);
    
    @try {
        if (posix_spawn(&pid, killallPathStr, NULL, NULL, argv, NULL) == 0) {
            if (waitpid(pid, &status, WEXITED) != -1) {
                if (WIFEXITED(status)) {
                    if (WEXITSTATUS(status) == 0) {
                        NSLog(@"[FreezeManager] Successfully killed app %@ via executable name: %@", bundleID, executableName);
                    } else {
                        NSLog(@"[FreezeManager] Process exited with status %d for app %@", WEXITSTATUS(status), bundleID);
                    }
                } else if (WIFSIGNALED(status)) {
                    NSLog(@"[FreezeManager] Process killed by signal %d for app %@", WTERMSIG(status), bundleID);
                }
            } else {
                NSLog(@"[FreezeManager] Failed to wait for process termination: %s", strerror(errno));
            }
        } else {
            NSLog(@"[FreezeManager] Failed to spawn killall process: %s", strerror(errno));
        }
    } @catch (NSException *exception) {
        NSLog(@"[FreezeManager] Exception while killing app %@: %@", bundleID, exception);
    }
    
    // Add a small delay to ensure processes are terminated
    usleep(100000); // 100ms delay
}

@end