#import "ProfileManager.h"
#import <UIKit/UIKit.h>
#import "ContainerManager.h"
#import <spawn.h>
#import <sys/wait.h>

// Forward declaration for app termination
@interface BottomButtons : NSObject
+ (instancetype)sharedInstance;
- (void)terminateApplicationWithBundleID:(NSString *)bundleID;
- (void)killAppViaExecutableName:(NSString *)bundleID;
@end

@interface SBSRelaunchAction : NSObject
+ (id)actionWithReason:(NSString *)reason options:(unsigned int)options targetURL:(NSURL *)targetURL;
@end

@interface FBSSystemService : NSObject
+ (id)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

@interface IdentifierManager : NSObject
+ (instancetype)sharedManager;
- (BOOL)isApplicationEnabled:(NSString *)bundleID;
- (NSDictionary *)getApplicationInfo:(NSString *)bundleID;
- (void)regenerateAllEnabledIdentifiers;
- (void)resetCanvasNoise;
@end

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(id)identifier;
@property(readonly) NSString *bundleExecutable;
@end

@interface NetworkManager : NSObject
+ (void)saveLocalIPAddress:(NSString *)localIP;
@end

@interface ProfileManager ()

@property (nonatomic, strong) NSMutableArray<Profile *> *mutableProfiles;
@property (nonatomic, strong) Profile *mutableCurrentProfile;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSString *profilesDirectory;

@end

@implementation Profile

@synthesize profileId = _profileId;

- (instancetype)initWithName:(NSString *)name iconName:(NSString *)iconName {
    self = [super init];
    if (self) {
        // UUID is no longer used, but will be set by ProfileManager via setter
        _profileId = [[NSUUID UUID] UUIDString];
        _name = name;
        _iconName = iconName;
        _createdAt = [NSDate date];
        _lastUsed = [NSDate date];
        _settings = @{};
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name shortDescription:(NSString *)shortDescription iconName:(NSString *)iconName {
    self = [super init];
    if (self) {
        // UUID is no longer used, but will be set by ProfileManager via setter
        _profileId = [[NSUUID UUID] UUIDString];
        _name = name;
        _shortDescription = shortDescription;
        _iconName = iconName;
        _createdAt = [NSDate date];
        _lastUsed = [NSDate date];
        _settings = @{};
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _profileId = dictionary[@"profileId"];
        _name = dictionary[@"name"];
        _shortDescription = dictionary[@"shortDescription"];
        _iconName = dictionary[@"iconName"];
        _createdAt = dictionary[@"createdAt"];
        _lastUsed = dictionary[@"lastUsed"];
        _settings = dictionary[@"settings"] ?: @{};
        
        // If timestamps are missing, set them to current time
        NSDate *now = [NSDate date];
        if (!_createdAt) {
            NSLog(@"[WeaponX] Setting missing createdAt timestamp for profile: %@", _name);
            _createdAt = now;
        }
        if (!_lastUsed) {
            NSLog(@"[WeaponX] Setting missing lastUsed timestamp for profile: %@", _name);
            _lastUsed = now;
        }
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"profileId": self.profileId,
        @"name": self.name,
        @"iconName": self.iconName,
        @"createdAt": self.createdAt,
        @"lastUsed": self.lastUsed,
        @"settings": self.settings
    }];
    
    if (self.shortDescription) {
        dict[@"shortDescription"] = self.shortDescription;
    }
    
    return dict;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.profileId forKey:@"profileId"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.shortDescription forKey:@"shortDescription"];
    [coder encodeObject:self.iconName forKey:@"iconName"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
    [coder encodeObject:self.lastUsed forKey:@"lastUsed"];
    [coder encodeObject:self.settings forKey:@"settings"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _profileId = [coder decodeObjectOfClass:[NSString class] forKey:@"profileId"];
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _shortDescription = [coder decodeObjectOfClass:[NSString class] forKey:@"shortDescription"];
        _iconName = [coder decodeObjectOfClass:[NSString class] forKey:@"iconName"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        _lastUsed = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastUsed"];
        _settings = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"settings"];
        
        // If timestamps are missing, set them to current time
        if (!_createdAt) {
            NSLog(@"[WeaponX] Setting missing createdAt timestamp for profile: %@", _name);
            _createdAt = [NSDate date];
        }
        if (!_lastUsed) {
            NSLog(@"[WeaponX] Setting missing lastUsed timestamp for profile: %@", _name);
            _lastUsed = [NSDate date];
        }
        
        // Ensure settings exists
        if (!_settings) {
            _settings = @{};
        }
    }
    return self;
}

@end

@implementation ProfileManager

+ (instancetype)sharedManager {
    static ProfileManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[ProfileManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableProfiles = [NSMutableArray array];
        _fileManager = [NSFileManager defaultManager];
        
        // Use the specified jailbreak directory structure
        _profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        
        NSLog(@"[WeaponX] 📁 Using profiles directory: %@", _profilesDirectory);
        
        // Create main WeaponX directory if it doesn't exist
        NSString *weaponXDirectory = @"/var/jb/var/mobile/Library/WeaponX";
        [self createDirectoryIfNeeded:weaponXDirectory];
        
        // Create profiles directory if it doesn't exist
        [self createDirectoryIfNeeded:_profilesDirectory];
        
        // Check if current_profile_info.plist exists, create with profile "0" if not
        NSString *centralInfoPath = [_profilesDirectory stringByAppendingPathComponent:@"current_profile_info.plist"];
        BOOL centralInfoExists = [_fileManager fileExistsAtPath:centralInfoPath];
        
        // Check if profile "0" directory exists
        NSString *profileZeroPath = [_profilesDirectory stringByAppendingPathComponent:@"0"];
        BOOL profileZeroExists = [_fileManager fileExistsAtPath:profileZeroPath isDirectory:NULL];
        
        // If current_profile_info.plist doesn't exist or profile "0" doesn't exist, we need to create them
        if (!centralInfoExists || !profileZeroExists) {
            NSLog(@"[WeaponX] ⚠️ No current profile info or profile '0' found, creating...");
            // We'll create profile "0" immediately rather than waiting for loadProfiles completion
            [self createProfileZeroImmediately];
            
            // Create current_profile_info.plist pointing to profile "0"
            NSDate *now = [NSDate date];
            NSDictionary *profileInfo = @{
                @"ProfileId": @"0",
                @"ProfileName": @"Default",
                @"Description": @"Default Profile",
                @"LastSelected": now
            };
            [profileInfo writeToFile:centralInfoPath atomically:YES];
            [_fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:centralInfoPath error:nil];
            
            // Also write to active_profile_info.plist as a backup/legacy support
            NSString *activeInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
            [profileInfo writeToFile:activeInfoPath atomically:YES];
            [_fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:activeInfoPath error:nil];
            
            NSLog(@"[WeaponX] ✅ Created current_profile_info.plist with profile '0'");
        }
        
        // Load profiles
        [self loadProfilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
            if (!success) {
                NSLog(@"[WeaponX] ❌ Failed to load profiles: %@", error);
            }
            
            // Double-check if no profiles exist after loading (in case createProfileZeroImmediately wasn't sufficient)
            if (self.mutableProfiles.count == 0) {
                NSLog(@"[WeaponX] 📝 No profiles found after initialization, creating profile '0'");
                [self createProfileZero];
            }
        }];
    }
    return self;
}

- (void)createDirectoryIfNeeded:(NSString *)directory {
    if (![_fileManager fileExistsAtPath:directory]) {
        NSError *error = nil;
        NSDictionary *attributes = @{
            NSFilePosixPermissions: @0755,
            NSFileOwnerAccountName: @"mobile",
            NSFileGroupOwnerAccountName: @"mobile"
        };
        
        [_fileManager createDirectoryAtPath:directory
               withIntermediateDirectories:YES
                                attributes:attributes
                                     error:&error];
        if (error) {
            NSLog(@"[WeaponX] ❌ Failed to create directory %@: %@", directory, error);
        } else {
            // Set permissions using NSFileManager
            [_fileManager setAttributes:@{NSFilePosixPermissions: @0755}
                         ofItemAtPath:directory
                              error:&error];
            if (error) {
                NSLog(@"[WeaponX] ⚠️ Failed to set directory permissions: %@", error);
            }
            NSLog(@"[WeaponX] ✅ Created directory: %@", directory);
        }
    }
}

#pragma mark - Public Properties

- (NSArray<Profile *> *)profiles {
    return [self.mutableProfiles copy];
}

- (Profile *)currentProfile {
    // If we already have a current profile set, return it
    if (self.mutableCurrentProfile) {
        return self.mutableCurrentProfile;
    }
    
    // Try to load from central store
    Profile *storedProfile = [self loadCurrentProfileInfoFromCentralStore];
    if (storedProfile) {
        // Update our current profile property
        self.mutableCurrentProfile = storedProfile;
        return storedProfile;
    }
    
    // Fallback: return the first profile in the array if available
    if (self.mutableProfiles.count > 0) {
        self.mutableCurrentProfile = self.mutableProfiles[0];
        // Update the central store with this profile
        [self updateCurrentProfileInfoWithProfile:self.mutableCurrentProfile];
        return self.mutableCurrentProfile;
    }
    
    return nil;
}

#pragma mark - Public Methods

- (void)createProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSLog(@"[WeaponX] 📝 Creating new profile: %@", profile.name);
    
    // Validate profile name
    if (!profile.name || profile.name.length == 0) {
        NSError *error = [NSError errorWithDomain:@"WeaponXProfileError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Profile name cannot be empty"}];
        if (completion) completion(NO, error);
        return;
    }
    
    // Check for duplicate names
    for (Profile *existingProfile in self.mutableProfiles) {
        if ([existingProfile.name isEqualToString:profile.name]) {
            NSError *error = [NSError errorWithDomain:@"WeaponXProfileError" code:2 userInfo:@{NSLocalizedDescriptionKey: @"A profile with this name already exists"}];
            if (completion) completion(NO, error);
            return;
        }
    }
    
    // Generate a sequential profile ID instead of using UUID
    NSString *profileID = [self generateProfileID];
    
    // Set the generated ID
    // We need to use setValue:forKey: because profileId is readonly
    [profile setValue:profileID forKey:@"profileId"];
    
    // Set creation and last used dates with precise timestamps
    NSDate *now = [NSDate date];
    profile.createdAt = now;
    profile.lastUsed = now;
    
    // Create profile directory
    NSString *profileDir = [self.profilesDirectory stringByAppendingPathComponent:profile.profileId];
    [self createDirectoryIfNeeded:profileDir];
    
    // Set the creation and modification dates explicitly on the directory
    NSDictionary *attributes = @{
        NSFileCreationDate: now,
        NSFileModificationDate: now
    };
    
    NSError *attributesError = nil;
    BOOL attributesSuccess = [self.fileManager setAttributes:attributes ofItemAtPath:profileDir error:&attributesError];
    
    if (!attributesSuccess) {
        NSLog(@"[WeaponX] ⚠️ Failed to set profile directory attributes: %@", attributesError);
    }
    
    // Create identity directory for device IDs
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    [self createDirectoryIfNeeded:identityDir];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:identityDir error:nil];
    
    // Create appdata.plist
    NSString *appDataInfoPath = [profileDir stringByAppendingPathComponent:@"appdata.plist"];
    NSDictionary *appDataInfoDict = @{
        @"ProfileName": profile.name,
        @"ProfileID": profile.profileId,
        @"ShortDescription": profile.shortDescription ?: [NSString stringWithFormat:@"Profile ID: %@", profile.profileId],
        @"Creation": profile.createdAt ?: [NSDate date],
        @"LastUsed": profile.lastUsed ?: [NSDate date]
    };
    [appDataInfoDict writeToFile:appDataInfoPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:appDataInfoPath error:nil];
    
    // Create identifiers.plist
    NSString *identifiersPath = [profileDir stringByAppendingPathComponent:@"identifiers.plist"];
    NSDictionary *identifiersDict = @{
        @"DisplayName": profile.name,
        @"Description": profile.shortDescription ?: [NSString stringWithFormat:@"Profile ID: %@", profile.profileId],
        @"Identifier": profile.profileId
    };
    [identifiersDict writeToFile:identifiersPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:identifiersPath error:nil];
    
    // Create scoped-apps.plist
    NSString *scopedAppsPath = [profileDir stringByAppendingPathComponent:@"scoped-apps.plist"];
    NSDictionary *scopedAppsDict = @{
        @"ProfileName": profile.name,
        @"ProfileDescription": profile.shortDescription ?: [NSString stringWithFormat:@"Profile ID: %@", profile.profileId],
        @"Apps": @[]
    };
    [scopedAppsDict writeToFile:scopedAppsPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:scopedAppsPath error:nil];
    
    // Add profile to array
    [self.mutableProfiles addObject:profile];
    
    // Terminate all enabled scoped apps before setting as current profile
    [self terminateEnabledScopedApps];
    
    // Set as current profile
    self.mutableCurrentProfile = profile;
    
    // Update central store with new profile
    [self updateCurrentProfileInfoWithProfile:profile];
    
    // Randomize app versions for the new profile
    [self randomizeAppVersionsForProfile:profile.profileId];
    
    // Generate identifiers for the new profile
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 1. Generate WiFi information using WiFiManager
        SEL sharedManagerSel = NSSelectorFromString(@"sharedManager");
        Class wifiManagerClass = NSClassFromString(@"WiFiManager");
        
        if (wifiManagerClass && [wifiManagerClass respondsToSelector:sharedManagerSel]) {
            // Use NSInvocation to safely call the method
            NSMethodSignature *signature = [wifiManagerClass methodSignatureForSelector:sharedManagerSel];
            if (signature) {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setTarget:wifiManagerClass];
                [invocation setSelector:sharedManagerSel];
                [invocation invoke];
                
                // Get the result
                id __unsafe_unretained wifiManager;
                [invocation getReturnValue:&wifiManager];
                
                if (wifiManager) {
                    SEL generateWiFiInfoSel = NSSelectorFromString(@"generateWiFiInfo");
                    if ([wifiManager respondsToSelector:generateWiFiInfoSel]) {
                        NSLog(@"[WeaponX] 📶 Generating WiFi info for profile: %@", profile.name);
                        
                        // Use NSInvocation to safely call the method
                        NSMethodSignature *genSig = [wifiManager methodSignatureForSelector:generateWiFiInfoSel];
                        NSInvocation *genInvocation = [NSInvocation invocationWithMethodSignature:genSig];
                        [genInvocation setTarget:wifiManager];
                        [genInvocation setSelector:generateWiFiInfoSel];
                        [genInvocation invoke];
                    }
                }
            }
        }
        
        // 2. Generate local IP and carrier info based on connection type
        NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        NSInteger connectionType = [securitySettings integerForKey:@"networkConnectionType"];
        
        // Path to profile identity directory
        NSString *identityDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@/identity", profile.profileId];
        
        // Check if directory exists, create if not
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:identityDir]) {
            [fileManager createDirectoryAtPath:identityDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        // Generate carrier info if in cellular (2) or auto (0) mode
        if (connectionType == 0 || connectionType == 2) {
            NSString *countryCode = [securitySettings stringForKey:@"networkISOCountryCode"] ?: @"us";
            
            // Get proper carrier info from NetworkManager using NSInvocation
            Class networkManagerClass = NSClassFromString(@"NetworkManager");
            SEL randomCarrierSel = NSSelectorFromString(@"getRandomCarrierForCountry:");
            
            if ([networkManagerClass respondsToSelector:randomCarrierSel]) {
                // Use NSInvocation to safely call the class method
                NSMethodSignature *signature = [networkManagerClass methodSignatureForSelector:randomCarrierSel];
                if (signature) {
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setTarget:networkManagerClass];
                    [invocation setSelector:randomCarrierSel];
                    [invocation setArgument:&countryCode atIndex:2]; // Arguments start at index 2 (0:self, 1:_cmd)
                    [invocation invoke];
                    
                    // Get the return value
                    NSDictionary * __unsafe_unretained carrierInfo;
                    [invocation getReturnValue:&carrierInfo];
                    
                    if (carrierInfo) {
                    // Create carrier_details.plist
                    NSDictionary *carrierDict = @{
                        @"carrierName": carrierInfo[@"name"] ?: @"",
                        @"mcc": carrierInfo[@"mcc"] ?: @"",
                        @"mnc": carrierInfo[@"mnc"] ?: @"",
                        @"lastUpdated": [NSDate date]
                    };
                    
                    NSString *carrierPath = [identityDir stringByAppendingPathComponent:@"carrier_details.plist"];
                    [carrierDict writeToFile:carrierPath atomically:YES];
                    
                    // Also update the network_settings.plist
                    NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
                    NSMutableDictionary *networkDict = [NSMutableDictionary dictionaryWithContentsOfFile:networkPath] ?: 
                                                    [NSMutableDictionary dictionary];
                    networkDict[@"carrierName"] = carrierInfo[@"name"];
                    networkDict[@"mcc"] = carrierInfo[@"mcc"];
                    networkDict[@"mnc"] = carrierInfo[@"mnc"];
                    networkDict[@"lastUpdated"] = [NSDate date];
                    [networkDict writeToFile:networkPath atomically:YES];
                    
                    // Also update the device_ids.plist
                    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                    NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: 
                                                    [NSMutableDictionary dictionary];
                    deviceIds[@"CarrierName"] = carrierInfo[@"name"];
                    deviceIds[@"CarrierMCC"] = carrierInfo[@"mcc"];
                    deviceIds[@"CarrierMNC"] = carrierInfo[@"mnc"];
                    [deviceIds writeToFile:deviceIdsPath atomically:YES];
                    
                    NSLog(@"[WeaponX] 📱 Generated carrier info for profile %@: %@ (%@-%@)", 
                        profile.name, carrierInfo[@"name"], carrierInfo[@"mcc"], carrierInfo[@"mnc"]);
                }
                }
            }
        }
        
        // Generate local IP if in WiFi (1), auto (0), or cellular (2) mode
        if (connectionType == 0 || connectionType == 1 || connectionType == 2) {
            // Generate local IP using NSInvocation
            Class networkManagerClass = NSClassFromString(@"NetworkManager");
            SEL spoofedIPSel = NSSelectorFromString(@"generateSpoofedLocalIPAddressFromCurrent");
            if ([networkManagerClass respondsToSelector:spoofedIPSel]) {
                NSMethodSignature *signature = [networkManagerClass methodSignatureForSelector:spoofedIPSel];
                if (signature) {
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setTarget:networkManagerClass];
                    [invocation setSelector:spoofedIPSel];
                    [invocation invoke];
                    NSString * __unsafe_unretained localIP;
                    [invocation getReturnValue:&localIP];
                // Save to network_settings.plist
                NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
                    NSMutableDictionary *networkDict = [NSMutableDictionary dictionaryWithContentsOfFile:networkPath] ?: [NSMutableDictionary dictionary];
                networkDict[@"localIPAddress"] = localIP;
                // Also update the device_ids.plist
                NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
                NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: [NSMutableDictionary dictionary];
                deviceIds[@"LocalIPAddress"] = localIP;
                [deviceIds writeToFile:deviceIdsPath atomically:YES];
                    NSLog(@"[WeaponX] 🌐 Generated spoofed local IP for profile %@: %@", profile.name, localIP);
                    // --- FIX: Also save IPv6 using NetworkManager logic ---
                    [NetworkManager saveLocalIPAddress:localIP];
                }
                }
        }
        
        // 3. Get the IdentifierManager for other identifiers
        Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
        if (identifierManagerClass) {
            id identifierManager = [identifierManagerClass sharedManager];
            if (identifierManager && [identifierManager respondsToSelector:@selector(regenerateAllEnabledIdentifiers)]) {
                NSLog(@"[WeaponX] 🔄 Generating identifiers for new profile: %@", profile.name);
                [identifierManager regenerateAllEnabledIdentifiers];
            }
        }
    });
    
    // Save to disk
    [self saveProfilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"[WeaponX] ✅ Profile created successfully: %@ (created at: %@)", profile.name, profile.createdAt);
            // Reset canvas fingerprint noise for new profile
            Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
            if (identifierManagerClass) {
                id manager = [identifierManagerClass sharedManager];
                if ([manager respondsToSelector:@selector(resetCanvasNoise)]) {
                    [manager resetCanvasNoise];
                    NSLog(@"[WeaponX] 🎨 Canvas fingerprint noise reset after profile creation");
                }
            }
            // Post notification that profile has changed - UI components should refresh
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.profileChanged" object:nil];
            });
        } else {
            NSLog(@"[WeaponX] ❌ Failed to save profile: %@", error);
        }
        if (completion) completion(success, error);
    }];
}

- (void)updateProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSLog(@"[WeaponX] 🔄 Updating profile: %@", profile.name);
    
    // Find the profile to update
    NSUInteger index = [self.mutableProfiles indexOfObjectPassingTest:^BOOL(Profile *obj, NSUInteger idx, BOOL *stop) {
        return [obj.profileId isEqualToString:profile.profileId];
    }];
    
    if (index == NSNotFound) {
        NSError *error = [NSError errorWithDomain:@"WeaponXProfileError" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Profile not found"}];
        if (completion) completion(NO, error);
        return;
    }
    
    // Get the profile directory
    NSString *profileDir = [self.profilesDirectory stringByAppendingPathComponent:profile.profileId];
    NSString *appDataDir = [profileDir stringByAppendingPathComponent:@"appdata"];
    
    // Make sure appdata directory exists
    [self createDirectoryIfNeeded:appDataDir];
    
    // Update Info.plist in profile directory
    NSString *infoPath = [profileDir stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *infoDict = @{
        @"Name": profile.name,
        @"ProfileId": profile.profileId,
        @"Description": profile.shortDescription ?: [NSString stringWithFormat:@"Profile ID: %@", profile.profileId],
        @"CreatedAt": profile.createdAt ?: [NSDate date],
        @"LastUsed": profile.lastUsed ?: [NSDate date]
    };
    [infoDict writeToFile:infoPath atomically:YES];
    
    // Update Info.plist in appdata directory
    NSString *appDataInfoPath = [appDataDir stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *appDataInfoDict = @{
        @"ProfileName": profile.name,
        @"ProfileID": profile.profileId,
        @"ShortDescription": profile.shortDescription ?: [NSString stringWithFormat:@"Profile ID: %@", profile.profileId],
        @"Creation": profile.createdAt ?: [NSDate date],
        @"LastUsed": profile.lastUsed ?: [NSDate date]
    };
    [appDataInfoDict writeToFile:appDataInfoPath atomically:YES];
    
    // Update identifiers.plist
    NSString *identifiersPath = [profileDir stringByAppendingPathComponent:@"identifiers.plist"];
    NSDictionary *identifiersDict = @{
        @"DisplayName": profile.name,
        @"Description": profile.shortDescription ?: [NSString stringWithFormat:@"Profile ID: %@", profile.profileId],
        @"Identifier": profile.profileId
    };
    [identifiersDict writeToFile:identifiersPath atomically:YES];
    
    // Update scoped-apps.plist
    NSString *scopedAppsPath = [profileDir stringByAppendingPathComponent:@"scoped-apps.plist"];
    
    // Try to preserve existing contents if the file exists
    NSMutableDictionary *scopedAppsDict;
    if ([self.fileManager fileExistsAtPath:scopedAppsPath]) {
        scopedAppsDict = [NSMutableDictionary dictionaryWithContentsOfFile:scopedAppsPath];
    } else {
        scopedAppsDict = [NSMutableDictionary dictionary];
    }
    
    // Update only the profile info fields
    [scopedAppsDict setObject:profile.name forKey:@"ProfileName"];
    [scopedAppsDict setObject:(profile.shortDescription ?: [NSString stringWithFormat:@"Profile ID: %@", profile.profileId]) forKey:@"ProfileDescription"];
    if (![scopedAppsDict objectForKey:@"Apps"]) {
        [scopedAppsDict setObject:@[] forKey:@"Apps"];
    }
    
    [scopedAppsDict writeToFile:scopedAppsPath atomically:YES];
    
    NSLog(@"[WeaponX] Updated profile information files in: %@", profileDir);
    
    // Update the profile
    self.mutableProfiles[index] = profile;
    
    // If this is the current profile, update it
    if ([self.mutableCurrentProfile.profileId isEqualToString:profile.profileId]) {
        self.mutableCurrentProfile = profile;
    }
    
    // Save to disk
    [self saveProfilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"[WeaponX] ✅ Profile updated successfully: %@", profile.name);
            
            // Post notification that profile has changed - UI components should refresh
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.profileChanged" object:nil];
            });
        } else {
            NSLog(@"[WeaponX] ❌ Failed to save profile: %@", error);
        }
        if (completion) completion(success, error);
    }];
}

- (void)deleteProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSLog(@"[WeaponX] 🗑️ Deleting profile: %@", profile.name);
    
    // Don't allow deleting the last profile
    if (self.mutableProfiles.count <= 1) {
        NSError *error = [NSError errorWithDomain:@"WeaponXProfileError" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Cannot delete the last profile"}];
        if (completion) completion(NO, error);
        return;
    }
    
    // Remove profile directory
    NSString *profileDir = [self.profilesDirectory stringByAppendingPathComponent:profile.profileId];
    if ([self.fileManager fileExistsAtPath:profileDir]) {
        NSError *error = nil;
        [self.fileManager removeItemAtPath:profileDir error:&error];
        if (error) {
            NSLog(@"[WeaponX] ⚠️ Failed to remove profile directory: %@", error);
        }
    }
    
    // Remove from array
    [self.mutableProfiles removeObject:profile];
    
    // If this was the current profile, switch to another one
    if ([self.mutableCurrentProfile.profileId isEqualToString:profile.profileId]) {
        self.mutableCurrentProfile = self.mutableProfiles.firstObject;
    }
    
    // Save to disk
    [self saveProfilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"[WeaponX] ✅ Profile deleted successfully: %@", profile.name);
            
            // Post notification that profile has changed - UI components should refresh
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.profileChanged" object:nil];
            });
        } else {
            NSLog(@"[WeaponX] ❌ Failed to save profiles: %@", error);
        }
        if (completion) completion(success, error);
    }];
}

- (void)terminateEnabledScopedApps {
    NSLog(@"[WeaponX] 🔄 Terminating enabled scoped apps for profile switch");
    
    // Get the BottomButtons instance directly
    id bottomButtons = [NSClassFromString(@"BottomButtons") sharedInstance];
    if (!bottomButtons) {
        NSLog(@"[WeaponX] ⚠️ Could not get BottomButtons instance for app termination");
        return;
    }
    
    // Since the killEnabledApps method in BottomButtons works correctly,
    // directly invoke it to kill all enabled apps
    SEL killEnabledAppsSel = NSSelectorFromString(@"killEnabledApps");
    if ([bottomButtons respondsToSelector:killEnabledAppsSel]) {
        NSLog(@"[WeaponX] 🔪 Directly calling BottomButtons.killEnabledApps to terminate enabled apps");
        
        // Use NSInvocation to avoid ARC issues with performSelector
        NSMethodSignature *signature = [bottomButtons methodSignatureForSelector:killEnabledAppsSel];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:bottomButtons];
        [invocation setSelector:killEnabledAppsSel];
        [invocation invoke];
        
        NSLog(@"[WeaponX] ✅ Successfully called killEnabledApps method");
    } else {
        NSLog(@"[WeaponX] ❌ BottomButtons does not respond to killEnabledApps");
        
        // Fallback to using killAppViaExecutableName directly with all enabled apps
        id identifierManager = [NSClassFromString(@"IdentifierManager") sharedManager];
        if (!identifierManager) {
            NSLog(@"[WeaponX] ⚠️ Could not get IdentifierManager instance for app termination");
            return;
        }
        
        // Get all apps and filter by enabled
        NSDictionary *allApps = [identifierManager getApplicationInfo:nil];
        if (!allApps) {
            NSLog(@"[WeaponX] ⚠️ Could not retrieve app information");
            return;
        }
        
        NSLog(@"[WeaponX] Found %lu total apps to check", (unsigned long)allApps.count);
        
        // Create a safelist of apps that should NEVER be terminated
        NSArray *safeApps = @[
            @"com.hydra.projectx",      // The tweak itself
            @"com.apple.springboard",   // SpringBoard
            @"com.apple.backboardd",    // BackBoard
            @"com.apple.preferences",   // Settings
            @"com.apple.mobilephone",   // Phone
            @"com.apple.MobileSMS"      // Messages
        ];
        
        int terminatedCount = 0;
        for (NSString *bundleID in allApps) {
            // Skip apps in the safelist
            if ([safeApps containsObject:bundleID]) {
                NSLog(@"[WeaponX] 🛡️ Skipping termination of protected app: %@", bundleID);
                continue;
            }
            
            // Check if app is enabled
            if ([identifierManager isApplicationEnabled:bundleID]) {
                NSLog(@"[WeaponX] 🔄 Terminating enabled app: %@", bundleID);
                
                // Use killAppViaExecutableName method directly
                [bottomButtons killAppViaExecutableName:bundleID];
                terminatedCount++;
            }
        }
        
        NSLog(@"[WeaponX] ✅ Terminated %d enabled apps using fallback method", terminatedCount);
    }
}

- (void)switchToProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSLog(@"[WeaponX] 🔄 Switching to profile: %@", profile.name);
    
    // Don't switch to the same profile
    if ([self.mutableCurrentProfile.profileId isEqualToString:profile.profileId]) {
        NSLog(@"[WeaponX] Already using profile: %@, updating last used time", profile.name);
        
        // Even if not switching, update the last used time
        NSDate *now = [NSDate date];
        profile.lastUsed = now;
        
        // Update the central profile info store
        [self updateCurrentProfileInfoWithProfile:profile];
        
        // Save to disk
        [self saveProfilesWithCompletion:completion];
        return;
    }
    
    // Terminate all enabled scoped apps before switching profiles
    [self terminateEnabledScopedApps];
    
    // Update last used time
    NSDate *now = [NSDate date];
    profile.lastUsed = now;
    
    // Set as current profile
    self.mutableCurrentProfile = profile;
    
    // Update the central profile info store
    [self updateCurrentProfileInfoWithProfile:profile];
    
    // Update file modification time directly
    NSString *profileDirectory = [NSString stringWithFormat:@"%@/%@", self.profilesDirectory, profile.profileId];
    NSError *touchError = nil;
    
    // Use setAttributes to directly update the modification date
    NSDictionary *attributes = @{NSFileModificationDate: now};
    BOOL touchSuccess = [self.fileManager setAttributes:attributes ofItemAtPath:profileDirectory error:&touchError];
    
    if (!touchSuccess) {
        NSLog(@"[WeaponX] ⚠️ Failed to update profile directory modification time: %@", touchError);
    }
    
    // Randomize app versions for the new profile
    [self randomizeAppVersionsForProfile:profile.profileId];
    
    // Save to disk
    [self saveProfilesWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            // Post notification that profile has changed - UI components should refresh
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.profileChanged" object:nil];
            });
        }
        if (completion) completion(success, error);
    }];
}

// New method to randomize app versions for a profile
- (void)randomizeAppVersionsForProfile:(NSString *)profileId {
    NSLog(@"[WeaponX] 🎲 Randomizing app versions for profile: %@", profileId);
    
    // Try rootless path first for multi-version data
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    if (![self.fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        
        // Fallback to standard path if needed
        if (![self.fileManager fileExistsAtPath:prefsPath]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        }
    }
    
    // Load multi-version data
    NSDictionary *multiVersionDict = [NSDictionary dictionaryWithContentsOfFile:multiVersionFile];
    NSDictionary *multiVersions = multiVersionDict[@"MultiVersions"];
    
    if (!multiVersions || multiVersions.count == 0) {
        NSLog(@"[WeaponX] ℹ️ No multi-version data found, skipping randomization");
        return;
    }
    
    // Load scoped apps info to get app names
    NSDictionary *scopedAppsInfo = [self loadScopedAppsInfo];
    
    // Create app_versions directory in the profile directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *appVersionsDir = [profileDir stringByAppendingPathComponent:@"app_versions"];
    
    if (![self.fileManager fileExistsAtPath:appVersionsDir]) {
        NSError *dirError = nil;
        NSDictionary *attributes = @{NSFilePosixPermissions: @0755, NSFileOwnerAccountName: @"mobile"};
        if (![self.fileManager createDirectoryAtPath:appVersionsDir 
                           withIntermediateDirectories:YES 
                                            attributes:attributes 
                                                 error:&dirError]) {
            NSLog(@"[WeaponX] ❌ Failed to create app_versions directory: %@", dirError);
            return;
        }
    }
    
    // Process each app with multiple versions
    NSInteger randomizedCount = 0;
    for (NSString *bundleID in multiVersions) {
        NSArray *versions = multiVersions[bundleID];
        if (versions.count < 2) {
            // Skip apps with only one or zero versions
            continue; 
        }
        
        // Randomly select a version
        NSInteger randomIndex = arc4random_uniform((uint32_t)versions.count);
        NSDictionary *selectedVersion = versions[randomIndex];
        
        NSString *appName = scopedAppsInfo[bundleID][@"name"] ?: bundleID;
        NSString *spoofedVersion = selectedVersion[@"version"];
        NSString *spoofedBuild = selectedVersion[@"build"];
        NSString *displayName = selectedVersion[@"displayName"] ?: [NSString stringWithFormat:@"v%@", spoofedVersion];
        
        NSLog(@"[WeaponX] 🎲 Randomly selected version for %@: %@ (index %ld)", appName, displayName, (long)randomIndex);
        
        // Create and save the app version file
        NSString *safeFilename = [bundleID stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        safeFilename = [safeFilename stringByAppendingString:@"_version.plist"];
        NSString *appVersionFile = [appVersionsDir stringByAppendingPathComponent:safeFilename];
        
        NSMutableDictionary *appVersionData = [NSMutableDictionary dictionary];
        appVersionData[@"bundleID"] = bundleID;
        appVersionData[@"name"] = appName;
        appVersionData[@"spoofedVersion"] = spoofedVersion;
        if (spoofedBuild) {
            appVersionData[@"spoofedBuild"] = spoofedBuild;
        }
        appVersionData[@"activeVersionIndex"] = @(randomIndex);
        appVersionData[@"spoofingEnabled"] = @YES;  // Enable spoofing by default for randomized versions
        appVersionData[@"lastUpdated"] = [NSDate date];
        
        BOOL success = [appVersionData writeToFile:appVersionFile atomically:YES];
        if (success) {
            randomizedCount++;
        } else {
            NSLog(@"[WeaponX] ❌ Failed to save randomized version for %@", appName);
        }
    }
    
    NSLog(@"[WeaponX] ✅ Randomized versions for %ld apps", (long)randomizedCount);
}

- (NSDictionary *)loadScopedAppsInfo {
    // Try to load scoped apps info from global scope file
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    if (![self.fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        
        // Fallback to standard path if needed
        if (![self.fileManager fileExistsAtPath:prefsPath]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        }
    }
    
    // Load scoped apps
    NSDictionary *scopedAppsDict = [NSDictionary dictionaryWithContentsOfFile:scopedAppsFile];
    return scopedAppsDict[@"ScopedApps"] ?: @{};
}

- (void)loadProfilesWithCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSLog(@"[WeaponX] 📂 Loading profiles from disk");
    
    // Get profiles file path
    NSString *profilesPath = [self.profilesDirectory stringByAppendingPathComponent:@"profiles.plist"];
    
    // Check if profiles file exists
    if ([self.fileManager fileExistsAtPath:profilesPath]) {
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:profilesPath];
        
        // Try to decode profiles
        if (data) {
            // Use modern, non-deprecated API
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
            if (error) {
                NSLog(@"[WeaponX] ❌ Error initializing unarchiver: %@", error);
                [self createDefaultProfile];
                if (completion) completion(NO, error);
                return;
            }
            
            unarchiver.requiresSecureCoding = YES;
            NSArray *profilesArray = [unarchiver decodeObjectOfClass:[NSArray class] forKey:NSKeyedArchiveRootObjectKey];
            
            if (!profilesArray) {
                NSLog(@"[WeaponX] ⚠️ Failed to decode profiles, creating default profile");
                [self createDefaultProfile];
                if (completion) completion(NO, [NSError errorWithDomain:@"WeaponXProfileError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode profiles"}]);
                return;
            }
            
            // Get user defaults for current profile ID
            NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
            NSString *currentProfileID = [sharedDefaults objectForKey:@"CurrentProfileID"];
            
            // Update profiles array
            self.mutableProfiles = [profilesArray mutableCopy];
            
            // Find profile with the saved current profile ID, or use last used as fallback
            if (currentProfileID && currentProfileID.length > 0) {
                // Try to find profile with the saved ID
                Profile *currentProfile = nil;
                for (Profile *profile in self.mutableProfiles) {
                    if ([profile.profileId isEqualToString:currentProfileID]) {
                        currentProfile = profile;
                        break;
                    }
                }
                
                // If found, set as current
                if (currentProfile) {
                    self.mutableCurrentProfile = currentProfile;
                    NSLog(@"[WeaponX] ✅ Restored current profile from shared defaults: %@", currentProfile.name);
                } else {
                    // If not found, use last used
                    [self setCurrentProfileToLastUsed];
                }
            } else {
                // No saved ID, use last used
                [self setCurrentProfileToLastUsed];
            }
            
            NSLog(@"[WeaponX] ✅ Loaded %lu profiles", (unsigned long)self.mutableProfiles.count);
            if (completion) completion(YES, nil);
            return;
        }
    }
    
    // If we reached here, either the file doesn't exist or failed to read
    NSLog(@"[WeaponX] ⚠️ No profiles file found, creating default profile");
    [self createDefaultProfile];
    if (completion) completion(YES, nil);
}

- (void)setCurrentProfileToLastUsed {
    // Find the most recently used profile
    Profile *lastUsedProfile = [self.mutableProfiles sortedArrayUsingComparator:^NSComparisonResult(Profile *obj1, Profile *obj2) {
        return [obj2.lastUsed compare:obj1.lastUsed];
    }].firstObject;
    
    if (lastUsedProfile) {
        self.mutableCurrentProfile = lastUsedProfile;
        NSLog(@"[WeaponX] ✅ Set current profile to last used: %@", lastUsedProfile.name);
        
        // Update shared defaults with the current profile ID
        NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
        [sharedDefaults setObject:lastUsedProfile.profileId forKey:@"CurrentProfileID"];
        [sharedDefaults synchronize];
    } else if (self.mutableProfiles.count > 0) {
        // Fallback to first profile if no last used found
        self.mutableCurrentProfile = self.mutableProfiles.firstObject;
        NSLog(@"[WeaponX] ✅ Set current profile to first available: %@", self.mutableCurrentProfile.name);
        
        // Update shared defaults with the current profile ID
        NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
        [sharedDefaults setObject:self.mutableCurrentProfile.profileId forKey:@"CurrentProfileID"];
        [sharedDefaults synchronize];
    }
}

#pragma mark - Private Methods

// Generates profile IDs in the sequence: 1, 2, ... 99, 100, ..., 999, A01, A02, ... A99, B01, ...
- (NSString *)generateProfileID {
    @try {
        // Get all existing profile IDs directly from the file system
        NSMutableArray *existingIDs = [NSMutableArray array];
        
        // Get profiles directory path
        NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        
        // Get file manager
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // Check if directory exists
        if (![fileManager fileExistsAtPath:profilesDirectory]) {
            NSLog(@"[WeaponX] ⚠️ Profiles directory does not exist for ID generation!");
            return @"1";
        }
        
        // First try to get all profile IDs from profiles.plist
        NSString *profilesPath = [profilesDirectory stringByAppendingPathComponent:@"profiles.plist"];
        if ([fileManager fileExistsAtPath:profilesPath]) {
            NSLog(@"[WeaponX] Found profiles.plist at: %@ for ID generation", profilesPath);
            NSData *data = [NSData dataWithContentsOfFile:profilesPath];
            if (data) {
                NSError *error = nil;
                
                // Use the modern non-deprecated API for iOS 15+
                NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
                if (error) {
                    NSLog(@"[WeaponX] ❌ Failed to initialize unarchiver for ID generation: %@", error);
                } else {
                    unarchiver.requiresSecureCoding = YES;
                    NSArray *loadedProfiles = [unarchiver decodeObjectOfClass:[NSArray class] forKey:NSKeyedArchiveRootObjectKey];
                    
                    if (loadedProfiles) {
                        for (Profile *profile in loadedProfiles) {
                            if (profile.profileId) {
                                [existingIDs addObject:profile.profileId];
                            }
                        }
                        NSLog(@"[WeaponX] ✅ Successfully loaded %lu profile IDs from plist", (unsigned long)existingIDs.count);
                    }
                }
            }
        }
        
        // If loading from plist failed or we got no IDs, scan directory for profile folders
        if (existingIDs.count == 0) {
            NSError *error = nil;
            NSArray *contents = [fileManager contentsOfDirectoryAtPath:profilesDirectory error:&error];
            
            if (error) {
                NSLog(@"[WeaponX] ❌ Failed to read profiles directory for ID generation: %@", error);
                return @"1";
            }
            
            for (NSString *item in contents) {
                NSString *itemPath = [profilesDirectory stringByAppendingPathComponent:item];
                BOOL isDirectory = NO;
                
                // Skip non-directories and the profiles.plist file
                if (![fileManager fileExistsAtPath:itemPath isDirectory:&isDirectory] || !isDirectory || [item isEqualToString:@"profiles.plist"]) {
                    continue;
                }
                
                // Add profile ID to the list
                [existingIDs addObject:item];
            }
            
            NSLog(@"[WeaponX] ✅ Found %lu profile IDs from directory scan", (unsigned long)existingIDs.count);
        }
        
        // If no existing IDs, start with "1"
        if (existingIDs.count == 0) {
            return @"1";
        }
        
        // Find the highest numeric ID (for IDs that are just numbers)
        NSMutableArray *numericIDs = [NSMutableArray array];
        NSMutableArray *alphaIDs = [NSMutableArray array];
        
        for (NSString *profileId in existingIDs) {
            if (!profileId) continue; // Skip nil values
            
            if ([self isNumericString:profileId]) {
                [numericIDs addObject:profileId];
            } else if (profileId.length > 0) { // Make sure the string is not empty
                [alphaIDs addObject:profileId];
            }
        }
        
        // If we have numeric IDs and haven't reached 999 yet, increment the highest one
        if (numericIDs.count > 0) {
            NSArray *sortedNumericIDs = [numericIDs sortedArrayUsingComparator:^NSComparisonResult(NSString *id1, NSString *id2) {
                return [@([id1 intValue]) compare:@([id2 intValue])];
            }];
            
            NSString *highestID = [sortedNumericIDs lastObject];
            if (!highestID) return @"1"; // Safeguard
            
            int highestValue = [highestID intValue];
            
            // If we haven't reached 999 yet, increment
            if (highestValue < 999) {
                return [NSString stringWithFormat:@"%d", highestValue + 1];
            }
            // Otherwise we'll move to alpha IDs below
        }
        
        // If we've reached 999 or have no numeric IDs but have alpha IDs, find the highest alpha ID
        if (alphaIDs.count > 0) {
            // Sort alphabetically
            NSArray *sortedAlphaIDs = [alphaIDs sortedArrayUsingSelector:@selector(compare:)];
            NSString *highestID = [sortedAlphaIDs lastObject];
            if (!highestID || highestID.length < 3) return @"A01"; // Safeguard
            
            // Parse letter and number parts from the ID (e.g., "A01" -> "A" and 01)
            unichar letter = [highestID characterAtIndex:0];
            
            // Extract the number part safely
            NSString *numberPart = [highestID substringFromIndex:1];
            if (![self isNumericString:numberPart]) return @"A01"; // If not a valid format, reset
            
            int number = [numberPart intValue];
            
            // Increment (max 2 digits to keep total length at 3 chars)
            if (number < 99) {
                number++;
                return [NSString stringWithFormat:@"%c%02d", letter, number];
            } else {
                // Move to next letter and reset number to 01
                unichar nextLetter = letter + 1;
                return [NSString stringWithFormat:@"%c01", nextLetter];
            }
        }
        
        // If we've reached 999 and have no alpha IDs yet, start with "A01"
        return @"A01";
    }
    @catch (NSException *exception) {
        NSLog(@"[WeaponX] ❌ Exception in generateProfileID: %@", exception);
        return @"1"; // Safe fallback
    }
}

// Helper method to check if a string is numeric
- (BOOL)isNumericString:(NSString *)string {
    if (!string) return NO;
    NSCharacterSet *nonNumericSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [string rangeOfCharacterFromSet:nonNumericSet].location == NSNotFound;
}

- (void)createDefaultProfile {
    Profile *defaultProfile = [[Profile alloc] initWithName:@"Default" iconName:@"default_profile"];
    
    // Use our ID generation system
    NSString *profileID = [self generateProfileID];
    [defaultProfile setValue:profileID forKey:@"profileId"];
    
    [self.mutableProfiles addObject:defaultProfile];
    self.mutableCurrentProfile = defaultProfile;
    [self saveProfilesWithCompletion:nil];
}

- (void)saveProfilesWithCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    NSLog(@"[WeaponX] 💾 Saving profiles to disk");
    
    // Ensure profiles directory exists
    [self createDirectoryIfNeeded:self.profilesDirectory];
    
    // Get the profiles file path
    NSString *profilesPath = [self.profilesDirectory stringByAppendingPathComponent:@"profiles.plist"];
    
    // Encode profiles
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.mutableProfiles requiringSecureCoding:YES error:&error];
    if (error) {
        NSLog(@"[WeaponX] ❌ Failed to encode profiles: %@", error);
        if (completion) completion(NO, error);
        return;
    }
    
    // Try to write with standard API first
    BOOL success = [data writeToFile:profilesPath options:NSDataWritingAtomic error:&error];
    
    if (!success) {
        // If standard API fails, try writing to temp and then moving
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"temp_profiles.plist"];
        success = [data writeToFile:tempPath options:NSDataWritingAtomic error:&error];
        
        if (success) {
            // Remove existing file if it exists
            if ([self.fileManager fileExistsAtPath:profilesPath]) {
                [self.fileManager removeItemAtPath:profilesPath error:nil];
            }
            
            // Move temp file to final location
            success = [self.fileManager moveItemAtPath:tempPath toPath:profilesPath error:&error];
            if (success) {
                [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644}
                                 ofItemAtPath:profilesPath
                                      error:nil];
            }
        }
    } else {
        // Set permissions if standard write succeeded
        [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644}
                         ofItemAtPath:profilesPath
                              error:nil];
    }
    
    if (success) {
        NSLog(@"[WeaponX] ✅ Saved %lu profiles to %@", (unsigned long)self.mutableProfiles.count, profilesPath);
    } else {
        NSLog(@"[WeaponX] ❌ Failed to write profiles file: %@", error);
    }
    
    if (completion) completion(success, error);
}

- (void)saveSettings:(NSDictionary *)settings {
    NSString *settingsPath = [@"/var/jb/var/mobile/Library/WeaponX" stringByAppendingPathComponent:@"settings.plist"];
    
    BOOL success = [settings writeToFile:settingsPath atomically:YES];
    if (success) {
        [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644}
                         ofItemAtPath:settingsPath
                              error:nil];
        NSLog(@"[WeaponX] ✅ Saved settings to %@", settingsPath);
    } else {
        NSLog(@"[WeaponX] ❌ Failed to write settings file");
    }
}

#pragma mark - Convenience Methods

- (void)removeProfile:(NSString *)profileName {
    // Find profile with matching name
    Profile *profileToDelete = nil;
    for (Profile *profile in self.mutableProfiles) {
        if ([profile.name isEqualToString:profileName]) {
            profileToDelete = profile;
            break;
        }
    }
    
    if (profileToDelete) {
        [self deleteProfile:profileToDelete completion:^(BOOL success, NSError * _Nullable error) {
            if (!success) {
                NSLog(@"[WeaponX] ❌ Failed to delete profile %@: %@", profileName, error);
            }
        }];
    }
}

- (void)renameProfile:(NSString *)oldName to:(NSString *)newName {
    // Find profile with matching name
    Profile *profileToRename = nil;
    for (Profile *profile in self.mutableProfiles) {
        if ([profile.name isEqualToString:oldName]) {
            profileToRename = profile;
            break;
        }
    }
    
    if (profileToRename) {
        profileToRename.name = newName;
        [self updateProfile:profileToRename completion:^(BOOL success, NSError * _Nullable error) {
            if (!success) {
                NSLog(@"[WeaponX] ❌ Failed to rename profile from %@ to %@: %@", oldName, newName, error);
            }
        }];
    }
}

- (void)addProfile:(NSString *)profileName {
    Profile *newProfile = [[Profile alloc] initWithName:profileName iconName:@"default_profile"];
    [self createProfile:newProfile completion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            NSLog(@"[WeaponX] ❌ Failed to add profile %@: %@", profileName, error);
        }
    }];
}

- (void)addProfileWithName:(NSString *)profileName shortDescription:(NSString *)shortDescription {
    Profile *newProfile = [[Profile alloc] initWithName:profileName shortDescription:shortDescription iconName:@"default_profile"];
    [self createProfile:newProfile completion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            NSLog(@"[WeaponX] ❌ Failed to add profile %@: %@", profileName, error);
        }
    }];
}

#pragma mark - Current Profile Central Management

- (NSString *)centralProfileInfoPath {
    return [self.profilesDirectory stringByAppendingPathComponent:@"current_profile_info.plist"];
}

- (BOOL)saveCentralProfileInfo:(NSDictionary *)infoDict {
    NSString *infoPath = [self centralProfileInfoPath];
    
    BOOL success = [infoDict writeToFile:infoPath atomically:YES];
    if (success) {
        NSLog(@"[WeaponX] Successfully saved current profile info to central store: %@", infoPath);
    } else {
        NSLog(@"[WeaponX] Failed to save current profile info to central store: %@", infoPath);
    }
    
    return success;
}

- (NSDictionary *)loadCentralProfileInfo {
    NSString *infoPath = [self centralProfileInfoPath];
    
    // Check if the file exists
    if (![self.fileManager fileExistsAtPath:infoPath]) {
        NSLog(@"[WeaponX] Central profile info file doesn't exist: %@", infoPath);
        return nil;
    }
    
    // Load the dictionary
    NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (!infoDict) {
        NSLog(@"[WeaponX] Failed to load central profile info from: %@", infoPath);
        return nil;
    }
    
    NSLog(@"[WeaponX] Successfully loaded central profile info: %@", infoDict);
    return infoDict;
}

- (void)updateCurrentProfileInfoWithProfile:(Profile *)profile {
    if (!profile) {
        NSLog(@"[WeaponX] Cannot update central profile info with nil profile");
        return;
    }
    
    // Create info dictionary with all relevant profile information
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
    infoDict[@"ProfileId"] = profile.profileId;
    infoDict[@"ProfileName"] = profile.name;
    infoDict[@"Description"] = profile.shortDescription ?: @"";
    infoDict[@"LastSelected"] = [NSDate date];
    
    // Save to central store
    [self saveCentralProfileInfo:infoDict];
    
    // Also update the shared NSUserDefaults for compatibility with existing code
    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
    [sharedDefaults setObject:profile.profileId forKey:@"CurrentProfileID"];
    [sharedDefaults synchronize];
    
    NSLog(@"[WeaponX] Updated central profile info for profile: %@ (ID: %@)", profile.name, profile.profileId);
}

- (Profile *)loadCurrentProfileInfoFromCentralStore {
    // Load info from central store
    NSDictionary *infoDict = [self loadCentralProfileInfo];
    
    if (!infoDict || !infoDict[@"ProfileId"]) {
        NSLog(@"[WeaponX] No valid current profile info found in central store");
        return nil;
    }
    
    // Try to find the profile in our profiles array
    NSString *profileId = infoDict[@"ProfileId"];
    
    for (Profile *profile in self.mutableProfiles) {
        if ([profile.profileId isEqualToString:profileId]) {
            NSLog(@"[WeaponX] Found current profile from central store: %@ (ID: %@)", profile.name, profile.profileId);
            return profile;
        }
    }
    
    // If we couldn't find the profile in our array, create a temporary one
    // This could happen if the profiles haven't been fully loaded yet
    NSLog(@"[WeaponX] Profile from central store not found in profiles array, creating temporary");
    
    Profile *tempProfile = [[Profile alloc] initWithName:infoDict[@"ProfileName"] 
                                        shortDescription:infoDict[@"Description"] 
                                               iconName:@"default_profile"];
    [tempProfile setValue:profileId forKey:@"profileId"];
    
    return tempProfile;
}

// New method to create profile "0"
- (void)createProfileZero {
    // Create profile directory
    NSString *profileDir = [self.profilesDirectory stringByAppendingPathComponent:@"0"];
    [self createDirectoryIfNeeded:profileDir];
    
    // Create profile object
    Profile *defaultProfile = [[Profile alloc] initWithName:@"Default" iconName:@"default_profile"];
    [defaultProfile setValue:@"0" forKey:@"profileId"];
    
    NSDate *now = [NSDate date];
    defaultProfile.createdAt = now;
    defaultProfile.lastUsed = now;
    
    // Create identity directory for device IDs
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    [self createDirectoryIfNeeded:identityDir];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:identityDir error:nil];
    
    // Create appdata.plist
    NSString *appDataInfoPath = [profileDir stringByAppendingPathComponent:@"appdata.plist"];
    NSDictionary *appDataInfoDict = @{
        @"ProfileName": defaultProfile.name,
        @"ProfileID": @"0",
        @"ShortDescription": @"Default Profile",
        @"Creation": now,
        @"LastUsed": now
    };
    [appDataInfoDict writeToFile:appDataInfoPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:appDataInfoPath error:nil];
    
    // Create identifiers.plist
    NSString *identifiersPath = [profileDir stringByAppendingPathComponent:@"identifiers.plist"];
    NSDictionary *identifiersDict = @{
        @"DisplayName": defaultProfile.name,
        @"Description": @"Default Profile",
        @"Identifier": @"0"
    };
    [identifiersDict writeToFile:identifiersPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:identifiersPath error:nil];
    
    // Create scoped-apps.plist
    NSString *scopedAppsPath = [profileDir stringByAppendingPathComponent:@"scoped-apps.plist"];
    NSDictionary *scopedAppsDict = @{
        @"ProfileName": defaultProfile.name,
        @"ProfileDescription": @"Default Profile",
        @"Apps": @[]
    };
    [scopedAppsDict writeToFile:scopedAppsPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:scopedAppsPath error:nil];
    
    // Add to profiles array
    [self.mutableProfiles addObject:defaultProfile];
    self.mutableCurrentProfile = defaultProfile;
    
    // Save to profiles.plist
    [self saveProfilesWithCompletion:nil];
    
    // Update central profile info
    [self updateCurrentProfileInfoWithProfile:defaultProfile];
    
    // Also write directly to active_profile_info.plist as a backup
    NSString *activeInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
    NSDictionary *activeInfo = @{
        @"ProfileId": @"0",
        @"ProfileName": defaultProfile.name,
        @"LastSelected": now
    };
    [activeInfo writeToFile:activeInfoPath atomically:YES];
    
    NSLog(@"[WeaponX] ✅ Created and set profile '0' as the default profile");
}

// Immediate profile creation without waiting for loadProfiles
- (void)createProfileZeroImmediately {
    // Create profile directory
    NSString *profileDir = [self.profilesDirectory stringByAppendingPathComponent:@"0"];
    [self createDirectoryIfNeeded:profileDir];
    
    // Create identity directory for device IDs
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    [self createDirectoryIfNeeded:identityDir];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:identityDir error:nil];
    
    // Create profile object for internal use
    Profile *defaultProfile = [[Profile alloc] initWithName:@"Default" iconName:@"default_profile"];
    [defaultProfile setValue:@"0" forKey:@"profileId"];
    
    NSDate *now = [NSDate date];
    defaultProfile.createdAt = now;
    defaultProfile.lastUsed = now;
    
    // Create appdata.plist
    NSString *appDataInfoPath = [profileDir stringByAppendingPathComponent:@"appdata.plist"];
    NSDictionary *appDataInfoDict = @{
        @"ProfileName": @"Default",
        @"ProfileID": @"0",
        @"ShortDescription": @"Default Profile",
        @"Creation": now,
        @"LastUsed": now
    };
    [appDataInfoDict writeToFile:appDataInfoPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:appDataInfoPath error:nil];
    
    // Create identifiers.plist
    NSString *identifiersPath = [profileDir stringByAppendingPathComponent:@"identifiers.plist"];
    NSDictionary *identifiersDict = @{
        @"DisplayName": @"Default",
        @"Description": @"Default Profile",
        @"Identifier": @"0"
    };
    [identifiersDict writeToFile:identifiersPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:identifiersPath error:nil];
    
    // Create scoped-apps.plist
    NSString *scopedAppsPath = [profileDir stringByAppendingPathComponent:@"scoped-apps.plist"];
    NSDictionary *scopedAppsDict = @{
        @"ProfileName": @"Default",
        @"ProfileDescription": @"Default Profile",
        @"Apps": @[]
    };
    [scopedAppsDict writeToFile:scopedAppsPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:scopedAppsPath error:nil];
    
    // Create device_ids.plist in identity directory for immediate identifier storage
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *emptyDeviceIds = @{};
    [emptyDeviceIds writeToFile:deviceIdsPath atomically:YES];
    [self.fileManager setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:deviceIdsPath error:nil];
    
    NSLog(@"[WeaponX] ✅ Immediately created profile '0' directory structure");
}

@end 