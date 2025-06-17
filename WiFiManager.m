#import "WiFiManager.h"
#import "ProfileManager.h"
#import "ProjectXLogging.h"
#import <Security/Security.h>

@interface WiFiManager ()
@property (nonatomic, strong) NSString *currentIdentifier;
@property (nonatomic, strong) NSMutableDictionary *wifiInfo;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSString *currentProfileId;
@property (nonatomic, weak) id profileChangeObserver;
@end

@implementation WiFiManager

+ (instancetype)sharedManager {
    static WiFiManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _wifiInfo = [NSMutableDictionary dictionary];
        _error = nil;
        
        // Load WiFi info for current profile
        [self loadWiFiInfoFromCurrentProfile];
        
        // Register for profile changes
        [self registerForProfileNotifications];
    }
    return self;
}

#pragma mark - Profile Integration

- (void)registerForProfileNotifications {
    // Register for profile change notifications
    self.profileChangeObserver = [[NSNotificationCenter defaultCenter] 
        addObserverForName:@"WeaponXProfileChanged"
        object:nil 
        queue:[NSOperationQueue mainQueue] 
        usingBlock:^(NSNotification *note) {
            // Reload WiFi info when profile changes
            NSString *newProfileId = note.userInfo[@"ProfileId"];
            if (newProfileId && ![newProfileId isEqualToString:self.currentProfileId]) {
                self.currentProfileId = newProfileId;
                [self loadWiFiInfoFromCurrentProfile];
                PXLog(@"[WiFiManager] Loaded WiFi info for new profile: %@", newProfileId);
            }
    }];
}

- (NSString *)getCurrentProfileID {
    // First try via ProfileManager
    id profileManager = NSClassFromString(@"ProfileManager");
    if (profileManager) {
        id sharedManager = [profileManager sharedManager];
        if ([sharedManager respondsToSelector:@selector(currentProfile)]) {
            id currentProfile = [sharedManager currentProfile];
            if (currentProfile && [currentProfile respondsToSelector:@selector(profileId)]) {
                NSString *profileId = [currentProfile profileId];
                if (profileId) {
                    return profileId;
                }
            }
        }
    }
    
    // Fallback to direct file read if ProfileManager isn't available
    NSString *currentProfileInfoPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *profileInfo = [NSDictionary dictionaryWithContentsOfFile:currentProfileInfoPath];
    
    if (profileInfo && profileInfo[@"ProfileId"]) {
        id profileIdValue = profileInfo[@"ProfileId"];
        NSString *profileId = nil;
        
        // Handle both NSNumber and NSString types properly
        if ([profileIdValue isKindOfClass:[NSNumber class]]) {
            profileId = [profileIdValue stringValue];
        } else if ([profileIdValue isKindOfClass:[NSString class]]) {
            profileId = profileIdValue;
        } else {
            profileId = [profileIdValue description];
        }
        
        PXLog(@"[WiFiManager] Got current profile ID from plist: %@", profileId);
        return profileId;
    }
    
    // If all else fails, use default
    return @"default";
}

- (void)loadWiFiInfoFromCurrentProfile {
    NSString *profileId = [self getCurrentProfileID];
    if (!profileId) {
        PXLog(@"[WiFiManager] No active profile, cannot load WiFi info");
        return;
    }
    
    self.currentProfileId = profileId;
    
    // Build path to WiFi info file in profile directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    NSString *wifiInfoPath = [identityDir stringByAppendingPathComponent:@"wifi_info.plist"];
    
    // Check if file exists
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:wifiInfoPath]) {
        PXLog(@"[WiFiManager] No saved WiFi info found for profile %@", profileId);
        return;
    }
    
    // Load the saved info
    NSMutableDictionary *savedInfo = [NSMutableDictionary dictionaryWithContentsOfFile:wifiInfoPath];
    if (savedInfo) {
        self.wifiInfo = savedInfo;
        PXLog(@"[WiFiManager] Loaded WiFi info from profile %@: SSID=%@, BSSID=%@", 
              profileId, savedInfo[@"ssid"], savedInfo[@"bssid"]);
    }
}

- (void)saveWiFiInfoToCurrentProfile {
    NSString *profileId = [self getCurrentProfileID];
    if (!profileId) {
        PXLog(@"[WiFiManager] No active profile, cannot save WiFi info");
        return;
    }
    
    self.currentProfileId = profileId;
    
    // Build path to WiFi info file in profile directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    NSString *wifiInfoPath = [identityDir stringByAppendingPathComponent:@"wifi_info.plist"];
    
    // Ensure directory exists
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:identityDir]) {
        [fileManager createDirectoryAtPath:identityDir 
              withIntermediateDirectories:YES 
                               attributes:nil 
                                    error:nil];
    }
    
    // Save to file
    [self.wifiInfo writeToFile:wifiInfoPath atomically:YES];
    
    // Also update the combined device_ids.plist to include WiFi info
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: 
                                     [NSMutableDictionary dictionary];
    deviceIds[@"SSID"] = self.wifiInfo[@"ssid"];
    deviceIds[@"BSSID"] = self.wifiInfo[@"bssid"];
    [deviceIds writeToFile:deviceIdsPath atomically:YES];
    
    PXLog(@"[WiFiManager] Saved WiFi info to profile %@: SSID=%@, BSSID=%@", 
          profileId, self.wifiInfo[@"ssid"], self.wifiInfo[@"bssid"]);
}

#pragma mark - Core Methods

- (NSDictionary *)generateWiFiInfo {
    self.error = nil;
    
    // Generate random US-style WiFi network information
    NSMutableDictionary *newWifiInfo = [NSMutableDictionary dictionary];

    // US ISP providers
    NSArray *usProviders = @[
        // Major national ISPs
        @"Xfinity", @"Spectrum", @"ATT", @"Verizon", @"CenturyLink", @"Cox", @"Frontier",
        @"Optimum", @"Suddenlink", @"WOW", @"Mediacom", @"Windstream", @"Sparklight",
        // Regional ISPs
        @"RCN", @"Grande", @"Wave", @"Armstrong", @"WideOpenWest", @"MetroNet", @"Ziply",
        @"Sonic", @"Earthlink", @"HughesNet", @"TDS", @"Consolidated", @"Fairpoint",
        // Cable providers
        @"Comcast", @"TimeWarner", @"Charter", @"BrightHouse", @"Cablevision", @"GCI",
        // Fiber/specialized providers
        @"GoogleFiber", @"FiOS", @"AT&T-Fiber", @"CenturyLink-Fiber", @"Webpass",
        // Mobile hotspot providers
        @"TMobile", @"Sprint", @"USCellular", @"Cricket", @"MetroPCS", @"Boost"
    ];
    
    // US WiFi suffixes and modifiers
    NSArray *usSuffixes = @[
        // Empty/standard
        @"", @"WiFi", @"WLAN", @"Net", @"Network", @"Internet",
        // Band identifiers
        @"-5G", @"-5GHz", @"-2G", @"-2.4", @"-2.4GHz", @"-6G", @"-6GHz", @"_5G", @"_2G",
        // Location/purpose
        @"-Home", @"-Office", @"-Guest", @"-IoT", @"-ExtWifi", @"-Mesh", @"-Basement", 
        @"-Upstairs", @"-Kitchen", @"-Backyard", @"-Patio", @"-Garage", @"-Private", 
        @"-Family", @"-Apartment", @"-Condo", @"-Suite", @"-Lobby",
        // Security identifiers
        @"_Secure", @"-Secure", @"-Protected", @"-WPA2", @"-WPA3", @"_EXT", @"-EXT",
        // Dynamic additions
        @"-MESH", @"-AP", @"-Hub", @"-NODE1", @"-POD", @"-REPEATER", @"-EXTENDER"
    ];
    
    // Router brand names popular in the US
    NSArray *routerBrands = @[
        @"NETGEAR", @"Linksys", @"TP-Link", @"ASUS", @"ORBI", @"Eero", @"Google-WiFi",
        @"Nest-WiFi", @"Nighthawk", @"Apple", @"Amazon", @"ARRIS", @"Motorola", @"Ubiquiti",
        @"AmpliFi", @"D-Link", @"Belkin", @"Buffalo", @"Cisco", @"EnGenius", @"Tenda"
    ];
    
    // Common US last names
    NSArray *commonLastNames = @[
        @"Smith", @"Johnson", @"Williams", @"Jones", @"Brown", @"Miller", @"Davis",
        @"Wilson", @"Anderson", @"Thomas", @"Taylor", @"Moore", @"White", @"Harris",
        @"Martin", @"Thompson", @"Garcia", @"Martinez", @"Robinson", @"Clark", @"Rodriguez",
        @"Lewis", @"Lee", @"Walker", @"Hall", @"Allen", @"Young", @"King", @"Wright",
        @"Scott", @"Green", @"Baker", @"Adams", @"Nelson", @"Hill", @"Ramirez", @"Campbell",
        @"Mitchell", @"Roberts", @"Carter", @"Phillips", @"Evans", @"Turner", @"Torres"
    ];
    
    // Creative network names popular in the US
    NSArray *creativeNames = @[
        @"HideYoKids", @"HideYoWiFi", @"ItHurtsWhenIP", @"PrettyFlyForAWiFi",
        @"WiFiAintGonnaBreadItself", @"ThePromisedLAN", @"WhyFi", @"WiFiDoYouLoveMe",
        @"LANDownUnder", @"TheLANBeforeTime", @"WuTangLAN", @"ThisLANIsMyLAN", 
        @"BillWiTheScienceFi", @"TellMyWiFiLoveHer", @"NachoWiFi", @"GetOffMyLAN", 
        @"TheInternetBox", @"Series-of-Tubes", @"FBI-Surveillance", @"NSA-Van", 
        @"Area51", @"DEA-Monitoring", @"CIA-Spy-Van", @"NoWiFiForYou", 
        @"Password123", @"NotTheWiFiYoureLookingFor", @"VirusInfectedWiFi",
        @"PayMeToConnect", @"ICanHearYouHavingSex", @"WifiSoFastUCantSeeThis", 
        @"YourNeighborHasABetterRouter", @"WinternetIsComing", @"TwoGirlsOneRouter",
        @"DropItLikeItsHotspot", @"99ProblemsButWiFiAintOne", @"ThePasswordIsPASSWORD",
        @"Mom-Click-Here-For-Internet", @"ShoutingInTernetConspiracyTheories", 
        @"AllYourBandwidthAreBelongToUs", @"NewEnglandClamRouter", @"RouterIHardlyKnowHer"
    ];
    
    // Generate random SSID using one of three methods
    NSString *ssid;
    int networkStyle = arc4random_uniform(100);
    
    if (networkStyle < 45) {
        // ISP style (45% chance)
        NSString *provider = usProviders[arc4random_uniform((uint32_t)usProviders.count)];
        NSString *suffix = usSuffixes[arc4random_uniform((uint32_t)usSuffixes.count)];
        
        if ([suffix length] > 0) {
            ssid = [NSString stringWithFormat:@"%@%@", provider, suffix];
        } else {
            ssid = provider;
        }
        
        // Sometimes add numbers for uniqueness
        if (arc4random_uniform(100) < 40) {
            ssid = [ssid stringByAppendingFormat:@"-%d", arc4random_uniform(999) + 1];
        }
    } 
    else if (networkStyle < 70) {
        // Router brand style (25% chance)
        NSString *brand = routerBrands[arc4random_uniform((uint32_t)routerBrands.count)];
        NSString *suffix = usSuffixes[arc4random_uniform((uint32_t)usSuffixes.count)];
        
        if ([suffix length] > 0) {
            ssid = [NSString stringWithFormat:@"%@%@", brand, suffix];
        } else {
            ssid = brand;
        }
        
        // More likely to add model numbers for router brands
        if (arc4random_uniform(100) < 70) {
            // Different formats for model numbers
            int format = arc4random_uniform(5);
            if (format == 0) {
                ssid = [ssid stringByAppendingFormat:@"_%d", arc4random_uniform(1000)];
            } else if (format == 1) {
                ssid = [ssid stringByAppendingFormat:@"-%c%d", 'A' + arc4random_uniform(26), arc4random_uniform(100)];
            } else if (format == 2) {
                ssid = [ssid stringByAppendingFormat:@"_%dGHZ", (arc4random_uniform(2) == 0) ? 2 : 5];
            } else if (format == 3) {
                ssid = [ssid stringByAppendingFormat:@"-AC%d", 1000 + arc4random_uniform(9000)];
            } else {
                ssid = [ssid stringByAppendingFormat:@"_%X%X%X", arc4random_uniform(16), arc4random_uniform(16), arc4random_uniform(16)];
            }
        }
    }
    else {
        // Personal style (30% chance)
        int personalType = arc4random_uniform(100);
        NSString *base;
        
        if (personalType < 50) {
            // Family/Last name (50% of personal)
            base = commonLastNames[arc4random_uniform((uint32_t)commonLastNames.count)];
            
            // Add common variations
            int variation = arc4random_uniform(7);
            if (variation == 0) {
                base = [base stringByAppendingString:@"-Home"];
            } else if (variation == 1) {
                base = [base stringByAppendingString:@"-WiFi"];
            } else if (variation == 2) {
                base = [base stringByAppendingString:@"-Net"];
            } else if (variation == 3) {
                base = [base stringByAppendingString:@"Family"];
            } else if (variation == 4) {
                base = [base stringByAppendingString:@"House"];
            } else if (variation == 5) {
                base = [NSString stringWithFormat:@"The%@s", base];
            }
            // Otherwise leave as just the name
        } else {
            // Creative name (50% of personal)
            base = creativeNames[arc4random_uniform((uint32_t)creativeNames.count)];
        }
        
        // Sometimes add numbers for uniqueness
        if (arc4random_uniform(100) < 40) {
            ssid = [base stringByAppendingFormat:@"%d", arc4random_uniform(999) + 1];
        } else {
            ssid = base;
        }
    }
    
    // Generate random but valid BSSID (MAC address)
    // Common US router manufacturers OUIs (first 3 bytes)
    NSArray *commonOUIs = @[
        // Cisco/Linksys (popular in US)
        @"00:18:F8", // Cisco-Linksys
        @"00:1D:7E", // Cisco-Linksys
        @"00:23:69", // Cisco-Linksys
        @"E4:95:6E", // Cisco
        @"58:6D:8F", // Cisco-Linksys
        @"C8:BE:19", // Cisco-Linksys
        
        // NETGEAR (very popular in US market)
        @"00:14:6C", // NETGEAR
        @"00:26:F2", // NETGEAR
        @"08:BD:43", // NETGEAR
        @"20:E5:2A", // NETGEAR
        @"28:C6:8E", // NETGEAR
        @"3C:37:86", // NETGEAR
        @"D8:6C:63", // NETGEAR
        
        // Arris/Motorola (common in US cable modems)
        @"00:1A:DE", // Arris
        @"00:26:36", // Arris
        @"E4:64:E9", // Arris
        @"00:01:E3", // Motorola
        @"00:24:37", // Motorola
        
        // Comcast/Xfinity (US-specific)
        @"00:11:AE", // Xfinity
        @"00:14:6C", // Xfinity
        @"E4:64:E9", // Xfinity
        @"F8:F1:B6", // Xfinity
        
        // Charter/Spectrum (US-specific)
        @"68:A4:0E", // Spectrum
        @"00:FC:8D", // Spectrum
        
        // Apple (popular in US homes)
        @"00:1C:B3", // Apple WiFi
        @"88:41:FC", // Apple AirPort
        @"AC:BC:32", // Apple
        
        // Google/Nest (US market)
        @"F4:F5:D8", // Google WiFi
        @"F8:8F:CA", // Google Nest
        
        // Amazon/Eero (US market)
        @"04:F0:21", // Eero
        @"F8:BB:BF", // Eero
        @"FC:65:DE", // Amazon
        
        // TP-Link (common in US budget market)
        @"0C:80:63", // TP-Link
        @"54:A7:03", // TP-Link
        @"F8:1A:67", // TP-Link
        
        // ASUS (popular in US gaming/high-end)
        @"00:0C:6E", // ASUS
        @"30:85:A9", // ASUS
        @"AC:9E:17", // ASUS
        
        // Ubiquiti (popular for prosumers in US)
        @"44:E9:DD", // Ubiquiti
        @"78:8A:20", // Ubiquiti
        @"FC:EC:DA", // Ubiquiti
        
        // Belkin (common US brand)
        @"08:86:3B", // Belkin
        @"14:91:82", // Belkin
        @"94:10:3E", // Belkin
        
        // D-Link (budget US market)
        @"00:26:5A", // D-Link
        @"C0:A0:BB", // D-Link
        
        // Cable modems/gateways used by US ISPs
        @"00:90:D0", // Thomson/RCA (Spectrum)
        @"7C:BF:B1", // ARRIS (Comcast)
        @"00:15:63", // CableMatrix (various US cable)
        @"00:22:10"  // Motorola Solutions (US cable)
    ];
    
    // Select appropriate OUI based on SSID when possible
    NSString *oui = nil;
    
    // Match SSID provider with appropriate manufacturer
    if ([ssid containsString:@"Apple"] || [ssid containsString:@"Airport"]) {
        int appleIdx = 26 + arc4random_uniform(3);
        oui = commonOUIs[appleIdx]; // Apple OUIs
    } 
    else if ([ssid containsString:@"Google"] || [ssid containsString:@"Nest"]) {
        int googleIdx = 29 + arc4random_uniform(2);
        oui = commonOUIs[googleIdx]; // Google OUIs
    }
    else if ([ssid containsString:@"Linksys"] || [ssid containsString:@"Cisco"]) {
        int ciscoIdx = arc4random_uniform(6);
        oui = commonOUIs[ciscoIdx]; // Cisco OUIs (indices 0-5)
    }
    else if ([ssid containsString:@"NETGEAR"] || [ssid containsString:@"Nighthawk"]) {
        int netgearIdx = 6 + arc4random_uniform(7);
        oui = commonOUIs[netgearIdx]; // NETGEAR OUIs (indices 6-12)
    }
    else if ([ssid containsString:@"Motorola"] || [ssid containsString:@"ARRIS"]) {
        int arrisIdx = 13 + arc4random_uniform(5);
        oui = commonOUIs[arrisIdx]; // Arris OUIs (indices 13-17)
    }
    else if ([ssid containsString:@"Xfinity"] || [ssid containsString:@"Comcast"]) {
        int xfinityIdx = 18 + arc4random_uniform(4);
        oui = commonOUIs[xfinityIdx]; // Xfinity OUIs (indices 18-21)
    }
    else if ([ssid containsString:@"Spectrum"] || [ssid containsString:@"Charter"]) {
        int spectrumIdx = 22 + arc4random_uniform(2);
        oui = commonOUIs[spectrumIdx]; // Spectrum OUIs (indices 22-23)
    }
    else if ([ssid containsString:@"Eero"] || [ssid containsString:@"Amazon"]) {
        int eeroIdx = 31 + arc4random_uniform(3);
        oui = commonOUIs[eeroIdx]; // Eero/Amazon OUIs (indices 31-33)
    }
    else if ([ssid containsString:@"TP-Link"] || [ssid containsString:@"TPLink"]) {
        int tplinkIdx = 34 + arc4random_uniform(3);
        oui = commonOUIs[tplinkIdx]; // TP-Link OUIs (indices 34-36)
    }
    else if ([ssid containsString:@"ASUS"]) {
        int asusIdx = 37 + arc4random_uniform(3);
        oui = commonOUIs[asusIdx]; // ASUS OUIs (indices 37-39)
    }
    else if ([ssid containsString:@"Ubiquiti"] || [ssid containsString:@"UBNT"] || [ssid containsString:@"AmpliFi"]) {
        int ubiquitiIdx = 40 + arc4random_uniform(3);
        oui = commonOUIs[ubiquitiIdx]; // Ubiquiti OUIs (indices 40-42)
    }
    else if ([ssid containsString:@"Belkin"]) {
        int belkinIdx = 43 + arc4random_uniform(3);
        oui = commonOUIs[belkinIdx]; // Belkin OUIs (indices 43-45)
    }
    else if ([ssid containsString:@"DLink"] || [ssid containsString:@"D-Link"]) {
        int dlinkIdx = 46 + arc4random_uniform(2);
        oui = commonOUIs[dlinkIdx]; // D-Link OUIs (indices 46-47)
    }
    // ISP-specific cases
    else if ([ssid containsString:@"ATT"] || [ssid containsString:@"AT&T"]) {
        // Use Arris or Cisco (common AT&T suppliers)
        oui = commonOUIs[arc4random_uniform(2) == 0 ? 2 : 14];
    }
    else if ([ssid containsString:@"Verizon"] || [ssid containsString:@"FiOS"]) {
        // Use Actiontec or Motorola (common Verizon suppliers)
        oui = commonOUIs[16 + arc4random_uniform(2)];
    }
    else if ([ssid containsString:@"Cox"]) {
        // Use ARRIS or Cisco (common Cox suppliers)
        oui = commonOUIs[arc4random_uniform(2) == 0 ? 4 : 15];
    }
    else {
        // For all other cases, choose a random OUI
        oui = commonOUIs[arc4random_uniform((uint32_t)commonOUIs.count)];
    }
    
    // Generate the random part of the MAC address
    NSString *bssid = [NSString stringWithFormat:@"%@:%02X:%02X:%02X", 
                       oui,
                       arc4random_uniform(256),
                       arc4random_uniform(256),
                       arc4random_uniform(256)];
    
    // Set network type (usually "Infrastructure" for home networks)
    NSString *networkType = @"Infrastructure";
    
    // Set WiFi standard (802.11ac or 802.11ax most common in US now)
    NSArray *standards = @[@"802.11ax", @"802.11ac", @"802.11n"];
    NSString *wifiStandard = standards[arc4random_uniform(3)]; // Equally likely among the three
    
    // Set auto-join status (usually YES for home networks)
    BOOL autoJoin = YES;
    
    // Set last connection time (typically within the last day)
    NSDate *lastConnectionTime = [NSDate dateWithTimeIntervalSinceNow:-1 * arc4random_uniform(86400)];
    
    // Store values
    newWifiInfo[@"ssid"] = ssid;
    newWifiInfo[@"bssid"] = bssid;
    newWifiInfo[@"networkType"] = networkType;
    newWifiInfo[@"wifiStandard"] = wifiStandard;
    newWifiInfo[@"autoJoin"] = @(autoJoin);
    newWifiInfo[@"lastConnectionTime"] = lastConnectionTime;
    
    // Update current info
    self.wifiInfo = newWifiInfo;
    
    // Save to current profile
    [self saveWiFiInfoToCurrentProfile];
    
    return [newWifiInfo copy];
}

- (NSDictionary *)currentWiFiInfo {
    // Always check the current profile ID first
    NSString *currentId = [self getCurrentProfileID];
    if (currentId && (self.currentProfileId == nil || ![self.currentProfileId isEqualToString:currentId])) {
        PXLog(@"[WiFiManager] Profile change detected (%@ → %@), reloading WiFi info", 
              self.currentProfileId ?: @"nil", currentId);
        self.currentProfileId = currentId;
        [self loadWiFiInfoFromCurrentProfile];
    }
    
    // If we don't have info, load from profile
    if (self.wifiInfo.count == 0) {
        [self loadWiFiInfoFromCurrentProfile];
    }
    
    // If still no info, generate new
    if (self.wifiInfo.count == 0) {
        return [self generateWiFiInfo];
    }
    
    PXLog(@"[WiFiManager] Returning WiFi info: SSID=%@, BSSID=%@", 
          self.wifiInfo[@"ssid"], self.wifiInfo[@"bssid"]);
    return [self.wifiInfo copy];
}

- (void)setCurrentWiFiInfo:(NSDictionary *)wifiInfo {
    if (!wifiInfo) return;
    
    // Validate required fields
    if (!wifiInfo[@"ssid"] || !wifiInfo[@"bssid"]) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                         code:3001 
                                     userInfo:@{NSLocalizedDescriptionKey: @"WiFi info must contain SSID and BSSID"}];
        return;
    }
    
    // Validate SSID and BSSID
    if (![self isValidSSID:wifiInfo[@"ssid"]] || ![self isValidBSSID:wifiInfo[@"bssid"]]) {
        return; // Error will be set by validation methods
    }
    
    // Copy values
    self.wifiInfo = [NSMutableDictionary dictionaryWithDictionary:wifiInfo];
    
    // Save to profile
    [self saveWiFiInfoToCurrentProfile];
}

#pragma mark - Accessors

- (NSString *)currentSSID {
    return self.wifiInfo[@"ssid"];
}

- (NSString *)currentBSSID {
    return self.wifiInfo[@"bssid"];
}

- (NSString *)currentNetworkType {
    return self.wifiInfo[@"networkType"] ?: @"Infrastructure";
}

- (NSString *)currentWiFiStandard {
    return self.wifiInfo[@"wifiStandard"] ?: @"802.11ac";
}

- (BOOL)currentAutoJoinStatus {
    return [self.wifiInfo[@"autoJoin"] boolValue];
}

- (NSDate *)lastConnectionTime {
    return self.wifiInfo[@"lastConnectionTime"] ?: [NSDate date];
}

#pragma mark - Validation

- (BOOL)isValidSSID:(NSString *)ssid {
    if (!ssid) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                         code:3002 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SSID cannot be nil"}];
        return NO;
    }
    
    // SSID must be 1-32 bytes
    NSData *ssidData = [ssid dataUsingEncoding:NSUTF8StringEncoding];
    if (ssidData.length < 1 || ssidData.length > 32) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                         code:3003 
                                     userInfo:@{NSLocalizedDescriptionKey: @"SSID must be 1-32 bytes"}];
        return NO;
    }
    
    return YES;
}

- (BOOL)isValidBSSID:(NSString *)bssid {
    if (!bssid) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                         code:3004 
                                     userInfo:@{NSLocalizedDescriptionKey: @"BSSID cannot be nil"}];
        return NO;
    }
    
    // BSSID must match MAC address format XX:XX:XX:XX:XX:XX
    NSString *pattern = @"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:0
                                                                           error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:bssid
                                               options:0
                                                 range:NSMakeRange(0, bssid.length)];
    
    if (matches != 1) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                         code:3005 
                                     userInfo:@{NSLocalizedDescriptionKey: @"BSSID must be in format XX:XX:XX:XX:XX:XX"}];
        return NO;
    }
    
    return YES;
}

#pragma mark - Error Handling

- (NSError *)lastError {
    return self.error;
}

#pragma mark - Cleanup

- (void)dealloc {
    if (self.profileChangeObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.profileChangeObserver];
    }
}

@end 