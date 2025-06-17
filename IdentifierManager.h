#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ProjectX.h"

// Declare this in a category to avoid duplicate interface
@interface IdentifierManager (ProfilePath)
- (NSString *)profileIdentityPath;
@end

@interface IdentifierManager (AppManagement)

#pragma mark - App Management

- (void)addApplicationToScope:(NSString *)bundleID;
- (void)removeApplicationFromScope:(NSString *)bundleID;
- (void)setApplication:(NSString *)bundleID enabled:(BOOL)enabled;
- (NSDictionary *)getApplicationInfo:(NSString *)bundleID;
- (BOOL)isApplicationEnabled:(NSString *)bundleID;
- (void)refreshScopedAppsInfoIfNeeded;
- (void)addApplicationWithExtensionsToScope:(NSString *)bundleID;
- (BOOL)isApplicationInScope:(NSString *)bundleID;
- (BOOL)isExtensionEnabled:(NSString *)bundleID;
- (BOOL)isBundleIDMatch:(NSString *)targetBundleID withPattern:(NSString *)patternBundleID;
- (void)saveScopedApps;

#pragma mark - Custom Values

// Set custom values for identifiers
- (BOOL)setCustomIDFA:(NSString *)value;
- (BOOL)setCustomIDFV:(NSString *)value;
- (BOOL)setCustomDeviceName:(NSString *)value;
- (BOOL)setCustomSerialNumber:(NSString *)value;
- (BOOL)setCustomSystemBootUUID:(NSString *)value;
- (BOOL)setCustomDyldCacheUUID:(NSString *)value;
- (BOOL)setCustomPasteboardUUID:(NSString *)value;
- (BOOL)setCustomKeychainUUID:(NSString *)value;
- (BOOL)setCustomUserDefaultsUUID:(NSString *)value;
- (BOOL)setCustomAppGroupUUID:(NSString *)value;
- (BOOL)setCustomCoreDataUUID:(NSString *)value;
- (BOOL)setCustomAppInstallUUID:(NSString *)value;
- (BOOL)setCustomAppContainerUUID:(NSString *)value;

// Canvas Fingerprinting Protection
- (BOOL)toggleCanvasFingerprintProtection;
- (BOOL)isCanvasFingerprintProtectionEnabled;
- (BOOL)setCanvasFingerprintProtection:(BOOL)enabled;
- (void)resetCanvasNoise;
// Device Model
- (BOOL)setCustomDeviceModel:(NSString *)value;
- (NSString *)generateDeviceModel;

// Device Theme
- (BOOL)setCustomDeviceTheme:(NSString *)value;
- (NSString *)generateDeviceTheme;
- (NSString *)toggleDeviceTheme;

// Device Model Specifications
- (NSDictionary *)getDeviceModelSpecifications;
- (NSString *)getScreenResolution;
- (NSString *)getViewportResolution;
- (CGFloat)getDevicePixelRatio;
- (NSInteger)getScreenDensity;
- (NSString *)getCPUArchitecture;
- (NSInteger)getDeviceMemory;
- (NSString *)getGPUFamily;
- (NSDictionary *)getWebGLInfo;
- (NSInteger)getCPUCoreCount;
- (NSString *)getMetalFeatureSet;

// IMEI/MEID
- (BOOL)setCustomIMEI:(NSString *)value;
- (BOOL)setCustomMEID:(NSString *)value;
- (NSString *)generateIMEI;
- (NSString *)generateMEID;

@end