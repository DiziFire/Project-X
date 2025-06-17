#import <Foundation/Foundation.h>

@interface JailbreakDetectionBypass : NSObject

+ (instancetype)sharedInstance;

// Setup the jailbreak detection bypass - call this early in the initialization process
- (void)setupBypass;

// Check if bypass is enabled for an app
- (BOOL)isEnabledForApp:(NSString *)bundleID;

// Toggle the jailbreak detection bypass
- (void)setEnabled:(BOOL)enabled;
- (BOOL)isEnabled;

@end
