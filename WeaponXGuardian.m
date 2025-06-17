#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>

// Forward declarations for private API
extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define PROC_ALL_PIDS 1
#define PROC_PIDPATHINFO_MAXSIZE 4096

// UIKit constants
#ifndef UIBackgroundTaskInvalid
#define UIBackgroundTaskInvalid 0
#endif

static NSString * const kWeaponXGuardianKey = @"WeaponXGuardianActive";
static NSString * const kWeaponXProcessIDs = @"WeaponXProcessIDs";
static NSString * const kWeaponXDaemonPath = @"/var/jb/Library/WeaponX/WeaponXDaemon";
static NSString * const kWeaponXLaunchDaemonPath = @"/var/jb/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist";

@interface WeaponXGuardian : NSObject
@property (nonatomic, strong) NSTimer *guardianTimer;
@property (nonatomic, strong) NSMutableArray *protectedProcesses;
@property (nonatomic, strong) NSMutableDictionary *processInfo;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic, assign) BOOL isGuardianActive;
@property (nonatomic, strong) dispatch_source_t keepAliveTimer;

+ (instancetype)sharedInstance;
- (void)startGuardian;
- (void)stopGuardian;
- (void)registerProcess:(NSString *)processName;
- (void)unregisterProcess:(NSString *)processName;
@end

@implementation WeaponXGuardian

#pragma mark - Singleton Setup

+ (instancetype)sharedInstance {
    static WeaponXGuardian *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _protectedProcesses = [NSMutableArray array];
        _processInfo = [NSMutableDictionary dictionary];
        _isGuardianActive = NO;
        _backgroundTask = UIBackgroundTaskInvalid;
        
        // Only register ProjectX - let the daemon handle itself
        [self registerProcess:@"ProjectX"];
        
        // Register for notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillTerminate:)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
                                                   
        // Ensure daemon is running
        [self ensureDaemonIsRunning];
    }
    return self;
}

- (void)ensureDaemonIsRunning {
    // Check if daemon exists
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:kWeaponXDaemonPath]) {
        NSLog(@"[WeaponX] ⚠️ Daemon executable not found at %@", kWeaponXDaemonPath);
        return;
    }
    
    // Check if LaunchDaemon plist exists
    if (![fileManager fileExistsAtPath:kWeaponXLaunchDaemonPath]) {
        NSLog(@"[WeaponX] ⚠️ LaunchDaemon plist not found at %@", kWeaponXLaunchDaemonPath);
        return;
    }
    
    // Load the daemon using posix_spawn
    pid_t pid;
    const char *launchctl = "/bin/launchctl";
    const char *args[] = {
        launchctl,
        "load",
        [kWeaponXLaunchDaemonPath UTF8String],
        NULL
    };
    
    // Set up file actions
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    
    // Create pipe for output
    int pipe_fd[2];
    pipe(pipe_fd);
    posix_spawn_file_actions_adddup2(&actions, pipe_fd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipe_fd[1], STDERR_FILENO);
    
    // Spawn process
    int status = posix_spawn(&pid, launchctl, &actions, NULL, (char *const *)args, NULL);
    
    // Close write end of pipe
    close(pipe_fd[1]);
    
    if (status == 0) {
        // Read output from pipe
        char buffer[4096];
        ssize_t bytes_read = read(pipe_fd[0], buffer, sizeof(buffer) - 1);
        if (bytes_read > 0) {
            buffer[bytes_read] = '\0';
            NSLog(@"[WeaponX] ℹ️ launchctl output: %s", buffer);
        }
        
        // Wait for process to complete
        int wait_status;
        waitpid(pid, &wait_status, 0);
        
        if (WIFEXITED(wait_status) && WEXITSTATUS(wait_status) == 0) {
            NSLog(@"[WeaponX] ✅ Successfully loaded daemon");
        } else {
            NSLog(@"[WeaponX] ⚠️ Failed to load daemon, status: %d", WEXITSTATUS(wait_status));
        }
    } else {
        NSLog(@"[WeaponX] ⚠️ Failed to spawn launchctl process, error: %d", status);
    }
    
    // Clean up
    close(pipe_fd[0]);
    posix_spawn_file_actions_destroy(&actions);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopGuardian];
}

#pragma mark - Guardian Control

- (void)startGuardian {
    if (_isGuardianActive) {
        return;
    }
    
    _isGuardianActive = YES;
    
    // Store state in UserDefaults
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kWeaponXGuardianKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Register as a background task
    [self beginBackgroundTask];
    
    // Start process monitor timer
    [self startProcessMonitor];
    
    // Start keep-alive timer
    [self startKeepAliveTimer];
    
    // Create persistent state file
    [self createPersistentState];
    
    // Ensure daemon is running
    [self ensureDaemonIsRunning];
}

- (void)stopGuardian {
    if (!_isGuardianActive) {
        return;
    }
    
    _isGuardianActive = NO;
    
    // Clear UserDefaults state
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kWeaponXGuardianKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Stop timer
    if (_guardianTimer) {
        [_guardianTimer invalidate];
        _guardianTimer = nil;
    }
    
    // End background task
    [self endBackgroundTask];
    
    // Stop keep-alive timer
    if (_keepAliveTimer) {
        dispatch_source_cancel(_keepAliveTimer);
        _keepAliveTimer = nil;
    }
}

#pragma mark - Process Registration

- (void)registerProcess:(NSString *)processName {
    if (![_protectedProcesses containsObject:processName]) {
        [_protectedProcesses addObject:processName];
    }
}

- (void)unregisterProcess:(NSString *)processName {
    if ([_protectedProcesses containsObject:processName]) {
        [_protectedProcesses removeObject:processName];
    }
}

#pragma mark - Background Task Management

- (void)beginBackgroundTask {
    // Direct UIKit calls are having issues in tweak context
    // Instead, we'll use a simple timer to keep the app active
    if (!_guardianTimer) {
        _guardianTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                         target:self
                                                       selector:@selector(checkProtectedProcesses)
                                                       userInfo:nil
                                                        repeats:YES];
        
        [[NSRunLoop mainRunLoop] addTimer:_guardianTimer forMode:NSRunLoopCommonModes];
    }
    
    // Set active flag
    _backgroundTask = 1; // Just a placeholder since we're not using actual UIKit background tasks
}

- (void)endBackgroundTask {
    if (_guardianTimer) {
        [_guardianTimer invalidate];
        _guardianTimer = nil;
    }
    
    _backgroundTask = UIBackgroundTaskInvalid;
}

#pragma mark - Process Monitoring

- (void)startProcessMonitor {
    // Cancel existing timer if it exists
    if (_guardianTimer) {
        [_guardianTimer invalidate];
    }
    
    // Create a timer that fires every 2 seconds to check processes
    _guardianTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                     target:self
                                                   selector:@selector(checkProtectedProcesses)
                                                   userInfo:nil
                                                    repeats:YES];
    
    // Add timer to run loop to ensure it fires in background
    [[NSRunLoop mainRunLoop] addTimer:_guardianTimer forMode:NSRunLoopCommonModes];
    
    // Fire timer immediately to check processes now
    [_guardianTimer fire];
}

- (void)checkProtectedProcesses {
    if (!_isGuardianActive) {
        return;
    }
    
    NSMutableArray *pidsArray = [NSMutableArray array];
    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    
    if (numberOfProcesses <= 0) {
        return;
    }
    
    pid_t *pids = (pid_t *)malloc(sizeof(pid_t) * numberOfProcesses);
    if (!pids) {
        return;
    }
    
    numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pid_t) * numberOfProcesses);
    
    // Check each process against our protected list
    for (int i = 0; i < numberOfProcesses; i++) {
        if (pids[i] == 0) continue;
        
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        int result = proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));
        
        if (result > 0) {
            NSString *processPath = [NSString stringWithUTF8String:pathBuffer];
            NSString *processName = [processPath lastPathComponent];
            
            // Check if this is one of our protected processes
            for (NSString *protectedProcess in _protectedProcesses) {
                if ([processName hasPrefix:protectedProcess]) {
                    [pidsArray addObject:@(pids[i])];
                    
                    // Update our process info dictionary
                    _processInfo[protectedProcess] = @{
                        @"pid": @(pids[i]),
                        @"path": processPath,
                        @"lastSeen": [NSDate date]
                    };
                }
            }
        }
    }
    
    free(pids);
    
    // Check if we're missing any processes that need to be restarted
    NSMutableArray *missingProcesses = [NSMutableArray array];
    for (NSString *process in _protectedProcesses) {
        if (!_processInfo[process]) {
            [missingProcesses addObject:process];
        } else {
            // Check if process was seen in the last 10 seconds
            NSDate *lastSeen = _processInfo[process][@"lastSeen"];
            NSTimeInterval timeSinceLastSeen = [[NSDate date] timeIntervalSinceDate:lastSeen];
            if (timeSinceLastSeen > 10.0) {
                [missingProcesses addObject:process];
            }
        }
    }
    
    // Restart any missing processes
    for (NSString *missingProcess in missingProcesses) {
        [self restartProcess:missingProcess];
    }
    
    // Save PIDs to UserDefaults for recovery
    [[NSUserDefaults standardUserDefaults] setObject:pidsArray forKey:kWeaponXProcessIDs];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)restartProcess:(NSString *)processName {
    // Check if we have a path for this process
    NSString *processPath = nil;
    
    if ([processName isEqualToString:@"ProjectX"]) {
        // Path to the ProjectX app
        processPath = @"/var/jb/Applications/ProjectX.app/ProjectX";
    } else if ([processName isEqualToString:@"WeaponXDaemon"]) {
        // Path to the daemon
        processPath = @"/var/jb/Library/WeaponX/WeaponXDaemon";
    }
    
    if (!processPath) {
        return;
    }
    
    // Check if the file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:processPath]) {
        return;
    }
    
    // Launch the process
    pid_t pid;
    const char *path = [processPath UTF8String];
    const char *args[] = {path, NULL};
    posix_spawn_file_actions_t actions;
    
    posix_spawn_file_actions_init(&actions);
    int status = posix_spawn(&pid, path, &actions, NULL, (char *const *)args, NULL);
    posix_spawn_file_actions_destroy(&actions);
    
    if (status == 0) {
        // Update process info with new PID
        _processInfo[processName] = @{
            @"pid": @(pid),
            @"path": processPath,
            @"lastSeen": [NSDate date]
        };
    }
}

#pragma mark - Keep-Alive Mechanisms

- (void)startKeepAliveTimer {
    // Cancel existing timer if it exists
    if (_keepAliveTimer) {
        dispatch_source_cancel(_keepAliveTimer);
        _keepAliveTimer = nil;
    }
    
    // Create a dispatch timer that fires every 15 minutes
    _keepAliveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    
    uint64_t interval = 15 * 60 * NSEC_PER_SEC; // 15 minutes
    dispatch_source_set_timer(_keepAliveTimer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, 5 * NSEC_PER_SEC);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_keepAliveTimer, ^{
        [weakSelf performKeepAliveActions];
    });
    
    dispatch_resume(_keepAliveTimer);
}

- (void)performKeepAliveActions {
    // 1. Refresh background task
    dispatch_async(dispatch_get_main_queue(), ^{
        [self endBackgroundTask];
        [self beginBackgroundTask];
    });
    
    // 2. Update our persistent state
    [self updatePersistentState];
    
    // 3. Force check all protected processes
    [self checkProtectedProcesses];
}

#pragma mark - Persistent State Management

- (void)createPersistentState {
    // Create a directory to store our persistent state
    NSString *guardianDir = @"/var/jb/Library/WeaponX/Guardian";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:guardianDir]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:guardianDir withIntermediateDirectories:YES attributes:nil error:&error];
        
        if (error) {
            return;
        }
    }
    
    // Create state file
    NSString *statePath = [guardianDir stringByAppendingPathComponent:@"guardian.plist"];
    NSDictionary *state = @{
        @"active": @(YES),
        @"protectedProcesses": self.protectedProcesses,
        @"startTime": [NSDate date]
    };
    
    [state writeToFile:statePath atomically:YES];
}

- (void)updatePersistentState {
    NSString *statePath = @"/var/jb/Library/WeaponX/Guardian/guardian.plist";
    NSDictionary *state = @{
        @"active": @(_isGuardianActive),
        @"protectedProcesses": self.protectedProcesses,
        @"lastUpdateTime": [NSDate date],
        @"processInfo": self.processInfo
    };
    
    [state writeToFile:statePath atomically:YES];
}

#pragma mark - App Lifecycle Notifications

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    // Update state
    [self updatePersistentState];
    
    // Check processes immediately
    [self checkProtectedProcesses];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    // Check processes
    [self checkProtectedProcesses];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // Update state with termination flag
    NSString *statePath = @"/var/jb/Library/WeaponX/Guardian/guardian.plist";
    NSDictionary *state = @{
        @"active": @(YES),
        @"needsRestart": @(YES),
        @"terminationTime": [NSDate date],
        @"protectedProcesses": self.protectedProcesses
    };
    
    [state writeToFile:statePath atomically:YES];
}

@end

// Entry point initializer - call this when you want to start the guardian
void StartWeaponXGuardian(void) {
    [[WeaponXGuardian sharedInstance] startGuardian];
} 