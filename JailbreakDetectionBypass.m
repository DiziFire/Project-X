#import "JailbreakDetectionBypass.h"
#import "IdentifierManager.h"
#import "ProjectXLogging.h"

@implementation JailbreakDetectionBypass

+ (instancetype)sharedInstance {
    static JailbreakDetectionBypass *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        // Initialize with default values
    }
    return self;
}

- (BOOL)isEnabledForApp:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }
    
    // First check if the global toggle is enabled
    if (![self isEnabled]) {
        return NO;
    }
    
    // Then check if the app is in the scoped list
    IdentifierManager *manager = [IdentifierManager sharedManager];
    return [manager isApplicationEnabled:bundleID];
}

- (void)setEnabled:(BOOL)enabled {
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings setBool:enabled forKey:@"jailbreakDetectionEnabled"];
    [securitySettings synchronize];
    
    PXLog(@"[JailbreakBypass] Jailbreak detection bypass %@", enabled ? @"enabled" : @"disabled");
}

- (BOOL)isEnabled {
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings synchronize];
    return [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
}

- (BOOL)isEnabledRealtime {
    // For real-time verification, just use isEnabled (no caching)
    return [self isEnabled];
}

- (void)setupBypass {
    // Placeholder for future implementation
    PXLog(@"[JailbreakBypass] Setup placeholder - will be implemented in future updates");
}

@end

