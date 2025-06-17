#import <Foundation/Foundation.h>
#import <syslog.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <dispatch/dispatch.h>
#import <spawn.h>
#import <sys/wait.h>

// Declare the environ variable for posix_spawn
extern char **environ;

// XPC typedefs and constants
typedef void *xpc_object_t;
typedef void *xpc_connection_t;
typedef void (^xpc_handler_t)(xpc_object_t);
typedef const struct _xpc_type_s *xpc_type_t;

// XPC constants - Define them directly since we don't have the XPC framework
// This is a simplified approach for our purposes
xpc_object_t XPC_ERROR_CONNECTION_INTERRUPTED = (xpc_object_t)1;
xpc_object_t XPC_ERROR_CONNECTION_INVALID = (xpc_object_t)2;
xpc_type_t XPC_TYPE_DICTIONARY = (xpc_type_t)1;
xpc_type_t XPC_TYPE_ERROR = (xpc_type_t)2;
xpc_type_t XPC_TYPE_BOOL = (xpc_type_t)3;
xpc_type_t XPC_TYPE_CONNECTION = (xpc_type_t)4;
const char *XPC_ERROR_KEY_DESCRIPTION = "description";

// XPC function declarations - we'll implement simplified versions
void xpc_release(xpc_object_t object) {
    // No-op implementation for our custom XPC
}

const char *xpc_dictionary_get_string(xpc_object_t dictionary, const char *key) {
    // Simplified implementation
    return NULL;
}

void xpc_dictionary_set_string(xpc_object_t dictionary, const char *key, const char *value) {
    // Simplified implementation
}

void xpc_dictionary_set_bool(xpc_object_t dictionary, const char *key, bool value) {
    // Simplified implementation
}

bool xpc_dictionary_get_bool(xpc_object_t dictionary, const char *key) {
    // Simplified implementation
    return false;
}

xpc_connection_t xpc_connection_create_mach_service(const char *name, dispatch_queue_t queue, uint64_t flags) {
    // Simplified implementation
    return NULL;
}

void xpc_connection_set_event_handler(xpc_connection_t connection, xpc_handler_t handler) {
    // Simplified implementation
}

void xpc_connection_resume(xpc_connection_t connection) {
    // Simplified implementation
}

xpc_object_t xpc_dictionary_create(const char * const *keys, const xpc_object_t *values, size_t count) {
    // Simplified implementation
    return NULL;
}

void xpc_connection_send_message(xpc_connection_t connection, xpc_object_t message) {
    // Simplified implementation
}

xpc_object_t xpc_dictionary_create_reply(xpc_object_t original) {
    // Simplified implementation
    return NULL;
}

xpc_type_t xpc_get_type(xpc_object_t object) {
    // Simplified implementation
    return NULL;
}

// Constants
static NSString *const kWeaponXHelperServiceName = @"com.weaponx.mounthelper";
#define XPC_CONNECTION_MACH_SERVICE_LISTENER (1 << 0)

// Function declarations
static int fs_snapshot_mount(const char *volume, const char *mount_path, const char *snapshot, uint32_t flags);
static void handle_mount_request(xpc_object_t request, xpc_object_t reply);
static void handle_unmount_request(xpc_object_t request, xpc_object_t reply);
static BOOL ensure_directory_exists(NSString *path);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Set up logging
        syslog(LOG_NOTICE, "[WeaponX] Mount daemon starting");
        
        // Create XPC listener
        xpc_connection_t listener = xpc_connection_create_mach_service(
            [kWeaponXHelperServiceName UTF8String],
            dispatch_get_main_queue(),
            XPC_CONNECTION_MACH_SERVICE_LISTENER
        );
        
        if (!listener) {
            syslog(LOG_ERR, "[WeaponX] Failed to create XPC listener");
            return 1;
        }
        
        // Set connection handler
        xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
            xpc_type_t type = xpc_get_type(event);
            
            if (type == XPC_TYPE_CONNECTION) {
                xpc_connection_t connection = event;
                
                xpc_connection_set_event_handler(connection, ^(xpc_object_t message) {
                    xpc_type_t messageType = xpc_get_type(message);
                    
                    if (messageType == XPC_TYPE_DICTIONARY) {
                        // Handle the message
                        const char *operation = xpc_dictionary_get_string(message, "operation");
                        
                        // Create reply dictionary
                        xpc_object_t reply = xpc_dictionary_create_reply(message);
                        
                        if (strcmp(operation, "mount") == 0) {
                            handle_mount_request(message, reply);
                        } else if (strcmp(operation, "unmount") == 0) {
                            handle_unmount_request(message, reply);
                        } else {
                            syslog(LOG_WARNING, "[WeaponX] Unknown operation: %s", operation);
                            xpc_dictionary_set_bool(reply, "success", false);
                            xpc_dictionary_set_string(reply, "error", "Unknown operation");
                        }
                        
                        // Send reply
                        xpc_connection_send_message(connection, reply);
                        xpc_release(reply);
                    }
                });
                
                xpc_connection_resume(connection);
            }
        });
        
        xpc_connection_resume(listener);
        
        syslog(LOG_NOTICE, "[WeaponX] Mount daemon ready to accept connections");
        
        // Run forever
        dispatch_main();
    }
    
    return 0;
}

// Handle mount request
static void handle_mount_request(xpc_object_t request, xpc_object_t reply) {
    const char *source = xpc_dictionary_get_string(request, "source");
    const char *target = xpc_dictionary_get_string(request, "target");
    bool readOnly = xpc_dictionary_get_bool(request, "read_only");
    
    if (!source || !target) {
        syslog(LOG_ERR, "[WeaponX] Missing source or target for mount operation");
        xpc_dictionary_set_bool(reply, "success", false);
        xpc_dictionary_set_string(reply, "error", "Missing source or target path");
        return;
    }
    
    syslog(LOG_NOTICE, "[WeaponX] Mounting %s to %s (read-only: %d)", source, target, readOnly);
    
    // Ensure target directory exists
    NSString *targetPath = [NSString stringWithUTF8String:target];
    if (!ensure_directory_exists(targetPath)) {
        syslog(LOG_ERR, "[WeaponX] Failed to create target directory: %s", target);
        xpc_dictionary_set_bool(reply, "success", false);
        xpc_dictionary_set_string(reply, "error", "Failed to create target directory");
        return;
    }
    
    // Perform the mount
    uint32_t flags = readOnly ? MNT_RDONLY : 0;
    int result = fs_snapshot_mount(source, target, NULL, flags);
    
    if (result == 0) {
        syslog(LOG_NOTICE, "[WeaponX] Mount successful");
        xpc_dictionary_set_bool(reply, "success", true);
    } else {
        syslog(LOG_ERR, "[WeaponX] Mount failed with error: %d (%s)", result, strerror(errno));
        xpc_dictionary_set_bool(reply, "success", false);
        xpc_dictionary_set_string(reply, "error", strerror(errno));
    }
}

// Handle unmount request
static void handle_unmount_request(xpc_object_t request, xpc_object_t reply) {
    const char *target = xpc_dictionary_get_string(request, "target");
    
    if (!target) {
        syslog(LOG_ERR, "[WeaponX] Missing target for unmount operation");
        xpc_dictionary_set_bool(reply, "success", false);
        xpc_dictionary_set_string(reply, "error", "Missing target path");
        return;
    }
    
    syslog(LOG_NOTICE, "[WeaponX] Unmounting %s", target);
    
    // Perform the unmount
    int result = unmount(target, MNT_FORCE);
    
    if (result == 0) {
        syslog(LOG_NOTICE, "[WeaponX] Unmount successful");
        xpc_dictionary_set_bool(reply, "success", true);
    } else {
        syslog(LOG_ERR, "[WeaponX] Unmount failed with error: %d (%s)", result, strerror(errno));
        xpc_dictionary_set_bool(reply, "success", false);
        xpc_dictionary_set_string(reply, "error", strerror(errno));
    }
}

// Helper function to ensure a directory exists
static BOOL ensure_directory_exists(NSString *path) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:path]) {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:path 
                    withIntermediateDirectories:YES 
                                     attributes:nil 
                                          error:&error]) {
            syslog(LOG_ERR, "[WeaponX] Failed to create directory %s: %s", 
                   [path UTF8String], [[error description] UTF8String]);
            return NO;
        }
    }
    
    return YES;
}

// Implementation of fs_snapshot_mount for bind mounts
static int fs_snapshot_mount(const char *volume, const char *mount_path, const char *snapshot, uint32_t flags) {
    // This is a simplified implementation - on a real system this would use the actual fs_snapshot_mount syscall
    // For rootless jailbreaks, we're using a bind mount approach
    
    struct stat source_stat;
    if (stat(volume, &source_stat) != 0) {
        syslog(LOG_ERR, "[WeaponX] Source directory doesn't exist: %s", volume);
        return -1;
    }
    
    // Use posix_spawn instead of NSTask
    char *args[5]; // Maximum 5 arguments: command, -r flag, source, target, NULL terminator
    int argIndex = 0;
    
    // Path to the mount_bindfs command
    const char *binPath = "/var/jb/usr/bin/mount_bindfs";
    args[argIndex++] = (char *)binPath;
    
    // Add -r flag if read-only
    if (flags & MNT_RDONLY) {
        args[argIndex++] = (char *)"-r";
    }
    
    // Add source and target paths
    args[argIndex++] = (char *)volume;
    args[argIndex++] = (char *)mount_path;
    
    // Null-terminate the args array
    args[argIndex] = NULL;
    
    // Log the command we're about to run
    syslog(LOG_NOTICE, "[WeaponX] Running command: %s %s%s %s", binPath, 
           (flags & MNT_RDONLY) ? "-r " : "", volume, mount_path);
    
    // Spawn the process
    pid_t pid;
    int status = posix_spawn(&pid, binPath, NULL, NULL, args, environ);
    
    if (status != 0) {
        syslog(LOG_ERR, "[WeaponX] Failed to spawn process: %s", strerror(status));
        return status;
    }
    
    // Wait for it to complete
    if (waitpid(pid, &status, 0) == -1) {
        syslog(LOG_ERR, "[WeaponX] Failed to wait for process: %s", strerror(errno));
        return -1;
    }
    
    if (WIFEXITED(status)) {
        int exit_status = WEXITSTATUS(status);
        if (exit_status != 0) {
            syslog(LOG_ERR, "[WeaponX] Mount command failed with status %d", exit_status);
        }
        return exit_status;
    } else {
        syslog(LOG_ERR, "[WeaponX] Mount command did not exit normally");
        return -1;
    }
} 