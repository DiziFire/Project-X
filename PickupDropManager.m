#import "PickupDropManager.h"
#import "ProjectXLogging.h"
#import "UberFareCalculator.h"

// Keys for NSUserDefaults persistence
NSString * const kPickupLocationKey = @"com.weaponx.pickupLocation";
NSString * const kDropLocationKey = @"com.weaponx.dropLocation";

@implementation PickupDropManager

+ (instancetype)sharedManager {
    NSLog(@"[WeaponX Debug] PickupDropManager - sharedManager called");
    static PickupDropManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
        NSLog(@"[WeaponX Debug] PickupDropManager - Created sharedManager instance: %@", sharedManager);
    });
    return sharedManager;
}

- (instancetype)init {
    NSLog(@"[WeaponX Debug] PickupDropManager - init called");
    if (self = [super init]) {
        // Load saved locations on initialization
        [self loadSavedLocations];
        
        // Verify they were loaded properly
        if (self.pickupLocation) {
            NSLog(@"[WeaponX Debug] PickupDropManager - Loaded pickup: lat=%@, lng=%@", 
                  self.pickupLocation[@"latitude"], self.pickupLocation[@"longitude"]);
        } else {
            NSLog(@"[WeaponX Debug] PickupDropManager - No pickup location loaded");
        }
        
        if (self.dropLocation) {
            NSLog(@"[WeaponX Debug] PickupDropManager - Loaded drop: lat=%@, lng=%@", 
                  self.dropLocation[@"latitude"], self.dropLocation[@"longitude"]);
        } else {
            NSLog(@"[WeaponX Debug] PickupDropManager - No drop location loaded");
        }
        
        // Register for app lifecycle notifications to ensure persistence
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(appWillResignActive:) 
               name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(appWillTerminate:) 
               name:UIApplicationWillTerminateNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    // Unregister notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// App lifecycle handlers to ensure data is saved
- (void)appWillResignActive:(NSNotification *)notification {
    NSLog(@"[WeaponX Debug] PickupDropManager - App will resign active, forcing NSUserDefaults sync");
    // Force a synchronize when app goes to background
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)appWillTerminate:(NSNotification *)notification {
    NSLog(@"[WeaponX Debug] PickupDropManager - App will terminate, forcing NSUserDefaults sync");
    // Final save before app terminates
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)initWithMapWebView:(WKWebView *)webView {
    NSLog(@"[WeaponX Debug] PickupDropManager - initWithMapWebView called");
    self.mapWebView = webView;
    
    // Update markers if locations are loaded
    if (self.pickupLocation || self.dropLocation) {
        NSLog(@"[WeaponX Debug] PickupDropManager - Locations exist, updating markers on map");
        // Delay slightly to ensure map is ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self updatePickupDropMarkersOnMap];
        });
    } else {
        NSLog(@"[WeaponX Debug] PickupDropManager - No locations to display on map");
    }
}

#pragma mark - Location Management

- (void)removePickupLocation {
    NSLog(@"[WeaponX Debug] Removing pickup location");
    self.pickupLocation = nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kPickupLocationKey];
    [defaults synchronize];
    [self updatePickupDropMarkersOnMap];
}

- (void)removeDropLocation {
    NSLog(@"[WeaponX Debug] Removing drop location");
    self.dropLocation = nil;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kDropLocationKey];
    [defaults synchronize];
    [self updatePickupDropMarkersOnMap];
}


- (void)savePickupLocation:(NSDictionary *)location {
    NSLog(@"[WeaponX Debug] PickupDropManager - savePickupLocation called with: %@", location);
    
    // Explicitly check for valid data
    if (!location) {
        NSLog(@"[WeaponX Error] Attempted to save nil pickup location");
        return;
    }
    
    if (!location[@"latitude"] || !location[@"longitude"]) {
        NSLog(@"[WeaponX Error] Attempted to save pickup location with missing coordinates: %@", location);
        return;
    }
    
    // Create a copy with just the necessary fields to avoid any serialization issues
    NSDictionary *locationToSave = @{
        @"latitude": location[@"latitude"],
        @"longitude": location[@"longitude"]
    };
    
    NSLog(@"[WeaponX Debug] PickupDropManager - Saving pickup location: %@", locationToSave);
    
    // Set the property with our clean copy
    self.pickupLocation = locationToSave;
    
    // Save to user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:locationToSave forKey:kPickupLocationKey];
    BOOL syncResult = [defaults synchronize];
    
    NSLog(@"[WeaponX Debug] PickupDropManager - NSUserDefaults synchronize result: %@", syncResult ? @"SUCCESS" : @"FAILED");
    NSLog(@"[WeaponX Debug] PickupDropManager - After saving, self.pickupLocation: %@", self.pickupLocation);
    
    // Verify data was saved by reading it back
    NSDictionary *verifyLocation = [defaults objectForKey:kPickupLocationKey];
    NSLog(@"[WeaponX Debug] PickupDropManager - Verification read from NSUserDefaults: %@", verifyLocation);
    
    PXLog(@"[WeaponX] Pickup location saved: %@, %@", 
         self.pickupLocation[@"latitude"], 
         self.pickupLocation[@"longitude"]);
}

- (void)saveDropLocation:(NSDictionary *)location {
    NSLog(@"[WeaponX Debug] PickupDropManager - saveDropLocation called with: %@", location);
    
    // Explicitly check for valid data
    if (!location) {
        NSLog(@"[WeaponX Error] Attempted to save nil drop location");
        return;
    }
    
    if (!location[@"latitude"] || !location[@"longitude"]) {
        NSLog(@"[WeaponX Error] Attempted to save drop location with missing coordinates: %@", location);
        return;
    }
    
    // Create a copy with just the necessary fields to avoid any serialization issues
    NSDictionary *locationToSave = @{
        @"latitude": location[@"latitude"],
        @"longitude": location[@"longitude"]
    };
    
    NSLog(@"[WeaponX Debug] PickupDropManager - Saving drop location: %@", locationToSave);
    
    // Set the property with our clean copy
    self.dropLocation = locationToSave;
    
    // Save to user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:locationToSave forKey:kDropLocationKey];
    BOOL syncResult = [defaults synchronize];
    
    NSLog(@"[WeaponX Debug] PickupDropManager - NSUserDefaults drop synchronize result: %@", syncResult ? @"SUCCESS" : @"FAILED");
    NSLog(@"[WeaponX Debug] PickupDropManager - After saving, self.dropLocation: %@", self.dropLocation);
    
    // Verify data was saved by reading it back
    NSDictionary *verifyLocation = [defaults objectForKey:kDropLocationKey];
    NSLog(@"[WeaponX Debug] PickupDropManager - Verification read from NSUserDefaults: %@", verifyLocation);
    
    PXLog(@"[WeaponX] Drop location saved: %@, %@", 
         self.dropLocation[@"latitude"], 
         self.dropLocation[@"longitude"]);
}

- (void)loadSavedLocations {
    NSLog(@"[WeaponX Debug] PickupDropManager - Loading saved locations");
    
    // Load pickup location
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *savedPickup = [defaults objectForKey:kPickupLocationKey];
    NSLog(@"[WeaponX Debug] PickupDropManager - Loaded pickup from NSUserDefaults: %@", savedPickup);
    
    if (savedPickup) {
        // Validate that the dictionary contains required keys
        if (savedPickup[@"latitude"] && savedPickup[@"longitude"]) {
            self.pickupLocation = savedPickup;
            PXLog(@"[WeaponX] Loaded saved pickup location: %@, %@", 
                 self.pickupLocation[@"latitude"], 
                 self.pickupLocation[@"longitude"]);
            NSLog(@"[WeaponX Debug] PickupDropManager - Set self.pickupLocation to: %@", self.pickupLocation);
        } else {
            NSLog(@"[WeaponX Error] Found invalid pickup location data in NSUserDefaults: %@", savedPickup);
        }
    } else {
        NSLog(@"[WeaponX Debug] PickupDropManager - No pickup location found in NSUserDefaults");
    }
    
    // Load drop location
    NSDictionary *savedDrop = [defaults objectForKey:kDropLocationKey];
    NSLog(@"[WeaponX Debug] PickupDropManager - Loaded drop from NSUserDefaults: %@", savedDrop);
    
    if (savedDrop) {
        // Validate that the dictionary contains required keys
        if (savedDrop[@"latitude"] && savedDrop[@"longitude"]) {
            self.dropLocation = savedDrop;
            PXLog(@"[WeaponX] Loaded saved drop location: %@, %@", 
                 self.dropLocation[@"latitude"], 
                 self.dropLocation[@"longitude"]);
            NSLog(@"[WeaponX Debug] PickupDropManager - Set self.dropLocation to: %@", self.dropLocation);
        } else {
            NSLog(@"[WeaponX Error] Found invalid drop location data in NSUserDefaults: %@", savedDrop);
        }
    } else {
        NSLog(@"[WeaponX Debug] PickupDropManager - No drop location found in NSUserDefaults");
    }
}

#pragma mark - Map Visualization

- (void)updatePickupDropMarkersOnMap {
    if (!self.mapWebView) {
        PXLog(@"[WeaponX] Map WebView not set for pickup/drop marker update");
        return;
    }

    // Always clear previous route if either pickup or drop is missing
    if (!(self.pickupLocation && self.dropLocation)) {
        NSString *clearRouteScript = @"if (window.directionsRenderer) { window.directionsRenderer.setMap(null); window.directionsRenderer = null; } if (window.routePath) { window.routePath.setMap(null); window.routePath = null; }";
        [self.mapWebView evaluateJavaScript:clearRouteScript completionHandler:nil];
    }
    
    NSLog(@"[WeaponX Debug] Updating pickup/drop markers on map");
    
    // JavaScript to update markers - simplified to avoid syntax errors
    NSMutableString *script = [NSMutableString stringWithString:@"(function() {\n"];
    
    // Clear existing pickup/drop markers
    [script appendString:@"  if (window.pickupMarker) { window.pickupMarker.setMap(null); }\n"];
    [script appendString:@"  if (window.dropMarker) { window.dropMarker.setMap(null); }\n"];
    [script appendString:@"  if (window.routePath) { window.routePath.setMap(null); }\n"];
    
    // Add pickup marker if exists
    if (self.pickupLocation) {
        double lat = [self.pickupLocation[@"latitude"] doubleValue];
        double lng = [self.pickupLocation[@"longitude"] doubleValue];
        
        [script appendFormat:@"  window.pickupMarker = new google.maps.Marker({\n"];
        [script appendFormat:@"    position: new google.maps.LatLng(%f, %f),\n", lat, lng];
        [script appendFormat:@"    map: map,\n"];
        [script appendFormat:@"    icon: {\n"];
        [script appendFormat:@"      url: 'https://maps.google.com/mapfiles/ms/icons/green-dot.png',\n"];
        [script appendFormat:@"      scaledSize: new google.maps.Size(40, 40),\n"];
        [script appendFormat:@"      anchor: new google.maps.Point(20, 40)\n"];
        [script appendFormat:@"    },\n"];
        [script appendFormat:@"    label: { text: 'P', color: '#FFFFFF', fontWeight: 'bold' }\n"];
        [script appendFormat:@"  });\n"];
        
        NSLog(@"[WeaponX Debug] Added pickup marker at %f, %f", lat, lng);
    }
    
    // Add drop marker if exists
    if (self.dropLocation) {
        double lat = [self.dropLocation[@"latitude"] doubleValue];
        double lng = [self.dropLocation[@"longitude"] doubleValue];
        
        [script appendFormat:@"  window.dropMarker = new google.maps.Marker({\n"];
        [script appendFormat:@"    position: new google.maps.LatLng(%f, %f),\n", lat, lng];
        [script appendFormat:@"    map: map,\n"];
        [script appendFormat:@"    icon: {\n"];
        [script appendFormat:@"      url: 'https://maps.google.com/mapfiles/ms/icons/orange-dot.png',\n"];
        [script appendFormat:@"      scaledSize: new google.maps.Size(40, 40),\n"];
        [script appendFormat:@"      anchor: new google.maps.Point(20, 40)\n"];
        [script appendFormat:@"    },\n"];
        [script appendFormat:@"    label: { text: 'D', color: '#FFFFFF', fontWeight: 'bold' }\n"];
        [script appendFormat:@"  });\n"];
        
        NSLog(@"[WeaponX Debug] Added drop marker at %f, %f", lat, lng);
            
        // If both pickup and drop exist, draw a path between them
        if (self.pickupLocation) {
            double pickupLat = [self.pickupLocation[@"latitude"] doubleValue];
            double pickupLng = [self.pickupLocation[@"longitude"] doubleValue];
            
            // Remove any existing route
            [script appendFormat:@"  if (window.routePath) { window.routePath.setMap(null); }\n"];
            [script appendFormat:@"  if (window.directionsRenderer) { window.directionsRenderer.setMap(null); }\n"];
            // Use DirectionsService to get the real route
            [script appendFormat:@"  var directionsService = new google.maps.DirectionsService();\n"];
            [script appendFormat:@"  var directionsRenderer = new google.maps.DirectionsRenderer({suppressMarkers: true, polylineOptions: {strokeColor: '#2196F3', strokeWeight: 4}});\n"];
            [script appendFormat:@"  directionsRenderer.setMap(map);\n"];
            [script appendFormat:@"  window.directionsRenderer = directionsRenderer;\n"];
            [script appendFormat:@"  directionsService.route({\n"];
            [script appendFormat:@"    origin: {lat: %f, lng: %f},\n", pickupLat, pickupLng];
            [script appendFormat:@"    destination: {lat: %f, lng: %f},\n", lat, lng];
            [script appendFormat:@"    travelMode: google.maps.TravelMode.DRIVING\n"];
            [script appendFormat:@"  }, function(response, status) {\n"];
            [script appendFormat:@"    if (status === 'OK') {\n"];
            [script appendFormat:@"      directionsRenderer.setDirections(response);\n"];
            [script appendFormat:@"    } else {\n"];
            [script appendFormat:@"      console.error('Directions request failed due to ' + status);\n"];
            [script appendFormat:@"    }\n"];
            [script appendFormat:@"  });\n"];
            NSLog(@"[WeaponX Debug] Added DirectionsService-based route between pickup and drop");
        }
    }
    
    [script appendString:@"  return true;\n"];
    [script appendString:@"})();"];
    
    // For debugging, log the complete script
    NSLog(@"[WeaponX Debug] JavaScript for markers: %@", script);
    
    // Execute the JavaScript
    [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[WeaponX] Error updating pickup/drop markers: %@", error);
            NSLog(@"[WeaponX Debug] Full JavaScript error: %@", error);
        } else {
            NSLog(@"[WeaponX Debug] Successfully updated map markers: %@", result);
        }
    }];
}

#pragma mark - Path Creation

- (NSArray *)createPathFromPickupToDrop {
    // Check if both pickup and drop locations exist
    if (![self hasPickupAndDropLocations]) {
        return nil;
    }
    
    // Create waypoints from pickup to drop
    NSArray *waypoints = @[
        [NSValue valueWithCGPoint:CGPointMake(
            [self.pickupLocation[@"latitude"] doubleValue], 
            [self.pickupLocation[@"longitude"] doubleValue])],
        [NSValue valueWithCGPoint:CGPointMake(
            [self.dropLocation[@"latitude"] doubleValue], 
            [self.dropLocation[@"longitude"] doubleValue])]
    ];
    
    return waypoints;
}

#pragma mark - Helper Methods

- (BOOL)hasPickupLocation {
    BOOL result = (self.pickupLocation != nil);
    NSLog(@"[WeaponX Debug] PickupDropManager - hasPickupLocation called, result: %@, value: %@", result ? @"YES" : @"NO", self.pickupLocation);
    return result;
}

- (BOOL)hasDropLocation {
    BOOL result = (self.dropLocation != nil);
    NSLog(@"[WeaponX Debug] PickupDropManager - hasDropLocation called, result: %@, value: %@", result ? @"YES" : @"NO", self.dropLocation);
    return result;
}

- (BOOL)hasPickupAndDropLocations {
    BOOL result = ([self hasPickupLocation] && [self hasDropLocation]);
    NSLog(@"[WeaponX Debug] PickupDropManager - hasPickupAndDropLocations called, result: %@", result ? @"YES" : @"NO");
    return result;
}

#pragma mark - Uber Fare Estimation

- (void)configureUberWithAppId:(NSString *)appId clientSecret:(NSString *)clientSecret {
    [[UberFareCalculator sharedCalculator] initWithApplicationId:appId clientSecret:clientSecret];
    NSLog(@"[WeaponX] Configured Uber fare calculator with application ID: %@", appId);
}

- (void)calculateUberFareWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
    // Check if both pickup and drop locations are set
    if (![self hasPickupAndDropLocations]) {
        NSError *missingLocationError = [NSError errorWithDomain:@"PickupDropManagerErrorDomain" 
                                                          code:1001 
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Both pickup and drop locations must be set"}];
        if (completion) {
            completion(nil, missingLocationError);
        }
        return;
    }
    
    // Get coordinates from locations
    CLLocationCoordinate2D pickup = [self pickupCoordinate];
    CLLocationCoordinate2D drop = [self dropCoordinate];
    
    // Use UberFareCalculator to get the fare
    [[UberFareCalculator sharedCalculator] calculateFareBetweenPickup:pickup 
                                                             andDrop:drop 
                                                          completion:^(NSDictionary * _Nullable fareEstimate, NSError * _Nullable error) {
        // Ensure callback on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"[WeaponX] ❌ Uber fare calculation error: %@", error);
                if (completion) {
                    completion(nil, error);
                }
                return;
            }
            
            // Format the fare estimate for display
            NSMutableDictionary *formattedEstimate = [NSMutableDictionary dictionaryWithDictionary:fareEstimate];
            
            // Add calculated distance for display
            if (fareEstimate[@"distance"]) {
                double distanceValue = [fareEstimate[@"distance"] doubleValue];
                formattedEstimate[@"formattedDistance"] = [NSString stringWithFormat:@"%.2f miles", distanceValue];
            }
            
            // Add formatted duration
            if (fareEstimate[@"duration"]) {
                int durationSeconds = [fareEstimate[@"duration"] intValue];
                int minutes = durationSeconds / 60;
                formattedEstimate[@"formattedDuration"] = [NSString stringWithFormat:@"%d min", minutes];
            }
            
            // Parse fare range if present
            NSString *displayName = fareEstimate[@"display_name"] ?: @"Uber";
            NSString *estimate = fareEstimate[@"estimate"] ?: @"Unavailable";
            formattedEstimate[@"summary"] = [NSString stringWithFormat:@"%@: %@", displayName, estimate];
            
            NSLog(@"[WeaponX] ✅ Uber fare estimate: %@", formattedEstimate[@"summary"]);
            
            if (completion) {
                completion(formattedEstimate, nil);
            }
        });
    }];
}

- (CLLocationCoordinate2D)pickupCoordinate {
    CLLocationCoordinate2D coordinate = kCLLocationCoordinate2DInvalid;
    
    if (self.pickupLocation) {
        double latitude = [self.pickupLocation[@"latitude"] doubleValue];
        double longitude = [self.pickupLocation[@"longitude"] doubleValue];
        coordinate = CLLocationCoordinate2DMake(latitude, longitude);
    }
    
    return coordinate;
}

- (CLLocationCoordinate2D)dropCoordinate {
    CLLocationCoordinate2D coordinate = kCLLocationCoordinate2DInvalid;
    
    if (self.dropLocation) {
        double latitude = [self.dropLocation[@"latitude"] doubleValue];
        double longitude = [self.dropLocation[@"longitude"] doubleValue];
        coordinate = CLLocationCoordinate2DMake(latitude, longitude);
    }
    
    return coordinate;
}

@end 