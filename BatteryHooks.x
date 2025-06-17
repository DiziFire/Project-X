#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <ellekit/ellekit.h>
#import "BatteryManager.h"
#import "IdentifierManager.h"

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// Bundle decision cache
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes

// Helper: get current bundle ID
static NSString *getCurrentBundleID(void) {
    @try {
        NSBundle *mainBundle = [NSBundle mainBundle];
        if (!mainBundle) {
            return nil;
        }
        return [mainBundle bundleIdentifier];
    } @catch (NSException *e) {
        return nil;
    }
}

// Helper: load scoped apps from plist (with cache)
static NSDictionary *loadScopedApps(void) {
    @try {
        if (scopedAppsCache && scopedAppsCacheTimestamp &&
            [[NSDate date] timeIntervalSinceDate:scopedAppsCacheTimestamp] < kScopedAppsCacheValidDuration) {
            return scopedAppsCache;
        }
        if (!scopedAppsCache) {
            scopedAppsCache = [NSMutableDictionary dictionary];
        } else {
            [scopedAppsCache removeAllObjects];
        }
        NSArray *possiblePaths = @[kScopedAppsPath, kScopedAppsPathAlt1, kScopedAppsPathAlt2];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *validPath = nil;
        for (NSString *path in possiblePaths) {
            if ([fileManager fileExistsAtPath:path]) {
                validPath = path;
                break;
            }
        }
        if (!validPath) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:validPath];
        if (!plistDict || ![plistDict isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        NSDictionary *scopedApps = plistDict[@"ScopedApps"];
        if (!scopedApps || ![scopedApps isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        [scopedAppsCache addEntriesFromDictionary:scopedApps];
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache;
    } @catch (NSException *e) {
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache ?: [NSMutableDictionary dictionary];
    }
}

// Helper: check if current app is in scoped apps list and enabled
static BOOL isInScopedAppsList(void) {
    @try {
        NSString *bundleID = getCurrentBundleID();
        if (!bundleID || [bundleID length] == 0) {
            return NO;
        }
        NSDictionary *scopedApps = loadScopedApps();
        if (!scopedApps || scopedApps.count == 0) {
            return NO;
        }
        id appEntry = scopedApps[bundleID];
        if (!appEntry || ![appEntry isKindOfClass:[NSDictionary class]]) {
            return NO;
        }
        BOOL isEnabled = [appEntry[@"enabled"] boolValue];
        return isEnabled;
    } @catch (NSException *e) {
        return NO;
    }
}

// Helper: should spoof battery for this bundle (with cache)
static BOOL shouldSpoofBatteryForBundle(NSString *bundleID) {
    if (!bundleID) return NO;
    if (!cachedBundleDecisions) {
        cachedBundleDecisions = [NSMutableDictionary dictionary];
    } else {
        NSNumber *cachedDecision = cachedBundleDecisions[bundleID];
        NSDate *decisionTimestamp = cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]];
        if (cachedDecision && decisionTimestamp &&
            [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
            return [cachedDecision boolValue];
        }
    }
    BOOL isScoped = isInScopedAppsList();
    cachedBundleDecisions[bundleID] = @(isScoped);
    cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    return isScoped;
}

// Helper to check if battery spoofing is enabled for this app/profile
static BOOL isBatterySpoofingEnabled(void) {
    @try {
        NSString *bundleID = getCurrentBundleID();
        if (!bundleID) {
            return NO;
        }
        if (!shouldSpoofBatteryForBundle(bundleID)) {
            return NO;
        }
        Class managerClass = NSClassFromString(@"IdentifierManager");
        if (!managerClass) {
            return NO;
        }
        id manager = [managerClass respondsToSelector:@selector(sharedManager)] ? [managerClass sharedManager] : nil;
        if (!manager) {
            return NO;
        }
        SEL isEnabledSel = NSSelectorFromString(@"isIdentifierEnabled:");
        if (![manager respondsToSelector:isEnabledSel]) {
            return NO;
        }
        NSString *batteryStr = @"Battery";
        BOOL enabled = NO;
        NSMethodSignature *sig = [manager methodSignatureForSelector:isEnabledSel];
        if (sig) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
            [invocation setSelector:isEnabledSel];
            [invocation setTarget:manager];
            [invocation setArgument:&batteryStr atIndex:2];
            [invocation invoke];
            [invocation getReturnValue:&enabled];
        }
        return enabled;
    } @catch (...) {
        return NO;
    }
}

// Helper: get battery level from profile battery_info.plist
static NSString *getProfileBatteryLevel(void) {
    @try {
        // Get current profile ID
        NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
        NSDictionary *currentProfileInfo = [NSDictionary dictionaryWithContentsOfFile:profilesPath];
        if (!currentProfileInfo) {
            return nil;
        }
        NSString *profileId = currentProfileInfo[@"ProfileId"];
        if (!profileId) {
            return nil;
        }
        NSString *identityDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
        NSString *batteryInfoPath = [identityDir stringByAppendingPathComponent:@"battery_info.plist"];
        NSDictionary *batteryInfo = [NSDictionary dictionaryWithContentsOfFile:batteryInfoPath];
        if (!batteryInfo) {
            return nil;
        }
        NSString *level = batteryInfo[@"BatteryLevel"];
        if (level && [level floatValue] >= 0.01 && [level floatValue] <= 1.0) {
            return level;
        }
        return nil;
    } @catch (NSException *e) {
        return nil;
    }
}

// Hook for -[UIDevice batteryLevel]
static float (*orig_batteryLevel)(UIDevice *, SEL);
static float hook_batteryLevel(UIDevice *self, SEL _cmd) {
    if (isBatterySpoofingEnabled()) {
        NSString *spoofed = getProfileBatteryLevel();
        if (spoofed) {
            float spoofedValue = [spoofed floatValue];
            if (spoofedValue >= 0.01 && spoofedValue <= 1.0) {
                return spoofedValue;
            }
        }
    }
    float realValue = orig_batteryLevel(self, _cmd);
    return realValue;
}

// Optionally, hook batteryState (returns UIDeviceBatteryState)
static NSInteger (*orig_batteryState)(UIDevice *, SEL);
static NSInteger hook_batteryState(UIDevice *self, SEL _cmd) {
    if (isBatterySpoofingEnabled()) {
        return 1; // UIDeviceBatteryStateUnplugged
    }
    NSInteger realState = orig_batteryState(self, _cmd);
    return realState;
}

%ctor {
    @autoreleasepool {
        Class deviceClass = objc_getClass("UIDevice");
        if (deviceClass) {
            MSHookMessageEx(deviceClass, @selector(batteryLevel), (IMP)hook_batteryLevel, (IMP *)&orig_batteryLevel);
            MSHookMessageEx(deviceClass, @selector(batteryState), (IMP)hook_batteryState, (IMP *)&orig_batteryState);
        }
    }
} 