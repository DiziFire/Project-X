#import "LocationSpoofingManager.h"
#import "ProjectXLogging.h"

// Constants
static NSString *ROOT_PREFIX = @"/var/jb"; // For rootless jailbreak
static NSString *PLIST_NAME = @"com.weaponx.gpsspoofing.plist";
static NSString *GLOBAL_SCOPE_PLIST = @"com.hydra.projectx.global_scope.plist";

// File-scope variables for caching
NSMutableDictionary *appSpoofingCache = nil;
NSDate *lastCacheRefreshTime = nil;  // Shared between shouldSpoofApp and refreshAppSpoofingCache methods 
                                     // to fix "set but not used" compiler warning

@interface LocationSpoofingManager ()
@property (nonatomic, assign) BOOL spoofingEnabled;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
@property (nonatomic, strong) NSDictionary *cachedPinnedLocation; // Add persistent cache for pinned location
@property (nonatomic, assign) NSTimeInterval lastPinnedLocationReadTime; // Track when we last read from file
@property (nonatomic, assign) BOOL spoofingToggleState; // Explicit toggle state
@property (nonatomic, readwrite, assign) TransportationMode transportationMode;
@property (nonatomic, readwrite, assign) double maxMovementSpeed;
@property (nonatomic, readwrite, assign) double jitterAmount;
@property (nonatomic, readwrite, assign) double accuracyValue;
@property (nonatomic, readwrite, assign) BOOL jitterEnabled;
@property (nonatomic, readwrite, assign) double lastReportedSpeed;
@property (nonatomic, readwrite, assign) double lastReportedCourse;

// Path-based movement properties
@property (nonatomic, readwrite, assign) BOOL isMovingAlongPath;

@property (nonatomic, strong) NSTimer *pathMovementTimer;
@property (nonatomic, strong) NSArray<CLLocation *> *pathLocations;
@property (nonatomic, copy) void (^pathCompletionHandler)(BOOL);
@property (nonatomic, assign) double pathSpeed;

@end

@implementation LocationSpoofingManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static LocationSpoofingManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize properties with defaults
        _spoofingEnabled = NO;
        _spoofingToggleState = NO;
        _latitude = 0.0;
        _longitude = 0.0;
        _cachedPinnedLocation = nil;
        _lastPinnedLocationReadTime = 0;
        self.cachedScopedApps = [NSMutableDictionary dictionary];
        
        // Initialize advanced spoofing properties with defaults
        _transportationMode = TransportationModeStationary;
        _maxMovementSpeed = 0.2; // m/s (very slight drift for stationary)
        _jitterAmount = 1.0;     // Minimal jitter
        _accuracyValue = 10.0;   // Default accuracy (meters)
        _jitterEnabled = YES;    // Enable jitter by default
        _lastReportedSpeed = 0.0;
        _lastReportedCourse = 0.0;
        _positionVariationsEnabled = YES; // Enable position variations by default for realistic movement
        
        PXLog(@"[WeaponX] LocationSpoofingManager initialized with position variations %@", 
              _positionVariationsEnabled ? @"ENABLED" : @"DISABLED");
        
        @try {
            // First load the toggle state - this controls whether spoofing is enabled
            _spoofingToggleState = [self loadSpoofingToggleState];
            
            // If toggle is ON, try to get the pinned location
            if (_spoofingToggleState) {
                // Directly read the pinned location without using loadSpoofingLocation
                NSDictionary *pinnedLocation = [self directReadPinnedLocationFromFile];
                
                if (pinnedLocation) {
                    // We have a valid pinned location
                    _latitude = [pinnedLocation[@"latitude"] doubleValue];
                    _longitude = [pinnedLocation[@"longitude"] doubleValue];
                    _spoofingEnabled = YES; // Enable actual spoofing since we have both toggle ON and valid location
                    
                    PXLog(@"[WeaponX] LocationSpoofingManager initialized with toggle ON and pinned location at %.6f, %.6f", 
                          _latitude, _longitude);
                } else {
                    // Toggle is ON but no pinned location found
                    _spoofingEnabled = NO; // Can't spoof without coordinates
                    PXLog(@"[WeaponX] LocationSpoofingManager: Toggle is ON but no pinned location found");
                }
            } else {
                // Toggle is OFF, disable spoofing regardless of pinned location
                _spoofingEnabled = NO;
                PXLog(@"[WeaponX] LocationSpoofingManager: Toggle is OFF, spoofing disabled");
                
                // Still check if we have a pinned location for informational purposes
                NSDictionary *pinnedLocation = [self directReadPinnedLocationFromFile];
                if (pinnedLocation) {
                    _latitude = [pinnedLocation[@"latitude"] doubleValue];
                    _longitude = [pinnedLocation[@"longitude"] doubleValue];
                    PXLog(@"[WeaponX] LocationSpoofingManager: Pinned location exists but will not be used (toggle OFF)");
                }
            }
            
            // Load scoped apps exactly once
            [self loadScopedApps];
            
        } @catch (NSException *exception) {
            // Reset to default values if initialization fails
            _spoofingEnabled = NO;
            _spoofingToggleState = NO;
            _latitude = 0.0;
            _longitude = 0.0;
            _cachedPinnedLocation = nil;
            PXLog(@"[WeaponX] LocationSpoofingManager initialization exception: %@", exception);
        }
    }
    return self;
}

#pragma mark - Core Functionality

- (BOOL)isSpoofingEnabled {
    @synchronized(self) {
        // First check if the toggle is ON
        if (!self.spoofingToggleState) {
            // Toggle is OFF, spoofing is disabled regardless of pinned location
            self.spoofingEnabled = NO;
            return NO;
        }
        
        // Toggle is ON, now check if we have valid coordinates to use
        if (!self.spoofingEnabled) {
            NSDictionary *pinnedLocation = [self directReadPinnedLocationFromFile];
            if (pinnedLocation) {
                // We found a pinned location, enable spoofing and set coordinates
                self.latitude = [pinnedLocation[@"latitude"] doubleValue];
                self.longitude = [pinnedLocation[@"longitude"] doubleValue];
                self.spoofingEnabled = YES;
                
                PXLog(@"[WeaponX] LocationSpoofingManager: Enabling spoofing with pinned location: %.6f, %.6f",
                      self.latitude, self.longitude);
            } else {
                // Toggle is ON but no pinned location, can't spoof
                self.spoofingEnabled = NO;
                PXLog(@"[WeaponX] LocationSpoofingManager: Cannot enable spoofing - toggle is ON but no pinned location found");
            }
        }
        
        return self.spoofingEnabled;
    }
}

- (void)enableSpoofingWithLatitude:(double)latitude longitude:(double)longitude {
    // Validate coordinates
    if (!CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(latitude, longitude))) {
        PXLog(@"[WeaponX] Cannot enable GPS spoofing with invalid coordinates: %.6f, %.6f", latitude, longitude);
        return;
    }
    
    @synchronized(self) {
        // Always enable the toggle when setting coordinates
        self.spoofingToggleState = YES;
        self.spoofingEnabled = YES;
        self.latitude = latitude;
        self.longitude = longitude;
        
        // Update cached location in memory
        self.cachedPinnedLocation = @{
            @"latitude": @(latitude),
            @"longitude": @(longitude)
        };
        self.lastPinnedLocationReadTime = [[NSDate date] timeIntervalSince1970];
    }
    
    // Save location as PinnedLocation
    @try {
        // Save both the location and toggle state
        [self saveSpoofingLocation:@{
            @"latitude": @(latitude),
            @"longitude": @(longitude)
        }];
        
        // Make sure toggle is saved as enabled
        [self saveSpoofingToggleState:YES];
        
        PXLog(@"[WeaponX] GPS Spoofing enabled with toggle ON at %.6f, %.6f", latitude, longitude);
        
        // Post notification for time zone spoofing to update based on location
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.weaponx.locationSpoofingChanged" 
                                                            object:nil 
                                                          userInfo:@{
                                                              @"latitude": @(latitude),
                                                              @"longitude": @(longitude),
                                                              @"enabled": @YES
                                                          }];
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception while enabling GPS spoofing: %@", exception);
    }
}

- (void)disableSpoofing {
    @synchronized(self) {
        // Disable actual spoofing but keep toggle state as is
        self.spoofingEnabled = NO;
        self.latitude = 0.0;
        self.longitude = 0.0;
        self.cachedPinnedLocation = nil;
        self.lastPinnedLocationReadTime = 0;
    }
    
    @try {
        NSString *plistPath = [self spoofingPlistPath];
        
        // Load existing settings
        NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
        if (settings) {
            // Remove PinnedLocation but keep toggle state
            [settings removeObjectForKey:@"PinnedLocation"];
            
            // Write to file
            BOOL success = [settings writeToFile:plistPath atomically:YES];
            if (!success) {
                PXLog(@"[WeaponX] Failed to remove pinned location");
            }
        }
        
        PXLog(@"[WeaponX] Pinned location removed, toggle state remains %@", 
              self.spoofingToggleState ? @"ON" : @"OFF");
              
        // Post notification for time zone spoofing to know location spoofing was disabled
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.weaponx.locationSpoofingChanged" 
                                                            object:nil 
                                                          userInfo:@{
                                                              @"enabled": @NO
                                                          }];
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception while removing pinned location: %@", exception);
    }
}

#pragma mark - Settings Management

- (NSString *)spoofingPlistPath {
    @try {
        // Try rootless path first
        NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:[@"/var/mobile/Library/Preferences/" stringByAppendingString:PLIST_NAME]];
        
        // Check if file exists at rootless path
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:plistPath]) {
            // Try Dopamine 2 path
            plistPath = [ROOT_PREFIX stringByAppendingPathComponent:[@"/private/var/mobile/Library/Preferences/" stringByAppendingString:PLIST_NAME]];
            
            // Fallback to non-rootless path if needed
            if (![fileManager fileExistsAtPath:plistPath]) {
                plistPath = [@"/var/mobile/Library/Preferences/" stringByAppendingString:PLIST_NAME];
            }
        }
        
        PXLog(@"[WeaponX] Using GPS spoofing plist path: %@", plistPath);
        return plistPath;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception getting spoofing plist path: %@", exception);
        // Fallback to default path
        return [@"/var/mobile/Library/Preferences/" stringByAppendingString:PLIST_NAME];
    }
}

- (NSString *)globalScopePlistPath {
    @try {
        // Try rootless path first
        NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:[@"/var/mobile/Library/Preferences/" stringByAppendingString:GLOBAL_SCOPE_PLIST]];
        
        // Check if file exists at rootless path
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:plistPath]) {
            // Try Dopamine 2 path
            plistPath = [ROOT_PREFIX stringByAppendingPathComponent:[@"/private/var/mobile/Library/Preferences/" stringByAppendingString:GLOBAL_SCOPE_PLIST]];
            
            // Fallback to non-rootless path if needed
            if (![fileManager fileExistsAtPath:plistPath]) {
                plistPath = [@"/var/mobile/Library/Preferences/" stringByAppendingString:GLOBAL_SCOPE_PLIST];
            }
        }
        
        return plistPath;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception getting global scope plist path: %@", exception);
        // Fallback to default path
        return [@"/var/mobile/Library/Preferences/" stringByAppendingString:GLOBAL_SCOPE_PLIST];
    }
}

- (void)saveSpoofingLocation:(NSDictionary *)location {
    if (!location || !location[@"latitude"] || !location[@"longitude"]) {
        PXLog(@"[WeaponX] Cannot save invalid spoofing location");
        return;
    }
    
    @try {
        NSString *plistPath = [self spoofingPlistPath];
        
        // Load existing settings or create new dictionary
        NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
        if (!settings) {
            settings = [NSMutableDictionary dictionary];
        }
        
        // Save as PinnedLocation
        settings[@"PinnedLocation"] = location;
        
        // Write to file
        BOOL success = [settings writeToFile:plistPath atomically:YES];
        if (!success) {
            PXLog(@"[WeaponX] Failed to save pinned location");
        } else {
            PXLog(@"[WeaponX] Saved pinned location: %.6f, %.6f", 
                  [location[@"latitude"] doubleValue], 
                  [location[@"longitude"] doubleValue]);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception saving spoofing location: %@", exception);
    }
}

- (NSDictionary *)loadSpoofingLocation {
    @try {
        NSString *plistPath = [self spoofingPlistPath];
        
        // Load settings
        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (!settings) {
            return @{}; // Empty dictionary if no settings file
        }
        
        // Only get pinned location - no GPSSpoofingLocation fallback
        NSDictionary *location = settings[@"PinnedLocation"];
        
        // Log what we're doing
        if (location && location[@"latitude"] && location[@"longitude"]) {
            PXLog(@"[WeaponX] Found pinned location at: %.6f, %.6f", 
                  [location[@"latitude"] doubleValue], 
                  [location[@"longitude"] doubleValue]);
        } else {
            PXLog(@"[WeaponX] No pinned location found, spoofing disabled");
        }
        
        return location ?: @{};
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception loading spoofing location: %@", exception);
        return @{}; // Return empty dictionary on error
    }
}

- (void)loadScopedApps {
    @try {
        // Add a cooldown timer to prevent excessive reloading
        static NSTimeInterval lastLoadTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        
        // Only allow reloading once every 30 seconds
        if (currentTime - lastLoadTime < 30.0 && self.cachedScopedApps.count > 0) {
            PXLog(@"[WeaponX] LocationSpoofingManager: Skipping reload of scoped apps (cooldown active)");
            return;
        }
        
        lastLoadTime = currentTime;
        
        // Try rootless path first
        NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
        NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        PXLog(@"[WeaponX] LocationSpoofingManager: Trying to load scoped apps from: %@", scopedAppsFile);
        
        // Fallback to standard path if rootless path doesn't exist
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:scopedAppsFile]) {
            PXLog(@"[WeaponX] LocationSpoofingManager: First path not found, trying Dopamine 2 path");
            // Try Dopamine 2 path
            prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
            
            // Fallback to older paths if needed
            if (![fileManager fileExistsAtPath:scopedAppsFile]) {
                PXLog(@"[WeaponX] LocationSpoofingManager: Dopamine 2 path not found, trying legacy path");
                prefsPath = @"/var/mobile/Library/Preferences";
                scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
            }
        }
        
        PXLog(@"[WeaponX] LocationSpoofingManager: Loading scoped apps from: %@", scopedAppsFile);
        PXLog(@"[WeaponX] LocationSpoofingManager: File exists: %@", [fileManager fileExistsAtPath:scopedAppsFile] ? @"YES" : @"NO");
        
        // Load scoped apps from the global scope file
        NSDictionary *scopedAppsDict = [NSDictionary dictionaryWithContentsOfFile:scopedAppsFile];
        PXLog(@"[WeaponX] LocationSpoofingManager: Loaded dictionary: %@", scopedAppsDict ? @"YES" : @"NO");
        
        NSDictionary *savedApps = scopedAppsDict[@"ScopedApps"];
        PXLog(@"[WeaponX] LocationSpoofingManager: Scoped apps entry found in dictionary: %@", savedApps ? @"YES" : @"NO");
        
        if (savedApps) {
            PXLog(@"[WeaponX] LocationSpoofingManager: Number of scoped apps found: %lu", (unsigned long)savedApps.count);
            if (savedApps.count > 0) {
                PXLog(@"[WeaponX] LocationSpoofingManager: App list includes: %@", [savedApps allKeys]);
            }
            
            // Retain old apps if loading fails
            NSMutableDictionary *oldApps = [NSMutableDictionary dictionaryWithDictionary:self.cachedScopedApps];
            
            // Make sure we properly update the cached scoped apps dictionary
            if (!self.cachedScopedApps) {
                self.cachedScopedApps = [NSMutableDictionary dictionaryWithDictionary:savedApps];
            } else {
                [self.cachedScopedApps removeAllObjects];
                [self.cachedScopedApps addEntriesFromDictionary:savedApps];
            }
            
            // Validate we successfully loaded apps
            if (self.cachedScopedApps.count == 0 && oldApps.count > 0) {
                // Loading failed, restore old apps
                self.cachedScopedApps = oldApps;
                PXLog(@"[WeaponX] LocationSpoofingManager: Failed to load scoped apps, restored previous list with %lu items", 
                      (unsigned long)oldApps.count);
            } else {
                PXLog(@"[WeaponX] LocationSpoofingManager: Loaded %lu scoped apps from %@", 
                      (unsigned long)savedApps.count, scopedAppsFile);
            }
        } else {
            // Keep the existing apps if loading failed
            if (self.cachedScopedApps.count == 0) {
                self.cachedScopedApps = [NSMutableDictionary dictionary];
                
                // Add common location apps as a fallback
                NSArray *commonLocationApps = @[
                    @"com.apple.Maps",
                    @"com.google.Maps",
                    @"com.waze.iphone",
                    @"com.ubercab.UberClient",
                    @"com.ubercab.UberPartner",
                    @"com.zimride.instant",
                    @"com.yelp.yelpiphone",
                    @"com.seatgeek.SeatGeek"
                ];
                
                for (NSString *app in commonLocationApps) {
                    self.cachedScopedApps[app] = @{@"enabled": @YES};
                }
                
                PXLog(@"[WeaponX] LocationSpoofingManager: ⚠️ Failed to load scoped apps, using fallback list with common apps");
            } else {
                PXLog(@"[WeaponX] LocationSpoofingManager: ⚠️ Failed to load new scoped apps, keeping existing list with %lu items",
                      (unsigned long)self.cachedScopedApps.count);
            }
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] LocationSpoofingManager: Exception loading scoped apps: %@", exception);
        // Maintain existing dictionary on error
        if (!self.cachedScopedApps) {
            self.cachedScopedApps = [NSMutableDictionary dictionary];
        }
    }
}

#pragma mark - GPS Data Modification

- (CLLocation *)modifySpoofedLocation:(CLLocation *)originalLocation {
    if (!originalLocation) {
        return originalLocation;
    }
    
    @synchronized(self) {
        // Double-check spoofing is enabled and we have a valid pinned location
        if (![self isSpoofingEnabled]) {
            return originalLocation;
        }
        
        // Ensure we have valid coordinates
        double safeLatitude = [self getSpoofedLatitude];
        double safeLongitude = [self getSpoofedLongitude];
        
        // Quick validation check - avoid expensive logging
        if (isnan(safeLatitude) || isnan(safeLongitude) || 
            isinf(safeLatitude) || isinf(safeLongitude) ||
            !CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(safeLatitude, safeLongitude))) {
            return originalLocation;
        }
        
        // Create a realistic spoofed location
        CLLocationCoordinate2D baseCoordinate = CLLocationCoordinate2DMake(safeLatitude, safeLongitude);
        
        // Add randomized position variations if enabled
        if (self.positionVariationsEnabled) {
            // Generate random angle in radians (0-360 degrees) for true omnidirectional movement
            double randomAngle = (arc4random_uniform(360) * M_PI) / 180.0;
            
            // Determine variation distance based on transportation mode
            double variationDistance;
            switch (self.transportationMode) {
                case TransportationModeDriving:
                    // Larger variations for driving (2-8 meters)
                    variationDistance = 2.0 + ((arc4random_uniform(60)) / 10.0);
                    break;
                    
                case TransportationModeWalking:
                    // Medium variations for walking (1-5 meters)
                    variationDistance = 1.0 + ((arc4random_uniform(40)) / 10.0);
                    break;
                    
                default: // Stationary
                    // Small variations for stationary (0.5-2 meters)
                    variationDistance = 0.5 + ((arc4random_uniform(15)) / 10.0);
                    break;
            }
            
            // Convert distance and angle to latitude/longitude offsets
            // This uses the haversine formula approximation for small distances
            double latOffset = variationDistance * cos(randomAngle) / 111000.0; // Approx meters to degrees lat
            double lonOffset = variationDistance * sin(randomAngle) / (111000.0 * cos(baseCoordinate.latitude * M_PI / 180.0)); // Adjust for longitude compression
            
            // Apply the offsets to create realistic movement in any direction
            baseCoordinate.latitude += latOffset;
            baseCoordinate.longitude += lonOffset;
        }
        
        // Create a new location with the spoofed coordinates and additional properties
        CLLocation *spoofedLocation = [[CLLocation alloc] initWithCoordinate:baseCoordinate
                                                                   altitude:originalLocation.altitude
                                                         horizontalAccuracy:self.accuracyValue
                                                           verticalAccuracy:originalLocation.verticalAccuracy
                                                                  timestamp:[NSDate date]];
        
        return spoofedLocation;
    }
}

- (double)getSpoofedLatitude {
    @synchronized(self) {
        // If we don't have a valid latitude, try to refresh location
        if (self.latitude == 0.0 || isnan(self.latitude) || isinf(self.latitude)) {
            NSDictionary *pinnedLocation = [self directReadPinnedLocationFromFile];
            if (pinnedLocation) {
                self.latitude = [pinnedLocation[@"latitude"] doubleValue];
                self.longitude = [pinnedLocation[@"longitude"] doubleValue];
                self.spoofingEnabled = YES;
            }
        }
        return self.latitude;
    }
}

- (double)getSpoofedLongitude {
    @synchronized(self) {
        // If we don't have a valid longitude, try to refresh location
        if (self.longitude == 0.0 || isnan(self.longitude) || isinf(self.longitude)) {
            NSDictionary *pinnedLocation = [self directReadPinnedLocationFromFile];
            if (pinnedLocation) {
                self.latitude = [pinnedLocation[@"latitude"] doubleValue];
                self.longitude = [pinnedLocation[@"longitude"] doubleValue];
                self.spoofingEnabled = YES;
            }
        }
        return self.longitude;
    }
}

#pragma mark - App Scoping

- (BOOL)shouldSpoofApp:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }
    
    // Early check - if not enabled, no need to check scoped apps
    if (![self isSpoofingEnabled]) {
        return NO;
    }
    
    @try {
        // Use an in-memory cache with time expiration to avoid constant plist checks
        // Use file scope variables for sharing
        extern NSMutableDictionary *appSpoofingCache;
        extern NSDate *lastCacheRefreshTime;
        
        // Initialize cache if needed
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            if (appSpoofingCache == nil) {
                appSpoofingCache = [NSMutableDictionary dictionary];
                lastCacheRefreshTime = [NSDate date];
            }
        });
        
        // Check if we have a valid cached result
        NSDate *currentDate = [NSDate date];
        NSNumber *cachedResult = appSpoofingCache[bundleID];
        
        // Cache is valid for longer time (2 minutes) to avoid excessive file reads
        if (cachedResult && lastCacheRefreshTime && [currentDate timeIntervalSinceDate:lastCacheRefreshTime] < 120.0) {
            return [cachedResult boolValue];
        }
        
        // Direct check against the cached dictionary
        if (self.cachedScopedApps[bundleID]) {
            BOOL isEnabled = [self.cachedScopedApps[bundleID][@"enabled"] boolValue];
            // Update cache
            appSpoofingCache[bundleID] = @(isEnabled);
            return isEnabled;
        }
        
        // Try case-insensitive comparison
        NSString *lowercaseBundleID = [bundleID lowercaseString];
        for (NSString *key in self.cachedScopedApps) {
            if ([[key lowercaseString] isEqualToString:lowercaseBundleID]) {
                BOOL isEnabled = [self.cachedScopedApps[key][@"enabled"] boolValue];
                // Add to case-sensitive cache for future lookups
                appSpoofingCache[bundleID] = @(isEnabled);
                return isEnabled;
            }
        }
        
        // As a fallback for location apps, check common location-based apps
        NSArray *commonLocationApps = @[
            @"com.apple.Maps",
            @"com.google.Maps",
            @"com.waze.iphone",
            @"com.ubercab.UberClient",
            @"com.ubercab.UberPartner",
            @"com.zimride.instant",
            @"com.yelp.yelpiphone",
            @"com.seatgeek.SeatGeek"
        ];
        
        if ([commonLocationApps containsObject:bundleID]) {
            // Add to cache for future lookups
            appSpoofingCache[bundleID] = @YES;
            return YES;
        }
        
        // Log the failure only occasionally to avoid log spam
        static NSTimeInterval lastLogTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLogTime > 60.0) {
            PXLog(@"[WeaponX] App %@ not found in scoped apps, spoofing disabled for this app", bundleID);
            lastLogTime = currentTime;
        }
        
        // Not found after all attempts - cache negative result
        appSpoofingCache[bundleID] = @NO;
        return NO;
    } @catch (NSException *exception) {
        // Only log occasionally to reduce overhead
        static NSTimeInterval lastLogTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLogTime > 60.0) {
            PXLog(@"[WeaponX] Exception in shouldSpoofApp: %@", exception);
            lastLogTime = currentTime;
        }
        return NO;
    }
}

// Helper method to refresh the app spoofing cache
- (void)refreshAppSpoofingCache {
    static BOOL isRefreshing = NO;
    
    // Prevent concurrent refreshes
    @synchronized(self) {
        if (isRefreshing) return;
        isRefreshing = YES;
    }
    
    @try {
        // Load scoped apps from disk
        [self loadScopedApps];
        
        // Create or update the static cache - use extern variables for access from shouldSpoofApp
        extern NSMutableDictionary *appSpoofingCache;
        extern NSDate *lastCacheRefreshTime;
        
        if (!appSpoofingCache) {
            appSpoofingCache = [NSMutableDictionary dictionary];
        } else {
            [appSpoofingCache removeAllObjects];
        }
        
        // Rebuild the cache
        for (NSString *bundleID in self.cachedScopedApps) {
            BOOL isEnabled = [self.cachedScopedApps[bundleID][@"enabled"] boolValue];
            appSpoofingCache[bundleID] = @(isEnabled);
        }
        
        // Add common location apps as enabled by default
        NSArray *commonLocationApps = @[
            @"com.apple.Maps",
            @"com.google.Maps",
            @"com.waze.iphone",
            @"com.ubercab.UberClient",
            @"com.ubercab.UberPartner",
            @"com.zimride.instant",
            @"com.yelp.yelpiphone",
            @"com.seatgeek.SeatGeek"
        ];
        
        for (NSString *app in commonLocationApps) {
            if (!appSpoofingCache[app]) {
                appSpoofingCache[app] = @YES;
            }
        }
        
        // Update refresh timestamp and make it accessible to shouldSpoofApp
        lastCacheRefreshTime = [NSDate date];
        
        PXLog(@"[WeaponX] App spoofing cache refreshed with %lu apps at %@", 
              (unsigned long)appSpoofingCache.count, 
              lastCacheRefreshTime ? [NSDateFormatter localizedStringFromDate:lastCacheRefreshTime 
                                                                    dateStyle:NSDateFormatterShortStyle 
                                                                    timeStyle:NSDateFormatterMediumStyle] : @"unknown time");
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Error refreshing app spoofing cache: %@", exception);
    } @finally {
        // Always reset the refreshing flag
        @synchronized(self) {
            isRefreshing = NO;
        }
    }
}

/**
 * Directly reads pinned location from plist file with caching.
 * Returns nil if no pinned location is found.
 */
- (NSDictionary *)directReadPinnedLocationFromFile {
    // First check if we have a recent cached version
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (self.cachedPinnedLocation && (currentTime - self.lastPinnedLocationReadTime < 15.0)) {
        // Cache is fresh (within 15 seconds), use it
        return self.cachedPinnedLocation;
    }
    
    @try {
        // Get the plist path
        NSString *plistPath = [self spoofingPlistPath];
        
        // Check if file exists
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:plistPath]) {
            self.cachedPinnedLocation = nil;
            self.lastPinnedLocationReadTime = currentTime;
            return nil;
        }
        
        // Read the plist file directly
        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (!settings) {
            self.cachedPinnedLocation = nil;
            self.lastPinnedLocationReadTime = currentTime;
            return nil;
        }
        
        // Get only the pinned location
        NSDictionary *pinnedLocation = settings[@"PinnedLocation"];
        if (!pinnedLocation || !pinnedLocation[@"latitude"] || !pinnedLocation[@"longitude"]) {
            self.cachedPinnedLocation = nil;
            self.lastPinnedLocationReadTime = currentTime;
            return nil;
        }
        
        // Verify the coordinates are valid
        double lat = [pinnedLocation[@"latitude"] doubleValue];
        double lon = [pinnedLocation[@"longitude"] doubleValue];
        
        if (isnan(lat) || isinf(lat) || isnan(lon) || isinf(lon) || 
            !CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon))) {
            self.cachedPinnedLocation = nil;
            self.lastPinnedLocationReadTime = currentTime;
            return nil;
        }
        
        // Cache the result
        self.cachedPinnedLocation = pinnedLocation;
        self.lastPinnedLocationReadTime = currentTime;
        
        PXLog(@"[WeaponX] Loaded pinned location from file: %.6f, %.6f (lat, lon)", 
              lat, lon);
        
        return pinnedLocation;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception reading pinned location: %@", exception);
        self.cachedPinnedLocation = nil;
        self.lastPinnedLocationReadTime = [[NSDate date] timeIntervalSince1970];
        return nil;
    }
}

- (void)saveSpoofingToggleState:(BOOL)enabled {
    @try {
        NSString *plistPath = [self spoofingPlistPath];
        
        // Load existing settings or create new dictionary
        NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
        if (!settings) {
            settings = [NSMutableDictionary dictionary];
        }
        
        // Update toggle state
        settings[@"GPSSpoofingToggleEnabled"] = @(enabled);
        
        // Write to file
        BOOL success = [settings writeToFile:plistPath atomically:YES];
        if (!success) {
            PXLog(@"[WeaponX] Failed to save GPS spoofing toggle state");
        } else {
            PXLog(@"[WeaponX] Saved GPS spoofing toggle state: %@", enabled ? @"ON" : @"OFF");
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception saving spoofing toggle state: %@", exception);
    }
}

- (BOOL)loadSpoofingToggleState {
    @try {
        NSString *plistPath = [self spoofingPlistPath];
        
        // Load settings
        NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (!settings) {
            return NO; // Default to disabled if no settings file
        }
        
        // Get GPS spoofing toggle state
        BOOL toggleState = [settings[@"GPSSpoofingToggleEnabled"] boolValue];
        PXLog(@"[WeaponX] Loaded GPS spoofing toggle state: %@", toggleState ? @"ON" : @"OFF");
        return toggleState;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception loading spoofing toggle state: %@", exception);
        return NO; // Default to disabled on error
    }
}

- (void)enableSpoofingToggle {
    @synchronized(self) {
        self.spoofingToggleState = YES;
        
        // Check if we have a pinned location to use
        NSDictionary *pinnedLocation = [self directReadPinnedLocationFromFile];
        if (pinnedLocation) {
            // We have a pinned location, enable actual spoofing
            self.latitude = [pinnedLocation[@"latitude"] doubleValue];
            self.longitude = [pinnedLocation[@"longitude"] doubleValue];
            self.spoofingEnabled = YES;
            
            PXLog(@"[WeaponX] GPS Spoofing Toggle turned ON, using pinned location at %.6f, %.6f",
                  self.latitude, self.longitude);
        } else {
            // No pinned location, can't spoof yet
            self.spoofingEnabled = NO;
            PXLog(@"[WeaponX] GPS Spoofing Toggle turned ON, but no pinned location available");
        }
    }
    
    // Save toggle state to plist
    [self saveSpoofingToggleState:YES];
}

- (void)disableSpoofingToggle {
    @synchronized(self) {
        self.spoofingToggleState = NO;
        self.spoofingEnabled = NO;
    }
    
    // Save toggle state to plist
    [self saveSpoofingToggleState:NO];
    
    PXLog(@"[WeaponX] GPS Spoofing Toggle turned OFF");
}

// Get the current toggle state
- (BOOL)isSpoofingToggleEnabled {
    return self.spoofingToggleState;
}

#pragma mark - Advanced Spoofing Methods

- (void)setTransportationMode:(TransportationMode)mode {
    @synchronized(self) {
        // Set the transportation mode using direct ivar access instead of property
        _transportationMode = mode;
        
        // Set appropriate movement parameters based on mode
        switch(mode) {
            case TransportationModeStationary:
                // Almost no movement, just tiny jitter
                _maxMovementSpeed = 0.2; // m/s (very slight drift)
                _jitterAmount = 1.0;     // Minimal jitter
                break;
                
            case TransportationModeWalking:
                // Walking pace with natural variations
                // Average human walking speed is about 1.4 m/s (5 km/h)
                // Use a narrower range with a more accurate center point
                _maxMovementSpeed = 1.4 + ((arc4random() % 60) / 100.0); // 1.4-2.0 m/s
                
                // Increase jitter for more realistic path wandering
                _jitterAmount = 4.5;     // More pronounced jitter - humans don't walk in straight lines
                break;
                
            case TransportationModeDriving:
                // Driving speed with appropriate smoothness
                _maxMovementSpeed = 13.0 + ((arc4random() % 700) / 100.0); // 13-20 m/s (47-72 km/h)
                _jitterAmount = 1.5;     // Less jitter - cars follow roads more precisely
                break;
        }
        
        PXLog(@"[WeaponX] Set transportation mode to %ld, speed: %.2f m/s, jitter: %.1f", 
              (long)mode, _maxMovementSpeed, _jitterAmount);
    }
}

- (void)setAccuracyValue:(double)accuracy {
    @synchronized(self) {
        // Clamp accuracy between 5-15 meters using direct ivar access
        _accuracyValue = MAX(5.0, MIN(15.0, accuracy));
        PXLog(@"[WeaponX] Set GPS accuracy to %.1f meters", _accuracyValue);
    }
}

- (void)setJitterEnabled:(BOOL)enabled {
    @synchronized(self) {
        _jitterEnabled = enabled;
        PXLog(@"[WeaponX] GPS position jitter %@", enabled ? @"enabled" : @"disabled");
    }
}

// Helper method to calculate bearing between two coordinates
- (double)calculateBearingFromCoordinate:(CLLocationCoordinate2D)fromCoord toCoordinate:(CLLocationCoordinate2D)toCoord {
    double lat1 = fromCoord.latitude * M_PI / 180.0;
    double lon1 = fromCoord.longitude * M_PI / 180.0;
    double lat2 = toCoord.latitude * M_PI / 180.0;
    double lon2 = toCoord.longitude * M_PI / 180.0;
    
    double dLon = lon2 - lon1;
    
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double bearing = atan2(y, x);
    
    // Convert to degrees
    bearing = bearing * 180.0 / M_PI;
    
    // Normalize to 0-360
    bearing = fmod(bearing + 360.0, 360.0);
    
    return bearing;
}

- (CLLocation *)createRealisticSpoofedLocation:(CLLocationCoordinate2D)baseCoordinate {
    static CLLocationCoordinate2D lastCoord = {0,0};
    static NSDate *lastTime = nil;
    static double lastHeadingChange = 0;  // Track accumulated heading changes for more natural direction changes
    
    // Calculate realistic speed and course if we have previous data
    double speed = 0;
    double course = 0;
    NSDate *now = [NSDate date];
    
    if (lastTime != nil && CLLocationCoordinate2DIsValid(lastCoord)) {
        NSTimeInterval timeDiff = [now timeIntervalSinceDate:lastTime];
        
        // Calculate distance between points
        CLLocation *lastLocation = [[CLLocation alloc] initWithLatitude:lastCoord.latitude 
                                                              longitude:lastCoord.longitude];
        CLLocation *newLocation = [[CLLocation alloc] initWithLatitude:baseCoordinate.latitude 
                                                             longitude:baseCoordinate.longitude];
        CLLocationDistance distance = [newLocation distanceFromLocation:lastLocation];
        
        // Calculate speed (m/s)
        speed = (timeDiff > 0) ? distance / timeDiff : 0;
        
        // If speed is too high, cap it based on transportation mode
        if (speed > _maxMovementSpeed) {
            speed = _maxMovementSpeed;
        }
        
        // Calculate bearing/course
        course = [self calculateBearingFromCoordinate:lastCoord toCoordinate:baseCoordinate];
        
        // For walking mode, make direction changes more natural
        if (_transportationMode == TransportationModeWalking) {
            // Add small random direction variations for walking
            // Use a different pattern based on time to avoid unnatural zigzagging
            double timeFactor = fmod(timeDiff * 10.0, 6.28);  // 0 to 2π
            double dirChange = sin(timeFactor) * 5.0;  // Smooth variation pattern
            
            // Accumulate changes to create a more meandering path
            lastHeadingChange = lastHeadingChange * 0.8 + dirChange * 0.2;
            
            // Apply the accumulated heading change
            course += lastHeadingChange;
            
            // 5% chance of more significant direction change (like avoiding obstacle)
            if (arc4random() % 100 < 5) {
                course += ((arc4random() % 40) - 20);
            }
            
            // Normalize to 0-360
            course = fmod(course + 360.0, 360.0);
        }
    } else {
        // First time or invalid last coord, use a default speed based on transportation mode
        speed = _transportationMode == TransportationModeStationary ? 0 : 
                _transportationMode == TransportationModeWalking ? 1.4 : 15.0;
        
        // Random initial course
        course = arc4random() % 360;
        lastHeadingChange = 0;
    }
    
    // Store the reported values
    _lastReportedSpeed = speed;
    _lastReportedCourse = course;
    
    // Add realistic jitter if enabled
    double jitterLat = 0.0;
    double jitterLon = 0.0;
    
    if (_jitterEnabled) {
        // Walking mode has more natural jitter variations
        if (_transportationMode == TransportationModeWalking) {
            // Use a truly random angle approach instead of sine waves for omnidirectional movement
            double jitterScale = _jitterAmount / 10000.0;
            double randomAngle = (arc4random_uniform(360) * M_PI) / 180.0; // Random angle in radians
            double jitterMagnitude = ((arc4random_uniform(30) + 10) * jitterScale * 20.0); // Random magnitude
            
            // Convert polar coordinates (angle + magnitude) to Cartesian (x,y)
            jitterLat = jitterMagnitude * cos(randomAngle);
            jitterLon = jitterMagnitude * sin(randomAngle);
            
            // Add some extra randomness to break any patterns
            jitterLat += ((arc4random() % 20) - 10) * jitterScale;
            jitterLon += ((arc4random() % 20) - 10) * jitterScale;
        } else {
            // Scale jitter based on jitterAmount setting - standard method for non-walking modes
            double jitterScale = _jitterAmount / 10000.0;
            
            // Use random angle for all modes to ensure omnidirectional movement
            double randomAngle = (arc4random_uniform(360) * M_PI) / 180.0;
            double jitterMagnitude = ((arc4random() % 40) + 5) * jitterScale;
            
            jitterLat = jitterMagnitude * cos(randomAngle);
            jitterLon = jitterMagnitude * sin(randomAngle);
        }
    }
    
    // Calculate accuracy based on user setting with slight variation
    double accuracy = _accuracyValue;
    
    // Walking mode has variable accuracy with occasional spikes
    if (_transportationMode == TransportationModeWalking) {
        // Add variations typical of phone GPS when walking (buildings, etc.)
        accuracy += ((arc4random() % 200) / 100.0) - 1.0;  // ±1.0m variation
        
        // Occasional GPS accuracy spikes (10% chance)
        if (arc4random() % 100 < 10) {
            accuracy *= 1.5; // 50% worse accuracy occasionally
        }
    } else {
        // Standard accuracy variation for other modes
        accuracy += ((arc4random() % 100) / 50.0) - 1.0; // ±1.0m variation
    }
    
    // Store values for next calculation
    lastCoord = baseCoordinate;
    lastTime = now;
    
    // Create location with all properties properly set
    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(
                                                baseCoordinate.latitude + jitterLat,
                                                baseCoordinate.longitude + jitterLon)
                                        altitude:arc4random() % 10 + 0.0
                              horizontalAccuracy:accuracy
                                verticalAccuracy:accuracy * 1.5
                                          course:course
                                           speed:speed
                                       timestamp:now];
}

// Calculate points for simple linear movement between two coordinates
- (NSArray<CLLocation *> *)calculateSimpleMovement:(CLLocationCoordinate2D)start 
                                               end:(CLLocationCoordinate2D)end
                                  speedMetersPerSecond:(double)speed {
    NSMutableArray *points = [NSMutableArray array];
    
    // Calculate distance
    CLLocation *startLoc = [[CLLocation alloc] initWithLatitude:start.latitude longitude:start.longitude];
    CLLocation *endLoc = [[CLLocation alloc] initWithLatitude:end.latitude longitude:end.longitude];
    CLLocationDistance distance = [endLoc distanceFromLocation:startLoc];
    
    // Calculate number of points based on speed and update frequency
    double updateFrequencySeconds = 1.0; // Update every second
    int numberOfPoints = MAX(2, ceil(distance / (speed * updateFrequencySeconds)));
    
    // For walking mode, add more points to create more natural path
    BOOL isWalking = (_transportationMode == TransportationModeWalking);
    if (isWalking && numberOfPoints > 3) {
        // Add more intermediate points for walking
        numberOfPoints = numberOfPoints * 1.5;
    }
    
    // Generate intermediate points
    double lastCourse = -1;  // Track last course for more natural changes
    double lastSpeed = speed;
    
    for (int i = 0; i < numberOfPoints; i++) {
        double fraction = (double)i / (numberOfPoints - 1);
        
        // Base position - linear interpolation between points
        double lat = start.latitude + fraction * (end.latitude - start.latitude);
        double lon = start.longitude + fraction * (end.longitude - start.longitude);
        
        // Add natural variation based on transportation mode
        if (i > 0 && i < numberOfPoints - 1) {  // Don't modify start and end points
            double variationFactor;
            
            if (_transportationMode == TransportationModeWalking) {
                // Walking has more natural meandering
                variationFactor = 0.00003; // ±0.003 degrees - significantly higher variation
                
                // Create a more organic path with higher deflection around the midpoint
                double deflectionFactor = sin(fraction * M_PI); // Peak at the middle of the path
                lat += ((arc4random() % 200) - 100) / 10000.0 * deflectionFactor; 
                lon += ((arc4random() % 200) - 100) / 10000.0 * deflectionFactor;
                
                // Add occasional slight pause or direction change (10% chance)
                if (arc4random() % 100 < 10) {
                    // More dramatic direction change
                    lat += ((arc4random() % 100) - 50) / 20000.0;
                    lon += ((arc4random() % 100) - 50) / 20000.0;
                }
            } else if (_transportationMode == TransportationModeDriving) {
                // Driving follows more direct path with slight variations (like a road)
                variationFactor = 0.000015; // ±0.0015 degrees
            } else {
                // Stationary mode has less variation
                variationFactor = 0.000008; // ±0.0008 degrees
            }
            
            // Apply base variation for all modes
            lat += ((arc4random() % 20) - 10) * variationFactor;
            lon += ((arc4random() % 20) - 10) * variationFactor;
        }
        
        // Vary the speed for more realism
        double currentSpeed = speed;
        if (i > 0 && i < numberOfPoints - 1) {
            if (_transportationMode == TransportationModeWalking) {
                // Walking speed naturally varies by about ±20%
                double variation = ((arc4random() % 40) - 20) / 100.0;
                currentSpeed = speed * (1.0 + variation);
                
                // Occasionally slow down significantly (5% chance)
                if (arc4random() % 100 < 5) {
                    currentSpeed *= 0.7; // 70% of normal speed
                }
            } else if (_transportationMode == TransportationModeDriving) {
                // Driving speed varies less on straightaways, more on turns
                double variation = ((arc4random() % 20) - 10) / 100.0;
                currentSpeed = speed * (1.0 + variation);
            }
            
            // Smooth speed changes - don't change drastically from last speed
            if (lastSpeed > 0) {
                currentSpeed = lastSpeed * 0.7 + currentSpeed * 0.3;
            }
            lastSpeed = currentSpeed;
        }
        
        // Create the location with realistic properties
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(lat, lon);
        
        // Calculate bearing/course more naturally
        double course;
        if (i == 0) {
            // Initial course is direct bearing to next point
            course = [self calculateBearingFromCoordinate:start toCoordinate:end];
        } else if (i == numberOfPoints - 1) {
            // Final point keeps the approach course
            course = lastCourse >= 0 ? lastCourse : [self calculateBearingFromCoordinate:start toCoordinate:end];
        } else {
            // Intermediate points - calculate course to next interpolated point
            double nextFraction = (double)(i+1) / (numberOfPoints - 1);
            double nextLat = start.latitude + nextFraction * (end.latitude - start.latitude);
            double nextLon = start.longitude + nextFraction * (end.longitude - start.longitude);
            
            course = [self calculateBearingFromCoordinate:coordinate 
                                           toCoordinate:CLLocationCoordinate2DMake(nextLat, nextLon)];
            
            // Make direction changes more gradual for walking
            if (lastCourse >= 0 && _transportationMode == TransportationModeWalking) {
                // Blend current course with previous course for smoother transitions
                // The closer to the endpoint, the more we align with the target direction
                double blendFactor = 0.3; // How much of previous course to keep
                course = lastCourse * blendFactor + course * (1.0 - blendFactor);
                
                // Add small random course variations for walking (human walking isn't perfectly straight)
                course += ((arc4random() % 20) - 10);
                // Normalize to 0-360
                course = fmod(course + 360.0, 360.0);
            }
        }
        lastCourse = course;
        
        // Create the location with our parameters
        CLLocation *location = [[CLLocation alloc] initWithCoordinate:coordinate
                                                         altitude:arc4random() % 10 + 0.0
                                               horizontalAccuracy:_accuracyValue
                                                 verticalAccuracy:_accuracyValue * 1.5
                                                           course:course
                                                            speed:currentSpeed
                                                        timestamp:[NSDate dateWithTimeIntervalSinceNow:i * updateFrequencySeconds]];
        
        [points addObject:location];
    }
    
    PXLog(@"[WeaponX] Calculated movement path with %lu points over %.1f meters at %.1f m/s (%@)", 
          (unsigned long)points.count, distance, speed, 
          _transportationMode == TransportationModeWalking ? @"walking" : 
          _transportationMode == TransportationModeDriving ? @"driving" : @"stationary");
    
    return points;
}

// Adjust location updates based on transportation mode
- (void)applyTransportationMode:(TransportationMode)mode toLocation:(CLLocation *)location {
    @synchronized(self) {
        // Set appropriate movement parameters based on mode
        switch(mode) {
            case TransportationModeStationary:
                // Almost no movement, just tiny jitter
                _maxMovementSpeed = 0.2; // m/s (very slight drift)
                _jitterAmount = 1.0;     // Minimal jitter
                break;
            case TransportationModeWalking:
                // Walking pace with natural variations
                _maxMovementSpeed = 1.2 + ((arc4random() % 80) / 100.0); // 1.2-2.0 m/s
                _jitterAmount = 3.0;     // Moderate jitter
                break;
            case TransportationModeDriving:
                // Driving speed with appropriate smoothness
                _maxMovementSpeed = 13.0 + ((arc4random() % 700) / 100.0); // 13-20 m/s (47-72 km/h)
                _jitterAmount = 1.5;     // Less jitter
                break;
        }
        return;
    }
}

- (void)startMovementAlongPath:(NSArray *)waypoints
                     withSpeed:(double)metersPerSecond
                    completion:(void(^)(BOOL completed))completion {
    [self startMovementAlongPath:waypoints withSpeed:metersPerSecond startIndex:0 completion:completion];
}

// Overloaded method to start from a specific index
- (void)startMovementAlongPath:(NSArray *)waypoints
                     withSpeed:(double)metersPerSecond
                    startIndex:(NSInteger)startIndex
                    completion:(void(^)(BOOL completed))completion {
    @synchronized(self) {
        if (!waypoints || waypoints.count < 2) {
            PXLog(@"[WeaponX] Cannot start movement: Invalid waypoints array (need at least 2 points)");
            if (completion) {
                completion(NO);
            }
            return;
        }
        if (self.isMovingAlongPath) {
            [self stopMovementAlongPath];
        }
        self.currentPath = waypoints;
        self.pathCompletionHandler = completion;
        self.pathSpeed = metersPerSecond;
        self.isMovingAlongPath = YES;
        // Generate detailed path by connecting all waypoints with intermediate points
        NSMutableArray<CLLocation *> *allPathLocations = [NSMutableArray array];
        for (NSUInteger i = 0; i < waypoints.count - 1; i++) {
            id startObj = [waypoints objectAtIndex:i];
            id endObj = [waypoints objectAtIndex:i+1];
            CLLocationCoordinate2D start = CLLocationCoordinate2DMake(0, 0);
            CLLocationCoordinate2D end = CLLocationCoordinate2DMake(0, 0);
            // Extract coordinates from start
            if ([startObj isKindOfClass:[CLLocation class]]) {
                start = [(CLLocation *)startObj coordinate];
            } else if ([startObj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)startObj;
                start.latitude = [dict[@"latitude"] doubleValue];
                start.longitude = [dict[@"longitude"] doubleValue];
            } else if ([startObj isKindOfClass:[NSValue class]]) {
                CGPoint point;
                [(NSValue *)startObj getValue:&point];
                start.latitude = point.x;
                start.longitude = point.y;
            }

            // Extract coordinates from the end waypoint object
            if ([endObj isKindOfClass:[CLLocation class]]) {
                // CLLocation object
                end = [(CLLocation *)endObj coordinate];
            } else if ([endObj isKindOfClass:[NSDictionary class]]) {
                // Dictionary with latitude/longitude keys
                NSDictionary *dict = (NSDictionary *)endObj;
                end.latitude = [dict[@"latitude"] doubleValue];
                end.longitude = [dict[@"longitude"] doubleValue];
            } else if ([endObj isKindOfClass:[NSValue class]]) {
                // NSValue containing CGPoint
                CGPoint point;
                [(NSValue *)endObj getValue:&point];
                end.latitude = point.x;
                end.longitude = point.y;
            }
            
            // Validate coordinates before using them
            if (!CLLocationCoordinate2DIsValid(start) || !CLLocationCoordinate2DIsValid(end)) {
                PXLog(@"[WeaponX] Invalid coordinates in waypoints: start=(%.6f, %.6f), end=(%.6f, %.6f)",
                     start.latitude, start.longitude, end.latitude, end.longitude);
                
                if (completion) {
                    completion(NO);
                }
                [self stopMovementAlongPath];
                return;
            }
            
            // Calculate points for this segment
            NSArray<CLLocation *> *segmentLocations = [self calculateSimpleMovement:start 
                                                                              end:end
                                                             speedMetersPerSecond:metersPerSecond];
            
            // Add all points except the last one (which will be the start of the next segment)
            if (i < waypoints.count - 2) {
                [allPathLocations addObjectsFromArray:[segmentLocations subarrayWithRange:NSMakeRange(0, segmentLocations.count - 1)]];
            } else {
                // For the last segment, include the final point
                [allPathLocations addObjectsFromArray:segmentLocations];
            }
        }
        
        self.pathLocations = allPathLocations;
        
        PXLog(@"[WeaponX] Starting movement along path with %lu waypoints and %lu total locations at %.1f m/s", 
              (unsigned long)waypoints.count, (unsigned long)allPathLocations.count, metersPerSecond);
        
        // Start the movement timer (update every second)
        self.pathMovementTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 
                                                                 target:self 
                                                               selector:@selector(updatePathMovement) 
                                                               userInfo:nil 
                                                                repeats:YES];
        
        // Ensure GPS spoofing is enabled
        if (!self.spoofingEnabled) {
            // Use the first waypoint as the initial location
            id firstObj = [waypoints firstObject];
            CLLocationCoordinate2D firstPoint = CLLocationCoordinate2DMake(0, 0);

            // Extract coordinates from the first waypoint
            if ([firstObj isKindOfClass:[CLLocation class]]) {
                firstPoint = [(CLLocation *)firstObj coordinate];
            } else if ([firstObj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)firstObj;
                firstPoint.latitude = [dict[@"latitude"] doubleValue];
                firstPoint.longitude = [dict[@"longitude"] doubleValue];
            } else if ([firstObj isKindOfClass:[NSValue class]]) {
                CGPoint point;
                [(NSValue *)firstObj getValue:&point];
                firstPoint.latitude = point.x;
                firstPoint.longitude = point.y;
            }
            
            if (CLLocationCoordinate2DIsValid(firstPoint)) {
                [self enableSpoofingWithLatitude:firstPoint.latitude longitude:firstPoint.longitude];
            }
        }
    }
}

- (void)updatePathMovement {
    @synchronized(self) {
        if (!_isMovingAlongPath || !self.pathLocations || _currentPathIndex >= self.pathLocations.count) {
            [self stopMovementAlongPath];
            return;
        }
        
        // Get the current location in the path
        CLLocation *currentLoc = [self.pathLocations objectAtIndex:_currentPathIndex];
        
        // Update spoofed coordinates
        _latitude = currentLoc.coordinate.latitude;
        _longitude = currentLoc.coordinate.longitude;
        
        // Store reported speed and course
        _lastReportedSpeed = currentLoc.speed;
        _lastReportedCourse = currentLoc.course;
        
        // Notify about location update
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.weaponx.locationUpdated" 
                                                            object:nil 
                                                          userInfo:@{
                                                              @"latitude": @(_latitude),
                                                              @"longitude": @(_longitude),
                                                              @"speed": @(currentLoc.speed),
                                                              @"course": @(currentLoc.course)
                                                          }];
        
        // Move to next location
        _currentPathIndex++;
        // Persist currentPathIndex after increment
        [self persistCurrentPathIndexToDefaults];
        
        // Check if we've reached the end of the path
        if (_currentPathIndex >= self.pathLocations.count) {
            PXLog(@"[WeaponX] Reached end of movement path");
            [self stopMovementAlongPath];
            
            if (self.pathCompletionHandler) {
                self.pathCompletionHandler(YES);
            }
        }
    }
}

// Helper to persist currentPathIndex
- (void)persistCurrentPathIndexToDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentPathIndex forKey:@"com.weaponx.pathCurrentIndex"];
    [defaults synchronize];
}

- (void)stopMovementAlongPath {
    @synchronized(self) {
        if (self.pathMovementTimer) {
            [self.pathMovementTimer invalidate];
            self.pathMovementTimer = nil;
        }
        
        self.isMovingAlongPath = NO;
        // Do NOT clear currentPath or currentPathIndex here; let controller handle clearing if needed
        self.pathLocations = nil;
        
        // Don't call completion handler when manually stopped
        self.pathCompletionHandler = nil;
        
        PXLog(@"[WeaponX] Stopped movement along path");
    }
}

- (BOOL)isCurrentlyMoving {
    return self.isMovingAlongPath;
}

- (double)estimatedTimeToCompleteCurrentPath {
    @synchronized(self) {
        if (!self.isMovingAlongPath || !self.pathLocations || self.currentPathIndex >= self.pathLocations.count) {
            return 0.0;
        }
        
        // Calculate remaining locations
        NSInteger remainingLocations = self.pathLocations.count - self.currentPathIndex;
        
        // Each location represents approximately 1 second at configured speed
        return (double)remainingLocations;
    }
}

@end 