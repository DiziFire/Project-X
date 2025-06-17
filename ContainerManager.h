#import <Foundation/Foundation.h>

@interface ContainerManager : NSObject

@property (nonatomic, readonly, strong) NSString *currentProfileID;

// Shared manager accessor
+ (instancetype)sharedManager;
+ (instancetype)sharedInstance;

// Path Translation
- (NSString *)translatePath:(NSString *)originalPath forApp:(NSString *)bundleID inProfile:(NSString *)profileID;
- (BOOL)isPathRedirectable:(NSString *)path forApp:(NSString *)bundleID;

// Directory Structure
- (NSString *)profileBasePath:(NSString *)profileID;
- (NSString *)appBasePath:(NSString *)profileID bundleID:(NSString *)bundleID;
- (NSString *)appDataPath:(NSString *)bundleID inProfile:(NSString *)profileID;

// Profile Integration
- (void)profileDidChange:(NSString *)newProfileID;
- (BOOL)prepareProfileDirectory:(NSString *)profileID;

// Gets the current profile ID
- (NSString *)currentProfileID;

// Translates a path for the current environment (rootful or rootless)
+ (NSString *)translatePathForEnvironment:(NSString *)path;

// System app detection
- (BOOL)isSystemApp:(NSString *)bundleID;

@end 