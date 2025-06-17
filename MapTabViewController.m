#import "MapTabViewController.h"
#import "MapTabViewController+PickupDrop.h" // Import the category with Uber API methods
#import <CoreLocation/CoreLocation.h>
#import <CoreLocationUI/CoreLocationUI.h>  // For CLLocationButton (iOS 15+)
#import <objc/runtime.h>  // For associated objects
#import "ProjectXLogging.h"
#import "LocationSpoofingManager.h" // Import the new LocationSpoofingManager
#import "LocationHeaderView.h"
#import "IPStatusCacheManager.h" // Import for IP and location data saving

// Forward declaration for app termination
@interface BottomButtons : NSObject
+ (instancetype)sharedInstance;
- (void)killEnabledApps;
@end

// Configuration constants
static NSString *const kGoogleMapsAPIKey = @"AIzaSyCXF2ySIyCntOgy53QnqeeqNV_P_9ShfSY"; // Google Maps API key
static NSString *const kGoogleMapsAPIKeyFallback = @"AIzaSyB41DRUbKWJHPxaFjMAwdrzWzbVKartNGg"; // Fallback Google Maps API key
static BOOL useAlternativeKey = NO; // Flag to track which API key we're using
static NSString *ROOT_PREFIX = @""; // Prefix for rootless jailbreak paths

// Add constants for NSUserDefaults keys at the top of the file (after imports but before @interface)
// Keys for NSUserDefaults persistence
static NSString * const kTransportationModeKey = @"com.weaponx.transportationMode";
static NSString * const kAccuracyValueKey = @"com.weaponx.accuracyValue";
static NSString * const kJitterEnabledKey = @"com.weaponx.jitterEnabled";
static NSString * const kMovementSpeedKey = @"com.weaponx.movementSpeed";
static NSString * const kPathWaypointsKey = @"com.weaponx.pathWaypoints";
static NSString * const kMapTypeKey = @"com.weaponx.mapType"; // New key for map type
// New keys for path movement state persistence
static NSString * const kPathMovementActiveKey = @"com.weaponx.pathMovementActive";
static NSString * const kPathCurrentIndexKey = @"com.weaponx.pathCurrentIndex";
static NSString * const kPathMovementSpeedKey = @"com.weaponx.pathMovementSpeed";

@interface MapTabViewController () <WKNavigationDelegate, WKScriptMessageHandler, UITextFieldDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIView *searchBarContainer;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *currentLocationButton;
@property (nonatomic, strong) UIButton *permissionsButton;
@property (nonatomic, strong) UIView *toolbarView;
@property (nonatomic, strong) UISegmentedControl *mapTypeControl;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UIButton *layersButton;
@property (nonatomic, strong) UIView *mapTypeOptionsView;
@property (nonatomic, strong) CAGradientLayer *searchBarGradient;
@property (nonatomic, readwrite, strong) UIView *gpsSpoofingBar;
@property (nonatomic, readwrite, strong) UISwitch *gpsSpoofingSwitch;
@property (nonatomic, strong) UIButton *pinModeButton;
@property (nonatomic, assign) BOOL isPinModeActive;
@property (nonatomic, strong) UILabel *coordinatesLabel;
@property (nonatomic, strong) UIView *coordinatesContainer;
// New properties for favorite locations
@property (nonatomic, readwrite, strong) UIButton *favoritesButton;
@property (nonatomic, readwrite, strong) UIView *favoritesContainer;
@property (nonatomic, strong) UIButton *saveLocationButton;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) NSDictionary *currentPinLocation;
@property (nonatomic, copy) void (^mapLoadCompletion)(BOOL success);
@property (nonatomic, readwrite, strong) UIButton *gpsAdvancedButton;
@property (nonatomic, readwrite, strong) UIView *gpsAdvancedPanel;
@property (nonatomic, readwrite, strong) UISegmentedControl *transportationModeControl;
@property (nonatomic, readwrite, strong) UISlider *accuracySlider;
@property (nonatomic, readwrite, strong) UISwitch *jitterSwitch;
@property (nonatomic, readwrite, strong) UILabel *speedCourseLabel;
@property (nonatomic, readwrite, strong) NSTimer *speedUpdateTimer;
@property (nonatomic, readwrite, strong) UIButton *unpinButton;
@property (nonatomic, readwrite, strong) UIButton *pinButton;
@property (nonatomic, readwrite, strong) UIView *unpinContainer;
@property (nonatomic, readwrite, strong) UISlider *movementSpeedSlider;
@property (nonatomic, readwrite, strong) UILabel *movementSpeedLabel;
@property (nonatomic, readwrite, strong) UILabel *pathStatusLabel;
@property (nonatomic, strong) UIView *pinnedLocationCircleView;
@end

@implementation MapTabViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Restore path movement state if present
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL movementActive = [defaults boolForKey:kPathMovementActiveKey];
    NSInteger savedIndex = [defaults integerForKey:kPathCurrentIndexKey];
    double savedSpeed = [defaults doubleForKey:kPathMovementSpeedKey];
    NSArray *savedWaypoints = [self getPathWaypoints];
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    if (movementActive && savedWaypoints && savedWaypoints.count >= 2) {
        double speed = (savedSpeed > 0) ? savedSpeed : 5.0;
        // Resume movement from saved index using new API
        [manager startMovementAlongPath:savedWaypoints withSpeed:speed startIndex:savedIndex completion:^(BOOL completed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.pathStatusLabel.text = @"Status: Movement Completed";
                self.pathStatusLabel.textColor = [UIColor systemGreenColor];
                [self.movementSpeedSlider setValue:speed animated:NO];
                [self updateSpeedDisplay];
                [self updatePinUnpinVisibility];
                // Restore pin if static location exists
                if ([self hasPinnedLocation]) {
                    NSDictionary *loc = [self getPinnedLocation];
                    [self centerMapAndPlacePinAtLatitude:[loc[@"latitude"] doubleValue] longitude:[loc[@"longitude"] doubleValue] shouldTogglePinButton:YES];
                }
            });
        }];
        self.pathStatusLabel.text = @"Status: Moving... (resumed)";
        self.pathStatusLabel.textColor = [UIColor systemBlueColor];
        [self.movementSpeedSlider setValue:speed animated:NO];
        [self updateSpeedDisplay];
        [self updatePinUnpinVisibility];
    } else {
        [self updatePinUnpinVisibility];
    }

    // Create and set the location header view
    [LocationHeaderView createHeaderViewWithTitle:@"Map" 
                                navigationItem:self.navigationItem 
                                 updateHandler:^{
        // Add any map-specific update handling if needed
    }];
    
    // Initialize pickup/drop manager
    self.pickupDropManager = [PickupDropManager sharedManager];
    
    // Initialize Uber API with provided credentials
    NSString *uberAppId = @"x3Ver_fJtiRM9tmckasEu0aXymBlYjDX";
    NSString *uberClientSecret = @"s7PttLsUrggdRGr5cVXHIT5ezU5N6Jsxbs-tbNuR";
    [self setupUberAPIWithAppId:uberAppId clientSecret:uberClientSecret];
    
    self.title = @"Map";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Check for rootless jailbreak
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:@"/var/jb"]) {
        ROOT_PREFIX = @"/var/jb/var/mobile/Library/Preferences";
        PXLog(@"[WeaponX] Detected rootless jailbreak, using path prefix: %@", ROOT_PREFIX);
    } else {
        ROOT_PREFIX = @"/var/mobile/Library/Preferences";
        PXLog(@"[WeaponX] Using standard jailbreak path: %@", ROOT_PREFIX);
    }
    
    // Ensure Preferences directory exists
    if (![fileManager fileExistsAtPath:ROOT_PREFIX]) {
        NSError *error;
        [fileManager createDirectoryAtPath:ROOT_PREFIX 
                withIntermediateDirectories:YES 
                                 attributes:nil 
                                      error:&error];
        if (error) {
            PXLog(@"[WeaponX] Error creating Preferences directory: %@", error);
        } else {
            PXLog(@"[WeaponX] Created Preferences directory at: %@", ROOT_PREFIX);
        }
    }
    
    // Setup location manager
    [self setupLocationManager];
    
    [self setupLoadingIndicator];
    [self setupWebView];
    [self setupSearchBar];
    [self setupToolbar];
    [self setupStatusLabel];
    [self setupCoordinatesDisplay];
    
    // Initialize pinning mode as always active
    self.isPinModeActive = YES;
    
    // Initialize currentPinLocation
    self.currentPinLocation = nil;
    
    // Setup favorites button - ensure it's always shown
    [self setupFavoritesButton];
    
    // Setup unpin button
    [self setupUnpinButton];
    
    // Setup GPS spoofing button
    [self setupGPSSpoofingButton];
    
    // Set up GPS spoofing bar (UI element at the top)
    [self setupGpsSpoofingBar];
    
    
    // Load the map
    [self loadMapWithCompletionHandler:^(BOOL success) {
        if (success) {
            // Check for saved pinned location after map is loaded
            [self checkForSavedPinnedLocation];
            
            // Start periodic check for pinned location changes
            [self startPinnedLocationMonitoring];
        }
    }];
    
    // Add tap gesture recognizer to dismiss keyboard when tapping on map
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard:)];
    tapRecognizer.delegate = self;
    [self.mapWebView addGestureRecognizer:tapRecognizer];
    
    // Add tap gesture recognizer for pin placement
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    self.tapGesture.delegate = self;
    [self.mapWebView addGestureRecognizer:self.tapGesture];
    
    // Ensure pin/unpin UI is correct after all setup
    [self updatePinUnpinVisibility];

    PXLog(@"[WeaponX] Map tab initialized with Google Maps API");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Refresh the header view when the view appears
    [LocationHeaderView createHeaderViewWithTitle:@"Map" 
                                navigationItem:self.navigationItem 
                                 updateHandler:^{
        // Add any map-specific update handling if needed
    }];
    
    // Sync GPS spoofing switch with actual state
    LocationSpoofingManager *spoofingManager = [LocationSpoofingManager sharedManager];
    self.gpsSpoofingSwitch.on = [spoofingManager isSpoofingEnabled];
    
    // ... rest of existing viewWillAppear code ...
}

#pragma mark - Theme Support

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self updateAdvancedPanelForCurrentTheme];
        }
    }
}

#pragma mark - Setup Methods

- (void)setupWebView {
    // Configure WKWebView with preferences
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.allowsInlineMediaPlayback = YES;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    // Add message handler for JavaScript communication
    [configuration.userContentController addScriptMessageHandler:self name:@"mapHandler"];
    
    // Create the web view with configuration
    self.mapWebView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.mapWebView.navigationDelegate = self;
    self.mapWebView.opaque = YES;
    self.mapWebView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapWebView.scrollView.bounces = NO;
    self.mapWebView.hidden = YES; // Initially hidden until loaded
    
    [self.view addSubview:self.mapWebView];
    
    // Set constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.mapWebView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:60], // Space for search bar
        [self.mapWebView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mapWebView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mapWebView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-50] // Space for toolbar
    ]];
}

- (void)setupSearchBar {
    // Create a container view for the search bar components
    self.searchBarContainer = [[UIView alloc] init];
    
    // Determine if in dark mode
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    
    // Enhanced appearance with 3D effect
    // Use a semi-transparent background that works in both light and dark mode
    self.searchBarContainer.backgroundColor = isDarkMode ? 
        [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.9] : 
        [UIColor colorWithWhite:1.0 alpha:0.95];
    
    // Enhanced corner radius for modern look
    self.searchBarContainer.layer.cornerRadius = 12;
    
    // Enhanced shadow for 3D effect
    self.searchBarContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.searchBarContainer.layer.shadowOffset = CGSizeMake(0, 3);
    self.searchBarContainer.layer.shadowOpacity = isDarkMode ? 0.5 : 0.2;
    self.searchBarContainer.layer.shadowRadius = 6;
    
    // Add border for more definition
    self.searchBarContainer.layer.borderWidth = 0.5;
    self.searchBarContainer.layer.borderColor = isDarkMode ? 
        [UIColor colorWithWhite:0.3 alpha:0.8].CGColor : 
        [UIColor colorWithWhite:0.8 alpha:0.8].CGColor;
    
    self.searchBarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Instead of inner shadow, add a gradient overlay for 3D effect
    self.searchBarGradient = [CAGradientLayer layer];
    self.searchBarGradient.frame = CGRectMake(0, 0, 600, 48); // Will be adjusted to container size
    self.searchBarGradient.colors = @[
        (id)(isDarkMode ? 
            [UIColor colorWithWhite:0.12 alpha:1.0].CGColor : 
            [UIColor colorWithWhite:0.95 alpha:1.0].CGColor),
        (id)(isDarkMode ? 
            [UIColor colorWithWhite:0.18 alpha:1.0].CGColor : 
            [UIColor colorWithWhite:1.0 alpha:1.0].CGColor)
    ];
    self.searchBarGradient.startPoint = CGPointMake(0.5, 0.0);
    self.searchBarGradient.endPoint = CGPointMake(0.5, 1.0);
    self.searchBarGradient.cornerRadius = 12;
    self.searchBarGradient.masksToBounds = YES;
    [self.searchBarContainer.layer insertSublayer:self.searchBarGradient atIndex:0];
    
    [self.view addSubview:self.searchBarContainer];
    
    // Create the search text field with enhanced styling
    self.searchTextField = [[UITextField alloc] init];
    self.searchTextField.placeholder = @"Search location...";
    self.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] 
        initWithString:@"Search location..." 
        attributes:@{
            NSForegroundColorAttributeName: isDarkMode ? 
                [UIColor colorWithWhite:0.6 alpha:1.0] : 
                [UIColor colorWithWhite:0.5 alpha:1.0]
        }];
    self.searchTextField.returnKeyType = UIReturnKeySearch;
    self.searchTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.searchTextField.backgroundColor = [UIColor clearColor]; // Use clear color for search field
    self.searchTextField.textColor = isDarkMode ? [UIColor whiteColor] : [UIColor darkTextColor];
    self.searchTextField.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    
    // Add left padding
    self.searchTextField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 0)];
    self.searchTextField.leftViewMode = UITextFieldViewModeAlways;
    self.searchTextField.delegate = self;
    self.searchTextField.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add keyboard accessory view with Done button
    UIToolbar *keyboardToolbar = [[UIToolbar alloc] init];
    [keyboardToolbar sizeToFit];
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonTapped)];
    keyboardToolbar.items = @[flexSpace, doneButton];
    self.searchTextField.inputAccessoryView = keyboardToolbar;
    
    [self.searchBarContainer addSubview:self.searchTextField];
    
    // Create the search button with enhanced styling
    self.searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *searchIcon = [UIImage systemImageNamed:@"magnifyingglass"];
    [self.searchButton setImage:searchIcon forState:UIControlStateNormal];
    self.searchButton.tintColor = isDarkMode ? [UIColor colorWithRed:0.1 green:0.6 blue:1.0 alpha:1.0] : [UIColor systemBlueColor];
    self.searchButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchButton addTarget:self action:@selector(searchButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.searchBarContainer addSubview:self.searchButton];
    
    // Create a current location button with enhanced styling
    [self setupLocationButton];
    
    // Create permissions button
    [self setupPermissionsButton];
    
    // Create the pickup/drop button
    [self setupPickupDropButton];
    
    if (isDarkMode) {
        // Adjust the location button appearance in dark mode
        self.currentLocationButton.tintColor = [UIColor colorWithRed:0.1 green:0.6 blue:1.0 alpha:1.0];
        self.permissionsButton.tintColor = [UIColor colorWithRed:0.1 green:0.6 blue:1.0 alpha:1.0];
        if ([self.currentLocationButton respondsToSelector:@selector(setBackgroundColor:)]) {
            self.currentLocationButton.backgroundColor = [UIColor clearColor];
            self.permissionsButton.backgroundColor = [UIColor clearColor];
        }
    }
    
    self.currentLocationButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.permissionsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchBarContainer addSubview:self.currentLocationButton];
    [self.searchBarContainer addSubview:self.permissionsButton];
    
    // Set constraints for search container - make it slightly taller for better touch experience
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBarContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.searchBarContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.searchBarContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.searchBarContainer.heightAnchor constraintEqualToConstant:48]
    ]];
    
    // Set constraints for search components
    [NSLayoutConstraint activateConstraints:@[
        // Permissions button (leftmost)
        [self.permissionsButton.leadingAnchor constraintEqualToAnchor:self.searchBarContainer.leadingAnchor constant:8],
        [self.permissionsButton.centerYAnchor constraintEqualToAnchor:self.searchBarContainer.centerYAnchor],
        [self.permissionsButton.widthAnchor constraintEqualToConstant:36],
        [self.permissionsButton.heightAnchor constraintEqualToConstant:36],
        
        // Current location button (next to permissions)
        [self.currentLocationButton.leadingAnchor constraintEqualToAnchor:self.permissionsButton.trailingAnchor constant:4],
        [self.currentLocationButton.centerYAnchor constraintEqualToAnchor:self.searchBarContainer.centerYAnchor],
        [self.currentLocationButton.widthAnchor constraintEqualToConstant:36],
        [self.currentLocationButton.heightAnchor constraintEqualToConstant:36],
        
        // Search text field
        [self.searchTextField.leadingAnchor constraintEqualToAnchor:self.currentLocationButton.trailingAnchor constant:4],
        [self.searchTextField.topAnchor constraintEqualToAnchor:self.searchBarContainer.topAnchor constant:4],
        [self.searchTextField.bottomAnchor constraintEqualToAnchor:self.searchBarContainer.bottomAnchor constant:-4],
        
        // Search button (rightmost)
        [self.searchButton.leadingAnchor constraintEqualToAnchor:self.searchTextField.trailingAnchor constant:4],
        [self.searchButton.trailingAnchor constraintEqualToAnchor:self.searchBarContainer.trailingAnchor constant:-8],
        [self.searchButton.centerYAnchor constraintEqualToAnchor:self.searchBarContainer.centerYAnchor],
        [self.searchButton.widthAnchor constraintEqualToConstant:36],
        [self.searchButton.heightAnchor constraintEqualToConstant:36]
    ]];
}

// Setup pickup/drop button
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
    
    // Set constraints for pickup/drop menu
    [NSLayoutConstraint activateConstraints:@[
        [self.pickupDropMenuView.topAnchor constraintEqualToAnchor:self.searchBarContainer.bottomAnchor constant:8],
        [self.pickupDropMenuView.trailingAnchor constraintEqualToAnchor:self.searchBarContainer.trailingAnchor constant:-8],
        [self.pickupDropMenuView.widthAnchor constraintEqualToConstant:160],
        [self.pickupDropMenuView.heightAnchor constraintEqualToConstant:2 * 40] // 2 options * 40pts height
    ]];
    
    // Add menu options
    NSArray *options = @[@"Set Pickup", @"Set Drop"];
    NSArray *icons = @[@"mappin.circle.fill", @"mappin.and.ellipse"];
    NSArray *colors = @[
        isDarkMode ? [UIColor systemGreenColor] : [UIColor systemGreenColor],
        isDarkMode ? [UIColor systemOrangeColor] : [UIColor systemOrangeColor]
    ];
    
    for (NSInteger i = 0; i < options.count; i++) {
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
        
        optionButton.tag = i; // Use tag to identify option (0=pickup, 1=drop)
        optionButton.tintColor = colors[i];
        optionButton.translatesAutoresizingMaskIntoConstraints = NO;
        [optionButton addTarget:self action:@selector(pickupDropOptionSelected:) forControlEvents:UIControlEventTouchUpInside];
        [self.pickupDropMenuView addSubview:optionButton];
        
        [NSLayoutConstraint activateConstraints:@[
            [optionButton.leadingAnchor constraintEqualToAnchor:self.pickupDropMenuView.leadingAnchor],
            [optionButton.trailingAnchor constraintEqualToAnchor:self.pickupDropMenuView.trailingAnchor],
            [optionButton.heightAnchor constraintEqualToConstant:40],
            [optionButton.topAnchor constraintEqualToAnchor:self.pickupDropMenuView.topAnchor constant:i * 40]
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
                [separator.topAnchor constraintEqualToAnchor:optionButton.bottomAnchor]
            ]];
        }
    }
}

- (void)setupToolbar {
    // Create a container view for button 
    UIView *buttonContainer = [[UIView alloc] init];
    buttonContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mapWebView addSubview:buttonContainer];
    
    // Create layers button
    self.layersButton = [UIButton buttonWithType:UIButtonTypeCustom]; // Change to custom button type
    
    // Create a map thumbnail using Core Graphics directly
    UIImage *mapThumbnail = [self createMapThumbnailImage];
    
    // Set the image directly to the button
    [self.layersButton setImage:mapThumbnail forState:UIControlStateNormal];
    self.layersButton.imageView.contentMode = UIViewContentModeScaleToFill;
    
    // Add shadow and border
    self.layersButton.layer.cornerRadius = 4;
    self.layersButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layersButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.layersButton.layer.shadowOpacity = 0.3;
    self.layersButton.layer.shadowRadius = 3;
    self.layersButton.layer.masksToBounds = NO;
    
    // Important: Set clipsToBounds on imageView, not button (for shadow to show)
    self.layersButton.imageView.clipsToBounds = YES;
    self.layersButton.imageView.layer.cornerRadius = 4;
    
    self.layersButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.layersButton addTarget:self action:@selector(layersButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [buttonContainer addSubview:self.layersButton];
    
    // Setup GPS Spoofing bar
    [self setupGpsSpoofingBar];
    
    // Create map type options view (initially hidden)
    self.mapTypeOptionsView = [[UIView alloc] init];
    self.mapTypeOptionsView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.95];
    self.mapTypeOptionsView.layer.cornerRadius = 8;
    self.mapTypeOptionsView.clipsToBounds = YES;
    self.mapTypeOptionsView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.mapTypeOptionsView.layer.shadowOffset = CGSizeMake(0, 2);
    self.mapTypeOptionsView.layer.shadowOpacity = 0.2;
    self.mapTypeOptionsView.layer.shadowRadius = 4;
    self.mapTypeOptionsView.layer.masksToBounds = NO;
    self.mapTypeOptionsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapTypeOptionsView.hidden = YES;
    [self.mapWebView addSubview:self.mapTypeOptionsView];
    
    // Set constraints for button container - more compact in the corner
    [NSLayoutConstraint activateConstraints:@[
        [buttonContainer.leadingAnchor constraintEqualToAnchor:self.mapWebView.leadingAnchor constant:10],
        [buttonContainer.topAnchor constraintEqualToAnchor:self.mapWebView.topAnchor constant:10],
        [buttonContainer.widthAnchor constraintEqualToConstant:50],
        [buttonContainer.heightAnchor constraintEqualToConstant:50]
    ]];
    
    // Set constraints for layers button - full size of container
    [NSLayoutConstraint activateConstraints:@[
        [self.layersButton.topAnchor constraintEqualToAnchor:buttonContainer.topAnchor],
        [self.layersButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [self.layersButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [self.layersButton.bottomAnchor constraintEqualToAnchor:buttonContainer.bottomAnchor]
    ]];
    
    // Set constraints for map type options view - positioned below the button container
    [NSLayoutConstraint activateConstraints:@[
        [self.mapTypeOptionsView.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [self.mapTypeOptionsView.topAnchor constraintEqualToAnchor:buttonContainer.bottomAnchor constant:8],
        [self.mapTypeOptionsView.widthAnchor constraintEqualToConstant:160],
        [self.mapTypeOptionsView.heightAnchor constraintEqualToConstant:4 * 40] // 4 options * 40pts height
    ]];
    
    // Add map type buttons to options view
    NSArray *mapTypes = @[@"Road", @"Satellite", @"Hybrid", @"Terrain"];
    NSArray *mapIcons = @[@"map", @"globe", @"map.fill", @"mountain.2"];
    
    for (NSInteger i = 0; i < mapTypes.count; i++) {
        UIButton *optionButton;
        
        if (@available(iOS 15.0, *)) {
            // Use modern UIButtonConfiguration for iOS 15+
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            
            // Configure the button appearance
            config.imagePlacement = NSDirectionalRectEdgeLeading;
            config.imagePadding = 10;
            config.contentInsets = NSDirectionalEdgeInsetsMake(0, 5, 0, 0);
            config.title = mapTypes[i];
            config.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
            
            UIImage *image = [UIImage systemImageNamed:mapIcons[i]];
            config.image = image;
            
            optionButton = [UIButton buttonWithConfiguration:config primaryAction:nil];
        } else {
            // Legacy approach for iOS 14 and earlier
            optionButton = [UIButton buttonWithType:UIButtonTypeSystem];
            [optionButton setTitle:mapTypes[i] forState:UIControlStateNormal];
            [optionButton setImage:[UIImage systemImageNamed:mapIcons[i]] forState:UIControlStateNormal];
            optionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            
            // Using deprecated properties but only for older iOS versions
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            optionButton.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
            optionButton.imageEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
            #pragma clang diagnostic pop
        }
        
        optionButton.tag = i;  // Use tag to identify map type
        optionButton.tintColor = [UIColor labelColor];
        optionButton.translatesAutoresizingMaskIntoConstraints = NO;
        [optionButton addTarget:self action:@selector(mapTypeOptionSelected:) forControlEvents:UIControlEventTouchUpInside];
        [self.mapTypeOptionsView addSubview:optionButton];
        
    [NSLayoutConstraint activateConstraints:@[
            [optionButton.leadingAnchor constraintEqualToAnchor:self.mapTypeOptionsView.leadingAnchor],
            [optionButton.trailingAnchor constraintEqualToAnchor:self.mapTypeOptionsView.trailingAnchor],
            [optionButton.heightAnchor constraintEqualToConstant:40],
            [optionButton.topAnchor constraintEqualToAnchor:self.mapTypeOptionsView.topAnchor constant:i * 40]
        ]];
        
        // Add a separator line except for the last item
        if (i < mapTypes.count - 1) {
            UIView *separator = [[UIView alloc] init];
            separator.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.5];
            separator.translatesAutoresizingMaskIntoConstraints = NO;
            [self.mapTypeOptionsView addSubview:separator];
            
            [NSLayoutConstraint activateConstraints:@[
                [separator.leadingAnchor constraintEqualToAnchor:self.mapTypeOptionsView.leadingAnchor constant:10],
                [separator.trailingAnchor constraintEqualToAnchor:self.mapTypeOptionsView.trailingAnchor constant:-10],
                [separator.heightAnchor constraintEqualToConstant:0.5],
                [separator.topAnchor constraintEqualToAnchor:optionButton.bottomAnchor]
            ]];
        }
    }
    
    // Apply dark mode styling if needed
    if (@available(iOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            self.mapTypeOptionsView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
        }
    }
}

- (void)setupLoadingIndicator {
    // Create loading indicator
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];
    
    // Center the loading indicator
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    
    [self.loadingIndicator startAnimating];
}

- (void)setupStatusLabel {
    // Create status label for error messages
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.hidden = YES;
    [self.view addSubview:self.statusLabel];
    
    // Center the status label
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40]
    ]];
}

- (void)setupLocationButton {
    // Create location button based on iOS version
    if (@available(iOS 15.0, *)) {
        // iOS 15+ location button - using UIButton instead of CLLocationButton for compatibility
        UIButton *locationButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [locationButton setImage:[UIImage systemImageNamed:@"location.fill"] forState:UIControlStateNormal];
        locationButton.backgroundColor = [UIColor systemBackgroundColor];
        locationButton.tintColor = [UIColor systemBlueColor];
        locationButton.layer.cornerRadius = 18;
        locationButton.translatesAutoresizingMaskIntoConstraints = NO;
        [locationButton addTarget:self action:@selector(locationButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        self.currentLocationButton = locationButton;
    } else {
        // Legacy location button implementation for older iOS
        self.currentLocationButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.currentLocationButton setImage:[UIImage systemImageNamed:@"location.fill"] forState:UIControlStateNormal];
        [self.currentLocationButton addTarget:self action:@selector(currentLocationButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)setupLocationManager {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.allowsBackgroundLocationUpdates = YES; // Enable background updates
    self.locationManager.pausesLocationUpdatesAutomatically = NO; // Prevent automatic pausing
    
    // Add required entry to Info.plist
    // NSLocationAlwaysAndWhenInUseUsageDescription - "This app requires background location access to provide continuous location services"
    // NSLocationWhenInUseUsageDescription - "This app requires location access to show your position on the map"
    
    // iOS 15+ specific configuration
    if (@available(iOS 15.0, *)) {
        // Request full accuracy
        [self.locationManager requestTemporaryFullAccuracyAuthorizationWithPurposeKey:@"LocationAccuracyUsageDescription"];
    }
    
    // Check authorization status
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus; // Use instance method in iOS 14+
    } else {
        // Suppress deprecation warning for older iOS compatibility
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus]; // Use class method for older iOS
        #pragma clang diagnostic pop
    }
    
    // For iOS 15, we need to request "When In Use" permission first, then "Always" later
    if (status == kCLAuthorizationStatusNotDetermined) {
        // First request "When In Use" permission - this will show the "Always Allow" option in iOS 15
        [self.locationManager requestWhenInUseAuthorization];
        
        // After a short delay, request "Always" permission to trigger the prompt with "Always Allow" option
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.locationManager requestAlwaysAuthorization];
            PXLog(@"[WeaponX] Requesting upgrade to Always authorization after When In Use");
        });
    } else if (status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        // If we only have "When in Use" permission, request "Always" permission
        [self.locationManager requestAlwaysAuthorization];
        PXLog(@"[WeaponX] Requesting upgrade to Always authorization");
    }
    
    PXLog(@"[WeaponX] Location manager setup complete with proper authorization sequence for iOS 15+");
}

#pragma mark - Action Methods

- (void)searchButtonTapped {
    [self.searchTextField resignFirstResponder];
    
    // Existing search functionality
    NSString *searchText = self.searchTextField.text;
    if (searchText.length > 0) {
        [self searchLocation:searchText];
    }
}

- (void)currentLocationButtonTapped {
    // COMPLETELY ISOLATED from GPS spoofing functionality
    PXLog(@"[WeaponX] Current location button tapped - isolated from GPS spoofing");
    
    // Check authorization without interacting with GPS spoofing or blue pin
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus];
        #pragma clang diagnostic pop
    }
    
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || 
        status == kCLAuthorizationStatusAuthorizedAlways) {
        
        // Get the real location without interacting with GPS spoofing
        CLLocation *location = self.locationManager.location;
        if (location) {
            // First ensure the map is ready
            [self ensureMapIsReadyWithCompletion:^(BOOL success) {
                if (!success) {
                    PXLog(@"[WeaponX] Map is not ready for location display");
                    return;
                }
                
                // Simplified approach - just center and create a blue circle marker
                NSString *script = [NSString stringWithFormat:@"if (map) { \
                    var latLng = new google.maps.LatLng(%f, %f); \
                    map.setCenter(latLng); \
                    \
                    if (window.userLocationMarker) { \
                        window.userLocationMarker.setMap(null); \
                    } \
                    if (window.accuracyCircle) { \
                        window.accuracyCircle.setMap(null); \
                    } \
                    \
                    window.accuracyCircle = new google.maps.Circle({ \
                        center: latLng, \
                        radius: %f, \
                        fillColor: '#4285F4', \
                        fillOpacity: 0.1, \
                        strokeColor: '#4285F4', \
                        strokeOpacity: 0.3, \
                        strokeWeight: 1, \
                        map: map \
                    }); \
                    \
                    window.userLocationMarker = new google.maps.Marker({ \
                        position: latLng, \
                        map: map, \
                        icon: { \
                            url: 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent('<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 16 16\"><circle cx=\"8\" cy=\"8\" r=\"8\" fill=\"#4285F4\" stroke=\"white\" stroke-width=\"2\"/></svg>'), \
                            scaledSize: new google.maps.Size(16, 16), \
                            anchor: new google.maps.Point(8, 8) \
                        } \
                    }); \
                }", 
                    location.coordinate.latitude, 
                    location.coordinate.longitude,
                    location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 50.0];
                
                [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
                    if (error) {
                        PXLog(@"[WeaponX] Error showing current location: %@", error);
                        // Try an even simpler approach if the first one fails
                        NSString *fallbackScript = [NSString stringWithFormat:@"if (map) { map.setCenter(new google.maps.LatLng(%f, %f)); }",
                                                  location.coordinate.latitude, location.coordinate.longitude];
                        [self.mapWebView evaluateJavaScript:fallbackScript completionHandler:nil];
                    }
                }];
            }];
            
            PXLog(@"[WeaponX] Centered map on real location - isolated from GPS spoofing: %f, %f", 
                 location.coordinate.latitude, location.coordinate.longitude);
        } else {
            PXLog(@"[WeaponX] No location available - no action taken");
        }
    } else if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
        PXLog(@"[WeaponX] Requesting location authorization");
    } else {
        [self showLocationSettingsAlert];
        PXLog(@"[WeaponX] Location access denied - showing settings alert");
    }
}

- (void)layersButtonTapped:(UIButton *)sender {
    // Toggle visibility of map type options
    self.mapTypeOptionsView.hidden = !self.mapTypeOptionsView.hidden;
    
    // Add subtle animation
    if (!self.mapTypeOptionsView.hidden) {
        self.mapTypeOptionsView.alpha = 0;
        self.mapTypeOptionsView.transform = CGAffineTransformMakeScale(0.95, 0.95);
        
        [UIView animateWithDuration:0.2 animations:^{
            self.mapTypeOptionsView.alpha = 1;
            self.mapTypeOptionsView.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)mapTypeOptionSelected:(UIButton *)sender {
    // Hide options view
    self.mapTypeOptionsView.hidden = YES;
    
    // Get map type based on sender's tag
    NSString *mapType;
    switch (sender.tag) {
        case 0:
            mapType = @"roadmap";
            break;
        case 1:
            mapType = @"satellite";
            break;
        case 2:
            mapType = @"hybrid";
            break;
        case 3:
            mapType = @"terrain";
            break;
        default:
            mapType = @"roadmap";
            break;
    }
    
    // Update map type
    NSString *script = [NSString stringWithFormat:@"changeMapType('%@');", mapType];
    [self.mapWebView evaluateJavaScript:script completionHandler:nil];
    
    // Save the selected map type to NSUserDefaults
    [[NSUserDefaults standardUserDefaults] setObject:mapType forKey:kMapTypeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    PXLog(@"[WeaponX] Map type changed to: %@ and saved to preferences", mapType);
    
    // Don't update button title as we're using an image button with separate label
}

- (void)mapTypeChanged:(UISegmentedControl *)sender {
    // This method is maintained for backward compatibility
    NSString *mapType;
    switch (sender.selectedSegmentIndex) {
        case 0:
            mapType = @"roadmap";
            break;
        case 1:
            mapType = @"satellite";
            break;
        case 2:
            mapType = @"hybrid";
            break;
        case 3:
            mapType = @"terrain";
            break;
        default:
            mapType = @"roadmap";
            break;
    }
    
    NSString *script = [NSString stringWithFormat:@"changeMapType('%@');", mapType];
    [self.mapWebView evaluateJavaScript:script completionHandler:nil];
}

// Handle iOS 15 location button tap
- (void)locationButtonTapped:(id)sender {
    if (@available(iOS 15.0, *)) {
        // COMPLETELY ISOLATED from GPS spoofing functionality
        // No interaction with GPS spoofing toggle or blue pointer
        PXLog(@"[WeaponX] Location button tapped - using real location ONLY, no effect on GPS spoofing toggle");
        
        // Only center on actual location, don't interact with GPS spoofing or blue pin
        if (self.locationManager.location) {
            // First ensure the map is ready
            [self ensureMapIsReadyWithCompletion:^(BOOL success) {
                if (!success) {
                    PXLog(@"[WeaponX] Map is not ready for location display");
                    return;
                }
                
                // Use the same implementation as currentLocationButtonTapped
                // Simplified approach - just center and create a blue circle marker
                NSString *script = [NSString stringWithFormat:@"if (map) { \
                    var latLng = new google.maps.LatLng(%f, %f); \
                    map.setCenter(latLng); \
                    \
                    if (window.userLocationMarker) { \
                        window.userLocationMarker.setMap(null); \
                    } \
                    if (window.accuracyCircle) { \
                        window.accuracyCircle.setMap(null); \
                    } \
                    \
                    window.accuracyCircle = new google.maps.Circle({ \
                        center: latLng, \
                        radius: %f, \
                        fillColor: '#4285F4', \
                        fillOpacity: 0.1, \
                        strokeColor: '#4285F4', \
                        strokeOpacity: 0.3, \
                        strokeWeight: 1, \
                        map: map \
                    }); \
                    \
                    window.userLocationMarker = new google.maps.Marker({ \
                        position: latLng, \
                        map: map, \
                        icon: { \
                            url: 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent('<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 16 16\"><circle cx=\"8\" cy=\"8\" r=\"8\" fill=\"#4285F4\" stroke=\"white\" stroke-width=\"2\"/></svg>'), \
                            scaledSize: new google.maps.Size(16, 16), \
                            anchor: new google.maps.Point(8, 8) \
                        } \
                    }); \
                }", 
                    self.locationManager.location.coordinate.latitude,
                    self.locationManager.location.coordinate.longitude,
                    self.locationManager.location.horizontalAccuracy > 0 ? self.locationManager.location.horizontalAccuracy : 50.0];
                
                [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
                    if (error) {
                        PXLog(@"[WeaponX] Error showing current location: %@", error);
                        // Try an even simpler approach if the first one fails
                        NSString *fallbackScript = [NSString stringWithFormat:@"if (map) { map.setCenter(new google.maps.LatLng(%f, %f)); }",
                                                  self.locationManager.location.coordinate.latitude, 
                                                  self.locationManager.location.coordinate.longitude];
                        [self.mapWebView evaluateJavaScript:fallbackScript completionHandler:nil];
                    }
                }];
            }];
            
            PXLog(@"[WeaponX] Centered on real location - completely isolated from GPS spoofing");
        } else {
            PXLog(@"[WeaponX] Location not available - no action taken");
        }
    }
}

#pragma mark - Map Loading Methods

- (void)loadMapWithCompletionHandler:(void(^)(BOOL success))completion {
    // Start showing loading indicator
    [self.loadingIndicator startAnimating];
    self.mapWebView.hidden = YES;
    self.statusLabel.hidden = YES;
    
    // Log network status first
    [self checkNetworkConnectivity];
    
    // Create the HTML content for Google Maps
    NSString *htmlContent = [self googleMapsHTMLContent];
    NSString *savedMapType = [[NSUserDefaults standardUserDefaults] stringForKey:kMapTypeKey] ?: @"roadmap";
    PXLog(@"[WeaponX] Loading map with API key: %@ and map type: %@", 
         useAlternativeKey ? @"FALLBACK_KEY" : @"PRIMARY_KEY", savedMapType);
    
    // Load the HTML content with a valid base URL (Google Maps domain)
    NSURL *baseURL = [NSURL URLWithString:@"https://maps.googleapis.com/"];
    [self.mapWebView loadHTMLString:htmlContent baseURL:baseURL];
    PXLog(@"[WeaponX] Map HTML content loaded with base URL: %@", baseURL);
    
    // Store the completion handler
    self.mapLoadCompletion = completion;
    
    // Setup a fallback timer to ensure the pinned location is restored
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self ensurePinnedLocationRestored];
    });
}

- (void)checkNetworkConnectivity {
    // Basic network connectivity test
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://maps.googleapis.com/maps/api/js"]];
    NSURLSession *session = [NSURLSession sharedSession];
    
    PXLog(@"[WeaponX] Testing network connectivity to Google Maps API...");
    
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            PXLog(@"[WeaponX] Network test failed: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.hidden = NO;
                self.statusLabel.text = [NSString stringWithFormat:@"Network issue detected: %@", error.localizedDescription];
            });
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            PXLog(@"[WeaponX] Network test response: %ld", (long)httpResponse.statusCode);
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                PXLog(@"[WeaponX] Network connectivity to Google Maps API confirmed");
            } else {
                PXLog(@"[WeaponX] Network test received HTTP status: %ld", (long)httpResponse.statusCode);
            }
        }
    }] resume];
}

- (void)tryAlternativeAPIKey {
    // Switch to alternative API key
    useAlternativeKey = !useAlternativeKey;
    PXLog(@"[WeaponX] Trying %@ API key", useAlternativeKey ? @"fallback" : @"primary");
    
    // Reload map
    [self loadMapWithCompletionHandler:nil];
}

- (NSString *)googleMapsHTMLContent {
    // Use the appropriate API key
    NSString *apiKey = useAlternativeKey ? kGoogleMapsAPIKeyFallback : kGoogleMapsAPIKey;
    
    // Check if system is in dark mode
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
        PXLog(@"[WeaponX] Map using %@ mode", isDarkMode ? @"dark" : @"light");
    }
    
    // Load saved map type or use default
    NSString *savedMapType = [[NSUserDefaults standardUserDefaults] stringForKey:kMapTypeKey] ?: @"roadmap";
    PXLog(@"[WeaponX] Loading map with saved style: %@", savedMapType);
    
    // Create HTML content - avoiding multi-line string issues
    NSString *html = [NSString stringWithFormat:@"<!DOCTYPE html>"
                      "<html>"
                      "<head>"
                      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, user-scalable=no\">"
                      "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src * 'unsafe-inline' 'unsafe-eval' data: gap: https:\">"
                      "<style>"
                      "body, html, #map { height: 100%%; margin: 0; padding: 0; font-family: sans-serif; }"
                      "body { background-color: %@; }"
                      "#error-message { display: none; position: absolute; top: 50%%; left: 50%%; transform: translate(-50%%, -50%%); text-align: center; color: %@; padding: 20px; background: %@; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); z-index: 1000; }"
                      "</style>"
                      "<script>"
                      "var map, marker, markers = [], mapLoadTimeout, jsErrors = [], customPin = null, isPinModeActive = true;"
                      "var isDarkMode = %@;"
                      "var userLocationMarker = null, accuracyCircle = null;" // Add variables for user location display
                      
                      "function sendLog(message) {"
                      "  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "    window.webkit.messageHandlers.mapHandler.postMessage({type: 'jsLog', message: message});"
                      "  }"
                      "}"
                      
                      "window.onerror = function(message, source, line) {"
                      "  jsErrors.push({message:message, source:source, line:line});"
                      "  sendLog('JS Error: ' + message);"
                      "  showMapError('JavaScript error: ' + message);"
                      "  return true;"
                      "};"
                      
                      "window.onload = function() {"
                      "  sendLog('Window loaded');"
                      
                      "  mapLoadTimeout = setTimeout(function() {"
                      "    if (typeof google === 'undefined') {"
                      "      sendLog('Error: Google API not loaded');"
                      "      showMapError('Failed to load Google Maps API');"
                      "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "        window.webkit.messageHandlers.mapHandler.postMessage({type: 'mapError', error: 'API not loaded', details: {errors: jsErrors}});"
                      "      }"
                      "    }"
                      "  }, 10000);"
                      "};"
                      
                      "function showMapError(message) {"
                      "  var errorDiv = document.getElementById('error-message');"
                      "  if (errorDiv) {"
                      "    errorDiv.innerHTML = message + '<br><button onclick=\"retryLoading()\">Try Again</button>';"
                      "    errorDiv.style.display = 'block';"
                      "  }"
                      "  sendLog('Error shown: ' + message);"
                      "}"
                      
                      "function retryLoading() {"
                      "  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "    window.webkit.messageHandlers.mapHandler.postMessage({type: 'retry'});"
                      "  }"
                      "}"
                      
                      // Dark mode styles for the map
                      "var darkModeStyles = ["
                      "  {elementType: 'geometry', stylers: [{color: '#242f3e'}]},"
                      "  {elementType: 'labels.text.stroke', stylers: [{color: '#242f3e'}]},"
                      "  {elementType: 'labels.text.fill', stylers: [{color: '#746855'}]},"
                      "  {"
                      "    featureType: 'administrative.locality',"
                      "    elementType: 'labels.text.fill',"
                      "    stylers: [{color: '#d59563'}]"
                      "  },"
                      "  {"
                      "    featureType: 'poi',"
                      "    elementType: 'labels.text.fill',"
                      "    stylers: [{color: '#d59563'}]"
                      "  },"
                      "  {"
                      "    featureType: 'poi.park',"
                      "    elementType: 'geometry',"
                      "    stylers: [{color: '#263c3f'}]"
                      "  },"
                      "  {"
                      "    featureType: 'poi.park',"
                      "    elementType: 'labels.text.fill',"
                      "    stylers: [{color: '#6b9a76'}]"
                      "  },"
                      "  {"
                      "    featureType: 'road',"
                      "    elementType: 'geometry',"
                      "    stylers: [{color: '#38414e'}]"
                      "  },"
                      "  {"
                      "    featureType: 'road',"
                      "    elementType: 'geometry.stroke',"
                      "    stylers: [{color: '#212a37'}]"
                      "  },"
                      "  {"
                      "    featureType: 'road',"
                      "    elementType: 'labels.text.fill',"
                      "    stylers: [{color: '#9ca5b3'}]"
                      "  },"
                      "  {"
                      "    featureType: 'road.highway',"
                      "    elementType: 'geometry',"
                      "    stylers: [{color: '#746855'}]"
                      "  },"
                      "  {"
                      "    featureType: 'road.highway',"
                      "    elementType: 'geometry.stroke',"
                      "    stylers: [{color: '#1f2835'}]"
                      "  },"
                      "  {"
                      "    featureType: 'road.highway',"
                      "    elementType: 'labels.text.fill',"
                      "    stylers: [{color: '#f3d19c'}]"
                      "  },"
                      "  {"
                      "    featureType: 'transit',"
                      "    elementType: 'geometry',"
                      "    stylers: [{color: '#2f3948'}]"
                      "  },"
                      "  {"
                      "    featureType: 'transit.station',"
                      "    elementType: 'labels.text.fill',"
                      "    stylers: [{color: '#d59563'}]"
                      "  },"
                      "  {"
                      "    featureType: 'water',"
                      "    elementType: 'geometry',"
                      "    stylers: [{color: '#17263c'}]"
                      "  },"
                      "  {"
                      "    featureType: 'water',"
                      "    elementType: 'labels.text.fill',"
                      "    stylers: [{color: '#515c6d'}]"
                      "  },"
                      "  {"
                      "    featureType: 'water',"
                      "    elementType: 'labels.text.stroke',"
                      "    stylers: [{color: '#17263c'}]"
                      "  }"
                      "];"
                      
                      "function initMap() {"
                      "  sendLog('initMap called');"
                      "  clearTimeout(mapLoadTimeout);"
                      "  try {"
                      "    if (typeof google === 'undefined') throw new Error('Google API not available');"
                      "    if (typeof google.maps === 'undefined') throw new Error('Maps API not available');"
                      
                      "    var options = {"
                      "      center: {lat: 40.7128, lng: -74.0060}," // New York City coordinates
                      "      zoom: 13,"
                      "      mapTypeId: '%@'," // Use saved map type here
                      "      zoomControl: true,"
                      "      mapTypeControl: false,"
                      "      streetViewControl: false,"
                      "      fullscreenControl: false"
                      "    };"
                      
                      // Apply dark mode styles if dark mode is enabled
                      "    if (isDarkMode) {"
                      "      options.styles = darkModeStyles;"
                      "      sendLog('Applied dark mode styles to map');"
                      "    }"
                      
                      "    map = new google.maps.Map(document.getElementById('map'), options);"
                      "    sendLog('Map created successfully with type: ' + options.mapTypeId);"
                      
                      // Add click listener for pin placement
                      "    map.addListener('click', function(event) {"
                      "      if (isPinModeActive) {"
                      "        placeCustomPin(event.latLng, false);" // Initially place an unpinned (blue) pin
                      "      }"
                      "    });"
                      
                      "    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "      window.webkit.messageHandlers.mapHandler.postMessage({type: 'mapReady'});"
                      "    }"
                      "  } catch (e) {"
                      "    sendLog('Error in initMap: ' + e.message);"
                      "    showMapError('Error initializing map: ' + e.message);"
                      
                      "    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "      window.webkit.messageHandlers.mapHandler.postMessage({"
                      "        type: 'mapError',"
                      "        error: e.message,"
                      "        details: {stack: e.stack}"
                      "      });"
                      "    }"
                      "  }"
                      "}"
                      
                      "function gm_authFailure() {"
                      "  sendLog('Auth failure for Maps API key');"
                      "  showMapError('Google Maps API key is invalid');"
                      "  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "    window.webkit.messageHandlers.mapHandler.postMessage({type: 'mapError', error: 'API key error'});"
                      "  }"
                      "}"
                      
                      "function clearMarkers() {"
                      "  for (var i = 0; i < markers.length; i++) {"
                      "    markers[i].setMap(null);"
                      "  }"
                      "  markers = [];"
                      "}"
                      
                      "function centerOnLocation(lat, lng) {"
                      "  if (!map) return;"
                      "  var location = new google.maps.LatLng(lat, lng);"
                      "  map.setCenter(location);"
                      "  clearMarkers();"
                      "  marker = new google.maps.Marker({map: map, position: location, animation: google.maps.Animation.DROP});"
                      "  markers.push(marker);"
                      "}"
                      
                      "function searchLocation(query) {"
                      "  if (!map) return;"
                      "  var geocoder = new google.maps.Geocoder();"
                      "  sendLog('Searching for location: ' + query);"
                      "  geocoder.geocode({'address': query}, function(results, status) {"
                      "    if (status === 'OK') {"
                      "      sendLog('Found location: ' + results[0].formatted_address);"
                      "      clearMarkers();"
                      "      map.setCenter(results[0].geometry.location);"
                      "      marker = new google.maps.Marker({map: map, position: results[0].geometry.location});"
                      "      markers.push(marker);"
                      "      var infoWindow = new google.maps.InfoWindow({content: results[0].formatted_address});"
                      "      marker.addListener('click', function() { infoWindow.open(map, marker); });"
                      "      infoWindow.open(map, marker);"
                      
                      "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "        window.webkit.messageHandlers.mapHandler.postMessage({"
                      "          type: 'searchResult',"
                      "          success: true,"
                      "          address: results[0].formatted_address,"
                      "          lat: results[0].geometry.location.lat(),"
                      "          lng: results[0].geometry.location.lng()"
                      "        });"
                      "      }"
                      "    } else {"
                      "      var errorMessage = 'Location not found';"
                      "      switch(status) {"
                      "        case 'ZERO_RESULTS': errorMessage = 'No locations found matching your search'; break;"
                      "        case 'OVER_QUERY_LIMIT': errorMessage = 'Too many requests, please try again later'; break;"
                      "        case 'REQUEST_DENIED': errorMessage = 'Location search is not enabled with this API key'; break;"
                      "        case 'INVALID_REQUEST': errorMessage = 'Invalid search request'; break;"
                      "        case 'UNKNOWN_ERROR': errorMessage = 'Server error, please try again'; break;"
                      "        default: errorMessage = 'Location not found: ' + status; break;"
                      "      }"
                      "      sendLog('Search error: ' + status);"
                      "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "        window.webkit.messageHandlers.mapHandler.postMessage({"
                      "          type: 'searchResult',"
                      "          success: false,"
                      "          error: errorMessage"
                      "        });"
                      "      }"
                      "    }"
                      "  });"
                      "}"
                      
                      "function changeMapType(type) {"
                      "  if (map) map.setMapTypeId(type);"
                      "}"
                      
                      // Set pin mode
                      "function setPinMode(active) {"
                      "  isPinModeActive = active;"
                      "  sendLog('Pin mode ' + (active ? 'activated' : 'deactivated'));"
                      "  if (!active && customPin) {"
                      "    clearCustomPin();"
                      "  }"
                      "}"
                      
                      // Convert pixel coordinates to lat/lng
                      "function pixelPointToLatLng(point) {"
                      "  if (!map) return null;"
                      "  try {"
                      "    var topRight = map.getProjection().fromLatLngToPoint(map.getBounds().getNorthEast());"
                      "    var bottomLeft = map.getProjection().fromLatLngToPoint(map.getBounds().getSouthWest());"
                      "    var scale = Math.pow(2, map.getZoom());"
                      "    var worldPoint = new google.maps.Point("
                      "      (point.x / scale) + bottomLeft.x,"
                      "      (point.y / scale) + topRight.y"
                      "    );"
                      "    return map.getProjection().fromPointToLatLng(worldPoint);"
                      "  } catch (e) {"
                      "    sendLog('Error converting pixel to latlng: ' + e.message);"
                      "    return null;"
                      "  }"
                      "}"
                      
                      // Place custom pin
                      "function placeCustomPin(latLng, isPinned) {"
                      "  if (customPin) {"
                      "    customPin.setMap(null);"
                      "  }"
                      
                      "  var pinColor = isPinned ? '#00C853' : '#4285F4';"  // Green when pinned, blue otherwise
                      
                      "  customPin = new google.maps.Marker({"
                      "    position: latLng,"
                      "    map: map,"
                      "    draggable: true,"
                      "    animation: google.maps.Animation.DROP,"
                      "    icon: {"
                      "      url: 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent('"
                      "        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"42\" viewBox=\"0 0 32 42\">"
                      "          <g fill=\"none\" fill-rule=\"evenodd\">"
                      "            <path fill=\"' + pinColor + '\" d=\"M16,0 C7.2,0 0,7.2 0,16 C0,28 16,42 16,42 C16,42 32,28 32,16 C32,7.2 24.8,0 16,0 Z\"/>"
                      "            <circle fill=\"#FFFFFF\" cx=\"16\" cy=\"16\" r=\"10\"/>"
                      "            <circle fill=\"' + pinColor + '\" cx=\"16\" cy=\"16\" r=\"6\"/>"
                      "          </g>"
                      "        </svg>'),"
                      "      scaledSize: new google.maps.Size(40, 52),"
                      "      anchor: new google.maps.Point(20, 52),"
                      "      labelOrigin: new google.maps.Point(16, 16)"
                      "    }"
                      "  });"
                      
                      // Send coordinates to native code
                      "  sendPinCoordinates(latLng, isPinned);"
                      
                      // Add dragend listener to update coordinates when pin is moved
                      "  customPin.addListener('dragend', function() {"
                      "    sendPinCoordinates(customPin.getPosition(), isPinned);"
                      "  });"
                      
                      "  return customPin;"
                      "}"
                      
                      // Clear custom pin
                      "function clearCustomPin() {"
                      "  if (customPin) {"
                      "    customPin.setMap(null);"
                      "    customPin = null;"
                      "  }"
                      "}"
                      
                      // Send pin coordinates to native code
                      "function sendPinCoordinates(latLng, isPinned) {"
                      "  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "    window.webkit.messageHandlers.mapHandler.postMessage({"
                      "      type: 'pinCoordinates',"
                      "      lat: latLng.lat(),"
                      "      lng: latLng.lng(),"
                      "      isPinned: isPinned || false"
                      "    });"
                      "  }"
                      "}"
                      "</script>"
                      "</head>"
                      "<body>"
                      "<div id=\"map\"></div>"
                      "<div id=\"error-message\"></div>"
                      "</style>"
                      "<script>"
                      "  function safeInitMap() {"
                      "    try {"
                      "      if (typeof google === 'object' && typeof google.maps === 'object') {"
                      "        initMap();"
                      "      } else {"
                      "        setTimeout(safeInitMap, 100);"
                      "      }"
                      "    } catch (e) {"
                      "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapHandler) {"
                      "        window.webkit.messageHandlers.mapHandler.postMessage({"
                      "          type: 'mapError',"
                      "          error: e.message,"
                      "          details: {stack: e.stack}"
                      "        });"
                      "      }"
                      "    }"
                      "  }"
                      "  function loadGoogleMapsScript() {"
                      "    var script = document.createElement('script');"
                      "    script.src = 'https://maps.googleapis.com/maps/api/js?key=%@';"
                      "    script.async = true;"
                      "    script.defer = true;"
                      "    script.onload = safeInitMap;"
                      "    document.head.appendChild(script);"
                      "  }"
                      "  if (document.readyState === 'loading') {"
                      "    document.addEventListener('DOMContentLoaded', loadGoogleMapsScript);"
                      "  } else {"
                      "    loadGoogleMapsScript();"
                      "  }"
                      "</script>"
                      "<script>"
                      "</html>", 
                      // Pass dark/light mode colors to HTML
                      isDarkMode ? @"#121212" : @"#ffffff",  // background color
                      isDarkMode ? @"#ffffff" : @"#333333",  // error text color
                      isDarkMode ? @"#333333" : @"#ffffff",  // error background color
                      isDarkMode ? @"true" : @"false",       // isDarkMode JS variable
                      savedMapType,                          // saved map type
                      apiKey];                              // API key
    
    return html;
}

- (void)searchLocation:(NSString *)query {
    if (query.length == 0) {
        return;
    }
    
    NSString *script = [NSString stringWithFormat:@"searchLocation('%@');", [self escapeJavaScriptString:query]];
    [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[WeaponX] Error searching location: %@", error);
        }
    }];
}

- (void)centerMapOnUserLocation {
    PXLog(@"[WeaponX] Attempting to center map on user location");
    
    // Check authorization
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus; // Use instance method in iOS 14+
    } else {
        // Suppress deprecation warning for older iOS compatibility
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus]; // Use class method for older iOS
        #pragma clang diagnostic pop
    }
    
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || 
        status == kCLAuthorizationStatusAuthorizedAlways) {
        
        // Get the last known location
        CLLocation *location = self.locationManager.location;
        if (location) {
            // Use the actual location
            NSString *script = [NSString stringWithFormat:@"centerOnLocation(%f, %f);", 
                              location.coordinate.latitude, 
                              location.coordinate.longitude];
            [self.mapWebView evaluateJavaScript:script completionHandler:nil];
            PXLog(@"[WeaponX] Centering map on user location: %f, %f", 
                 location.coordinate.latitude, location.coordinate.longitude);
            
            // If we only have "When in Use" permission, suggest upgrading to "Always"
            if (status == kCLAuthorizationStatusAuthorizedWhenInUse) {
                static BOOL hasPromptedForAlwaysAuthorization = NO;
                if (!hasPromptedForAlwaysAuthorization) {
                    hasPromptedForAlwaysAuthorization = YES;
                    
                    UIAlertController *upgradeAlert = [UIAlertController alertControllerWithTitle:@"Enable Background Location" 
                                                                           message:@"For the best experience with location-based features, please allow 'Always' access to your location."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                    
                    UIAlertAction *upgradeAction = [UIAlertAction actionWithTitle:@"Enable" style:UIAlertActionStyleDefault 
                                                                         handler:^(UIAlertAction * _Nonnull action) {
                        [self.locationManager requestAlwaysAuthorization];
                    }];
                    
                    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil];
                    
                    [upgradeAlert addAction:upgradeAction];
                    [upgradeAlert addAction:laterAction];
                    
                    [self presentViewController:upgradeAlert animated:YES completion:nil];
                }
            }
        } else {
            // If no location available, show an alert
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Location Unavailable" 
                                                                         message:@"Could not determine your current location. Please make sure location services are enabled."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
    
            [self presentViewController:alert animated:YES completion:nil];
            PXLog(@"[WeaponX] Unable to get user location - no location available");
        }
    } else {
        // If not authorized, request authorization or show an alert
        if (status == kCLAuthorizationStatusNotDetermined) {
            // For iOS 15, start with When In Use then request Always
            if (@available(iOS 15.0, *)) {
                [self.locationManager requestWhenInUseAuthorization];
                
                // After a short delay, request Always permission
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self.locationManager requestAlwaysAuthorization];
                    PXLog(@"[WeaponX] Requesting upgrade to Always authorization after When In Use");
                });
            } else {
                [self.locationManager requestAlwaysAuthorization];
            }
            PXLog(@"[WeaponX] Requesting location authorization");
        } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
            // Show alert that location services are disabled, with direct option to go to settings
            [self showLocationSettingsAlert];
            PXLog(@"[WeaponX] Location access denied or restricted - showing settings alert");
        }
    }
}

#pragma mark - Helper Methods

- (NSString *)escapeJavaScriptString:(NSString *)string {
    NSMutableString *escapedString = [NSMutableString stringWithString:string];
    [escapedString replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    [escapedString replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    [escapedString replaceOccurrencesOfString:@"\'" withString:@"\\\'" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    [escapedString replaceOccurrencesOfString:@"\n" withString:@"\\n" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    [escapedString replaceOccurrencesOfString:@"\r" withString:@"\\r" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    [escapedString replaceOccurrencesOfString:@"\f" withString:@"\\f" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    [escapedString replaceOccurrencesOfString:@"\u2028" withString:@"\\u2028" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    [escapedString replaceOccurrencesOfString:@"\u2029" withString:@"\\u2029" options:NSLiteralSearch range:NSMakeRange(0, [escapedString length])];
    
    return escapedString;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    
    // Search if text is not empty
    if (textField.text.length > 0) {
        [self searchLocation:textField.text];
    }
    
    return YES;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    PXLog(@"[WeaponX] WebView started loading");
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    PXLog(@"[WeaponX] Navigation policy for URL: %@", navigationAction.request.URL);
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[WeaponX Debug] Map WebView did finish navigation");
    
    // Show the web view now that it's loaded
    self.mapWebView.hidden = NO;
    [self.loadingIndicator stopAnimating];
    
    // Initialize pickup/drop manager with the loaded webview
    if (!self.pickupDropManager) {
        // Setup pickup/drop manager if not already set up
        [self setupPickupDropManager];
    } else {
        // If manager exists but WebView wasn't set, initialize it
        [self.pickupDropManager initWithMapWebView:self.mapWebView];
    }
    
    // Load saved locations and show markers on map
    [self.pickupDropManager loadSavedLocations];
    [self.pickupDropManager updatePickupDropMarkersOnMap];
    
    // Execute the completion handler
    if (self.mapLoadCompletion) {
        self.mapLoadCompletion(YES);
        self.mapLoadCompletion = nil;
    }
    
    PXLog(@"[WeaponX] Map loaded successfully, markers updated");
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    // Handle navigation failure
    [self.loadingIndicator stopAnimating];
    self.statusLabel.hidden = NO;
    self.statusLabel.text = [NSString stringWithFormat:@"Failed to load map: %@", error.localizedDescription];
    PXLog(@"[WeaponX] Web view did fail navigation: %@", error);
    PXLog(@"[WeaponX] Error code: %ld, domain: %@", (long)error.code, error.domain);
    PXLog(@"[WeaponX] Error user info: %@", error.userInfo);
    
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        // Network-related error
        switch (error.code) {
            case NSURLErrorNotConnectedToInternet:
                PXLog(@"[WeaponX] Device is not connected to the internet");
                break;
            case NSURLErrorTimedOut:
                PXLog(@"[WeaponX] Connection timed out");
                break;
            case NSURLErrorCannotFindHost:
                PXLog(@"[WeaponX] Cannot find host: maps.googleapis.com");
                break;
            case NSURLErrorCannotConnectToHost:
                PXLog(@"[WeaponX] Cannot connect to host: maps.googleapis.com");
                break;
            default:
                PXLog(@"[WeaponX] Other URL error: %ld", (long)error.code);
                break;
        }
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    // Handle provisional navigation failure (initial request failure)
    [self.loadingIndicator stopAnimating];
    self.statusLabel.hidden = NO;
    self.statusLabel.text = [NSString stringWithFormat:@"Failed to load map resources: %@", error.localizedDescription];
    PXLog(@"[WeaponX] Web view did fail provisional navigation: %@", error);
    PXLog(@"[WeaponX] Error code: %ld, domain: %@", (long)error.code, error.domain);
    PXLog(@"[WeaponX] Error user info: %@", error.userInfo);
    
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        // Network-related error
        switch (error.code) {
            case NSURLErrorNotConnectedToInternet:
                PXLog(@"[WeaponX] Device is not connected to the internet - trying offline mode");
                [self loadOfflineMap];
                break;
            case NSURLErrorTimedOut:
                PXLog(@"[WeaponX] Connection timed out - try again or use alternative API");
                [self tryAlternativeAPIKey];
                break;
            default:
                PXLog(@"[WeaponX] Other URL error: %ld", (long)error.code);
                break;
        }
    }
}

- (void)loadOfflineMap {
    // Load a basic offline map with a message
    NSString *offlineHTML = @"<!DOCTYPE html>\
    <html>\
    <head>\
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, user-scalable=no\">\
        <style>\
            body {\
                font-family: -apple-system, system-ui, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, sans-serif;\
                display: flex;\
                justify-content: center;\
                align-items: center;\
                height: 100vh;\
                margin: 0;\
                background-color: #f8f9fa;\
                color: #343a40;\
                text-align: center;\
                padding: 20px;\
            }\
            .message {\
                max-width: 80%;\
            }\
            h1 {\
                font-size: 24px;\
                margin-bottom: 16px;\
            }\
            p {\
                font-size: 16px;\
                margin-bottom: 24px;\
            }\
            .retry-button {\
                background-color: #007bff;\
                color: white;\
                border: none;\
                padding: 12px 24px;\
                border-radius: 4px;\
                font-size: 16px;\
                cursor: pointer;\
            }\
        </style>\
    </head>\
    <body>\
        <div class=\"message\">\
            <h1>Map Unavailable</h1>\
            <p>Unable to load the map due to network connectivity issues. Please check your internet connection and try again.</p>\
            <button class=\"retry-button\" onclick=\"window.webkit.messageHandlers.mapHandler.postMessage({type: 'retry'});\">Retry</button>\
        </div>\
    </body>\
    </html>";
    
    [self.mapWebView loadHTMLString:offlineHTML baseURL:nil];
    PXLog(@"[WeaponX] Loaded offline map placeholder");
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"mapHandler"]) {
        NSDictionary *messageBody = message.body;
        NSString *messageType = messageBody[@"type"];
        
        PXLog(@"[WeaponX] Received message from WebView: %@", messageType);
        
        if ([messageType isEqualToString:@"mapReady"]) {
            // Map is ready
            [self.loadingIndicator stopAnimating];
            self.mapWebView.hidden = NO;
            PXLog(@"[WeaponX] Map is ready");
            
            // Set visibility on the UI thread to be safe
            dispatch_async(dispatch_get_main_queue(), ^{
                self.mapWebView.hidden = NO;
                self.statusLabel.hidden = YES;
            });
        }
        else if ([messageType isEqualToString:@"retry"]) {
            // User clicked retry button
            PXLog(@"[WeaponX] User requested retry for map loading");
            [self loadMapWithCompletionHandler:nil];
        }
        else if ([messageType isEqualToString:@"mapError"]) {
            // Handle map error
            NSString *error = messageBody[@"error"];
            [self.loadingIndicator stopAnimating];
            self.statusLabel.hidden = NO;
            self.statusLabel.text = [NSString stringWithFormat:@"Map Error: %@", error];
            PXLog(@"[WeaponX] Map error: %@", error);
            
            // Dump extra debug info if available
            if (messageBody[@"details"]) {
                PXLog(@"[WeaponX] Error details: %@", messageBody[@"details"]);
            }
            
            // Try alternative API key if this might be an API key issue
            if ([error containsString:@"API key"] || [error containsString:@"API"]) {
                // Show error with option to try again with a different key
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Map API Error" 
                                                                           message:@"There was a problem with the Google Maps API key. Would you like to try with a different provider?"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction *retryAction = [UIAlertAction actionWithTitle:@"Try Again" style:UIAlertActionStyleDefault 
                                                              handler:^(UIAlertAction * _Nonnull action) {
                    [self tryAlternativeAPIKey];
                }];
                
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
                
                [alert addAction:retryAction];
                [alert addAction:cancelAction];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
        else if ([messageType isEqualToString:@"jsLog"]) {
            // Direct log from JavaScript for debugging
            NSString *logMessage = messageBody[@"message"];
            PXLog(@"[WeaponX] JavaScript log: %@", logMessage);
        }
        else if ([messageType isEqualToString:@"searchResult"]) {
            // Handle search result
            BOOL success = [messageBody[@"success"] boolValue];
            
            if (success) {
                NSString *address = messageBody[@"address"];
                double latitude = [messageBody[@"lat"] doubleValue];
                double longitude = [messageBody[@"lng"] doubleValue];
                
                PXLog(@"[WeaponX] Found location: %@ at %f, %f", address, latitude, longitude);
                
                // Pass the search result to the handler to place a pin and show coordinates
                NSDictionary *resultData = @{
                    @"address": address,
                    @"lat": @(latitude),
                    @"lng": @(longitude)
                };
                [self handleMapSearchResult:resultData];
            } else {
                NSString *error = messageBody[@"error"];
                
                // Show error to user
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Location Not Found" 
                                                                               message:error 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                
                [self presentViewController:alert animated:YES completion:nil];
                
                PXLog(@"[WeaponX] Search failed: %@", error);
            }
        }
        else if ([messageType isEqualToString:@"pinCoordinates"]) {
            // Handle pin coordinates from JavaScript
            double latitude = [messageBody[@"lat"] doubleValue];
            double longitude = [messageBody[@"lng"] doubleValue];
            BOOL isPinned = [messageBody[@"isPinned"] boolValue];
            
            // Log coordinates without mentioning pin placement
            PXLog(@"[WeaponX] Received coordinates: %f, %f (isPinned: %@)", 
                 latitude, longitude, isPinned ? @"YES" : @"NO");
            
            // Save the current pin location for potential saving
            self.currentPinLocation = @{
                @"latitude": @(latitude),
                @"longitude": @(longitude),
                @"isPinned": @(isPinned)
            };
            
            // Update UI to show coordinates
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showCoordinates:latitude longitude:longitude];
                
                // Show the unpin button when a pin is placed
                self.unpinContainer.hidden = NO;
            });
        }
        else if ([messageType isEqualToString:@"mapMoved"]) {
            // Update pinned location circle position when map is moved
            [self checkPinnedLocationFromPlist];
        }
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // Only update the map if the view is visible
    if (self.isViewLoaded && self.view.window && locations.count > 0) {
        CLLocation *location = [locations lastObject];
        
        // Log the update but NO interaction with blue pointer or GPS spoofing
        PXLog(@"[WeaponX] Location updated: %f, %f - NO effect on blue pointer or GPS spoofing", 
             location.coordinate.latitude, location.coordinate.longitude);
        
        // Stop updating location after we get one update
        [self.locationManager stopUpdatingLocation];
        
        // DO NOT update any map markers or blue pointer in response to this event
        // This completely isolates the GPS spoofing UI from real location updates
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    PXLog(@"[WeaponX] Location error: %@", error.localizedDescription);
    
    // Show error to user
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Location Error" 
                                                                 message:error.localizedDescription
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    NSString *statusString;
    switch (status) {
        case kCLAuthorizationStatusNotDetermined:
            statusString = @"Not Determined";
            break;
        case kCLAuthorizationStatusRestricted:
            statusString = @"Restricted";
            break;
        case kCLAuthorizationStatusDenied:
            statusString = @"Denied";
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            statusString = @"Authorized When In Use";
            break;
        case kCLAuthorizationStatusAuthorizedAlways:
            statusString = @"Authorized Always";
            break;
        default:
            statusString = @"Unknown";
            break;
    }
    
    PXLog(@"[WeaponX] Location authorization status changed to: %@ (%d)", statusString, status);
    
    // Update permissions button icon when status changes
    [self updatePermissionsButtonIcon];
    
    // Check for precise location (iOS 14+)
    if (@available(iOS 14.0, *)) {
        NSString *accuracyString = (manager.accuracyAuthorization == CLAccuracyAuthorizationFullAccuracy) ? 
            @"Precise (Full Accuracy)" : @"Approximate (Reduced Accuracy)";
        PXLog(@"[WeaponX] Location accuracy setting: %@", accuracyString);
        
        // If reduced accuracy, request full accuracy on iOS 15+
        if (manager.accuracyAuthorization == CLAccuracyAuthorizationReducedAccuracy) {
            if (@available(iOS 15.0, *)) {
                [manager requestTemporaryFullAccuracyAuthorizationWithPurposeKey:@"LocationAccuracyUsageDescription"];
                PXLog(@"[WeaponX] Requesting temporary full accuracy for iOS 15+");
            }
            
            // Alert user that precise location would improve experience
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enable Precise Location" 
                                                               message:@"For the best mapping experience, please enable precise location in Settings."
                                                        preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault 
                                                               handler:^(UIAlertAction * _Nonnull action) {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] 
                                                 options:@{} completionHandler:nil];
            }];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Continue Anyway" style:UIAlertActionStyleCancel handler:nil];
            
            [alert addAction:settingsAction];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    
    // If the status is authorized, try to get the current location
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || 
        status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager startUpdatingLocation];
        
        // If only authorized for when in use, request always authorization
        if (status == kCLAuthorizationStatusAuthorizedWhenInUse) {
            // Wait a bit before requesting upgrade to avoid overwhelming the user
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.locationManager requestAlwaysAuthorization];
                PXLog(@"[WeaponX] Requesting upgrade to Always authorization");
            });
        }
    }
}

// For iOS 14+, handle accuracy authorization changes
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 140000
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager API_AVAILABLE(ios(14.0)) {
    // Update button when accuracy changes
    [self updatePermissionsButtonIcon];
    
    // Log the change
    if (@available(iOS 14.0, *)) {
        CLAuthorizationStatus status = manager.authorizationStatus;
        NSString *statusString;
        
        switch (status) {
            case kCLAuthorizationStatusNotDetermined:
                statusString = @"Not Determined";
                break;
            case kCLAuthorizationStatusRestricted:
                statusString = @"Restricted";
                break;
            case kCLAuthorizationStatusDenied:
                statusString = @"Denied";
                break;
            case kCLAuthorizationStatusAuthorizedWhenInUse:
                statusString = @"Authorized When In Use";
                break;
            case kCLAuthorizationStatusAuthorizedAlways:
                statusString = @"Authorized Always";
                break;
            default:
                statusString = @"Unknown";
                break;
        }
        
        NSString *accuracyString = (manager.accuracyAuthorization == CLAccuracyAuthorizationFullAccuracy) ? 
            @"Precise (Full Accuracy)" : @"Approximate (Reduced Accuracy)";
        
        PXLog(@"[WeaponX] Location authorization changed: %@, accuracy: %@", statusString, accuracyString);
        
        // Check for denied status
        if (status == kCLAuthorizationStatusDenied) {
            // Don't show the alert immediately, as it might be annoying
            // If the user tries to use a location feature, we'll show the alert then
            PXLog(@"[WeaponX] Location authorization denied - will prompt for settings when needed");
        } 
        
        // Handle precise location changes
        if (manager.accuracyAuthorization == CLAccuracyAuthorizationReducedAccuracy && 
            (status == kCLAuthorizationStatusAuthorizedWhenInUse || 
             status == kCLAuthorizationStatusAuthorizedAlways)) {
            
            // Show a notification to the user that precise location would improve the experience
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enable Precise Location" 
                                                          message:@"For the best mapping experience, please enable precise location."
                                                   preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault 
                                                          handler:^(UIAlertAction * _Nonnull action) {
                [self openLocationSettings];
            }];
            
            UIAlertAction *requestAction = [UIAlertAction actionWithTitle:@"Request Precision" style:UIAlertActionStyleDefault 
                                                         handler:^(UIAlertAction * _Nonnull action) {
                if (@available(iOS 15.0, *)) {
                    [manager requestTemporaryFullAccuracyAuthorizationWithPurposeKey:@"LocationAccuracyUsageDescription"];
                    PXLog(@"[WeaponX] Requesting temporary full accuracy");
                } else {
                    [self openLocationSettings];
                }
            }];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Continue Anyway" style:UIAlertActionStyleCancel handler:nil];
            
            [alert addAction:settingsAction];
            [alert addAction:requestAction];
            [alert addAction:cancelAction];
            
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}
#endif

// New method to create a map thumbnail image directly using Core Graphics
- (UIImage *)createMapThumbnailImage {
    CGSize size = CGSizeMake(50, 50);
    
    // Check for dark mode
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Create a satellite-like image background
    // Dark gradient background simulating satellite imagery - slightly different for dark/light mode
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[2] = {0.0, 1.0};
    CGFloat components[8];
    
    if (isDarkMode) {
        // Darker satellite colors for dark mode
        components[0] = 0.1; components[1] = 0.15; components[2] = 0.25; components[3] = 1.0; // Darker blue-gray
        components[4] = 0.2; components[5] = 0.25; components[6] = 0.35; components[7] = 1.0; // Slightly lighter
    } else {
        // Lighter satellite colors for light mode
        components[0] = 0.3; components[1] = 0.35; components[2] = 0.4; components[3] = 1.0; // Medium blue-gray
        components[4] = 0.4; components[5] = 0.45; components[6] = 0.5; components[7] = 1.0; // Lighter
    }
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, components, locations, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(size.width, size.height), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    // Simulate satellite imagery with city layout
    // Add some larger blocks for "buildings"
    for (int i = 0; i < 8; i++) {
        CGFloat x = (arc4random() % (int)(size.width - 12));
        CGFloat y = (arc4random() % (int)(size.height - 12));
        CGFloat width = 5 + (arc4random() % 7);
        CGFloat height = 5 + (arc4random() % 7);
        
        CGFloat brightness = 0.3 + (arc4random() % 40) / 100.0; // Vary brightness to simulate different buildings
        CGContextSetRGBFillColor(context, brightness, brightness, brightness + 0.05, 0.7);
        CGContextFillRect(context, CGRectMake(x, y, width, height));
    }
    
    // Add some "roads"
    CGContextSetRGBStrokeColor(context, 0.6, 0.6, 0.6, 0.8);
    CGContextSetLineWidth(context, 1.0);
    
    // Horizontal roads
    for (int i = 1; i < 5; i += 2) {
        CGFloat y = (size.height / 5) * i;
        CGContextMoveToPoint(context, 0, y);
        CGContextAddLineToPoint(context, size.width, y);
    }
    
    // Vertical roads
    for (int i = 1; i < 5; i += 2) {
        CGFloat x = (size.width / 5) * i;
        CGContextMoveToPoint(context, x, 0);
        CGContextAddLineToPoint(context, x, size.height);
    }
    
    CGContextStrokePath(context);
    
    // Add a translucent dark overlay at the bottom for text background
    CGFloat overlayHeight = 16;
    CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 0.6); // Semi-transparent black
    CGContextFillRect(context, CGRectMake(0, size.height - overlayHeight, size.width, overlayHeight));
    
    // Add "Layers" text inside the image
    UIFont *font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    
    NSDictionary *textAttributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSParagraphStyleAttributeName: paragraphStyle
    };
    
    NSString *text = @"Layers";
    CGSize textSize = [text sizeWithAttributes:textAttributes];
    CGFloat textX = (size.width - textSize.width) / 2;
    CGFloat textY = size.height - overlayHeight + (overlayHeight - textSize.height) / 2;
    
    [text drawAtPoint:CGPointMake(textX, textY) withAttributes:textAttributes];
    
    // Create a diamond logo overlay in the top left
    CGFloat logoSize = 12;
    CGFloat logoX = 4;
    CGFloat logoY = 4;
    
    // Draw white diamond shape
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 0.9);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, logoX + logoSize/2, logoY);
    CGContextAddLineToPoint(context, logoX + logoSize, logoY + logoSize/2);
    CGContextAddLineToPoint(context, logoX + logoSize/2, logoY + logoSize);
    CGContextAddLineToPoint(context, logoX, logoY + logoSize/2);
    CGContextClosePath(context);
    CGContextFillPath(context);
    
    UIImage *resultImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return resultImage;
}

// Add method to dismiss keyboard
- (void)dismissKeyboard:(UITapGestureRecognizer *)recognizer {
    // Check if the search text field is the first responder (keyboard is active)
    if ([self.searchTextField isFirstResponder]) {
        [self.searchTextField resignFirstResponder];
        PXLog(@"[WeaponX] Keyboard dismissed by tapping on map");
    }
}

// Add UIGestureRecognizerDelegate method to allow web view interaction
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // CRITICAL: Never allow GPS spoofing gestures to interact with map gestures
    // This prevents the GPS spoofing toggle from affecting the blue pointer
    
    // Check if either gesture is related to the GPS spoofing UI
    if ([gestureRecognizer.view isDescendantOfView:self.gpsSpoofingBar] || 
        [otherGestureRecognizer.view isDescendantOfView:self.gpsSpoofingBar]) {
        // NEVER allow GPS spoofing gestures to interact with other gestures
        return NO;
    }
    
    // If one is our tap for pin placement and one is for dismissing keyboard, don't recognize simultaneously
    if ((gestureRecognizer == self.tapGesture && [otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && otherGestureRecognizer != self.tapGesture) ||
        (otherGestureRecognizer == self.tapGesture && [gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && gestureRecognizer != self.tapGesture)) {
        return NO;
    }
    
    // Allow all other gesture combinations
    return YES;
}

// Add method to handle Done button tap
- (void)doneButtonTapped {
    [self.searchTextField resignFirstResponder];
}

// Add new method to setup GPS Spoofing bar
- (void)setupGpsSpoofingBar {
    // Create a completely isolated container for the GPS spoofing UI
    // This ensures no touch events propagate to the map and affect the blue pointer
    
    // Determine if in dark mode
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    }
    
    // IMPORTANT: Create an isolated touch container to prevent ANY interaction with map
    UIView *isolatedContainer = [[UIView alloc] init];
    isolatedContainer.translatesAutoresizingMaskIntoConstraints = NO;
    isolatedContainer.backgroundColor = [UIColor clearColor];
    isolatedContainer.userInteractionEnabled = YES; // Captures all touches within it
    [self.mapWebView addSubview:isolatedContainer];
    
    // Create a background view for the glassy effect
    UIView *glassyBackground = [[UIView alloc] init];
    glassyBackground.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Set background properties for glassy effect based on mode
    if (isDarkMode) {
        glassyBackground.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.3]; // Very transparent dark
    } else {
        glassyBackground.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.3]; // Very transparent white
    }
    glassyBackground.layer.cornerRadius = 12;
    glassyBackground.clipsToBounds = YES;
    
    // Add blur effect for a more glassy look (iOS 8+) with appropriate style
    UIBlurEffect *blurEffect;
    if (isDarkMode) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight];
    }
    
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.layer.cornerRadius = 12;
    blurView.clipsToBounds = YES;
    blurView.alpha = 0.3; // Very subtle blur
    
    // Create GPS spoofing bar - using a transparent container INSIDE the isolated container
    self.gpsSpoofingBar = [[UIView alloc] init];
    self.gpsSpoofingBar.backgroundColor = [UIColor clearColor];
    self.gpsSpoofingBar.translatesAutoresizingMaskIntoConstraints = NO;
    [isolatedContainer addSubview:self.gpsSpoofingBar]; // Add to isolated container, not directly to map
    
    // Add the blurry background to the container
    [self.gpsSpoofingBar addSubview:glassyBackground];
    [self.gpsSpoofingBar addSubview:blurView];
    
    // CRITICAL: Ensure touch events are fully contained, not propagated to map
    isolatedContainer.userInteractionEnabled = YES;
    self.gpsSpoofingBar.userInteractionEnabled = YES;
    
    // Add a specific tap gesture recognizer that fully consumes touches
    UITapGestureRecognizer *spoofingBarTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gpsSpoofingBarTapped:)];
    spoofingBarTapRecognizer.cancelsTouchesInView = YES; // Explicitly prevent touches from propagating
    [self.gpsSpoofingBar addGestureRecognizer:spoofingBarTapRecognizer];
    
    // Add tap recognizer to the isolated container too to catch any touches that might leak
    UITapGestureRecognizer *containerTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gpsSpoofingBarTapped:)];
    containerTapRecognizer.cancelsTouchesInView = YES;
    [isolatedContainer addGestureRecognizer:containerTapRecognizer];
    
    // Create the first part of the arrow text label with dotted style (horizontal now)
    UILabel *gpsSpoofingLabelStart = [[UILabel alloc] init];
    gpsSpoofingLabelStart.text = @"←------------ GPS";
    gpsSpoofingLabelStart.textColor = [UIColor systemBlueColor];
    gpsSpoofingLabelStart.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    gpsSpoofingLabelStart.textAlignment = NSTextAlignmentRight;
    gpsSpoofingLabelStart.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gpsSpoofingBar addSubview:gpsSpoofingLabelStart];
    
    // Create second part of the text (after "GPS")
    UILabel *spoofingLabel = [[UILabel alloc] init];
    spoofingLabel.text = @"SPOOFING";
    spoofingLabel.textColor = [UIColor systemBlueColor];
    spoofingLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold]; // Slightly larger and bold
    spoofingLabel.textAlignment = NSTextAlignmentLeft;
    spoofingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gpsSpoofingBar addSubview:spoofingLabel];
    
    // Create third part (end of arrow)
    UILabel *arrowEndLabel = [[UILabel alloc] init];
    arrowEndLabel.text = @"----→";
    arrowEndLabel.textColor = [UIColor systemBlueColor];
    arrowEndLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    arrowEndLabel.textAlignment = NSTextAlignmentLeft;
    arrowEndLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gpsSpoofingBar addSubview:arrowEndLabel];
    
    // Add switch control inside a dedicated container for isolation
    UIView *switchContainer = [[UIView alloc] init];
    switchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    switchContainer.backgroundColor = [UIColor clearColor];
    switchContainer.userInteractionEnabled = YES; // Critical - this container will catch all switch touches
    [self.gpsSpoofingBar addSubview:switchContainer];
    
    // Add switch to the container (not directly to spoofing bar)
    self.gpsSpoofingSwitch = [[UISwitch alloc] init];
    self.gpsSpoofingSwitch.onTintColor = [UIColor systemBlueColor];
    // Make the switch more compact
    self.gpsSpoofingSwitch.transform = CGAffineTransformMakeScale(0.4, 0.4);
    self.gpsSpoofingSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gpsSpoofingSwitch addTarget:self action:@selector(gpsSpoofingSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [switchContainer addSubview:self.gpsSpoofingSwitch]; // Add to container, not directly to bar
    
    // Ensure switch is OFF by default, avoid loading any state
    self.gpsSpoofingSwitch.on = NO; // Always start with OFF to avoid injecting any state
    
    // Position the isolated container
    [NSLayoutConstraint activateConstraints:@[
        [isolatedContainer.leadingAnchor constraintEqualToAnchor:self.mapWebView.leadingAnchor constant:40],
        [isolatedContainer.bottomAnchor constraintEqualToAnchor:self.mapWebView.bottomAnchor constant:-5],
        [isolatedContainer.widthAnchor constraintEqualToConstant:320], // Wider to fully contain everything including dotted line
        [isolatedContainer.heightAnchor constraintEqualToConstant:50]  // Taller to ensure touch capture
    ]];
    
    // Set constraints for GPS spoofing bar inside the isolated container
    [NSLayoutConstraint activateConstraints:@[
        [self.gpsSpoofingBar.centerXAnchor constraintEqualToAnchor:isolatedContainer.centerXAnchor],
        [self.gpsSpoofingBar.centerYAnchor constraintEqualToAnchor:isolatedContainer.centerYAnchor],
        [self.gpsSpoofingBar.widthAnchor constraintEqualToConstant:300], // Increased width to ensure text fits
        [self.gpsSpoofingBar.heightAnchor constraintEqualToConstant:30]
    ]];
    
    // Make the glassy background cover the entire bar with some padding
    [NSLayoutConstraint activateConstraints:@[
        [glassyBackground.topAnchor constraintEqualToAnchor:self.gpsSpoofingBar.topAnchor constant:-4],
        [glassyBackground.bottomAnchor constraintEqualToAnchor:self.gpsSpoofingBar.bottomAnchor constant:4],
        [glassyBackground.leadingAnchor constraintEqualToAnchor:self.gpsSpoofingBar.leadingAnchor constant:-8],
        [glassyBackground.trailingAnchor constraintEqualToAnchor:self.gpsSpoofingBar.trailingAnchor constant:8]
    ]];
    
    // Make the blur view match the glassy background
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:glassyBackground.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:glassyBackground.bottomAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:glassyBackground.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:glassyBackground.trailingAnchor]
    ]];
    
    // Position switch container in center
    [NSLayoutConstraint activateConstraints:@[
        [switchContainer.centerYAnchor constraintEqualToAnchor:self.gpsSpoofingBar.centerYAnchor],
        [switchContainer.widthAnchor constraintEqualToConstant:60], // Wider than the switch to ensure all touches are caught
        [switchContainer.heightAnchor constraintEqualToConstant:30]
    ]];
    
    // Position the switch within its container
    [NSLayoutConstraint activateConstraints:@[
        [self.gpsSpoofingSwitch.centerXAnchor constraintEqualToAnchor:switchContainer.centerXAnchor],
        [self.gpsSpoofingSwitch.centerYAnchor constraintEqualToAnchor:switchContainer.centerYAnchor]
    ]];
    
    // Position the elements horizontally
    [NSLayoutConstraint activateConstraints:@[
        // First part of label (←------------ GPS)
        [gpsSpoofingLabelStart.leadingAnchor constraintEqualToAnchor:self.gpsSpoofingBar.leadingAnchor constant:8],
        [gpsSpoofingLabelStart.centerYAnchor constraintEqualToAnchor:self.gpsSpoofingBar.centerYAnchor],
        [gpsSpoofingLabelStart.trailingAnchor constraintEqualToAnchor:switchContainer.leadingAnchor constant:-2],
        
        // Switch container positioned after label
        [switchContainer.leadingAnchor constraintEqualToAnchor:gpsSpoofingLabelStart.trailingAnchor constant:2],
        
        // SPOOFING label after switch
        [spoofingLabel.leadingAnchor constraintEqualToAnchor:switchContainer.trailingAnchor constant:2],
        [spoofingLabel.centerYAnchor constraintEqualToAnchor:self.gpsSpoofingBar.centerYAnchor],
        
        // End arrow part - ensure it stays within container
        [arrowEndLabel.leadingAnchor constraintEqualToAnchor:spoofingLabel.trailingAnchor],
        [arrowEndLabel.centerYAnchor constraintEqualToAnchor:self.gpsSpoofingBar.centerYAnchor],
        [arrowEndLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.gpsSpoofingBar.trailingAnchor constant:-8],
    ]];
    
    // Add subtle shadow to the glassy background for better visibility
    glassyBackground.layer.shadowColor = [UIColor blackColor].CGColor;
    glassyBackground.layer.shadowOffset = CGSizeMake(0, 1);
    glassyBackground.layer.shadowOpacity = isDarkMode ? 0.15 : 0.1;
    glassyBackground.layer.shadowRadius = 2;
    
    // Store reference to the background for theme changes
    objc_setAssociatedObject(self, "gpsSpoofingBackgroundView", glassyBackground, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "gpsSpoofingBlurView", blurView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "gpsSpoofingIsolatedContainer", isolatedContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Log the setup of a completely isolated GPS spoofing UI
    PXLog(@"[WeaponX] Setting up FULLY ISOLATED GPS Spoofing UI with touch event containment");
    
    // Setup advanced GPS spoofing UI
    [self setupAdvancedGpsSpoofingUI];
}

// Method to handle taps on the GPS spoofing bar
- (void)gpsSpoofingBarTapped:(UITapGestureRecognizer *)recognizer {
    // Ensure the tap is COMPLETELY consumed and doesn't propagate to the map view
    recognizer.cancelsTouchesInView = YES;
    
    // Explicitly stop the event propagation
    PXLog(@"[WeaponX] GPS Spoofing bar tapped - FULLY CONSUMING touch event to prevent ANY map/pin interaction");
    
    // Do not call any other methods or allow any map interactions
    // This method only handles the tap on the GPS spoofing bar UI
}

// Add method to handle GPS spoofing switch changes
- (void)gpsSpoofingSwitchChanged:(UISwitch *)sender {
    // ABSOLUTELY ESSENTIAL: Set UISwitch inside a UIView container to prevent touch event propagation
    // This prevents the toggle from affecting the map pointer
    sender.superview.userInteractionEnabled = YES;
    
    BOOL isEnabled = sender.isOn;
    PXLog(@"[WeaponX] GPS Spoofing UI toggle: %@", isEnabled ? @"enabled" : @"disabled");
    
    LocationSpoofingManager *spoofingManager = [LocationSpoofingManager sharedManager];
    
    if (isEnabled) {
        // Only enable if we have valid pin coordinates
        if (self.currentPinLocation && self.currentPinLocation[@"latitude"] && self.currentPinLocation[@"longitude"]) {
            double latitude = [self.currentPinLocation[@"latitude"] doubleValue];
            double longitude = [self.currentPinLocation[@"longitude"] doubleValue];
            
            // Enable spoofing with current pin coordinates
            [spoofingManager enableSpoofingWithLatitude:latitude longitude:longitude];
            [self updateGpsSpoofingUIState:YES];
        } else {
            // No pin set, can't enable spoofing
            [sender setOn:NO animated:YES];
            [self showToastWithMessage:@"Please place a pin first"];
            PXLog(@"[WeaponX] Can't enable GPS spoofing - no pin coordinates");
        }
    } else {
        // Disable spoofing
        [spoofingManager disableSpoofing];
        [self updateGpsSpoofingUIState:NO];
    }
}

// Load GPS spoofing state from NSUserDefaults
- (BOOL)loadGpsSpoofingState {
    // Always return false - GPS spoofing is completely isolated
    return NO;
}

// Save GPS spoofing state to NSUserDefaults
- (void)saveGpsSpoofingState:(BOOL)enabled {
    // Completely empty - no state is saved to avoid any side effects
}

// Enable GPS spoofing
- (void)enableGpsSpoofing {
    // Visual feedback only
    PXLog(@"[WeaponX] GPS Spoofing UI enabled (VISUAL ONLY)");
}

// Disable GPS spoofing
- (void)disableGpsSpoofing {
    // Visual feedback only
    PXLog(@"[WeaponX] GPS Spoofing UI disabled (VISUAL ONLY)");
    
    // Update the switch state if needed
    if (self.gpsSpoofingSwitch.on) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.gpsSpoofingSwitch.on = NO;
        });
    }
}

// Update GPS spoofing UI state
- (void)updateGpsSpoofingUIState:(BOOL)enabled {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update the switch state
        [self.gpsSpoofingSwitch setOn:enabled animated:YES];
        
        // Update visual feedback
        if (enabled) {
            [self showToastWithMessage:@"GPS Spoofing enabled"];
        } else {
            [self showToastWithMessage:@"GPS Spoofing disabled"];
        }
    });
}

// Remove GPS spoofing location from settings
- (void)removeGPSSpoofingLocation {
    // Visual feedback only
    PXLog(@"[WeaponX] GPS Spoofing functionality will be implemented in the future");
}

// Check for saved GPS spoofing location and restore pin if available
- (void)checkForSavedGPSSpoofingLocation {
    // Completely empty implementation to avoid any interaction
}

// Save current pin location to GPS spoofing settings
- (void)saveGPSSpoofingLocation {
    // Visual feedback only
    PXLog(@"[WeaponX] GPS Spoofing functionality will be implemented in the future");
}

// Show spoofed location on map
- (void)showSpoofedLocation:(double)latitude longitude:(double)longitude {
    // Visual feedback only
    PXLog(@"[WeaponX] GPS Spoofing functionality will be implemented in the future");
}

// Show save location prompt for spoofing
- (void)showSaveLocationPromptForSpoofing {
    // Completely visual only - no pin interaction
    PXLog(@"[WeaponX] GPS Spoofing prompt functionality will be implemented in the future");
    
    // Just show a toast but avoid any real functionality
    [self showToastWithMessage:@"GPS Spoofing will be available in a future update"];
}

// Setup permissions button
- (void)setupPermissionsButton {
    self.permissionsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    // Set the icon based on the current permission status
    [self updatePermissionsButtonIcon];
    
    self.permissionsButton.tintColor = [UIColor systemBlueColor];
    [self.permissionsButton addTarget:self action:@selector(permissionsButtonTapped) forControlEvents:UIControlEventTouchUpInside];
}

// Update the permissions button icon based on current status
- (void)updatePermissionsButtonIcon {
    UIImage *permissionIcon;
    
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus];
        #pragma clang diagnostic pop
    }
    
    switch (status) {
        case kCLAuthorizationStatusAuthorizedAlways:
            permissionIcon = [UIImage systemImageNamed:@"location.fill.viewfinder"];
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            permissionIcon = [UIImage systemImageNamed:@"location.viewfinder"];
            break;
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            permissionIcon = [UIImage systemImageNamed:@"location.slash.fill"];
            break;
        case kCLAuthorizationStatusNotDetermined:
        default:
            permissionIcon = [UIImage systemImageNamed:@"location.circle"];
            break;
    }
    
    [self.permissionsButton setImage:permissionIcon forState:UIControlStateNormal];
}

// Handle tapping on the permissions button
- (void)permissionsButtonTapped {
    [self showLocationPermissionsMenu];
}

// Show location permissions menu
- (void)showLocationPermissionsMenu {
    // Get current permission status
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus];
        #pragma clang diagnostic pop
    }
    
    // Create alert controller with current status
    NSString *statusMessage;
    switch (status) {
        case kCLAuthorizationStatusAuthorizedAlways:
            statusMessage = @"Current status: Always allowed";
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            statusMessage = @"Current status: Allowed while using app";
            break;
        case kCLAuthorizationStatusDenied:
            statusMessage = @"Current status: Denied";
            break;
        case kCLAuthorizationStatusRestricted:
            statusMessage = @"Current status: Restricted";
            break;
        case kCLAuthorizationStatusNotDetermined:
            statusMessage = @"Current status: Not determined";
            break;
        default:
            statusMessage = @"Current status: Unknown";
            break;
    }
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Location Permissions" 
                                                                          message:statusMessage 
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Check for precise location (iOS 14+)
    if (@available(iOS 14.0, *)) {
        NSString *accuracyStatus = (self.locationManager.accuracyAuthorization == CLAccuracyAuthorizationFullAccuracy) ? 
            @"Precise location: Enabled" : @"Precise location: Reduced accuracy";
        
        // Update alert message to include accuracy info
        alertController.message = [NSString stringWithFormat:@"%@\n%@", statusMessage, accuracyStatus];
    }
    
    // Add actions based on current status
    if (status == kCLAuthorizationStatusNotDetermined) {
        [alertController addAction:[UIAlertAction actionWithTitle:@"Request When In Use Permission" 
                                                     style:UIAlertActionStyleDefault 
                                                   handler:^(UIAlertAction * _Nonnull action) {
            [self.locationManager requestWhenInUseAuthorization];
        }]];
        
        [alertController addAction:[UIAlertAction actionWithTitle:@"Request Always Permission" 
                                                     style:UIAlertActionStyleDefault 
                                                   handler:^(UIAlertAction * _Nonnull action) {
            [self.locationManager requestAlwaysAuthorization];
        }]];
    } else if (status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        [alertController addAction:[UIAlertAction actionWithTitle:@"Request Always Permission" 
                                                     style:UIAlertActionStyleDefault 
                                                   handler:^(UIAlertAction * _Nonnull action) {
            [self.locationManager requestAlwaysAuthorization];
        }]];
    }
    
    // For iOS 14+, add action to request full accuracy if currently reduced
    if (@available(iOS 14.0, *)) {
        if (self.locationManager.accuracyAuthorization == CLAccuracyAuthorizationReducedAccuracy) {
            [alertController addAction:[UIAlertAction actionWithTitle:@"Request Precise Location" 
                                                         style:UIAlertActionStyleDefault 
                                                       handler:^(UIAlertAction * _Nonnull action) {
                if (@available(iOS 15.0, *)) {
                    // Check if location access is already granted
                    CLAuthorizationStatus currentStatus = self.locationManager.authorizationStatus;
                    
                    if (currentStatus == kCLAuthorizationStatusDenied || 
                        currentStatus == kCLAuthorizationStatusRestricted) {
                        // If location access is denied, direct to settings instead
                        [self showLocationSettingsAlert];
                    } else {
                        // Otherwise, request temporary full accuracy
                        [self.locationManager requestTemporaryFullAccuracyAuthorizationWithPurposeKey:@"LocationAccuracyUsageDescription"];
                        PXLog(@"[WeaponX] Requesting temporary full accuracy");
                    }
                } else {
                    // For iOS 14, direct to settings since we can't directly request
                    [self showLocationSettingsAlert];
                }
            }]];
        }
    }
    
    // Always add option to open system settings
    [alertController addAction:[UIAlertAction actionWithTitle:@"Open Settings" 
                                                 style:UIAlertActionStyleDefault 
                                               handler:^(UIAlertAction * _Nonnull action) {
        [self openLocationSettings];
    }]];
    
    // Add cancel action
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                                 style:UIAlertActionStyleCancel 
                                               handler:nil]];
    
    // For iPad, set source for popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alertController.popoverPresentationController.sourceView = self.favoritesContainer;
        alertController.popoverPresentationController.sourceRect = self.favoritesContainer.bounds;
    }
    
    [self presentViewController:alertController animated:YES completion:nil];
}

// Add pin mode button setup
- (void)setupPinModeButton {
    self.pinModeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    // Create a circular button with a pin icon (using mappin.and.ellipse)
    UIImage *pinIcon = [UIImage systemImageNamed:@"mappin.and.ellipse"];
    [self.pinModeButton setImage:pinIcon forState:UIControlStateNormal];
    
    // Style the button
    self.pinModeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    self.pinModeButton.tintColor = [UIColor systemBlueColor];
    self.pinModeButton.layer.cornerRadius = 25;
    self.pinModeButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.pinModeButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.pinModeButton.layer.shadowOpacity = 0.3;
    self.pinModeButton.layer.shadowRadius = 3;
    
    [self.pinModeButton addTarget:self action:@selector(pinModeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.pinModeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mapWebView addSubview:self.pinModeButton];
    
    // Position at the right side of the screen
    [NSLayoutConstraint activateConstraints:@[
        [self.pinModeButton.trailingAnchor constraintEqualToAnchor:self.mapWebView.trailingAnchor constant:-16],
        [self.pinModeButton.centerYAnchor constraintEqualToAnchor:self.mapWebView.centerYAnchor],
        [self.pinModeButton.widthAnchor constraintEqualToConstant:50],
        [self.pinModeButton.heightAnchor constraintEqualToConstant:50]
    ]];
}

// Add coordinates display setup
- (void)setupCoordinatesDisplay {
    // Create a container for coordinates display
    self.coordinatesContainer = [[UIView alloc] init];
    self.coordinatesContainer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    self.coordinatesContainer.layer.cornerRadius = 8;
    self.coordinatesContainer.clipsToBounds = YES;
    self.coordinatesContainer.hidden = YES; // Initially hidden
    self.coordinatesContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add tap gesture to copy coordinates
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyCoordinates)];
    [self.coordinatesContainer addGestureRecognizer:tapGesture];
    
    [self.mapWebView addSubview:self.coordinatesContainer];
    
    // Create the label to display coordinates
    self.coordinatesLabel = [[UILabel alloc] init];
    self.coordinatesLabel.textColor = [UIColor whiteColor];
    self.coordinatesLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    self.coordinatesLabel.textAlignment = NSTextAlignmentCenter;
    self.coordinatesLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.coordinatesLabel.numberOfLines = 0;
    
    // Add a copy hint
    UILabel *copyHintLabel = [[UILabel alloc] init];
    copyHintLabel.text = @"Tap to copy";
    copyHintLabel.textColor = [UIColor lightGrayColor];
    copyHintLabel.font = [UIFont systemFontOfSize:10];
    copyHintLabel.textAlignment = NSTextAlignmentCenter;
    copyHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.coordinatesContainer addSubview:self.coordinatesLabel];
    [self.coordinatesContainer addSubview:copyHintLabel];
    
    // Position at the bottom of the screen
    [NSLayoutConstraint activateConstraints:@[
        [self.coordinatesContainer.centerXAnchor constraintEqualToAnchor:self.mapWebView.centerXAnchor],
        [self.coordinatesContainer.bottomAnchor constraintEqualToAnchor:self.mapWebView.bottomAnchor constant:-70],
        [self.coordinatesContainer.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        
        [self.coordinatesLabel.topAnchor constraintEqualToAnchor:self.coordinatesContainer.topAnchor constant:6],
        [self.coordinatesLabel.leadingAnchor constraintEqualToAnchor:self.coordinatesContainer.leadingAnchor constant:8],
        [self.coordinatesLabel.trailingAnchor constraintEqualToAnchor:self.coordinatesContainer.trailingAnchor constant:-8],
        
        [copyHintLabel.topAnchor constraintEqualToAnchor:self.coordinatesLabel.bottomAnchor constant:2],
        [copyHintLabel.leadingAnchor constraintEqualToAnchor:self.coordinatesContainer.leadingAnchor],
        [copyHintLabel.trailingAnchor constraintEqualToAnchor:self.coordinatesContainer.trailingAnchor],
        [copyHintLabel.bottomAnchor constraintEqualToAnchor:self.coordinatesContainer.bottomAnchor constant:-6]
    ]];
}

// Handle pin mode button tap
- (void)pinModeButtonTapped {
    // Store label references
    UILabel *pinLabel = nil;
    UILabel *unpinLabel = nil;
    
    // Find the labels in the container
    for (UIView *subview in self.unpinContainer.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"Pin"]) {
                pinLabel = label;
            } else if ([label.text isEqualToString:@"Unpin"]) {
                unpinLabel = label;
            }
        }
    }
    
    // Save the current location data to NSUserDefaults
    [self savePinnedLocationToUserDefaults];
    
    // Get the coordinates from currentPinLocation
    if (self.currentPinLocation) {
        double latitude = [self.currentPinLocation[@"latitude"] doubleValue];
        double longitude = [self.currentPinLocation[@"longitude"] doubleValue];
        
        // Update the currentPinLocation isPinned status
        NSMutableDictionary *updatedPinLocation = [NSMutableDictionary dictionaryWithDictionary:self.currentPinLocation];
        updatedPinLocation[@"isPinned"] = @YES;
        self.currentPinLocation = updatedPinLocation;
        
        // Update the pin to a green pin (isPinned=true)
        NSString *script = [NSString stringWithFormat:@"placeCustomPin(new google.maps.LatLng(%f, %f), true);", 
                          latitude, longitude];
        
        [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (error) {
                PXLog(@"[WeaponX] Error updating pin color: %@", error);
            } else {
                PXLog(@"[WeaponX] Successfully updated pin to green");
            }
        }];
    }
    
    // UI-only implementation
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pinButton.hidden = YES;
        if (pinLabel) pinLabel.hidden = YES;
        
        self.unpinButton.hidden = NO;
        if (unpinLabel) unpinLabel.hidden = NO;
        
        // Show confirmation
        [self showToastWithMessage:@"Location marked"];
        
        // Terminate all enabled scoped apps after pinning location
        [self terminateEnabledScopedApps];
    });
    
    // Refresh header view after pinning
    [LocationHeaderView createHeaderViewWithTitle:@"Map" 
                                navigationItem:self.navigationItem 
                                 updateHandler:^{
        // Add any map-specific update handling if needed
    }];
}

// Add unpinButtonTapped method
- (void)unpinButtonTapped {
    // Store label references
    UILabel *pinLabel = nil;
    UILabel *unpinLabel = nil;
    
    // Find the labels in the container
    for (UIView *subview in self.unpinContainer.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"Pin"]) {
                pinLabel = label;
            } else if ([label.text isEqualToString:@"Unpin"]) {
                unpinLabel = label;
            }
        }
    }
    
    // Remove the pinned location data from NSUserDefaults
    [self removePinnedLocationFromUserDefaults];
    
    // Get the coordinates from currentPinLocation
    if (self.currentPinLocation) {
        double latitude = [self.currentPinLocation[@"latitude"] doubleValue];
        double longitude = [self.currentPinLocation[@"longitude"] doubleValue];
        
        // Update the pin to a blue pin (isPinned=false)
        NSString *script = [NSString stringWithFormat:@"placeCustomPin(new google.maps.LatLng(%f, %f), false);", 
                          latitude, longitude];
        
        [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (error) {
                PXLog(@"[WeaponX] Error updating pin color: %@", error);
            } else {
                PXLog(@"[WeaponX] Successfully updated pin to blue");
                
                // Update the currentPinLocation isPinned status
                NSMutableDictionary *updatedPinLocation = [NSMutableDictionary dictionaryWithDictionary:self.currentPinLocation];
                updatedPinLocation[@"isPinned"] = @NO;
                self.currentPinLocation = updatedPinLocation;
            }
        }];
    }
    
    // UI update
    dispatch_async(dispatch_get_main_queue(), ^{
        self.unpinButton.hidden = YES;
        if (unpinLabel) unpinLabel.hidden = YES;
        
        self.pinButton.hidden = NO;
        if (pinLabel) pinLabel.hidden = NO;
        
        // Optionally hide coordinates container
        self.coordinatesContainer.hidden = YES;
        
        // Show confirmation without "pin" terminology
        [self showToastWithMessage:@"Location unmarked"];
        
        // Terminate all enabled scoped apps after unpinning location
        [self terminateEnabledScopedApps];
    });
    
    // Refresh header view after unpinning
    [LocationHeaderView createHeaderViewWithTitle:@"Map" 
                                navigationItem:self.navigationItem 
                                 updateHandler:^{
        // Add any map-specific update handling if needed
    }];
}

// Show coordinates and update the UI
- (void)showCoordinates:(double)latitude longitude:(double)longitude {
    // Format the coordinates string with less decimal places for a more compact display
    NSString *coordsText = [NSString stringWithFormat:@"📍 %.5f, %.5f", latitude, longitude];
    self.coordinatesLabel.text = coordsText;
    
    // Show the coordinates container
    self.coordinatesContainer.hidden = NO;
    self.coordinatesContainer.alpha = 0;
    
    // Animate in
    [UIView animateWithDuration:0.3 animations:^{
        self.coordinatesContainer.alpha = 1.0;
    }];
}

// Copy coordinates to clipboard
- (void)copyCoordinates {
    if (self.coordinatesLabel.text) {
        // Extract just the numbers from the formatted text (already in reduced format)
        NSString *coordsOnly = [self.coordinatesLabel.text stringByReplacingOccurrencesOfString:@"📍 " withString:@""];
        
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:coordsOnly];
        
        // Show feedback
        [self showToastWithMessage:@"Coordinates copied"];
        
        // Flash the container to indicate success
        [UIView animateWithDuration:0.2 animations:^{
            self.coordinatesContainer.backgroundColor = [UIColor systemGreenColor];
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.2 animations:^{
                self.coordinatesContainer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
            }];
        }];
    }
}

// Modern toast message display (positioned at the top of the screen)
- (void)showToastWithMessage:(NSString *)message {
    // Create container view
    UIView *toastContainer = [[UIView alloc] init];
    toastContainer.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.85];
    toastContainer.layer.cornerRadius = 12;
    toastContainer.clipsToBounds = YES;
    toastContainer.translatesAutoresizingMaskIntoConstraints = NO;
    toastContainer.alpha = 0.0;
    
    // Add blur effect for modern look
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    blurView.alpha = 0.5;
    [toastContainer addSubview:blurView];
    
    // Add icon based on message
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tintColor = [UIColor whiteColor];
    
    UIImage *icon = nil;
    if ([message isEqualToString:@"Location marked"]) {
        icon = [UIImage systemImageNamed:@"mappin.circle.fill"];
        toastContainer.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:0.85]; // Green tint
    } else if ([message isEqualToString:@"Location unmarked"]) {
        icon = [UIImage systemImageNamed:@"mappin.slash.circle.fill"];
        toastContainer.backgroundColor = [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:0.85]; // Red tint
    } else if ([message isEqualToString:@"Coordinates copied"]) {
        icon = [UIImage systemImageNamed:@"doc.on.clipboard.fill"];
        toastContainer.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.7 alpha:0.85]; // Blue tint
    } else if ([message isEqualToString:@"Location loaded"]) {
        icon = [UIImage systemImageNamed:@"arrow.triangle.turn.up.right.circle.fill"];
        toastContainer.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.7 alpha:0.85]; // Purple tint
    } else {
        icon = [UIImage systemImageNamed:@"info.circle.fill"];
    }
    
    iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [toastContainer addSubview:iconView];
    
    // Create label
    UILabel *toastLabel = [[UILabel alloc] init];
    toastLabel.text = message;
    toastLabel.textColor = [UIColor whiteColor];
    toastLabel.textAlignment = NSTextAlignmentLeft;
    toastLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    toastLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [toastContainer addSubview:toastLabel];
    
    // Add to view
    [self.view addSubview:toastContainer];
    
    // Setup constraints for blur view
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:toastContainer.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:toastContainer.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:toastContainer.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:toastContainer.bottomAnchor]
    ]];
    
    // Setup constraints for icon
    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:toastContainer.leadingAnchor constant:15],
        [iconView.centerYAnchor constraintEqualToAnchor:toastContainer.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:24],
        [iconView.heightAnchor constraintEqualToConstant:24]
    ]];
    
    // Setup constraints for label
    [NSLayoutConstraint activateConstraints:@[
        [toastLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10],
        [toastLabel.trailingAnchor constraintEqualToAnchor:toastContainer.trailingAnchor constant:-15],
        [toastLabel.centerYAnchor constraintEqualToAnchor:toastContainer.centerYAnchor]
    ]];
    
    // Setup constraints for container - position at the TOP of the screen
    [NSLayoutConstraint activateConstraints:@[
        [toastContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toastContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [toastContainer.heightAnchor constraintGreaterThanOrEqualToConstant:48],
        [toastContainer.widthAnchor constraintLessThanOrEqualToConstant:300],
        [toastContainer.widthAnchor constraintGreaterThanOrEqualToConstant:180]
    ]];
    
    // Add shadow to container
    toastContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    toastContainer.layer.shadowOffset = CGSizeMake(0, 4);
    toastContainer.layer.shadowOpacity = 0.3;
    toastContainer.layer.shadowRadius = 5;
    
    // Show the toast with spring animation for modern feel - animate DOWN from top
    [UIView animateWithDuration:0.5 
                          delay:0 
         usingSpringWithDamping:0.7 
          initialSpringVelocity:0.5 
                        options:UIViewAnimationOptionCurveEaseOut 
                     animations:^{
        toastContainer.alpha = 1.0;
        toastContainer.transform = CGAffineTransformMakeTranslation(0, 10);
    } completion:^(BOOL finished) {
        // Hide the toast after a delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastContainer.alpha = 0.0;
                toastContainer.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) {
                [toastContainer removeFromSuperview];
            }];
        });
    }];
}

// Handle tap on map for pin placement
- (void)handleMapTap:(UITapGestureRecognizer *)recognizer {
    // No special handling for GPS spoofing bar - allow pin placement regardless
    
    // Get tap coordinates in the WebView's coordinate system
    CGPoint tapPointInWebView = [recognizer locationInView:self.mapWebView];
    
    // Use JavaScript to convert the tap point to map coordinates
    NSString *script = [NSString stringWithFormat:@"(function() { \
        var point = new google.maps.Point(%f, %f); \
        var containerPoint = point; \
        var topLeft = new google.maps.Point(0, 0); \
        var worldPoint = new google.maps.Point( \
            containerPoint.x / Math.pow(2, map.getZoom()), \
            containerPoint.y / Math.pow(2, map.getZoom()) \
        ); \
        var latLng = map.getProjection().fromPointToLatLng(worldPoint); \
        if (latLng) { \
            placeCustomPin(latLng, false); \
            return { success: true, lat: latLng.lat(), lng: latLng.lng() }; \
        } else { \
            return { success: false }; \
        } \
    })();", tapPointInWebView.x, tapPointInWebView.y];
    
    // Fallback coordinates in case JavaScript fails
    __block double latitude = 37.7749; // Example coordinate for San Francisco
    __block double longitude = -122.4194;
    
    [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (!error && [result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *resultDict = (NSDictionary *)result;
            
            if ([resultDict[@"success"] boolValue]) {
                // Get coordinates from JavaScript
                latitude = [resultDict[@"lat"] doubleValue];
                longitude = [resultDict[@"lng"] doubleValue];
                
                PXLog(@"[WeaponX] Map tapped at coordinates: %.6f, %.6f", latitude, longitude);
                
                // Store as current pin location
                self.currentPinLocation = @{
                    @"latitude": @(latitude),
                    @"longitude": @(longitude),
                    @"isPinned": @NO
                };
                
                // Update UI on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Show coordinates
                    [self showCoordinates:latitude longitude:longitude];
                    
                    // Toggle buttons - hide pin button and show unpin button
                    self.unpinButton.hidden = NO;
                    self.pinButton.hidden = YES;
                });
            } else {
                PXLog(@"[WeaponX] Failed to get coordinates from tap location");
                
                // Fallback to default coordinates
                [self handleFallbackCoordinates:latitude longitude:longitude];
            }
        } else {
            PXLog(@"[WeaponX] JavaScript error for map tap: %@", error);
            
            // Fallback to default coordinates
            [self handleFallbackCoordinates:latitude longitude:longitude];
        }
    }];
}

// Helper method to handle fallback coordinates
- (void)handleFallbackCoordinates:(double)latitude longitude:(double)longitude {
    // Use fallback coordinates
    self.currentPinLocation = @{
        @"latitude": @(latitude),
        @"longitude": @(longitude),
        @"isPinned": @NO
    };
    
    // Update UI
    dispatch_async(dispatch_get_main_queue(), ^{
        // Show coordinates
        [self showCoordinates:latitude longitude:longitude];
        
        // Toggle buttons - hide pin button and show unpin button
        self.unpinButton.hidden = NO;
        self.pinButton.hidden = YES;
    });
}

// Show a toast message to the user
// Show save location button when a pin is placed
- (void)showSaveLocationButton {
    // Create save button if it doesn't exist
    if (!self.saveLocationButton) {
        self.saveLocationButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.saveLocationButton setTitle:@"Save Location" forState:UIControlStateNormal];
        
        // Style the button
        self.saveLocationButton.backgroundColor = [UIColor systemBlueColor];
        self.saveLocationButton.tintColor = [UIColor whiteColor];
        self.saveLocationButton.layer.cornerRadius = 8;
        self.saveLocationButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        
        // Add shadow
        self.saveLocationButton.layer.shadowColor = [UIColor blackColor].CGColor;
        self.saveLocationButton.layer.shadowOffset = CGSizeMake(0, 2);
        self.saveLocationButton.layer.shadowOpacity = 0.3;
        self.saveLocationButton.layer.shadowRadius = 3;
        
        [self.saveLocationButton addTarget:self action:@selector(saveLocationButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        self.saveLocationButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.mapWebView addSubview:self.saveLocationButton];
        
        // Position at bottom of screen
        [NSLayoutConstraint activateConstraints:@[
            [self.saveLocationButton.centerXAnchor constraintEqualToAnchor:self.mapWebView.centerXAnchor],
            [self.saveLocationButton.bottomAnchor constraintEqualToAnchor:self.mapWebView.bottomAnchor constant:-120],
            [self.saveLocationButton.widthAnchor constraintEqualToConstant:140],
            [self.saveLocationButton.heightAnchor constraintEqualToConstant:40]
        ]];
    }
    
    // Make it visible with animation
    self.saveLocationButton.alpha = 0;
    self.saveLocationButton.hidden = NO;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.saveLocationButton.alpha = 1.0;
    }];
}

// Hide save location button with animation
- (void)hideSaveLocationButton {
    if (self.saveLocationButton) {
        [UIView animateWithDuration:0.3 animations:^{
            self.saveLocationButton.alpha = 0;
        } completion:^(BOOL finished) {
            self.saveLocationButton.hidden = YES;
        }];
    }
}

// Handle saving a location
- (void)saveLocationButtonTapped {
    // Simplified implementation - UI only
    
    // Show dialog with dummy UI
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Location" 
                                                                  message:@"Enter a name for this location" 
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Home, Work, etc.";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.returnKeyType = UIReturnKeyDone;
    }];
    
    // Add save action
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *locationName = textField.text;
        
        if (locationName.length == 0) {
            locationName = @"Unnamed Location";
        }
        
        // Show feedback toast
        [self showToastWithMessage:[NSString stringWithFormat:@"UI only - Location '%@' saved", locationName]];
        
        // Hide the save button
        [self hideSaveLocationButton];
    }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Save a location to favorites
- (void)saveFavoriteLocation:(NSString *)name withCoordinates:(NSDictionary *)coordinates {
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    
    if (!settings) {
        settings = [NSMutableDictionary dictionary];
    }
    
    // Get existing favorites or create new array
    NSMutableArray *favorites = [NSMutableArray arrayWithArray:settings[@"FavoriteLocations"]];
    if (!favorites) {
        favorites = [NSMutableArray array];
    }
    
    // Create a location entry with name and coordinates
    NSDictionary *locationEntry = @{
        @"name": name,
        @"latitude": coordinates[@"latitude"],
        @"longitude": coordinates[@"longitude"],
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };
    
    // Add to favorites
    [favorites addObject:locationEntry];
    
    // Save back to settings
    [settings setObject:favorites forKey:@"FavoriteLocations"];
    [settings writeToFile:plistPath atomically:YES];
    
    // Show confirmation
    [self showToastWithMessage:[NSString stringWithFormat:@"Saved location: %@", name]];
    
    PXLog(@"[WeaponX] Saved favorite location: %@ at %.6f, %.6f", 
         name, 
         [coordinates[@"latitude"] doubleValue], 
         [coordinates[@"longitude"] doubleValue]);
}

// Setup favorites button
- (void)setupFavoritesButton {
    if (!self.favoritesButton) {
        // Create a container view for the button and label
        self.favoritesContainer = [[UIView alloc] init];
        self.favoritesContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.favoritesContainer];
        
        // Create the star button
        self.favoritesButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *starIcon = [UIImage systemImageNamed:@"star.fill"];
        
        // Configure the button with a smaller image
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
        UIImage *configuredImage = [starIcon imageByApplyingSymbolConfiguration:config];
        [self.favoritesButton setImage:configuredImage forState:UIControlStateNormal];
        
        // Style the button - make it circular
        self.favoritesButton.backgroundColor = [UIColor systemBlueColor];
        self.favoritesButton.tintColor = [UIColor whiteColor];
        self.favoritesButton.layer.cornerRadius = 20;
        
        // Add shadow
        self.favoritesButton.layer.shadowColor = [UIColor blackColor].CGColor;
        self.favoritesButton.layer.shadowOffset = CGSizeMake(0, 2);
        self.favoritesButton.layer.shadowOpacity = 0.3;
        self.favoritesButton.layer.shadowRadius = 3;
        
        [self.favoritesButton addTarget:self action:@selector(favoritesButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        self.favoritesButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.favoritesContainer addSubview:self.favoritesButton];
        
        // Create and add a label
        UILabel *favoritesLabel = [[UILabel alloc] init];
        favoritesLabel.text = @"Favorites";
        favoritesLabel.textColor = [UIColor labelColor];
        favoritesLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        favoritesLabel.textAlignment = NSTextAlignmentCenter;
        favoritesLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.favoritesContainer addSubview:favoritesLabel];
        
        // Position at the bottom right corner but above the tab bar
        [NSLayoutConstraint activateConstraints:@[
            [self.favoritesContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30], // Increased from -25 to -30
            [self.favoritesContainer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
            [self.favoritesContainer.widthAnchor constraintEqualToConstant:60],
            [self.favoritesContainer.heightAnchor constraintEqualToConstant:55]
        ]];
        
        // Button constraints
        [NSLayoutConstraint activateConstraints:@[
            [self.favoritesButton.topAnchor constraintEqualToAnchor:self.favoritesContainer.topAnchor],
            [self.favoritesButton.centerXAnchor constraintEqualToAnchor:self.favoritesContainer.centerXAnchor],
            [self.favoritesButton.widthAnchor constraintEqualToConstant:40],
            [self.favoritesButton.heightAnchor constraintEqualToConstant:40]
        ]];
        
        // Label constraints
        [NSLayoutConstraint activateConstraints:@[
            [favoritesLabel.topAnchor constraintEqualToAnchor:self.favoritesButton.bottomAnchor constant:1],
            [favoritesLabel.leadingAnchor constraintEqualToAnchor:self.favoritesContainer.leadingAnchor],
            [favoritesLabel.trailingAnchor constraintEqualToAnchor:self.favoritesContainer.trailingAnchor],
            [favoritesLabel.bottomAnchor constraintEqualToAnchor:self.favoritesContainer.bottomAnchor]
        ]];
    }
}

// Show favorites list when button is tapped
- (void)favoritesButtonTapped {
    // Load favorites from settings
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSArray *favorites = settings[@"FavoriteLocations"];
    NSArray *recentLocations = settings[@"RecentLocations"];
    
    // Check if we have any recents
    BOOL hasRecents = (recentLocations && recentLocations.count > 0);
    
    // Create action sheet with all options
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Locations" 
                                                                  message:(favorites.count > 0 || hasRecents) ? @"Select a location" : @"No saved locations yet"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add section for recent locations if available
    if (hasRecents) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Recent Pinned Locations" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showRecentLocations];
        }]];
    }
    
    // Add separator if we have both favorites and recents
    if (hasRecents && favorites && favorites.count > 0) {
        UIAlertAction *separator = [UIAlertAction actionWithTitle:@"────────────────" style:UIAlertActionStyleDefault handler:nil];
        separator.enabled = NO;
        [alert addAction:separator];
    }
    
    // Add actions for each favorite location if there are any
    if (favorites && favorites.count > 0) {
        // Add a section title
        UIAlertAction *favoritesHeader = [UIAlertAction actionWithTitle:@"Saved Favorites" style:UIAlertActionStyleDefault handler:nil];
        favoritesHeader.enabled = NO;
        [alert addAction:favoritesHeader];
        
        for (NSDictionary *location in favorites) {
            NSString *name = location[@"name"];
            // Add show/use/delete options
            [alert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                // Show options for this location
                [self showOptionsForLocation:location];
            }]];
        }
        
        // Add manage option
        [alert addAction:[UIAlertAction actionWithTitle:@"Manage Locations" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showManageFavoritesView];
        }]];
    }
    
    // Always add option to add current location regardless of whether there are saved locations
    [alert addAction:[UIAlertAction actionWithTitle:@"Add Current Location" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (!self.currentPinLocation) {
            [self showToastWithMessage:@"No location marked. Tap on map to mark a location first."];
            return;
        }
        
        // Show prompt to name the location
        [self promptForLocationName];
    }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad, set source for popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.favoritesContainer;
        alert.popoverPresentationController.sourceRect = self.favoritesContainer.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Show options for a selected favorite location
- (void)showOptionsForLocation:(NSDictionary *)location {
    NSString *name = location[@"name"];
    double latitude = [location[@"latitude"] doubleValue];
    double longitude = [location[@"longitude"] doubleValue];
    
    // Create action sheet with options for this location
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name
                                                                  message:[NSString stringWithFormat:@"%.5f, %.5f", latitude, longitude]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add option to view on map
    [alert addAction:[UIAlertAction actionWithTitle:@"View on Map" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self centerMapAndPlacePinAtLatitude:latitude longitude:longitude shouldTogglePinButton:NO];
    }]];
    
    // Add option to delete
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteFavoriteLocation:location];
    }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad, set source for popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.favoritesButton;
        alert.popoverPresentationController.sourceRect = self.favoritesButton.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Show manage favorites view
- (void)showManageFavoritesView {
    // Load favorites from settings
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSArray *favorites = settings[@"FavoriteLocations"];
    
    if (!favorites || favorites.count == 0) {
        [self showToastWithMessage:@"No saved locations to manage"];
        return;
    }
    
    // Create action sheet for management options
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Manage Locations" 
                                                                  message:[NSString stringWithFormat:@"%lu location(s) saved", (unsigned long)favorites.count]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add option to delete all locations
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete All Locations" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self confirmDeleteAllLocations];
    }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad, set source for popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.favoritesButton;
        alert.popoverPresentationController.sourceRect = self.favoritesButton.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Confirm deletion of all locations
- (void)confirmDeleteAllLocations {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete All Locations" 
                                                                  message:@"Are you sure you want to delete all saved locations? This cannot be undone."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    // Add confirm action
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteAllLocations];
    }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Delete all saved locations
- (void)deleteAllLocations {
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    
    if (!settings) {
        settings = [NSMutableDictionary dictionary];
    }
    
    // Remove or replace with empty array
    [settings setObject:@[] forKey:@"FavoriteLocations"];
    [settings writeToFile:plistPath atomically:YES];
    
    // Show confirmation
    [self showToastWithMessage:@"All locations deleted"];
    
    PXLog(@"[WeaponX] Deleted all saved locations");
}

// Save current location to favorites - simplified stub
- (void)saveCurrentLocationToFavorites {
    // UI only implementation
    [self showToastWithMessage:@"UI only - Save favorites functionality disabled"];
}

// Setup pin/unpin buttons
- (void)setupUnpinButton {
    if (!self.unpinButton) {
        // Create a container view for the buttons
        self.unpinContainer = [[UIView alloc] init];
        self.unpinContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.unpinContainer];
        
        // Create the unpin button
        self.unpinButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *unpinIcon = [UIImage systemImageNamed:@"mappin.slash.circle.fill"];
        
        // Configure the button with a suitable image size
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
        UIImage *configuredUnpinImage = [unpinIcon imageByApplyingSymbolConfiguration:config];
        
        // Set image only (no text on button)
        [self.unpinButton setImage:configuredUnpinImage forState:UIControlStateNormal];
        
        // Style the button - make it circular
        self.unpinButton.backgroundColor = [UIColor systemRedColor];
        self.unpinButton.tintColor = [UIColor whiteColor];
        self.unpinButton.layer.cornerRadius = 20;
        
        // Add shadow
        self.unpinButton.layer.shadowColor = [UIColor blackColor].CGColor;
        self.unpinButton.layer.shadowOffset = CGSizeMake(0, 2);
        self.unpinButton.layer.shadowOpacity = 0.3;
        self.unpinButton.layer.shadowRadius = 3;
        
        [self.unpinButton addTarget:self action:@selector(unpinButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        self.unpinButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.unpinContainer addSubview:self.unpinButton];
        
        // Create the pin button
        self.pinButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *pinIcon = [UIImage systemImageNamed:@"mappin.circle.fill"];
        
        // Configure the button with a suitable image size
        UIImage *configuredPinImage = [pinIcon imageByApplyingSymbolConfiguration:config];
        
        // Set image only (no text on button)
        [self.pinButton setImage:configuredPinImage forState:UIControlStateNormal];
        
        // Style the button - make it circular
        self.pinButton.backgroundColor = [UIColor systemGreenColor];
        self.pinButton.tintColor = [UIColor whiteColor];
        self.pinButton.layer.cornerRadius = 20;
        
        // Add shadow
        self.pinButton.layer.shadowColor = [UIColor blackColor].CGColor;
        self.pinButton.layer.shadowOffset = CGSizeMake(0, 2);
        self.pinButton.layer.shadowOpacity = 0.3;
        self.pinButton.layer.shadowRadius = 3;
        
        [self.pinButton addTarget:self action:@selector(pinButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        self.pinButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.unpinContainer addSubview:self.pinButton];
        
        // Create and add labels for each button
        UILabel *unpinLabel = [[UILabel alloc] init];
        unpinLabel.text = @"Unpin";
        unpinLabel.textColor = [UIColor labelColor];
        unpinLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        unpinLabel.textAlignment = NSTextAlignmentCenter;
        unpinLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.unpinContainer addSubview:unpinLabel];
        
        UILabel *pinLabel = [[UILabel alloc] init];
        pinLabel.text = @"Pin";
        pinLabel.textColor = [UIColor labelColor];
        pinLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        pinLabel.textAlignment = NSTextAlignmentCenter;
        pinLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.unpinContainer addSubview:pinLabel];
        
        // Position at the bottom left of favorites button
        [NSLayoutConstraint activateConstraints:@[
            [self.unpinContainer.trailingAnchor constraintEqualToAnchor:self.favoritesContainer.leadingAnchor constant:-30], // Increased from -25 to -30 for even spacing
            [self.unpinContainer.bottomAnchor constraintEqualToAnchor:self.favoritesContainer.bottomAnchor],
            [self.unpinContainer.widthAnchor constraintEqualToConstant:60],
            [self.unpinContainer.heightAnchor constraintEqualToConstant:55]
        ]];
        
        // Button constraints - both positioned in the same place
        [NSLayoutConstraint activateConstraints:@[
            [self.unpinButton.topAnchor constraintEqualToAnchor:self.unpinContainer.topAnchor],
            [self.unpinButton.centerXAnchor constraintEqualToAnchor:self.unpinContainer.centerXAnchor],
            [self.unpinButton.widthAnchor constraintEqualToConstant:40],
            [self.unpinButton.heightAnchor constraintEqualToConstant:40],
            
            [self.pinButton.topAnchor constraintEqualToAnchor:self.unpinContainer.topAnchor],
            [self.pinButton.centerXAnchor constraintEqualToAnchor:self.unpinContainer.centerXAnchor],
            [self.pinButton.widthAnchor constraintEqualToConstant:40],
            [self.pinButton.heightAnchor constraintEqualToConstant:40]
        ]];
        
        // Label constraints - positioned below their respective buttons
        [NSLayoutConstraint activateConstraints:@[
            [unpinLabel.topAnchor constraintEqualToAnchor:self.unpinButton.bottomAnchor constant:1],
            [unpinLabel.centerXAnchor constraintEqualToAnchor:self.unpinButton.centerXAnchor],
            [unpinLabel.widthAnchor constraintEqualToConstant:40],
            
            [pinLabel.topAnchor constraintEqualToAnchor:self.pinButton.bottomAnchor constant:1],
            [pinLabel.centerXAnchor constraintEqualToAnchor:self.pinButton.centerXAnchor],
            [pinLabel.widthAnchor constraintEqualToConstant:40]
        ]];
        
        // Initially show the pin button and hide the unpin button
        self.unpinButton.hidden = YES;
        unpinLabel.hidden = YES;
        self.pinButton.hidden = NO;
        pinLabel.hidden = NO;
    }
}

// New method for pin button tap
- (void)pinButtonTapped {
    // Store label references
    UILabel *pinLabel = nil;
    UILabel *unpinLabel = nil;
    
    // Find the labels in the container
    for (UIView *subview in self.unpinContainer.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"Pin"]) {
                pinLabel = label;
            } else if ([label.text isEqualToString:@"Unpin"]) {
                unpinLabel = label;
            }
        }
    }
    
    // Save the current location data to NSUserDefaults
    [self savePinnedLocationToUserDefaults];
    
    // Get the coordinates from currentPinLocation
    if (self.currentPinLocation) {
        double latitude = [self.currentPinLocation[@"latitude"] doubleValue];
        double longitude = [self.currentPinLocation[@"longitude"] doubleValue];
        
        // Update the currentPinLocation isPinned status
        NSMutableDictionary *updatedPinLocation = [NSMutableDictionary dictionaryWithDictionary:self.currentPinLocation];
        updatedPinLocation[@"isPinned"] = @YES;
        self.currentPinLocation = updatedPinLocation;
        
        // Update the pin to a green pin (isPinned=true)
        NSString *script = [NSString stringWithFormat:@"placeCustomPin(new google.maps.LatLng(%f, %f), true);", 
                          latitude, longitude];
        
        [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (error) {
                PXLog(@"[WeaponX] Error updating pin color: %@", error);
            } else {
                PXLog(@"[WeaponX] Successfully updated pin to green");
            }
        }];
    }
    
    // UI-only implementation
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pinButton.hidden = YES;
        if (pinLabel) pinLabel.hidden = YES;
        
        self.unpinButton.hidden = NO;
        if (unpinLabel) unpinLabel.hidden = NO;
        
        // Show confirmation
        [self showToastWithMessage:@"Location marked"];
        
        // Terminate all enabled scoped apps after pinning location
        [self terminateEnabledScopedApps];
    });
    
    // Refresh header view after pinning
    [LocationHeaderView createHeaderViewWithTitle:@"Map" 
                                navigationItem:self.navigationItem 
                                 updateHandler:^{
        // Add any map-specific update handling if needed
    }];
}

- (void)savePinnedLocationToUserDefaults {
    // Get the current pin location
    if (!self.currentPinLocation) {
        PXLog(@"[WeaponX] No current pin location to save");
        return;
    }
    
    // Create a dictionary with pin data
    NSDictionary *pinData = @{
        @"latitude": self.currentPinLocation[@"latitude"],
        @"longitude": self.currentPinLocation[@"longitude"],
        @"isPinned": @YES,
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };
    
    // Get the plist path
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    
    // Load existing settings
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!settings) {
        settings = [NSMutableDictionary dictionary];
    }
    
    // Save pinned location
    [settings setObject:pinData forKey:@"PinnedLocation"];
    
    // Update recent locations
    NSMutableArray *recentLocations = [NSMutableArray array];
    if (settings[@"RecentLocations"]) {
        recentLocations = [NSMutableArray arrayWithArray:settings[@"RecentLocations"]];
    }
    
    // Check if this location is already in recents to avoid duplicates
    BOOL isDuplicate = NO;
    double newLat = [self.currentPinLocation[@"latitude"] doubleValue];
    double newLng = [self.currentPinLocation[@"longitude"] doubleValue];
    
    for (NSDictionary *location in recentLocations) {
        double existingLat = [location[@"latitude"] doubleValue];
        double existingLng = [location[@"longitude"] doubleValue];
        
        // If coordinates are very close (within ~10 meters), consider it a duplicate
        if (fabs(existingLat - newLat) < 0.0001 && fabs(existingLng - newLng) < 0.0001) {
            isDuplicate = YES;
            break;
        }
    }
    
    // If not a duplicate, add to recents
    if (!isDuplicate) {
        // Add current location to the beginning of the array
        [recentLocations insertObject:pinData atIndex:0];
        
        // Limit to last 2 locations
        if (recentLocations.count > 2) {
            [recentLocations removeLastObject];
        }
        
        // Save updated recent locations
        [settings setObject:recentLocations forKey:@"RecentLocations"];
    }
    
    // Write to file
    [settings writeToFile:plistPath atomically:YES];
    
    PXLog(@"[WeaponX] Saved pinned location at %.6f, %.6f", 
         [pinData[@"latitude"] doubleValue], 
         [pinData[@"longitude"] doubleValue]);
    
    // Also save to the iplocationtime.plist for easy access across the app
    CLLocationCoordinate2D coords;
    coords.latitude = newLat;
    coords.longitude = newLng;
    
    // Get the country code and flag for this location
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    CLLocation *location = [[CLLocation alloc] initWithLatitude:coords.latitude longitude:coords.longitude];
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> * _Nullable placemarks, NSError * _Nullable error) {
        if (error || placemarks.count == 0) {
            // Save without country info
            [IPStatusCacheManager savePinnedLocation:coords 
                                         countryCode:@"" 
                                          flagEmoji:@"" 
                                          timestamp:[NSDate date]];
            return;
        }
        
        CLPlacemark *placemark = placemarks.firstObject;
        NSString *countryCode = placemark.ISOcountryCode;
        if (!countryCode) {
            // Save without country info
            [IPStatusCacheManager savePinnedLocation:coords 
                                         countryCode:@"" 
                                          flagEmoji:@"" 
                                          timestamp:[NSDate date]];
            return;
        }
        
        // Get flag emoji for country code
        NSString *flagEmoji = [self flagEmojiForCountryCode:countryCode];
        
        // Save with country info
        [IPStatusCacheManager savePinnedLocation:coords 
                                     countryCode:countryCode 
                                      flagEmoji:flagEmoji 
                                      timestamp:[NSDate date]];
        
        PXLog(@"[WeaponX] Saved pinned location to iplocationtime.plist with country: %@", countryCode);
    }];
    
    // No longer updating the UI directly since we're not showing recent locations on screen
}

// Add a method to update the favorites UI with recent locations

// Handle tap on recent location
- (void)recentLocationTapped:(UITapGestureRecognizer *)gesture {
    UIView *tappedView = gesture.view;
    NSString *coordString = tappedView.accessibilityHint;
    [self centerAndShowLocation:coordString];
}

// Handle go button tap
- (void)goToRecentLocation:(UIButton *)sender {
    NSString *coordString = sender.accessibilityHint;
    [self centerAndShowLocation:coordString];
}

// Center and show location helper
- (void)centerAndShowLocation:(NSString *)coordString {
    if (!coordString) return;
    
    NSArray *components = [coordString componentsSeparatedByString:@","];
    if (components.count != 2) return;
    
    double latitude = [components[0] doubleValue];
    double longitude = [components[1] doubleValue];
    
    // Center map and place pin
    [self centerMapAndPlacePinAtLatitude:latitude longitude:longitude shouldTogglePinButton:YES];
    
    // Show toast
    [self showToastWithMessage:@"Location loaded"];
    
    // Update current pin location
    self.currentPinLocation = @{
        @"latitude": @(latitude),
        @"longitude": @(longitude),
        @"isPinned": @NO
    };
    
    // Show coordinates
    [self showCoordinates:latitude longitude:longitude];
}

// Get recent locations
- (NSArray *)getRecentLocations {
    // Get the plist path
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    
    // Load existing settings
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!settings) {
        return @[];
    }
    
    // Get recent locations
    NSArray *recentLocations = settings[@"RecentLocations"];
    if (!recentLocations || ![recentLocations isKindOfClass:[NSArray class]]) {
        return @[];
    }
    
    return recentLocations;
}

// Remove pinned location from NSUserDefaults
- (void)removePinnedLocationFromUserDefaults {
    // Get the plist path
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    
    // Load existing settings
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!settings) {
        return; // Nothing to remove
    }
    
    // Remove pinned location
    [settings removeObjectForKey:@"PinnedLocation"];
    
    // Write to file
    [settings writeToFile:plistPath atomically:YES];
    
    PXLog(@"[WeaponX] Removed pinned location from settings");
}

// Check for saved pinned location
- (void)checkForSavedPinnedLocation {
    // Get the plist path
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    
    PXLog(@"[WeaponX] Checking for saved pinned location at path: %@", plistPath);
    
    // Load existing settings
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!settings) {
        PXLog(@"[WeaponX] No settings file found at path");
        return; // No settings file
    }
    
    // Dump entire settings content for debugging
    PXLog(@"[WeaponX] Settings content: %@", settings);
    
    // Get pinned location
    NSDictionary *pinnedLocation = settings[@"PinnedLocation"];
    if (!pinnedLocation) {
        PXLog(@"[WeaponX] No saved pinned location found in settings");
        return;
    }
    
    // Extract coordinates
    double latitude = [pinnedLocation[@"latitude"] doubleValue];
    double longitude = [pinnedLocation[@"longitude"] doubleValue];
    
    PXLog(@"[WeaponX] Found saved pinned location at %.6f, %.6f", latitude, longitude);
    
    // Check if the map is ready
    [self.mapWebView evaluateJavaScript:@"if (typeof map !== 'undefined' && map != null) { true; } else { false; }"
              completionHandler:^(id result, NSError *error) {
        if (error || ![result boolValue]) {
            PXLog(@"[WeaponX] Map not ready, scheduling retry for pinned location");
            // If map not ready, try again after a short delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self checkForSavedPinnedLocation];
            });
            return;
        }
        
        // Map is ready, restore the pinned location
        PXLog(@"[WeaponX] Map is ready, restoring pinned location");
        [self centerMapAndPlacePinnedPin:latitude longitude:longitude];
        
        // Store as current pin location
        self.currentPinLocation = @{
            @"latitude": pinnedLocation[@"latitude"],
            @"longitude": pinnedLocation[@"longitude"],
            @"isPinned": @YES
        };
        
        // Update UI - show unpin button and update label text
        dispatch_async(dispatch_get_main_queue(), ^{
            // Store label references
            UILabel *pinLabel = nil;
            UILabel *unpinLabel = nil;
            
            // Find the labels in the container
            for (UIView *subview in self.unpinContainer.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)subview;
                    if ([label.text isEqualToString:@"Pin"]) {
                        pinLabel = label;
                    } else if ([label.text isEqualToString:@"Unpin"]) {
                        unpinLabel = label;
                    }
                }
            }
            
            // Update button visibility and label visibility
            self.unpinButton.hidden = NO;
            self.pinButton.hidden = YES;
            
            // Update label visibility to match button visibility
            if (pinLabel) pinLabel.hidden = YES;
            if (unpinLabel) unpinLabel.hidden = NO;
            
            // Show coordinates
            [self showCoordinates:latitude longitude:longitude];
            
            PXLog(@"[WeaponX] Successfully restored pinned location UI state with proper labels");
        });
    }];
}

// New method to center map and place a pinned (green) pin
- (void)centerMapAndPlacePinnedPin:(double)latitude longitude:(double)longitude {
    // Create JavaScript to center map and place a pinned (green) pin
    NSString *script = [NSString stringWithFormat:@"(function() { \
        try { \
            if (typeof map === 'undefined' || map === null) { \
                return { success: false, error: 'Map not ready' }; \
            } \
            var latLng = new google.maps.LatLng(%f, %f); \
            map.setCenter(latLng); \
            map.setZoom(17); \
            placeCustomPin(latLng, true); \
            return { success: true, lat: %f, lng: %f }; \
        } catch(e) { \
            return { success: false, error: e.toString() }; \
        } \
    })();", latitude, longitude, latitude, longitude];
    
    [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[WeaponX] Error placing pinned pin: %@", error);
            // Retry after a short delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self centerMapAndPlacePinnedPin:latitude longitude:longitude];
            });
        } else if ([result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *resultDict = (NSDictionary *)result;
            if ([resultDict[@"success"] boolValue]) {
                PXLog(@"[WeaponX] Successfully placed pinned (green) pin at %.6f, %.6f", latitude, longitude);
            } else {
                PXLog(@"[WeaponX] Failed to place green pin: %@", resultDict[@"error"]);
                // Retry after a short delay
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self centerMapAndPlacePinnedPin:latitude longitude:longitude];
                });
            }
        }
    }];
}

- (void)togglePinState {
    // Simplified implementation
    // Just toggle between pin button and unpin button
    BOOL isCurrentlyUnpinned = self.pinButton.hidden == NO;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isCurrentlyUnpinned) {
            // If currently showing pin button, switch to showing unpin button
            self.pinButton.hidden = YES;
            self.unpinButton.hidden = NO;
            [self showToastWithMessage:@"Location saved"];
        } else {
            // If currently showing unpin button, switch to showing pin button
            self.pinButton.hidden = NO;
            self.unpinButton.hidden = YES;
            [self showToastWithMessage:@"Location removed"];
        }
    });
}

// When a location is being pinned from search, use the isPinned parameter:
- (void)handleMapSearchResult:(NSDictionary *)result {
    if (result && result[@"lat"] && result[@"lng"]) {
        double latitude = [result[@"lat"] doubleValue];
        double longitude = [result[@"lng"] doubleValue];
        NSString *address = result[@"address"];
        
        // Place a pin at the search result location (same blue pointer as tap)
        NSString *script = [NSString stringWithFormat:@"placeCustomPin(new google.maps.LatLng(%f, %f), false);",
                          latitude, longitude];
        
        [self.mapWebView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            if (error) {
                PXLog(@"[WeaponX] Error placing pin at search result: %@", error);
                // Removed error toast message
            } else {
                // Update current pin location
                self.currentPinLocation = @{
                    @"latitude": @(latitude),
                    @"longitude": @(longitude),
                    @"isPinned": @NO,
                    @"address": address ?: @""
                };
                
                // Update UI on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Show coordinates
                    [self showCoordinates:latitude longitude:longitude];
                    
                    // Toggle buttons - hide pin button and show unpin button
                    self.unpinButton.hidden = NO;
                    self.pinButton.hidden = YES;
                    
                    // Show confirmation with address if available
                    NSString *toastMessage = address ? 
                        [NSString stringWithFormat:@"Found: %@", address] : 
                        @"Location found";
                    [self showToastWithMessage:toastMessage];
                });
            }
        }];
    } else {
        PXLog(@"[WeaponX] Invalid search result data");
    }
}

#pragma mark - UITableViewDataSource Methods

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Empty implementation to satisfy protocol requirements
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Empty implementation to satisfy protocol requirements
    static NSString *cellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    return cell;
}

#pragma mark - UIContextMenuInteractionDelegate Methods

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    // Empty implementation to satisfy protocol requirements
    return nil;
}

#pragma mark - Helper Methods

// Convert country code to flag emoji
- (NSString *)flagEmojiForCountryCode:(NSString *)countryCode {
    if (!countryCode || countryCode.length != 2) {
        return nil;
    }
    
    // Convert country code to uppercase
    countryCode = [countryCode uppercaseString];
    
    // Create array of country codes and corresponding emojis
    NSDictionary *flagEmojis = @{
        @"US": @"🇺🇸", @"GB": @"🇬🇧", @"CA": @"🇨🇦", @"AU": @"🇦🇺",
        @"IN": @"🇮🇳", @"JP": @"🇯🇵", @"DE": @"🇩🇪", @"FR": @"🇫🇷",
        @"IT": @"🇮🇹", @"ES": @"🇪🇸", @"BR": @"🇧🇷", @"RU": @"🇷🇺",
        @"CN": @"🇨🇳", @"KR": @"🇰🇷", @"ID": @"🇮🇩", @"MX": @"🇲🇽",
        @"NL": @"🇳🇱", @"TR": @"🇹🇷", @"SA": @"🇸🇦", @"CH": @"🇨🇭",
        @"SE": @"🇸🇪", @"PL": @"🇵🇱", @"BE": @"🇧🇪", @"IR": @"🇮🇷",
        @"NO": @"🇳🇴", @"AT": @"🇦🇹", @"IL": @"🇮🇱", @"DK": @"🇩🇰",
        @"SG": @"🇸🇬", @"FI": @"🇫🇮", @"NZ": @"🇳🇿", @"MY": @"🇲🇾",
        @"TH": @"🇹🇭", @"AE": @"🇦🇪", @"PH": @"🇵🇭", @"IE": @"🇮🇪",
        @"PT": @"🇵🇹", @"GR": @"🇬🇷", @"CZ": @"🇨🇿", @"VN": @"🇻🇳",
        @"RO": @"🇷🇴", @"ZA": @"🇿🇦", @"UA": @"🇺🇦", @"HK": @"🇭🇰",
        @"HU": @"🇭🇺", @"BG": @"🇧🇬", @"HR": @"🇭🇷", @"LT": @"🇱🇹",
        @"EE": @"🇪🇪", @"SK": @"🇸🇰"
    };
    
    NSString *flag = flagEmojis[countryCode];
    if (!flag) {
        // Fallback to dynamic generation for unsupported country codes
        flag = [[NSString alloc] initWithFormat:@"%C%C",
                (unichar)(0x1F1E6 + [countryCode characterAtIndex:0] - 'A'),
                (unichar)(0x1F1E6 + [countryCode characterAtIndex:1] - 'A')];
    }
    
    return flag;
}

// Prompt for location name when saving to favorites
- (void)promptForLocationName {
    // Show dialog asking for location name
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Location" 
                                                                  message:@"Enter a name for this location" 
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Home, Work, etc.";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.returnKeyType = UIReturnKeyDone;
    }];
    
    // Add save action
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *locationName = textField.text;
        
        if (locationName.length == 0) {
            locationName = @"Unnamed Location";
        }
        
        // Save the current location with this name
        [self saveFavoriteLocation:locationName withCoordinates:self.currentPinLocation];
    }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

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
            // Removed error toast message
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

// Original method - keeps backward compatibility by calling new method with toggle=YES
- (void)centerMapAndPlacePinAtLatitude:(double)latitude longitude:(double)longitude {
    [self centerMapAndPlacePinAtLatitude:latitude longitude:longitude shouldTogglePinButton:YES];
}

// Delete a favorite location
- (void)deleteFavoriteLocation:(NSDictionary *)locationToDelete {
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    
    if (!settings) {
        // Nothing to delete
        return;
    }
    
    // Get existing favorites
    NSMutableArray *favorites = [NSMutableArray arrayWithArray:settings[@"FavoriteLocations"]];
    
    if (!favorites || favorites.count == 0) {
        // No favorites to delete
        return;
    }
    
    // Find and remove the location by matching name and coordinates
    NSString *nameToDelete = locationToDelete[@"name"];
    double latToDelete = [locationToDelete[@"latitude"] doubleValue];
    double lngToDelete = [locationToDelete[@"longitude"] doubleValue];
    
    NSUInteger indexToRemove = NSNotFound;
    
    for (NSUInteger i = 0; i < favorites.count; i++) {
        NSDictionary *location = favorites[i];
        NSString *name = location[@"name"];
        double lat = [location[@"latitude"] doubleValue];
        double lng = [location[@"longitude"] doubleValue];
        
        // Match by name and coordinates
        if ([name isEqualToString:nameToDelete] && 
            fabs(lat - latToDelete) < 0.0000001 && 
            fabs(lng - lngToDelete) < 0.0000001) {
            indexToRemove = i;
            break;
        }
    }
    
    if (indexToRemove != NSNotFound) {
        [favorites removeObjectAtIndex:indexToRemove];
        
        // Save back to settings
        [settings setObject:favorites forKey:@"FavoriteLocations"];
        [settings writeToFile:plistPath atomically:YES];
        
        // Show confirmation
        [self showToastWithMessage:[NSString stringWithFormat:@"Deleted: %@", nameToDelete]];
        
        PXLog(@"[WeaponX] Deleted favorite location: %@", nameToDelete);
    }
}

// Helper method to show location settings alert
- (void)showLocationSettingsAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Location Access Required" 
                                                              message:@"Location access has been denied. Please enable it in Settings to use this feature."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openLocationSettings];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
    PXLog(@"[WeaponX] Showing location settings alert due to denied access");
}

// Helper method to open system location settings
- (void)openLocationSettings {
    NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
        [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:^(BOOL success) {
            PXLog(@"[WeaponX] Opening settings %@", success ? @"succeeded" : @"failed");
        }];
    } else {
        PXLog(@"[WeaponX] Unable to open settings URL");
    }
}

// New method to ensure pinned location is restored
- (void)ensurePinnedLocationRestored {
    PXLog(@"[WeaponX] Ensuring pinned location is restored...");
    
    // Check if the map is ready by running a test script
    [self.mapWebView evaluateJavaScript:@"if (typeof map !== 'undefined' && map != null) { true; } else { false; }"
              completionHandler:^(id result, NSError *error) {
        if (error || ![result boolValue]) {
            PXLog(@"[WeaponX] Map not ready yet, will retry in 1 second");
            // Map not ready, retry after a short delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self ensurePinnedLocationRestored];
            });
            return;
        }
        
        // Map is ready, now check for pinned location
        [self checkForSavedPinnedLocation];
    }];
}

// Update the togglePinState method to properly update label visibility
- (void)togglePinState:(BOOL)isPinned {
    // Store label references
    UILabel *pinLabel = nil;
    UILabel *unpinLabel = nil;
    
    // Find the labels in the container
    for (UIView *subview in self.unpinContainer.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"Pin"] || 
                [label.text isEqualToString:@"Location marked"]) {
                pinLabel = label;
            } else if ([label.text isEqualToString:@"Unpin"] || 
                       [label.text isEqualToString:@"Location unmarked"]) {
                unpinLabel = label;
            }
        }
    }
    
    if (isPinned) {
        // If pinned, show unpin button and hide pin button
        self.unpinButton.hidden = NO;
        self.pinButton.hidden = YES;
        
        // Update label visibility to match button visibility
        if (pinLabel) pinLabel.hidden = YES;
        if (unpinLabel) unpinLabel.hidden = NO;
        
        PXLog(@"[WeaponX] Location saved");
    } else {
        // If not pinned, show pin button and hide unpin button
        self.unpinButton.hidden = YES;
        self.pinButton.hidden = NO;
        
        // Update label visibility to match button visibility
        if (pinLabel) pinLabel.hidden = NO;
        if (unpinLabel) unpinLabel.hidden = YES;
        
        PXLog(@"[WeaponX] Location removed");
    }
}

// Add a method to show recent locations
- (void)showRecentLocations {
    // Get recent locations
    NSArray *recentLocations = [self getRecentLocations];
    if (recentLocations.count == 0) {
        [self showToastWithMessage:@"No recent locations found"];
        return;
    }
    
    // Create action sheet with all recent locations
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Recent Pinned Locations" 
                                                                  message:@"Select a location to view"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add each recent location
    for (NSDictionary *location in recentLocations) {
        double latitude = [location[@"latitude"] doubleValue];
        double longitude = [location[@"longitude"] doubleValue];
        NSString *timeString = @"";
        
        // If there's a timestamp, format it
        if (location[@"timestamp"]) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:[location[@"timestamp"] doubleValue]];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateStyle = NSDateFormatterShortStyle;
            formatter.timeStyle = NSDateFormatterShortStyle;
            timeString = [NSString stringWithFormat:@" (%@)", [formatter stringFromDate:date]];
        }
        
        NSString *title = [NSString stringWithFormat:@"%.5f, %.5f%@", latitude, longitude, timeString];
        
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            // Go to this location
            [self centerAndShowLocation:[NSString stringWithFormat:@"%.8f,%.8f", latitude, longitude]];
        }]];
    }
    
    // Add option to clear recent locations
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear Recent Locations" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self clearRecentLocations];
    }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad, set source for popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.favoritesButton;
        alert.popoverPresentationController.sourceRect = self.favoritesButton.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Add method to clear recent locations
- (void)clearRecentLocations {
    // Get the plist path
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    
    // Load existing settings
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
    if (!settings) {
        return;
    }
    
    // Remove recent locations
    [settings removeObjectForKey:@"RecentLocations"];
    
    // Write to file
    [settings writeToFile:plistPath atomically:YES];
    
    // Show toast
    [self showToastWithMessage:@"Recent locations cleared"];
    
    PXLog(@"[WeaponX] Cleared recent pinned locations");
}

// Add back viewDidAppear method but without showing recent locations panel
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // No longer showing recent locations panel here
    PXLog(@"[WeaponX] Map tab view appeared");
}
    // ... rest of existing viewWillAppear code ...

// Update setupButtons to add a GPS spoofing button
- (void)setupButtons {
    // ... existing code for setting up buttons ...
    
    // Add dedicated GPS spoofing button next to pin/unpin buttons
    UIButton *gpsSpoofingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *gpsSpoofingImage = [UIImage systemImageNamed:@"location.fill"];
    [gpsSpoofingButton setImage:gpsSpoofingImage forState:UIControlStateNormal];
    gpsSpoofingButton.tintColor = [UIColor systemBlueColor];
    [gpsSpoofingButton addTarget:self action:@selector(gpsSpoofingButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    gpsSpoofingButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:gpsSpoofingButton];
    
    // Create container view for the button
    UIView *gpsSpoofingContainer = [[UIView alloc] init];
    gpsSpoofingContainer.backgroundColor = [UIColor clearColor];
    gpsSpoofingContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:gpsSpoofingContainer];
    [gpsSpoofingContainer addSubview:gpsSpoofingButton];
    
    // Add label
    UILabel *gpsSpoofingLabel = [[UILabel alloc] init];
    gpsSpoofingLabel.text = @"Spoof";
    gpsSpoofingLabel.textColor = [UIColor systemBlueColor];
    gpsSpoofingLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    gpsSpoofingLabel.textAlignment = NSTextAlignmentCenter;
    gpsSpoofingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [gpsSpoofingContainer addSubview:gpsSpoofingLabel];
    
    // Position the GPS spoofing button to the left of the pin/unpin button
    [NSLayoutConstraint activateConstraints:@[
        [gpsSpoofingContainer.widthAnchor constraintEqualToConstant:60],
        [gpsSpoofingContainer.heightAnchor constraintEqualToConstant:55],
        [gpsSpoofingContainer.bottomAnchor constraintEqualToAnchor:self.unpinContainer.bottomAnchor],
        [gpsSpoofingContainer.rightAnchor constraintEqualToAnchor:self.unpinContainer.leftAnchor constant:-35], // Increased from -10 to -35 for more space
        
        [gpsSpoofingButton.centerXAnchor constraintEqualToAnchor:gpsSpoofingContainer.centerXAnchor],
        [gpsSpoofingButton.topAnchor constraintEqualToAnchor:gpsSpoofingContainer.topAnchor],
        [gpsSpoofingButton.widthAnchor constraintEqualToConstant:40],
        [gpsSpoofingButton.heightAnchor constraintEqualToConstant:40],
        
        [gpsSpoofingLabel.topAnchor constraintEqualToAnchor:gpsSpoofingButton.bottomAnchor constant:1],
        [gpsSpoofingLabel.leadingAnchor constraintEqualToAnchor:gpsSpoofingContainer.leadingAnchor],
        [gpsSpoofingLabel.trailingAnchor constraintEqualToAnchor:gpsSpoofingContainer.trailingAnchor],
        [gpsSpoofingLabel.bottomAnchor constraintEqualToAnchor:gpsSpoofingContainer.bottomAnchor]
    ]];
    
    // Store reference
    objc_setAssociatedObject(self, "gpsSpoofingButton", gpsSpoofingButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "gpsSpoofingContainer", gpsSpoofingContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // ... rest of existing setupButtons code ...
}

// OpenCage Geocoding API Key
static NSString *const kOpenCageAPIKey = @"a8db6f0729f34f41a9deebdb8305c54f";
static NSString *const kOpenCageBaseURL = @"https://api.opencagedata.com/geocode/v1/json";

#pragma mark - Manual Coordinate Entry

- (void)showManualCoordinateInput {
    // ... rest of existing code ...
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"Enter Coordinates"
        message:@"Enter latitude and longitude (e.g., 40.7128, -74.0060)" 
        preferredStyle:UIAlertControllerStyleAlert];
    
    // Add text fields for latitude and longitude
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Latitude";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Longitude";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    
    // Add paste button
    UIAlertAction *pasteAction = [UIAlertAction 
        actionWithTitle:@"Paste from Clipboard" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction * _Nonnull action) {
            [self pasteCoordinatesFromClipboard];
        }];
    
    // Add cancel button
    UIAlertAction *cancelAction = [UIAlertAction 
        actionWithTitle:@"Cancel" 
        style:UIAlertActionStyleCancel 
        handler:nil];
    
    // Add save button
    UIAlertAction *saveAction = [UIAlertAction 
        actionWithTitle:@"Save" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction * _Nonnull action) {
            [self processManualCoordinates:alert.textFields[0].text 
                                longitude:alert.textFields[1].text];
        }];
    
    // Add search location button
    UIAlertAction *searchAction = [UIAlertAction 
        actionWithTitle:@"Search Location" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction * _Nonnull action) {
            [self showLocationSearch];
        }];
    
    [alert addAction:pasteAction];
    [alert addAction:searchAction];
    [alert addAction:cancelAction];
    [alert addAction:saveAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Location Search

- (void)showLocationSearch {
    UIAlertController *searchAlert = [UIAlertController
        alertControllerWithTitle:@"Search Location"
        message:@"Enter an address, city, or place name"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [searchAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"e.g., Eiffel Tower, Paris";
        textField.returnKeyType = UIReturnKeySearch;
    }];
    
    UIAlertAction *searchAction = [UIAlertAction
        actionWithTitle:@"Search"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * _Nonnull action) {
            NSString *searchQuery = searchAlert.textFields.firstObject.text;
            if (searchQuery.length > 0) {
                [self searchLocationWithQuery:searchQuery];
            }
        }];
    
    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel
        handler:nil];
    
    [searchAlert addAction:cancelAction];
    [searchAlert addAction:searchAction];
    
    [self presentViewController:searchAlert animated:YES completion:nil];
}

- (void)searchLocationWithQuery:(NSString *)query {
    if (kOpenCageAPIKey.length == 0 || [kOpenCageAPIKey isEqualToString:@"YOUR_OPENCAGE_API_KEY"]) {
        [self showToastWithMessage:@"Please configure OpenCage API key first"];
        return;
    }
    
    // Show loading indicator
    UIActivityIndicatorView *spinner;
    if (@available(iOS 13.0, *)) {
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    } else {
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:2]; // UIActivityIndicatorViewStyleGray = 2
    }
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    
    // Create URL with query parameters
    NSURLComponents *components = [NSURLComponents componentsWithString:kOpenCageBaseURL];
    NSCharacterSet *allowedChars = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *encodedQuery = [query stringByAddingPercentEncodingWithAllowedCharacters:allowedChars];
    
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"q" value:encodedQuery],
        [NSURLQueryItem queryItemWithName:@"key" value:kOpenCageAPIKey],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"5"],
        [NSURLQueryItem queryItemWithName:@"no_annotations" value:@"1"],
        [NSURLQueryItem queryItemWithName:@"pretty" value:@"1"]
    ];
    
    NSURL *url = components.URL;
    
    // Create and start the data task
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
            
            if (error) {
                [self showToastWithMessage:[NSString stringWithFormat:@"Search error: %@", error.localizedDescription]];
                return;
            }
            
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                [self showToastWithMessage:@"Failed to parse search results"];
                return;
            }
            
            NSArray *results = json[@"results"];
            if (![results isKindOfClass:[NSArray class]] || results.count == 0) {
                [self showToastWithMessage:@"No results found"];
                return;
            }
            
            [self showSearchResults:results];
        });
    }];
    
    [task resume];
}

- (void)showSearchResults:(NSArray *)results {
    UIAlertController *resultsAlert = [UIAlertController
        alertControllerWithTitle:@"Select Location"
        message:@"Choose a location from the search results"
        preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Limit to first 5 results
    NSUInteger count = MIN(5, results.count);
    
    for (NSUInteger i = 0; i < count; i++) {
        NSDictionary *result = results[i];
        NSString *formatted = result[@"formatted"];
        NSDictionary *geometry = result[@"geometry"];
        
        if (![formatted isKindOfClass:[NSString class]] || !geometry) {
            continue;
        }
        
        NSNumber *lat = geometry[@"lat"];
        NSNumber *lng = geometry[@"lng"];
        
        if (![lat isKindOfClass:[NSNumber class]] || ![lng isKindOfClass:[NSNumber class]]) {
            continue;
        }
        
        // Truncate long location names
        NSString *title = formatted;
        if (title.length > 40) {
            title = [title substringToIndex:37];
            title = [title stringByAppendingString:@"..."];
        }
        
        UIAlertAction *locationAction = [UIAlertAction
            actionWithTitle:title
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * _Nonnull action) {
                [self processManualCoordinates:lat.stringValue longitude:lng.stringValue];
            }];
        
        [resultsAlert addAction:locationAction];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel
        handler:nil];
    
    [resultsAlert addAction:cancelAction];
    
    // Present from the topmost view controller to avoid warnings
    UIViewController *topController = nil;
    
    // Get the active window scene for iOS 13+
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                // Get the first window with a root view controller
                for (UIWindow *window in windowScene.windows) {
                    if (window.rootViewController) {
                        topController = window.rootViewController;
                        break;
                    }
                }
                if (topController) break;
            }
        }
    } 
    // Fallback for iOS 12 and below
    else {
        // Try to get the root view controller from the app delegate if available
        UIApplication *application = [UIApplication sharedApplication];
        if ([application.delegate respondsToSelector:@selector(window)]) {
            topController = application.delegate.window.rootViewController;
        }
        
        // Try to get the root view controller from the key window if still needed
        if (!topController) {
            // This is a last resort for iOS 12 and below
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            // On iOS 12 and below, we'll use the deprecated API as a last resort
            UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
            if (keyWindow) {
                topController = keyWindow.rootViewController;
            }
            #pragma clang diagnostic pop
        }
    }
    
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    // For iPad, set the popover presentation controller
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        resultsAlert.popoverPresentationController.sourceView = self.view;
        resultsAlert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0, 1.0, 1.0);
        resultsAlert.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [topController presentViewController:resultsAlert animated:YES completion:nil];
}

- (void)pasteCoordinatesFromClipboard {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *clipboardText = pasteboard.string;
    
    if (!clipboardText) {
        [self showToastWithMessage:@"Clipboard is empty"];
        return;
    }
    
    // Try to parse the clipboard text
    [self parseAndProcessCoordinates:clipboardText];
}

- (void)parseAndProcessCoordinates:(NSString *)coordinateString {
    // Clean and parse the coordinate string
    double latitude, longitude;
    if ([self parseCoordinateString:coordinateString intoLatitude:&latitude longitude:&longitude]) {
        [self showCoordinateConfirmationWithLatitude:[NSString stringWithFormat:@"%.6f", latitude] 
                                         longitude:[NSString stringWithFormat:@"%.6f", longitude]];
    } else {
        [self showToastWithMessage:@"Could not parse coordinates. Please enter as: lat, lng"];
    }
}

- (BOOL)parseCoordinateString:(NSString *)string intoLatitude:(double *)latitude longitude:(double *)longitude {
    if (!string || string.length == 0) {
        return NO;
    }
    
    // Try different parsing methods
    return [self parseDecimalDegrees:string lat:latitude lon:longitude] ||
           [self parseDMSFormat:string lat:latitude lon:longitude] ||
           [self parseCardinalFormat:string lat:latitude lon:longitude] ||
           [self parseSpaceSeparated:string lat:latitude lon:longitude];
}

// Parse standard decimal degrees format: 40.7128, -74.0060
- (BOOL)parseDecimalDegrees:(NSString *)string lat:(double *)lat lon:(double *)lon {
    NSArray *components = [string componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;|/	"]];
    if (components.count != 2) return NO;
    
    NSString *latString = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lonString = [components[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Check for direction indicators and handle them
    *lat = [self parseCoordinateValue:latString isLongitude:NO];
    *lon = [self parseCoordinateValue:lonString isLongitude:YES];
    
    return [self validateLatitude:*lat longitude:*lon];
}

// Parse DMS (Degrees, Minutes, Seconds) format: 40°42'51"N, 74°00'21"W
- (BOOL)parseDMSFormat:(NSString *)string lat:(double *)lat lon:(double *)lon {
    NSError *error = nil;
    // Match DMS format like: 40°42'51"N, 74°00'21"W
    // Using a simplified pattern to avoid special character issues
    NSString *pattern = @"([0-9]{1,3})[^0-9]+([0-9]{1,2})[^0-9]*([0-9]*(?:\\.[0-9]+)?)[^NSns]*([NSns]?)[^0-9]*([0-9]{1,3})[^0-9]+([0-9]{1,2})[^0-9]*([0-9]*(?:\\.[0-9]+)?)[^EWew]*([EWew]?)";
    NSRegularExpression *regex = [NSRegularExpression 
        regularExpressionWithPattern:pattern
        options:0
        error:&error];
    
    if (error) return NO;
    
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match || match.numberOfRanges < 8) return NO;
    
    // Parse latitude
    double latDeg = [self stringFromRange:[match rangeAtIndex:1] inString:string].doubleValue;
    double latMin = [self stringFromRange:[match rangeAtIndex:2] inString:string].doubleValue;
    double latSec = [self rangeExists:[match rangeAtIndex:3] inString:string] ? 
                   [self stringFromRange:[match rangeAtIndex:3] inString:string].doubleValue : 0;
    NSString *latDir = [self stringFromRange:[match rangeAtIndex:4] inString:string];
    
    // Parse longitude
    double lonDeg = [self stringFromRange:[match rangeAtIndex:5] inString:string].doubleValue;
    double lonMin = [self stringFromRange:[match rangeAtIndex:6] inString:string].doubleValue;
    double lonSec = [self rangeExists:[match rangeAtIndex:7] inString:string] ? 
                   [self stringFromRange:[match rangeAtIndex:7] inString:string].doubleValue : 0;
    NSString *lonDir = [self stringFromRange:[match rangeAtIndex:8] inString:string];
    
    // Convert DMS to decimal degrees
    *lat = [self dmsToDecimal:latDeg minutes:latMin seconds:latSec direction:latDir isLongitude:NO];
    *lon = [self dmsToDecimal:lonDeg minutes:lonMin seconds:lonSec direction:lonDir isLongitude:YES];
    
    return [self validateLatitude:*lat longitude:*lon];
}

// Parse cardinal direction format: 40.7128 N, 74.0060 W
- (BOOL)parseCardinalFormat:(NSString *)string lat:(double *)lat lon:(double *)lon {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression 
        regularExpressionWithPattern:@"([-+]?[0-9]*\\.?[0-9]+)[°]?\\s*([NS]?)[,;|/\\t]?\\s*([-+]?[0-9]*\\.?[0-9]+)[°]?\\s*([EW]?)"
        options:NSRegularExpressionCaseInsensitive
        error:&error];
    
    if (error) return NO;
    
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match || match.numberOfRanges < 5) return NO;
    
    // Parse latitude
    double latVal = [self stringFromRange:[match rangeAtIndex:1] inString:string].doubleValue;
    NSString *latDir = [self stringFromRange:[match rangeAtIndex:2] inString:string];
    
    // Parse longitude
    double lonVal = [self stringFromRange:[match rangeAtIndex:3] inString:string].doubleValue;
    NSString *lonDir = [self stringFromRange:[match rangeAtIndex:4] inString:string];
    
    // Apply direction
    *lat = [self applyDirection:latDir toValue:latVal isLongitude:NO];
    *lon = [self applyDirection:lonDir toValue:lonVal isLongitude:YES];
    
    return [self validateLatitude:*lat longitude:*lon];
}

// Parse space-separated format: 40.7128 -74.0060
- (BOOL)parseSpaceSeparated:(NSString *)string lat:(double *)lat lon:(double *)lon {
    NSArray *components = [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *cleanComponents = [NSMutableArray array];
    
    // Remove empty strings
    for (NSString *comp in components) {
        if (comp.length > 0) {
            [cleanComponents addObject:comp];
        }
    }
    
    if (cleanComponents.count < 2) return NO;
    
    // Try to parse first two valid numbers as lat,lon
    double latVal = 0, lonVal = 0;
    int found = 0;
    
    for (NSString *comp in cleanComponents) {
        if (found >= 2) break;
        
        // Try to extract a number from the component
        NSScanner *scanner = [NSScanner scannerWithString:comp];
        double value;
        if ([scanner scanDouble:&value]) {
            if (found == 0) {
                latVal = value;
                found++;
            } else {
                lonVal = value;
                found++;
            }
        }
    }
    
    if (found != 2) return NO;
    
    *lat = latVal;
    *lon = lonVal;
    
    return [self validateLatitude:*lat longitude:*lon];
}

// Helper: Convert DMS to decimal degrees
- (double)dmsToDecimal:(double)degrees minutes:(double)minutes seconds:(double)seconds direction:(NSString *)direction isLongitude:(BOOL)isLongitude {
    double decimal = degrees + minutes/60.0 + seconds/3600.0;
    
    // Apply direction (N/S or E/W)
    if ([direction.uppercaseString isEqualToString:@"S"] || 
        [direction.uppercaseString isEqualToString:@"W"]) {
        decimal = -decimal;
    } else if (isLongitude && [direction.uppercaseString isEqualToString:@"E"]) {
        // East is positive
    } else if (!isLongitude && [direction.uppercaseString isEqualToString:@"N"]) {
        // North is positive
    } else if (isLongitude && decimal > 0) {
        // If no direction but longitude is positive, assume East
    } else if (!isLongitude && decimal < 0) {
        // If no direction but latitude is negative, assume South
    }
    
    return decimal;
}

// Helper: Apply direction to coordinate value
- (double)applyDirection:(NSString *)direction toValue:(double)value isLongitude:(BOOL)isLongitude {
    if ([direction.uppercaseString isEqualToString:@"S"] || 
        [direction.uppercaseString isEqualToString:@"W"]) {
        return -fabs(value);
    } else if ([direction.uppercaseString isEqualToString:@"N"] || 
               [direction.uppercaseString isEqualToString:@"E"]) {
        return fabs(value);
    } else if (isLongitude && value < 0) {
        return value; // Already negative
    } else if (!isLongitude && value > 0) {
        return value; // Already positive
    }
    return value;
}

// Helper: Validate coordinate ranges
- (BOOL)validateLatitude:(double)lat longitude:(double)lon {
    return (lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0);
}

// Helper: Get string from range, handling invalid ranges
- (NSString *)stringFromRange:(NSRange)range inString:(NSString *)string {
    if (range.location == NSNotFound || range.location + range.length > string.length) {
        return @"";
    }
    return [string substringWithRange:range];
}

// Helper: Check if range is valid
- (BOOL)rangeExists:(NSRange)range inString:(NSString *)string {
    return range.location != NSNotFound && range.location + range.length <= string.length;
}

// Helper: Parse coordinate value with direction
- (double)parseCoordinateValue:(NSString *)string isLongitude:(BOOL)isLongitude {
    if (!string || string.length == 0) return 0.0;
    
    // Extract the numeric part
    NSScanner *scanner = [NSScanner scannerWithString:string];
    double value;
    if (![scanner scanDouble:&value]) return 0.0;
    
    // Check for direction indicators
    NSString *direction = [[string substringFromIndex:scanner.scanLocation] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    if (direction.length > 0) {
        unichar dirChar = [direction.uppercaseString characterAtIndex:0];
        if (isLongitude) {
            if (dirChar == 'W') return -fabs(value);
            if (dirChar == 'E') return fabs(value);
        } else {
            if (dirChar == 'S') return -fabs(value);
            if (dirChar == 'N') return fabs(value);
        }
    }
    
    return value;
}

- (void)showCoordinateConfirmationWithLatitude:(NSString *)latString 
                                    longitude:(NSString *)lonString {
    UIAlertController *confirmAlert = [UIAlertController
        alertControllerWithTitle:@"Confirm Coordinates"
        message:[NSString stringWithFormat:@"Latitude: %@\nLongitude: %@", latString, lonString]
        preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel
        handler:nil];
    
    UIAlertAction *confirmAction = [UIAlertAction
        actionWithTitle:@"Use These Coordinates"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * _Nonnull action) {
            [self processManualCoordinates:latString longitude:lonString];
        }];
    
    [confirmAlert addAction:cancelAction];
    [confirmAlert addAction:confirmAction];
    
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (void)processManualCoordinates:(NSString *)latString longitude:(NSString *)lonString {
    // Convert strings to numbers
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    
    NSNumber *latNumber = [formatter numberFromString:latString];
    NSNumber *lonNumber = [formatter numberFromString:lonString];
    
    if (!latNumber || !lonNumber) {
        [self showToastWithMessage:@"Invalid coordinates"];
        return;
    }
    
    double latitude = [latNumber doubleValue];
    double longitude = [lonNumber doubleValue];
    
    // Validate coordinate ranges
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        [self showToastWithMessage:@"Coordinates out of range"];
        return;
    }
    
    // Save as pinned location
    self.currentPinLocation = @{
        @"latitude": @(latitude),
        @"longitude": @(longitude),
        @"timestamp": [NSDate date]
    };
    
    // Save to user defaults
    [self savePinnedLocationToUserDefaults];
    
    // Center map on new location
    [self centerMapAndPlacePinnedPin:latitude longitude:longitude];
    
    // Update UI
    [self updatePinUnpinVisibility];
    [self showToastWithMessage:@"Location pinned"];
    
    // Update pin button state
    dispatch_async(dispatch_get_main_queue(), ^{
        self.unpinButton.hidden = NO;
        self.pinButton.hidden = YES;
        
        // Update labels if they exist
        for (UIView *subview in self.unpinContainer.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                UILabel *label = (UILabel *)subview;
                if ([label.text isEqualToString:@"Pin"]) {
                    label.hidden = YES;
                } else if ([label.text isEqualToString:@"Unpin"]) {
                    label.hidden = NO;
                }
            }
        }
    });
    
    // Enable GPS spoofing if not already enabled
    if (![LocationSpoofingManager sharedManager].isSpoofingEnabled) {
        [self.gpsSpoofingSwitch setOn:YES animated:YES];
        [self gpsSpoofingSwitchChanged:self.gpsSpoofingSwitch];
    } else {
        // Ensure the switch state is consistent
        [self.gpsSpoofingSwitch setOn:YES animated:YES];
    }
}

// Add method to handle GPS spoofing button tap
- (void)gpsSpoofingButtonTapped {
    // Create action sheet
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"GPS Spoofing"
                                                                            message:@"Manage GPS spoofing settings"
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Get current spoofing state
    LocationSpoofingManager *spoofingManager = [LocationSpoofingManager sharedManager];
    BOOL isSpoofingEnabled = [spoofingManager isSpoofingEnabled];
    
    // Toggle spoofing action
    NSString *toggleTitle = isSpoofingEnabled ? @"Disable GPS Spoofing" : @"Enable GPS Spoofing";
    [alertController addAction:[UIAlertAction actionWithTitle:toggleTitle
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        if (isSpoofingEnabled) {
            // Disable spoofing
            [spoofingManager disableSpoofing];
            self.gpsSpoofingSwitch.on = NO;
            [self showToastWithMessage:@"GPS Spoofing disabled"];
        } else {
            // Enable spoofing with current pin coordinates
            if (self.currentPinLocation && self.currentPinLocation[@"latitude"] && self.currentPinLocation[@"longitude"]) {
                double latitude = [self.currentPinLocation[@"latitude"] doubleValue];
                double longitude = [self.currentPinLocation[@"longitude"] doubleValue];
                
                [spoofingManager enableSpoofingWithLatitude:latitude longitude:longitude];
                self.gpsSpoofingSwitch.on = YES;
                [self showToastWithMessage:@"GPS Spoofing enabled"];
            } else {
                [self showToastWithMessage:@"Please place a pin first"];
            }
        }
    }]];
    
    
    // Add search location option
    [alertController addAction:[UIAlertAction actionWithTitle:@"Search Location"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        [self showLocationSearch];
    }]];
    
    // Add manual coordinate entry option
    [alertController addAction:[UIAlertAction actionWithTitle:@"Enter Coordinates Manually"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
        [self showManualCoordinateInput];
    }]];
    
    // Cancel action
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
    
    // Present the action sheet
    [self presentViewController:alertController animated:YES completion:nil];
}

// Add this new method to set up the GPS spoofing button
- (void)setupGPSSpoofingButton {
    UIButton *gpsSpoofingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    // Configure the GPS spoofing button with a symbol image
    UIImage *gpsSpoofingImage = [UIImage systemImageNamed:@"location.fill"];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    UIImage *configuredImage = [gpsSpoofingImage imageByApplyingSymbolConfiguration:config];
    [gpsSpoofingButton setImage:configuredImage forState:UIControlStateNormal];
    
    // Style the button to match other circular buttons
    gpsSpoofingButton.backgroundColor = [UIColor systemBlueColor];
    gpsSpoofingButton.tintColor = [UIColor whiteColor];
    gpsSpoofingButton.layer.cornerRadius = 20;
    
    // Add shadow
    gpsSpoofingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    gpsSpoofingButton.layer.shadowOffset = CGSizeMake(0, 2);
    gpsSpoofingButton.layer.shadowOpacity = 0.3;
    gpsSpoofingButton.layer.shadowRadius = 3;
    
    [gpsSpoofingButton addTarget:self action:@selector(gpsSpoofingButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    gpsSpoofingButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create container view for the button
    UIView *gpsSpoofingContainer = [[UIView alloc] init];
    gpsSpoofingContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:gpsSpoofingContainer];
    [gpsSpoofingContainer addSubview:gpsSpoofingButton];
    
    // Add label
    UILabel *gpsSpoofingLabel = [[UILabel alloc] init];
    gpsSpoofingLabel.text = @"GPS Spoof";
    gpsSpoofingLabel.textColor = [UIColor labelColor];
    gpsSpoofingLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    gpsSpoofingLabel.textAlignment = NSTextAlignmentCenter;
    gpsSpoofingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [gpsSpoofingContainer addSubview:gpsSpoofingLabel];
    
    // Position the GPS spoofing button to the left of the pin/unpin button
    [NSLayoutConstraint activateConstraints:@[
        [gpsSpoofingContainer.widthAnchor constraintEqualToConstant:60],
        [gpsSpoofingContainer.heightAnchor constraintEqualToConstant:55],
        [gpsSpoofingContainer.bottomAnchor constraintEqualToAnchor:self.unpinContainer.bottomAnchor],
        [gpsSpoofingContainer.rightAnchor constraintEqualToAnchor:self.unpinContainer.leftAnchor constant:-10],
        
        [gpsSpoofingButton.centerXAnchor constraintEqualToAnchor:gpsSpoofingContainer.centerXAnchor],
        [gpsSpoofingButton.topAnchor constraintEqualToAnchor:gpsSpoofingContainer.topAnchor],
        [gpsSpoofingButton.widthAnchor constraintEqualToConstant:40],
        [gpsSpoofingButton.heightAnchor constraintEqualToConstant:40],
        
        [gpsSpoofingLabel.topAnchor constraintEqualToAnchor:gpsSpoofingButton.bottomAnchor constant:1],
        [gpsSpoofingLabel.leadingAnchor constraintEqualToAnchor:gpsSpoofingContainer.leadingAnchor],
        [gpsSpoofingLabel.trailingAnchor constraintEqualToAnchor:gpsSpoofingContainer.trailingAnchor],
        [gpsSpoofingLabel.bottomAnchor constraintEqualToAnchor:gpsSpoofingContainer.bottomAnchor]
    ]];
    
    // Store reference
    objc_setAssociatedObject(self, "gpsSpoofingButton", gpsSpoofingButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "gpsSpoofingContainer", gpsSpoofingContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Helper Methods

- (void)ensureMapIsReadyWithCompletion:(void(^)(BOOL success))completion {
    // Check if map is ready before executing location-dependent operations
    [self.mapWebView evaluateJavaScript:@"(function() { return (typeof map !== 'undefined' && map !== null); })();"
                     completionHandler:^(id result, NSError *error) {
        if (error || ![result boolValue]) {
            PXLog(@"[WeaponX] Map is not ready: %@", error ? error.localizedDescription : @"map is undefined");
            
            // Try to initialize map or wait for it to be ready
            [self.mapWebView evaluateJavaScript:@"(function() { \
                if (typeof google !== 'undefined' && typeof google.maps !== 'undefined') { \
                    if (typeof initMap === 'function') { \
                        initMap(); \
                        return true; \
                    } \
                } \
                return false; \
            })();" completionHandler:^(id initResult, NSError *initError) {
                if (initError || ![initResult boolValue]) {
                    PXLog(@"[WeaponX] Could not initialize map: %@", initError ? initError.localizedDescription : @"initialization failed");
                    if (completion) completion(NO);
                } else {
                    // Map was just initialized, give it time to fully load
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (completion) completion(YES);
                    });
                }
            }];
        } else {
            // Map is ready
            if (completion) completion(YES);
        }
    }];
}

// Fix in setupAdvancedGpsSpoofingUI - use the existing isDarkMode variable
- (void)setupAdvancedGpsSpoofingUI {
    // Check if PRO button already exists to avoid duplicates
    UIView *existingProContainer = objc_getAssociatedObject(self, "proButtonContainer");
    if (existingProContainer) {
        // PRO button already set up, don't create another one
        return;
    }
    
    // Determine if in dark mode
    BOOL isDarkMode = NO;
    if (@available(iOS 13.0, *)) {
        isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    } else {
        // For older iOS versions, check if it's night time (7PM-7AM)
        NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitHour fromDate:[NSDate date]];
        isDarkMode = (components.hour >= 19 || components.hour < 7);
    }
    
    // Retrieve the GPS spoofing button container (from setupGPSSpoofingButton)
    UIView *gpsSpoofingContainer = objc_getAssociatedObject(self, "gpsSpoofingContainer");
    
    // Create a container view for the PRO button and label, similar to favorites button
    UIView *proButtonContainer = [[UIView alloc] init];
    proButtonContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:proButtonContainer];
    
    // Create the PRO button
    self.gpsAdvancedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    // Configure the button with rocket icon
    UIImage *proIcon = [UIImage systemImageNamed:@"bolt.fill"];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    UIImage *configuredImage = [proIcon imageByApplyingSymbolConfiguration:config];
    [self.gpsAdvancedButton setImage:configuredImage forState:UIControlStateNormal];
    
    // Style the button - make it circular like the favorites button
    self.gpsAdvancedButton.backgroundColor = [UIColor systemBlueColor];
    self.gpsAdvancedButton.tintColor = [UIColor whiteColor];
    self.gpsAdvancedButton.layer.cornerRadius = 20;
    
    // Add shadow
    self.gpsAdvancedButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.gpsAdvancedButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.gpsAdvancedButton.layer.shadowOpacity = 0.3;
    self.gpsAdvancedButton.layer.shadowRadius = 3;
    
    [self.gpsAdvancedButton addTarget:self action:@selector(gpsAdvancedButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.gpsAdvancedButton.translatesAutoresizingMaskIntoConstraints = NO;
    [proButtonContainer addSubview:self.gpsAdvancedButton];
    
    // Create and add a label
    UILabel *proLabel = [[UILabel alloc] init];
    proLabel.text = @"PRO";
    proLabel.textColor = [UIColor labelColor];
    proLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    proLabel.textAlignment = NSTextAlignmentCenter;
    proLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [proButtonContainer addSubview:proLabel];
    
    // Position the PRO button in the same row as the other bottom buttons
    // To the left of the GPS spoofing button
    if (gpsSpoofingContainer) {
        // Position PRO button to the left of GPS Spoofing button with proper spacing
        [NSLayoutConstraint activateConstraints:@[
            [proButtonContainer.widthAnchor constraintEqualToConstant:60],
            [proButtonContainer.heightAnchor constraintEqualToConstant:55],
            [proButtonContainer.bottomAnchor constraintEqualToAnchor:gpsSpoofingContainer.bottomAnchor],
            [proButtonContainer.trailingAnchor constraintEqualToAnchor:gpsSpoofingContainer.leadingAnchor constant:-30] // Proper spacing between PRO and GPS buttons
        ]];
    } else {
        // Fallback positioning if GPS spoofing container isn't found
        [NSLayoutConstraint activateConstraints:@[
            [proButtonContainer.widthAnchor constraintEqualToConstant:60],
            [proButtonContainer.heightAnchor constraintEqualToConstant:55],
            [proButtonContainer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
            [proButtonContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30]
        ]];
    }
    
    // Button constraints within its container
    [NSLayoutConstraint activateConstraints:@[
        [self.gpsAdvancedButton.topAnchor constraintEqualToAnchor:proButtonContainer.topAnchor],
        [self.gpsAdvancedButton.centerXAnchor constraintEqualToAnchor:proButtonContainer.centerXAnchor],
        [self.gpsAdvancedButton.widthAnchor constraintEqualToConstant:40],
        [self.gpsAdvancedButton.heightAnchor constraintEqualToConstant:40]
    ]];
    
    // Label constraints
    [NSLayoutConstraint activateConstraints:@[
        [proLabel.topAnchor constraintEqualToAnchor:self.gpsAdvancedButton.bottomAnchor constant:1],
        [proLabel.leadingAnchor constraintEqualToAnchor:proButtonContainer.leadingAnchor],
        [proLabel.trailingAnchor constraintEqualToAnchor:proButtonContainer.trailingAnchor],
        [proLabel.bottomAnchor constraintEqualToAnchor:proButtonContainer.bottomAnchor]
    ]];
    
    // Create the advanced panel (initially hidden) - only if not already created
    if (!self.gpsAdvancedPanel) {
        // Use the isDarkMode variable already declared at the beginning of this method
        
        // Create main container view with blur effect
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleExtraLight];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurView.translatesAutoresizingMaskIntoConstraints = NO;
        
        self.gpsAdvancedPanel = [[UIView alloc] init];
        self.gpsAdvancedPanel.translatesAutoresizingMaskIntoConstraints = NO;
        self.gpsAdvancedPanel.backgroundColor = [UIColor clearColor]; // Clear because we use blur
        self.gpsAdvancedPanel.layer.cornerRadius = 16;
        self.gpsAdvancedPanel.clipsToBounds = YES;
        self.gpsAdvancedPanel.hidden = YES; // Hidden by default
        [self.view addSubview:self.gpsAdvancedPanel];
        
        // Add blur view to panel
        [self.gpsAdvancedPanel addSubview:blurView];
        
        // Add a scroll view to ensure all content is visible
        UIScrollView *scrollView = [[UIScrollView alloc] init];
        scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        scrollView.showsVerticalScrollIndicator = YES;
        scrollView.showsHorizontalScrollIndicator = NO;
        scrollView.alwaysBounceVertical = YES;
        [self.gpsAdvancedPanel addSubview:scrollView];
        
        // Add a content view inside the scroll view
        UIView *contentView = [[UIView alloc] init];
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        contentView.backgroundColor = [UIColor clearColor];
        [scrollView addSubview:contentView];
        
        // Position the panel centered in the view with appropriate size constraints
        [NSLayoutConstraint activateConstraints:@[
            [self.gpsAdvancedPanel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.gpsAdvancedPanel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
            [self.gpsAdvancedPanel.widthAnchor constraintEqualToConstant:320],
            [self.gpsAdvancedPanel.heightAnchor constraintEqualToConstant:450], // Fixed height that fits most screens
            
            // Blur view should fill the entire panel
            [blurView.topAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.topAnchor],
            [blurView.leadingAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.leadingAnchor],
            [blurView.trailingAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.trailingAnchor],
            [blurView.bottomAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.bottomAnchor],
            
            // Scroll view fills the panel (minus header)
            [scrollView.topAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.topAnchor constant:50],
            [scrollView.leadingAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.leadingAnchor],
            [scrollView.trailingAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.trailingAnchor],
            [scrollView.bottomAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.bottomAnchor],
            
            // Content view width matches scroll view width
            [contentView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
            [contentView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor]
        ]];
        
        // Add a subtle border and shadow
        self.gpsAdvancedPanel.layer.borderWidth = 0.5;
        self.gpsAdvancedPanel.layer.borderColor = [UIColor colorWithWhite:isDarkMode ? 0.5 : 0.8 alpha:0.3].CGColor;
        self.gpsAdvancedPanel.layer.shadowColor = [UIColor blackColor].CGColor;
        self.gpsAdvancedPanel.layer.shadowOffset = CGSizeMake(0, 3);
        self.gpsAdvancedPanel.layer.shadowOpacity = isDarkMode ? 0.5 : 0.2;
        self.gpsAdvancedPanel.layer.shadowRadius = 8;
        
        // Create header container with gradient background (placed over the scroll view)
        UIView *headerView = [[UIView alloc] init];
        headerView.translatesAutoresizingMaskIntoConstraints = NO;
        headerView.backgroundColor = [UIColor clearColor];
        [self.gpsAdvancedPanel addSubview:headerView];
        
        // Add gradient to header
        CAGradientLayer *gradientLayer = [CAGradientLayer layer];
        gradientLayer.colors = @[
            (id)[UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:isDarkMode ? 0.8 : 0.2].CGColor,
            (id)[UIColor clearColor].CGColor
        ];
        gradientLayer.startPoint = CGPointMake(0.5, 0.0);
        gradientLayer.endPoint = CGPointMake(0.5, 1.0);
        headerView.layer.masksToBounds = YES;
        [headerView.layer addSublayer:gradientLayer];
        
        // Create a title label
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.text = @"Advanced GPS Options";
        titleLabel.textColor = isDarkMode ? [UIColor whiteColor] : [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:1.0];
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [headerView addSubview:titleLabel];
        
        // Add close button
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        closeButton.tintColor = isDarkMode ? [UIColor whiteColor] : [UIColor systemBlueColor];
        [closeButton addTarget:self action:@selector(gpsAdvancedButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [headerView addSubview:closeButton];
        
        // Movement section container
        UIView *movementSectionView = [[UIView alloc] init];
        movementSectionView.translatesAutoresizingMaskIntoConstraints = NO;
        movementSectionView.backgroundColor = isDarkMode ? [UIColor colorWithWhite:0.15 alpha:0.5] : [UIColor colorWithWhite:0.95 alpha:0.7];
        movementSectionView.layer.cornerRadius = 12;
        [contentView addSubview:movementSectionView];
        
        // Create the section title
        UILabel *movementSectionLabel = [[UILabel alloc] init];
        movementSectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        movementSectionLabel.text = @"Movement Options";
        movementSectionLabel.textColor = isDarkMode ? [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0] : [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:1.0];
        movementSectionLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [movementSectionView addSubview:movementSectionLabel];
        
        // Create transportation mode label
        UILabel *modeLabel = [[UILabel alloc] init];
        modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        modeLabel.text = @"Movement Mode:";
        modeLabel.textColor = [UIColor labelColor];
        modeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [movementSectionView addSubview:modeLabel];
        
        // Create transportation mode selector with improved style
        self.transportationModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Stationary", @"Walking", @"Driving"]];
        self.transportationModeControl.translatesAutoresizingMaskIntoConstraints = NO;
        self.transportationModeControl.selectedSegmentIndex = 0; // Default to stationary
        // Modern styling for iOS
        if (@available(iOS 13.0, *)) {
            self.transportationModeControl.selectedSegmentTintColor = [UIColor systemBlueColor];
            [self.transportationModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateSelected];
        }
        [self.transportationModeControl addTarget:self action:@selector(transportationModeChanged:) forControlEvents:UIControlEventValueChanged];
        [movementSectionView addSubview:self.transportationModeControl];
        
        // Create accuracy section with slider
        UIView *accuracyView = [[UIView alloc] init];
        accuracyView.translatesAutoresizingMaskIntoConstraints = NO;
        accuracyView.backgroundColor = isDarkMode ? [UIColor colorWithWhite:0.15 alpha:0.5] : [UIColor colorWithWhite:0.95 alpha:0.7];
        accuracyView.layer.cornerRadius = 12;
        [contentView addSubview:accuracyView];
        
        // Create accuracy section title
        UILabel *accuracySectionLabel = [[UILabel alloc] init];
        accuracySectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        accuracySectionLabel.text = @"Location Accuracy";
        accuracySectionLabel.textColor = isDarkMode ? [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0] : [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:1.0];
        accuracySectionLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [accuracyView addSubview:accuracySectionLabel];
        
        // Create accuracy label with current value
        UILabel *accuracyLabel = [[UILabel alloc] init];
        accuracyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        accuracyLabel.text = @"GPS Accuracy: 10.0m";
        accuracyLabel.tag = 1001; // Tag for updating text
        accuracyLabel.textColor = [UIColor labelColor];
        accuracyLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [accuracyView addSubview:accuracyLabel];
        
        // Create a clearer accuracy slider
        self.accuracySlider = [[UISlider alloc] init];
        self.accuracySlider.translatesAutoresizingMaskIntoConstraints = NO;
        self.accuracySlider.minimumValue = 5.0;
        self.accuracySlider.maximumValue = 15.0;
        self.accuracySlider.value = 10.0; // Default accuracy
        self.accuracySlider.minimumTrackTintColor = [UIColor systemBlueColor];
        [self.accuracySlider addTarget:self action:@selector(accuracySliderChanged:) forControlEvents:UIControlEventValueChanged];
        [accuracyView addSubview:self.accuracySlider];
        
        // Add min/max labels for better understanding
        UILabel *minAccuracyLabel = [[UILabel alloc] init];
        minAccuracyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        minAccuracyLabel.text = @"5m (Precise)";
        minAccuracyLabel.textColor = [UIColor secondaryLabelColor];
        minAccuracyLabel.font = [UIFont systemFontOfSize:10];
        [accuracyView addSubview:minAccuracyLabel];
        
        UILabel *maxAccuracyLabel = [[UILabel alloc] init];
        maxAccuracyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        maxAccuracyLabel.text = @"15m (Less Precise)";
        maxAccuracyLabel.textColor = [UIColor secondaryLabelColor];
        maxAccuracyLabel.font = [UIFont systemFontOfSize:10];
        [accuracyView addSubview:maxAccuracyLabel];
        
        // Create jitter option container
        UIView *jitterView = [[UIView alloc] init];
        jitterView.translatesAutoresizingMaskIntoConstraints = NO;
        jitterView.backgroundColor = isDarkMode ? [UIColor colorWithWhite:0.15 alpha:0.5] : [UIColor colorWithWhite:0.95 alpha:0.7];
        jitterView.layer.cornerRadius = 12;
        [contentView addSubview:jitterView];
        
        // Create jitter section label
        UILabel *jitterSectionLabel = [[UILabel alloc] init];
        jitterSectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        jitterSectionLabel.text = @"Position Variations";
        jitterSectionLabel.textColor = isDarkMode ? [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0] : [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:1.0];
        jitterSectionLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [jitterView addSubview:jitterSectionLabel];
        
        // Create jitter label with description
        UILabel *jitterLabel = [[UILabel alloc] init];
        jitterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        jitterLabel.text = @"Enable natural position variations\nmaking movement more realistic";
        jitterLabel.numberOfLines = 2;
        jitterLabel.textColor = [UIColor labelColor];
        jitterLabel.font = [UIFont systemFontOfSize:12];
        [jitterView addSubview:jitterLabel];
        
        // Create enhanced jitter switch
        self.jitterSwitch = [[UISwitch alloc] init];
        self.jitterSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        self.jitterSwitch.on = YES; // Default to on
        self.jitterSwitch.onTintColor = [UIColor systemBlueColor];
        [self.jitterSwitch addTarget:self action:@selector(jitterSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        [jitterView addSubview:self.jitterSwitch];
        
        // Create speed/course display in a more prominent card
        UIView *infoCardView = [[UIView alloc] init];
        infoCardView.translatesAutoresizingMaskIntoConstraints = NO;
        infoCardView.backgroundColor = isDarkMode ? [UIColor colorWithWhite:0.15 alpha:0.5] : [UIColor colorWithWhite:0.95 alpha:0.7];
        infoCardView.layer.cornerRadius = 12;
        [contentView addSubview:infoCardView];
        
        // Speed info label
        UILabel *infoTitleLabel = [[UILabel alloc] init];
        infoTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        infoTitleLabel.text = @"Current Movement Data";
        infoTitleLabel.textColor = isDarkMode ? [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0] : [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:1.0];
        infoTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [infoCardView addSubview:infoTitleLabel];
        
        // Create an enhanced speed/course display label
        self.speedCourseLabel = [[UILabel alloc] init];
        self.speedCourseLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.speedCourseLabel.text = @"Speed: 0.0 m/s   Course: 0°";
        self.speedCourseLabel.textColor = [UIColor labelColor];
        self.speedCourseLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
        self.speedCourseLabel.textAlignment = NSTextAlignmentCenter;
        [infoCardView addSubview:self.speedCourseLabel];
        
        // -- Path Movement Controls --
        
        // Path section container
        UIView *pathView = [[UIView alloc] init];
        pathView.translatesAutoresizingMaskIntoConstraints = NO;
        pathView.backgroundColor = isDarkMode ? [UIColor colorWithWhite:0.15 alpha:0.5] : [UIColor colorWithWhite:0.95 alpha:0.7];
        pathView.layer.cornerRadius = 12;
        [contentView addSubview:pathView];
        
        // Path section label
        UILabel *pathSectionLabel = [[UILabel alloc] init];
        pathSectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        pathSectionLabel.text = @"Path Movement";
        pathSectionLabel.textColor = isDarkMode ? [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0] : [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:1.0];
        pathSectionLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [pathView addSubview:pathSectionLabel];
        
        // Create path creation button
        UIButton *createPathButton = [UIButton buttonWithType:UIButtonTypeSystem];
        createPathButton.translatesAutoresizingMaskIntoConstraints = NO;
        [createPathButton setTitle:@"Create Path" forState:UIControlStateNormal];
        createPathButton.backgroundColor = isDarkMode ? [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.8] : [UIColor systemBlueColor];
        createPathButton.tintColor = [UIColor whiteColor];
        createPathButton.layer.cornerRadius = 10;
        createPathButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [createPathButton addTarget:self action:@selector(createPathButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [pathView addSubview:createPathButton];
        
        // Start/Stop Movement button
        UIButton *startStopButton = [UIButton buttonWithType:UIButtonTypeSystem];
        startStopButton.translatesAutoresizingMaskIntoConstraints = NO;
        [startStopButton setTitle:@"Start Movement" forState:UIControlStateNormal];
        startStopButton.backgroundColor = [UIColor systemGreenColor];
        startStopButton.tintColor = [UIColor whiteColor];
        startStopButton.layer.cornerRadius = 10;
        startStopButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [startStopButton addTarget:self action:@selector(startStopMovementButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [pathView addSubview:startStopButton];
        startStopButton.tag = 1002; // Tag for updating button text
        
        // Movement speed label
        UILabel *movementSpeedLabel = [[UILabel alloc] init];
        movementSpeedLabel.translatesAutoresizingMaskIntoConstraints = NO;
        movementSpeedLabel.text = @"Path Speed: 5.0 m/s";
        movementSpeedLabel.tag = 1003; // Tag for updating text
        movementSpeedLabel.textColor = [UIColor labelColor];
        movementSpeedLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [pathView addSubview:movementSpeedLabel];
        self.movementSpeedLabel = movementSpeedLabel;
        
        // Speed slider for path movement
        UISlider *movementSpeedSlider = [[UISlider alloc] init];
        movementSpeedSlider.translatesAutoresizingMaskIntoConstraints = NO;
        movementSpeedSlider.minimumValue = 1.0;  // 1 m/s (walking)
        movementSpeedSlider.maximumValue = 20.0; // 20 m/s (driving)
        movementSpeedSlider.value = 5.0;         // Default 5 m/s
        movementSpeedSlider.minimumTrackTintColor = [UIColor systemBlueColor];
        [movementSpeedSlider addTarget:self action:@selector(movementSpeedSliderChanged:) forControlEvents:UIControlEventValueChanged];
        [pathView addSubview:movementSpeedSlider];
        self.movementSpeedSlider = movementSpeedSlider;
        
        // Min/max speed labels
        UILabel *minSpeedLabel = [[UILabel alloc] init];
        minSpeedLabel.translatesAutoresizingMaskIntoConstraints = NO;
        minSpeedLabel.text = @"1 m/s";
        minSpeedLabel.textColor = [UIColor secondaryLabelColor];
        minSpeedLabel.font = [UIFont systemFontOfSize:10];
        [pathView addSubview:minSpeedLabel];
        
        UILabel *maxSpeedLabel = [[UILabel alloc] init];
        maxSpeedLabel.translatesAutoresizingMaskIntoConstraints = NO;
        maxSpeedLabel.text = @"20 m/s";
        maxSpeedLabel.textColor = [UIColor secondaryLabelColor];
        maxSpeedLabel.font = [UIFont systemFontOfSize:10];
        [pathView addSubview:maxSpeedLabel];
        
        // Status label for path movement
        UILabel *pathStatusLabel = [[UILabel alloc] init];
        pathStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        pathStatusLabel.text = @"Status: Ready";
        pathStatusLabel.textColor = [UIColor systemGreenColor];
        pathStatusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        pathStatusLabel.textAlignment = NSTextAlignmentCenter;
        [pathView addSubview:pathStatusLabel];
        self.pathStatusLabel = pathStatusLabel;
        
        // Position all elements with improved layout
        [NSLayoutConstraint activateConstraints:@[
            // Header view
            [headerView.topAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.topAnchor],
            [headerView.leadingAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.leadingAnchor],
            [headerView.trailingAnchor constraintEqualToAnchor:self.gpsAdvancedPanel.trailingAnchor],
            [headerView.heightAnchor constraintEqualToConstant:50],
            
            // Header title
            [titleLabel.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
            [titleLabel.centerXAnchor constraintEqualToAnchor:headerView.centerXAnchor],
            
            // Close button
            [closeButton.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
            [closeButton.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-15],
            [closeButton.widthAnchor constraintEqualToConstant:24],
            [closeButton.heightAnchor constraintEqualToConstant:24],
            
            // Content height constraint to enable scrolling
            [contentView.heightAnchor constraintGreaterThanOrEqualToConstant:600],
            
            // Movement section
            [movementSectionView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:10],
            [movementSectionView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:15],
            [movementSectionView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-15],
            [movementSectionView.heightAnchor constraintEqualToConstant:90],
            
            // Movement section title
            [movementSectionLabel.topAnchor constraintEqualToAnchor:movementSectionView.topAnchor constant:10],
            [movementSectionLabel.leadingAnchor constraintEqualToAnchor:movementSectionView.leadingAnchor constant:15],
            
            // Mode label
            [modeLabel.topAnchor constraintEqualToAnchor:movementSectionLabel.bottomAnchor constant:10],
            [modeLabel.leadingAnchor constraintEqualToAnchor:movementSectionView.leadingAnchor constant:15],
            
            // Movement mode control
            [self.transportationModeControl.topAnchor constraintEqualToAnchor:modeLabel.bottomAnchor constant:5],
            [self.transportationModeControl.leadingAnchor constraintEqualToAnchor:movementSectionView.leadingAnchor constant:15],
            [self.transportationModeControl.trailingAnchor constraintEqualToAnchor:movementSectionView.trailingAnchor constant:-15],
            
            // Accuracy section
            [accuracyView.topAnchor constraintEqualToAnchor:movementSectionView.bottomAnchor constant:10],
            [accuracyView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:15],
            [accuracyView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-15],
            [accuracyView.heightAnchor constraintEqualToConstant:100],
            
            // Accuracy section title
            [accuracySectionLabel.topAnchor constraintEqualToAnchor:accuracyView.topAnchor constant:10],
            [accuracySectionLabel.leadingAnchor constraintEqualToAnchor:accuracyView.leadingAnchor constant:15],
            
            // Accuracy value label
            [accuracyLabel.topAnchor constraintEqualToAnchor:accuracySectionLabel.bottomAnchor constant:10],
            [accuracyLabel.leadingAnchor constraintEqualToAnchor:accuracyView.leadingAnchor constant:15],
            
            // Accuracy slider
            [self.accuracySlider.topAnchor constraintEqualToAnchor:accuracyLabel.bottomAnchor constant:8],
            [self.accuracySlider.leadingAnchor constraintEqualToAnchor:accuracyView.leadingAnchor constant:15],
            [self.accuracySlider.trailingAnchor constraintEqualToAnchor:accuracyView.trailingAnchor constant:-15],
            
            // Min/max labels for slider
            [minAccuracyLabel.topAnchor constraintEqualToAnchor:self.accuracySlider.bottomAnchor constant:5],
            [minAccuracyLabel.leadingAnchor constraintEqualToAnchor:self.accuracySlider.leadingAnchor],
            
            [maxAccuracyLabel.topAnchor constraintEqualToAnchor:self.accuracySlider.bottomAnchor constant:5],
            [maxAccuracyLabel.trailingAnchor constraintEqualToAnchor:self.accuracySlider.trailingAnchor],
            
            // Jitter section
            [jitterView.topAnchor constraintEqualToAnchor:accuracyView.bottomAnchor constant:10],
            [jitterView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:15],
            [jitterView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-15],
            [jitterView.heightAnchor constraintEqualToConstant:85],
            
            // Jitter section title
            [jitterSectionLabel.topAnchor constraintEqualToAnchor:jitterView.topAnchor constant:10],
            [jitterSectionLabel.leadingAnchor constraintEqualToAnchor:jitterView.leadingAnchor constant:15],
            
            // Jitter description and switch
            [jitterLabel.topAnchor constraintEqualToAnchor:jitterSectionLabel.bottomAnchor constant:10],
            [jitterLabel.leadingAnchor constraintEqualToAnchor:jitterView.leadingAnchor constant:15],
            [jitterLabel.trailingAnchor constraintEqualToAnchor:self.jitterSwitch.leadingAnchor constant:-10],
            
            [self.jitterSwitch.centerYAnchor constraintEqualToAnchor:jitterLabel.centerYAnchor],
            [self.jitterSwitch.trailingAnchor constraintEqualToAnchor:jitterView.trailingAnchor constant:-15],
            
            // Info card section
            [infoCardView.topAnchor constraintEqualToAnchor:jitterView.bottomAnchor constant:10],
            [infoCardView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:15],
            [infoCardView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-15],
            [infoCardView.heightAnchor constraintEqualToConstant:75],
            
            // Info title
            [infoTitleLabel.topAnchor constraintEqualToAnchor:infoCardView.topAnchor constant:10],
            [infoTitleLabel.leadingAnchor constraintEqualToAnchor:infoCardView.leadingAnchor constant:15],
            
            // Speed/course info
            [self.speedCourseLabel.topAnchor constraintEqualToAnchor:infoTitleLabel.bottomAnchor constant:15],
            [self.speedCourseLabel.leadingAnchor constraintEqualToAnchor:infoCardView.leadingAnchor constant:15],
            [self.speedCourseLabel.trailingAnchor constraintEqualToAnchor:infoCardView.trailingAnchor constant:-15],
            
            // Path section
            [pathView.topAnchor constraintEqualToAnchor:infoCardView.bottomAnchor constant:10],
            [pathView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:15],
            [pathView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-15],
            [pathView.heightAnchor constraintEqualToConstant:170], // Taller to fit all content
            [pathView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20],
            
            // Path section title
            [pathSectionLabel.topAnchor constraintEqualToAnchor:pathView.topAnchor constant:10],
            [pathSectionLabel.leadingAnchor constraintEqualToAnchor:pathView.leadingAnchor constant:15],
            
            // Path buttons
            [createPathButton.topAnchor constraintEqualToAnchor:pathSectionLabel.bottomAnchor constant:12],
            [createPathButton.leadingAnchor constraintEqualToAnchor:pathView.leadingAnchor constant:15],
            [createPathButton.widthAnchor constraintEqualToConstant:130],
            [createPathButton.heightAnchor constraintEqualToConstant:35],
            
            [startStopButton.topAnchor constraintEqualToAnchor:pathSectionLabel.bottomAnchor constant:12],
            [startStopButton.trailingAnchor constraintEqualToAnchor:pathView.trailingAnchor constant:-15],
            [startStopButton.widthAnchor constraintEqualToConstant:130],
            [startStopButton.heightAnchor constraintEqualToConstant:35],
            
            // Path speed label
            [movementSpeedLabel.topAnchor constraintEqualToAnchor:createPathButton.bottomAnchor constant:15],
            [movementSpeedLabel.leadingAnchor constraintEqualToAnchor:pathView.leadingAnchor constant:15],
            
            // Path speed slider
            [movementSpeedSlider.topAnchor constraintEqualToAnchor:movementSpeedLabel.bottomAnchor constant:8],
            [movementSpeedSlider.leadingAnchor constraintEqualToAnchor:pathView.leadingAnchor constant:15],
            [movementSpeedSlider.trailingAnchor constraintEqualToAnchor:pathView.trailingAnchor constant:-15],
            
            // Min/max speed labels
            [minSpeedLabel.topAnchor constraintEqualToAnchor:movementSpeedSlider.bottomAnchor constant:5],
            [minSpeedLabel.leadingAnchor constraintEqualToAnchor:movementSpeedSlider.leadingAnchor],
            
            [maxSpeedLabel.topAnchor constraintEqualToAnchor:movementSpeedSlider.bottomAnchor constant:5],
            [maxSpeedLabel.trailingAnchor constraintEqualToAnchor:movementSpeedSlider.trailingAnchor],
            
            // Path status label
            [pathStatusLabel.topAnchor constraintEqualToAnchor:minSpeedLabel.bottomAnchor constant:10],
            [pathStatusLabel.leadingAnchor constraintEqualToAnchor:pathView.leadingAnchor],
            [pathStatusLabel.trailingAnchor constraintEqualToAnchor:pathView.trailingAnchor],
            [pathStatusLabel.bottomAnchor constraintLessThanOrEqualToAnchor:pathView.bottomAnchor constant:-10]
        ]];
        
        // Set the gradient frame
        CAGradientLayer *headerGradient = (CAGradientLayer *)gradientLayer;
        headerGradient.frame = CGRectMake(0, 0, 320, 50);
    }
    
    // Save reference to the proButtonContainer to avoid deallocation
    objc_setAssociatedObject(self, "proButtonContainer", proButtonContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    PXLog(@"[WeaponX] Advanced GPS spoofing PRO button configured");
    
    // Load saved settings after all controls are initialized
    [self loadSavedAdvancedGPSSettings];
}

// Toggle advanced GPS settings panel with smooth animation
- (void)gpsAdvancedButtonTapped:(UIButton *)sender {
    // Toggle the advanced panel visibility with animation
    BOOL shouldShow = self.gpsAdvancedPanel.hidden;
    
    PXLog(@"[WeaponX] %@ advanced GPS panel", shouldShow ? @"Showing" : @"Hiding");
    
    if (shouldShow) {
        // Prepare for animation
        self.gpsAdvancedPanel.hidden = NO;
        self.gpsAdvancedPanel.alpha = 0.0;
        self.gpsAdvancedPanel.transform = CGAffineTransformMakeScale(0.95, 0.95);
        
        // Animate appearance
        [UIView animateWithDuration:0.3 
                              delay:0 
                            options:UIViewAnimationOptionCurveEaseOut 
                         animations:^{
            self.gpsAdvancedPanel.alpha = 1.0;
            self.gpsAdvancedPanel.transform = CGAffineTransformIdentity;
        } completion:nil];
        
        // Verify UI elements are properly initialized
        if (!self.speedCourseLabel) {
            PXLog(@"[WeaponX] Warning: speedCourseLabel is nil");
        }
        
        if (!self.movementSpeedSlider) {
            PXLog(@"[WeaponX] Warning: movementSpeedSlider is nil");
        }
        
        if (!self.pathStatusLabel) {
            PXLog(@"[WeaponX] Warning: pathStatusLabel is nil");
        }
        
        // Start the timer if not already running
        if (!self.speedUpdateTimer) {
            self.speedUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                     target:self
                                                                   selector:@selector(updateSpeedDisplay)
                                                                   userInfo:nil
                                                                    repeats:YES];
        }
        } else {
        // Animate disappearance
        [UIView animateWithDuration:0.25 
                              delay:0 
                            options:UIViewAnimationOptionCurveEaseIn 
                         animations:^{
            self.gpsAdvancedPanel.alpha = 0.0;
            self.gpsAdvancedPanel.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } completion:^(BOOL finished) {
            self.gpsAdvancedPanel.hidden = YES;
            self.gpsAdvancedPanel.transform = CGAffineTransformIdentity;
        }];
        
        // Stop the timer
        PXLog(@"[WeaponX] Stopping speed update timer");
        if (self.speedUpdateTimer) {
            [self.speedUpdateTimer invalidate];
            self.speedUpdateTimer = nil;
        }
    }
}

// Handler for the transportation mode control
- (void)transportationModeChanged:(UISegmentedControl *)sender {
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    
    // Add safety check for the selected index
    NSInteger selectedIndex = sender.selectedSegmentIndex;
    if (selectedIndex < 0 || selectedIndex > 2) {
        // Invalid selection, default to stationary
        selectedIndex = 0;
        sender.selectedSegmentIndex = 0;
    }
    
    // Convert safely to TransportationMode enum
    TransportationMode mode = (TransportationMode)selectedIndex;
    
    // Log the change for debugging
    PXLog(@"[WeaponX] Changing transportation mode to %ld", (long)mode);
    
    @try {
        [manager setTransportationMode:mode];
        
        // Save to NSUserDefaults
        [[NSUserDefaults standardUserDefaults] setInteger:selectedIndex forKey:kTransportationModeKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in transportationModeChanged: %@", exception);
        // Reset to stationary in case of error
        sender.selectedSegmentIndex = 0;
    }
}

// Handler for the accuracy slider
- (void)accuracySliderChanged:(UISlider *)sender {
    // Update the label
    UILabel *accuracyLabel = [self.gpsAdvancedPanel viewWithTag:1001];
    if (accuracyLabel) {
        accuracyLabel.text = [NSString stringWithFormat:@"GPS Accuracy: %.1fm", sender.value];
    }
    
    // Validate the slider value
    float accuracyValue = sender.value;
    if (isnan(accuracyValue) || isinf(accuracyValue)) {
        // Invalid value, reset to default
        accuracyValue = 10.0;
        sender.value = 10.0;
    }
    
    // Clamp the value within valid range (5-15m)
    accuracyValue = MAX(5.0, MIN(15.0, accuracyValue));
    
    // Log the change for debugging
    PXLog(@"[WeaponX] Setting GPS accuracy to %.1f meters", accuracyValue);
    
    // Update the LocationSpoofingManager
    @try {
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        [manager setAccuracyValue:accuracyValue];
        
        // Save to NSUserDefaults
        [[NSUserDefaults standardUserDefaults] setFloat:accuracyValue forKey:kAccuracyValueKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in accuracySliderChanged: %@", exception);
    }
}

// Handler for the jitter switch
- (void)jitterSwitchChanged:(UISwitch *)sender {
    // Log the change for debugging
    PXLog(@"[WeaponX] Setting position jitter %@", sender.isOn ? @"ON" : @"OFF");
    
    @try {
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        [manager setJitterEnabled:sender.isOn];
        
        // Also set the position variations flag to enable true 360° movement
        manager.positionVariationsEnabled = sender.isOn;
        
        // Save to NSUserDefaults
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:kJitterEnabledKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in jitterSwitchChanged: %@", exception);
        // Reset switch state in case of error
        sender.on = YES; // Default to ON
    }
}

// Method to update the speed/course display
- (void)updateSpeedDisplay {
    // Format speed and course properly with appropriate precision
    NSString *speedText;
    
    // Access the properties from LocationSpoofingManager
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    double speed = manager.lastReportedSpeed;
    
    // Format speed with appropriate precision and reasonable limit
    if (speed > 1000 || speed < 0) {
        // Cap unreasonable speed values
        speed = 0.0;
        speedText = @"0.0 m/s";
            } else {
        // Format with 1 decimal place
        speedText = [NSString stringWithFormat:@"%.1f m/s", speed];
    }
    
    // Get course (direction)
    int course = (int)manager.lastReportedCourse;
    
    // Format course with 0 decimal places
    NSString *courseText = [NSString stringWithFormat:@"%d°", course];
    
    // Update the display label
    self.speedCourseLabel.text = [NSString stringWithFormat:@"Speed: %@   Course: %@", speedText, courseText];
    
    // Update path status if the label exists
    if (self.pathStatusLabel) {
        if ([manager isCurrentlyMoving]) {
            double remainingTime = [manager estimatedTimeToCompleteCurrentPath];
            self.pathStatusLabel.text = [NSString stringWithFormat:@"Status: Moving (%.0f sec remaining)", remainingTime];
            self.pathStatusLabel.textColor = [UIColor systemGreenColor];
            
            // Update Start/Stop button if it exists
            for (UIView *view in [self findAllSubviewsOfClass:[UIButton class] inView:self.gpsAdvancedPanel]) {
                if ([view isKindOfClass:[UIButton class]]) {
                    UIButton *button = (UIButton *)view;
                    if (button.tag == 1002) { // Tag for start/stop button
                        [button setTitle:@"Stop Movement" forState:UIControlStateNormal];
                        button.backgroundColor = [UIColor systemRedColor];
                    }
                }
            }
        } else {
            // Not moving
            if ([manager.currentPath count] > 0) {
                self.pathStatusLabel.text = @"Status: Path Ready";
                self.pathStatusLabel.textColor = [UIColor systemBlueColor];
            } else {
                self.pathStatusLabel.text = @"Status: No Path Set";
                self.pathStatusLabel.textColor = [UIColor secondaryLabelColor];
            }
            
            // Update Start/Stop button if it exists
            for (UIView *view in [self findAllSubviewsOfClass:[UIButton class] inView:self.gpsAdvancedPanel]) {
                if ([view isKindOfClass:[UIButton class]]) {
                    UIButton *button = (UIButton *)view;
                    if (button.tag == 1002) { // Tag for start/stop button
                        [button setTitle:@"Start Movement" forState:UIControlStateNormal];
                        button.backgroundColor = [UIColor systemGreenColor];
                    }
                }
            }
        }
    }
}

// Handler for the movement speed slider
- (void)movementSpeedSliderChanged:(UISlider *)sender {
    // Update the label
    self.movementSpeedLabel.text = [NSString stringWithFormat:@"Path Speed: %.1f m/s", sender.value];
    
    // Validate the slider value
    float speedValue = sender.value;
    if (isnan(speedValue) || isinf(speedValue)) {
        // Invalid value, reset to default
        speedValue = 5.0;
        sender.value = 5.0;
    }
    
    // Clamp the value within valid range (1-20 m/s)
    speedValue = MAX(1.0, MIN(20.0, speedValue));
    
    // Save to NSUserDefaults
    [[NSUserDefaults standardUserDefaults] setFloat:speedValue forKey:kMovementSpeedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Path creation button handler
- (void)createPathButtonTapped:(UIButton *)sender {
    // Create an alert for path creation options
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Create Path" 
                                                                             message:@"Choose path creation method:" 
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add map tap option
    UIAlertAction *mapTapAction = [UIAlertAction actionWithTitle:@"Tap on Map" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self startPathCreationByMapTap];
    }];
    
    // Add straight line option
    UIAlertAction *straightLineAction = [UIAlertAction actionWithTitle:@"Straight Line (Current → New)" 
                                                               style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
        [self promptForStraightLinePath];
    }];
    
    // Add predefined path option
    UIAlertAction *predefinedAction = [UIAlertAction actionWithTitle:@"Predefined Path" 
                                                               style:UIAlertActionStyleDefault 
                                                             handler:^(UIAlertAction * _Nonnull action) {
        [self showPredefinedPathOptions];
    }];
    
    // Add cancel option
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" 
                                                           style:UIAlertActionStyleCancel 
                                                             handler:nil];
    
    [alertController addAction:mapTapAction];
    [alertController addAction:straightLineAction];
    [alertController addAction:predefinedAction];
    [alertController addAction:cancelAction];
    
    // Present the alert
    [self presentViewController:alertController animated:YES completion:nil];
}

// Start path creation by map tap
- (void)startPathCreationByMapTap {
    // Update status
    self.pathStatusLabel.text = @"Status: Tap on map to set waypoints";
    self.pathStatusLabel.textColor = [UIColor systemOrangeColor];
    
    // For demonstration, we'll use a predefined path for now
    [self createSimpleDemoPath];
}

// Create a simple demo path around the current location
- (void)createSimpleDemoPath {
    // Get current spoofed location
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    CLLocationCoordinate2D currentLocation = CLLocationCoordinate2DMake(
        [manager getSpoofedLatitude], 
        [manager getSpoofedLongitude]
    );
    
    // Create a simple rectangular path around the current location
    double offset = 0.001; // Approximately 100 meters
    
    NSArray *waypoints = @[
        [NSValue valueWithCGPoint:CGPointMake(currentLocation.latitude, currentLocation.longitude)],
        [NSValue valueWithCGPoint:CGPointMake(currentLocation.latitude + offset, currentLocation.longitude)],
        [NSValue valueWithCGPoint:CGPointMake(currentLocation.latitude + offset, currentLocation.longitude + offset)],
        [NSValue valueWithCGPoint:CGPointMake(currentLocation.latitude, currentLocation.longitude + offset)],
        [NSValue valueWithCGPoint:CGPointMake(currentLocation.latitude, currentLocation.longitude)]
    ];
    
    // Store the waypoints for movement
    [self setPathWaypoints:waypoints];
    
    // Update UI
    self.pathStatusLabel.text = @"Status: Path Created (5 waypoints)";
    self.pathStatusLabel.textColor = [UIColor systemGreenColor];
    
    // Update the start/stop button
    UIButton *startStopButton = [self.gpsAdvancedPanel viewWithTag:1002];
    [startStopButton setTitle:@"Start Movement" forState:UIControlStateNormal];
    [startStopButton setBackgroundColor:[UIColor systemGreenColor]];
}

// Store the path waypoints for movement
- (void)setPathWaypoints:(NSArray *)waypoints {
    // Convert waypoints to a serializable format (dictionaries)
    NSMutableArray *serializableWaypoints = [NSMutableArray arrayWithCapacity:waypoints.count];
    
    for (NSValue *value in waypoints) {
        CGPoint point;
        [value getValue:&point]; // Use getValue: instead of CGPointValue
        // Store as a dictionary with latitude and longitude keys
        NSDictionary *waypointDict = @{
            @"latitude": @(point.x),
            @"longitude": @(point.y)
        };
        [serializableWaypoints addObject:waypointDict];
    }
    
    // Store in user defaults for persistence
    [[NSUserDefaults standardUserDefaults] setObject:serializableWaypoints forKey:kPathWaypointsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    // Also update LocationSpoofingManager's currentPath so UI reflects the new path
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    manager.currentPath = waypoints;
}

// Get the stored path waypoints
- (NSArray *)getPathWaypoints {
    NSArray *storedWaypoints = [[NSUserDefaults standardUserDefaults] objectForKey:kPathWaypointsKey];
    if (!storedWaypoints || storedWaypoints.count < 2) {
        return nil;
    }
    
    // Convert dictionaries back to format expected by the movement functions
    NSMutableArray *waypoints = [NSMutableArray arrayWithCapacity:storedWaypoints.count];
    
    for (NSDictionary *waypointDict in storedWaypoints) {
        if ([waypointDict isKindOfClass:[NSDictionary class]]) {
            double lat = [waypointDict[@"latitude"] doubleValue];
            double lon = [waypointDict[@"longitude"] doubleValue];
            
            // Create waypoint as NSValue containing CGPoint
            [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(lat, lon)]];
        }
    }
    
    return waypoints;
}

// Prompt for straight line path
- (void)promptForStraightLinePath {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Create Straight Line Path" 
                                                                             message:@"Enter destination coordinates:" 
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    // Add text fields for latitude and longitude
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Destination Latitude";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Destination Longitude";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    // Add create action
    UIAlertAction *createAction = [UIAlertAction actionWithTitle:@"Create Path" 
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction * _Nonnull action) {
        // Get the entered coordinates
        UITextField *latField = alertController.textFields[0];
        UITextField *lonField = alertController.textFields[1];
        
        double destLat = [latField.text doubleValue];
        double destLon = [lonField.text doubleValue];
        
        // Validate coordinates
        if (CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(destLat, destLon))) {
            [self createStraightLinePath:CLLocationCoordinate2DMake(destLat, destLon)];
        } else {
            // Show error
            self.pathStatusLabel.text = @"Status: Invalid coordinates";
            self.pathStatusLabel.textColor = [UIColor systemRedColor];
        }
    }];
    
    // Add cancel action
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    [alertController addAction:createAction];
    [alertController addAction:cancelAction];
    
    // Present the alert
    [self presentViewController:alertController animated:YES completion:nil];
}

// Create a straight line path to the given destination
- (void)createStraightLinePath:(CLLocationCoordinate2D)destination {
    // Get current spoofed location
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    CLLocationCoordinate2D currentLocation = CLLocationCoordinate2DMake(
        [manager getSpoofedLatitude], 
        [manager getSpoofedLongitude]
    );
    
    // Create a straight line path from current to destination
    NSArray *waypoints = @[
        [NSValue valueWithCGPoint:CGPointMake(currentLocation.latitude, currentLocation.longitude)],
        [NSValue valueWithCGPoint:CGPointMake(destination.latitude, destination.longitude)]
    ];
    
    // Store the waypoints for movement
    [self setPathWaypoints:waypoints];
    
    // Update UI
    self.pathStatusLabel.text = @"Status: Path Created (straight line)";
    self.pathStatusLabel.textColor = [UIColor systemGreenColor];
    
    // Update the start/stop button
    UIButton *startStopButton = [self.gpsAdvancedPanel viewWithTag:1002];
    [startStopButton setTitle:@"Start Movement" forState:UIControlStateNormal];
    [startStopButton setBackgroundColor:[UIColor systemGreenColor]];
}

// Show predefined path options
- (void)showPredefinedPathOptions {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Predefined Paths" 
                                                                             message:@"Choose a path pattern:" 
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add predefined path options
    UIAlertAction *circleAction = [UIAlertAction actionWithTitle:@"Circle Around Current Location" 
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self createCirclePath];
    }];
    
    UIAlertAction *squareAction = [UIAlertAction actionWithTitle:@"Square Around Current Location" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self createSimpleDemoPath]; // Uses rectangular path
    }];
    
    UIAlertAction *zigzagAction = [UIAlertAction actionWithTitle:@"Zigzag Pattern" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self createZigzagPath];
    }];
    
    // Add cancel option
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];
    
    [alertController addAction:circleAction];
    [alertController addAction:squareAction];
    [alertController addAction:zigzagAction];
    [alertController addAction:cancelAction];
    
    // Present the alert
    [self presentViewController:alertController animated:YES completion:nil];
}

// Create a circular path around the current location
- (void)createCirclePath {
    // Get current spoofed location
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    CLLocationCoordinate2D center = CLLocationCoordinate2DMake(
        [manager getSpoofedLatitude], 
        [manager getSpoofedLongitude]
    );
    
    // Create a circular path with 8 points
    double radius = 0.0005; // Approximately 50 meters
    NSMutableArray *waypoints = [NSMutableArray array];
    
    // Add center point first
    [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(center.latitude, center.longitude)]];
    
    // Add points around the circle
    for (int i = 0; i <= 8; i++) {
        double angle = (i * M_PI / 4); // 8 points around the circle
        double lat = center.latitude + radius * sin(angle);
        double lon = center.longitude + radius * cos(angle);
        [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(lat, lon)]];
    }
    
    // Return to center
    [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(center.latitude, center.longitude)]];
    
    // Store the waypoints for movement
    [self setPathWaypoints:waypoints];
    
    // Update UI
    self.pathStatusLabel.text = @"Status: Circular Path Created";
    self.pathStatusLabel.textColor = [UIColor systemGreenColor];
    
    // Update the start/stop button
    UIButton *startStopButton = [self.gpsAdvancedPanel viewWithTag:1002];
    [startStopButton setTitle:@"Start Movement" forState:UIControlStateNormal];
    [startStopButton setBackgroundColor:[UIColor systemGreenColor]];
}

// Create a zigzag path from the current location
- (void)createZigzagPath {
    // Get current spoofed location
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    CLLocationCoordinate2D start = CLLocationCoordinate2DMake(
        [manager getSpoofedLatitude], 
        [manager getSpoofedLongitude]
    );
    
    // Create a zigzag path
    double mainDistance = 0.002; // Approximately 200 meters
    double zigzagWidth = 0.0005; // Approximately 50 meters
    NSMutableArray *waypoints = [NSMutableArray array];
    
    // Add starting point
    [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(start.latitude, start.longitude)]];
    
    // Create zigzag pattern points (5 zigs)
    for (int i = 1; i <= 5; i++) {
        double progress = i / 5.0;
        
        // Right side point
        [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(
            start.latitude + (mainDistance * progress),
            start.longitude + zigzagWidth
        )]];
        
        // Left side point (if not the last one)
        if (i < 5) {
            double nextProgress = (i + 0.5) / 5.0;
            [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(
                start.latitude + (mainDistance * nextProgress),
                start.longitude - zigzagWidth
            )]];
        }
    }
    
    // Return to original longitude
    [waypoints addObject:[NSValue valueWithCGPoint:CGPointMake(
        start.latitude + mainDistance,
        start.longitude
    )]];
    
    // Store the waypoints for movement
    [self setPathWaypoints:waypoints];
    
    // Update UI
    self.pathStatusLabel.text = @"Status: Zigzag Path Created";
    self.pathStatusLabel.textColor = [UIColor systemGreenColor];
    
    // Update the start/stop button
    UIButton *startStopButton = [self.gpsAdvancedPanel viewWithTag:1002];
    [startStopButton setTitle:@"Start Movement" forState:UIControlStateNormal];
    [startStopButton setBackgroundColor:[UIColor systemGreenColor]];
}

// Remove static pin from map
- (void)removeStaticPinFromMap {
    NSString *js = @"if (typeof customPin !== 'undefined' && customPin) { customPin.setMap(null); customPin = null; }";
    [self.mapWebView evaluateJavaScript:js completionHandler:nil];
}

// Return YES if static pin exists in storage
- (BOOL)hasPinnedLocation {
    NSDictionary *loc = [[NSUserDefaults standardUserDefaults] objectForKey:@"PinnedLocation"];
    return (loc && loc[@"latitude"] && loc[@"longitude"]);
}

// Get pinned location dictionary
- (NSDictionary *)getPinnedLocation {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"PinnedLocation"];
}

// Start/Stop movement button handler
- (void)startStopMovementButtonTapped:(UIButton *)sender {
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    
    if ([manager isCurrentlyMoving]) {
        // Stop movement
        [manager stopMovementAlongPath];
        
        // Update UI
        self.pathStatusLabel.text = @"Status: Movement Stopped";
        self.pathStatusLabel.textColor = [UIColor systemOrangeColor];
        
        // Update button
        [sender setTitle:@"Start Movement" forState:UIControlStateNormal];
        [sender setBackgroundColor:[UIColor systemGreenColor]];
        // Persist stopped state
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:NO forKey:kPathMovementActiveKey];
        [defaults setInteger:0 forKey:kPathCurrentIndexKey];
        [defaults setDouble:0 forKey:kPathMovementSpeedKey];
        [defaults synchronize];
        // Restore pin/unpin UI
        [self updatePinUnpinVisibility];
    } else {
        // Get the waypoints
        NSArray *waypoints = [self getPathWaypoints];
        if (!waypoints || waypoints.count < 2) {
            // No valid path
            self.pathStatusLabel.text = @"Status: No valid path created";
            self.pathStatusLabel.textColor = [UIColor systemRedColor];
            return;
        }
        
        // Get the speed
        double speed = self.movementSpeedSlider.value;
        
        // Remove static pin from map and hide pin/unpin buttons
        [self removeStaticPinFromMap];
        self.pinButton.hidden = YES;
        self.unpinButton.hidden = YES;
        // Also hide pin/unpin labels
        UILabel *pinLabel = nil;
        UILabel *unpinLabel = nil;
        for (UIView *subview in self.unpinContainer.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                UILabel *label = (UILabel *)subview;
                if ([label.text isEqualToString:@"Pin"] || [label.text isEqualToString:@"Location marked"]) {
                    pinLabel = label;
                } else if ([label.text isEqualToString:@"Unpin"] || [label.text isEqualToString:@"Location unmarked"]) {
                    unpinLabel = label;
                }
            }
        }
        if (pinLabel) pinLabel.hidden = YES;
        if (unpinLabel) unpinLabel.hidden = YES;

        // Start movement
        [manager startMovementAlongPath:waypoints withSpeed:speed startIndex:0 completion:^(BOOL completed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.pathStatusLabel.text = @"Status: Movement Completed";
                self.pathStatusLabel.textColor = [UIColor systemGreenColor];
                // Update button
                [sender setTitle:@"Start Movement" forState:UIControlStateNormal];
                [sender setBackgroundColor:[UIColor systemGreenColor]];
                // Restore pin if static location exists
                if ([self hasPinnedLocation]) {
                    NSDictionary *loc = [self getPinnedLocation];
                    [self centerMapAndPlacePinAtLatitude:[loc[@"latitude"] doubleValue] longitude:[loc[@"longitude"] doubleValue] shouldTogglePinButton:YES];
                }
                // Clear movement state persistence
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setBool:NO forKey:kPathMovementActiveKey];
                [defaults setInteger:0 forKey:kPathCurrentIndexKey];
                [defaults setDouble:0 forKey:kPathMovementSpeedKey];
                [defaults synchronize];
                [self updatePinUnpinVisibility];
            });
        }];
        
        // Persist movement state
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:kPathMovementActiveKey];
        [defaults setInteger:0 forKey:kPathCurrentIndexKey];
        [defaults setDouble:speed forKey:kPathMovementSpeedKey];
        [defaults synchronize];
        
        // Update UI
        self.pathStatusLabel.text = @"Status: Moving...";
        self.pathStatusLabel.textColor = [UIColor systemBlueColor];
        
        // Update button
        [sender setTitle:@"Stop Movement" forState:UIControlStateNormal];
        [sender setBackgroundColor:[UIColor systemRedColor]];
        // Hide pin/unpin UI when movement starts
        [self updatePinUnpinVisibility];
    }
}

// Cleanup resources in dealloc
- (void)dealloc {
    // Invalidate the speed update timer
    if (self.speedUpdateTimer) {
        [self.speedUpdateTimer invalidate];
        self.speedUpdateTimer = nil;
    }
}

// Improved theme detection and handling
- (void)showGPSAdvancedPanel {
    if (self.gpsAdvancedPanel.hidden) {
        // Update UI for current theme before showing
        [self updateAdvancedPanelForCurrentTheme];
        
        // Show with animation
        self.gpsAdvancedPanel.transform = CGAffineTransformMakeScale(0.8, 0.8);
        self.gpsAdvancedPanel.alpha = 0;
        self.gpsAdvancedPanel.hidden = NO;
        
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.gpsAdvancedPanel.transform = CGAffineTransformIdentity;
            self.gpsAdvancedPanel.alpha = 1;
        } completion:nil];
        
        // Start speed update timer when panel shows
        if (!self.speedUpdateTimer) {
            self.speedUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 
                                                                     target:self 
                                                                   selector:@selector(updateSpeedDisplay) 
                                                                   userInfo:nil 
                                                                    repeats:YES];
            [self updateSpeedDisplay]; // Update immediately
        }
    }
}

// Add new method to update colors based on theme
- (void)updateAdvancedPanelForCurrentTheme {
    // Check if we're in dark mode
    BOOL isDarkMode = NO;
    
    if (@available(iOS 13.0, *)) {
        isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    } else {
        // For older iOS versions, check if it's night time (7PM-7AM)
        NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitHour fromDate:[NSDate date]];
        isDarkMode = (components.hour >= 19 || components.hour < 7);
    }
    
    // Update blur effect
    if ([self.gpsAdvancedPanel.subviews firstObject] && [[self.gpsAdvancedPanel.subviews firstObject] isKindOfClass:[UIVisualEffectView class]]) {
        UIVisualEffectView *blurView = (UIVisualEffectView *)[self.gpsAdvancedPanel.subviews firstObject];
        UIBlurEffect *newEffect = [UIBlurEffect effectWithStyle:isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleExtraLight];
        [blurView setEffect:newEffect];
    }
    
    // Update section background colors
    for (UIView *subview in [self findAllSubviewsOfClass:[UIView class] inView:self.gpsAdvancedPanel]) {
        if (subview.layer.cornerRadius == 12) {
            subview.backgroundColor = isDarkMode ? 
                [UIColor colorWithWhite:0.15 alpha:0.5] : 
                [UIColor colorWithWhite:0.95 alpha:0.7];
        }
    }
    
    // Update section title colors
    for (UILabel *label in [self findAllSubviewsOfClass:[UILabel class] inView:self.gpsAdvancedPanel]) {
        if ([label.font.fontName containsString:@"Semibold"] && label.font.pointSize == 14) {
            label.textColor = isDarkMode ? 
                [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0] : 
                [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:1.0];
        } else if (label != self.speedCourseLabel) {
            // Regular labels (excluding the speed/course data label)
            label.textColor = [UIColor labelColor];
        }
    }
    
    // Update border color
    self.gpsAdvancedPanel.layer.borderColor = [UIColor colorWithWhite:isDarkMode ? 0.5 : 0.8 alpha:0.3].CGColor;
    self.gpsAdvancedPanel.layer.shadowOpacity = isDarkMode ? 0.5 : 0.2;
}

// Helper method to find all subviews of a specific class
- (NSArray *)findAllSubviewsOfClass:(Class)class inView:(UIView *)view {
    NSMutableArray *results = [NSMutableArray array];
    
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:class]) {
            [results addObject:subview];
        }
        
        // Recursively search in subviews
        [results addObjectsFromArray:[self findAllSubviewsOfClass:class inView:subview]];
    }
    
    return results;
}

// Helper to update pin/unpin button and label visibility
- (void)updatePinUnpinVisibility {
    BOOL isMoving = [[LocationSpoofingManager sharedManager] isCurrentlyMoving];
    BOOL hasPin = [self hasPinnedLocation];
    UILabel *pinLabel = nil;
    UILabel *unpinLabel = nil;
    for (UIView *subview in self.unpinContainer.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"Pin"] || [label.text isEqualToString:@"Location marked"]) {
                pinLabel = label;
            } else if ([label.text isEqualToString:@"Unpin"] || [label.text isEqualToString:@"Location unmarked"]) {
                unpinLabel = label;
            }
        }
    }
    if (isMoving) {
        self.pinButton.hidden = YES;
        self.unpinButton.hidden = YES;
        if (pinLabel) pinLabel.hidden = YES;
        if (unpinLabel) unpinLabel.hidden = YES;
    } else if (hasPin) {
        self.pinButton.hidden = YES;
        self.unpinButton.hidden = NO;
        if (pinLabel) pinLabel.hidden = YES;
        if (unpinLabel) unpinLabel.hidden = NO;
    } else {
        self.pinButton.hidden = NO;
        self.unpinButton.hidden = YES;
        if (pinLabel) pinLabel.hidden = NO;
        if (unpinLabel) unpinLabel.hidden = YES;
    }
}

// Add this new method to load saved settings from NSUserDefaults
- (void)loadSavedAdvancedGPSSettings {

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Load transportation mode
    NSInteger transportationMode = [defaults integerForKey:kTransportationModeKey];
    if (transportationMode >= 0 && transportationMode <= 2) { // Valid range check
        self.transportationModeControl.selectedSegmentIndex = transportationMode;
        // Update the LocationSpoofingManager
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        [manager setTransportationMode:(TransportationMode)transportationMode];
    }
    
    // Load accuracy value
    float accuracyValue = [defaults floatForKey:kAccuracyValueKey];
    if (accuracyValue >= 5.0 && accuracyValue <= 15.0) { // Valid range check
        self.accuracySlider.value = accuracyValue;
        // Update the label
        UILabel *accuracyLabel = [self.gpsAdvancedPanel viewWithTag:1001];
        if (accuracyLabel) {
            accuracyLabel.text = [NSString stringWithFormat:@"GPS Accuracy: %.1fm", accuracyValue];
        }
        // Update the LocationSpoofingManager
        LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
        [manager setAccuracyValue:accuracyValue];
    }
    
    // Load saved settings for jitter
    BOOL jitterEnabled = [defaults boolForKey:kJitterEnabledKey];
    if (![defaults objectForKey:kJitterEnabledKey]) {
        jitterEnabled = YES; // Default to on if not saved before
    }
    self.jitterSwitch.on = jitterEnabled;
    // Update the LocationSpoofingManager
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    [manager setJitterEnabled:jitterEnabled];
    
    // Also set position variations to match jitter setting
    manager.positionVariationsEnabled = jitterEnabled;
    
    // Load movement speed
    float movementSpeed = [defaults floatForKey:kMovementSpeedKey];
    if (movementSpeed >= 1.0 && movementSpeed <= 20.0) { // Valid range check
        self.movementSpeedSlider.value = movementSpeed;
        // Update the label
        self.movementSpeedLabel.text = [NSString stringWithFormat:@"Path Speed: %.1f m/s", movementSpeed];
    }
}

// Add a method to kill enabled apps like during profile switching
- (void)terminateEnabledScopedApps {
    PXLog(@"[WeaponX] 🔄 Terminating enabled scoped apps after location pin state change");
    
    // Get the BottomButtons instance
    id bottomButtons = [NSClassFromString(@"BottomButtons") sharedInstance];
    if (!bottomButtons) {
        PXLog(@"[WeaponX] ⚠️ Could not get BottomButtons instance for app termination");
        return;
    }
    
    // Call killEnabledApps method to terminate all enabled apps
    SEL killEnabledAppsSel = NSSelectorFromString(@"killEnabledApps");
    if ([bottomButtons respondsToSelector:killEnabledAppsSel]) {
        PXLog(@"[WeaponX] 🔪 Calling BottomButtons.killEnabledApps to terminate enabled apps");
        
        // Use NSInvocation to avoid ARC issues with performSelector
        NSMethodSignature *signature = [bottomButtons methodSignatureForSelector:killEnabledAppsSel];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:bottomButtons];
        [invocation setSelector:killEnabledAppsSel];
        [invocation invoke];
        
        PXLog(@"[WeaponX] ✅ Successfully terminated enabled apps after location pin state change");
    } else {
        PXLog(@"[WeaponX] ❌ BottomButtons does not respond to killEnabledApps");
    }
}

// Show or update the pinned location circle on the map using Google Maps JavaScript overlay
- (void)showOrUpdatePinnedLocationCircleAtLatitude:(double)latitude longitude:(double)longitude {
    // Inject JavaScript to add or update a google.maps.Circle overlay at the pinned location
    NSString *script = [NSString stringWithFormat:@"(function() {\n"
        "  if (!window.pinnedLocationCircle) {\n"
        "    window.pinnedLocationCircle = new google.maps.Circle({\n"
        "      strokeColor: '#00b34d',\n"
        "      strokeOpacity: 0.8,\n"
        "      strokeWeight: 2,\n"
        "      fillColor: '#00b34d',\n"
        "      fillOpacity: 0.25,\n"
        "      map: map,\n"
        "      center: {lat: %f, lng: %f},\n"
        "      radius: 12\n"
        "    });\n"
        "  } else {\n"
        "    window.pinnedLocationCircle.setCenter({lat: %f, lng: %f});\n"
        "    window.pinnedLocationCircle.setMap(map);\n"
        "  }\n"
        "})();", latitude, longitude, latitude, longitude];
    [self.mapWebView evaluateJavaScript:script completionHandler:nil];
}

// Remove the pinned location circle overlay from the map
- (void)removePinnedLocationCircle {
    NSString *script = @"if (window.pinnedLocationCircle) { window.pinnedLocationCircle.setMap(null); }";
    [self.mapWebView evaluateJavaScript:script completionHandler:nil];
}

// Start monitoring for pinned location changes
- (void)startPinnedLocationMonitoring {
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                     target:self
                                   selector:@selector(checkPinnedLocationFromPlist)
                                   userInfo:nil
                                    repeats:YES];
}

// Check for pinned location from plist and update circle overlay if needed
- (void)checkPinnedLocationFromPlist {
    NSString *plistPath = [ROOT_PREFIX stringByAppendingPathComponent:@"com.weaponx.gpsspoofing.plist"];
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!settings) {
        // Remove circle if no settings file
        dispatch_async(dispatch_get_main_queue(), ^{
            [self removePinnedLocationCircle];
        });
        return;
    }
    NSDictionary *pinnedLocation = settings[@"PinnedLocation"];
    if (!pinnedLocation) {
        // Remove circle if no pinned location
        dispatch_async(dispatch_get_main_queue(), ^{
            [self removePinnedLocationCircle];
        });
        return;
    }
    double latitude = [pinnedLocation[@"latitude"] doubleValue];
    double longitude = [pinnedLocation[@"longitude"] doubleValue];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showOrUpdatePinnedLocationCircleAtLatitude:latitude longitude:longitude];
    });
}

// Setup pickup/drop button

@end
