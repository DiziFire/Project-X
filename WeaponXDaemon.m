#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <os/log.h>

// Constants
static const int kCheckInterval = 5; // Check every 5 seconds
static NSString *kGuardianDir = nil; // Will be initialized in init
static NSString *kProjectXPath = nil; // Will be initialized in init
static NSString *ROOT_PREFIX = nil; // Will be set based on environment
static os_log_t weaponx_log = NULL;
static BOOL debugMode = NO;

// Forward declarations
extern int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

#define PROC_ALL_PIDS 1
#define PROC_PIDPATHINFO_MAXSIZE 4096

@interface WeaponXDaemon : NSObject
@property (nonatomic, strong) NSTimer *monitorTimer;
@property (nonatomic, strong) NSMutableDictionary *processInfo;
@property (nonatomic, strong) NSMutableArray *protectedProcesses;
@end

@implementation WeaponXDaemon

+ (void)initialize {
    if (self == [WeaponXDaemon class]) {
        // Initialize the os_log handle for system console
        weaponx_log = os_log_create("com.hydra.weaponx.guardian", "daemon");
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Check for rootless environment
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:@"/var/jb"]) {
            ROOT_PREFIX = @"/var/jb";
            NSLog(@"Rootless jailbreak detected - using prefix: %@", ROOT_PREFIX);
        } else if ([fileManager fileExistsAtPath:@"/var/LIB"]) {
            ROOT_PREFIX = @"/var/LIB";
            NSLog(@"Dopamine rootless jailbreak detected - using prefix: %@", ROOT_PREFIX);
        } else {
            ROOT_PREFIX = @"";
            NSLog(@"Traditional jailbreak detected");
        }
        
        // Set paths with the appropriate prefix
        kGuardianDir = [ROOT_PREFIX stringByAppendingString:@"/Library/WeaponX/Guardian"];
        kProjectXPath = [ROOT_PREFIX stringByAppendingString:@"/Applications/ProjectX.app/ProjectX"];
        
        _processInfo = [NSMutableDictionary dictionary];
        _protectedProcesses = [NSMutableArray arrayWithObjects:@"ProjectX", nil];
        
        NSLog(@"Using Guardian dir: %@", kGuardianDir);
        NSLog(@"Using ProjectX path: %@", kProjectXPath);
        
        // Create guardian directory if needed
        [self ensureGuardianDirectoryExists];
        
        // Start logging
        [self log:[NSString stringWithFormat:@"WeaponXDaemon initialized (rootless: %@, debug: %@)", 
                   ROOT_PREFIX.length > 0 ? @"YES" : @"NO",
                   debugMode ? @"YES" : @"NO"] 
         withType:OS_LOG_TYPE_INFO];
        
        // Write to stderr directly for visibility
        fprintf(stderr, "WeaponXDaemon initialized with root prefix: %s\n", [ROOT_PREFIX UTF8String]);
    }
    return self;
}

- (void)startDaemon {
    [self log:@"WeaponXDaemon starting..." withType:OS_LOG_TYPE_INFO];
    
    // Schedule monitoring timer
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:kCheckInterval
                                                       target:self
                                                     selector:@selector(checkProcesses)
                                                     userInfo:nil
                                                      repeats:YES];
    
    // Add to runloop
    [[NSRunLoop currentRunLoop] addTimer:self.monitorTimer forMode:NSRunLoopCommonModes];
    
    // Check immediately
    [self checkProcesses];
    
    // Keep runloop running
    [[NSRunLoop currentRunLoop] run];
}

- (void)checkProcesses {
    [self log:@"Checking processes..." withType:OS_LOG_TYPE_DEBUG];
    
    // Get all running processes
    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    
    if (numberOfProcesses <= 0) {
        [self log:@"Failed to get process list" withType:OS_LOG_TYPE_ERROR];
        return;
    }
    
    pid_t *pids = (pid_t *)malloc(sizeof(pid_t) * numberOfProcesses);
    if (!pids) {
        [self log:@"Failed to allocate memory for process IDs" withType:OS_LOG_TYPE_ERROR];
        return;
    }
    
    numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pid_t) * numberOfProcesses);
    
    // Check for each protected process
    NSMutableSet *foundProcesses = [NSMutableSet set];
    
    for (int i = 0; i < numberOfProcesses; i++) {
        if (pids[i] == 0) continue;
        
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        int result = proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));
        
        if (result > 0) {
            NSString *processPath = [NSString stringWithUTF8String:pathBuffer];
            NSString *processName = [processPath lastPathComponent];
            
            for (NSString *protectedName in self.protectedProcesses) {
                if ([processName hasPrefix:protectedName]) {
                    [self log:[NSString stringWithFormat:@"Found protected process: %@ (PID: %d)", processName, pids[i]] withType:OS_LOG_TYPE_INFO];
                    [foundProcesses addObject:protectedName];
                    
                    // Update process info
                    self.processInfo[protectedName] = @{
                        @"pid": @(pids[i]),
                        @"path": processPath,
                        @"lastSeen": [NSDate date]
                    };
                }
            }
        }
    }
    
    free(pids);
    
    // Determine which processes need to be started
    NSMutableArray *missingProcesses = [NSMutableArray array];
    
    for (NSString *processName in self.protectedProcesses) {
        if (![foundProcesses containsObject:processName]) {
            [missingProcesses addObject:processName];
            [self log:[NSString stringWithFormat:@"Protected process missing: %@", processName] withType:OS_LOG_TYPE_INFO];
        }
    }
    
    // Start missing processes
    for (NSString *processName in missingProcesses) {
        [self startProcess:processName];
    }
    
    // Update state file
    [self updateStateFile];
}

- (void)startProcess:(NSString *)processName {
    [self log:[NSString stringWithFormat:@"Starting process: %@", processName] withType:OS_LOG_TYPE_INFO];
    
    NSString *executablePath = nil;
    
    if ([processName isEqualToString:@"ProjectX"]) {
        executablePath = kProjectXPath;
    }
    
    if (!executablePath) {
        [self log:[NSString stringWithFormat:@"No executable path for process: %@", processName] withType:OS_LOG_TYPE_ERROR];
        return;
    }
    
    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:executablePath]) {
        [self log:[NSString stringWithFormat:@"Executable not found: %@", executablePath] withType:OS_LOG_TYPE_ERROR];
        return;
    }
    
    // Launch process
    pid_t pid;
    const char *path = [executablePath UTF8String];
    const char *args[] = {path, NULL};
    posix_spawn_file_actions_t actions;
    
    posix_spawn_file_actions_init(&actions);
    int status = posix_spawn(&pid, path, &actions, NULL, (char *const *)args, NULL);
    posix_spawn_file_actions_destroy(&actions);
    
    if (status == 0) {
        [self log:[NSString stringWithFormat:@"Successfully started process %@ (PID: %d)", processName, pid] withType:OS_LOG_TYPE_INFO];
        
        // Update process info
        self.processInfo[processName] = @{
            @"pid": @(pid),
            @"path": executablePath,
            @"lastSeen": [NSDate date],
            @"startedBy": @"daemon"
        };
    } else {
        [self log:[NSString stringWithFormat:@"Failed to start process %@ (Error: %d)", processName, status] withType:OS_LOG_TYPE_ERROR];
    }
}

#pragma mark - Utility Methods

- (void)ensureGuardianDirectoryExists {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:kGuardianDir]) {
        NSError *error = nil;
        BOOL success = [fileManager createDirectoryAtPath:kGuardianDir 
              withIntermediateDirectories:YES 
                               attributes:nil 
                                    error:&error];
        
        if (!success) {
            NSLog(@"Failed to create guardian directory: %@", error);
            // Try with posix methods as fallback
            mkdir([kGuardianDir UTF8String], 0755);
        }
        
        // Set permissions explicitly to ensure we can write
        chmod([kGuardianDir UTF8String], 0755);
        
        // Create empty log files
        NSString *stdoutPath = [kGuardianDir stringByAppendingPathComponent:@"guardian-stdout.log"];
        NSString *stderrPath = [kGuardianDir stringByAppendingPathComponent:@"guardian-stderr.log"];
        NSString *daemonPath = [kGuardianDir stringByAppendingPathComponent:@"daemon.log"];
        
        [@"" writeToFile:stdoutPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [@"" writeToFile:stderrPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [@"" writeToFile:daemonPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        
        // Set log file permissions
        chmod([stdoutPath UTF8String], 0664);
        chmod([stderrPath UTF8String], 0664);
        chmod([daemonPath UTF8String], 0664);
        
        NSLog(@"Created Guardian directory and log files");
    }
}

- (void)updateStateFile {
    NSString *statePath = [kGuardianDir stringByAppendingPathComponent:@"daemon-state.plist"];
    NSDictionary *state = @{
        @"active": @YES,
        @"processInfo": self.processInfo,
        @"lastCheck": [NSDate date],
        @"protectedProcesses": self.protectedProcesses
    };
    
    [state writeToFile:statePath atomically:YES];
}

- (void)log:(NSString *)message withType:(os_log_type_t)type {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logMessage = [NSString stringWithFormat:@"[WeaponX] [%@] %@", timestamp, message];
    
    // Log to system console
    os_log_with_type(weaponx_log, type, "%{public}@", logMessage);
    
    // Also log to file
    NSString *logPath = [kGuardianDir stringByAppendingPathComponent:@"daemon.log"];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[[logMessage stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        // Try to create the file if it doesn't exist
        [@"" writeToFile:logPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [logMessage writeToFile:logPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
    
    // Also log to stderr for debug visibility
    if (debugMode || type == OS_LOG_TYPE_ERROR || type == OS_LOG_TYPE_FAULT) {
        fprintf(stderr, "%s\n", [logMessage UTF8String]);
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Parse command line arguments
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            if ([arg isEqualToString:@"--debug"] || [arg isEqualToString:@"-d"]) {
                debugMode = YES;
            }
        }
        
        NSLog(@"WeaponXDaemon starting (debug mode: %@)", debugMode ? @"ON" : @"OFF");
        
        // Write directly to stderr for visibility
        fprintf(stderr, "WeaponXDaemon starting (debug mode: %s)\n", debugMode ? "ON" : "OFF");
        
        // Start the daemon
        WeaponXDaemon *daemon = [[WeaponXDaemon alloc] init];
        [daemon startDaemon];
    }
    return 0;
} 