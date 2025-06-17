#import "JailbreakDetectionBypass_App.h"
#import "IdentifierManager.h"
#import "ProjectXLogging.h"
#import <objc/runtime.h>
#import <notify.h>

@implementation JailbreakDetectionBypass {
    BOOL _enabled;
}

+ (instancetype)sharedInstance {
    static JailbreakDetectionBypass *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Load preference
        NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        _enabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
        
        // Default to enabled if not set
        if (![[securitySettings objectForKey:@"jailbreakDetectionEnabled"] isKindOfClass:[NSNumber class]]) {
            _enabled = YES;
            [securitySettings setBool:YES forKey:@"jailbreakDetectionEnabled"];
            [securitySettings synchronize];
        }
        
        // Register for emergency disable notification
        int emergencyToken;
        notify_register_dispatch("com.hydra.projectx.emergencyDisableJailbreakBypass", &emergencyToken, dispatch_get_main_queue(), ^(int token) {
            // Force disable immediately
            PXLog(@"[JailbreakBypass-App] 🚨 EMERGENCY DISABLE received - immediately disabling bypass");
            _enabled = NO;
            
            // Force update NSUserDefaults
            NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
            [settings setBool:NO forKey:@"jailbreakDetectionEnabled"];
            [settings synchronize];
        });
        
        // Register for toggle change notification
        int toggleToken;
        notify_register_dispatch("com.hydra.projectx.jailbreakToggleChanged", &toggleToken, dispatch_get_main_queue(), ^(int token) {
            // Reload preference when the notification is received
            NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
            [settings synchronize]; // Force refresh from disk
            BOOL newState = [settings boolForKey:@"jailbreakDetectionEnabled"];
            if (newState != _enabled) {
                PXLog(@"[JailbreakBypass-App] Updating toggle state: %@", newState ? @"ENABLED" : @"DISABLED");
                _enabled = newState;
            }
        });
        
        PXLog(@"[JailbreakBypass-App] Initialized, enabled: %@", _enabled ? @"YES" : @"NO");
    }
    return self;
}

- (void)setupBypass {
    // This is just a stub for the app version - the actual implementation is in the tweak
    PXLog(@"[JailbreakBypass-App] App version doesn't need to set up hooks");
}

- (BOOL)isEnabledForApp:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }
    
    // Never apply bypass to the WeaponX app itself
    if ([bundleID isEqualToString:@"com.hydra.projectx"]) {
        PXLog(@"[JailbreakBypass-App] Never apply bypass to WeaponX app itself");
        return NO;
    }
    
    // Always check the global toggle directly from NSUserDefaults
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings synchronize]; // Force refresh from disk
    BOOL globalEnabled = [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
    
    // If global setting is off, no app gets bypass
    if (!globalEnabled) {
        PXLog(@"[JailbreakBypass-App] Global toggle is disabled, bypass will not be applied to %@", bundleID);
        return NO;
    }
    
    // Use IdentifierManager to check if the app is in the scoped list
    IdentifierManager *manager = [objc_getClass("IdentifierManager") sharedManager];
    return [manager isApplicationEnabled:bundleID];
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    
    // Save the preference
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings setBool:enabled forKey:@"jailbreakDetectionEnabled"];
    [securitySettings synchronize];
    
    PXLog(@"[JailbreakBypass-App] Jailbreak detection bypass %@", enabled ? @"enabled" : @"disabled");
}

- (BOOL)isEnabled {
    // Always check the current value from NSUserDefaults
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings synchronize]; // Force refresh
    return [securitySettings boolForKey:@"jailbreakDetectionEnabled"];
}

@end
