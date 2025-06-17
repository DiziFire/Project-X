#import "DomainBlockingSettings.h"

// Multiple possible paths for rootless jailbreak compatibility
static NSString *const kDomainBlockingSettingsFile = @"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.domainblocking.plist";
static NSString *const kDomainBlockingSettingsFileAlt1 = @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.domainblocking.plist";
static NSString *const kDomainBlockingSettingsFileAlt2 = @"/var/mobile/Library/Preferences/com.hydra.projectx.domainblocking.plist";
static NSString *const kIsEnabledKey = @"isEnabled";
static NSString *const kBlockedDomainsKey = @"blockedDomains";
static NSString *const kCustomDomainsKey = @"customDomains";

@interface DomainBlockingSettings ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *customDomainsStatus;
@end

// Helper function to find the correct settings file path
static NSString *getSettingsFilePath(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Try each possible path in order of preference
    NSArray *possiblePaths = @[
        kDomainBlockingSettingsFile,        // Primary rootless path
        kDomainBlockingSettingsFileAlt1,    // Alternative rootless path  
        kDomainBlockingSettingsFileAlt2     // Legacy non-rootless path
    ];
    
    for (NSString *path in possiblePaths) {
        if ([fileManager fileExistsAtPath:path]) {
            return path;
        }
    }
    
    // If no file exists, return the primary path for creating new file
    return kDomainBlockingSettingsFile;
}

// Helper function to ensure directory exists before saving
static void ensureDirectoryExists(NSString *filePath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directory = [filePath stringByDeletingLastPathComponent];
    
    if (![fileManager fileExistsAtPath:directory]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            // STEALTH: No logging - avoid detection
        }
    }
}

@implementation DomainBlockingSettings

+ (instancetype)sharedSettings {
    static DomainBlockingSettings *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[DomainBlockingSettings] Creating shared instance");
        sharedInstance = [[self alloc] init];
        NSLog(@"[DomainBlockingSettings] Before loadSettings - domains: %@", sharedInstance.blockedDomains);
        [sharedInstance loadSettings];
        NSLog(@"[DomainBlockingSettings] After loadSettings - domains: %@", sharedInstance.blockedDomains);
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize empty blocked domains list (built from custom domains only)
        _blockedDomains = [NSMutableArray array];
        
        // Initialize custom domains status (this is where all domains go)
        _customDomainsStatus = [NSMutableDictionary dictionary];
        
        // Add critical Apple domains by default for essential protection
        _customDomainsStatus[@"devicecheck.apple.com"] = @YES;
        _customDomainsStatus[@"appattest.apple.com"] = @YES;
        
        // Build the initial blocked domains list
        [self rebuildBlockedDomainsList];
        
        _isEnabled = YES;
        
        // TEMPORARY DEBUG
        NSLog(@"[DomainBlockingSettings] Initialized with domains: %@", _blockedDomains);
    }
    return self;
}

- (void)saveSettings {
    @try {
        NSString *settingsPath = getSettingsFilePath();
        NSLog(@"[DomainBlockingSettings] Saving to path: %@", settingsPath);
        
        // Ensure directory exists before saving
        ensureDirectoryExists(settingsPath);
        
        NSDictionary *settings = @{
            kIsEnabledKey: @(self.isEnabled),
            kBlockedDomainsKey: self.blockedDomains,
            kCustomDomainsKey: self.customDomainsStatus
        };
        
        NSLog(@"[DomainBlockingSettings] Saving settings: %@", settings);
        
        BOOL success = [settings writeToFile:settingsPath atomically:YES];
        if (!success) {
            NSLog(@"[DomainBlockingSettings] ERROR: Failed to save settings!");
        } else {
            NSLog(@"[DomainBlockingSettings] Settings saved successfully");
        }
    } @catch (NSException *exception) {
        NSLog(@"[DomainBlockingSettings] Exception saving: %@", exception);
    }
}

- (void)loadSettings {
    @try {
        NSString *settingsPath = getSettingsFilePath();
        NSLog(@"[DomainBlockingSettings] Loading from path: %@", settingsPath);
        
        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
        
        if (settings) {
            NSLog(@"[DomainBlockingSettings] Found settings file");
            
            // Load enabled state (default to YES if not found)
            if (settings[kIsEnabledKey] != nil) {
                self.isEnabled = [settings[kIsEnabledKey] boolValue];
            } else {
                self.isEnabled = YES; // Default to enabled
            }
            
            // Load custom domains status - CRITICAL FIX: Clear and reload ALL domains
            NSDictionary *savedCustomStatus = settings[kCustomDomainsKey];
            if ([savedCustomStatus isKindOfClass:[NSDictionary class]]) {
                // IMPORTANT: We need to replace the dictionary, not merge
                // because the saved file contains ALL domains (defaults + custom)
                [self.customDomainsStatus removeAllObjects];
                [self.customDomainsStatus addEntriesFromDictionary:savedCustomStatus];
                NSLog(@"[DomainBlockingSettings] Loaded custom domains: %@", savedCustomStatus);
            }
            
            // Legacy support for old format - migrate old blocked domains to custom domains
            NSArray *savedDomains = settings[kBlockedDomainsKey];
            if ([savedDomains isKindOfClass:[NSArray class]] && !savedCustomStatus) {
                // STEALTH: No logging - avoid detection
                // Migrate old format - add all old blocked domains as custom domains
                for (NSString *domain in savedDomains) {
                    // Add to custom domains with enabled status
                    self.customDomainsStatus[domain] = @YES;
                }
                // Save migrated format
                [self saveSettings];
            }
            
            // Rebuild blocked domains list from custom domains
            [self rebuildBlockedDomainsList];
            
            // STEALTH: No logging - avoid detection
            
        } else {
            NSLog(@"[DomainBlockingSettings] No settings file found, keeping defaults");
            // No settings file found, keep defaults from init
            // Important: Don't clear customDomainsStatus here!
            
            // Save the defaults to create the file
            [self saveSettings];
        }
    } @catch (NSException *exception) {
        NSLog(@"[DomainBlockingSettings] Exception loading: %@", exception);
        // Use defaults on error - but don't clear them!
        // self.isEnabled is already YES from init
        // customDomainsStatus already has default domains
        // Just rebuild the list
        [self rebuildBlockedDomainsList];
    }
}

- (void)rebuildBlockedDomainsList {
    [self.blockedDomains removeAllObjects];
    
    NSLog(@"[DomainBlockingSettings] Rebuilding list from customDomainsStatus: %@", self.customDomainsStatus);
    
    // Add all enabled custom domains (this is now the only source)
    NSMutableArray *enabledDomains = [NSMutableArray array];
    for (NSString *domain in self.customDomainsStatus.allKeys) {
        BOOL isEnabled = [self.customDomainsStatus[domain] boolValue];
        if (isEnabled) {
            [self.blockedDomains addObject:domain];
            [enabledDomains addObject:domain];
        }
    }
    
    NSLog(@"[DomainBlockingSettings] Final blocked domains: %@", self.blockedDomains);
}

- (void)addDomain:(NSString *)domain {
    NSLog(@"[DomainBlockingSettings] addDomain called with: %@", domain);
    
    if (![self.blockedDomains containsObject:domain]) {
        // Add as custom domain with enabled status
        self.customDomainsStatus[domain] = @YES;
        NSLog(@"[DomainBlockingSettings] Added domain to customDomainsStatus: %@", self.customDomainsStatus);
        
        [self rebuildBlockedDomainsList];
        [self saveSettings];
    } else {
        NSLog(@"[DomainBlockingSettings] Domain already in blocked list: %@", domain);
    }
}

- (void)removeDomain:(NSString *)domain {
    // Remove from custom domains
    if (self.customDomainsStatus[domain] != nil) {
        self.customDomainsStatus[domain] = @NO;
        [self rebuildBlockedDomainsList];
        [self saveSettings];
    }
}

// Removed optional domain methods - everything is now custom domains

- (BOOL)isDomainBlocked:(NSString *)domain {
    if (!self.isEnabled) {
        return NO;
    }
    
    if (!domain || domain.length == 0) {
        return NO;
    }
    
    // Convert to lowercase for case-insensitive comparison
    NSString *lowerDomain = [domain lowercaseString];
    
    // Remove any trailing dots (DNS format)
    if ([lowerDomain hasSuffix:@"."]) {
        lowerDomain = [lowerDomain substringToIndex:lowerDomain.length - 1];
    }
    
    for (NSString *blockedDomain in self.blockedDomains) {
        NSString *lowerBlocked = [blockedDomain lowercaseString];
        
        // Remove any trailing dots from blocked domain too
        if ([lowerBlocked hasSuffix:@"."]) {
            lowerBlocked = [lowerBlocked substringToIndex:lowerBlocked.length - 1];
        }
        
        // Exact match
        if ([lowerDomain isEqualToString:lowerBlocked]) {
            // STEALTH: No logging - avoid detection
            return YES;
        }
        
        // Subdomain match: if requested domain ends with "." + blocked domain
        // Example: api.example.com should be blocked if example.com is in blocklist
        NSString *dotPrefixedBlocked = [@"." stringByAppendingString:lowerBlocked];
        if ([lowerDomain hasSuffix:dotPrefixedBlocked]) {
            // STEALTH: No logging - avoid detection
            return YES;
        }
    }
    
    return NO;
}

// Removed getEnabledByDefaultDomains - no longer needed

#pragma mark - Custom Domain Management

- (void)setCustomDomainEnabled:(NSString *)domain enabled:(BOOL)enabled {
    if (self.customDomainsStatus[domain] != nil) {
        self.customDomainsStatus[domain] = @(enabled);
        [self rebuildBlockedDomainsList];
        [self saveSettings];
    }
}

- (BOOL)isCustomDomainEnabled:(NSString *)domain {
    return [self.customDomainsStatus[domain] boolValue];
}

- (void)removeCustomDomain:(NSString *)domain {
    if (self.customDomainsStatus[domain] != nil) {
        [self.customDomainsStatus removeObjectForKey:domain];
        [self rebuildBlockedDomainsList];
        [self saveSettings];
    }
}

- (NSArray<NSDictionary *> *)getCustomDomains {
    NSMutableArray *customDomains = [NSMutableArray array];
    for (NSString *domain in self.customDomainsStatus.allKeys) {
        BOOL enabled = [self.customDomainsStatus[domain] boolValue];
        [customDomains addObject:@{
            @"domain": domain,
            @"enabled": @(enabled),
            @"category": @"Custom",
            @"description": @"User added domain"
        }];
    }
    return [customDomains sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        return [obj1[@"domain"] localizedCaseInsensitiveCompare:obj2[@"domain"]];
    }];
    }

- (BOOL)isCustomDomain:(NSString *)domain {
    return self.customDomainsStatus[domain] != nil;
}

- (NSArray<NSDictionary *> *)getAllDomains {
    // Only custom domains now - just return the custom domains list
    return [self getCustomDomains];
}

@end
