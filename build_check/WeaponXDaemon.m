#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

// Constants
static const int kCheckInterval = 5; // Check every 5 seconds
static NSString * const kGuardianDir = @"/Library/WeaponX/Guardian";
static NSString * const kProjectXPath = @"/Applications/ProjectX.app/ProjectX";

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

- (instancetype)init {
    self = [super init];
    if (self) {
        _processInfo = [NSMutableDictionary dictionary];
        _protectedProcesses = [NSMutableArray arrayWithObjects:@"ProjectX", nil];
        
        // Create guardian directory if needed
        [self ensureGuardianDirectoryExists];
        
        // Start logging
        [self log:@"WeaponXDaemon initialized"];
    }
    return self;
}

- (void)startDaemon {
    [self log:@"WeaponXDaemon starting..."];
    
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
    [self log:@"Checking processes..."];
    
    // Get all running processes
    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    
    if (numberOfProcesses <= 0) {
        [self log:@"Failed to get process list"];
        return;
    }
    
    pid_t *pids = (pid_t *)malloc(sizeof(pid_t) * numberOfProcesses);
    if (!pids) {
        [self log:@"Failed to allocate memory for process IDs"];
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
                    [self log:[NSString stringWithFormat:@"Found protected process: %@ (PID: %d)", processName, pids[i]]];
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
    [self log:[NSString stringWithFormat:@"Starting process: %@", processName]];
    
    NSString *executablePath = nil;
    
    if ([processName isEqualToString:@"ProjectX"]) {
        executablePath = kProjectXPath;
    }
    
    if (!executablePath) {
        [self log:[NSString stringWithFormat:@"No executable path for process: %@", processName]];
        return;
    }
    
    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:executablePath]) {
        [self log:[NSString stringWithFormat:@"Executable not found: %@", executablePath]];
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
        [self log:[NSString stringWithFormat:@"Successfully started process %@ (PID: %d)", processName, pid]];
        
        // Update process info
        self.processInfo[processName] = @{
            @"pid": @(pid),
            @"path": executablePath,
            @"lastSeen": [NSDate date],
            @"startedBy": @"daemon"
        };
    } else {
        [self log:[NSString stringWithFormat:@"Failed to start process %@ (Error: %d)", processName, status]];
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

- (void)log:(NSString *)message {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logMessage = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSLog(@"%@", logMessage);
    
    // Also write to log file
    NSString *logPath = [kGuardianDir stringByAppendingPathComponent:@"daemon.log"];
    
    @try {
        // Ensure Guardian directory exists
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:kGuardianDir]) {
            [fileManager createDirectoryAtPath:kGuardianDir 
                  withIntermediateDirectories:YES 
                                   attributes:nil 
                                        error:nil];
            // Set permissions
            chmod([kGuardianDir UTF8String], 0755);
        }
        
        // Append log message to file
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        } else {
            // Create log file if it doesn't exist
            [logMessage writeToFile:logPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
            // Set permissions
            chmod([logPath UTF8String], 0664);
        }
    } @catch (NSException *exception) {
        NSLog(@"Error writing to log file: %@", exception);
    }
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Create and start daemon
        WeaponXDaemon *daemon = [[WeaponXDaemon alloc] init];
        [daemon startDaemon];
    }
    return 0;
} 