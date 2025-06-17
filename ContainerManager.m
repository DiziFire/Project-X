#import "ContainerManager.h"
#import <Foundation/Foundation.h>

@interface ContainerManager ()
@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation ContainerManager

+ (instancetype)sharedManager {
    static ContainerManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+ (instancetype)sharedInstance {
    return [self sharedManager];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = [NSFileManager defaultManager];
    }
    return self;
}

#pragma mark - Path Translation

- (NSString *)translatePath:(NSString *)originalPath forApp:(NSString *)bundleID inProfile:(NSString *)profileID {
    if (!bundleID || !originalPath || originalPath.length == 0) {
        return originalPath;
    }
    
    if (!profileID) {
        profileID = [self currentProfileID];
        if (!profileID) {
            return originalPath;
        }
    }
    
    NSString *appDataPath = [self appDataPath:bundleID inProfile:profileID];
    return [originalPath stringByReplacingOccurrencesOfString:@"/var/mobile/Library"
                                                  withString:[appDataPath stringByAppendingPathComponent:@"Library"]];
}

- (BOOL)isPathRedirectable:(NSString *)path forApp:(NSString *)bundleID {
    return [path hasPrefix:@"/var/mobile/Library"];
}

#pragma mark - Directory Structure

- (NSString *)profileBasePath:(NSString *)profileID {
    NSString *basePath = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
    return [basePath stringByAppendingPathComponent:profileID];
}

- (NSString *)appBasePath:(NSString *)profileID bundleID:(NSString *)bundleID {
    NSString *profilePath = [self profileBasePath:profileID];
    NSString *appDataPath = [profilePath stringByAppendingPathComponent:@"appdata"];
    return [appDataPath stringByAppendingPathComponent:bundleID];
}

- (NSString *)appDataPath:(NSString *)bundleID inProfile:(NSString *)profileID {
    return [self appBasePath:profileID bundleID:bundleID];
}

#pragma mark - Profile Integration

- (void)profileDidChange:(NSString *)newProfileID {
    _currentProfileID = newProfileID;
}

- (BOOL)prepareProfileDirectory:(NSString *)profileID {
    NSString *basePath = [self profileBasePath:profileID];
    NSError *error = nil;
    BOOL success = [self.fileManager createDirectoryAtPath:basePath
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:&error];
    
    if (!success) {
        NSLog(@"[WeaponX] Failed to prepare profile directory: %@", error);
    }
    
    return success;
}

#pragma mark - System App Detection

- (BOOL)isSystemApp:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }
    
    NSString *appPath = [NSString stringWithFormat:@"/Applications/%@.app", bundleID];
    return [self.fileManager fileExistsAtPath:appPath];
}

+ (NSString *)translatePathForEnvironment:(NSString *)path {
    if (!path) {
        return nil;
    }
    
    // Check if we're in a rootless environment
    BOOL isRootless = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
    
    if (isRootless) {
        // If the path starts with /var/mobile, prepend /var/jb
        if ([path hasPrefix:@"/var/mobile"]) {
            return [@"/var/jb" stringByAppendingString:path];
        }
    }
    
    return path;
}

@end 