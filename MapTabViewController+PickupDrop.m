#import "MapTabViewController+PickupDrop.h"
#import "PickupDropManager.h"
#import "ProjectXLogging.h"
#import <UIKit/UIPasteboard.h>

// Import key constants
extern NSString * const kPickupLocationKey;
extern NSString * const kDropLocationKey;

// Forward declarations for properties not directly exposed in the header
@interface MapTabViewController ()
@property (nonatomic, strong) UIView *searchBarContainer;
@property (nonatomic, strong) NSDictionary *currentPinLocation;
@property (nonatomic, strong) UIView *gpsAdvancedPanel;
@property (nonatomic, strong) UILabel *pathStatusLabel;
@end

// Forward declarations for private methods
@interface MapTabViewController (PrivateMethods)
- (void)showToastWithMessage:(NSString *)message;
- (void)setPathWaypoints:(NSArray *)waypoints;
- (void)showCoordinates:(double)latitude longitude:(double)longitude;
@end

@implementation MapTabViewController (PickupDrop)

#pragma mark - Setup Methods

- (void)setupPickupDropManager {
    // Create the pickup/drop manager
    self.pickupDropManager = [PickupDropManager sharedManager];
    
    // Initialize with the map webview
    [self.pickupDropManager initWithMapWebView:self.mapWebView];
    
    // Initialize Uber API with credentials
    [self.pickupDropManager configureUberWithAppId:@"x3Ver_fJtiRM9tmckasEu0aXymBlYjDX" 
                                    clientSecret:@"s7PttLsUrggdRGr5cVXHIT5ezU5N6Jsxbs-tbNuR"];
    
    // Log the manager instance for debugging
    NSLog(@"[WeaponX Debug] Created PickupDropManager instance: %@", self.pickupDropManager);
    
    // Verify the manager is working by checking its properties
    NSLog(@"[WeaponX Debug] Initial manager.pickupLocation: %@", self.pickupDropManager.pickupLocation);
    NSLog(@"[WeaponX Debug] Initial manager.dropLocation: %@", self.pickupDropManager.dropLocation);
    
    // We're now using the plus menu for Uber fare, so no need to call this
    // [self setupUberFareButton];
}

- (void)setupPickupDropButton {
    // Determine if in dark mode
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    
    // Create plus button
    self.pickupDropButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *plusIcon = [UIImage systemImageNamed:@"plus.circle.fill"];
    [self.pickupDropButton setImage:plusIcon forState:UIControlStateNormal];
    self.pickupDropButton.tintColor = isDarkMode ? 
        [UIColor colorWithRed:0.1 green:0.8 blue:0.4 alpha:1.0] : 
        [UIColor systemGreenColor];
    self.pickupDropButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pickupDropButton addTarget:self action:@selector(pickupDropButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Add button to the view (not to the search bar container)
    [self.view addSubview:self.pickupDropButton];
    
    // Position the button below the search bar, next to where the search magnifier icon would be
    [NSLayoutConstraint activateConstraints:@[
        [self.pickupDropButton.topAnchor constraintEqualToAnchor:self.searchBarContainer.bottomAnchor constant:15],
        [self.pickupDropButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:60], // Position it near the magnifier icon
        [self.pickupDropButton.widthAnchor constraintEqualToConstant:44],
        [self.pickupDropButton.heightAnchor constraintEqualToConstant:44]
    ]];
    
    // Create pickup/drop menu (initially hidden)
    self.pickupDropMenuView = [[UIView alloc] init];
    self.pickupDropMenuView.backgroundColor = isDarkMode ? 
        [UIColor colorWithWhite:0.2 alpha:0.95] : 
        [UIColor colorWithWhite:1.0 alpha:0.95];
    self.pickupDropMenuView.layer.cornerRadius = 8;
    self.pickupDropMenuView.clipsToBounds = YES;
    self.pickupDropMenuView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.pickupDropMenuView.layer.shadowOffset = CGSizeMake(0, 2);
    self.pickupDropMenuView.layer.shadowOpacity = 0.2;
    self.pickupDropMenuView.layer.shadowRadius = 4;
    self.pickupDropMenuView.layer.masksToBounds = NO;
    self.pickupDropMenuView.translatesAutoresizingMaskIntoConstraints = NO;
    self.pickupDropMenuView.hidden = YES;
    [self.view addSubview:self.pickupDropMenuView];
    
    // Update dropdown menu position to appear below the new plus button position
    [NSLayoutConstraint activateConstraints:@[
        [self.pickupDropMenuView.topAnchor constraintEqualToAnchor:self.pickupDropButton.bottomAnchor constant:8],
        [self.pickupDropMenuView.leadingAnchor constraintEqualToAnchor:self.pickupDropButton.leadingAnchor],
        [self.pickupDropMenuView.widthAnchor constraintEqualToConstant:200], // Wider to accommodate ellipsis buttons
        [self.pickupDropMenuView.heightAnchor constraintEqualToConstant:3 * 50] // 3 options * 50pts height (taller)
    ]];
    
    // Add menu options
    NSArray *options = @[@"Set Pickup", @"Set Drop", @"GET UBER FAIR"];
    NSArray *icons = @[@"mappin.circle.fill", @"mappin.and.ellipse", @"car.fill"];
    NSArray *colors = @[
        isDarkMode ? [UIColor systemGreenColor] : [UIColor systemGreenColor],
        isDarkMode ? [UIColor systemOrangeColor] : [UIColor systemOrangeColor],
        isDarkMode ? [UIColor blackColor] : [UIColor blackColor]
    ];
    
    for (NSInteger i = 0; i < options.count; i++) {
        // Create option row container
        UIView *optionRow = [[UIView alloc] init];
        optionRow.translatesAutoresizingMaskIntoConstraints = NO;
        [self.pickupDropMenuView addSubview:optionRow];
        
        // Create option button container (left side)
        UIView *optionContainer = [[UIView alloc] init];
        optionContainer.translatesAutoresizingMaskIntoConstraints = NO;
        optionContainer.backgroundColor = [UIColor clearColor];
        [optionRow addSubview:optionContainer];
        
        // Create ellipsis container (right side)
        UIView *ellipsisContainer = [[UIView alloc] init];
        ellipsisContainer.translatesAutoresizingMaskIntoConstraints = NO;
        ellipsisContainer.backgroundColor = [UIColor clearColor];
        [optionRow addSubview:ellipsisContainer];
        
        // Create main option button
        UIButton *optionButton;
        
        if (@available(iOS 15.0, *)) {
            // Use modern UIButtonConfiguration for iOS 15+
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            
            // Configure button appearance
            config.imagePlacement = NSDirectionalRectEdgeLeading;
            config.imagePadding = 10;
            config.contentInsets = NSDirectionalEdgeInsetsMake(0, 5, 0, 0);
            config.title = options[i];
            config.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
            
            UIImage *image = [UIImage systemImageNamed:icons[i]];
            config.image = image;
            
            optionButton = [UIButton buttonWithConfiguration:config primaryAction:nil];
        } else {
            // Legacy approach for iOS 14 and earlier
            optionButton = [UIButton buttonWithType:UIButtonTypeSystem];
            [optionButton setTitle:options[i] forState:UIControlStateNormal];
            [optionButton setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];
            optionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            
            // Using deprecated properties but only for older iOS versions
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            optionButton.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
            optionButton.imageEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
            #pragma clang diagnostic pop
        }
        
        optionButton.tag = i; // Use tag to identify option (0=pickup, 1=drop, 2=uber)
        optionButton.tintColor = colors[i];
        optionButton.translatesAutoresizingMaskIntoConstraints = NO;
        [optionButton addTarget:self action:@selector(pickupDropOptionSelected:) forControlEvents:UIControlEventTouchUpInside];
        [optionContainer addSubview:optionButton];
        
        // Add ellipsis button (as a separate button) - not for the Uber option
        if (i < 2) { // Only for pickup and drop options
        UIButton *ellipsisButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *ellipsisIcon = [UIImage systemImageNamed:@"ellipsis.circle.fill"];
        [ellipsisButton setImage:ellipsisIcon forState:UIControlStateNormal];
        ellipsisButton.tintColor = colors[i];
        ellipsisButton.translatesAutoresizingMaskIntoConstraints = NO;
        ellipsisButton.tag = i; // Same tag as option button (0=pickup, 1=drop)
        [ellipsisButton addTarget:self action:@selector(ellipsisButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [ellipsisContainer addSubview:ellipsisButton];
            
            // Set up constraints for ellipsis button - make it larger and centered
            [NSLayoutConstraint activateConstraints:@[
                [ellipsisButton.centerXAnchor constraintEqualToAnchor:ellipsisContainer.centerXAnchor],
                [ellipsisButton.centerYAnchor constraintEqualToAnchor:ellipsisContainer.centerYAnchor],
                [ellipsisButton.widthAnchor constraintEqualToConstant:40], // Larger
                [ellipsisButton.heightAnchor constraintEqualToConstant:40]  // Larger
            ]];
        }
        
        // Set up constraints for the row
        [NSLayoutConstraint activateConstraints:@[
            [optionRow.leadingAnchor constraintEqualToAnchor:self.pickupDropMenuView.leadingAnchor],
            [optionRow.trailingAnchor constraintEqualToAnchor:self.pickupDropMenuView.trailingAnchor],
            [optionRow.heightAnchor constraintEqualToConstant:50], // Taller for better tappability
            [optionRow.topAnchor constraintEqualToAnchor:self.pickupDropMenuView.topAnchor constant:i * 50]
        ]];
        
        // Set up constraints for option container and ellipsis container
        [NSLayoutConstraint activateConstraints:@[
            // Option container (left 70% for pickup/drop, 100% for Uber)
            [optionContainer.leadingAnchor constraintEqualToAnchor:optionRow.leadingAnchor],
            [optionContainer.topAnchor constraintEqualToAnchor:optionRow.topAnchor],
            [optionContainer.bottomAnchor constraintEqualToAnchor:optionRow.bottomAnchor],
            [optionContainer.widthAnchor constraintEqualToAnchor:optionRow.widthAnchor multiplier:(i < 2 ? 0.7 : 1.0)],
        ]];
            
        // Only add ellipsis container constraints for pickup and drop options
        if (i < 2) {
            [NSLayoutConstraint activateConstraints:@[
            // Ellipsis container (right 30%)
            [ellipsisContainer.leadingAnchor constraintEqualToAnchor:optionContainer.trailingAnchor],
            [ellipsisContainer.trailingAnchor constraintEqualToAnchor:optionRow.trailingAnchor],
            [ellipsisContainer.topAnchor constraintEqualToAnchor:optionRow.topAnchor],
            [ellipsisContainer.bottomAnchor constraintEqualToAnchor:optionRow.bottomAnchor]
        ]];
        }
        
        // Set up constraints for option button
        [NSLayoutConstraint activateConstraints:@[
            [optionButton.leadingAnchor constraintEqualToAnchor:optionContainer.leadingAnchor constant:5],
            [optionButton.trailingAnchor constraintEqualToAnchor:optionContainer.trailingAnchor],
            [optionButton.topAnchor constraintEqualToAnchor:optionContainer.topAnchor],
            [optionButton.bottomAnchor constraintEqualToAnchor:optionContainer.bottomAnchor]
        ]];
        
        // Add separator line except for the last item
        if (i < options.count - 1) {
            UIView *separator = [[UIView alloc] init];
            separator.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.5];
            separator.translatesAutoresizingMaskIntoConstraints = NO;
            [self.pickupDropMenuView addSubview:separator];
            
            [NSLayoutConstraint activateConstraints:@[
                [separator.leadingAnchor constraintEqualToAnchor:self.pickupDropMenuView.leadingAnchor constant:10],
                [separator.trailingAnchor constraintEqualToAnchor:self.pickupDropMenuView.trailingAnchor constant:-10],
                [separator.heightAnchor constraintEqualToConstant:0.5],
                [separator.topAnchor constraintEqualToAnchor:optionRow.bottomAnchor]
            ]];
        }
    }
    
    // No need to call setupUberFareButton since we're now integrating it into the + menu
}

#pragma mark - Action Handlers

// Toggle the pickup/drop menu
- (void)pickupDropButtonTapped:(UIButton *)sender {
    // Toggle visibility of pickup/drop menu
    self.pickupDropMenuView.hidden = !self.pickupDropMenuView.hidden;
    
    // Add subtle animation
    if (!self.pickupDropMenuView.hidden) {
        self.pickupDropMenuView.alpha = 0;
        self.pickupDropMenuView.transform = CGAffineTransformMakeScale(0.95, 0.95);
        
        [UIView animateWithDuration:0.2 animations:^{
            self.pickupDropMenuView.alpha = 1;
            self.pickupDropMenuView.transform = CGAffineTransformIdentity;
        }];
    }
}

// Handle pickup/drop option selection
- (void)pickupDropOptionSelected:(UIButton *)sender {
    // Hide menu
    self.pickupDropMenuView.hidden = YES;
    
    // Determine option selected by tag
    NSInteger selectedOption = sender.tag;
    
    // Handle based on selected option
    if (selectedOption == 0 || selectedOption == 1) {
        // Pickup (0) or Drop (1) options
        BOOL isPickup = (selectedOption == 0);
    
    NSLog(@"[WeaponX Debug] pickupDropOptionSelected - isPickup: %d", isPickup);
    NSLog(@"[WeaponX Debug] currentPinLocation exists: %@", self.currentPinLocation ? @"YES" : @"NO");
    NSLog(@"[WeaponX Debug] PickupDropManager exists: %@", self.pickupDropManager ? @"YES" : @"NO");
    
    // Verify that PickupDropManager is properly initialized
    if (!self.pickupDropManager) {
        NSLog(@"[WeaponX Error] PickupDropManager is nil, recreating...");
        [self setupPickupDropManager];
        
        if (!self.pickupDropManager) {
            NSLog(@"[WeaponX Error] Failed to create PickupDropManager");
            [self showToastWithMessage:@"Error: Cannot save location"];
            return;
        }
    }
    
    if (self.currentPinLocation) {
        NSLog(@"[WeaponX Debug] Current pin location: %@", self.currentPinLocation);
        
        // Create a clean copy of the current pin location with only lat/long
        NSDictionary *location = @{
            @"latitude": self.currentPinLocation[@"latitude"],
            @"longitude": self.currentPinLocation[@"longitude"]
        };
        
        NSLog(@"[WeaponX Debug] Location to save: %@", location);
        
        // Save the location to the pickup/drop manager - add extra logging
        BOOL saveSuccess = NO;
        if (isPickup) {
            NSLog(@"[WeaponX Debug] About to call savePickupLocation on manager: %@", self.pickupDropManager);
            [self.pickupDropManager savePickupLocation:location];
            saveSuccess = [self.pickupDropManager hasPickupLocation];
            if (saveSuccess) {
                [self showToastWithMessage:@"Pickup location set"];
            } else {
                [self showToastWithMessage:@"Error: Failed to save pickup location. Please try again."];
                NSLog(@"[WeaponX Error] Manager failed to save pickup location");
            }
        } else {
            NSLog(@"[WeaponX Debug] About to call saveDropLocation on manager: %@", self.pickupDropManager);
            [self.pickupDropManager saveDropLocation:location];
            saveSuccess = [self.pickupDropManager hasDropLocation];
            if (saveSuccess) {
                [self showToastWithMessage:@"Drop location set"];
            } else {
                [self showToastWithMessage:@"Error: Failed to save drop location. Please try again."];
                NSLog(@"[WeaponX Error] Manager failed to save drop location");
            }
        }
        
        // Update map markers - make sure webview is initialized
        if (self.pickupDropManager.mapWebView == nil) {
            NSLog(@"[WeaponX Debug] Initializing map web view for PickupDropManager");
            [self.pickupDropManager initWithMapWebView:self.mapWebView];
        }
        [self.pickupDropManager updatePickupDropMarkersOnMap];
    } else {
        // No pin currently set, show error
        NSString *message = [NSString stringWithFormat:@"Please place a pin on the map first to set %@ location", 
                            isPickup ? @"pickup" : @"drop"];
        [self showToastWithMessage:message];
        NSLog(@"[WeaponX Debug] No pin location set when trying to save %@ location", isPickup ? @"pickup" : @"drop");
        }
    } else if (selectedOption == 2) {
        // GET UBER FAIR option selected
        [self showUberFareEstimate];
    }
}

// Handle ellipsis button tap (show location options)
- (void)ellipsisButtonTapped:(UIButton *)sender {
    // Hide the main pickup/drop menu
    self.pickupDropMenuView.hidden = YES;
    
    // Determine if pickup or drop options
    BOOL isPickup = (sender.tag == 0);
    
    NSLog(@"[WeaponX Debug] ellipsisButtonTapped - isPickup: %d", isPickup);
    
    // Check if location exists
    NSDictionary *location = isPickup ? self.pickupDropManager.pickupLocation : self.pickupDropManager.dropLocation;
    
    NSLog(@"[WeaponX Debug] Location from manager: %@", location);
    NSLog(@"[WeaponX Debug] Manager hasPickupLocation: %@", [self.pickupDropManager hasPickupLocation] ? @"YES" : @"NO");
    
    if (!location) {
        [self showToastWithMessage:[NSString stringWithFormat:@"No %@ location set", isPickup ? @"pickup" : @"drop"]];
        NSLog(@"[WeaponX Debug] No %@ location found when tapping ellipsis", isPickup ? @"pickup" : @"drop");
        return;
    }
    
    // Create alert controller with options
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isPickup ? @"Pickup Location" : @"Drop Location" 
                                                               message:nil 
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Option to show coordinates
    [alert addAction:[UIAlertAction actionWithTitle:@"Show Coordinates" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // Format coordinates with 6 decimal places
        double lat = [location[@"latitude"] doubleValue];
        double lng = [location[@"longitude"] doubleValue];
        NSString *coordsString = [NSString stringWithFormat:@"Lat: %.6f, Lng: %.6f", lat, lng];
        
        // Show coordinates in toast
        [self showToastWithMessage:coordsString];
        
        // Copy to clipboard
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = coordsString;
    }]];
    
    // Option to show on map
    [alert addAction:[UIAlertAction actionWithTitle:@"Show on Map" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        double lat = [location[@"latitude"] doubleValue];
        double lng = [location[@"longitude"] doubleValue];
        
        // Center map on location without toggling the pin button
        [self centerMapAndPlacePinAtLatitude:lat longitude:lng shouldTogglePinButton:NO];
    }]];
    
    // Option to remove
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove Location" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // Remove from manager
        if (isPickup) {
            [self.pickupDropManager removePickupLocation];
        } else {
            [self.pickupDropManager removeDropLocation];
        }
        
        // Update map markers
        [self.pickupDropManager updatePickupDropMarkersOnMap];
        
        // Show confirmation
        [self showToastWithMessage:[NSString stringWithFormat:@"%@ location removed", 
                                   isPickup ? @"Pickup" : @"Drop"]];
    }]];
    
    // Cancel option
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Present the alert
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Load Saved Locations

// Load saved pickup and drop locations from NSUserDefaults
- (void)loadSavedPickupDropLocations {
    NSLog(@"[WeaponX Debug] Loading saved pickup/drop locations");
    
    // Make sure the manager has the web view
    if (self.pickupDropManager.mapWebView == nil && self.mapWebView != nil) {
        NSLog(@"[WeaponX Debug] Setting map web view for PickupDropManager during loadSavedPickupDropLocations");
        [self.pickupDropManager initWithMapWebView:self.mapWebView];
    }
    
    [self.pickupDropManager loadSavedLocations];
    
    // Update UI with loaded locations
    [self.pickupDropManager updatePickupDropMarkersOnMap];
}

#pragma mark - Path Creation

// Create a path between pickup and drop locations
- (void)createPathFromPickupToDrop {
    // Get pickup and drop locations
    NSDictionary *pickup = self.pickupDropManager.pickupLocation;
    NSDictionary *drop = self.pickupDropManager.dropLocation;
    if (!pickup || !drop) {
        [self showToastWithMessage:@"Set both pickup and drop locations first!"];
        return;
    }
    // Validate pickup and drop dictionaries
    if (!pickup[@"latitude"] || !pickup[@"longitude"] || !drop[@"latitude"] || !drop[@"longitude"]) {
        [self showToastWithMessage:@"Invalid pickup or drop location data. Please reset locations."];
        NSLog(@"[WeaponX Error] Invalid pickup or drop dictionary: pickup=%@, drop=%@", pickup, drop);
        return;
    }
    double pickupLat = [pickup[@"latitude"] doubleValue];
    double pickupLng = [pickup[@"longitude"] doubleValue];
    double dropLat = [drop[@"latitude"] doubleValue];
    double dropLng = [drop[@"longitude"] doubleValue];
    
    // Build Directions API URL
    NSString *apiKey = @"AIzaSyCXF2ySIyCntOgy53QnqeeqNV_P_9ShfSY";
    NSString *urlString = [NSString stringWithFormat:@"https://maps.googleapis.com/maps/api/directions/json?origin=%f,%f&destination=%f,%f&mode=driving&key=%@", pickupLat, pickupLng, dropLat, dropLng, apiKey];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"Failed to fetch route from Google Directions API!"];
            });
            return;
        }
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json || ![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"Invalid response from Google Directions API!"];
            });
            return;
        }
        NSArray *routes = json[@"routes"];
        if (!routes || ![routes isKindOfClass:[NSArray class]] || routes.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"No route found between pickup and drop!"];
            });
            return;
        }
        NSDictionary *route = routes[0];
        NSDictionary *overviewPolyline = route[@"overview_polyline"];
        NSString *polyline = overviewPolyline[@"points"];
        if (!polyline) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"No polyline found in route!"];
            });
            return;
        }
        // Decode polyline
        NSArray *decodedCoords = [self decodePolyline:polyline];
        if (!decodedCoords || decodedCoords.count < 2) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showToastWithMessage:@"Failed to decode polyline!"];
            });
            return;
        }
        // Convert to waypoints (NSValue with CGPoint)
        NSMutableArray *waypoints = [NSMutableArray arrayWithCapacity:decodedCoords.count];
        for (NSDictionary *coord in decodedCoords) {
            double lat = [coord[@"lat"] doubleValue];
            double lng = [coord[@"lng"] doubleValue];
            [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(lat, lng)]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setPathWaypoints:waypoints];
            self.pathStatusLabel.text = @"Status: Path Created (pickup to drop)";
            self.pathStatusLabel.textColor = [UIColor systemGreenColor];
            UIButton *startStopButton = [self.gpsAdvancedPanel viewWithTag:1002];
            [startStopButton setTitle:@"Start Movement" forState:UIControlStateNormal];
            [startStopButton setBackgroundColor:[UIColor systemGreenColor]];
            [self showToastWithMessage:@"Path created from pickup to drop (road-following)!"];
        });
    }];
    [task resume];
}

// Polyline decoding helper (Google Encoded Polyline Algorithm Format)
- (NSArray *)decodePolyline:(NSString *)encoded {
    NSMutableArray *coordinates = [NSMutableArray array];
    NSInteger len = [encoded length];
    NSInteger index = 0;
    NSInteger lat = 0, lng = 0;
    while (index < len) {
        NSInteger b, shift = 0, result = 0;
        do {
            b = [encoded characterAtIndex:index++] - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20);
        NSInteger dlat = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lat += dlat;
        shift = 0;
        result = 0;
        do {
            b = [encoded characterAtIndex:index++] - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20);
        NSInteger dlng = ((result & 1) ? ~(result >> 1) : (result >> 1));
        lng += dlng;
        double finalLat = lat * 1e-5;
        double finalLng = lng * 1e-5;
        [coordinates addObject:@{ @"lat": @(finalLat), @"lng": @(finalLng) }];
    }
    return coordinates;
}

#pragma mark - Map Methods

// Center map on location and place pin - with option to toggle pin/unpin button
- (void)centerMapAndPlacePinAtLatitude:(double)latitude longitude:(double)longitude shouldTogglePinButton:(BOOL)shouldToggle {
    // Create JavaScript to center map and place pin
    NSString *script = [NSString stringWithFormat:@"(function() { \
        var latLng = new google.maps.LatLng(%f, %f); \
        map.setCenter(latLng); \
        map.setZoom(17); \
        placeCustomPin(latLng, false); \
        return { success: true, lat: %f, lng: %f }; \
    })();", latitude, longitude, latitude, longitude];
    
    [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[WeaponX] Error centering map: %@", error);
            [self showToastWithMessage:@"Error showing location on map"];
        } else {
            // Update current pin location
            self.currentPinLocation = @{
                @"latitude": @(latitude),
                @"longitude": @(longitude),
                @"isPinned": @NO
            };
            
            // Show coordinates
            [self showCoordinates:latitude longitude:longitude];
            
            // Only update pin/unpin button UI if requested
            if (shouldToggle) {
                self.unpinButton.hidden = NO;
                self.pinButton.hidden = YES;
            }
            
            // Show toast confirming view
            [self showToastWithMessage:@"Location shown on map"];
        }
    }];
}

#pragma mark - Uber Fare Estimation

- (void)setupUberAPIWithAppId:(NSString *)appId clientSecret:(NSString *)clientSecret {
    // Configure the PickupDropManager with Uber API credentials
    [self.pickupDropManager configureUberWithAppId:appId clientSecret:clientSecret];
    NSLog(@"[WeaponX] Uber API configured in MapTabViewController");
}

- (void)setupUberFareButton {
    // Create a circular button with "U" text
    UIButton *uberButton = [UIButton buttonWithType:UIButtonTypeSystem];
    uberButton.frame = CGRectMake(20, self.view.bounds.size.height - 190, 50, 50);
    
    // Use Uber's black color for the button
    uberButton.backgroundColor = [UIColor blackColor];
    uberButton.tintColor = [UIColor whiteColor];
    
    // Make it circular
    uberButton.layer.cornerRadius = 25;
    uberButton.layer.masksToBounds = YES;
    
    // Add drop shadow for depth
    uberButton.layer.shadowColor = [UIColor blackColor].CGColor;
    uberButton.layer.shadowOffset = CGSizeMake(0, 2);
    uberButton.layer.shadowRadius = 4;
    uberButton.layer.shadowOpacity = 0.3;
    
    // Bold font for the "U"
    uberButton.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightHeavy];
    [uberButton setTitle:@"U" forState:UIControlStateNormal];
    
    // Add action
    [uberButton addTarget:self action:@selector(uberFareButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Add to the map view above any Google Maps layers but below other controls
    [self.mapContainerView insertSubview:uberButton aboveSubview:self.mapWebView];
    
    // Store the button for later reference
    self.uberFareButton = uberButton;
    
    // Make sure button stays in a good position for different screen sizes
    uberButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
}

- (void)uberFareButtonTapped:(UIButton *)sender {
    // Show loading indicator on the button
    [sender setTitle:@"..." forState:UIControlStateNormal];
    sender.enabled = NO;
    
    // Show the fare estimate
    [self showUberFareEstimate];
    
    // Restore button state after delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sender setTitle:@"U" forState:UIControlStateNormal];
        sender.enabled = YES;
    });
}

- (void)showUberFareEstimate {
    // Check if both locations are set
    if (![self.pickupDropManager hasPickupAndDropLocations]) {
        [self showToastWithMessage:@"Please set both pickup and drop locations first"];
        return;
    }
    
    // Show loading indicator
    [self showToastWithMessage:@"Calculating Uber fare..."];
    
    // Request fare calculation
    [self.pickupDropManager calculateUberFareWithCompletion:^(NSDictionary *fareEstimate, NSError *error) {
        if (error) {
            // Log the error details
            NSLog(@"[WeaponX] ❌ Uber fare calculation error: %@", error);
            NSLog(@"[WeaponX] Error domain: %@, code: %ld", error.domain, (long)error.code);
            NSLog(@"[WeaponX] Error user info: %@", error.userInfo);
            
            // Show appropriate error message
            NSString *errorMessage;
            if ([error.domain isEqualToString:@"UberFareCalculatorErrorDomain"] && error.code == 1001) {
                // API credentials not set error
                errorMessage = @"Uber API configuration error. Please try again.";
                
                // Try to reinitialize the API
                [self.pickupDropManager configureUberWithAppId:@"x3Ver_fJtiRM9tmckasEu0aXymBlYjDX" 
                                                clientSecret:@"s7PttLsUrggdRGr5cVXHIT5ezU5N6Jsxbs-tbNuR"];
            } else if ([error.domain isEqualToString:@"UberAPIErrorDomain"] && 
                       [error.localizedDescription containsString:@"scope"]) {
                // Scope error - try to reinitialize with correct scopes
                errorMessage = @"Reinitializing Uber API permissions...";
                [self.pickupDropManager configureUberWithAppId:@"x3Ver_fJtiRM9tmckasEu0aXymBlYjDX" 
                                                clientSecret:@"s7PttLsUrggdRGr5cVXHIT5ezU5N6Jsxbs-tbNuR"];
                
                // Try the request again after a short delay
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self showUberFareEstimate];
                });
            } else {
                errorMessage = error.localizedDescription ?: @"Unable to calculate Uber fare";
            }
            
            [self showToastWithMessage:errorMessage];
            return;
        }
        
        // Create alert with fare information
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Uber Fare Estimate" 
                                                                     message:nil 
                                                              preferredStyle:UIAlertControllerStyleAlert];
        
        // Format content for alert
        NSMutableString *message = [NSMutableString string];
        
        // Add ride type and price
        [message appendString:fareEstimate[@"summary"] ?: @""];
        [message appendString:@"\n\n"];
        
        // Add distance information if available
        if (fareEstimate[@"formattedDistance"]) {
            [message appendFormat:@"Distance: %@\n", fareEstimate[@"formattedDistance"]];
        }
        
        // Add duration if available
        if (fareEstimate[@"formattedDuration"]) {
            [message appendFormat:@"Duration: %@\n", fareEstimate[@"formattedDuration"]];
        }
        
        // Add surge multiplier if available and > 1
        NSNumber *surgeMultiplier = fareEstimate[@"surge_multiplier"];
        if (surgeMultiplier && [surgeMultiplier floatValue] > 1.0) {
            [message appendFormat:@"\n⚠️ Surge: %.1fx", [surgeMultiplier floatValue]];
        }
        
        alert.message = message;
        
        // Add action to open in Uber app
        BOOL canOpenUber = [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"uber://"]];
        if (canOpenUber) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Open in Uber" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self openUberAppWithPickup:[self.pickupDropManager pickupCoordinate] 
                                  andDrop:[self.pickupDropManager dropCoordinate]];
            }]];
        }
        
        // Add action to dismiss
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        // Present the alert
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)openUberAppWithPickup:(CLLocationCoordinate2D)pickup andDrop:(CLLocationCoordinate2D)drop {
    // Create deep link URL to open Uber with these coordinates
    NSString *urlString = [NSString stringWithFormat:@"uber://?client_id=%@&action=setPickup&pickup[latitude]=%f&pickup[longitude]=%f&dropoff[latitude]=%f&dropoff[longitude]=%f",
                        @"x3Ver_fJtiRM9tmckasEu0aXymBlYjDX",
                        pickup.latitude,
                        pickup.longitude,
                        drop.latitude,
                        drop.longitude];
    
    NSURL *uberURL = [NSURL URLWithString:urlString];
    
    // Try to open Uber app
    [[UIApplication sharedApplication] openURL:uberURL options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            // If opening app fails, try to open App Store to Uber app
            NSURL *appStoreURL = [NSURL URLWithString:@"https://apps.apple.com/app/uber/id368677368"];
            [[UIApplication sharedApplication] openURL:appStoreURL options:@{} completionHandler:nil];
        }
    }];
}

@end 