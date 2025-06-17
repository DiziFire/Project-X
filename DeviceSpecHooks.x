#import "ProjectX.h"
#import "DeviceModelManager.h"
#import "IdentifierManager.h"
#import "ProfileManager.h"
#import "ProjectXLogging.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <ellekit/ellekit.h>

// Define the swap usage structure if it's not available
#ifndef HAVE_XSW_USAGE
struct xsw_usage {
    uint64_t xsu_total;
    uint64_t xsu_avail;
    uint64_t xsu_used;
    uint32_t xsu_pagesize;
    boolean_t xsu_encrypted;
};
typedef struct xsw_usage xsw_usage;
#endif

// Original function pointers
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static kern_return_t (*orig_host_statistics64)(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count);

// Path to scoped apps plist
static NSString *const kScopedAppsPath = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";
static NSString *const kScopedAppsPathAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist";

// Scoped apps cache
static NSMutableDictionary *scopedAppsCache = nil;
static NSDate *scopedAppsCacheTimestamp = nil;
static const NSTimeInterval kScopedAppsCacheValidDuration = 60.0; // 1 minute

// Caches for device specs
static NSMutableDictionary *deviceSpecsCache;
static NSDate *cacheTimestamp;
static NSString *cachedDeviceModel;
static NSMutableDictionary *cachedBundleDecisions;

// Cache to track which memory hooks have been called for logging
static NSMutableSet *hookedMemoryAPIs;

// Cache for bundle decisions
static const NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes

// Helper for logging memory hook invocations only once
static void logMemoryHook(NSString *apiName);

// Function declarations
static NSString *getCurrentBundleID(void);
static NSDictionary *loadScopedApps(void);
static BOOL isInScopedAppsList(void);
static BOOL isSpoofingEnabled(void);
static NSString *getSpoofedDeviceModel(void);
static NSDictionary *getDeviceSpecs(void);
static float getFreeMemoryPercentage(void);
static void getConsistentMemoryStats(unsigned long long totalMemory, 
                                    unsigned long long *freeMemory,
                                    unsigned long long *wiredMemory,
                                    unsigned long long *activeMemory,
                                    unsigned long long *inactiveMemory);
static kern_return_t hook_host_statistics64(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count);
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static void refreshCaches(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static CGSize parseResolution(NSString *resolutionString);

#pragma mark - Helper Functions

// Get the current bundle ID
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

// Load scoped apps from the plist file
static NSDictionary *loadScopedApps(void) {
    @try {
        // Check if cache is valid
        if (scopedAppsCache && scopedAppsCacheTimestamp && 
            [[NSDate date] timeIntervalSinceDate:scopedAppsCacheTimestamp] < kScopedAppsCacheValidDuration) {
            return scopedAppsCache;
        }
        
        // Initialize cache if needed
        if (!scopedAppsCache) {
            scopedAppsCache = [NSMutableDictionary dictionary];
        } else {
            [scopedAppsCache removeAllObjects];
        }
        
        // Try each possible path for the scoped apps file
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
            // Don't log this error too frequently to avoid spam
            static NSDate *lastErrorLog = nil;
            if (!lastErrorLog || [[NSDate date] timeIntervalSinceDate:lastErrorLog] > 300.0) { // 5 minutes
                PXLog(@"[DeviceSpec] Could not find scoped apps file");
                lastErrorLog = [NSDate date];
            }
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Load the plist file safely
        NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:validPath];
        if (!plistDict || ![plistDict isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Get the scoped apps dictionary
        NSDictionary *scopedApps = plistDict[@"ScopedApps"];
        if (!scopedApps || ![scopedApps isKindOfClass:[NSDictionary class]]) {
            scopedAppsCacheTimestamp = [NSDate date];
            return scopedAppsCache;
        }
        
        // Copy the scoped apps to our cache
        [scopedAppsCache addEntriesFromDictionary:scopedApps];
        scopedAppsCacheTimestamp = [NSDate date];
        
        return scopedAppsCache;
        
    } @catch (NSException *e) {
        scopedAppsCacheTimestamp = [NSDate date];
        return scopedAppsCache ?: [NSMutableDictionary dictionary];
    }
}

// Check if the current app is in the scoped apps list
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
        
        // Check if this bundle ID is in the scoped apps dictionary
        id appEntry = scopedApps[bundleID];
        if (!appEntry || ![appEntry isKindOfClass:[NSDictionary class]]) {
            return NO;
        }
        
        // Check if the app is enabled
        BOOL isEnabled = [appEntry[@"enabled"] boolValue];
        return isEnabled;
        
    } @catch (NSException *e) {
        return NO;
    }
}

// Check if device model spoofing is enabled for the current app with caching
static BOOL isSpoofingEnabled(void) {
    NSString *currentBundleID = getCurrentBundleID();
    if (!currentBundleID) return NO;
    
    // Initialize cache if needed
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedBundleDecisions = [NSMutableDictionary dictionary];
    });
    
    // Check cache first
    @synchronized(cachedBundleDecisions) {
        NSNumber *cachedDecision = cachedBundleDecisions[currentBundleID];
        NSDate *decisionTimestamp = cachedBundleDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]];
        
        if (cachedDecision && decisionTimestamp && 
            [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
            return [cachedDecision boolValue];
        }
    }
    
    // Always exclude system processes
    if ([currentBundleID hasPrefix:@"com.apple."] && 
        ![currentBundleID isEqualToString:@"com.apple.mobilesafari"] &&
        ![currentBundleID isEqualToString:@"com.apple.webapp"]) {
        @synchronized(cachedBundleDecisions) {
            cachedBundleDecisions[currentBundleID] = @NO;
            cachedBundleDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
        }
        return NO;
    }
    
    // Check if the current app is a scoped app AND if device model spoofing is enabled
    BOOL shouldSpoof = NO;
    @try {
        // First check if this app is in the scoped apps list
        BOOL isScoped = isInScopedAppsList();
        if (!isScoped) {
            shouldSpoof = NO;
        } else {
            // Now check if device model spoofing is specifically enabled
            if (NSClassFromString(@"IdentifierManager")) {
                IdentifierManager *manager = [NSClassFromString(@"IdentifierManager") sharedManager];
                shouldSpoof = [manager isIdentifierEnabled:@"DeviceModel"];
                
                // If the direct check fails, try profile settings directly
                if (!shouldSpoof) {
                    // Try to get profile settings directly from file
                    NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
                    NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
                    NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
                    
                    NSString *profileId = centralInfo[@"ProfileId"];
                    if (profileId) {
                        NSString *profileSettingsPath = [profilesPath stringByAppendingPathComponent:[profileId stringByAppendingPathComponent:@"settings.plist"]];
                        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:profileSettingsPath];
                        shouldSpoof = [settings[@"deviceModelEnabled"] boolValue];
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[DeviceSpec] Exception checking if device model spoofing is enabled: %@", exception);
        shouldSpoof = NO;
    }
    
    // Cache the decision
    @synchronized(cachedBundleDecisions) {
        cachedBundleDecisions[currentBundleID] = @(shouldSpoof);
        cachedBundleDecisions[[currentBundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    }
    
    return shouldSpoof;
}

// Get the device model from profile
static NSString *getSpoofedDeviceModel() {
    @try {
        // Try multiple methods to get the model value
        NSString *deviceModel = nil;
        
        // METHOD 1: Try direct access from profile plist
        NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        
        NSString *profileId = centralInfo[@"ProfileId"];
        if (profileId) {
            // Build path to identity directory
            NSString *identityDir = [[profilesPath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
            
            // First try device_model.plist (detailed specs)
            NSString *deviceModelPath = [identityDir stringByAppendingPathComponent:@"device_model.plist"];
            NSDictionary *deviceModelDict = [NSDictionary dictionaryWithContentsOfFile:deviceModelPath];
            deviceModel = deviceModelDict[@"value"];
            
            if (!deviceModel || deviceModel.length == 0) {
                // Fallback to device_ids.plist (combined storage)
                NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
                deviceModel = deviceIds[@"DeviceModel"];
            }
        }
        
        // METHOD 2: Use DeviceModelManager as fallback
        if (!deviceModel.length && NSClassFromString(@"DeviceModelManager")) {
            DeviceModelManager *deviceManager = [NSClassFromString(@"DeviceModelManager") sharedManager];
            deviceModel = [deviceManager currentDeviceModel] ?: [deviceManager generateDeviceModel];
        }
        
        // METHOD 3: Emergency fallback
        if (!deviceModel.length) {
            deviceModel = @"iPhone14,6"; // iPhone SE (3rd Gen) as fallback
        }
        
        return deviceModel;
    } @catch (NSException *exception) {
        return @"iPhone14,6"; // Fallback on exception
    }
}

// Get all device specifications for the current spoofed model
static NSDictionary *getDeviceSpecs() {
    // Initialize cache if needed
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        deviceSpecsCache = [NSMutableDictionary dictionary];
    });
    
    // Check if specs are already cached
    @synchronized(deviceSpecsCache) {
        NSDictionary *cachedSpecs = deviceSpecsCache[@"specs"];
        if (cachedSpecs && [[NSDate date] timeIntervalSinceDate:cacheTimestamp] < kCacheValidityDuration) {
            return cachedSpecs;
        }
    }
    
    @try {
        // METHOD 1: Try to get specs directly from profile plist files
        NSString *profilesPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        NSString *centralInfoPath = [profilesPath stringByAppendingPathComponent:@"current_profile_info.plist"];
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        
        NSString *profileId = centralInfo[@"ProfileId"];
        if (profileId) {
            NSString *identityDir = [[profilesPath stringByAppendingPathComponent:profileId] stringByAppendingPathComponent:@"identity"];
            
            // First try device_model.plist (has all detailed specs)
            NSString *deviceModelPath = [identityDir stringByAppendingPathComponent:@"device_model.plist"];
            NSDictionary *deviceModelDict = [NSDictionary dictionaryWithContentsOfFile:deviceModelPath];
            
            if (deviceModelDict && deviceModelDict.count > 0) {
                // We have the full specs in the plist, use them directly
                PXLog(@"[DeviceSpec] Loaded device specs from device_model.plist");
                
                // Cache the specifications
                @synchronized(deviceSpecsCache) {
                    deviceSpecsCache[@"specs"] = deviceModelDict;
                    cacheTimestamp = [NSDate date];
                }
                
                return deviceModelDict;
            }
            
            // Fallback to device_ids.plist and reconstruct specs
            NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
            NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
            
            if (deviceIds && deviceIds[@"DeviceModel"]) {
                // Reconstruct specs from device_ids.plist
                NSMutableDictionary *specs = [NSMutableDictionary dictionary];
                specs[@"value"] = deviceIds[@"DeviceModel"];
                specs[@"name"] = deviceIds[@"DeviceModelName"] ?: @"Unknown";
                specs[@"screenResolution"] = deviceIds[@"ScreenResolution"] ?: @"Unknown";
                specs[@"viewportResolution"] = deviceIds[@"ViewportResolution"] ?: @"Unknown";
                specs[@"devicePixelRatio"] = deviceIds[@"DevicePixelRatio"] ?: @(0);
                specs[@"screenDensity"] = deviceIds[@"ScreenDensityPPI"] ?: @(0);
                specs[@"cpuArchitecture"] = deviceIds[@"CPUArchitecture"] ?: @"Unknown";
                specs[@"deviceMemory"] = deviceIds[@"DeviceMemory"] ?: @(0);
                specs[@"gpuFamily"] = deviceIds[@"GPUFamily"] ?: @"Unknown";
                specs[@"cpuCoreCount"] = deviceIds[@"CPUCoreCount"] ?: @(0);
                specs[@"metalFeatureSet"] = deviceIds[@"MetalFeatureSet"] ?: @"Unknown";
                
                // Reconstruct webGLInfo
                NSMutableDictionary *webGLInfo = [NSMutableDictionary dictionary];
                webGLInfo[@"webglVendor"] = deviceIds[@"WebGLVendor"] ?: @"Apple";
                webGLInfo[@"webglRenderer"] = deviceIds[@"WebGLRenderer"] ?: @"Apple GPU";
                webGLInfo[@"unmaskedVendor"] = @"Apple Inc.";
                webGLInfo[@"unmaskedRenderer"] = deviceIds[@"GPUFamily"] ?: @"Apple GPU";
                webGLInfo[@"webglVersion"] = @"WebGL 2.0";
                webGLInfo[@"maxTextureSize"] = @(16384);
                webGLInfo[@"maxRenderBufferSize"] = @(16384);
                specs[@"webGLInfo"] = webGLInfo;
                
                PXLog(@"[DeviceSpec] Reconstructed device specs from device_ids.plist");
                
                // Cache the specifications
                @synchronized(deviceSpecsCache) {
                    deviceSpecsCache[@"specs"] = specs;
                    cacheTimestamp = [NSDate date];
                }
                
                return specs;
            }
        }
        
        // METHOD 2: Fallback to DeviceModelManager
        // Get the current spoofed device model
        NSString *deviceModel = getSpoofedDeviceModel();
        if (!deviceModel.length) {
            return nil;
        }
        
        // Get the specifications from DeviceModelManager
        DeviceModelManager *deviceManager = [NSClassFromString(@"DeviceModelManager") sharedManager];
        if (!deviceManager) {
            PXLog(@"[DeviceSpec] WARNING: DeviceModelManager not available");
            return nil;
        }
        
        NSDictionary *specs = [deviceManager deviceSpecificationsForModel:deviceModel];
        if (!specs) {
            PXLog(@"[DeviceSpec] WARNING: No specifications found for device model: %@", deviceModel);
            return nil;
        }
        
        // Cache the specifications
        @synchronized(deviceSpecsCache) {
            deviceSpecsCache[@"specs"] = specs;
            cacheTimestamp = [NSDate date];
        }
        
        return specs;
    } @catch (NSException *exception) {
        PXLog(@"[DeviceSpec] Exception getting device specifications: %@", exception);
        return nil;
    }
}

// Parse resolution string (e.g., "2556x1179") into CGSize
static CGSize parseResolution(NSString *resolutionString) {
    if (!resolutionString) return CGSizeZero;
    
    NSArray *components = [resolutionString componentsSeparatedByString:@"x"];
    if (components.count != 2) return CGSizeZero;
    
    CGFloat width = [components[0] floatValue];
    CGFloat height = [components[1] floatValue];
    
    return CGSizeMake(width, height);
}

#pragma mark - UIScreen Hooks

// Check if current process is a WebKit/WebContent process that needs resolution spoofing
static BOOL shouldSpoofResolutionForCurrentProcess() {
    static BOOL cachedDecision = NO;
    static BOOL hasCheckedProcess = NO;
    
    if (hasCheckedProcess) {
        return cachedDecision;
    }
    
    // Only spoof resolution for web views, not for native apps
    NSString *processName = [[NSProcessInfo processInfo] processName];
    BOOL isWebProcess = [processName containsString:@"WebKit"] || 
                        [processName containsString:@"WebContent"] ||
                        [processName containsString:@"Safari"];
                        
    // For Safari and web-focused apps, continue spoofing
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    BOOL isWebApp = [bundleID hasPrefix:@"com.apple.mobilesafari"] ||
                    [bundleID hasPrefix:@"com.google.chrome"] ||
                    [bundleID hasPrefix:@"org.mozilla.ios.Firefox"] ||
                    [bundleID hasPrefix:@"com.brave.ios"] ||
                    [bundleID hasPrefix:@"com.opera"];
    
    // Cache the decision
    hasCheckedProcess = YES;
    cachedDecision = isWebProcess || isWebApp;
    
    PXLog(@"[DeviceSpec] Resolution spoofing for process '%@' (%@): %@", 
          processName, bundleID, cachedDecision ? @"ENABLED" : @"DISABLED");
          
    return cachedDecision;
}

%hook UIScreen

// Hook for bounds (controls size of the screen in points)
- (CGRect)bounds {
    CGRect originalBounds = %orig;
    
    if (!isSpoofingEnabled() || !shouldSpoofResolutionForCurrentProcess()) {
        return originalBounds;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalBounds;
    }
    
    // Get the viewport resolution and device pixel ratio from specs
    NSString *viewportResString = specs[@"viewportResolution"];
    CGFloat pixelRatio = [specs[@"devicePixelRatio"] floatValue];
    
    if (!viewportResString || pixelRatio <= 0) {
        return originalBounds;
    }
    
    // Parse the viewport resolution
    CGSize viewportSize = parseResolution(viewportResString);
    if (CGSizeEqualToSize(viewportSize, CGSizeZero)) {
        return originalBounds;
    }
    
    // Calculate bounds in points (logical pixels)
    CGFloat width = viewportSize.width / pixelRatio;
    CGFloat height = viewportSize.height / pixelRatio;
    
    // Log the change the first time
    static BOOL loggedScreenBounds = NO;
    if (!loggedScreenBounds) {
        PXLog(@"[DeviceSpec] Spoofing UIScreen bounds from %@ to %@",
             NSStringFromCGRect(originalBounds),
             NSStringFromCGRect(CGRectMake(0, 0, width, height)));
        loggedScreenBounds = YES;
    }
    
    return CGRectMake(0, 0, width, height);
}

// Hook for nativeBounds (actual pixels)
- (CGRect)nativeBounds {
    CGRect originalNativeBounds = %orig;
    
    if (!isSpoofingEnabled() || !shouldSpoofResolutionForCurrentProcess()) {
        return originalNativeBounds;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalNativeBounds;
    }
    
    // Get the screen resolution from specs
    NSString *screenResString = specs[@"screenResolution"];
    if (!screenResString) {
        return originalNativeBounds;
    }
    
    // Parse the screen resolution
    CGSize screenSize = parseResolution(screenResString);
    if (CGSizeEqualToSize(screenSize, CGSizeZero)) {
        return originalNativeBounds;
    }
    
    // Log the change the first time
    static BOOL loggedNativeBounds = NO;
    if (!loggedNativeBounds) {
        PXLog(@"[DeviceSpec] Spoofing UIScreen nativeBounds from %@ to %@",
             NSStringFromCGRect(originalNativeBounds),
             NSStringFromCGRect(CGRectMake(0, 0, screenSize.width, screenSize.height)));
        loggedNativeBounds = YES;
    }
    
    return CGRectMake(0, 0, screenSize.width, screenSize.height);
}

// Hook for scale (affects UI element sizes)
- (CGFloat)scale {
    CGFloat originalScale = %orig;
    
    if (!isSpoofingEnabled() || !shouldSpoofResolutionForCurrentProcess()) {
        return originalScale;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalScale;
    }
    
    // Get the device pixel ratio from specs
    CGFloat pixelRatio = [specs[@"devicePixelRatio"] floatValue];
    if (pixelRatio <= 0) {
        return originalScale;
    }
    
    // Log the change the first time
    static BOOL loggedScale = NO;
    if (!loggedScale) {
        PXLog(@"[DeviceSpec] Spoofing UIScreen scale from %.2f to %.2f", originalScale, pixelRatio);
        loggedScale = YES;
    }
    
    return pixelRatio;
}

// Hook for current mode (affects refresh rate)
- (UIScreenMode *)currentMode {
    UIScreenMode *originalMode = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalMode;
    }
    
    // We can't create a new UIScreenMode, but we can modify its properties
    // through associated objects if needed in the future
    
    return originalMode;
}

%end

#pragma mark - NSProcessInfo Hooks

%hook NSProcessInfo

// Hook for physical memory (RAM)
- (unsigned long long)physicalMemory {
    unsigned long long originalMemory = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalMemory;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalMemory;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [specs[@"deviceMemory"] integerValue];
    if (deviceMemoryGB <= 0) {
        return originalMemory;
    }
    
    // Convert GB to bytes
    unsigned long long spoofedMemory = deviceMemoryGB * 1024 * 1024 * 1024;
    
    // Log the change the first time
    static BOOL loggedMemory = NO;
    if (!loggedMemory) {
        PXLog(@"[DeviceSpec] Spoofing device memory from %llu bytes to %llu bytes (%ld GB)",
             originalMemory, spoofedMemory, (long)deviceMemoryGB);
        loggedMemory = YES;
    }
    
    return spoofedMemory;
}

// Add hook for macOS compatibility - similar to iOS physicalMemory
- (unsigned long long)physicalMemorySize {
    logMemoryHook(@"physicalMemorySize");
    return [self physicalMemory]; // Reuse the physicalMemory hook
}

// Add hook for total memory (used on some iOS versions)
- (unsigned long long)totalPhysicalMemory {
    logMemoryHook(@"totalPhysicalMemory");
    return [self physicalMemory]; // Reuse the physicalMemory hook
}

// Hook for available memory
- (unsigned long long)availableMemory {
    unsigned long long originalAvailableMemory = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalAvailableMemory;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalAvailableMemory;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [specs[@"deviceMemory"] integerValue];
    if (deviceMemoryGB <= 0) {
        return originalAvailableMemory;
    }
    
    // Calculate total memory
    unsigned long long totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
    
    // Calculate free memory based on typical iOS behavior
    float freePercentage = getFreeMemoryPercentage();
    unsigned long long spoofedAvailableMemory = (unsigned long long)(totalMemory * freePercentage);
    
    // Log the change the first time
    static BOOL loggedAvailableMemory = NO;
    if (!loggedAvailableMemory) {
        PXLog(@"[DeviceSpec] Spoofing available memory from %llu bytes to %llu bytes (%.1f%% of %ld GB)",
             originalAvailableMemory, spoofedAvailableMemory, freePercentage * 100, (long)deviceMemoryGB);
        loggedAvailableMemory = YES;
    }
    
    return spoofedAvailableMemory;
}

// Hook for processor count
- (NSUInteger)processorCount {
    NSUInteger originalCount = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalCount;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalCount;
    }
    
    // Get CPU core count from specs
    NSInteger cpuCoreCount = [specs[@"cpuCoreCount"] integerValue];
    if (cpuCoreCount <= 0) {
        return originalCount;
    }
    
    // Log the change the first time
    static BOOL loggedProcessorCount = NO;
    if (!loggedProcessorCount) {
        PXLog(@"[DeviceSpec] Spoofing processor count from %lu to %ld",
             (unsigned long)originalCount, (long)cpuCoreCount);
        loggedProcessorCount = YES;
    }
    
    return cpuCoreCount;
}

// Add hook for CPU architecture information
- (NSString *)machineHardwareName {
    NSString *originalName = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalName;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalName;
    }
    
    // Get CPU architecture from specs
    NSString *cpuArchitecture = specs[@"cpuArchitecture"];
    if (!cpuArchitecture || cpuArchitecture.length == 0) {
        return originalName;
    }
    
    // Log the change the first time
    static BOOL loggedMachineHardwareName = NO;
    if (!loggedMachineHardwareName) {
        PXLog(@"[DeviceSpec] Spoofing machine hardware name from '%@' to '%@'",
             originalName, cpuArchitecture);
        loggedMachineHardwareName = YES;
    }
    
    return cpuArchitecture;
}

%end

#pragma mark - Device Memory JS API Hooks

// JavaScript deviceMemory API hook
%hook WKWebView

// Inject JavaScript to override navigator.deviceMemory
- (void)_didFinishLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    if (!isSpoofingEnabled()) {
        return;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [specs[@"deviceMemory"] integerValue];
    if (deviceMemoryGB <= 0) {
        return;
    }
    
    // Create JavaScript to override navigator.deviceMemory
    NSString *script = [NSString stringWithFormat:
                      @"(function() {"
                      @"  Object.defineProperty(navigator, 'deviceMemory', {"
                      @"    value: %ld,"
                      @"    writable: false,"
                      @"    configurable: true"
                      @"  });"
                      @"})();", (long)deviceMemoryGB];
    
    // Execute the script
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Error injecting deviceMemory script: %@", error);
        } else {
            static BOOL loggedDeviceMemory = NO;
            if (!loggedDeviceMemory) {
                PXLog(@"[DeviceSpec] Successfully spoofed navigator.deviceMemory to %ld GB", (long)deviceMemoryGB);
                loggedDeviceMemory = YES;
            }
        }
    }];
}

%end

#pragma mark - WebGL Info Hooks

%hook WebGLRenderingContext

// Hook for WebGL vendor and renderer strings
- (NSString *)getParameter:(unsigned)pname {
    NSString *original = %orig;
    
    if (!isSpoofingEnabled()) {
        return original;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return original;
    }
    
    NSDictionary *webGLInfo = specs[@"webGLInfo"];
    if (!webGLInfo) {
        return original;
    }
    
    // Map WebGL parameter constants to our stored values
    // VENDOR = 0x1F00, RENDERER = 0x1F01, VERSION = 0x1F02
    NSString *spoofedValue = nil;
    
    if (pname == 0x1F00) { // VENDOR
        spoofedValue = webGLInfo[@"webglVendor"];
    } else if (pname == 0x1F01) { // RENDERER
        spoofedValue = webGLInfo[@"webglRenderer"];
    } else if (pname == 0x1F02) { // VERSION
        spoofedValue = webGLInfo[@"webglVersion"];
    } else if (pname == 0x8B4F || pname == 0x8B4E) { // UNMASKED_VENDOR_WEBGL or UNMASKED_RENDERER_WEBGL
        spoofedValue = (pname == 0x8B4F) ? webGLInfo[@"unmaskedVendor"] : webGLInfo[@"unmaskedRenderer"];
    } else if (pname == 0x0D33) { // MAX_TEXTURE_SIZE
        return [NSString stringWithFormat:@"%@", webGLInfo[@"maxTextureSize"]];
    } else if (pname == 0x8D57) { // MAX_RENDERBUFFER_SIZE
        return [NSString stringWithFormat:@"%@", webGLInfo[@"maxRenderBufferSize"]];
    }
    
    if (spoofedValue) {
        static NSMutableSet *loggedParameters = nil;
        if (!loggedParameters) {
            loggedParameters = [NSMutableSet set];
        }
        
        NSString *paramKey = [NSString stringWithFormat:@"%u", pname];
        if (![loggedParameters containsObject:paramKey]) {
            [loggedParameters addObject:paramKey];
            PXLog(@"[DeviceSpec] Spoofing WebGL parameter 0x%X from '%@' to '%@'", pname, original, spoofedValue);
        }
        
        return spoofedValue;
    }
    
    return original;
}

%end

#pragma mark - Metal API Hooks

%hook MTLDevice

// Hook for name property
- (NSString *)name {
    NSString *originalName = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalName;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalName;
    }
    
    NSString *gpuFamily = specs[@"gpuFamily"];
    if (!gpuFamily) {
        return originalName;
    }
    
    // Log the change the first time
    static BOOL loggedGPUName = NO;
    if (!loggedGPUName) {
        PXLog(@"[DeviceSpec] Spoofing GPU name from '%@' to '%@'", originalName, gpuFamily);
        loggedGPUName = YES;
    }
    
    return gpuFamily;
}

// Also hook the family name property
- (NSString *)familyName {
    NSString *originalFamilyName = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalFamilyName;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalFamilyName;
    }
    
    NSString *gpuFamily = specs[@"gpuFamily"];
    if (!gpuFamily) {
        return originalFamilyName;
    }
    
    // Log the change the first time
    static BOOL loggedGPUFamilyName = NO;
    if (!loggedGPUFamilyName) {
        PXLog(@"[DeviceSpec] Spoofing GPU family name from '%@' to '%@'", originalFamilyName, gpuFamily);
        loggedGPUFamilyName = YES;
    }
    
    return gpuFamily;
}

%end

#pragma mark - Screen Density (DPI) Hooks

%hook UIScreen

// For screen density
- (CGFloat)native_scale {
    CGFloat originalScale = %orig;
    
    if (!isSpoofingEnabled()) {
        return originalScale;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return originalScale;
    }
    
    // Calculate from screen density (PPI)
    NSInteger screenDensity = [specs[@"screenDensity"] integerValue];
    if (screenDensity <= 0) {
        return originalScale;
    }
    
    // iPhone reference point is 163 PPI for scale 1.0
    CGFloat spoofedScale = screenDensity / 163.0;
    
    // Log the change the first time
    static BOOL loggedNativeScale = NO;
    if (!loggedNativeScale) {
        PXLog(@"[DeviceSpec] Spoofing native scale from %.2f to %.2f (density: %ld PPI)",
             originalScale, spoofedScale, (long)screenDensity);
        loggedNativeScale = YES;
    }
    
    return spoofedScale;
}

%end

#pragma mark - JavaScript WebKit Feature Detection Hooks

%hook WKWebView

// Hook document.load to inject our custom JavaScript for device spoofing
- (void)_documentDidFinishLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    if (!isSpoofingEnabled()) {
        return;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return;
    }
    
    NSString *deviceModel = getSpoofedDeviceModel();
    if (!deviceModel) {
        return;
    }
    
    // Prepare values from specs
    NSString *screenResolution = specs[@"screenResolution"] ?: @"";
    CGFloat devicePixelRatio = [specs[@"devicePixelRatio"] floatValue];
    NSInteger deviceMemory = [specs[@"deviceMemory"] integerValue];
    NSInteger cpuCoreCount = [specs[@"cpuCoreCount"] integerValue];
    
    // Create a comprehensive JavaScript to override browser properties
    NSString *script = [NSString stringWithFormat:
                      @"(function() {"
                      // Device memory
                      @"  if ('deviceMemory' in navigator) {"
                      @"    Object.defineProperty(navigator, 'deviceMemory', { value: %ld, writable: false });"
                      @"  }"
                      
                      // Hardware concurrency (CPU cores)
                      @"  if ('hardwareConcurrency' in navigator) {"
                      @"    Object.defineProperty(navigator, 'hardwareConcurrency', { value: %ld, writable: false });"
                      @"  }"
                      
                      // Device pixel ratio
                      @"  if ('devicePixelRatio' in window) {"
                      @"    Object.defineProperty(window, 'devicePixelRatio', { value: %.2f, writable: false });"
                      @"  }"
                      
                      // Screen properties
                      @"  if ('screen' in window) {"
                      @"    var res = '%@'.split('x');"
                      @"    var w = parseInt(res[0], 10) || screen.width;"
                      @"    var h = parseInt(res[1], 10) || screen.height;"
                      @"    Object.defineProperty(screen, 'width', { value: w, writable: false });"
                      @"    Object.defineProperty(screen, 'height', { value: h, writable: false });"
                      @"    Object.defineProperty(screen, 'availWidth', { value: w, writable: false });"
                      @"    Object.defineProperty(screen, 'availHeight', { value: h, writable: false });"
                      @"  }"
                      
                      // Window dimensions - critical for browser fingerprinting
                      @"  if ('innerWidth' in window) {"
                      @"    var res = '%@'.split('x');"
                      @"    var w = parseInt(res[0], 10) / %.2f || window.innerWidth;"
                      @"    var h = parseInt(res[1], 10) / %.2f || window.innerHeight;"
                      @"    Object.defineProperty(window, 'innerWidth', { "
                      @"      get: function() { return Math.floor(w); },"
                      @"      configurable: true"
                      @"    });"
                      @"    Object.defineProperty(window, 'innerHeight', { "
                      @"      get: function() { return Math.floor(h); },"
                      @"      configurable: true"
                      @"    });"
                      @"  }"
                      
                      // Outer window dimensions
                      @"  if ('outerWidth' in window) {"
                      @"    var res = '%@'.split('x');"
                      @"    var w = parseInt(res[0], 10) / %.2f || window.outerWidth;"
                      @"    var h = parseInt(res[1], 10) / %.2f || window.outerHeight;"
                      @"    // Add small offset to simulate browser chrome"
                      @"    Object.defineProperty(window, 'outerWidth', { "
                      @"      get: function() { return Math.floor(w) + 16; },"
                      @"      configurable: true"
                      @"    });"
                      @"    Object.defineProperty(window, 'outerHeight', { "
                      @"      get: function() { return Math.floor(h) + 88; },"
                      @"      configurable: true"
                      @"    });"
                      @"  }"
                      
                      // User agent manipulation if needed
                      // Note: Generally better to spoof UA at the HTTP header level
                      
                      // Additional WebGL spoofing if needed
                      @"})();",
                      (long)deviceMemory,
                      (long)cpuCoreCount,
                      devicePixelRatio,
                      screenResolution,
                      // Parameters for inner window size
                      screenResolution,
                      devicePixelRatio,
                      devicePixelRatio,
                      // Parameters for outer window size
                      screenResolution,
                      devicePixelRatio,
                      devicePixelRatio];
    
    // Execute the script
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Error injecting device properties script: %@", error);
        } else {
            static BOOL loggedJSInjection = NO;
            if (!loggedJSInjection) {
                PXLog(@"[DeviceSpec] Successfully injected device properties for %@", deviceModel);
                loggedJSInjection = YES;
            }
        }
    }];
}

%end

#pragma mark - Notification Handlers

// Handler for notification to refresh caches
static void refreshCaches(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    PXLog(@"[DeviceSpec] Received notification: %@, refreshing caches", notificationName);
    
    @synchronized(deviceSpecsCache) {
        [deviceSpecsCache removeAllObjects];
        cachedDeviceModel = nil;
        cacheTimestamp = nil;
    }
    
    @synchronized(cachedBundleDecisions) {
        [cachedBundleDecisions removeAllObjects];
    }
}

#pragma mark - Canvas Fingerprinting Protection

// Add hooks for canvas toDataURL and getImageData to prevent canvas fingerprinting
%hook WKWebView

// Add JavaScript to protect against canvas fingerprinting 
- (void)_didCreateMainFrame:(WKFrameInfo *)frame {
    %orig;
    
    if (!isSpoofingEnabled()) {
        return;
    }
    
    NSString *deviceModel = getSpoofedDeviceModel();
    if (!deviceModel) {
        return;
    }
    
    // Create a hash value from the device model to generate consistent noise
    NSUInteger deviceModelHash = [deviceModel hash];
    
    // This script adds noise to canvas operations in a way that's consistent for the same device model
    NSString *canvasProtectionScript = [NSString stringWithFormat:
                                       @"(function() {"
                                       // Store original methods before modifying them
                                       @"  const origToDataURL = HTMLCanvasElement.prototype.toDataURL;"
                                       @"  const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;"
                                       @"  const origReadPixels = WebGLRenderingContext.prototype.readPixels;"
                                       
                                       // Define a noise function based on spoofed device model
                                       @"  const deviceSeed = %lu;"
                                       @"  function generateNoise(input) {"
                                       @"    let hash = (deviceSeed * 131 + input) & 0xFFFFFFFF;"
                                       @"    return (hash / 0xFFFFFFFF) * 2 - 1;"  // -1 to +1 range
                                       @"  }"
                                       
                                       // Hook 2D Canvas toDataURL
                                       @"  HTMLCanvasElement.prototype.toDataURL = function() {"
                                       @"    try {"
                                       @"      const context = this.getContext('2d');"
                                       @"      if (context && this.width > 16 && this.height > 16) {"
                                       @"        // Subtly modify the canvas content in a consistent way"
                                       @"        const imgData = context.getImageData(0, 0, 2, 2);"
                                       @"        if (imgData && imgData.data) {"
                                       @"          // Add subtle, deterministic noise to a small portion"
                                       @"          for (let i = 0; i < imgData.data.length; i += 4) {"
                                       @"            const noise = generateNoise(i) * 0.5;"
                                       @"            imgData.data[i] = Math.min(255, Math.max(0, imgData.data[i] + noise));"
                                       @"          }"
                                       @"          context.putImageData(imgData, 0, 0);"
                                       @"        }"
                                       @"      }"
                                       @"    } catch(e) {}"
                                       @"    return origToDataURL.apply(this, arguments);"
                                       @"  };"
                                       
                                       // Hook 2D Canvas getImageData
                                       @"  CanvasRenderingContext2D.prototype.getImageData = function() {"
                                       @"    const imgData = origGetImageData.apply(this, arguments);"
                                       @"    try {"
                                       @"      // Add consistent noise to the image data"
                                       @"      if (imgData && imgData.data && imgData.data.length > 0) {"
                                       @"        // Only modify a small percentage of pixels to avoid visual detection"
                                       @"        for (let i = 0; i < imgData.data.length; i += 40) {"
                                       @"          const noise = generateNoise(i) * 1.0;"
                                       @"          imgData.data[i] = Math.min(255, Math.max(0, imgData.data[i] + noise));"
                                       @"        }"
                                       @"      }"
                                       @"    } catch(e) {}"
                                       @"    return imgData;"
                                       @"  };"
                                       
                                       // Hook WebGL readPixels
                                       @"  WebGLRenderingContext.prototype.readPixels = function(x, y, width, height, format, type, pixels) {"
                                       @"    // First perform the regular pixel read"
                                       @"    origReadPixels.apply(this, arguments);"
                                       @"    try {"
                                       @"      // Then apply consistent noise to the output"
                                       @"      if (pixels && pixels.length > 0) {"
                                       @"        for (let i = 0; i < pixels.length; i += 50) {"
                                       @"          const pixelIndex = i %% pixels.length;"
                                       @"          const noise = generateNoise(pixelIndex) * 1.0;"
                                       @"          pixels[pixelIndex] = Math.min(255, Math.max(0, pixels[pixelIndex] + noise));"
                                       @"        }"
                                       @"      }"
                                       @"    } catch(e) {}"
                                       @"    return;"
                                       @"  };"
                                       
                                       // Prevent canvas font fingerprinting
                                       @"  const origMeasureText = CanvasRenderingContext2D.prototype.measureText;"
                                       @"  CanvasRenderingContext2D.prototype.measureText = function(text) {"
                                       @"    const result = origMeasureText.apply(this, arguments);"
                                       @"    // Add tiny noise to font measurement consistent with device model"
                                       @"    const noise = (generateNoise(text.length) * 0.1) + 1.0;"
                                       @"    const origWidth = result.width;"
                                       @"    Object.defineProperty(result, 'width', { value: origWidth * noise });"
                                       @"    return result;"
                                       @"  };"
                                       
                                       // Extra protection for text rendering
                                       @"  const origFillText = CanvasRenderingContext2D.prototype.fillText;"
                                       @"  CanvasRenderingContext2D.prototype.fillText = function(text, x, y, maxWidth) {"
                                       @"    // Add subtle position variation consistent with device model"
                                       @"    const xNoise = generateNoise(text.length * 31) * 0.2;"
                                       @"    const yNoise = generateNoise(text.length * 37) * 0.2;"
                                       @"    const newX = x + xNoise;"
                                       @"    const newY = y + yNoise;"
                                       @"    if (arguments.length < 4) {"
                                       @"      return origFillText.call(this, text, newX, newY);"
                                       @"    } else {"
                                       @"      return origFillText.call(this, text, newX, newY, maxWidth);"
                                       @"    }"
                                       @"  };"
                                       
                                       @"})();",
                                       (unsigned long)deviceModelHash];
    
    // Execute the script
    [self evaluateJavaScript:canvasProtectionScript completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Error injecting canvas protection script: %@", error);
        } else {
            static BOOL loggedCanvasProtection = NO;
            if (!loggedCanvasProtection) {
                PXLog(@"[DeviceSpec] Successfully injected canvas fingerprinting protection for %@", deviceModel);
                loggedCanvasProtection = YES;
            }
        }
    }];
}

%end

#pragma mark - CPU Core Spoofing Enhancements

// Add an early hook to ensure CPU core count is spoofed as early as possible
%hook WKWebView

// Hook page initialization to spoof cores early
- (void)_didStartProvisionalLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    if (!isSpoofingEnabled()) {
        return;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return;
    }
    
    NSInteger cpuCoreCount = [specs[@"cpuCoreCount"] integerValue];
    if (cpuCoreCount <= 0) {
        return;
    }
    
    // Immediately inject CPU core count at load start
    NSString *script = [NSString stringWithFormat:
                        @"(function() {"
                        @"  if ('hardwareConcurrency' in navigator) {"
                        @"    Object.defineProperty(navigator, 'hardwareConcurrency', {"
                        @"      value: %ld,"
                        @"      writable: false,"
                        @"      configurable: true"
                        @"    });"
                        @"  }"
                        @"})();", (long)cpuCoreCount];
    
    [self evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[DeviceSpec] Early CPU core spoof error: %@", error);
        }
    }];
}

// Hook JavaScript context creation to spoof core count at the earliest possible moment
- (void)_didCreateJavaScriptContext:(id)context {
    %orig;
    
    if (!isSpoofingEnabled()) {
        return;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return;
    }
    
    NSInteger cpuCoreCount = [specs[@"cpuCoreCount"] integerValue];
    if (cpuCoreCount <= 0) {
        return;
    }
    
    NSString *script = [NSString stringWithFormat:
                        @"if ('hardwareConcurrency' in navigator) {"
                        @"  Object.defineProperty(navigator, 'hardwareConcurrency', {"
                        @"    value: %ld,"
                        @"    writable: false,"
                        @"    configurable: true"
                        @"  });"
                        @"}", (long)cpuCoreCount];
    
    [self evaluateJavaScript:script completionHandler:nil];
}

%end

// Hook lower-level CPU detection APIs for native apps
%hook host_basic_info

- (unsigned int)max_cpus {
    unsigned int original = %orig;
    
    if (!isSpoofingEnabled()) {
        return original;
    }
    
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return original;
    }
    
    NSInteger cpuCoreCount = [specs[@"cpuCoreCount"] integerValue];
    if (cpuCoreCount <= 0) {
        return original;
    }
    
    static BOOL loggedCoreAPI = NO;
    if (!loggedCoreAPI) {
        PXLog(@"[DeviceSpec] Spoofing low-level CPU API from %u to %ld", original, (long)cpuCoreCount);
        loggedCoreAPI = YES;
    }
    
    return (unsigned int)cpuCoreCount;
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        @try {
            PXLog(@"[DeviceSpec] Initializing device specifications spoofing hooks");
            
            NSString *currentBundleID = getCurrentBundleID();
            
            // Skip if we can't get bundle ID
            if (!currentBundleID || [currentBundleID length] == 0) {
                return;
            }
            
            // Don't hook system processes and our own apps
            if ([currentBundleID hasPrefix:@"com.apple."] || 
                [currentBundleID isEqualToString:@"com.hydra.projectx"] || 
                [currentBundleID isEqualToString:@"com.hydra.weaponx"]) {
                PXLog(@"[DeviceSpec] Not hooking system process: %@", currentBundleID);
                return;
            }
            
            // Always initialize caches
            deviceSpecsCache = [NSMutableDictionary dictionary];
            cachedBundleDecisions = [NSMutableDictionary dictionary];
            
            // Register for notifications to refresh caches
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                refreshCaches,
                CFSTR("com.hydra.projectx.profileChanged"),
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );
            
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                NULL,
                refreshCaches,
                CFSTR("com.hydra.projectx.settings.changed"),
                NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately
            );
            
            // CRITICAL: Only install hooks if this app is actually scoped
            if (!isInScopedAppsList()) {
                // App is NOT scoped - no hooks, no interference, no crashes
                PXLog(@"[DeviceSpec] App %@ is not scoped, skipping hook installation", currentBundleID);
                return;
            }
            
            PXLog(@"[DeviceSpec] App %@ is scoped, installing device specification hooks", currentBundleID);
            
            // Initialize memory hook function pointers for scoped apps only
            void *libSystem = dlopen("/usr/lib/libSystem.dylib", RTLD_NOW);
            if (libSystem) {
                // Hook sysctlbyname for memory-related calls
                orig_sysctlbyname = dlsym(libSystem, "sysctlbyname");
                if (orig_sysctlbyname) {
                    MSHookFunction(orig_sysctlbyname, (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname);
                    PXLog(@"[DeviceSpec] Successfully hooked sysctlbyname for memory spoofing");
                }
                
                // Hook host_statistics64 for VM stats spoofing
                orig_host_statistics64 = dlsym(libSystem, "host_statistics64");
                if (orig_host_statistics64) {
                    MSHookFunction(orig_host_statistics64, (void *)hook_host_statistics64, (void **)&orig_host_statistics64);
                    PXLog(@"[DeviceSpec] Successfully hooked host_statistics64 for memory stats spoofing");
                }
                
                dlclose(libSystem);
            }
            
            // Initialize Objective-C hooks for scoped apps only
            %init();
            
            PXLog(@"[DeviceSpec] Device specification hooks successfully initialized for scoped app: %@", currentBundleID);
            
        } @catch (NSException *e) {
            PXLog(@"[DeviceSpec] ❌ Exception in constructor: %@", e);
        }
    }
}

// Helper for logging memory hook invocations only once
static void logMemoryHook(NSString *apiName) {
    if (!hookedMemoryAPIs) {
        hookedMemoryAPIs = [NSMutableSet set];
    }
    
    if (![hookedMemoryAPIs containsObject:apiName]) {
        [hookedMemoryAPIs addObject:apiName];
        PXLog(@"[DeviceSpec] Memory spoofing API '%@' was accessed", apiName);
    }
}

// Function to calculate free memory percentage based on device specs
static float getFreeMemoryPercentage(void) {
    // Default free memory percentage (typical for iOS devices under normal usage)
    float defaultFreePercentage = 0.35; // 35% free
    
    // Check if spoofing is enabled
    if (!isSpoofingEnabled()) {
        return defaultFreePercentage;
    }
    
    // Get device specs
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return defaultFreePercentage;
    }
    
    // If we have a specific free memory percentage in specs, use it
    NSNumber *freeMemoryPercent = specs[@"freeMemoryPercentage"];
    if (freeMemoryPercent) {
        float percentage = [freeMemoryPercent floatValue];
        // Validate the percentage is reasonable
        if (percentage > 0.1 && percentage < 0.7) {
            return percentage;
        }
    }
    
    // Otherwise use a realistic value based on device memory
    NSInteger deviceMemoryGB = [specs[@"deviceMemory"] integerValue];
    if (deviceMemoryGB <= 0) {
        return defaultFreePercentage;
    }
    
    // Larger memory devices typically have higher free percentage
    if (deviceMemoryGB >= 6) {
        return 0.45; // 45% free for 6GB+ devices
    } else if (deviceMemoryGB >= 4) {
        return 0.40; // 40% free for 4GB devices
    } else if (deviceMemoryGB >= 3) {
        return 0.35; // 35% free for 3GB devices
    } else {
        return 0.30; // 30% free for smaller memory devices
    }
}

// Function to get consistent free/wired/active memory values based on total memory
static void getConsistentMemoryStats(unsigned long long totalMemory, 
                                    unsigned long long *freeMemory,
                                    unsigned long long *wiredMemory,
                                    unsigned long long *activeMemory,
                                    unsigned long long *inactiveMemory) {
    
    float freePercentage = getFreeMemoryPercentage();
    float wiredPercentage = 0.20; // 20% wired (kernel, system)
    float activePercentage = 0.30; // 30% active (running apps)
    float inactivePercentage = 1.0 - freePercentage - wiredPercentage - activePercentage;
    
    if (freeMemory) {
        *freeMemory = (unsigned long long)(totalMemory * freePercentage);
    }
    
    if (wiredMemory) {
        *wiredMemory = (unsigned long long)(totalMemory * wiredPercentage);
    }
    
    if (activeMemory) {
        *activeMemory = (unsigned long long)(totalMemory * activePercentage);
    }
    
    if (inactiveMemory) {
        *inactiveMemory = (unsigned long long)(totalMemory * inactivePercentage);
    }
}

// Host statistics hook for memory stats
static kern_return_t hook_host_statistics64(host_t host, host_flavor_t flavor, host_info64_t info, mach_msg_type_number_t *count) {
    // Call original function first
    kern_return_t result = orig_host_statistics64(host, flavor, info, count);
    
    // Check if we should modify the result
    if (result != KERN_SUCCESS || !info || !isSpoofingEnabled()) {
        return result;
    }
    
    // Get device specs
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return result;
    }
    
    // Get the device memory from specs (in GB)
    NSInteger deviceMemoryGB = [specs[@"deviceMemory"] integerValue];
    if (deviceMemoryGB <= 0) {
        return result;
    }
    
    // Calculate total memory in bytes
    unsigned long long totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
    
    // Handle specific host info types
    if (flavor == HOST_VM_INFO64 || flavor == HOST_VM_INFO) {
        // VM statistics (free memory, etc.)
        if (flavor == HOST_VM_INFO64 && *count >= HOST_VM_INFO64_COUNT) {
            vm_statistics64_data_t *vmStats = (vm_statistics64_data_t *)info;
            
            // Calculate consistent memory values
            unsigned long long freeMemory, wiredMemory, activeMemory, inactiveMemory;
            getConsistentMemoryStats(totalMemory, &freeMemory, &wiredMemory, &activeMemory, &inactiveMemory);
            
            // page size is typically 4096 or 16384 depending on device
            vm_size_t pageSize = 4096;
            host_page_size(host, &pageSize);
            
            // Convert bytes to pages
            uint64_t freePages = freeMemory / pageSize;
            uint64_t wiredPages = wiredMemory / pageSize;
            uint64_t activePages = activeMemory / pageSize;
            uint64_t inactivePages = inactiveMemory / pageSize;
            
            // Update stats consistently
            vmStats->free_count = freePages;
            vmStats->wire_count = wiredPages;
            vmStats->active_count = activePages;
            vmStats->inactive_count = inactivePages;
            
            // Log the change the first time
            static BOOL loggedVMStats = NO;
            if (!loggedVMStats) {
                PXLog(@"[DeviceSpec] Spoofed vm_statistics64 with %llu free pages (%.1f%% of total memory)",
                    freePages, (float)freeMemory * 100.0 / totalMemory);
                loggedVMStats = YES;
            }
        } else if (flavor == HOST_VM_INFO && *count >= HOST_VM_INFO_COUNT) {
            vm_statistics_data_t *vmStats = (vm_statistics_data_t *)info;
            
            // Calculate consistent memory values
            unsigned long long freeMemory, wiredMemory, activeMemory, inactiveMemory;
            getConsistentMemoryStats(totalMemory, &freeMemory, &wiredMemory, &activeMemory, &inactiveMemory);
            
            // page size is typically 4096 or 16384 depending on device
            vm_size_t pageSize = 4096;
            host_page_size(host, &pageSize);
            
            // Convert bytes to pages
            unsigned int freePages = (unsigned int)(freeMemory / pageSize);
            unsigned int wiredPages = (unsigned int)(wiredMemory / pageSize);
            unsigned int activePages = (unsigned int)(activeMemory / pageSize);
            unsigned int inactivePages = (unsigned int)(inactiveMemory / pageSize);
            
            // Update stats consistently
            vmStats->free_count = freePages;
            vmStats->wire_count = wiredPages;
            vmStats->active_count = activePages;
            vmStats->inactive_count = inactivePages;
            
            // Log the change the first time
            static BOOL loggedVMStats32 = NO;
            if (!loggedVMStats32) {
                PXLog(@"[DeviceSpec] Spoofed vm_statistics with %u free pages (%.1f%% of total memory)",
                    freePages, (float)freeMemory * 100.0 / totalMemory);
                loggedVMStats32 = YES;
            }
        }
    } else if (flavor == HOST_BASIC_INFO) {
        // Basic host info including memory size
        if (*count >= HOST_BASIC_INFO_COUNT) {
            host_basic_info_t basicInfo = (host_basic_info_t)info;
            
            // Spoof max memory to match our deviceMemory value
            basicInfo->max_mem = totalMemory;
            
            // Log the change the first time
            static BOOL loggedBasicInfo = NO;
            if (!loggedBasicInfo) {
                PXLog(@"[DeviceSpec] Spoofed host_basic_info max_mem to %llu bytes (%ld GB)",
                    totalMemory, (long)deviceMemoryGB);
                loggedBasicInfo = YES;
            }
        }
    }
    
    return result;
}

// Sysctlbyname hook for memory-related calls
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // Always call original function first to ensure proper behavior
    int result = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
    
    // Return original result if conditions not met
    if (result != 0 || !name || !oldp || !oldlenp || *oldlenp == 0 || !isSpoofingEnabled()) {
        return result;
    }
    
    // Get device specs
    NSDictionary *specs = getDeviceSpecs();
    if (!specs) {
        return result;
    }
    
    // Get CPU architecture for processor-related sysctls
    NSString *cpuArchitecture = specs[@"cpuArchitecture"];
    NSInteger cpuCoreCount = [specs[@"cpuCoreCount"] integerValue];
    
    // Handle CPU-related sysctls
    if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0) {
        // Number of CPUs / Active CPUs
        if (cpuCoreCount > 0) {
            if (*oldlenp == sizeof(uint32_t)) {
                *(uint32_t *)oldp = (uint32_t)cpuCoreCount;
            } else if (*oldlenp == sizeof(int)) {
                *(int *)oldp = (int)cpuCoreCount;
            } else if (*oldlenp == sizeof(unsigned long)) {
                *(unsigned long *)oldp = (unsigned long)cpuCoreCount;
            }
            
            static BOOL loggedCPUCount = NO;
            if (!loggedCPUCount) {
                PXLog(@"[DeviceSpec] Spoofed %s to %ld cores", name, (long)cpuCoreCount);
                loggedCPUCount = YES;
            }
        }
    }
    else if (strcmp(name, "hw.cpu.brand_string") == 0 || strcmp(name, "hw.cpubrand") == 0 || strcmp(name, "hw.model") == 0) {
        // CPU Brand/Model Name - return the processor name like "Apple A11 Bionic"
        if (cpuArchitecture && cpuArchitecture.length > 0) {
            const char *cpuBrand = [cpuArchitecture UTF8String];
            if (cpuBrand && *oldlenp > 0) {
                size_t brandLen = strlen(cpuBrand);
                if (brandLen < *oldlenp) {
                    *oldlenp = brandLen + 1;
                    memset(oldp, 0, *oldlenp);
                    strcpy(oldp, cpuBrand);
                    
                    static BOOL loggedCPUBrand = NO;
                    if (!loggedCPUBrand) {
                        PXLog(@"[DeviceSpec] Spoofed %s to '%s'", name, cpuBrand);
                        loggedCPUBrand = YES;
                    }
                } else {
                    PXLog(@"[DeviceSpec] WARNING: CPU brand string too long for buffer");
                }
            }
        }
    }
    else if (strcmp(name, "hw.cputype") == 0) {
        // CPU Type - ARM64 is already defined as CPU_TYPE_ARM64 in system headers
        if (*oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = CPU_TYPE_ARM64;
            
            static BOOL loggedCPUType = NO;
            if (!loggedCPUType) {
                PXLog(@"[DeviceSpec] Spoofed hw.cputype to ARM64 (0x%X)", (uint32_t)CPU_TYPE_ARM64);
                loggedCPUType = YES;
            }
        }
    }
    else if (strcmp(name, "hw.cpusubtype") == 0) {
        // CPU Subtype - varies by processor
        uint32_t cpuSubtype = 0;
        
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A9"]) {
                cpuSubtype = 2; // A9 subtype
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cpuSubtype = 3; // A10 subtype  
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cpuSubtype = 4; // A11 subtype
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cpuSubtype = 5; // A12 subtype
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cpuSubtype = 6; // A13 subtype
            } else if ([cpuArchitecture containsString:@"A14"]) {
                cpuSubtype = 7; // A14 subtype
            } else if ([cpuArchitecture containsString:@"A15"]) {
                cpuSubtype = 8; // A15 subtype
            } else if ([cpuArchitecture containsString:@"A16"]) {
                cpuSubtype = 9; // A16 subtype
            } else if ([cpuArchitecture containsString:@"A17"]) {
                cpuSubtype = 10; // A17 subtype
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cpuSubtype = 11; // A18 subtype
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cpuSubtype = 12; // M1 subtype
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cpuSubtype = 13; // M2 subtype
            } else {
                cpuSubtype = 1; // Default ARM64 subtype
            }
        }
        
        if (*oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = cpuSubtype;
            
            static BOOL loggedCPUSubtype = NO;
            if (!loggedCPUSubtype) {
                PXLog(@"[DeviceSpec] Spoofed hw.cpusubtype to %u for %@", cpuSubtype, cpuArchitecture);
                loggedCPUSubtype = YES;
            }
        }
    }
    else if (strcmp(name, "hw.cpufamily") == 0) {
        // CPU Family - unique identifier for each processor family
        uint32_t cpuFamily = 0;
        
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A9"]) {
                cpuFamily = 0x67CEEE93; // Apple A9 family
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cpuFamily = 0x92FB37C8; // Apple A10 family
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cpuFamily = 0xDA33D83D; // Apple A11 family
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cpuFamily = 0x8765EDEA; // Apple A12 family
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cpuFamily = 0xAF4F32CB; // Apple A13 family
            } else if ([cpuArchitecture containsString:@"A14"]) {
                cpuFamily = 0x1B588BB3; // Apple A14 family
            } else if ([cpuArchitecture containsString:@"A15"]) {
                cpuFamily = 0xDA33D83D; // Apple A15 family
            } else if ([cpuArchitecture containsString:@"A16"]) {
                cpuFamily = 0x8765EDEA; // Apple A16 family
            } else if ([cpuArchitecture containsString:@"A17"]) {
                cpuFamily = 0xAF4F32CB; // Apple A17 family
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cpuFamily = 0x1B588BB3; // Apple A18 family
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cpuFamily = 0x458F4D97; // Apple M1 family
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cpuFamily = 0x458F4D97; // Apple M2 family (same as M1)
            } else {
                cpuFamily = 0x67CEEE93; // Default ARM64 family
            }
        }
        
        if (*oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = cpuFamily;
            
            static BOOL loggedCPUFamily = NO;
            if (!loggedCPUFamily) {
                PXLog(@"[DeviceSpec] Spoofed hw.cpufamily to 0x%X for %@", cpuFamily, cpuArchitecture);
                loggedCPUFamily = YES;
            }
        }
    }
    else if (strcmp(name, "hw.cpufrequency") == 0 || strcmp(name, "hw.cpufrequency_max") == 0 || strcmp(name, "hw.cpufrequency_min") == 0) {
        // CPU Frequency - approximate values based on processor
        uint64_t cpuFrequency = 0;
        
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A9"]) {
                cpuFrequency = 1800000000; // 1.8 GHz
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cpuFrequency = 2340000000; // 2.34 GHz
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cpuFrequency = 2390000000; // 2.39 GHz
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cpuFrequency = 2490000000; // 2.49 GHz
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cpuFrequency = 2650000000; // 2.65 GHz
            } else if ([cpuArchitecture containsString:@"A14"]) {
                cpuFrequency = 2990000000; // 2.99 GHz
            } else if ([cpuArchitecture containsString:@"A15"]) {
                cpuFrequency = 3230000000; // 3.23 GHz
            } else if ([cpuArchitecture containsString:@"A16"]) {
                cpuFrequency = 3460000000; // 3.46 GHz
            } else if ([cpuArchitecture containsString:@"A17"]) {
                cpuFrequency = 3780000000; // 3.78 GHz
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cpuFrequency = 4050000000; // 4.05 GHz
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cpuFrequency = 3200000000; // 3.2 GHz
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cpuFrequency = 3490000000; // 3.49 GHz
            } else {
                cpuFrequency = 2000000000; // Default 2.0 GHz
            }
            
            // Adjust for min/max variants
            if (strcmp(name, "hw.cpufrequency_min") == 0) {
                cpuFrequency = cpuFrequency * 0.4; // Min is typically 40% of max
            }
        }
        
        if (*oldlenp >= sizeof(uint64_t)) {
            *(uint64_t *)oldp = cpuFrequency;
        } else if (*oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = (uint32_t)cpuFrequency;
        }
        
        static BOOL loggedCPUFreq = NO;
        if (!loggedCPUFreq) {
            PXLog(@"[DeviceSpec] Spoofed %s to %.2f GHz for %@", name, cpuFrequency / 1000000000.0, cpuArchitecture);
            loggedCPUFreq = YES;
        }
    }
    else if (strcmp(name, "hw.cachelinesize") == 0) {
        // Cache line size - typically 64 bytes for ARM64
        uint32_t cacheLineSize = 64;
        
        if (*oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = cacheLineSize;
            
            static BOOL loggedCacheLineSize = NO;
            if (!loggedCacheLineSize) {
                PXLog(@"[DeviceSpec] Spoofed hw.cachelinesize to %u bytes", cacheLineSize);
                loggedCacheLineSize = YES;
            }
        }
    }
    else if (strcmp(name, "hw.l1icachesize") == 0 || strcmp(name, "hw.l1dcachesize") == 0 || 
             strcmp(name, "hw.l2cachesize") == 0) {
        // Cache sizes vary by processor
        uint32_t cacheSize = 0;
        
        if (cpuArchitecture) {
            BOOL isL1 = (strcmp(name, "hw.l1icachesize") == 0 || strcmp(name, "hw.l1dcachesize") == 0);
            BOOL isL2 = (strcmp(name, "hw.l2cachesize") == 0);
            
            if ([cpuArchitecture containsString:@"A9"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 3145728 : 0); // 32KB L1, 3MB L2
            } else if ([cpuArchitecture containsString:@"A10"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 3145728 : 0); // 32KB L1, 3MB L2  
            } else if ([cpuArchitecture containsString:@"A11"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 8388608 : 0); // 32KB L1, 8MB L2
            } else if ([cpuArchitecture containsString:@"A12"]) {
                cacheSize = isL1 ? 32768 : (isL2 ? 8388608 : 0); // 32KB L1, 8MB L2
            } else if ([cpuArchitecture containsString:@"A13"]) {
                cacheSize = isL1 ? 65536 : (isL2 ? 8388608 : 0); // 64KB L1, 8MB L2
            } else if ([cpuArchitecture containsString:@"A14"] || [cpuArchitecture containsString:@"A15"]) {
                cacheSize = isL1 ? 65536 : (isL2 ? 12582912 : 0); // 64KB L1, 12MB L2
            } else if ([cpuArchitecture containsString:@"A16"] || [cpuArchitecture containsString:@"A17"]) {
                cacheSize = isL1 ? 65536 : (isL2 ? 16777216 : 0); // 64KB L1, 16MB L2
            } else if ([cpuArchitecture containsString:@"A18"]) {
                cacheSize = isL1 ? 131072 : (isL2 ? 20971520 : 0); // 128KB L1, 20MB L2
            } else if ([cpuArchitecture containsString:@"M1"]) {
                cacheSize = isL1 ? 131072 : (isL2 ? 12582912 : 0); // 128KB L1, 12MB L2
            } else if ([cpuArchitecture containsString:@"M2"]) {
                cacheSize = isL1 ? 131072 : (isL2 ? 16777216 : 0); // 128KB L1, 16MB L2
            } else {
                cacheSize = isL1 ? 32768 : (isL2 ? 3145728 : 0); // Default
            }
        }
        
        if (*oldlenp >= sizeof(uint32_t) && cacheSize > 0) {
            *(uint32_t *)oldp = cacheSize;
            
            static NSMutableSet *loggedCacheSizes = nil;
            if (!loggedCacheSizes) {
                loggedCacheSizes = [NSMutableSet set];
            }
            
            if (![loggedCacheSizes containsObject:@(name)]) {
                [loggedCacheSizes addObject:@(name)];
                PXLog(@"[DeviceSpec] Spoofed %s to %u bytes for %@", name, cacheSize, cpuArchitecture);
            }
        }
    }
    // Handle memory-related sysctls
    else if (strcmp(name, "hw.memsize") == 0 || strcmp(name, "hw.physmem") == 0) {
        // Get the device memory from specs (in GB)
        NSInteger deviceMemoryGB = [specs[@"deviceMemory"] integerValue];
        if (deviceMemoryGB <= 0) {
            return result;
        }
        
        // Calculate total memory in bytes
        unsigned long long totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
        
        // Different sysctls might return different size types
        if (*oldlenp == sizeof(uint64_t)) {
            *(uint64_t *)oldp = totalMemory;
        } else if (*oldlenp == sizeof(uint32_t)) {
            *(uint32_t *)oldp = (uint32_t)totalMemory;
        } else if (*oldlenp == sizeof(unsigned long)) {
            *(unsigned long *)oldp = (unsigned long)totalMemory;
        }
        
        // Log the change the first time
        static BOOL loggedMemSize = NO;
        if (!loggedMemSize) {
            PXLog(@"[DeviceSpec] Spoofed sysctlbyname %s to %llu bytes (%ld GB)",
                name, totalMemory, (long)deviceMemoryGB);
            loggedMemSize = YES;
        }
    } else if (strcmp(name, "vm.swapusage") == 0 && *oldlenp >= sizeof(xsw_usage)) {
        // Swap usage information
        xsw_usage *swap = (xsw_usage *)oldp;
        
        // Get the device memory from specs (in GB)
        NSInteger deviceMemoryGB = [specs[@"deviceMemory"] integerValue];
        if (deviceMemoryGB <= 0) {
            return result;
        }
        
        // Calculate realistic swap values based on device memory
        // iOS typically uses swap space proportional to RAM
        uint64_t totalMemory = deviceMemoryGB * 1024 * 1024 * 1024;
        
        // Typical iOS swap is ~50-100% of RAM depending on device
        float swapRatio = (deviceMemoryGB >= 4) ? 0.5 : 1.0;  // Less swap on high-RAM devices
        
        swap->xsu_total = totalMemory * swapRatio;
        swap->xsu_avail = totalMemory * swapRatio * 0.7;  // 70% available
        swap->xsu_used = totalMemory * swapRatio * 0.3;   // 30% used
        
        // Log the change the first time
        static BOOL loggedSwap = NO;
        if (!loggedSwap) {
            PXLog(@"[DeviceSpec] Spoofed vm.swapusage to %llu total, %llu used, %llu available",
                swap->xsu_total, swap->xsu_used, swap->xsu_avail);
            loggedSwap = YES;
        }
    }
    // Add additional CPU feature and identification sysctls
    else if (strncmp(name, "hw.optional.", 12) == 0) {
        // Handle CPU feature flags - these indicate specific CPU capabilities
        // Most ARM64 devices support these features consistently
        BOOL featureSupported = YES;
        
        // Some features that might not be supported on older processors
        if (cpuArchitecture) {
            if (strstr(name, "arm64e") && [cpuArchitecture containsString:@"A9"]) {
                featureSupported = NO; // A9 doesn't support arm64e
            } else if (strstr(name, "armv8_3") && ([cpuArchitecture containsString:@"A9"] || [cpuArchitecture containsString:@"A10"])) {
                featureSupported = NO; // A9/A10 don't support ARMv8.3
            }
        }
        
        if (*oldlenp >= sizeof(uint32_t)) {
            *(uint32_t *)oldp = featureSupported ? 1 : 0;
            
            static NSMutableSet *loggedOptionalFeatures = nil;
            if (!loggedOptionalFeatures) {
                loggedOptionalFeatures = [NSMutableSet set];
            }
            
            NSString *featureName = [NSString stringWithUTF8String:name];
            if (![loggedOptionalFeatures containsObject:featureName]) {
                [loggedOptionalFeatures addObject:featureName];
                PXLog(@"[DeviceSpec] Spoofed %s to %d for %@", name, featureSupported ? 1 : 0, cpuArchitecture);
            }
        }
    }
    else if (strcmp(name, "hw.machine") == 0) {
        // Machine name - should return the device model like "iPhone10,1"
        NSString *deviceModel = getSpoofedDeviceModel();
        if (deviceModel && deviceModel.length > 0) {
            const char *machineStr = [deviceModel UTF8String];
            if (machineStr && *oldlenp > 0) {
                size_t machineLen = strlen(machineStr);
                if (machineLen < *oldlenp) {
                    *oldlenp = machineLen + 1;
                    memset(oldp, 0, *oldlenp);
                    strcpy(oldp, machineStr);
                    
                    static BOOL loggedMachine = NO;
                    if (!loggedMachine) {
                        PXLog(@"[DeviceSpec] Spoofed hw.machine to '%s'", machineStr);
                        loggedMachine = YES;
                    }
                } else {
                    PXLog(@"[DeviceSpec] WARNING: Machine string too long for buffer");
                }
            }
        }
    }
    else if (strcmp(name, "hw.cpu.features") == 0) {
        // CPU features string - return a realistic feature set
        NSString *cpuFeatures = @"SSE SSE2 SSE3 SSSE3 SSE4.1 SSE4.2 AES AVX AVX2 BMI1 BMI2 FMA";
        
        // For ARM64, use ARM-specific features
        if (cpuArchitecture) {
            if ([cpuArchitecture containsString:@"A17"] || [cpuArchitecture containsString:@"A18"] || [cpuArchitecture containsString:@"M"]) {
                cpuFeatures = @"NEON AES SHA1 SHA2 CRC32 ATOMICS FP16 JSCVT FCMA LRCPC";
            } else if ([cpuArchitecture containsString:@"A15"] || [cpuArchitecture containsString:@"A16"]) {
                cpuFeatures = @"NEON AES SHA1 SHA2 CRC32 ATOMICS FP16 JSCVT";
            } else {
                cpuFeatures = @"NEON AES SHA1 SHA2 CRC32 ATOMICS";
            }
        }
        
        const char *featuresStr = [cpuFeatures UTF8String];
        if (featuresStr && *oldlenp > 0) {
            size_t featuresLen = strlen(featuresStr);
            if (featuresLen < *oldlenp) {
                *oldlenp = featuresLen + 1;
                memset(oldp, 0, *oldlenp);
                strcpy(oldp, featuresStr);
                
                static BOOL loggedFeatures = NO;
                if (!loggedFeatures) {
                    PXLog(@"[DeviceSpec] Spoofed hw.cpu.features to '%s'", featuresStr);
                    loggedFeatures = YES;
                }
            }
        }
    }
    
    return result;
} 