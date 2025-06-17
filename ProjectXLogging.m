#import "ProjectXLogging.h"
#import <Foundation/Foundation.h>
#import <os/log.h>

// Global logging function
void PXLog(NSString *format, ...) {
    static NSDateFormatter *dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    });
    
    @try {
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        
        // Get timestamp
        NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
        
        // Create formatted log with timestamp
        NSString *logMessage = [NSString stringWithFormat:@"[ProjectX %@] %@", timestamp, message];
        
        // Determine log file path
        NSString *logFilePath = nil;
        
        // Check for rootless jailbreak paths
        NSArray *possiblePaths = @[
            @"/var/jb/var/mobile/Library/Logs/ProjectX",
            @"/var/jb/private/var/mobile/Library/Logs/ProjectX",
            @"/var/LIB/var/mobile/Library/Logs/ProjectX",
            @"/var/mobile/Library/Logs/ProjectX"
        ];
        
        for (NSString *path in possiblePaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                logFilePath = [path stringByAppendingPathComponent:@"ProjectX.log"];
                break;
            }
        }
        
        // Fallback to temp directory if no log paths found
        if (!logFilePath) {
            logFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ProjectX.log"];
            
            // Attempt to create a logs directory in a location we have access to
            NSString *fallbackPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ProjectXLogs"];
            [[NSFileManager defaultManager] createDirectoryAtPath:fallbackPath 
                                      withIntermediateDirectories:YES 
                                                       attributes:nil 
                                                            error:nil];
            logFilePath = [fallbackPath stringByAppendingPathComponent:@"ProjectX.log"];
        }
        
        // Write to file
        if (logFilePath) {
            @try {
                NSFileHandle *fileHandle = nil;
                
                // Create file if it doesn't exist
                if (![[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
                    [[logMessage stringByAppendingString:@"\n"] writeToFile:logFilePath 
                                                              atomically:YES 
                                                                encoding:NSUTF8StringEncoding 
                                                                   error:nil];
                } else {
                    // Append to existing file
                    fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
                    [fileHandle seekToEndOfFile];
                    [fileHandle writeData:[[logMessage stringByAppendingString:@"\n"] 
                                          dataUsingEncoding:NSUTF8StringEncoding]];
                    [fileHandle closeFile];
                }
            } @catch (NSException *e) {
                // If writing to file fails, at least we have the NSLog
            }
        }
        
        // Modern logging via os_log if available (iOS 10+)
        if (@available(iOS 10.0, *)) {
            os_log_t logObject = os_log_create("com.hydra.projectx", "general");
            os_log_with_type(logObject, OS_LOG_TYPE_DEFAULT, "%{public}@", message);
        }
        
    } @catch (NSException *exception) {
        // Last resort recovery - if logging itself fails
    }
}

// Error recovery helper
void PXLogError(NSError *error, NSString *context) {
    if (!error) {
        return;
    }
    
    PXLog(@"[%@] Error %ld: %@", context, (long)error.code, error.localizedDescription);
    
    // Attempt recovery based on error
    switch (error.code) {
        case 4001: // Settings save error
            [[NSUserDefaults standardUserDefaults] synchronize];
            break;
            
        case 3001: // Invalid bundle ID
        case 3002: // App not found
            break;
            
        default:
            if ([error.domain isEqualToString:NSCocoaErrorDomain]) {
                // Check permissions silently
            }
            break;
    }
} 