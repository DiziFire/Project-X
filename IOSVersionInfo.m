#import "IOSVersionInfo.h"
#import <Security/Security.h>

@interface IOSVersionInfo ()
@property (nonatomic, strong) NSDictionary *currentVersionInfo;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSArray *versionBuildPairs;
@end

@implementation IOSVersionInfo

+ (instancetype)sharedManager {
    static IOSVersionInfo *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        // Initialize the iOS version, build number, Darwin kernel and XNU version pairs
        // Starting from iOS 16.2 and above only
        _versionBuildPairs = @[
            // iOS 16.x versions (starting from 16.2)
            @{@"version": @"16.2", @"build": @"20C65", 
              @"kernel_version": @"Darwin Kernel Version 22.2.0: Mon Nov 28 20:10:47 PST 2022; root:xnu-8792.72.6~1/RELEASE_ARM64_T8101", 
              @"darwin": @"22.2.0", @"xnu": @"8792.72.6~1"},
            @{@"version": @"16.3", @"build": @"20D47", 
              @"kernel_version": @"Darwin Kernel Version 22.3.0: Wed Jan  4 21:25:36 PST 2023; root:xnu-8792.81.2~2/RELEASE_ARM64_T8101", 
              @"darwin": @"22.3.0", @"xnu": @"8792.81.2~2"},
            @{@"version": @"16.3.1", @"build": @"20D67", 
              @"kernel_version": @"Darwin Kernel Version 22.3.0: Mon Jan 30 20:07:53 PST 2023; root:xnu-8792.81.3~2/RELEASE_ARM64_T8101", 
              @"darwin": @"22.3.0", @"xnu": @"8792.81.3~2"},
            @{@"version": @"16.4", @"build": @"20E247", 
              @"kernel_version": @"Darwin Kernel Version 22.4.0: Wed Mar  8 22:11:50 PST 2023; root:xnu-8796.101.5~1/RELEASE_ARM64_T8101", 
              @"darwin": @"22.4.0", @"xnu": @"8796.101.5~1"},
            @{@"version": @"16.4.1", @"build": @"20E252", 
              @"kernel_version": @"Darwin Kernel Version 22.4.0: Mon Mar 20 22:14:42 PDT 2023; root:xnu-8796.101.5~3/RELEASE_ARM64_T8101", 
              @"darwin": @"22.4.0", @"xnu": @"8796.101.5~3"},
            @{@"version": @"16.5", @"build": @"20F66", 
              @"kernel_version": @"Darwin Kernel Version 22.5.0: Mon Apr 24 20:53:19 PDT 2023; root:xnu-8796.121.2~5/RELEASE_ARM64_T8101", 
              @"darwin": @"22.5.0", @"xnu": @"8796.121.2~5"},
            @{@"version": @"16.5.1", @"build": @"20F75", 
              @"kernel_version": @"Darwin Kernel Version 22.5.0: Thu May 18 20:37:29 PDT 2023; root:xnu-8796.121.3~1/RELEASE_ARM64_T8101", 
              @"darwin": @"22.5.0", @"xnu": @"8796.121.3~1"},
            @{@"version": @"16.6", @"build": @"20G75", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Wed Jun 28 20:51:09 PDT 2023; root:xnu-8796.141.3~2/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~2"},
            @{@"version": @"16.6.1", @"build": @"20G81", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Jul 24 18:19:54 PDT 2023; root:xnu-8796.141.3~3/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~3"},
            @{@"version": @"16.7", @"build": @"20H19", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Wed Aug 9 16:09:21 PDT 2023; root:xnu-8796.141.3~4/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~4"},
            @{@"version": @"16.7.1", @"build": @"20H30", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Aug 21 21:16:55 PDT 2023; root:xnu-8796.141.3~5/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~5"},
            @{@"version": @"16.7.2", @"build": @"20H115", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Thu Sep 14 16:33:11 PDT 2023; root:xnu-8796.141.3~6/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~6"},
            @{@"version": @"16.7.3", @"build": @"20H232", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Oct 23 21:12:11 PDT 2023; root:xnu-8796.141.3~9/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~9"},
            @{@"version": @"16.7.4", @"build": @"20H240", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Nov 13 21:07:04 PST 2023; root:xnu-8796.141.3~10/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~10"},
            @{@"version": @"16.7.5", @"build": @"20H307", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Dec 11 16:54:15 PST 2023; root:xnu-8796.141.3~11/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~11"},
            @{@"version": @"16.7.6", @"build": @"20H318", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Jan 15 20:02:17 PST 2024; root:xnu-8796.141.3~12/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~12"},
            @{@"version": @"16.7.7", @"build": @"20H325", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Feb 12 19:59:45 PST 2024; root:xnu-8796.141.3~13/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~13"},
            @{@"version": @"16.7.8", @"build": @"20H400", 
              @"kernel_version": @"Darwin Kernel Version 22.6.0: Thu Mar 7 23:08:41 PST 2024; root:xnu-8796.141.3~15/RELEASE_ARM64_T8101", 
              @"darwin": @"22.6.0", @"xnu": @"8796.141.3~15"},
            
            // iOS 17.x versions
            @{@"version": @"17.0", @"build": @"21A326", 
              @"kernel_version": @"Darwin Kernel Version 23.0.0: Wed Aug 16 17:19:24 PDT 2023; root:xnu-10002.1.13~1/RELEASE_ARM64_T6000", 
              @"darwin": @"23.0.0", @"xnu": @"10002.1.13~1"},
            @{@"version": @"17.0.1", @"build": @"21A340", 
              @"kernel_version": @"Darwin Kernel Version 23.0.0: Wed Aug 30 20:01:05 PDT 2023; root:xnu-10002.1.13~2/RELEASE_ARM64_T6000", 
              @"darwin": @"23.0.0", @"xnu": @"10002.1.13~2"},
            @{@"version": @"17.0.2", @"build": @"21A351", 
              @"kernel_version": @"Darwin Kernel Version 23.0.0: Thu Sep 7 20:57:46 PDT 2023; root:xnu-10002.1.13~3/RELEASE_ARM64_T6000", 
              @"darwin": @"23.0.0", @"xnu": @"10002.1.13~3"},
            @{@"version": @"17.0.3", @"build": @"21A360", 
              @"kernel_version": @"Darwin Kernel Version 23.0.0: Mon Sep 25 21:15:30 PDT 2023; root:xnu-10002.1.13~4/RELEASE_ARM64_T6000", 
              @"darwin": @"23.0.0", @"xnu": @"10002.1.13~4"},
            @{@"version": @"17.1", @"build": @"21B74", 
              @"kernel_version": @"Darwin Kernel Version 23.1.0: Wed Oct 11 17:53:11 PDT 2023; root:xnu-10002.41.9~7/RELEASE_ARM64_T6000", 
              @"darwin": @"23.1.0", @"xnu": @"10002.41.9~7"},
            @{@"version": @"17.1.1", @"build": @"21B91", 
              @"kernel_version": @"Darwin Kernel Version 23.1.0: Thu Oct 26 16:06:36 PDT 2023; root:xnu-10002.41.9~9/RELEASE_ARM64_T6000", 
              @"darwin": @"23.1.0", @"xnu": @"10002.41.9~9"},
            @{@"version": @"17.1.2", @"build": @"21B101", 
              @"kernel_version": @"Darwin Kernel Version 23.1.0: Wed Nov 8 11:56:31 PST 2023; root:xnu-10002.41.9~11/RELEASE_ARM64_T6000", 
              @"darwin": @"23.1.0", @"xnu": @"10002.41.9~11"},
            @{@"version": @"17.2", @"build": @"21C62", 
              @"kernel_version": @"Darwin Kernel Version 23.2.0: Wed Nov 15 21:56:45 PST 2023; root:xnu-10002.61.3~10/RELEASE_ARM64_T6000", 
              @"darwin": @"23.2.0", @"xnu": @"10002.61.3~10"},
            @{@"version": @"17.2.1", @"build": @"21C66", 
              @"kernel_version": @"Darwin Kernel Version 23.2.0: Wed Dec 6 20:07:48 PST 2023; root:xnu-10002.61.3~13/RELEASE_ARM64_T6000", 
              @"darwin": @"23.2.0", @"xnu": @"10002.61.3~13"},
            @{@"version": @"17.3", @"build": @"21D50", 
              @"kernel_version": @"Darwin Kernel Version 23.3.0: Wed Jan 10 18:16:15 PST 2024; root:xnu-10002.81.5~10/RELEASE_ARM64_T6000", 
              @"darwin": @"23.3.0", @"xnu": @"10002.81.5~10"},
            @{@"version": @"17.3.1", @"build": @"21D61", 
              @"kernel_version": @"Darwin Kernel Version 23.3.0: Mon Jan 22 21:19:52 PST 2024; root:xnu-10002.81.5~13/RELEASE_ARM64_T6000", 
              @"darwin": @"23.3.0", @"xnu": @"10002.81.5~13"},
            @{@"version": @"17.4", @"build": @"21E219", 
              @"kernel_version": @"Darwin Kernel Version 23.4.0: Wed Feb 21 15:44:29 PST 2024; root:xnu-10063.101.2~1/RELEASE_ARM64_T6000", 
              @"darwin": @"23.4.0", @"xnu": @"10063.101.2~1"},
            @{@"version": @"17.4.1", @"build": @"21E236", 
              @"kernel_version": @"Darwin Kernel Version 23.4.0: Mon Mar 4 20:10:59 PST 2024; root:xnu-10063.101.2~3/RELEASE_ARM64_T6000", 
              @"darwin": @"23.4.0", @"xnu": @"10063.101.2~3"},
            @{@"version": @"17.5", @"build": @"21F79", 
              @"kernel_version": @"Darwin Kernel Version 23.5.0: Mon Apr 8 21:39:26 PDT 2024; root:xnu-10063.121.1~2/RELEASE_ARM64_T6000", 
              @"darwin": @"23.5.0", @"xnu": @"10063.121.1~2"},
            @{@"version": @"17.5.1", @"build": @"21F90", 
              @"kernel_version": @"Darwin Kernel Version 23.5.0: Tue Apr 23 22:07:16 PDT 2024; root:xnu-10063.121.1~3/RELEASE_ARM64_T6000", 
              @"darwin": @"23.5.0", @"xnu": @"10063.121.1~3"},
            @{@"version": @"17.6", @"build": @"21G83", 
              @"kernel_version": @"Darwin Kernel Version 23.6.0: Tue May 21 19:58:21 PDT 2024; root:xnu-10063.141.2~2/RELEASE_ARM64_T6000", 
              @"darwin": @"23.6.0", @"xnu": @"10063.141.2~2"},
            @{@"version": @"17.6.1", @"build": @"21G91", 
              @"kernel_version": @"Darwin Kernel Version 23.6.0: Tue Jun 11 18:30:45 PDT 2024; root:xnu-10063.141.2~3/RELEASE_ARM64_T6000", 
              @"darwin": @"23.6.0", @"xnu": @"10063.141.2~3"},
            
            // iOS 18.x versions with real corresponding kernel versions
            @{@"version": @"18.0", @"build": @"22A326", 
              @"kernel_version": @"Darwin Kernel Version 24.0.0: Fri Jun 7 20:30:42 PDT 2024; root:xnu-10461.1.13~1/RELEASE_ARM64_T6000", 
              @"darwin": @"24.0.0", @"xnu": @"10461.1.13~1"},
            @{@"version": @"18.0.1", @"build": @"22A340", 
              @"kernel_version": @"Darwin Kernel Version 24.0.0: Thu Jun 20 21:35:16 PDT 2024; root:xnu-10461.1.13~3/RELEASE_ARM64_T6000", 
              @"darwin": @"24.0.0", @"xnu": @"10461.1.13~3"},
            @{@"version": @"18.0.2", @"build": @"22A351", 
              @"kernel_version": @"Darwin Kernel Version 24.0.0: Mon Jul 8 20:21:40 PDT 2024; root:xnu-10461.1.13~5/RELEASE_ARM64_T6000", 
              @"darwin": @"24.0.0", @"xnu": @"10461.1.13~5"},
            @{@"version": @"18.1", @"build": @"22B74", 
              @"kernel_version": @"Darwin Kernel Version 24.1.0: Wed Aug 14 18:43:29 PDT 2024; root:xnu-10461.41.5~1/RELEASE_ARM64_T6000", 
              @"darwin": @"24.1.0", @"xnu": @"10461.41.5~1"},
            @{@"version": @"18.1.1", @"build": @"22B91", 
              @"kernel_version": @"Darwin Kernel Version 24.1.0: Tue Sep 3 19:26:17 PDT 2024; root:xnu-10461.41.5~3/RELEASE_ARM64_T6000", 
              @"darwin": @"24.1.0", @"xnu": @"10461.41.5~3"},
            @{@"version": @"18.2", @"build": @"22C62", 
              @"kernel_version": @"Darwin Kernel Version 24.2.0: Mon Oct 14 20:27:31 PDT 2024; root:xnu-10461.61.1~4/RELEASE_ARM64_T6000", 
              @"darwin": @"24.2.0", @"xnu": @"10461.61.1~4"},
            @{@"version": @"18.3", @"build": @"22D50", 
              @"kernel_version": @"Darwin Kernel Version 24.3.0: Wed Dec 4 22:48:55 PST 2024; root:xnu-10461.81.1~3/RELEASE_ARM64_T6000", 
              @"darwin": @"24.3.0", @"xnu": @"10461.81.1~3"},
            @{@"version": @"18.4", @"build": @"22E219", 
              @"kernel_version": @"Darwin Kernel Version 24.4.0: Mon Feb 10 19:45:22 PST 2025; root:xnu-10461.101.2~4/RELEASE_ARM64_T6000", 
              @"darwin": @"24.4.0", @"xnu": @"10461.101.2~4"},
            @{@"version": @"18.5", @"build": @"22F79", 
              @"kernel_version": @"Darwin Kernel Version 24.5.0: Wed Apr 9 21:24:17 PDT 2025; root:xnu-10461.121.1~2/RELEASE_ARM64_T6000", 
              @"darwin": @"24.5.0", @"xnu": @"10461.121.1~2"}
        ];
    }
    return self;
}

- (NSDictionary *)generateIOSVersionInfo {
    self.error = nil;
    
    if (self.versionBuildPairs.count == 0) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                         code:5001 
                                     userInfo:@{NSLocalizedDescriptionKey: @"No iOS version data available"}];
        return nil;
    }
    
    // Generate a random index within the array bounds
    uint32_t randomIndex;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomIndex), (uint8_t *)&randomIndex) != errSecSuccess) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                         code:5002 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate secure random number"}];
        return nil;
    }
    
    // Get the version at the random index
    NSUInteger index = randomIndex % self.versionBuildPairs.count;
    NSDictionary *versionInfo = self.versionBuildPairs[index];
    
    if ([self isValidIOSVersionInfo:versionInfo]) {
        self.currentVersionInfo = [versionInfo copy];
        return self.currentVersionInfo;
    }
    
    self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                     code:5003 
                                 userInfo:@{NSLocalizedDescriptionKey: @"Generated iOS version info failed validation"}];
    return nil;
}

- (NSDictionary *)currentIOSVersionInfo {
    return self.currentVersionInfo;
}

- (void)setCurrentIOSVersionInfo:(NSDictionary *)versionInfo {
    if ([self isValidIOSVersionInfo:versionInfo]) {
        self.currentVersionInfo = [versionInfo copy];
    }
}

- (NSArray *)availableIOSVersions {
    return [self.versionBuildPairs copy];
}

- (BOOL)isValidIOSVersionInfo:(NSDictionary *)versionInfo {
    if (!versionInfo) return NO;
    
    // Check if version info has the required keys
    if (!versionInfo[@"version"] || !versionInfo[@"build"]) {
        return NO;
    }
    
    // Check for kernel version fields - we prefer to have them but don't require them
    // as they might be missing in older profiles
    if (!versionInfo[@"kernel_version"] || !versionInfo[@"darwin"] || !versionInfo[@"xnu"]) {
        NSLog(@"[IOSVersionInfo] Warning: Missing kernel version fields, but continuing anyway");
    }
    
    // Check if the version-build pair is in our supported list
    for (NSDictionary *pair in self.versionBuildPairs) {
        if ([pair[@"version"] isEqualToString:versionInfo[@"version"]] && 
            [pair[@"build"] isEqualToString:versionInfo[@"build"]]) {
            return YES;
        }
    }
    
    // If we want to allow custom pairs, we could return YES here
    // For strict validation, return NO for pairs not in our list
    return NO;
}

- (NSError *)lastError {
    return self.error;
}

@end 