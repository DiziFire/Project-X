#import "AccountViewController.h"
#import "TabBarController.h"
#import "APIManager.h"
#import "IdentifierManager.h"
#import "SignupViewController.h"
#import "TelegramManager.h"
#import "SupportViewController.h"
#import "DevicesViewController.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h> // For CAGradientLayer

// Add file caching helpers
#pragma mark - File Cache Helpers

// File path helpers
NSString* getDocumentsDirectory() {
    NSArray* dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [dirs firstObject];
}

NSString* getPaymentSettingsCachePath() {
    NSString* docsDir = getDocumentsDirectory();
    return [docsDir stringByAppendingPathComponent:@"payment_settings_cache.json"];
}

// Save payment settings to file
void savePaymentSettingsToFile(NSDictionary* settings) {
    if (!settings) return;
    
    NSString* cachePath = getPaymentSettingsCachePath();
    NSError* error;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:settings options:0 error:&error];
    
    if (error) {
        return;
    }
    
    [jsonData writeToFile:cachePath options:NSDataWritingAtomic error:&error];
    if (error) {
        // Error handling without logging
    }
}

// Load payment settings from file
NSDictionary* loadPaymentSettingsFromFile() {
    NSString* cachePath = getPaymentSettingsCachePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        return nil;
    }
    
    NSError* error;
    NSData* jsonData = [NSData dataWithContentsOfFile:cachePath options:0 error:&error];
    
    if (error) {
        return nil;
    }
    
    NSDictionary* settings = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (error) {
        return nil;
    }
    
    return settings;
}

@interface AccountViewController () <UITextFieldDelegate, UIScrollViewDelegate>

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *emailLabel;

@property (nonatomic, strong) NSDictionary *planData;
@property (nonatomic, assign) BOOL hasPlan;
@property (nonatomic, strong) UIImageView *profileImageView;

@property (nonatomic, strong) UILabel *systemVersionLabel;
@property (nonatomic, strong) UILabel *loginHeader;
@property (nonatomic, strong) UIButton *startSharingButton;
@property (nonatomic, strong) UITextField *apiUrlTextField;
@property (nonatomic, strong) UILabel *daysRemainingLabel;
@property (nonatomic, strong) UIButton *supportButton;
@property (nonatomic, assign) BOOL isGetPlanMode;
@property (nonatomic, assign) NSInteger planDaysRemaining;
@end

@implementation AccountViewController

// This attribute makes this function run very early, even if the main tweak disables hooks
__attribute__((constructor)) static void AccountViewDirectFix(void) {
    NSLog(@"[WeaponX-Emergency] 🔴 Starting AccountViewController button fix");
}

#pragma mark - UITextFieldDelegate Methods

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.emailField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
        
        // If it's the password field, try to login
        if (textField == self.passwordField) {
            [self loginButtonTapped];
        }
    }
    return YES;
}

- (void)dismissKeyboard
{
    [self.view endEditing:YES];
}

#pragma mark - Lifecycle Methods

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSLog(@"[WeaponX] AccountViewController viewDidLoad");
    
    // Setup navigation bar with system colors
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        UINavigationBar *navBar = self.navigationController.navigationBar;
        navBar.barTintColor = [UIColor systemBackgroundColor];
        navBar.backgroundColor = [UIColor systemBackgroundColor];
        
        // Use this appearance for better adaptivity to light/dark mode
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor systemBackgroundColor];
        navBar.standardAppearance = appearance;
        navBar.scrollEdgeAppearance = appearance;
    } else {
        // Fallback for iOS 12 and below
        self.view.backgroundColor = [UIColor blackColor];
    }
    
    // Explicitly enable user interaction on the main view
    self.view.userInteractionEnabled = YES;
    
    // Initialize properties
    self.isLoggingIn = NO;
    [self setLoggedIn:NO];
    self.isCheckingForUpdates = NO;
    self.isDownloadingUpdate = NO;
    
    // Set up connection status in navigation bar
    [self setupConnectionStatusLabel];
    
    // Set up UI components
    [self setupUI];
    
    // Schedule automatic update checks
    [self scheduleUpdateChecks];
    
    // Check for an existing auth token
    self.authToken = [[APIManager sharedManager] currentAuthToken];
    
    if (self.authToken) {
        NSLog(@"[WeaponX] Found existing auth token, checking validity");
        [self setLoggedIn:YES];
        [self updateUI];
        [self refreshUserData];
    } else {
        NSLog(@"[WeaponX] No auth token found, showing login UI");
        [self setLoggedIn:NO];
        [self updateUI];
    }
    
    // Start checking internet connectivity
    [self startConnectivityTimer];
    
    // Add observers for network status changes and UI refresh notifications
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleNetworkStatusChanged:) 
                                                 name:@"WeaponXNetworkStatusChanged" 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleNetworkBecameAvailable:) 
                                                 name:@"WeaponXNetworkBecameAvailable" 
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleRefreshUIRequired:) 
                                                 name:@"WeaponXUIRefreshRequired" 
                                               object:nil];
    
    // Create loadingIndicator property
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.center = self.view.center;
    [self.view addSubview:self.loadingIndicator];
    
    // Register for plan data updated notification
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handlePlanDataUpdated:) 
                                                 name:@"WeaponXPlanDataUpdated" 
                                               object:nil];
    
    // Load saved credentials if available
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *lastEmail = [defaults objectForKey:@"LastLoginEmail"];
    NSString *lastPassword = [defaults objectForKey:@"LastLoginPassword"];
    
    if (lastEmail) {
        self.emailField.text = lastEmail;
    }
    
    if (lastPassword) {
        self.passwordField.text = lastPassword;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // If user is logged in, refresh user data
    if (self.isLoggedIn) {
        [self refreshUserData];
    }
    
    // Update notification badges
    [self updateSupportButtonBadge];
    
    // Refresh the UI with latest data
    [self updateUIWithPlanData];
    
    // If we have network, refresh from server too
    APIManager *apiManager = [APIManager sharedManager];
    if ([apiManager isNetworkAvailable]) {
        [self refreshUIAfterNetworkChange];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Initialize plan button with loading text
    [self initializePlanButton];
    
    // No longer needed as we have new update buttons
    // [self setupUpdateIcon];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    if (@available(iOS 13.0, *)) {
        if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            // Update UI elements for the new appearance
            [self updateAppearance];
        }
    }
}

- (void)updateAppearance {
    if (@available(iOS 13.0, *)) {
        // Determine if we're in dark mode
        BOOL isDarkMode = (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
        
        // Update userInfoCard appearance
        if (isDarkMode) {
            // Dark mode styling with stronger neon effect
            self.userInfoCard.layer.borderColor = [UIColor systemGreenColor].CGColor;
            self.userInfoCard.layer.shadowColor = [UIColor systemGreenColor].CGColor;
            self.userInfoCard.layer.shadowOpacity = 0.6;
            
            // Replace blur effect with dark style
            for (UIView *subview in self.userInfoCard.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                    UIVisualEffectView *blurView = (UIVisualEffectView *)subview;
                    blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
                    blurView.alpha = 0.85;
                }
            }
        } else {
            // Light mode styling with softer effect
            self.userInfoCard.layer.borderColor = [UIColor systemGreenColor].CGColor;
            self.userInfoCard.layer.shadowColor = [UIColor systemGreenColor].CGColor;
            self.userInfoCard.layer.shadowOpacity = 0.4;
            
            // Replace blur effect with light style
            for (UIView *subview in self.userInfoCard.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                    UIVisualEffectView *blurView = (UIVisualEffectView *)subview;
                    blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
                    blurView.alpha = 0.85;
                }
            }
        }
        
        // Update loginView appearance
        if (isDarkMode) {
            // Dark mode styling
            self.loginView.layer.borderColor = [UIColor systemGreenColor].CGColor;
            self.loginView.layer.shadowColor = [UIColor systemGreenColor].CGColor;
            
            // Replace blur effect with dark style
            for (UIView *subview in self.loginView.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                    UIVisualEffectView *blurView = (UIVisualEffectView *)subview;
                    blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
                }
            }
        } else {
            // Light mode styling
            self.loginView.layer.borderColor = [UIColor systemGreenColor].CGColor;
            self.loginView.layer.shadowColor = [UIColor systemGreenColor].CGColor;
            
            // Replace blur effect with light style
            for (UIView *subview in self.loginView.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                    UIVisualEffectView *blurView = (UIVisualEffectView *)subview;
                    blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
                }
            }
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}

- (void)dealloc {
    // Remove notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Keep the trait collection observer removal
    if (@available(iOS 13.0, *)) {
        [self.traitCollection removeObserver:self forKeyPath:@"userInterfaceStyle"];
    }
    
    // Stop connectivity timer
    [self stopConnectivityTimer];
}

#pragma mark - Internet Connectivity

- (void)setupConnectionStatusLabel {
    // Create the connection status label
    self.connectionStatusLabel = [[UILabel alloc] init];
    self.connectionStatusLabel.text = @"checking internet connection...";
    
    // Apply styling
    if (@available(iOS 13.0, *)) {
        self.connectionStatusLabel.textColor = [UIColor systemRedColor]; // Start with red color
    } else {
        self.connectionStatusLabel.textColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
    }
    
    self.connectionStatusLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    
    // Size the label correctly
    [self.connectionStatusLabel sizeToFit];
    
    // Add padding
    CGRect frame = self.connectionStatusLabel.frame;
    frame.size.width += 20;
    self.connectionStatusLabel.frame = frame;
    
    // Create a bar button item with the label
    UIBarButtonItem *statusBarButton = [[UIBarButtonItem alloc] initWithCustomView:self.connectionStatusLabel];
    
    // Set as left bar button item
    self.navigationItem.leftBarButtonItem = statusBarButton;
}

- (void)startConnectivityTimer {
    // Invalidate any existing timer
    [self stopConnectivityTimer];
    
    // Create a new timer that fires every 5 seconds
    self.connectivityTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                             target:self
                                                           selector:@selector(checkInternetConnectivity)
                                                           userInfo:nil
                                                            repeats:YES];
    
    // Fire immediately for first check
    [self checkInternetConnectivity];
}

- (void)stopConnectivityTimer {
    if (self.connectivityTimer) {
        [self.connectivityTimer invalidate];
        self.connectivityTimer = nil;
    }
    
    // Cancel any ongoing connectivity task
    if (self.connectivityTask) {
        [self.connectivityTask cancel];
        self.connectivityTask = nil;
    }
}

- (void)checkInternetConnectivity {
    // Cancel any existing task
    if (self.connectivityTask) {
        [self.connectivityTask cancel];
    }
    
    // Get base URL from API Manager
    NSString *baseURL = nil;
    @try {
        baseURL = [[APIManager sharedManager] baseURL];
    } @catch (NSException *exception) {
        [self updateConnectionStatusWithState:NO pingTime:0];
        return;
    }
    
    if (!baseURL) {
        [self updateConnectionStatusWithState:NO pingTime:0];
        return;
    }
    
    // Create a URL for connectivity check
    NSURL *url = [NSURL URLWithString:baseURL];
    if (!url) {
        [self updateConnectionStatusWithState:NO pingTime:0];
        return;
    }
    
    // Record start time for ping calculation
    NSDate *startTime = [NSDate date];
    self.lastPingTime = 0;
    
    // Create and start request
    NSURLRequest *request = [NSURLRequest requestWithURL:url 
                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                        timeoutInterval:4.0];
    
    // Use a weak reference to self to avoid retain cycles
    __weak typeof(self) weakSelf = self;
    
    self.connectivityTask = [[NSURLSession sharedSession] dataTaskWithRequest:request 
                                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Calculate ping time
        NSTimeInterval pingTime = [[NSDate date] timeIntervalSinceDate:startTime] * 1000; // Convert to milliseconds
        
        // Get back to main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            if (error) {
                [strongSelf updateConnectionStatusWithState:NO pingTime:0];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                [strongSelf updateConnectionStatusWithState:YES pingTime:pingTime];
            } else {
                [strongSelf updateConnectionStatusWithState:NO pingTime:0];
            }
        });
    }];
    
    [self.connectivityTask resume];
}

- (void)updateConnectionStatusWithState:(BOOL)isConnected pingTime:(NSTimeInterval)pingTime {
    // Store the ping time
    self.lastPingTime = pingTime;
    
    // Update label text based on connection state
    if (isConnected) {
        // Check if ping is high (poor connection)
        if (pingTime > 1500) {
            self.connectionStatusLabel.text = [NSString stringWithFormat:@"Connected: %.0f ms (Poor Connection)", pingTime];
            
            // Set text color to yellow/orange for poor connection
            if (@available(iOS 13.0, *)) {
                self.connectionStatusLabel.textColor = [UIColor systemYellowColor];
            } else {
                self.connectionStatusLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
            }
        } else {
            // Normal good connection
            self.connectionStatusLabel.text = [NSString stringWithFormat:@"Connected: %.0f ms", pingTime];
            
            // Set text color to green for connected state
            if (@available(iOS 13.0, *)) {
                self.connectionStatusLabel.textColor = [UIColor systemGreenColor];
            } else {
                self.connectionStatusLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:1.0];
            }
        }
        
        // Use standard font size for connected status
        self.connectionStatusLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    } else {
        self.connectionStatusLabel.text = @"Offline: Use internet for accessing account info";
        
        // Set text color to red for offline state
        if (@available(iOS 13.0, *)) {
            self.connectionStatusLabel.textColor = [UIColor systemRedColor];
        } else {
            self.connectionStatusLabel.textColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
        }
        
        // Use smaller font size for offline status message
        self.connectionStatusLabel.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont systemFontOfSize:11.0];
    }
    
    // Resize label to fit new text
    [self.connectionStatusLabel sizeToFit];
    
    // Add padding
    CGRect frame = self.connectionStatusLabel.frame;
    frame.size.width += 20;
    self.connectionStatusLabel.frame = frame;
}

#pragma mark - UI Setup

- (void)setupUI {
    // Setup scroll view for content
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Hide vertical scroll indicator (removes the scrollbar line when scrolling)
    self.scrollView.showsVerticalScrollIndicator = NO;
    
    // Explicitly enable user interaction
    self.scrollView.userInteractionEnabled = YES;
    
    // Configure scroll view appearance based on iOS version
    if (@available(iOS 13.0, *)) {
        self.scrollView.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.scrollView.backgroundColor = [UIColor whiteColor];
    }
    
    [self.view addSubview:self.scrollView];
    
    // Add refresh control for pull to refresh with custom styling
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    
    // Customize refresh control with dynamic styling
    if (@available(iOS 13.0, *)) {
        self.refreshControl.tintColor = [UIColor systemGreenColor];
        NSAttributedString *refreshText = [[NSAttributedString alloc] 
                                        initWithString:@"SYNCING DATA..." 
                                        attributes:@{NSForegroundColorAttributeName: [UIColor systemGreenColor],
                                                    NSFontAttributeName: [UIFont fontWithName:@"Menlo-Bold" size:12.0] ?: [UIFont boldSystemFontOfSize:12.0]}];
        self.refreshControl.attributedTitle = refreshText;
    } else {
        self.refreshControl.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    NSAttributedString *refreshText = [[NSAttributedString alloc] 
                                      initWithString:@"SYNCING DATA..." 
                                      attributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0],
                                                  NSFontAttributeName: [UIFont fontWithName:@"Menlo-Bold" size:12.0] ?: [UIFont boldSystemFontOfSize:12.0]}];
    self.refreshControl.attributedTitle = refreshText;
    }
    
    [self.scrollView addSubview:self.refreshControl];
    
    // Content view for scroll view
    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        self.contentView.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.contentView.backgroundColor = [UIColor whiteColor];
    }
    [self.scrollView addSubview:self.contentView];
    
    // Setup login view
    [self setupLoginView];
    
    // Setup user info card
    [self setupUserInfoCard];
    
    // Activity indicator with themed color
    if (@available(iOS 13.0, *)) {
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        self.activityIndicator.color = [UIColor systemGreenColor];
    } else {
        // Use the appropriate style for iOS 12 and below
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        #pragma clang diagnostic pop
        self.activityIndicator.color = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    }
    
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Scroll view
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        // Content view
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        // Fix: Make contentView always as tall as the bottom of its last subview (loginView or userInfoCard)
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.loginView.bottomAnchor],
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.userInfoCard.bottomAnchor],
        
        // Activity indicator
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)setupLoginView {
    // Login view container with adaptive style
    self.loginView = [[UIView alloc] init];
    self.loginView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginView.layer.cornerRadius = 8.0;
    self.loginView.layer.borderWidth = 1.0;
    
    // Explicitly enable user interaction
    self.loginView.userInteractionEnabled = YES;
    
    // Add gesture recognizer to diagnose touch issues
    UITapGestureRecognizer *loginViewTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(loginViewTapped:)];
    loginViewTapGesture.cancelsTouchesInView = NO;
    [self.loginView addGestureRecognizer:loginViewTapGesture];
    
    UIColor *primaryColor;
    UIColor *textColor;
    UIColor *backgroundColor;
    UIColor *containerBackgroundColor;
    
    if (@available(iOS 13.0, *)) {
        primaryColor = [UIColor systemGreenColor];
        textColor = [UIColor labelColor];
        backgroundColor = [UIColor secondarySystemBackgroundColor];
        containerBackgroundColor = [UIColor tertiarySystemBackgroundColor];
        
        self.loginView.layer.borderColor = [UIColor systemGreenColor].CGColor;
        self.loginView.layer.shadowColor = [UIColor systemGreenColor].CGColor;
        self.loginView.backgroundColor = backgroundColor;
    } else {
        primaryColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
        textColor = [UIColor blackColor];
        backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        containerBackgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        
        self.loginView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.6].CGColor;
        self.loginView.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8].CGColor;
        self.loginView.backgroundColor = backgroundColor;
    }
    
    self.loginView.layer.shadowOffset = CGSizeMake(0, 0);
    self.loginView.layer.shadowRadius = 10.0;
    self.loginView.layer.shadowOpacity = 0.5;
    [self.contentView addSubview:self.loginView];
    
    // App logo/icon with themed color
    UIImageView *logoImageView = [[UIImageView alloc] init];
    logoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    logoImageView.contentMode = UIViewContentModeScaleAspectFit;
    logoImageView.image = [UIImage imageNamed:@"AppIcon"];
    if (!logoImageView.image) {
        // Fallback to a system icon
        logoImageView.image = [UIImage systemImageNamed:@"lock.shield"];
        logoImageView.tintColor = primaryColor;
    }
    [self.loginView addSubview:logoImageView];
    
    // Login title with adaptive styling
    UILabel *loginTitle = [[UILabel alloc] init];
    loginTitle.text = @">> WEAPON X ACCESS";
    loginTitle.font = [UIFont fontWithName:@"Menlo-Bold" size:22.0] ?: [UIFont boldSystemFontOfSize:22.0];
    loginTitle.textAlignment = NSTextAlignmentCenter;
    loginTitle.textColor = primaryColor;
    loginTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginView addSubview:loginTitle];
    
    // Login subtitle with adaptive styling
    UILabel *loginSubtitle = [[UILabel alloc] init];
    loginSubtitle.text = @"AUTHORIZATION REQUIRED";
    loginSubtitle.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    if (@available(iOS 13.0, *)) {
        loginSubtitle.textColor = [UIColor secondaryLabelColor];
    } else {
        loginSubtitle.textColor = [UIColor darkGrayColor];
    }
    loginSubtitle.textAlignment = NSTextAlignmentCenter;
    loginSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginView addSubview:loginSubtitle];
    
    // Email field container with adaptive styling
    UIView *emailContainer = [[UIView alloc] init];
    emailContainer.translatesAutoresizingMaskIntoConstraints = NO;
    emailContainer.backgroundColor = containerBackgroundColor;
    emailContainer.layer.cornerRadius = 6.0;
    emailContainer.layer.borderWidth = 1.0;
    emailContainer.layer.borderColor = primaryColor.CGColor;
    [self.loginView addSubview:emailContainer];
    
    // Email icon with themed color
    UIImageView *emailIcon = [[UIImageView alloc] init];
    emailIcon.translatesAutoresizingMaskIntoConstraints = NO;
    emailIcon.contentMode = UIViewContentModeScaleAspectFit;
    emailIcon.image = [UIImage systemImageNamed:@"envelope"];
    emailIcon.tintColor = primaryColor;
    [emailContainer addSubview:emailIcon];
    
    // Email field with adaptive styling
    self.emailField = [[UITextField alloc] init];
    self.emailField.placeholder = @"Email ID";
    
    if (@available(iOS 13.0, *)) {
    self.emailField.attributedPlaceholder = [[NSAttributedString alloc] 
                                           initWithString:@"Email ID" 
                                               attributes:@{NSForegroundColorAttributeName: [UIColor placeholderTextColor]}];
        self.emailField.textColor = [UIColor labelColor];
    } else {
        self.emailField.attributedPlaceholder = [[NSAttributedString alloc] 
                                               initWithString:@"Email ID" 
                                               attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
        self.emailField.textColor = textColor;
    }
    
    self.emailField.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    
    if (@available(iOS 13.0, *)) {
        // Use automatic keyboard appearance based on system mode
        self.emailField.keyboardAppearance = UIKeyboardAppearanceDefault;
    } else {
        self.emailField.keyboardAppearance = UIKeyboardAppearanceDefault;
    }
    
    self.emailField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.emailField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.emailField.borderStyle = UITextBorderStyleNone;
    self.emailField.backgroundColor = [UIColor clearColor];
    self.emailField.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailField.delegate = self;
    self.emailField.returnKeyType = UIReturnKeyNext;
    [emailContainer addSubview:self.emailField];
    
    // Password field container with adaptive styling
    UIView *passwordContainer = [[UIView alloc] init];
    passwordContainer.translatesAutoresizingMaskIntoConstraints = NO;
    passwordContainer.backgroundColor = containerBackgroundColor;
    passwordContainer.layer.cornerRadius = 6.0;
    passwordContainer.layer.borderWidth = 1.0;
    passwordContainer.layer.borderColor = primaryColor.CGColor;
    [self.loginView addSubview:passwordContainer];
    
    // Password icon with themed color
    UIImageView *passwordIcon = [[UIImageView alloc] init];
    passwordIcon.translatesAutoresizingMaskIntoConstraints = NO;
    passwordIcon.contentMode = UIViewContentModeScaleAspectFit;
    passwordIcon.image = [UIImage systemImageNamed:@"lock"];
    passwordIcon.tintColor = primaryColor;
    [passwordContainer addSubview:passwordIcon];
    
    // Password field with adaptive styling
    self.passwordField = [[UITextField alloc] init];
    self.passwordField.placeholder = @"Passkey";
    
    if (@available(iOS 13.0, *)) {
    self.passwordField.attributedPlaceholder = [[NSAttributedString alloc] 
                                              initWithString:@"Passkey" 
                                                 attributes:@{NSForegroundColorAttributeName: [UIColor placeholderTextColor]}];
        self.passwordField.textColor = [UIColor labelColor];
    } else {
        self.passwordField.attributedPlaceholder = [[NSAttributedString alloc] 
                                                 initWithString:@"Passkey" 
                                                 attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
        self.passwordField.textColor = textColor;
    }
    
    self.passwordField.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.passwordField.secureTextEntry = YES;
    self.passwordField.keyboardAppearance = UIKeyboardAppearanceDefault;
    self.passwordField.borderStyle = UITextBorderStyleNone;
    self.passwordField.backgroundColor = [UIColor clearColor];
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordField.delegate = self;
    self.passwordField.returnKeyType = UIReturnKeyDone;
    [passwordContainer addSubview:self.passwordField];
    
    // Login button with adaptive style
    self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.loginButton setTitle:@"ACCESS SYSTEM" forState:UIControlStateNormal];
    [self.loginButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.loginButton.backgroundColor = primaryColor;
    self.loginButton.layer.cornerRadius = 6.0;
    self.loginButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16.0] ?: [UIFont boldSystemFontOfSize:16.0];
    self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.loginButton.clipsToBounds = NO;
    self.loginButton.layer.shadowColor = primaryColor.CGColor;
    self.loginButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.loginButton.layer.shadowRadius = 8.0;
    self.loginButton.layer.shadowOpacity = 0.8;
    
    // Ensure user interaction is explicitly enabled
    self.loginButton.userInteractionEnabled = YES;
    
    // Add direct tap gesture recognizer as a fallback
    UITapGestureRecognizer *loginButtonTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(loginButtonDirectTap:)];
    [self.loginButton addGestureRecognizer:loginButtonTapGesture];
    
    // Add debug logging for touch events
    [self.loginButton addTarget:self action:@selector(loginButtonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.loginButton addTarget:self action:@selector(loginButtonTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self.loginButton addTarget:self action:@selector(loginButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Add debug logging to the button tap
    NSLog(@"[WeaponX] Setting up ACCESS SYSTEM button in AccountViewController");
    
    [self.loginView addSubview:self.loginButton];
    
    // Signup button with adaptive style
    self.signupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.signupButton setTitle:@"REGISTER NEW IDENTITY" forState:UIControlStateNormal];
    [self.signupButton setTitleColor:primaryColor forState:UIControlStateNormal];
    self.signupButton.titleLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont systemFontOfSize:12.0];
    self.signupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.signupButton addTarget:self action:@selector(signupButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.loginView addSubview:self.signupButton];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Login view
        [self.loginView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20],
        [self.loginView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.loginView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        
        // Logo
        [logoImageView.topAnchor constraintEqualToAnchor:self.loginView.topAnchor constant:30],
        [logoImageView.centerXAnchor constraintEqualToAnchor:self.loginView.centerXAnchor],
        [logoImageView.widthAnchor constraintEqualToConstant:80],
        [logoImageView.heightAnchor constraintEqualToConstant:80],
        
        // Login title
        [loginTitle.topAnchor constraintEqualToAnchor:logoImageView.bottomAnchor constant:20],
        [loginTitle.leadingAnchor constraintEqualToAnchor:self.loginView.leadingAnchor constant:20],
        [loginTitle.trailingAnchor constraintEqualToAnchor:self.loginView.trailingAnchor constant:-20],
        
        // Login subtitle
        [loginSubtitle.topAnchor constraintEqualToAnchor:loginTitle.bottomAnchor constant:8],
        [loginSubtitle.leadingAnchor constraintEqualToAnchor:self.loginView.leadingAnchor constant:20],
        [loginSubtitle.trailingAnchor constraintEqualToAnchor:self.loginView.trailingAnchor constant:-20],
        
        // Email container
        [emailContainer.topAnchor constraintEqualToAnchor:loginSubtitle.bottomAnchor constant:30],
        [emailContainer.leadingAnchor constraintEqualToAnchor:self.loginView.leadingAnchor constant:20],
        [emailContainer.trailingAnchor constraintEqualToAnchor:self.loginView.trailingAnchor constant:-20],
        [emailContainer.heightAnchor constraintEqualToConstant:50],
        
        // Email icon
        [emailIcon.leadingAnchor constraintEqualToAnchor:emailContainer.leadingAnchor constant:15],
        [emailIcon.centerYAnchor constraintEqualToAnchor:emailContainer.centerYAnchor],
        [emailIcon.widthAnchor constraintEqualToConstant:20],
        [emailIcon.heightAnchor constraintEqualToConstant:20],
        
        // Email field
        [self.emailField.leadingAnchor constraintEqualToAnchor:emailIcon.trailingAnchor constant:10],
        [self.emailField.trailingAnchor constraintEqualToAnchor:emailContainer.trailingAnchor constant:-15],
        [self.emailField.topAnchor constraintEqualToAnchor:emailContainer.topAnchor],
        [self.emailField.bottomAnchor constraintEqualToAnchor:emailContainer.bottomAnchor],
        
        // Password container
        [passwordContainer.topAnchor constraintEqualToAnchor:emailContainer.bottomAnchor constant:15],
        [passwordContainer.leadingAnchor constraintEqualToAnchor:self.loginView.leadingAnchor constant:20],
        [passwordContainer.trailingAnchor constraintEqualToAnchor:self.loginView.trailingAnchor constant:-20],
        [passwordContainer.heightAnchor constraintEqualToConstant:50],
        
        // Password icon
        [passwordIcon.leadingAnchor constraintEqualToAnchor:passwordContainer.leadingAnchor constant:15],
        [passwordIcon.centerYAnchor constraintEqualToAnchor:passwordContainer.centerYAnchor],
        [passwordIcon.widthAnchor constraintEqualToConstant:20],
        [passwordIcon.heightAnchor constraintEqualToConstant:20],
        
        // Password field
        [self.passwordField.leadingAnchor constraintEqualToAnchor:passwordIcon.trailingAnchor constant:10],
        [self.passwordField.trailingAnchor constraintEqualToAnchor:passwordContainer.trailingAnchor constant:-15],
        [self.passwordField.topAnchor constraintEqualToAnchor:passwordContainer.topAnchor],
        [self.passwordField.bottomAnchor constraintEqualToAnchor:passwordContainer.bottomAnchor],
        
        // Login button
        [self.loginButton.topAnchor constraintEqualToAnchor:passwordContainer.bottomAnchor constant:25],
        [self.loginButton.leadingAnchor constraintEqualToAnchor:self.loginView.leadingAnchor constant:20],
        [self.loginButton.trailingAnchor constraintEqualToAnchor:self.loginView.trailingAnchor constant:-20],
        [self.loginButton.heightAnchor constraintEqualToConstant:50],
        
        // Signup button
        [self.signupButton.topAnchor constraintEqualToAnchor:self.loginButton.bottomAnchor constant:15],
        [self.signupButton.centerXAnchor constraintEqualToAnchor:self.loginView.centerXAnchor],
        [self.signupButton.bottomAnchor constraintEqualToAnchor:self.loginView.bottomAnchor constant:-20]
    ]];
}

- (void)setupUserInfoCard {
    // Clean up any existing views (in case this gets called multiple times)
    for (UIView *view in [self.userInfoCard subviews]) {
        [view removeFromSuperview];
    }
    
    // Create user info card - dark theme with terminal-like appearance
    self.userInfoCard = [[UIView alloc] init];
    self.userInfoCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.userInfoCard.layer.cornerRadius = 8.0; // Sharper corners for terminal look
    self.userInfoCard.clipsToBounds = YES;
    
    // Background with appropriate color for both light and dark modes
    if (@available(iOS 13.0, *)) {
        self.userInfoCard.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.09 green:0.09 blue:0.09 alpha:1.0]; // Very dark gray for dark mode
            } else {
                return [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0]; // Light gray for light mode
            }
        }];
    } else {
        self.userInfoCard.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.09 alpha:1.0]; // Default dark gray
    }
    
    // Terminal styling for border and shadow
    self.userInfoCard.layer.borderWidth = 1.0;
    
    if (@available(iOS 13.0, *)) {
        // Dynamic color for border
        self.userInfoCard.layer.borderColor = [UIColor systemGreenColor].CGColor;
        self.userInfoCard.layer.shadowColor = [UIColor systemGreenColor].CGColor; 
    } else {
        // Static color for older iOS
        self.userInfoCard.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.6].CGColor;
        self.userInfoCard.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.6].CGColor;
    }
    
    self.userInfoCard.layer.shadowOffset = CGSizeMake(0, 4);
    self.userInfoCard.layer.shadowOpacity = 0.5;
    self.userInfoCard.layer.shadowRadius = 8.0;
    
    [self.contentView addSubview:self.userInfoCard];
    
    // Remove the terminal-like header bar with user@weaponX text
    
    // Instagram-style top section with avatar on left, info on right
    
    // User avatar - now positioned on the left
    self.profileImageView = [[UIImageView alloc] init];
    self.profileImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.profileImageView.clipsToBounds = YES;
    self.profileImageView.layer.cornerRadius = 40; // Slightly smaller avatar
    self.profileImageView.layer.borderWidth = 2.0;
    
    // Set border color - same for both light and dark mode
    self.profileImageView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
    
    // Create the initial avatar
    [self createHackerAvatar];
    
    // Add to view hierarchy
    [self.userInfoCard addSubview:self.profileImageView];
    
    // Username label (larger, positioned to right of avatar)
    self.usernameLabel = [[UILabel alloc] init];
    self.usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.usernameLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:24.0] ?: [UIFont boldSystemFontOfSize:24.0]; // Larger, more prominent
    self.usernameLabel.textAlignment = NSTextAlignmentLeft;
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        self.usernameLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Bright green for dark mode
            } else {
                return [UIColor colorWithRed:0.0 green:0.6 blue:0.3 alpha:1.0]; // Darker green for light mode
            }
        }];
    } else {
        self.usernameLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Default bright green
    }
    
    [self.userInfoCard addSubview:self.usernameLabel];
    
    // User ID label (right under username)
    self.userIdLabel = [[UILabel alloc] init];
    self.userIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.userIdLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.userIdLabel.textAlignment = NSTextAlignmentLeft;
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        self.userIdLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.userIdLabel.textColor = [UIColor lightGrayColor];
    }
    
    [self.userInfoCard addSubview:self.userIdLabel];
    
    // Days Remaining Countdown Label (between ID and divider)
    self.daysRemainingLabel = [[UILabel alloc] init];
    self.daysRemainingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.daysRemainingLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:15.0] ?: [UIFont boldSystemFontOfSize:15.0];
    self.daysRemainingLabel.textAlignment = NSTextAlignmentCenter;
    self.daysRemainingLabel.layer.cornerRadius = 8.0;
    self.daysRemainingLabel.layer.masksToBounds = NO; // Need to set to NO to see shadow
    self.daysRemainingLabel.layer.borderWidth = 1.0;
    self.daysRemainingLabel.text = @""; // Will be set in updatePlanCountdown
    self.daysRemainingLabel.alpha = 0.0; // Start hidden, will fade in
    self.daysRemainingLabel.userInteractionEnabled = YES; // Enable user interaction for tap
    
    // Add tap gesture recognizer to make it tappable
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(daysRemainingLabelTapped)];
    [self.daysRemainingLabel addGestureRecognizer:tapGesture];
    
    // Create shadow effect for the glowing appearance
    self.daysRemainingLabel.layer.shadowOffset = CGSizeZero;
    self.daysRemainingLabel.layer.shadowRadius = 8.0;
    self.daysRemainingLabel.layer.shadowOpacity = 0.8;
    
    // Dynamic colors for light/dark mode
    if (@available(iOS 13.0, *)) {
        // Text color
        self.daysRemainingLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.0 green:0.95 blue:0.4 alpha:1.0]; // Brighter green for dark mode
            } else {
                return [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:1.0]; // Darker green for light mode
            }
        }];
        
        // Background color
        self.daysRemainingLabel.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.05 green:0.15 blue:0.05 alpha:0.6]; // Dark semi-transparent for dark mode
            } else {
                return [UIColor colorWithRed:0.9 green:1.0 blue:0.9 alpha:0.2]; // Light semi-transparent for light mode
            }
        }];
        
        // Use system green for border and shadow - it adapts automatically
        self.daysRemainingLabel.layer.borderColor = [UIColor systemGreenColor].CGColor;
        self.daysRemainingLabel.layer.shadowColor = [UIColor systemGreenColor].CGColor;
    } else {
        // Default colors for older iOS
        self.daysRemainingLabel.textColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.4 alpha:1.0];
        self.daysRemainingLabel.backgroundColor = [UIColor colorWithRed:0.05 green:0.15 blue:0.05 alpha:0.6];
        self.daysRemainingLabel.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.6].CGColor;
        self.daysRemainingLabel.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8].CGColor;
    }
    
    [self.userInfoCard addSubview:self.daysRemainingLabel];
    
    // Divider line with terminal style
    UIView *dividerLine = [[UIView alloc] init];
    dividerLine.translatesAutoresizingMaskIntoConstraints = NO;
    dividerLine.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.3]; // Subtle green line
    
    [self.userInfoCard addSubview:dividerLine];
    
    // Email section (below the divider)
    UILabel *emailTitleLabel = [[UILabel alloc] init];
    emailTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    emailTitleLabel.text = @"EMAIL";
    emailTitleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0];
    emailTitleLabel.textAlignment = NSTextAlignmentLeft;
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        emailTitleLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Bright green for dark mode
            } else {
                return [UIColor colorWithRed:0.0 green:0.6 blue:0.3 alpha:1.0]; // Darker green for light mode
            }
        }];
    } else {
        emailTitleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Default bright green
    }
    
    [self.userInfoCard addSubview:emailTitleLabel];
    
    self.emailValueLabel = [[UILabel alloc] init];
    self.emailValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailValueLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.emailValueLabel.textAlignment = NSTextAlignmentLeft;
    
    // Dynamic color based on interface style instead of fixed white
    if (@available(iOS 13.0, *)) {
        self.emailValueLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor whiteColor]; // White text for dark mode
            } else {
                return [UIColor blackColor]; // Black text for light mode
            }
        }];
    } else {
        self.emailValueLabel.textColor = [UIColor whiteColor];
    }
    
    [self.userInfoCard addSubview:self.emailValueLabel];
    
    // Plan section
    UILabel *planTitleLabel = [[UILabel alloc] init];
    planTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    planTitleLabel.text = @"PLAN";
    planTitleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0];
    planTitleLabel.textAlignment = NSTextAlignmentLeft;
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        planTitleLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Bright green for dark mode
            } else {
                return [UIColor colorWithRed:0.0 green:0.6 blue:0.3 alpha:1.0]; // Darker green for light mode
            }
        }];
    } else {
        planTitleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Default bright green
    }
    
    [self.userInfoCard addSubview:planTitleLabel];
    
    self.planValueLabel = [[UILabel alloc] init];
    self.planValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.planValueLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.planValueLabel.textAlignment = NSTextAlignmentLeft;
    
    // Dynamic color based on interface style instead of fixed white
    if (@available(iOS 13.0, *)) {
        self.planValueLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor whiteColor]; // White text for dark mode
            } else {
                return [UIColor blackColor]; // Black text for light mode
            }
        }];
    } else {
        self.planValueLabel.textColor = [UIColor whiteColor];
    }
    
    [self.userInfoCard addSubview:self.planValueLabel];
    
    // Plan expiry label
    self.planExpiryLabel = [[UILabel alloc] init];
    self.planExpiryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.planExpiryLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont systemFontOfSize:12.0];
    self.planExpiryLabel.textAlignment = NSTextAlignmentLeft;
    
    if (@available(iOS 13.0, *)) {
        self.planExpiryLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.planExpiryLabel.textColor = [UIColor grayColor];
    }
    
    [self.userInfoCard addSubview:self.planExpiryLabel];
    
    // System section
    UILabel *systemTitleLabel = [[UILabel alloc] init];
    systemTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    systemTitleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0];
    systemTitleLabel.text = @"SYSTEM";
    systemTitleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Same green color as other section titles
    [self.userInfoCard addSubview:systemTitleLabel];
    
    self.systemValueLabel = [[UILabel alloc] init];
    self.systemValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.systemValueLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.systemValueLabel.textColor = [UIColor lightGrayColor];
    self.systemValueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.systemValueLabel.text = [NSString stringWithFormat:@"[SYS] iOS %@ | %@", [[UIDevice currentDevice] systemVersion], [UIDevice currentDevice].model];
    [self.userInfoCard addSubview:self.systemValueLabel];
    
    // Device Limit section
    self.deviceLimitTitleLabel = [[UILabel alloc] init];
    self.deviceLimitTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceLimitTitleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0];
    self.deviceLimitTitleLabel.text = @"DEVICES";
    self.deviceLimitTitleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Same green color as other section titles
    [self.userInfoCard addSubview:self.deviceLimitTitleLabel];
    
    self.deviceLimitValueLabel = [[UILabel alloc] init];
    self.deviceLimitValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceLimitValueLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.deviceLimitValueLabel.textColor = [UIColor lightGrayColor];
    self.deviceLimitValueLabel.text = @"Loading...";
    [self.userInfoCard addSubview:self.deviceLimitValueLabel];
    
    // Device Icon
    self.deviceIconImageView = [[UIImageView alloc] init];
    self.deviceIconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceIconImageView.contentMode = UIViewContentModeScaleAspectFit;
    // Create a device icon programmatically
    UIImage *deviceIcon = [self createDeviceIcon];
    self.deviceIconImageView.image = deviceIcon;
    self.deviceIconImageView.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Green tint
    [self.userInfoCard addSubview:self.deviceIconImageView];
    
    // Telegram UI section - now positioned on the same level as other section labels
    UIColor *primaryColorForTelegram = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    self.telegramUI = [[TelegramUI alloc] initWithFrame:CGRectZero primaryColor:primaryColorForTelegram];
    self.telegramUI.translatesAutoresizingMaskIntoConstraints = NO;
    [self.userInfoCard addSubview:self.telegramUI];
    
    // Set update action for telegram UI
    __weak typeof(self) weakSelf = self;
    [self.telegramUI setUpdateActionBlock:^(NSString *newTag) {
        [weakSelf updateTelegramTag:newTag];
    }];
    
    // App version section
    UILabel *appVersionTitleLabel = [[UILabel alloc] init];
    appVersionTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    appVersionTitleLabel.text = @"APP";
    appVersionTitleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0];
    appVersionTitleLabel.textAlignment = NSTextAlignmentLeft;
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        appVersionTitleLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Bright green for dark mode
            } else {
                return [UIColor colorWithRed:0.0 green:0.6 blue:0.3 alpha:1.0]; // Darker green for light mode
            }
        }];
    } else {
        appVersionTitleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Default bright green
    }
    
    [self.userInfoCard addSubview:appVersionTitleLabel];
    
    self.appVersionValueLabel = [[UILabel alloc] init];
    self.appVersionValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.appVersionValueLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.appVersionValueLabel.textAlignment = NSTextAlignmentLeft;
    self.appVersionValueLabel.numberOfLines = 0;
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        self.appVersionValueLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor whiteColor]; // White text for dark mode
            } else {
                return [UIColor blackColor]; // Black text for light mode
            }
        }];
    } else {
        self.appVersionValueLabel.textColor = [UIColor whiteColor];
    }
    
    [self.userInfoCard addSubview:self.appVersionValueLabel];
    
    // Instagram-style layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // User info card
        [self.userInfoCard.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20.0],
        [self.userInfoCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [self.userInfoCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        
        // Profile image (left side)
        [self.profileImageView.topAnchor constraintEqualToAnchor:self.userInfoCard.topAnchor constant:20.0],
        [self.profileImageView.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [self.profileImageView.widthAnchor constraintEqualToConstant:80.0],
        [self.profileImageView.heightAnchor constraintEqualToConstant:80.0],
        
        // Username label (right of avatar)
        [self.usernameLabel.topAnchor constraintEqualToAnchor:self.profileImageView.topAnchor],
        [self.usernameLabel.leadingAnchor constraintEqualToAnchor:self.profileImageView.trailingAnchor constant:20.0],
        [self.usernameLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // User ID label (right of avatar, below username)
        [self.userIdLabel.topAnchor constraintEqualToAnchor:self.usernameLabel.bottomAnchor constant:5.0],
        [self.userIdLabel.leadingAnchor constraintEqualToAnchor:self.profileImageView.trailingAnchor constant:20.0],
        [self.userIdLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // Days remaining label - positioned in center, below user ID and above divider
        [self.daysRemainingLabel.topAnchor constraintEqualToAnchor:self.userIdLabel.bottomAnchor constant:12.0],
        // Remove the center constraint and position it more to the right
        
        // [self.daysRemainingLabel.centerXAnchor constraintEqualToAnchor:self.userInfoCard.centerXAnchor],
        // Add trailing anchor to position from the right side
        [self.daysRemainingLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-50.0], // Adjusted from -20.0 to -50.0 to move more leftward
        [self.daysRemainingLabel.widthAnchor constraintEqualToConstant:180.0], // Reduced from 220.0 to 180.0
        [self.daysRemainingLabel.heightAnchor constraintEqualToConstant:28.0], // Slightly reduced height
        
        // Divider line - now positioned below the days remaining label
        [dividerLine.topAnchor constraintEqualToAnchor:self.daysRemainingLabel.bottomAnchor constant:12.0],
        [dividerLine.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [dividerLine.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        [dividerLine.heightAnchor constraintEqualToConstant:1.0],
        
        // Telegram UI - inline with other sections
        [self.telegramUI.topAnchor constraintEqualToAnchor:dividerLine.bottomAnchor constant:20.0], 
        [self.telegramUI.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [self.telegramUI.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        [self.telegramUI.heightAnchor constraintEqualToConstant:30.0], // Same height as section titles
        
        // Email section  
        [emailTitleLabel.topAnchor constraintEqualToAnchor:self.telegramUI.bottomAnchor constant:15.0],
        [emailTitleLabel.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [emailTitleLabel.widthAnchor constraintEqualToConstant:70.0],
        
        [self.emailValueLabel.centerYAnchor constraintEqualToAnchor:emailTitleLabel.centerYAnchor],
        [self.emailValueLabel.leadingAnchor constraintEqualToAnchor:emailTitleLabel.trailingAnchor constant:10.0],
        [self.emailValueLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // Plan section
        [planTitleLabel.topAnchor constraintEqualToAnchor:emailTitleLabel.bottomAnchor constant:15.0],
        [planTitleLabel.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [planTitleLabel.widthAnchor constraintEqualToConstant:70.0],
        
        [self.planValueLabel.centerYAnchor constraintEqualToAnchor:planTitleLabel.centerYAnchor],
        [self.planValueLabel.leadingAnchor constraintEqualToAnchor:planTitleLabel.trailingAnchor constant:10.0],
        [self.planValueLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // Plan expiry label
        [self.planExpiryLabel.topAnchor constraintEqualToAnchor:planTitleLabel.bottomAnchor constant:5.0],
        [self.planExpiryLabel.leadingAnchor constraintEqualToAnchor:self.planValueLabel.leadingAnchor],
        [self.planExpiryLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // System section
        [systemTitleLabel.topAnchor constraintEqualToAnchor:self.planExpiryLabel.bottomAnchor constant:15.0],
        [systemTitleLabel.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [systemTitleLabel.widthAnchor constraintEqualToConstant:70.0],
        
        [self.systemValueLabel.topAnchor constraintEqualToAnchor:systemTitleLabel.topAnchor],
        [self.systemValueLabel.leadingAnchor constraintEqualToAnchor:systemTitleLabel.trailingAnchor constant:10.0],
        [self.systemValueLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // Device Limit section
        [self.deviceLimitTitleLabel.topAnchor constraintEqualToAnchor:self.systemValueLabel.bottomAnchor constant:15.0],
        [self.deviceLimitTitleLabel.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [self.deviceLimitTitleLabel.widthAnchor constraintEqualToConstant:70.0],
        
        // Position the device icon
        [self.deviceIconImageView.centerYAnchor constraintEqualToAnchor:self.deviceLimitTitleLabel.centerYAnchor],
        [self.deviceIconImageView.leadingAnchor constraintEqualToAnchor:self.deviceLimitTitleLabel.trailingAnchor constant:10.0],
        [self.deviceIconImageView.widthAnchor constraintEqualToConstant:20.0],
        [self.deviceIconImageView.heightAnchor constraintEqualToConstant:20.0],
        
        [self.deviceLimitValueLabel.centerYAnchor constraintEqualToAnchor:self.deviceLimitTitleLabel.centerYAnchor],
        [self.deviceLimitValueLabel.leadingAnchor constraintEqualToAnchor:self.deviceIconImageView.trailingAnchor constant:5.0],
        [self.deviceLimitValueLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // App version section
        [appVersionTitleLabel.topAnchor constraintEqualToAnchor:self.deviceLimitValueLabel.bottomAnchor constant:15.0],
        [appVersionTitleLabel.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [appVersionTitleLabel.widthAnchor constraintEqualToConstant:70.0],
        
        [self.appVersionValueLabel.topAnchor constraintEqualToAnchor:appVersionTitleLabel.topAnchor],
        [self.appVersionValueLabel.leadingAnchor constraintEqualToAnchor:appVersionTitleLabel.trailingAnchor constant:10.0],
        [self.appVersionValueLabel.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        
        // Comment out this constraint - now handled in setupUpdateButtons
        // [self.userInfoCard.bottomAnchor constraintEqualToAnchor:self.appVersionValueLabel.bottomAnchor constant:20.0],
        
        // Remove this line to avoid conflict with plan slider
        // [self.contentView.bottomAnchor constraintEqualToAnchor:self.userInfoCard.bottomAnchor constant:20.0]
    ]];
    
    // Remove call to setupUpdateButtons from here since we'll call it later
    // [self setupUpdateButtons];
    
    // Update EMAIL section constraints to position it after Telegram
    [NSLayoutConstraint activateConstraints:@[
        [emailTitleLabel.topAnchor constraintEqualToAnchor:self.telegramUI.bottomAnchor constant:16]
        // Other email constraints remain the same
    ]];
    
    // The app version constraints - remove duplicate constraints and ensure correct ordering
    [NSLayoutConstraint activateConstraints:@[
        [appVersionTitleLabel.topAnchor constraintEqualToAnchor:self.deviceLimitValueLabel.bottomAnchor constant:15.0],
    ]];
    
    // Add a footer section with separator and text
    UIView *footerSeparator = [[UIView alloc] init];
    footerSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    footerSeparator.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4]; // Neon green with transparency
    [self.userInfoCard addSubview:footerSeparator];
    
    // Create glowing CONTACT SUPPORT button instead of the subscription plans text
    UIButton *contactSupportButton;
    
    if (@available(iOS 15.0, *)) {
        // Modern iOS 15 button with configuration
        contactSupportButton = [UIButton buttonWithType:UIButtonTypeSystem];
        
        // Create button configuration
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
        config.baseBackgroundColor = [UIColor systemBlueColor];
        config.baseForegroundColor = [UIColor whiteColor];
        
        // Adding a trailing icon (after the text)
        UIImage *supportIcon = [UIImage systemImageNamed:@"bubble.left.fill"];
        config.image = supportIcon;
        config.imagePadding = 8;
        config.imagePlacement = NSDirectionalRectEdgeTrailing;
        
        // Set title with appropriate font
        UIFont *buttonFont = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        
        // Create title attributes with the text "Contact Support"
        NSMutableAttributedString *titleString = [[NSMutableAttributedString alloc] initWithString:@"Contact Support" attributes:@{NSFontAttributeName: buttonFont}];
        config.attributedTitle = titleString;
        
        [contactSupportButton setConfiguration:config];
    } else {
        // Fallback for older iOS versions - using a completely different approach to avoid deprecated properties
        contactSupportButton = [UIButton buttonWithType:UIButtonTypeSystem];
        contactSupportButton.backgroundColor = [UIColor systemBlueColor];
        contactSupportButton.layer.cornerRadius = 16.0;
        [contactSupportButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        
        // Create a UIStack to hold image and label instead of using imageEdgeInsets/titleEdgeInsets
        UIStackView *stackView = [[UIStackView alloc] init];
        stackView.axis = UILayoutConstraintAxisHorizontal;
        stackView.alignment = UIStackViewAlignmentCenter;
        stackView.spacing = 8.0;
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Create label for text - FIRST for trailing icon placement
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"Contact Support";
        titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        titleLabel.textColor = [UIColor whiteColor];
        [stackView addArrangedSubview:titleLabel];
        
        // Create image view for icon - SECOND for trailing placement
        UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bubble.left.fill"]];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.tintColor = [UIColor whiteColor];
        [stackView addArrangedSubview:iconView];
        
        // Add stack view to button
        [contactSupportButton addSubview:stackView];
        
        // Center stack view in button with appropriate constraints
        [NSLayoutConstraint activateConstraints:@[
            [stackView.centerXAnchor constraintEqualToAnchor:contactSupportButton.centerXAnchor],
            [stackView.centerYAnchor constraintEqualToAnchor:contactSupportButton.centerYAnchor],
            [stackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:contactSupportButton.leadingAnchor constant:12],
            [stackView.trailingAnchor constraintLessThanOrEqualToAnchor:contactSupportButton.trailingAnchor constant:-12],
            [iconView.widthAnchor constraintEqualToConstant:16],
            [iconView.heightAnchor constraintEqualToConstant:16]
        ]];
    }
    
    contactSupportButton.translatesAutoresizingMaskIntoConstraints = NO;
    contactSupportButton.layer.masksToBounds = NO; // Allow shadow to exceed bounds
    
    // Add subtle shadow for depth
    contactSupportButton.layer.shadowColor = [UIColor systemBlueColor].CGColor;
    contactSupportButton.layer.shadowOffset = CGSizeMake(0, 2);
    contactSupportButton.layer.shadowRadius = 4.0;
    contactSupportButton.layer.shadowOpacity = 0.3;
    
    [contactSupportButton addTarget:self action:@selector(contactSupportTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.userInfoCard addSubview:contactSupportButton];
    
    // Create a more subtle pulsating animation
    CABasicAnimation *pulseAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    pulseAnimation.duration = 2.0;
    pulseAnimation.fromValue = @(0.3);
    pulseAnimation.toValue = @(0.6);
    pulseAnimation.autoreverses = YES;
    pulseAnimation.repeatCount = HUGE_VALF;
    pulseAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [contactSupportButton.layer addAnimation:pulseAnimation forKey:@"pulse"];

    // Create a container for the update buttons
    UIView *updateButtonsContainer = [[UIView alloc] init];
    updateButtonsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.userInfoCard addSubview:updateButtonsContainer];
    
        [NSLayoutConstraint activateConstraints:@[
        // Update buttons container - positioned between app version and separator with reduced height
        [updateButtonsContainer.topAnchor constraintEqualToAnchor:self.appVersionValueLabel.bottomAnchor constant:15.0], // Reduced from 20 to 15
        [updateButtonsContainer.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [updateButtonsContainer.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        [updateButtonsContainer.heightAnchor constraintEqualToConstant:35.0], // Reduced from 40 to 35 for smaller buttons
        
        // Footer separator - now positioned closer to the update buttons
        [footerSeparator.topAnchor constraintEqualToAnchor:updateButtonsContainer.bottomAnchor constant:15.0], // Reduced from 20 to 15
        [footerSeparator.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:20.0],
        [footerSeparator.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-20.0],
        [footerSeparator.heightAnchor constraintEqualToConstant:1.0],
        
        // Contact Support button (replaces footer text)
        [contactSupportButton.topAnchor constraintEqualToAnchor:footerSeparator.bottomAnchor constant:10.0],
        [contactSupportButton.centerXAnchor constraintEqualToAnchor:self.userInfoCard.centerXAnchor],
        [contactSupportButton.widthAnchor constraintLessThanOrEqualToConstant:180.0], // Increased width for the longer text
        [contactSupportButton.heightAnchor constraintEqualToConstant:32.0], // Maintained the same height
        
        // Update the bottom constraint to use the contact support button
        [self.userInfoCard.bottomAnchor constraintEqualToAnchor:contactSupportButton.bottomAnchor constant:20.0],
    ]];
    
    // Setup the update buttons in the container
    [self setupUpdateButtonsInContainer:updateButtonsContainer];
}

#pragma mark - Plan Data Methods

- (void)fetchPlanData {
    self.planValueLabel.text = @"LOADING...";
    
    // Fetch plan data from the API
    [[APIManager sharedManager] fetchUserPlanWithToken:self.authToken completion:^(NSDictionary *planData, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.planValueLabel.text = @"ERROR_LOADING_PLAN_DATA";
            });
            return;
        }
        
        if (!planData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.planValueLabel.text = @"NO_PLAN_DATA_AVAILABLE";
            });
            return;
        }
        
        NSLog(@"[WeaponX] Plan data received: %@", planData);
        
        // DETAILED DEBUG: Log the structure of the plan data to understand what we're working with
        NSLog(@"[WeaponX] Full plan data structure check:");
        NSLog(@"[WeaponX] - plan key exists: %@", planData[@"plan"] ? @"YES" : @"NO");
        
        if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[WeaponX] - Plan data contains plan object with keys: %@", [planData[@"plan"] allKeys]);
            
            if (planData[@"plan"][@"max_devices"]) {
                NSLog(@"[WeaponX] - max_devices in plan data: %@ (type: %@)", 
                      planData[@"plan"][@"max_devices"], 
                      NSStringFromClass([planData[@"plan"][@"max_devices"] class]));
            }
        }
        
        // Log whether using custom device limit
        if (planData[@"using_custom_device_limit"] != nil && 
            ![planData[@"using_custom_device_limit"] isKindOfClass:[NSNull class]]) {
            BOOL usingCustomLimit = [planData[@"using_custom_device_limit"] boolValue];
            NSLog(@"[WeaponX] User is %@using a custom device limit according to API", usingCustomLimit ? @"" : @"NOT ");
        }
        
        // Store the raw plan data
        self.planData = planData;
        
        // Check different possible formats of the API response
        BOOL hasPlan = NO;
        NSString *planName = @"NO_PLAN";
        NSString *expiryDate = @"";
        
        if ([self.planData objectForKey:@"has_plan"] != nil) {
            // Format 1: API returns {has_plan: true/false, plan: {...}}
            hasPlan = [self.planData[@"has_plan"] boolValue];
            NSLog(@"[WeaponX] 📋 Has active plan (from server): %@", hasPlan ? @"YES" : @"NO");
            if (hasPlan && self.planData[@"plan"]) {
                planName = self.planData[@"plan"][@"name"] ?: @"UNKNOWN_PLAN";
                expiryDate = self.planData[@"plan"][@"expires_at"] ?: @"";
                
                // DEBUG: Check max_devices specifically
                if (self.planData[@"plan"][@"max_devices"]) {
                    NSLog(@"[WeaponX] Found max_devices in plan: %@ (type: %@)", 
                          self.planData[@"plan"][@"max_devices"],
                          NSStringFromClass([self.planData[@"plan"][@"max_devices"] class]));
                }
            }
        } else if (self.planData[@"name"]) {
            // Format 2: API returns plan details directly
            planName = self.planData[@"name"];
            expiryDate = self.planData[@"expires_at"] ?: @"";
            hasPlan = ![planName isEqualToString:@"NO_PLAN"] && ![planName isEqualToString:@""];
        } else if (self.planData[@"plan"] && [self.planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
            // Format 3: API returns {plan: {...}}
            NSDictionary *plan = self.planData[@"plan"];
            planName = plan[@"name"] ?: @"UNKNOWN_PLAN";
            expiryDate = plan[@"expires_at"] ?: @"";
            
            // Check for plan ID to determine if it's a valid plan
            id planId = plan[@"id"];
            if (planId && ![planId isKindOfClass:[NSNull class]]) {
                hasPlan = [planId intValue] > 0;
            } else {
                hasPlan = ![planName isEqualToString:@"NO_PLAN"] && ![planName isEqualToString:@""];
            }
            
            // DEBUG: Check max_devices specifically
            if (plan[@"max_devices"]) {
                NSLog(@"[WeaponX] Found max_devices in plan: %@ (type: %@)", 
                      plan[@"max_devices"],
                      NSStringFromClass([plan[@"max_devices"] class]));
            }
        }
        
        // Handle the no-plan case explicitly
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        if (!hasPlan) {
            NSLog(@"[WeaponX] ❌ No active plan detected, clearing plan data from UserDefaults");
            
            // Clear all plan-related data from UserDefaults
            [defaults setObject:@"NO_PLAN" forKey:@"UserPlanName"];
            [defaults removeObjectForKey:@"UserPlanExpiry"];
            [defaults removeObjectForKey:@"UserPlanDaysRemaining"];
            
            // Also remove any legacy keys that might exist
            [defaults removeObjectForKey:@"PlanExpiryDate"];
            [defaults removeObjectForKey:@"PlanDaysRemaining"];
            [defaults removeObjectForKey:@"WeaponXUserPlan"];
            [defaults removeObjectForKey:@"WeaponXUserPlanHash"];
            [defaults removeObjectForKey:@"WeaponXUserPlanTimestamp"];
            
            [defaults synchronize];
            
            // Update UI on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                self.planValueLabel.text = @"NO_PLAN";
                self.planExpiryLabel.text = @"No active subscription";
                self.daysRemainingLabel.text = @"GET PLAN";
                self.isGetPlanMode = YES;
                self.planDaysRemaining = 0;
                
                // Pulse animation on GET PLAN button
                [self setupPulseAnimationForLabel:self.daysRemainingLabel];
                
                // Cancel any loading state
                if (self.loadingTimeoutTimer) {
                    [self.loadingTimeoutTimer invalidate];
                    self.loadingTimeoutTimer = nil;
                }
            });
            
            return;
        }
        
        // Save plan name to user defaults
        [defaults setObject:planName forKey:@"UserPlanName"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // Format the expiry date if present
        NSString *formattedExpiryDate = @"";
        NSInteger daysRemaining = 0;
        
        if (expiryDate.length > 0) {
            NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
            [inputFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
            
            // Try multiple date formats
            NSArray *dateFormats = @[
                @"yyyy-MM-dd HH:mm:ss",
                @"yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                @"yyyy-MM-dd'T'HH:mm:ssZ",
                @"yyyy-MM-dd",
                @"MM/dd/yyyy"
            ];
            
            NSDate *expiryDateObj = nil;
            
            for (NSString *format in dateFormats) {
                [inputFormatter setDateFormat:format];
                expiryDateObj = [inputFormatter dateFromString:expiryDate];
                if (expiryDateObj) break;
            }
            
            if (expiryDateObj) {
                NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
                [outputFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
                [outputFormatter setDateFormat:@"yyyy-MM-dd"];
                formattedExpiryDate = [outputFormatter stringFromDate:expiryDateObj];
                
                // Calculate days remaining
                NSCalendar *calendar = [NSCalendar currentCalendar];
                [calendar setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
                NSDate *currentDate = [NSDate date];
                NSLog(@"[WeaponX] 📅 Comparing dates - Current: %@, Expiry: %@", currentDate, expiryDateObj);
                NSDateComponents *components = [calendar components:NSCalendarUnitDay
                                                          fromDate:[NSDate date]
                                                            toDate:expiryDateObj
                                                           options:0];
                daysRemaining = [components day];
                NSLog(@"[WeaponX] 📅 Days remaining calculation: %ld days", (long)daysRemaining);

                // Double-check with direct timestamp comparison (more reliable)
                BOOL isExpiredByTimestamp = [expiryDateObj timeIntervalSinceDate:currentDate] <= 0;
                NSLog(@"[WeaponX] 📅 Direct timestamp comparison - Expired: %@", isExpiredByTimestamp ? @"YES" : @"NO");

                // If there is a discrepancy, trust the direct timestamp comparison
                if ((daysRemaining <= 0) != isExpiredByTimestamp) {
                    NSLog(@"[WeaponX] ⚠️ Date comparison inconsistency detected!");
                    // Fix the daysRemaining value based on the direct timestamp check
                    daysRemaining = isExpiredByTimestamp ? -1 : 1;
                    NSLog(@"[WeaponX] 🔧 Corrected days remaining value: %ld", (long)daysRemaining);
                }
            } else {
                formattedExpiryDate = expiryDate; // Use original string if parsing fails
            }
            
            // Save expiry date to user defaults
            [[NSUserDefaults standardUserDefaults] setObject:formattedExpiryDate forKey:@"UserPlanExpiry"];
            [[NSUserDefaults standardUserDefaults] setObject:@(daysRemaining) forKey:@"UserPlanDaysRemaining"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        
        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update plan name with uppercase for hacker effect
            self.planValueLabel.text = [planName uppercaseString];
            
            // Add expiry info if present
            if (formattedExpiryDate.length > 0) {
                // Create plan expiry label if needed
                if (!self.planExpiryLabel) {
                    self.planExpiryLabel = [[UILabel alloc] init];
                    self.planExpiryLabel.translatesAutoresizingMaskIntoConstraints = NO;
                    self.planExpiryLabel.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont systemFontOfSize:11.0];
                    
                    // Find the plan section to add it to
                    UIView *planSection = nil;
                    for (UIView *subview in self.userInfoCard.subviews) {
                        if ([subview.subviews containsObject:self.planValueLabel]) {
                            planSection = subview;
                            break;
                        }
                    }
                    
                    if (planSection) {
                        [planSection addSubview:self.planExpiryLabel];
                        [NSLayoutConstraint activateConstraints:@[
                            [self.planExpiryLabel.topAnchor constraintEqualToAnchor:self.planValueLabel.bottomAnchor constant:3.0],
                            [self.planExpiryLabel.leadingAnchor constraintEqualToAnchor:self.planValueLabel.leadingAnchor],
                            [self.planExpiryLabel.trailingAnchor constraintEqualToAnchor:planSection.trailingAnchor constant:-10.0],
                            [self.planExpiryLabel.bottomAnchor constraintEqualToAnchor:planSection.bottomAnchor constant:-5.0]
                        ]];
                        
                        // Update plan section height
                        for (NSLayoutConstraint *constraint in planSection.constraints) {
                            if (constraint.firstAttribute == NSLayoutAttributeHeight) {
                                constraint.constant = 80.0;
                                break;
                            }
                        }
                    }
                }
                
                // Set text color based on days remaining
                if (daysRemaining <= 0) {
                    // Expired
                    if (@available(iOS 13.0, *)) {
                        self.planExpiryLabel.textColor = [UIColor systemRedColor];
                } else {
                        self.planExpiryLabel.textColor = [UIColor redColor];
                }
                    self.planExpiryLabel.text = [NSString stringWithFormat:@"ACTIVE UNTIL: %@", formattedExpiryDate];
                } else if (daysRemaining <= 7) {
                    // Warning: less than a week
                    if (@available(iOS 13.0, *)) {
                        self.planExpiryLabel.textColor = [UIColor systemOrangeColor];
            } else {
                        self.planExpiryLabel.textColor = [UIColor orangeColor];
            }
                    self.planExpiryLabel.text = [NSString stringWithFormat:@"EXPIRES IN %ld DAYS: %@", (long)daysRemaining, formattedExpiryDate];
        } else {
                    // Normal
                    if (@available(iOS 13.0, *)) {
                        self.planExpiryLabel.textColor = [UIColor secondaryLabelColor];
                    } else {
                        self.planExpiryLabel.textColor = [UIColor grayColor];
                    }
                    self.planExpiryLabel.text = [NSString stringWithFormat:@"VALID UNTIL: %@", formattedExpiryDate];
                }
                
                // Make sure it's visible
                self.planExpiryLabel.hidden = NO;
    } else {
                if (self.planExpiryLabel) {
                    self.planExpiryLabel.hidden = YES;
                }
            }
            
            // Force layout update
            [self.userInfoCard setNeedsLayout];
            [self.userInfoCard layoutIfNeeded];
        });
    }];
}

- (void)fetchAndDisplayPlanData {
    if (!self.isLoggedIn || !self.authToken) {
        // Hide plan information UI if not logged in
        self.planTitleLabel.hidden = YES;
        self.planNameLabel.hidden = YES;
        self.planExpiryLabel.hidden = YES;
        return;
    }
    
    // Trigger plan countdown update first using current data
    [self updatePlanCountdown];
    
    // Then fetch updated data from server
    [self fetchPlanData];
}

#pragma mark - UI Update Methods

- (void)updateUI {
    // Update UI based on login status
    if (self.isLoggedIn) {
        // Show user info and hide login view
        self.loginView.hidden = YES;
        self.userInfoCard.hidden = NO;
        
        // Update user info display
        [self updateUserInfoDisplay];
        
        // Update the navigation bar logout button
        [self setupNavBarLogoutButton];
        
        // Refresh user data from server if needed
        [self refreshUserData];
    } else {
        // Show login view and hide user info
        self.loginView.hidden = NO;
        self.userInfoCard.hidden = YES;
        
        // Remove the navigation bar logout button
        self.navigationItem.rightBarButtonItem = nil;
        
        // Clear text fields for security
        self.emailField.text = @"";
        self.passwordField.text = @"";
    }
}

- (void)updateUserInfoDisplay {
    if (!self.userData) {
        return;
    }
    
    NSLog(@"[WeaponX] Updating user info display with data: %@", self.userData);
    
    // Update username and user ID
    self.usernameLabel.text = [self.userData[@"name"] uppercaseString];
    self.userIdLabel.text = [NSString stringWithFormat:@"ID: %@", self.userData[@"id"]];
    
    // Update email
    self.emailValueLabel.text = self.userData[@"email"];
    
    // Update device UUID label if exists
    if (self.deviceUuidLabel) {
        self.deviceUuidLabel.text = [self getDeviceUUID];
    }
    
    // Update avatar image - always use our hacker avatar instead of loading from URL
    [self createHackerAvatar];
    
    // Update plan countdown
    [self updatePlanCountdown];
    
    // Update the plan slider
    [self updatePlanSlider];
    
    // Update Telegram UI with logging
    NSLog(@"[WeaponX] Setting Telegram tag: %@", self.userData[@"telegram_tag"]);
    [self.telegramUI setAuthToken:self.authToken];
    [self.telegramUI updateWithTelegramTag:self.userData[@"telegram_tag"]];
    
    // Update device limit - get data directly from user API response
    NSNumber *deviceLimit = nil;
    NSNumber *currentDeviceCount = nil;
    BOOL usingCustomDeviceLimit = NO;
    
    // First check if we have the using_custom_device_limit flag from the API
    if (self.planData && self.planData[@"using_custom_device_limit"] && 
        ![self.planData[@"using_custom_device_limit"] isKindOfClass:[NSNull class]]) {
        
        usingCustomDeviceLimit = [self.planData[@"using_custom_device_limit"] boolValue];
        NSLog(@"[WeaponX] Using custom device limit: %@", usingCustomDeviceLimit ? @"YES" : @"NO");
    }
    
    // Safely get the current device count
    if (self.userData[@"active_devices_count"] && 
        ![self.userData[@"active_devices_count"] isKindOfClass:[NSNull class]] &&
        ![self.userData[@"active_devices_count"] isEqual:@""]) {
        currentDeviceCount = self.userData[@"active_devices_count"];
        NSLog(@"[WeaponX] Found active devices count from user data: %@", currentDeviceCount);
    } else if (self.planData && self.planData[@"active_devices_count"] && 
               ![self.planData[@"active_devices_count"] isKindOfClass:[NSNull class]] &&
               ![self.planData[@"active_devices_count"] isEqual:@""]) {
        currentDeviceCount = self.planData[@"active_devices_count"];
        NSLog(@"[WeaponX] Found active devices count from plan data: %@", currentDeviceCount);
    } else {
        // Default to 0 if no data available
        currentDeviceCount = @0;
        NSLog(@"[WeaponX] No device count found, defaulting to 0");
    }
    
    // First check for custom device limit field (from API)
    if (self.userData[@"custom_device_limit"] && 
        ![self.userData[@"custom_device_limit"] isKindOfClass:[NSNull class]] && 
        ![self.userData[@"custom_device_limit"] isEqual:@""] &&
        [self.userData[@"custom_device_limit"] intValue] > 0) {
        
        deviceLimit = self.userData[@"custom_device_limit"];
        NSLog(@"[WeaponX] Found custom device limit from user data: %@", deviceLimit);
    } 
    // If no custom limit, try to get from device_limit field
    else if (self.userData[@"device_limit"] && 
             ![self.userData[@"device_limit"] isKindOfClass:[NSNull class]] && 
             ![self.userData[@"device_limit"] isEqual:@""] &&
             [self.userData[@"device_limit"] intValue] > 0) {
        
        deviceLimit = self.userData[@"device_limit"];
        NSLog(@"[WeaponX] Found device limit from user data: %@", deviceLimit);
    }
    // If still no limit, try to get from plan data
    else if (self.planData) {
        // Check for plan max_devices in different possible locations
        NSNumber *planDeviceLimit = nil;
        
        // Try format 1: plan data in planData[@"plan"]
        if (self.planData[@"plan"] && [self.planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *plan = self.planData[@"plan"];
            NSLog(@"[WeaponX] Checking plan data structure: %@", plan);
            
            // Check for max_devices with value > 0
            if (plan[@"max_devices"] && 
                ![plan[@"max_devices"] isKindOfClass:[NSNull class]] && 
                ![plan[@"max_devices"] isEqual:@""]) {
                
                // Convert to NSNumber if it's a string
                if ([plan[@"max_devices"] isKindOfClass:[NSString class]]) {
                    int intValue = [plan[@"max_devices"] intValue];
                    NSLog(@"[WeaponX] max_devices converted from string: '%@' to int: %d", plan[@"max_devices"], intValue);
                    // Even if intValue is 0, use it (might be valid)
                    planDeviceLimit = @(intValue);
                } else if ([plan[@"max_devices"] isKindOfClass:[NSNumber class]]) {
                    planDeviceLimit = plan[@"max_devices"];
                    NSLog(@"[WeaponX] max_devices is already NSNumber: %@", planDeviceLimit);
                } else {
                    NSLog(@"[WeaponX] max_devices is in unsupported format: %@ (type: %@)", 
                          plan[@"max_devices"], 
                          NSStringFromClass([plan[@"max_devices"] class]));
                }
            } 
            // Check for device_limit with value > 0
            else if (plan[@"device_limit"] && 
                     ![plan[@"device_limit"] isKindOfClass:[NSNull class]] && 
                     ![plan[@"device_limit"] isEqual:@""]) {
                
                // Convert to NSNumber if it's a string
                if ([plan[@"device_limit"] isKindOfClass:[NSString class]]) {
                    int intValue = [plan[@"device_limit"] intValue];
                    NSLog(@"[WeaponX] device_limit converted from string: '%@' to int: %d", plan[@"device_limit"], intValue);
                    // Even if intValue is 0, use it (might be valid)
                    planDeviceLimit = @(intValue);
                } else if ([plan[@"device_limit"] isKindOfClass:[NSNumber class]]) {
                    planDeviceLimit = plan[@"device_limit"];
                    NSLog(@"[WeaponX] device_limit is already NSNumber: %@", planDeviceLimit);
                } else {
                    NSLog(@"[WeaponX] device_limit is in unsupported format: %@ (type: %@)", 
                          plan[@"device_limit"], 
                          NSStringFromClass([plan[@"device_limit"] class]));
                }
            } 
            // Check for devices with value > 0
            else if (plan[@"devices"] && 
                     ![plan[@"devices"] isKindOfClass:[NSNull class]] && 
                     ![plan[@"devices"] isEqual:@""]) {
                
                // Convert to NSNumber if it's a string
                if ([plan[@"devices"] isKindOfClass:[NSString class]]) {
                    int intValue = [plan[@"devices"] intValue];
                    NSLog(@"[WeaponX] devices converted from string: '%@' to int: %d", plan[@"devices"], intValue);
                    // Even if intValue is 0, use it (might be valid)
                    planDeviceLimit = @(intValue);
                } else if ([plan[@"devices"] isKindOfClass:[NSNumber class]]) {
                    planDeviceLimit = plan[@"devices"];
                    NSLog(@"[WeaponX] devices is already NSNumber: %@", planDeviceLimit);
                } else {
                    NSLog(@"[WeaponX] devices is in unsupported format: %@ (type: %@)", 
                          plan[@"devices"], 
                          NSStringFromClass([plan[@"devices"] class]));
                }
            }
        } 
        // Try format 2: plan data directly in planData
        else if (self.planData[@"max_devices"] && 
                 ![self.planData[@"max_devices"] isKindOfClass:[NSNull class]] && 
                 ![self.planData[@"max_devices"] isEqual:@""]) {
            
            // Convert to NSNumber if it's a string
            if ([self.planData[@"max_devices"] isKindOfClass:[NSString class]]) {
                planDeviceLimit = @([self.planData[@"max_devices"] intValue]);
                } else {
                planDeviceLimit = self.planData[@"max_devices"];
            }
        } 
        else if (self.planData[@"device_limit"] && 
                 ![self.planData[@"device_limit"] isKindOfClass:[NSNull class]] && 
                 ![self.planData[@"device_limit"] isEqual:@""]) {
            
            // Convert to NSNumber if it's a string
            if ([self.planData[@"device_limit"] isKindOfClass:[NSString class]]) {
                planDeviceLimit = @([self.planData[@"device_limit"] intValue]);
            } else {
                planDeviceLimit = self.planData[@"device_limit"];
            }
        } 
        else if (self.planData[@"devices"] && 
                 ![self.planData[@"devices"] isKindOfClass:[NSNull class]] && 
                 ![self.planData[@"devices"] isEqual:@""]) {
            
            // Convert to NSNumber if it's a string
            if ([self.planData[@"devices"] isKindOfClass:[NSString class]]) {
                planDeviceLimit = @([self.planData[@"devices"] intValue]);
        } else {
                planDeviceLimit = self.planData[@"devices"];
            }
        }
        
        // If we found a valid plan device limit, use it
        if (planDeviceLimit) {
            deviceLimit = planDeviceLimit;
            NSLog(@"[WeaponX] Found device limit from plan data: %@", deviceLimit);
        }
    }
    
    // Set a default limit if none was found
    if (!deviceLimit || [deviceLimit intValue] <= 0) {
        deviceLimit = @1; // Default to 1 device if no valid limit found
        NSLog(@"[WeaponX] No valid device limit found, using default: %@", deviceLimit);
    }
    
    // Ensure we have NSNumber objects instead of strings for both counts
    if ([currentDeviceCount isKindOfClass:[NSString class]]) {
        currentDeviceCount = @([currentDeviceCount intValue]);
    }
    
    if ([deviceLimit isKindOfClass:[NSString class]]) {
        deviceLimit = @([deviceLimit intValue]);
    }
    
    // Update device limit label based on available data
    @try {
        // Format: Current/Total
        NSString *formattedText;
        if (usingCustomDeviceLimit) {
            formattedText = [NSString stringWithFormat:@"%@ / %@ devices (custom)", currentDeviceCount ?: @0, deviceLimit ?: @1];
        } else {
            formattedText = [NSString stringWithFormat:@"%@ / %@ devices", currentDeviceCount ?: @0, deviceLimit ?: @1];
        }
        self.deviceLimitValueLabel.text = formattedText;
        NSLog(@"[WeaponX] Updated device limit label: %@", formattedText);
    } @catch (NSException *exception) {
        // Fallback in case of any error
        self.deviceLimitValueLabel.text = @"1 device allowed";
        NSLog(@"[WeaponX] Error updating device limit label: %@", exception);
    }
    
    // Update app version info
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    self.appVersionValueLabel.text = [NSString stringWithFormat:@"Version: %@ (Build %@)", appVersion ?: @"1.0.0", buildNumber ?: @"1"];
    
    // Ensure all UI updates complete
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    
    // Update scroll view content size after layout
    [self updateScrollViewContentSize];
}

#pragma mark - Button Actions

- (void)loginButtonTapped {
    NSLog(@"[WeaponX] ACCESS SYSTEM button tapped in AccountViewController");
    // Validate input
    NSString *email = self.emailField.text;
    NSString *password = self.passwordField.text;
    
    if (!email.length || !password.length) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                   message:@"Please enter both email and password"
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Basic email validation
    NSString *emailRegex = @"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}";
    NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", emailRegex];
    if (![emailTest evaluateWithObject:email]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                   message:@"Please enter a valid email address"
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Show activity indicator
    [self.activityIndicator startAnimating];
    
    // Disable login button while processing
    self.loginButton.enabled = NO;
    
    // Use dynamic color for disabled state
    if (@available(iOS 13.0, *)) {
        self.loginButton.backgroundColor = [UIColor systemGray3Color];
    } else {
        self.loginButton.backgroundColor = [UIColor lightGrayColor];
    }
    
    NSLog(@"[WeaponX] Attempting login with email: %@", email);
    
    // Convert email to lowercase to ensure case-insensitive login
    NSString *lowercaseEmail = [email lowercaseString];
    
    // Use the APIManager to handle login with CSRF token
    [[APIManager sharedManager] loginWithEmail:lowercaseEmail password:password completion:^(NSDictionary *userData, NSString *token, NSError *error) {
        // --- All UI updates and navigation on main thread for safety ---
        dispatch_async(dispatch_get_main_queue(), ^{
            // Hide activity indicator
            [self.activityIndicator stopAnimating];
            // Re-enable login button
            self.loginButton.enabled = YES;
            // Reset button color based on mode
            UIColor *buttonColor;
            if (@available(iOS 13.0, *)) {
                buttonColor = [UIColor systemGreenColor];
            } else {
                buttonColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
            }
            self.loginButton.backgroundColor = buttonColor;

            if (error || !token) {
                NSString *errorMessage = error ? error.localizedDescription : @"Login failed. Please check your credentials and try again.";
                NSLog(@"[WeaponX] Login error: %@", errorMessage);
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LOGIN FAILED" 
                                                                               message:errorMessage 
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }

            NSLog(@"[WeaponX] Login successful, token: %@", token);

            // Process user data to handle NSNull values
            NSMutableDictionary *processedUserData = [NSMutableDictionary dictionary];

            if (userData) {
                // Process each key-value pair to replace NSNull with appropriate defaults
                [userData enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([obj isKindOfClass:[NSNull class]]) {
                        // Replace NSNull with appropriate default based on key
                        if ([key isEqualToString:@"id"] || 
                            [key isEqualToString:@"user_id"]) {
                            processedUserData[key] = @0;
                        } else {
                            processedUserData[key] = @"";
                        }
                    } else {
                        processedUserData[key] = obj;
                    }
                }];
                // Ensure all required fields exist
                if (!processedUserData[@"id"]) processedUserData[@"id"] = @0;
                if (!processedUserData[@"name"]) processedUserData[@"name"] = @"";
                if (!processedUserData[@"email"]) processedUserData[@"email"] = @"";
                if (!processedUserData[@"avatar"]) processedUserData[@"avatar"] = @"";
                if (!processedUserData[@"role"]) processedUserData[@"role"] = @"user";
                if (!processedUserData[@"telegram_tag"]) processedUserData[@"telegram_tag"] = @"";
                if (!processedUserData[@"created_at"]) processedUserData[@"created_at"] = @"";
                if (!processedUserData[@"updated_at"]) processedUserData[@"updated_at"] = @"";
            } else {
                // Create minimal user data if none provided
                processedUserData[@"id"] = @0;
                processedUserData[@"name"] = @"";
                processedUserData[@"email"] = lowercaseEmail;
                processedUserData[@"avatar"] = @"";
                processedUserData[@"role"] = @"user";
                processedUserData[@"telegram_tag"] = @"";
                processedUserData[@"created_at"] = @"";
                processedUserData[@"updated_at"] = @"";
            }

            // Save token and processed user data
            self.authToken = token;
            self.userData = processedUserData;
            [self setLoggedIn:YES];
            // Get existing defaults instance
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            // Save token and user info
            [defaults setObject:token forKey:@"WeaponXAuthToken"];
            [defaults setObject:processedUserData forKey:@"WeaponXUserInfo"];
            // Also save individual fields for easier access
            if (processedUserData[@"name"]) {
                [defaults setObject:processedUserData[@"name"] forKey:@"Username"];
            }
            if (processedUserData[@"email"]) {
                [defaults setObject:processedUserData[@"email"] forKey:@"UserEmail"];
                // Save the last successful login credentials
                [defaults setObject:lowercaseEmail forKey:@"LastLoginEmail"];
                [defaults setObject:password forKey:@"LastLoginPassword"];
                NSLog(@"[WeaponX] Saved last successful login credentials for quick login");
            }
            // Force NSUserDefaults to save immediately
            [defaults synchronize];
            // Verify save was successful
            NSString *savedToken = [defaults objectForKey:@"WeaponXAuthToken"];
            NSDictionary *savedUserData = [defaults objectForKey:@"WeaponXUserInfo"];
            if (!savedToken || !savedUserData) {
                NSLog(@"[WeaponX] WARNING: Failed to save user data to NSUserDefaults");
            } else {
                NSLog(@"[WeaponX] Successfully saved user data to NSUserDefaults");
            }
            // Update UI
            [self updateUI];

            // --- Post login notification and handle navigation like LoginViewController ---
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserDidLogin" object:nil];

            // Dismiss modal if presented, and switch to Account tab if possible
            UIWindow *keyWindow = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if ([scene isKindOfClass:[UIWindowScene class]] &&
                        scene.activationState == UISceneActivationStateForegroundActive) {
                        UIWindowScene *windowScene = (UIWindowScene *)scene;
                        for (UIWindow *window in windowScene.windows) {
                            if (window.isKeyWindow) {
                                keyWindow = window;
                                break;
                            }
                        }
                        if (keyWindow) break;
                    }
                }
            } else {
                keyWindow = [[UIApplication sharedApplication] delegate].window;
            }
            UITabBarController *tabBarController = (UITabBarController *)keyWindow.rootViewController;
            if ([tabBarController isKindOfClass:[TabBarController class]]) {
                // Dismiss if presented, then switch to account tab
                if (self.presentingViewController) {
                    [self dismissViewControllerAnimated:YES completion:^{
                        [(TabBarController *)tabBarController switchToAccountTab];
                    }];
                } else {
                    [(TabBarController *)tabBarController switchToAccountTab];
                }
            } else if (self.presentingViewController) {
                // Fallback: just dismiss
                [self dismissViewControllerAnimated:YES completion:nil];
            }

            // Show welcome message
            NSString *userName = processedUserData[@"name"] ? processedUserData[@"name"] : @"Agent";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ACCESS GRANTED" 
                                                                           message:[NSString stringWithFormat:@"Welcome back, %@!", userName]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

- (void)signupButtonTapped {
    // Create and present the signup view controller
    SignupViewController *signupVC = [[SignupViewController alloc] init];
    
    // Set the completion handler to refresh the account view when signup is complete
    signupVC.signupCompletionHandler = ^{
        // Update the UI with the new user data
        [self updateUI];
        
        // Force reload of auth data
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        self.authToken = [defaults objectForKey:@"WeaponXAuthToken"];
        self.userData = [defaults objectForKey:@"WeaponXUserInfo"];
        
        // Check if we actually have valid auth data
        if (self.authToken && self.userData) {
            [self setLoggedIn:YES];
            
            // Post notification for successful login to update other view controllers
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserDidLogin" object:nil];
        }
    };
    
    // Present the signup view controller modally with a slide up animation
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:signupVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)logoutButtonPressed {
    // Show activity indicator while logging out
    UIActivityIndicatorView *activityIndicator;
    if (@available(iOS 13.0, *)) {
        activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        #pragma clang diagnostic pop
    }
    activityIndicator.center = self.view.center;
    [self.view addSubview:activityIndicator];
    [activityIndicator startAnimating];
    
    // Clear user data from NSUserDefaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey:@"WeaponXAuthToken"];
        [defaults removeObjectForKey:@"WeaponXUserInfo"];
    [defaults removeObjectForKey:@"Username"];
    [defaults removeObjectForKey:@"UserEmail"];
    [defaults removeObjectForKey:@"UserId"];
    [defaults removeObjectForKey:@"UserPlanName"];
    [defaults removeObjectForKey:@"UserPlanExpiry"];
    [defaults removeObjectForKey:@"UserPlanDaysRemaining"];
    [defaults synchronize];
    
    // Update login status
    [self setLoggedIn:NO];
    self.authToken = nil;
    self.userData = nil;
    
    // Post logout notification
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserDidLogout" object:nil];
        
    // Clear all cookies and website data
    if (@available(iOS 9.0, *)) {
        NSSet *websiteDataTypes = [NSSet setWithArray:@[
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeWebSQLDatabases,
            WKWebsiteDataTypeIndexedDBDatabases
        ]];
        
        // Date from
        NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
        
        // Clear website data
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes 
                                                  modifiedSince:dateFrom 
                                              completionHandler:^{
            NSLog(@"[WeaponX] Cleared all website data");
        }];
    }
    
    // Show a confirmation alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Logged Out" 
                                                                  message:@"You have been logged out successfully. The app will now restart."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // Exit and relaunch the app after logout
        NSLog(@"[WeaponX] Exiting and relaunching app after manual logout");
        [activityIndicator removeFromSuperview];
        [[APIManager sharedManager] exitAndRelaunchApp];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Notification Handlers

- (void)handleUserLogin:(NSNotification *)notification {
    // Reload auth data from NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.authToken = [defaults objectForKey:@"WeaponXAuthToken"];
    self.userData = [defaults objectForKey:@"WeaponXUserInfo"];
    
    // Update login status
    [self setLoggedIn:(self.authToken != nil && self.userData != nil)];
    
    NSLog(@"[WeaponX] AccountViewController received login notification, isLoggedIn: %@", self.isLoggedIn ? @"YES" : @"NO");
    
    // Update UI on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
    [self updateUI];
    
        // Add the nav bar logout button now that we're logged in
        [self setupNavBarLogoutButton];
        
        // Refresh user data if logged in
    if (self.isLoggedIn) {
            [self refreshUserData];
        }
    });
}

// Method to handle user logout notification
- (void)handleUserLogout:(NSNotification *)notification {
    // Clear auth data
    self.authToken = nil;
    self.userData = nil;
    [self setLoggedIn:NO];
    
    NSLog(@"[WeaponX] AccountViewController received logout notification");
    
    // Update UI on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateUI];
    });
}

#pragma mark - Refresh Control

- (void)handleRefresh:(UIRefreshControl *)refreshControl {
    NSLog(@"[WeaponX] Pull to refresh triggered");
    
    if (self.isLoggedIn) {
        // Force refresh user data from server
        [self refreshUserDataForceRefresh:YES];
    } else {
        // If not logged in, just end refreshing
        [refreshControl endRefreshing];
    }
}

#pragma mark - Hacker Avatar Generation

- (UIImage *)generateHackerAvatarForUser:(NSString *)identifier {
    // Create a unique hash based on the user's email or identifier
    NSUInteger hash = [identifier hash];
    
    // Define avatar size
    CGSize size = CGSizeMake(80, 80);
    
    // Begin drawing
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Use hash to create a unique but consistent color for this user
    UIColor *primaryColor;
    UIColor *secondaryColor;
    
    // Use a modulo operation to select one of several cyberpunk color schemes
    int colorScheme = hash % 5;
    
    switch (colorScheme) {
        case 0: // Neon green & blue
            primaryColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
            secondaryColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.9 alpha:1.0];
            break;
        case 1: // Purple & cyan
            primaryColor = [UIColor colorWithRed:0.6 green:0.0 blue:0.8 alpha:1.0];
            secondaryColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.8 alpha:1.0];
            break;
        case 2: // Red & orange
            primaryColor = [UIColor colorWithRed:0.9 green:0.1 blue:0.2 alpha:1.0];
            secondaryColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1.0];
            break;
        case 3: // Yellow & green
            primaryColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.0 alpha:1.0];
            secondaryColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.1 alpha:1.0];
            break;
        case 4: // Pink & blue
            primaryColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.5 alpha:1.0];
            secondaryColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.9 alpha:1.0];
            break;
        default:
            primaryColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
            secondaryColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.9 alpha:1.0];
    }
    
    // Draw gradient background
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[] = {0.0, 1.0};
    NSArray *colors = @[(__bridge id)primaryColor.CGColor, (__bridge id)secondaryColor.CGColor];
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, locations);
    
    CGPoint startPoint = CGPointMake(0, 0);
    CGPoint endPoint;
    
    // Use hash to create different gradient directions
    int gradientType = (hash / 10) % 4;
    switch (gradientType) {
        case 0:
            endPoint = CGPointMake(size.width, size.height); // Diagonal
            break;
        case 1:
            endPoint = CGPointMake(size.width, 0); // Horizontal
            break;
        case 2:
            endPoint = CGPointMake(0, size.height); // Vertical
            break;
        case 3:
            endPoint = CGPointMake(size.width / 2, size.height / 2); // Radial
            break;
        default:
            endPoint = CGPointMake(size.width, size.height);
    }
    
    // Draw circular background
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(0, 0, size.width, size.height));
    CGContextClip(context);
    
    if (gradientType == 3) {
        // Radial gradient
        CGFloat startRadius = 0;
        CGFloat endRadius = size.width / 1.5;
        CGContextDrawRadialGradient(context, gradient, CGPointMake(size.width/2, size.height/2), startRadius, 
                                  CGPointMake(size.width/2, size.height/2), endRadius, kCGGradientDrawsBeforeStartLocation);
    } else {
        // Linear gradient
        CGContextDrawLinearGradient(context, gradient, startPoint, endPoint, kCGGradientDrawsBeforeStartLocation);
    }
    CGContextRestoreGState(context);
    
    // Release gradient resources
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    // Use the hash to seed the random number generator for consistent but unique patterns
    srandom((unsigned int)hash);
    
    // Draw circuit board pattern
    CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.5].CGColor);
    CGContextSetLineWidth(context, 0.8);
    
    int patternType = hash % 3;
    
    if (patternType == 0) {
        // Circuit board pattern - horizontal and vertical lines with nodes
        int steps = 6 + (hash % 7); // Between 6 and 12 grid lines
        CGFloat stepSize = size.width / steps;
        
        for (int i = 1; i < steps; i++) {
            // Only draw some of the lines
            if (random() % 100 < 70) {
                // Horizontal line
                CGFloat y = i * stepSize;
                CGFloat startX = random() % (int)(size.width / 3);
                CGFloat endX = size.width - (random() % (int)(size.width / 3));
                
                CGContextMoveToPoint(context, startX, y);
                CGContextAddLineToPoint(context, endX, y);
                CGContextStrokePath(context);
                
                // Add node points along the line
                int nodes = 1 + (random() % 3);
                for (int n = 0; n < nodes; n++) {
                    CGFloat nodeX = startX + ((endX - startX) / (nodes + 1)) * (n + 1);
                    CGContextAddEllipseInRect(context, CGRectMake(nodeX - 2, y - 2, 4, 4));
                    CGContextFillPath(context);
                }
            }
            
            // Only draw some of the lines
            if (random() % 100 < 70) {
                // Vertical line
                CGFloat x = i * stepSize;
                CGFloat startY = random() % (int)(size.height / 3);
                CGFloat endY = size.height - (random() % (int)(size.height / 3));
                
                CGContextMoveToPoint(context, x, startY);
                CGContextAddLineToPoint(context, x, endY);
                CGContextStrokePath(context);
                
                // Add node points along the line
                int nodes = 1 + (random() % 2);
                for (int n = 0; n < nodes; n++) {
                    CGFloat nodeY = startY + ((endY - startY) / (nodes + 1)) * (n + 1);
                    CGContextAddEllipseInRect(context, CGRectMake(x - 2, nodeY - 2, 4, 4));
                    CGContextFillPath(context);
                }
            }
        }
    } else if (patternType == 1) {
        // Matrix-style falling code pattern
        CGFloat fontSize = 7.0;
        UIFont *digitFont = [UIFont fontWithName:@"Menlo" size:fontSize] ?: [UIFont systemFontOfSize:fontSize];
        
        for (int col = 0; col < 12; col++) {
            CGFloat x = 5 + col * (size.width - 10) / 12;
            int charCount = 4 + (random() % 5); // Between 4 and 8 characters per column
            
            for (int row = 0; row < charCount; row++) {
                CGFloat y = 5 + row * (size.height - 10) / 8;
                
                // Binary or hex character
                NSString *character;
                if (random() % 100 < 70) {
                    // Binary (more common)
                    character = (random() % 2 == 0) ? @"1" : @"0";
                } else {
                    // Hex (less common)
                    NSArray *hexChars = @[@"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"A", @"B", @"C", @"D", @"E", @"F"];
                    character = hexChars[random() % 16];
                }
                
                // Vary the opacity based on position (more transparent toward the bottom)
                CGFloat opacity = 1.0 - ((CGFloat)row / charCount * 0.7);
                
                NSDictionary *attrs = @{
                    NSFontAttributeName: digitFont,
                    NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:opacity]
                };
                
                [character drawAtPoint:CGPointMake(x, y) withAttributes:attrs];
            }
        }
    } else {
        // Cyberpunk geometric pattern
        for (int i = 0; i < 8; i++) {
            CGFloat x = random() % (int)size.width;
            CGFloat y = random() % (int)size.height;
            CGFloat width = 10 + (random() % 20);
            CGFloat height = 10 + (random() % 20);
            
            if (random() % 2 == 0) {
                // Rectangle
                CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.6].CGColor);
                CGContextSetLineWidth(context, 1.0);
                CGContextStrokeRect(context, CGRectMake(x, y, width, height));
            } else {
                // Circle
                CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.6].CGColor);
                CGContextSetLineWidth(context, 1.0);
                CGContextStrokeEllipseInRect(context, CGRectMake(x, y, width, width));
            }
        }
        
        // Add some connecting lines
        for (int i = 0; i < 15; i++) {
            CGFloat x1 = random() % (int)size.width;
            CGFloat y1 = random() % (int)size.height;
            CGFloat x2 = random() % (int)size.width;
            CGFloat y2 = random() % (int)size.height;
            
            CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor);
            CGContextSetLineWidth(context, 0.5);
            CGContextMoveToPoint(context, x1, y1);
            CGContextAddLineToPoint(context, x2, y2);
            CGContextStrokePath(context);
        }
    }
    
    // Add a central design element based on hash
    int centerElement = (hash / 100) % 4;
    CGFloat centerX = size.width / 2;
    CGFloat centerY = size.height / 2;
    
    switch (centerElement) {
        case 0: {
            // Concentric circles
            for (int i = 1; i <= 4; i++) {
                CGFloat radius = 10.0 * i;
                CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.7].CGColor);
                CGContextSetLineWidth(context, 1.5);
                CGContextAddEllipseInRect(context, CGRectMake(centerX - radius, centerY - radius, radius * 2, radius * 2));
                CGContextStrokePath(context);
            }
            break;
        }
        case 1: {
            // Star pattern
            CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.8].CGColor);
            CGContextSetLineWidth(context, 1.5);
            for (int i = 0; i < 8; i++) {
                CGFloat angle = (M_PI * 2.0 * i) / 8;
                CGFloat endX = centerX + cos(angle) * 30.0;
                CGFloat endY = centerY + sin(angle) * 30.0;
                
                CGContextMoveToPoint(context, centerX, centerY);
                CGContextAddLineToPoint(context, endX, endY);
                CGContextStrokePath(context);
            }
            break;
        }
        case 2: {
            // Hexagon
            CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.8].CGColor);
            CGContextSetLineWidth(context, 1.5);
            CGFloat radius = 25.0;
            
            CGContextMoveToPoint(context, centerX + radius, centerY);
            for (int i = 1; i <= 6; i++) {
                CGFloat angle = (M_PI * 2.0 * i) / 6;
                CGFloat x = centerX + cos(angle) * radius;
                CGFloat y = centerY + sin(angle) * radius;
                CGContextAddLineToPoint(context, x, y);
            }
                CGContextClosePath(context);
                CGContextStrokePath(context);
            break;
        }
        case 3: {
            // Cross-hairs
            CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] colorWithAlphaComponent:0.8].CGColor);
            CGContextSetLineWidth(context, 1.5);
            
            // Horizontal line
            CGContextMoveToPoint(context, centerX - 25, centerY);
            CGContextAddLineToPoint(context, centerX + 25, centerY);
            CGContextStrokePath(context);
            
            // Vertical line
            CGContextMoveToPoint(context, centerX, centerY - 25);
            CGContextAddLineToPoint(context, centerX, centerY + 25);
            CGContextStrokePath(context);
            
            // Circle
            CGContextAddEllipseInRect(context, CGRectMake(centerX - 15, centerY - 15, 30, 30));
            CGContextStrokePath(context);
            break;
        }
    }
    
    // Add scanline effect for a retro digital look
    CGContextSetFillColorWithColor(context, [[UIColor blackColor] colorWithAlphaComponent:0.1].CGColor);
    for (int y = 0; y < size.height; y += 4) {
        CGContextFillRect(context, CGRectMake(0, y, size.width, 1));
    }
    
    // Add edge glow effect
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(0, 0, size.width, size.height));
    CGContextClip(context);
    
    // Outer glow
    CGContextSetShadowWithColor(context, CGSizeZero, 5, primaryColor.CGColor);
    CGContextAddEllipseInRect(context, CGRectMake(2, 2, size.width - 4, size.height - 4));
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
    
    // Get the image
    UIImage *avatarImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return avatarImage;
}

// Helper method to get system information
- (NSString *)getSystemInfo {
    UIDevice *device = [UIDevice currentDevice];
    NSString *deviceName = device.name;
    NSString *systemName = device.systemName;
    NSString *systemVersion = device.systemVersion;
    NSString *systemModel = device.model;
    
    // Create formatted system info string (system only)
    NSString *systemInfo = [NSString stringWithFormat:@"%@ v%@ | %@ | %@", 
                            systemName, systemVersion, systemModel, deviceName];
    
    return systemInfo;
}

// New helper method to get app version information
- (NSString *)getAppVersionInfo {
    // Get app version and build number
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildNumber = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    
    // Create formatted app version string
    NSString *appVersionInfo = [NSString stringWithFormat:@"Version: %@ (Build %@)", appVersion, buildNumber];
    
    return appVersionInfo;
}

// New method for detecting system info with animation
- (void)detectAndDisplaySystemInfoWithAnimation {
    // Get system information
    UIDevice *device = [UIDevice currentDevice];
    NSString *deviceName = device.name;
    NSString *systemName = device.systemName;
    NSString *systemVersion = device.systemVersion;
    NSString *systemModel = device.model;
    
    // Create hacker-style system info string (without duplicating [SYS] prefix)
    NSString *fullSystemInfo = [NSString stringWithFormat:@"[SYS] %@ v%@ | %@ | %@", 
                              systemName, systemVersion, systemModel, deviceName];
    
    // Set initial text
    self.systemValueLabel.text = @"[SYS] Scanning...";
    
    // Create dispatch timer for animated typing effect (faster for cooler effect)
    __block NSInteger charIndex = 0;
    __block NSString *currentText = @"";
    
    // Create hackerish scanning display before showing the real info
    NSArray *scanningMessages = @[
        @"[SYS] Scanning system...",
        @"[SYS] Detecting OS version...",
        @"[SYS] Reading device info...",
        @"[SYS] Validating protocols..."
    ];
    
    // Start with scanning sequences
    __block NSInteger messageIndex = 0;
    __block NSTimer *scanTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
        self.systemValueLabel.text = scanningMessages[messageIndex];
        self.appVersionValueLabel.text = @"[APP] Loading...";
        messageIndex++;
        
        if (messageIndex >= scanningMessages.count) {
            [scanTimer invalidate];
            scanTimer = nil;
            
            // Start typing animation for final system info
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSTimer *typingTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer * _Nonnull timer) {
                    if (charIndex < fullSystemInfo.length) {
                        // Add one character at a time
                        unichar nextChar = [fullSystemInfo characterAtIndex:charIndex];
                        currentText = [currentText stringByAppendingString:[NSString stringWithCharacters:&nextChar length:1]];
                        self.systemValueLabel.text = currentText;
                        charIndex++;
                    } else {
                        // Done typing system info, now set app version
                        [timer invalidate];
                        
                        // Get app version with similar animation
                        NSString *appVersionInfo = [self getAppVersionInfo];
                        [self animateTypingForLabel:self.appVersionValueLabel withText:appVersionInfo];
                    }
                }];
                
                // Add timer to run loop
                [[NSRunLoop currentRunLoop] addTimer:typingTimer forMode:NSRunLoopCommonModes];
            });
        }
    }];
    
    // Add timer to run loop
    [[NSRunLoop currentRunLoop] addTimer:scanTimer forMode:NSRunLoopCommonModes];
}

// Helper method for typing animation
- (void)animateTypingForLabel:(UILabel *)label withText:(NSString *)text {
    __block NSInteger charIndex = 0;
    __block NSString *currentText = @"";
    
    NSTimer *typingTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (charIndex < text.length) {
            // Add one character at a time
            unichar nextChar = [text characterAtIndex:charIndex];
            currentText = [currentText stringByAppendingString:[NSString stringWithCharacters:&nextChar length:1]];
            label.text = currentText;
            charIndex++;
        } else {
            // Done typing
            [timer invalidate];
        }
    }];
    
    // Add timer to run loop
    [[NSRunLoop currentRunLoop] addTimer:typingTimer forMode:NSRunLoopCommonModes];
}

// Helper method to find the top-most view controller
- (UIViewController *)topMostViewController {
    UIViewController *topController = nil;
    
    // Get the appropriate window scene and window
    if (@available(iOS 13.0, *)) {
        // iOS 13+ scene-based approach
        UIWindow *keyWindow = nil;
        NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
        
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
                if (keyWindow) break;
            }
        }
        
        // If we found a key window, use its root view controller
        if (keyWindow) {
            topController = keyWindow.rootViewController;
        }
                } else {
        // iOS 12 and earlier - use deprecated API but with compiler warning suppressed
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        topController = [UIApplication sharedApplication].keyWindow.rootViewController;
        #pragma clang diagnostic pop
    }
    
    // If we couldn't find any window or root view controller, use self as a fallback
    if (!topController) {
        NSLog(@"[WeaponX] Warning: Could not find any key window or root view controller, using self");
        return self;
    }
    
    // Find the presented view controller
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    // Handle special cases for tab bar and navigation controllers
    if ([topController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)topController;
        UIViewController *selectedController = tabController.selectedViewController;
        if (selectedController) {
            topController = selectedController;
        }
    }
    
    if ([topController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)topController;
        UIViewController *visibleController = navController.visibleViewController;
        if (visibleController) {
            topController = visibleController;
        }
    }
    
    return topController;
}

#pragma mark - Alternative Logout Button

- (void)setupNavBarLogoutButton {
    // Only show the logout button if we're logged in
    if (self.authToken != nil) {
        // Create a custom button with adaptive styling
        UIButton *logoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [logoutButton setTitle:@"LOGOUT" forState:UIControlStateNormal];
        
        // Set color based on iOS version
        if (@available(iOS 13.0, *)) {
            [logoutButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        } else {
            [logoutButton setTitleColor:[UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0] forState:UIControlStateNormal];
        }
        
        // Use smaller font size for more minimalistic look
        logoutButton.titleLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont systemFontOfSize:12.0];
        [logoutButton addTarget:self action:@selector(navBarLogoutButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        
        // Make button background semi-transparent
        logoutButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.3];
        
        // Add rounded corners for modern look
        logoutButton.layer.cornerRadius = 12.0;
        logoutButton.clipsToBounds = YES;
        
        // Add subtle border
        logoutButton.layer.borderWidth = 1.0;
        if (@available(iOS 13.0, *)) {
            logoutButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.3 alpha:0.2].CGColor;
        } else {
            logoutButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.3 alpha:0.2].CGColor;
        }
        
        // Ensure the button is sized properly
        [logoutButton sizeToFit];
        
        // Add padding for better touch target but keep it compact
        CGRect frame = logoutButton.frame;
        frame.size.width += 16;
        frame.size.height = 24;
        logoutButton.frame = frame;
        
        // Create a bar button item with the button
        UIBarButtonItem *logoutBarButton = [[UIBarButtonItem alloc] initWithCustomView:logoutButton];
        self.navigationItem.rightBarButtonItem = logoutBarButton;
        
        NSLog(@"[WeaponX] Nav bar logout button added");
    } else {
        // Remove the button if not logged in
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)navBarLogoutButtonTapped {
    NSLog(@"[WeaponX] Nav bar logout button tapped");
    
    // Create alert controller
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Logout"
                                                                   message:@"Are you sure you want to logout?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    // Add cancel action
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Add logout action
    [alert addAction:[UIAlertAction actionWithTitle:@"Logout" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"[WeaponX] Nav bar logout confirmed");
        [self logoutButtonPressed];
    }]];
    
    // Present directly from self since we're in the navigation controller
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateTelegramTag:(NSString *)newTag {
    if (!self.authToken) {
        NSLog(@"[WeaponX] Cannot update Telegram tag: no auth token");
        return;
    }
    
    // Show loading indicator
    [self.activityIndicator startAnimating];
    
    // Call the TelegramManager to update the tag
    [[TelegramManager sharedManager] updateTelegramTag:self.authToken 
                                          telegramTag:newTag 
                                           completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Always hide loading indicator
            [self.activityIndicator stopAnimating];
            
            if (success) {
                // Update local user data
                NSMutableDictionary *updatedUserData = [self.userData mutableCopy];
                updatedUserData[@"telegram_tag"] = newTag;
                self.userData = [updatedUserData copy];
                
                // Save to user defaults
                [[NSUserDefaults standardUserDefaults] setObject:self.userData forKey:@"WeaponXUserInfo"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                
                // Update UI - this will also stop the TelegramUI activity indicator
                [self.telegramUI updateWithTelegramTag:newTag];
                
                // Show success feedback
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success" 
                                                                              message:@"Telegram username updated successfully"
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
                // Refresh user data from server to ensure everything is in sync
                [self refreshUserData];
            } else {
                // Stop the TelegramUI activity indicator in case of error
                [self.telegramUI updateWithTelegramTag:self.userData[@"telegram_tag"]];
                
                // Show error
                NSString *errorMessage = error ? error.localizedDescription : @"Failed to update Telegram username";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                              message:errorMessage
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

// Add method to generate placeholder avatar
- (void)generatePlaceholderAvatar {
    [self createHackerAvatar];
}

// Add a new method for creating a hacker-style avatar
- (void)createHackerAvatar {
    // Set a size for our avatar
    CGFloat size = 80.0;
    
    // Create a bitmap context for drawing
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), YES, 0.0);
    
    // Get drawing context
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        NSLog(@"[WeaponX] Failed to create graphics context");
        return;
    }
    
    // Fill background with dark color
    CGContextSetFillColorWithColor(context, [UIColor colorWithRed:0.05 green:0.1 blue:0.05 alpha:1.0].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, size, size));
    
    // Add "matrix rain" effect
    CGContextSetFillColorWithColor(context, [UIColor colorWithRed:0.0 green:0.9 blue:0.3 alpha:0.7].CGColor);
    
    // Use a fixed seed for consistent generation
    srand(42);
    
    // Draw binary-looking characters in columns
    CGFloat fontSize = 10.0;
    NSArray *binaryChars = @[@"0", @"1"];
    
    for (int col = 0; col < 10; col++) {
        CGFloat x = col * (size / 10.0) + (size / 20.0);
        
        for (int row = 0; row < 8; row++) {
            if (rand() % 3 > 0) { // 2/3 chance of drawing a character
                CGFloat y = row * (size / 8.0) + (size / 16.0);
                NSString *character = binaryChars[rand() % 2];
                
                // Vary the green intensity for "glowing" effect
                CGFloat greenIntensity = 0.5 + ((rand() % 50) / 100.0); // 0.5-1.0
                UIColor *charColor = [UIColor colorWithRed:0.0 
                                                    green:greenIntensity 
                                                     blue:0.2 
                                                    alpha:0.8];
                
                NSDictionary *attributes = @{
                    NSFontAttributeName: [UIFont fontWithName:@"Courier" size:fontSize] ?: [UIFont systemFontOfSize:fontSize],
                    NSForegroundColorAttributeName: charColor
                };
                
                [character drawAtPoint:CGPointMake(x, y) withAttributes:attributes];
            }
        }
    }
    
    // Draw circuit pattern
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8].CGColor);
    CGContextSetLineWidth(context, 1.0);
    
    // Center circuit node
    CGFloat centerX = size / 2.0;
    CGFloat centerY = size / 2.0;
    CGFloat nodeRadius = 4.0;
    
    // Draw the center node
    CGContextSetFillColorWithColor(context, [UIColor colorWithRed:0.0 green:1.0 blue:0.5 alpha:1.0].CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(centerX - nodeRadius, centerY - nodeRadius, 
                                                  nodeRadius * 2, nodeRadius * 2));
    
    // Add connecting lines
    int numLines = 6;
    for (int i = 0; i < numLines; i++) {
        CGFloat angle = (2.0 * M_PI * i) / numLines;
        CGFloat lineLength = 20.0 + (rand() % 15); // Random length
        
        CGFloat endX = centerX + cos(angle) * lineLength;
        CGFloat endY = centerY + sin(angle) * lineLength;
        
        // Draw line
        CGContextBeginPath(context);
        CGContextMoveToPoint(context, centerX, centerY);
        CGContextAddLineToPoint(context, endX, endY);
        CGContextStrokePath(context);
        
        // Draw endpoint node
        CGContextFillEllipseInRect(context, CGRectMake(endX - 2, endY - 2, 4, 4));
    }
    
    // Draw a shield outline
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:0.9].CGColor);
    CGContextSetLineWidth(context, 2.0);
    
    CGFloat shieldWidth = size * 0.7;
    CGFloat shieldHeight = size * 0.7;
    CGFloat shieldX = (size - shieldWidth) / 2.0;
    CGFloat shieldY = (size - shieldHeight) / 2.0;
    
    // Shield path
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, shieldX, shieldY + shieldHeight * 0.3);
    CGContextAddLineToPoint(context, shieldX, shieldY);
    CGContextAddLineToPoint(context, shieldX + shieldWidth, shieldY);
    CGContextAddLineToPoint(context, shieldX + shieldWidth, shieldY + shieldHeight * 0.3);
    CGContextAddCurveToPoint(context, 
                             shieldX + shieldWidth, shieldY + shieldHeight * 0.6,
                             shieldX + shieldWidth * 0.8, shieldY + shieldHeight,
                             shieldX + shieldWidth * 0.5, shieldY + shieldHeight);
    CGContextAddCurveToPoint(context, 
                             shieldX + shieldWidth * 0.2, shieldY + shieldHeight,
                             shieldX, shieldY + shieldHeight * 0.6,
                             shieldX, shieldY + shieldHeight * 0.3);
    CGContextStrokePath(context);
    
    // Get the image from the context
    UIImage *hackerAvatar = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // Set the avatar image
    dispatch_async(dispatch_get_main_queue(), ^{
        self.profileImageView.image = hackerAvatar;
        // Ensure visibility
        self.profileImageView.layer.borderWidth = 2.0;
        self.profileImageView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
        self.profileImageView.backgroundColor = [UIColor clearColor];
    });
}

// Add a method to update the plan countdown with animation
- (void)updatePlanCountdown {
    NSLog(@"[WeaponX] updatePlanCountdown called - redirecting to new mechanism");
    
    // Redirect to new plan button mechanism
    [self checkPlanStatusForButton];
}

// New method to update the countdown display based on days remaining
- (void)updateCountdownDisplay {
    // Check if plan is expired
    if (self.planDaysRemaining < 0) {
        self.daysRemainingLabel.text = @"PLAN EXPIRED";
        self.isGetPlanMode = NO;
        [self setupPulseAnimationForLabel:self.daysRemainingLabel];
        self.daysRemainingLabel.alpha = 1.0;
        return;
    }
    
    // Format large numbers appropriately
    if (self.planDaysRemaining > 365) {
        NSInteger years = self.planDaysRemaining / 365;
        NSInteger remainingDays = self.planDaysRemaining % 365;
        
        if (remainingDays > 0) {
            // Show years and days
            self.daysRemainingLabel.text = [NSString stringWithFormat:@"%ld YEAR%@ %ld DAY%@", 
                                          (long)years, years > 1 ? @"S" : @"",
                                          (long)remainingDays, remainingDays > 1 ? @"S" : @""];
        } else {
            // Just show years
            self.daysRemainingLabel.text = [NSString stringWithFormat:@"%ld YEAR%@ LEFT", 
                                          (long)years, years > 1 ? @"S" : @""];
        }
        self.isGetPlanMode = NO;
        [self setupPulseAnimationForLabel:self.daysRemainingLabel];
        self.daysRemainingLabel.alpha = 1.0;
    } else {
        // Start counting animation from 0 to actual days for shorter periods
        [self animateCountingDaysRemaining:self.planDaysRemaining];
    }
}

// Modified handleLoadingTimeout to use our new approach
- (void)handleLoadingTimeout {
    NSLog(@"[WeaponX] Loading timeout - checking plan data sources");
    self.loadingTimeoutTimer = nil;
    
    // Check if PlanSliderView has loaded plans
    if (self.planSliderView && self.planSliderView.plans.count == 0) {
        NSLog(@"[WeaponX] PlanSliderView has no plans after timeout, trying to reload");
        [self.planSliderView loadPlans];
    }
    
    // Check UserDefaults first
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *planName = [defaults objectForKey:@"UserPlanName"];
    NSDictionary *planData = [defaults objectForKey:@"WeaponXUserPlan"];
    NSString *planHash = [defaults objectForKey:@"WeaponXUserPlanHash"];
    
    // Check for inconsistent plan data
    BOOL hasInconsistentData = NO;
    
    // Case 1: We have a plan name but no actual plan data or hash
    if (planName && ![planName isEqualToString:@"NO_PLAN"] && 
       (!planData || !planHash)) {
        NSLog(@"[WeaponX] ⚠️ Inconsistent plan data detected in timeout handler: Have plan name but missing plan data or hash");
        hasInconsistentData = YES;
    }
    
    // Case 2: We have plan data but integrity check fails
    if (planData && planHash && ![APIManager sharedManager].verifyPlanDataIntegrity) {
        NSLog(@"[WeaponX] ⚠️ Inconsistent plan data detected in timeout handler: Integrity check failed");
        hasInconsistentData = YES;
    }
    
    // If inconsistency detected, clear all plan data
    if (hasInconsistentData) {
        NSLog(@"[WeaponX] 🧹 Clearing inconsistent plan data in timeout handler");
        
        // Clear everything plan-related
        [defaults setObject:@"NO_PLAN" forKey:@"UserPlanName"];
        [defaults removeObjectForKey:@"UserPlanExpiry"];
        [defaults removeObjectForKey:@"UserPlanDaysRemaining"];
        [defaults removeObjectForKey:@"WeaponXUserPlan"];
        [defaults removeObjectForKey:@"WeaponXUserPlanHash"];
        [defaults removeObjectForKey:@"WeaponXUserPlanTimestamp"];
        [defaults removeObjectForKey:@"PlanExpiryDate"];
        [defaults removeObjectForKey:@"PlanDaysRemaining"];
        [defaults synchronize];
        
        // Show "GET PLAN" instead of continuing with inconsistent data
        self.daysRemainingLabel.text = @"GET PLAN";
        self.isGetPlanMode = YES;
        [self setupPulseAnimationForLabel:self.daysRemainingLabel];
        self.daysRemainingLabel.alpha = 1.0;
        
        // Force a plan data refresh
        [self fetchPlanData];
        return;
    }
    
    // If we have a plan name in UserDefaults, refresh countdown
    if (planName && ![planName isEqualToString:@"NO_PLAN"]) {
        NSLog(@"[WeaponX] Found plan in UserDefaults after timeout: %@", planName);
        [self updatePlanCountdown];
        
        // Make sure the plan slider is visible if we have one
        if (self.planSliderView) {
            self.planSliderView.hidden = NO;
            [self.planSliderView setNeedsLayout];
            [self.planSliderView layoutIfNeeded];
            [self.contentView setNeedsLayout];
            [self.contentView layoutIfNeeded];
        }
        return;
    }
    
    // Check UI labels
    if (self.planValueLabel && self.planValueLabel.text && 
        ![self.planValueLabel.text isEqualToString:@"NO_PLAN"] &&
        ![self.planValueLabel.text isEqualToString:@"LOADING..."]) {
        
        NSLog(@"[WeaponX] Found plan in UI after timeout: %@", self.planValueLabel.text);
        [self updatePlanCountdown];
        return;
    }
    
    // If we still don't have plan data, show GET TRIAL
    NSLog(@"[WeaponX] No plan data found after timeout, showing GET TRIAL");
    
    // First check if user has a paid plan
    [[APIManager sharedManager] fetchUserPlanWithToken:self.authToken completion:^(NSDictionary *planData, NSError *error) {
        // Check if user has an active paid plan
        BOOL hasPaidPlan = NO;
        
        if (!error && planData) {
            // Try to extract plan data
            if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *plan = planData[@"plan"];
                
                // Check if plan is active and has a price > 0
                if (plan[@"price"]) {
                    float price = 0;
                    if ([plan[@"price"] isKindOfClass:[NSNumber class]]) {
                        price = [plan[@"price"] floatValue];
                    } else if ([plan[@"price"] isKindOfClass:[NSString class]]) {
                        price = [plan[@"price"] floatValue];
                    }
                    
                    if (price > 0) {
                        hasPaidPlan = YES;
                    }
                }
            }
        }
        
        if (hasPaidPlan) {
            // User has a paid plan, show "PAID PLAN ACTIVE" (not clickable)
            NSLog(@"[WeaponX] User has a paid plan, trial option not available");
            self.daysRemainingLabel.text = @"PAID PLAN ACTIVE";
            self.isGetPlanMode = NO; // Not clickable
            self.daysRemainingLabel.alpha = 0.7; // Dimmed appearance
            return;
        }
        
        // If user doesn't have a paid plan, check if they've used the trial
        [self checkTrialStatusWithCompletion:^(BOOL hasUsedTrial) {
            if (hasUsedTrial) {
                // User has already used trial, show CLAIMED
                NSLog(@"[WeaponX] User has already used trial, showing CLAIMED");
                self.daysRemainingLabel.text = @"CLAIMED";
                self.isGetPlanMode = YES; // Make clickable so user can see message
                self.daysRemainingLabel.alpha = 0.7; // Dimmed appearance
            } else {
                // User has not used trial, show GET TRIAL
                NSLog(@"[WeaponX] User has not used trial, showing GET TRIAL");
                self.daysRemainingLabel.text = @"GET TRIAL";
                self.isGetPlanMode = YES; // Clickable
                [self setupPulseAnimationForLabel:self.daysRemainingLabel];
                self.daysRemainingLabel.alpha = 1.0;
            }
        }];
    }];
}

// Helper method to setup pulse animation for the label
- (void)setupPulseAnimationForLabel:(UILabel *)label {
    CABasicAnimation *pulseAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulseAnimation.duration = 1.5;
    pulseAnimation.fromValue = @(1.0);
    pulseAnimation.toValue = @(0.6);
    pulseAnimation.autoreverses = YES;
    pulseAnimation.repeatCount = HUGE_VALF;
    pulseAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [label.layer addAnimation:pulseAnimation forKey:@"pulseAnimation"];
    
    // Also add a shadow glow animation
    CABasicAnimation *shadowAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    shadowAnimation.duration = 1.5;
    shadowAnimation.fromValue = @(0.8);
    shadowAnimation.toValue = @(0.2);
    shadowAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    shadowAnimation.autoreverses = YES;
    shadowAnimation.repeatCount = HUGE_VALF;
    
    [label.layer addAnimation:shadowAnimation forKey:@"shadowAnimation"];
}

// Helper method to animate counting from 0 to days remaining
- (void)animateCountingDaysRemaining:(NSInteger)daysRemaining {
    // Starting value
    __block int currentCount = 0;
    
    // Make the label visible
    self.daysRemainingLabel.alpha = 1.0;
    
    // Setup timer for counting animation
    NSTimeInterval animationDuration = 1.5; // Total animation time
    NSTimeInterval interval = animationDuration / MIN(daysRemaining, 30); // Cap at 30 steps max
    
    // Calculate step size to avoid too many updates for large numbers
    int stepSize = daysRemaining > 30 ? MAX(1, daysRemaining / 30) : 1;
    
    // Setup timer
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        currentCount += stepSize;
        
        if (currentCount >= daysRemaining) {
            // Final value
            currentCount = daysRemaining;
            [timer invalidate];
            
            // Show the final text and start the subtle glow animation
            self.daysRemainingLabel.text = [NSString stringWithFormat:@"%ld DAYS REMAINING", (long)daysRemaining];
            [self setupPulseAnimationForLabel:self.daysRemainingLabel];
        } else {
            // Update with current count during animation
            self.daysRemainingLabel.text = [NSString stringWithFormat:@"%d DAYS REMAINING", currentCount];
        }
    }];
    
    // Start the timer
    [timer fire];
}

// Add the tap handler method
- (void)daysRemainingLabelTapped {
    NSLog(@"[WeaponX] Plan button tapped: %@", self.daysRemainingLabel.text);
    
    // Highlight effect
    [UIView animateWithDuration:0.1 animations:^{
        self.daysRemainingLabel.transform = CGAffineTransformMakeScale(0.95, 0.95);
        self.daysRemainingLabel.alpha = 0.8;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            self.daysRemainingLabel.transform = CGAffineTransformIdentity;
            self.daysRemainingLabel.alpha = 1.0;
        }];
    }];
    
    // Check the current state of the button
    NSString *labelText = self.daysRemainingLabel.text;
    
    // Handle different states
    if ([labelText isEqualToString:@"GET TRIAL"]) {
        // User wants to get a trial
        // Add a small delay to prevent accidental taps
        [self.daysRemainingLabel setUserInteractionEnabled:NO]; // Disable interaction during delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showTrialPlanOption];
            [self.daysRemainingLabel setUserInteractionEnabled:YES]; // Re-enable interaction
        });
    } 
    else if ([labelText isEqualToString:@"CLAIMED"]) {
        // User has already used a trial, show message about premium plans
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Trial Already Claimed"
                                                                      message:@"You have already claimed your free trial. Please check the plan options at the bottom of the Account tab to upgrade to a premium plan for continued access."
                                                               preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" 
                                                style:UIAlertActionStyleDefault 
                                              handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
    else if ([labelText isEqualToString:@"GET PLAN"]) {
        // User needs to get a plan - show paid plans options
        [self showPaidPlansOptions];
    }
    else if ([labelText containsString:@"DAYS REMAINING"] || 
             [labelText containsString:@"DAY REMAINING"] ||
             [labelText containsString:@"ACTIVE"] ||
             [labelText containsString:@"YEAR"]) {
        // User has an active plan, show details
        // Extract the days remaining for the animation
        NSInteger daysRemaining = 0;
        
        // Try to parse days from the label text
        if ([labelText containsString:@"DAYS REMAINING"]) {
            NSScanner *scanner = [NSScanner scannerWithString:labelText];
            [scanner scanInteger:&daysRemaining];
        } else if ([labelText containsString:@"DAY REMAINING"]) {
            daysRemaining = 1;
        }
        
        // Create initial message without the counter
        NSString *baseMessage = @"You have an active plan with %@ remaining. Extend your subscription for better price and premium support!";
        
        // Create the alert with initial text
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Active Plan" 
                                                                      message:[NSString stringWithFormat:baseMessage, @"0 days"]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Extend Subscription" 
                                                style:UIAlertActionStyleDefault 
                                              handler:^(UIAlertAction * _Nonnull action) {
            // Open the support tab instead of plan slider
            [self supportButtonTapped];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" 
                                                style:UIAlertActionStyleCancel 
                                              handler:nil]];
        
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            alert.popoverPresentationController.sourceView = self.daysRemainingLabel;
            alert.popoverPresentationController.sourceRect = self.daysRemainingLabel.bounds;
        }
        
        [self presentViewController:alert animated:YES completion:^{
            // Run the counting animation after the alert is presented
            if (daysRemaining > 0) {
                // Start counting animation
                __block NSInteger currentCount = 0;
                NSTimeInterval interval = 0.05; // Update interval
                
                // Calculate step size to avoid too many updates for large numbers
                NSInteger stepSize = daysRemaining > 50 ? MAX(1, daysRemaining / 50) : 1;
                
                // Setup timer for the counting animation
                NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
                    currentCount += stepSize;
                    
                    if (currentCount >= daysRemaining) {
                        // Final value
                        currentCount = daysRemaining;
                        [timer invalidate];
                    }
                    
                    // Update the alert message
                    NSString *countText = [NSString stringWithFormat:@"%ld day%@",
                                          (long)currentCount,
                                          currentCount == 1 ? @"" : @"s"];
                    
                    alert.message = [NSString stringWithFormat:baseMessage, countText];
                }];
                
                // Start the timer
                [timer fire];
            }
        }];
    }
}

- (void)showTrialPlanOption {
    // First check if the user already has a paid plan
    [[APIManager sharedManager] fetchUserPlanWithToken:self.authToken completion:^(NSDictionary *planData, NSError *error) {
        if (!error && planData) {
            // Check if user has an active paid plan
            BOOL hasPaidPlan = NO;
            NSNumber *planPrice = nil;
            
            // Try to extract plan data
            if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *plan = planData[@"plan"];
                
                // Check if plan is active and has a price > 0
                if (plan[@"price"] && [plan[@"price"] isKindOfClass:[NSNumber class]]) {
                    planPrice = plan[@"price"];
                    if ([planPrice floatValue] > 0) {
                        hasPaidPlan = YES;
                    }
                } else if (plan[@"price"] && [plan[@"price"] isKindOfClass:[NSString class]]) {
                    // Handle if price is a string
                    float price = [plan[@"price"] floatValue];
                    if (price > 0) {
                        hasPaidPlan = YES;
                    }
                }
            }
            
            if (hasPaidPlan) {
                // User already has a paid plan, don't allow trial
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Downgrade"
                                                                                  message:@"You already have a paid plan. Downgrading to a trial is not allowed."
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                    
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" 
                                                            style:UIAlertActionStyleDefault 
                                                          handler:nil]];
                    
                    [self presentViewController:alert animated:YES completion:nil];
                });
                return;
            }
        }
        
        // Continue with the original trial status check
        [self checkTrialStatusWithCompletion:^(BOOL hasUsedTrial) {
            if (hasUsedTrial) {
                // User has already used their trial, show simple message and don't offer to show paid plans
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Trial Already Claimed"
                                                                               message:@"You have already claimed your free trial. Please check the plan options at the bottom of the Account tab to upgrade to a premium plan for continued access."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" 
                                                         style:UIAlertActionStyleDefault 
                                                       handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                // User hasn't used their trial, show trial plan option
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Free Trial Plan"
                                                                              message:@"Get a free trial to experience our premium features."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction actionWithTitle:@"Claim Free Trial" 
                                                        style:UIAlertActionStyleDefault 
                                                      handler:^(UIAlertAction * _Nonnull action) {
                    [self upgradeToPlanWithID:@"1"]; // Plan ID 1 is the trial plan
                }]];
                
                [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                                        style:UIAlertActionStyleCancel 
                                                      handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        }];
    }];
}

// Add method to check if user has used their trial
- (void)checkTrialStatusWithCompletion:(void (^)(BOOL hasUsedTrial))completion {
    // First check if we have cached trial status in UserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id cachedTrialStatus = [defaults objectForKey:@"UserHasUsedTrial"];
    
    if (cachedTrialStatus != nil) {
        BOOL hasUsedTrial = [cachedTrialStatus boolValue];
        NSLog(@"[WeaponX] Using cached trial status: %@", hasUsedTrial ? @"Has used trial" : @"Has not used trial");
        
        // Check if this cached value is reliable - if it's older than 1 hour, refresh it
        NSDate *lastTrialCheck = [defaults objectForKey:@"LastTrialStatusCheck"];
        if (lastTrialCheck && [[NSDate date] timeIntervalSinceDate:lastTrialCheck] < 3600) {
            NSLog(@"[WeaponX] Cached trial status is recent, using it");
            completion(hasUsedTrial);
            return;
        } else {
            NSLog(@"[WeaponX] Cached trial status is old or missing timestamp, refreshing from server");
        }
    }
    
    // Call API to check if the user has already used their trial
    [[APIManager sharedManager] fetchUserPlanWithToken:self.authToken completion:^(NSDictionary *planData, NSError *error) {
        BOOL hasUsedTrial = NO;
        NSLog(@"[WeaponX] Received plan data for trial check: %@", planData);
        
        if (!error && planData) {
            // Check all possible paths where trial status could be stored in the response
            if ([planData objectForKey:@"has_used_trial"] != nil) {
                hasUsedTrial = [planData[@"has_used_trial"] boolValue];
                NSLog(@"[WeaponX] Found has_used_trial directly in response: %@", hasUsedTrial ? @"YES" : @"NO");
            } else if ([planData objectForKey:@"trial_used"] != nil) {
                hasUsedTrial = [planData[@"trial_used"] boolValue];
                NSLog(@"[WeaponX] Found trial_used in response: %@", hasUsedTrial ? @"YES" : @"NO");
            } else if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
                if ([planData[@"plan"] objectForKey:@"has_used_trial"] != nil) {
                    hasUsedTrial = [planData[@"plan"][@"has_used_trial"] boolValue];
                    NSLog(@"[WeaponX] Found has_used_trial in plan object: %@", hasUsedTrial ? @"YES" : @"NO");
                } else if ([planData[@"plan"] objectForKey:@"trial_used"] != nil) {
                    hasUsedTrial = [planData[@"plan"][@"trial_used"] boolValue];
                    NSLog(@"[WeaponX] Found trial_used in plan object: %@", hasUsedTrial ? @"YES" : @"NO");
                } else if ([planData[@"plan"][@"id"] isEqual:@(1)] || [planData[@"plan"][@"id"] isEqual:@"1"]) {
                    // If current plan ID is 1 (trial plan), they have a trial
                    hasUsedTrial = YES;
                    NSLog(@"[WeaponX] Current plan is trial plan (ID: 1), so marking as having used trial");
                } else if ([planData[@"plan"] objectForKey:@"is_trial"] != nil && [planData[@"plan"][@"is_trial"] boolValue]) {
                    // If current plan is marked as a trial, they have used trial
                    hasUsedTrial = YES;
                    NSLog(@"[WeaponX] Current plan is marked as trial, so marking as having used trial");
                }
            }
            
            // Store result in UserDefaults for future use
            [defaults setBool:hasUsedTrial forKey:@"UserHasUsedTrial"];
            [defaults setObject:[NSDate date] forKey:@"LastTrialStatusCheck"];
            [defaults synchronize];
            
            NSLog(@"[WeaponX] User trial status check: %@", hasUsedTrial ? @"Has used trial" : @"Has not used trial");
        } else {
            NSLog(@"[WeaponX] Failed to check trial status: %@", error.localizedDescription ?: @"Unknown error");
            // Use cached value if available, otherwise default to not used
            if (cachedTrialStatus != nil) {
                hasUsedTrial = [cachedTrialStatus boolValue];
                NSLog(@"[WeaponX] Using cached trial status due to error: %@", hasUsedTrial ? @"Has used trial" : @"Has not used trial");
            } else {
                hasUsedTrial = NO;
                NSLog(@"[WeaponX] Defaulting to 'not used trial' due to error and no cached status");
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(hasUsedTrial);
        });
    }];
}

// Add method to show paid plans options
- (void)showPaidPlansOptions {
    // Show message about getting a subscription plan
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Subscription Required" 
                                                                  message:@"GET ANY SUBSCRIPTION PLAN BELOW TO START USING PROJECT X APP FEATURES" 
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" 
                                            style:UIAlertActionStyleDefault 
                                          handler:^(UIAlertAction * _Nonnull action) {
        // Scroll to plan section to show available plans
        if (self.planSliderView) {
            [self.scrollView setContentOffset:CGPointMake(0, self.planSliderView.frame.origin.y - 50) animated:YES];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Update the upgradeToPlanWithID method to handle the specific plan upgrade
- (void)upgradeToPlanWithID:(NSString *)planID {
    // Show loading indicator
    [self.activityIndicator startAnimating];
    
    // Call API to purchase the plan
    [[APIManager sharedManager] purchasePlanWithToken:self.authToken planId:planID completion:^(BOOL success, NSError *error) {
        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            // Stop loading indicator
            [self.activityIndicator stopAnimating];
            
            if (success) {
                // Show success message
                NSString *message = [planID isEqualToString:@"1"] ? 
                    @"You have successfully activated your free trial." : 
                    @"You have successfully purchased the plan.";
                
                UIAlertController *alert = [UIAlertController 
                                           alertControllerWithTitle:@"Success" 
                                           message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
                [alert addAction:[UIAlertAction 
                                 actionWithTitle:@"OK" 
                                 style:UIAlertActionStyleDefault 
                                 handler:^(UIAlertAction * _Nonnull action) {
                                     // Refresh user data to update the plan display
                                     [self refreshUserData];
                                 }]];
                
                [self presentViewController:alert animated:YES completion:nil];
                
            } else {
                // Show error message
                UIAlertController *alert = [UIAlertController 
                                           alertControllerWithTitle:@"Error" 
                                           message:error.localizedDescription ?: @"Unable to complete purchase. Please try again."
                                           preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                                 actionWithTitle:@"OK" 
                                             style:UIAlertActionStyleDefault 
                                           handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

// Add a method to clear the loading state after timeout
- (void)setupLoadingTimeout {
    // Cancel any existing timer
    if (self.loadingTimeoutTimer) {
        [self.loadingTimeoutTimer invalidate];
        self.loadingTimeoutTimer = nil;
    }
    
    // Create a new timer for 3 seconds
    self.loadingTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 
                                                             target:self 
                                                           selector:@selector(handleLoadingTimeout) 
                                                           userInfo:nil 
                                                            repeats:NO];
}

#pragma mark - Plan Slider Setup

- (void)setupPlanSlider {
    NSLog(@"[WeaponX] Setting up PlanSliderView");
    
    // Remove existing plan slider if any
    if (self.planSliderView) {
        [self.planSliderView removeFromSuperview];
        self.planSliderView = nil;
    }
    
    // Create a container view for the device UUID display
    UIView *uuidContainer = [[UIView alloc] init];
    uuidContainer.translatesAutoresizingMaskIntoConstraints = NO;
    uuidContainer.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:uuidContainer];
    
    // Create UUID label with copy instruction
    UILabel *uuidTitleLabel = [[UILabel alloc] init];
    uuidTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    uuidTitleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0];
    
    // Use SF Symbol for Apple logo if available, otherwise use Unicode Apple symbol
    if (@available(iOS 13.0, *)) {
        // Create attachment for SF Symbol image
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        UIImage *appleImage = [UIImage systemImageNamed:@"applelogo"];
        if (appleImage) {
            // Create a configuration with appropriate size
            UIImage *resizedAppleLogo = nil;
            
            if (@available(iOS 13.0, *)) {
                UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium scale:UIImageSymbolScaleMedium];
                resizedAppleLogo = [appleImage imageWithConfiguration:configuration];
                
                // If we have system support for SF Symbol tinting, use it
                if (@available(iOS 13.0, *)) {
                    // Apply tint color to match the brand
                    UIColor *appleTint = [UIColor blackColor];
                    resizedAppleLogo = [resizedAppleLogo imageWithTintColor:appleTint renderingMode:UIImageRenderingModeAlwaysOriginal];
                }
            } else {
                // Fallback for images that don't support configuration
                resizedAppleLogo = appleImage;
            }
            
            attachment.image = resizedAppleLogo;
            
            // Adjust bounds to align with text (vertically centered)
            CGFloat capHeight = uuidTitleLabel.font.capHeight;
            CGFloat yOffset = (capHeight - resizedAppleLogo.size.height) / 2.0 - 2.0; // Fine-tune vertical alignment
            attachment.bounds = CGRectMake(0, yOffset, resizedAppleLogo.size.width, resizedAppleLogo.size.height);
            
            // Create attributed string with the image
            NSAttributedString *attachmentString = [NSAttributedString attributedStringWithAttachment:attachment];
            
            // Add a space before the Apple logo for better spacing
            NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:@"CURRENT DEVICE ID  "];
            [attributedText appendAttributedString:attachmentString];
            uuidTitleLabel.attributedText = attributedText;
        } else {
            // Fallback to Unicode apple symbol if SF Symbol not available
            uuidTitleLabel.text = @"CURRENT DEVICE ID 🍎";
        }
    } else {
        // Use Unicode apple symbol for older iOS versions
        uuidTitleLabel.text = @"CURRENT DEVICE ID ";
    }
    
    // Set color based on interface style
    if (@available(iOS 13.0, *)) {
        uuidTitleLabel.textColor = [UIColor labelColor];
    } else {
        uuidTitleLabel.textColor = [UIColor darkTextColor];
    }
    
    [uuidContainer addSubview:uuidTitleLabel];
    
    // Create UUID value label
    self.deviceUuidLabel = [[UILabel alloc] init];
    self.deviceUuidLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceUuidLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont systemFontOfSize:12.0];
    self.deviceUuidLabel.text = [self getDeviceUUID];
    self.deviceUuidLabel.textAlignment = NSTextAlignmentCenter;
    self.deviceUuidLabel.numberOfLines = 0;
    self.deviceUuidLabel.lineBreakMode = NSLineBreakByWordWrapping;
    
    // Set background color and styling to make it look like a button
    self.deviceUuidLabel.layer.cornerRadius = 6.0;
    self.deviceUuidLabel.layer.borderWidth = 1.0;
    self.deviceUuidLabel.clipsToBounds = YES;
    
    // Style based on interface
    if (@available(iOS 13.0, *)) {
        self.deviceUuidLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.deviceUuidLabel.textColor = [UIColor systemBlueColor];
        self.deviceUuidLabel.layer.borderColor = [UIColor systemBlueColor].CGColor;
    } else {
        self.deviceUuidLabel.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        self.deviceUuidLabel.textColor = [UIColor blueColor];
        self.deviceUuidLabel.layer.borderColor = [UIColor blueColor].CGColor;
    }
    
    // Add padding for better tap target
    self.deviceUuidLabel.userInteractionEnabled = YES;
    
    // Add tap gesture
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(deviceUuidLabelTapped:)];
    [self.deviceUuidLabel addGestureRecognizer:tapGesture];
    
    [uuidContainer addSubview:self.deviceUuidLabel];
    
    // Add constraints for UUID container elements
    [NSLayoutConstraint activateConstraints:@[
        [uuidTitleLabel.topAnchor constraintEqualToAnchor:uuidContainer.topAnchor constant:8.0],
        [uuidTitleLabel.leadingAnchor constraintEqualToAnchor:uuidContainer.leadingAnchor constant:15.0],
        [uuidTitleLabel.trailingAnchor constraintEqualToAnchor:uuidContainer.trailingAnchor constant:-15.0],
        
        [self.deviceUuidLabel.topAnchor constraintEqualToAnchor:uuidTitleLabel.bottomAnchor constant:8.0],
        [self.deviceUuidLabel.leadingAnchor constraintEqualToAnchor:uuidContainer.leadingAnchor constant:15.0],
        [self.deviceUuidLabel.trailingAnchor constraintEqualToAnchor:uuidContainer.trailingAnchor constant:-15.0],
        [self.deviceUuidLabel.heightAnchor constraintGreaterThanOrEqualToConstant:40.0]
    ]];
    
    // Add "MANAGE DEVICES" button
    self.manageDevicesButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.manageDevicesButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Set button title with all caps and appropriate font
    [self.manageDevicesButton setTitle:@"MANAGE DEVICES" forState:UIControlStateNormal];
    self.manageDevicesButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0];
    
    // Set button styling to match the application design
    self.manageDevicesButton.backgroundColor = [UIColor systemBlueColor];
    [self.manageDevicesButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.manageDevicesButton.layer.cornerRadius = 8.0;
    self.manageDevicesButton.clipsToBounds = YES;
    
    // Add button action
    [self.manageDevicesButton addTarget:self action:@selector(manageDevicesButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Add button to container
    [uuidContainer addSubview:self.manageDevicesButton];
    
    // Add constraints for the button
    [NSLayoutConstraint activateConstraints:@[
        [self.manageDevicesButton.topAnchor constraintEqualToAnchor:self.deviceUuidLabel.bottomAnchor constant:15.0],
        [self.manageDevicesButton.leadingAnchor constraintEqualToAnchor:uuidContainer.leadingAnchor constant:15.0],
        [self.manageDevicesButton.trailingAnchor constraintEqualToAnchor:uuidContainer.trailingAnchor constant:-15.0],
        [self.manageDevicesButton.bottomAnchor constraintEqualToAnchor:uuidContainer.bottomAnchor constant:-8.0],
        [self.manageDevicesButton.heightAnchor constraintEqualToConstant:44.0]
    ]];
    
    // Create a container view for the subscription plans section
    UIView *plansContainer = [[UIView alloc] init];
    plansContainer.translatesAutoresizingMaskIntoConstraints = NO;
    plansContainer.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:plansContainer];
    
    // Create a more prominent separator
    UIView *separatorLine = [[UIView alloc] init];
    separatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    separatorLine.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5]; // Subtle gray line
    [plansContainer addSubview:separatorLine];
    
    // Create new plan slider view
    self.planSliderView = [[PlanSliderView alloc] initWithFrame:CGRectZero authToken:self.authToken];
    self.planSliderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.planSliderView.delegate = self;
    
    // Add the plan slider to our container
    [plansContainer addSubview:self.planSliderView];
    
    // Add constraints for the containers - positioning UUID container after userInfoCard and plans container after UUID container
    [NSLayoutConstraint activateConstraints:@[
        // Position UUID container after userInfoCard
        [uuidContainer.topAnchor constraintEqualToAnchor:self.userInfoCard.bottomAnchor constant:20.0],
        [uuidContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [uuidContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        
        // Position plans container after UUID container
        [plansContainer.topAnchor constraintEqualToAnchor:uuidContainer.bottomAnchor constant:30.0],
        [plansContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [plansContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        
        // Make content view's bottom constraint depend on plansContainer
        [self.contentView.bottomAnchor constraintEqualToAnchor:plansContainer.bottomAnchor constant:50.0]
    ]];
    
    // Add constraints for separator line
    [NSLayoutConstraint activateConstraints:@[
        [separatorLine.topAnchor constraintEqualToAnchor:plansContainer.topAnchor],
        [separatorLine.leadingAnchor constraintEqualToAnchor:plansContainer.leadingAnchor constant:20.0],
        [separatorLine.trailingAnchor constraintEqualToAnchor:plansContainer.trailingAnchor constant:-20.0],
        [separatorLine.heightAnchor constraintEqualToConstant:1.0]
    ]];
    
    // Add constraints for plan slider - with good spacing below separator
    [NSLayoutConstraint activateConstraints:@[
        // Position below separator line with good spacing
        [self.planSliderView.topAnchor constraintEqualToAnchor:separatorLine.bottomAnchor constant:30.0],
        [self.planSliderView.leadingAnchor constraintEqualToAnchor:plansContainer.leadingAnchor],
        [self.planSliderView.trailingAnchor constraintEqualToAnchor:plansContainer.trailingAnchor],
        [self.planSliderView.heightAnchor constraintEqualToConstant:[self.planSliderView getContentHeight]]
    ]];
    
    // Create "Want more Devices" label
    UILabel *moreDevicesLabel = [[UILabel alloc] init];
    moreDevicesLabel.translatesAutoresizingMaskIntoConstraints = NO;
    moreDevicesLabel.text = @"Want more Devices? -> Raise Ticket By Contact Support";
    moreDevicesLabel.textAlignment = NSTextAlignmentCenter;
    moreDevicesLabel.textColor = [UIColor systemGreenColor];
    moreDevicesLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [plansContainer addSubview:moreDevicesLabel];
    
    // Position the label below plan slider
    [NSLayoutConstraint activateConstraints:@[
        [moreDevicesLabel.topAnchor constraintEqualToAnchor:self.planSliderView.bottomAnchor constant:15.0],
        [moreDevicesLabel.leadingAnchor constraintEqualToAnchor:plansContainer.leadingAnchor constant:20.0],
        [moreDevicesLabel.trailingAnchor constraintEqualToAnchor:plansContainer.trailingAnchor constant:-20.0],
        [plansContainer.bottomAnchor constraintEqualToAnchor:moreDevicesLabel.bottomAnchor constant:10.0]
    ]];
    
    // Add decorative lines at the bottom of the account tab
    
    // Add decorative lines at the bottom of the account tab
    // Create container for the decorative lines
    UIView *decorativeLinesContainer = [[UIView alloc] init];
    decorativeLinesContainer.translatesAutoresizingMaskIntoConstraints = NO;
    decorativeLinesContainer.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:decorativeLinesContainer];
    
    // Create the decorative lines (5 lines with decreasing length)
    NSMutableArray *decorativeLines = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        UIView *line = [[UIView alloc] init];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        line.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.7]; // Neon green
        line.layer.cornerRadius = 1.0;
        line.layer.masksToBounds = YES;
        [decorativeLinesContainer addSubview:line];
        [decorativeLines addObject:line];
    }
    
    // Add constraints for the decorative lines container
    [NSLayoutConstraint activateConstraints:@[
        [decorativeLinesContainer.topAnchor constraintEqualToAnchor:plansContainer.bottomAnchor constant:30.0],
        [decorativeLinesContainer.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [decorativeLinesContainer.widthAnchor constraintEqualToConstant:600], // Width enough for the longest line
        [decorativeLinesContainer.heightAnchor constraintEqualToConstant:80], // Height for all the lines
        [self.contentView.bottomAnchor constraintEqualToAnchor:decorativeLinesContainer.bottomAnchor constant:40.0] // Update bottom constraint
    ]];
    
    // Calculate the line widths (decreasing from longest to shortest)
    CGFloat baseWidth = 500.0;
    CGFloat widthDecrement = 70.0;
    
    // Add constraints for each line
    for (int i = 0; i < decorativeLines.count; i++) {
        UIView *line = decorativeLines[i];
        CGFloat lineWidth = baseWidth - (i * widthDecrement);
        
        [NSLayoutConstraint activateConstraints:@[
            [line.centerXAnchor constraintEqualToAnchor:decorativeLinesContainer.centerXAnchor],
            [line.topAnchor constraintEqualToAnchor:decorativeLinesContainer.topAnchor constant:i * 12.0], // Space between lines
            [line.widthAnchor constraintEqualToConstant:lineWidth],
            [line.heightAnchor constraintEqualToConstant:2.0] // Line height
        ]];
    }
    
    // Force layout update to ensure proper positioning
    [self.contentView setNeedsLayout];
    [self.contentView layoutIfNeeded];
    
    // Ensure scroll view updates its content size
    [self updateScrollViewContentSize];
    
    // Setup a loading timeout to ensure we eventually display content
    [self setupLoadingTimeout];
    
    // Load plans immediately
    NSLog(@"[WeaponX] PlanSliderView requesting to load plans with token: %@", self.authToken);
    [self.planSliderView loadPlans];
}

// Add this new method to ensure scroll view content size is updated correctly
- (void)updateScrollViewContentSize {
    // Ensure the view has been laid out
    [self.view layoutIfNeeded];
    
    // Get the height of the content view considering all of its subviews
    CGFloat contentHeight = 0;
    
    // Find the bottom-most element in the content view
    for (UIView *subview in self.contentView.subviews) {
        CGFloat subviewMaxY = CGRectGetMaxY(subview.frame);
        if (subviewMaxY > contentHeight) {
            contentHeight = subviewMaxY;
        }
    }
    
    // Add padding at the bottom
    contentHeight += 40.0;
    
    // Ensure the scroll view's content size is at least the height of the screen
    CGFloat screenHeight = UIScreen.mainScreen.bounds.size.height;
    contentHeight = MAX(contentHeight, screenHeight);
    
    // Set the content size of the scroll view
    self.scrollView.contentSize = CGSizeMake(self.scrollView.frame.size.width, contentHeight);
    
    // We'll move the update icon code to a separate method
    // that's called only once during initialization
}

// Add a new method to set up the update icon only once
- (void)setupUpdateIcon {
    // App update functionality removed
    return;
}

- (void)checkForUpdatesManually {
    // App update functionality removed
    return;
}

- (void)displayUpdateDetails:(NSDictionary *)updateInfo {
    // App update functionality removed
    return;
}

- (void)downloadAndUpdate:(id)sender {
    // App update functionality removed
    return;
}

- (void)checkForUpdates {
    // App update functionality removed
    return;
}

- (void)downloadUpdateButtonTapped:(id)sender {
    // App update functionality removed
    return;
}

#pragma mark - Plan Slider Update

- (void)updatePlanSlider {
    if (self.isLoggedIn && self.authToken) {
        if (!self.planSliderView) {
            [self setupPlanSlider];
        } else {
            // Refresh existing plan slider with current authToken
            self.planSliderView.authToken = self.authToken;
            
            // Force visibility and reload
            self.planSliderView.hidden = NO;
            [self setupLoadingTimeout];
            [self.planSliderView loadPlans];
            
            // Force layout update
            [self.planSliderView setNeedsLayout];
            [self.contentView setNeedsLayout];
        }
    } else if (self.planSliderView) {
        // Remove plan slider if user is not logged in
        [self.planSliderView removeFromSuperview];
        self.planSliderView = nil;
    }
}

#pragma mark - PlanSliderViewDelegate Methods

- (void)planSliderView:(PlanSliderView *)sliderView didSelectPlan:(NSDictionary *)plan {
    // Handle plan selection - e.g., show plan details
    NSLog(@"Plan selected: %@", plan[@"name"]);
    
    // Create alert with plan details
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:plan[@"name"]
                               message:[NSString stringWithFormat:@"%@\n\nPrice: %@", 
                                       plan[@"description"], 
                                       plan[@"price"]]
                               preferredStyle:UIAlertControllerStyleAlert];
    
    // Add purchase action
    [alert addAction:[UIAlertAction 
                     actionWithTitle:@"Purchase" 
                     style:UIAlertActionStyleDefault 
                     handler:^(UIAlertAction * _Nonnull action) {
                         [self purchasePlan:plan];
                     }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction 
                     actionWithTitle:@"Cancel" 
                     style:UIAlertActionStyleCancel 
                     handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)planSliderView:(PlanSliderView *)sliderView didPurchasePlan:(NSDictionary *)plan {
    // Handle plan purchase
    [self purchasePlan:plan];
}

- (void)purchasePlan:(NSDictionary *)plan {
    // Check if this is already the current plan
    NSString *currentPlanName = [[NSUserDefaults standardUserDefaults] objectForKey:@"UserPlanName"];
    if (currentPlanName && [currentPlanName isEqualToString:plan[@"name"]]) {
        // Already subscribed to this plan
        UIAlertController *alert = [UIAlertController 
                                   alertControllerWithTitle:@"Current Plan" 
                                   message:@"You are already subscribed to this plan."
                                   preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
                         actionWithTitle:@"OK" 
                         style:UIAlertActionStyleDefault 
                         handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Fetch payment settings first to check if manual payment is enabled
    [self fetchPaymentSettingsWithPlan:plan];
}

// Fetch payment settings from the server
- (void)fetchPaymentSettingsWithPlan:(NSDictionary *)plan {
    NSLog(@"[WeaponX] Fetching payment settings for plan: %@", plan[@"name"]);
    
    // Show loading indicator while fetching payment settings
    [self.activityIndicator startAnimating];
    
    // Get API base URL from shared manager
    NSString *apiBaseUrl = [[APIManager sharedManager] baseURL];
    NSString *endpointUrl = [NSString stringWithFormat:@"%@/api/payment/settings", apiBaseUrl];
    
    // Create request with authorization
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpointUrl]];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.authToken] forHTTPHeaderField:@"Authorization"];
    
    // Create and execute task
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                // Network error
                NSLog(@"[WeaponX] Error fetching payment settings: %@", error);
                
                // Create fallback payment settings
                NSDictionary *fallbackSettings = @{
                    @"paypal_enabled": @(NO),
                    @"crypto_enabled": @(NO),
                    @"manual_payment_enabled": @(NO),
                    @"manual_payment_title": @"Manual Payment Instructions",
                    @"manual_payment_content": @"Due to connection issues, we couldn't retrieve the payment settings. Please contact support at support@projectx.com with your username and the plan you're interested in to complete your purchase."
                };
                
                // Show alert and continue with fallback settings
                UIAlertController *alert = [UIAlertController 
                                           alertControllerWithTitle:@"Connection Error" 
                                           message:@"Could not fetch payment settings. Please try again later."
                                           preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                                 actionWithTitle:@"Continue Anyway" 
                                 style:UIAlertActionStyleDefault 
                                 handler:^(UIAlertAction * _Nonnull action) {
                                     [self showPurchaseConfirmationForPlan:plan withPaymentSettings:fallbackSettings];
                                 }]];
                
                [alert addAction:[UIAlertAction 
                                 actionWithTitle:@"Cancel" 
                                 style:UIAlertActionStyleCancel 
                                 handler:^(UIAlertAction * _Nonnull action) {
                                     [self.activityIndicator stopAnimating];
                                 }]];
                
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200 && data) {
                NSError *jsonError;
                NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (jsonError) {
                    NSLog(@"[WeaponX] Error parsing payment settings: %@", jsonError);
                    [self showPurchaseConfirmationForPlan:plan withPaymentSettings:nil];
                    return;
                }
                
                NSLog(@"[WeaponX] Payment settings response: %@", jsonResponse);
                // Process the response with the payment settings
                [self showPurchaseConfirmationForPlan:plan withPaymentSettings:jsonResponse];
            } else {
                NSLog(@"[WeaponX] Invalid response from payment settings: %ld", (long)httpResponse.statusCode);
                // Proceed without payment settings
                [self showPurchaseConfirmationForPlan:plan withPaymentSettings:nil];
            }
        });
    }];
    
    [task resume];
}

- (void)showPurchaseConfirmationForPlan:(NSDictionary *)plan withPaymentSettings:(NSDictionary *)paymentSettings {
    // Stop loading indicator
    [self.activityIndicator stopAnimating];
    
    // Check if manual payment is enabled
    BOOL manualPaymentEnabled = NO;
    NSString *manualPaymentTitle = @"Manual Payment INFO";
    NSString *manualPaymentContent = @"Please contact support to complete your payment.";
    
    // Extract settings if available
    if (paymentSettings) {
        manualPaymentEnabled = [paymentSettings[@"manual_payment_enabled"] boolValue];
        if (paymentSettings[@"manual_payment_title"]) {
            manualPaymentTitle = paymentSettings[@"manual_payment_title"];
        }
        if (paymentSettings[@"manual_payment_content"]) {
            manualPaymentContent = paymentSettings[@"manual_payment_content"];
        }
    }
    
    // Create confirmation alert
    NSString *currentPlanName = [[NSUserDefaults standardUserDefaults] objectForKey:@"UserPlanName"];
    NSString *message;
    if (currentPlanName && ![currentPlanName isEqualToString:@"NO_PLAN"]) {
        message = [NSString stringWithFormat:@"Are you sure you want to change your subscription from %@ to %@ for %@?", 
                  currentPlanName, plan[@"name"], plan[@"price"]];
    } else {
        message = [NSString stringWithFormat:@"Are you sure you want to purchase %@ for %@?", 
                  plan[@"name"], plan[@"price"]];
    }
    
    UIAlertController *alert = [UIAlertController 
                               alertControllerWithTitle:@"Confirm Purchase" 
                               message:message
                               preferredStyle:UIAlertControllerStyleAlert];
    
    // If manual payment is enabled, show that option
    if (manualPaymentEnabled) {
        [alert addAction:[UIAlertAction 
                         actionWithTitle:@"Manual Payment INFO"
                         style:UIAlertActionStyleDefault 
                         handler:^(UIAlertAction * _Nonnull action) {
                             // Show manual payment instructions
                             [self.activityIndicator stopAnimating];
                             // Create a more comprehensive view for manual payment instructions
                             [self showManualPaymentInstructions:plan withTitle:manualPaymentTitle content:manualPaymentContent];
                         }]];
    }
    
    // Add regular purchase option
    [alert addAction:[UIAlertAction 
                     actionWithTitle:@"CREATE TICKET FOR PURCHASE" 
                     style:UIAlertActionStyleDefault 
                     handler:^(UIAlertAction * _Nonnull action) {
                         [self openSupportTicketForPlan:plan];
                     }]];
    
    // Add cancel action
    [alert addAction:[UIAlertAction 
                     actionWithTitle:@"Cancel" 
                     style:UIAlertActionStyleCancel 
                     handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showManualPaymentInstructions:(NSDictionary *)plan withTitle:(NSString *)title content:(NSString *)content {
    // Create a modal view controller to display the manual payment instructions
    UIViewController *modalVC = [[UIViewController alloc] init];
    modalVC.modalPresentationStyle = UIModalPresentationFormSheet;
    modalVC.preferredContentSize = CGSizeMake(350, 500); // Increased height for better readability
    
    if (@available(iOS 13.0, *)) {
        modalVC.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        modalVC.view.backgroundColor = [UIColor whiteColor];
    }
    
    // Add a scroll view to hold the content
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [modalVC.view addSubview:scrollView];
    
    // Add constraints for the scroll view
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:modalVC.view.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:modalVC.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:modalVC.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:modalVC.view.bottomAnchor]
    ]];
    
    // Create a container view for the content
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];
    
    // Set constraints for the content view
    [NSLayoutConstraint activateConstraints:@[
        [contentView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor]
    ]];
    
    // Add a title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:22]; // Larger font size for better visibility
    titleLabel.numberOfLines = 0;
    
    if (@available(iOS 13.0, *)) {
        titleLabel.textColor = [UIColor labelColor];
    } else {
        titleLabel.textColor = [UIColor blackColor];
    }
    
    [contentView addSubview:titleLabel];
    
    // Add a plan info label
    UILabel *planInfoLabel = [[UILabel alloc] init];
    planInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    planInfoLabel.text = [NSString stringWithFormat:@"Plan: %@ - Price: %@", plan[@"name"], plan[@"price"]];
    planInfoLabel.textAlignment = NSTextAlignmentCenter;
    planInfoLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    planInfoLabel.numberOfLines = 0;
    
    if (@available(iOS 13.0, *)) {
        planInfoLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        planInfoLabel.textColor = [UIColor darkGrayColor];
    }
    
    [contentView addSubview:planInfoLabel];
    
    // Add a text view for the instructions content
    UITextView *instructionsTextView = [[UITextView alloc] init];
    instructionsTextView.translatesAutoresizingMaskIntoConstraints = NO;
    instructionsTextView.editable = NO;
    instructionsTextView.dataDetectorTypes = UIDataDetectorTypeAll; // Allow links, phone numbers, etc. to be tappable
    instructionsTextView.selectable = YES;
    instructionsTextView.font = [UIFont systemFontOfSize:15];
    instructionsTextView.font = [UIFont systemFontOfSize:15];
    
    // Set background color to clear for better dark mode visibility
    instructionsTextView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0]; // Light background for dark mode visibility
    
    // Set text color based on interface style
    if (@available(iOS 13.0, *)) {
        instructionsTextView.textColor = [UIColor blackColor]; // Dark text on light background for better visibility
        instructionsTextView.linkTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor systemBlueColor],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
        };
        } else {
        instructionsTextView.textColor = [UIColor blackColor];
        instructionsTextView.linkTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor blueColor],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
        };
    }
    
    // Set text using attributedString to handle HTML content
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithData:[content dataUsingEncoding:NSUTF8StringEncoding]
                                                                           options:@{
                                                                               NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                                                                               NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)
                                                                           }
                                                                documentAttributes:nil
                                                                             error:nil];
    
    if (attributedString) {
        instructionsTextView.attributedText = attributedString;
    } else {
        instructionsTextView.text = content;
    }
    
    [contentView addSubview:instructionsTextView];
    
    // Add a close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    
    [closeButton addTarget:self action:@selector(dismissManualPaymentView:) forControlEvents:UIControlEventTouchUpInside];
    
    // Create a container for the button to add a tinted background
    UIView *buttonContainer = [[UIView alloc] init];
    buttonContainer.translatesAutoresizingMaskIntoConstraints = NO;
    buttonContainer.layer.cornerRadius = 10;
    
    if (@available(iOS 13.0, *)) {
        buttonContainer.backgroundColor = [UIColor systemBlueColor];
    } else {
        buttonContainer.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0];
    }
    
    [buttonContainer addSubview:closeButton];
    [contentView addSubview:buttonContainer];
    [buttonContainer addSubview:closeButton];
    [contentView addSubview:buttonContainer];
    
    // Set the close button text color to white for better visibility
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor whiteColor];
    closeButton.tintColor = [UIColor whiteColor];
    // Add shadow to button for better visibility
    buttonContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    buttonContainer.layer.shadowOffset = CGSizeMake(0, 2);
    buttonContainer.layer.shadowRadius = 4.0;
    buttonContainer.layer.shadowOpacity = 0.5; // Increased shadow opacity for better visibility
    
    // Set constraints for the close button
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.topAnchor constraintEqualToAnchor:buttonContainer.topAnchor constant:10],
        [closeButton.leadingAnchor constraintEqualToAnchor:buttonContainer.leadingAnchor],
        [closeButton.trailingAnchor constraintEqualToAnchor:buttonContainer.trailingAnchor],
        [closeButton.bottomAnchor constraintEqualToAnchor:buttonContainer.bottomAnchor constant:-10],
    ]];
    
    // Set constraints for the button container
    [NSLayoutConstraint activateConstraints:@[
        [buttonContainer.topAnchor constraintEqualToAnchor:instructionsTextView.bottomAnchor constant:20],
        [buttonContainer.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [buttonContainer.widthAnchor constraintEqualToConstant:200],
        [buttonContainer.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20],
    ]];
    
    // Set constraints for all subviews
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [planInfoLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15],
        [planInfoLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [planInfoLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [instructionsTextView.topAnchor constraintEqualToAnchor:planInfoLabel.bottomAnchor constant:20],
        [instructionsTextView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [instructionsTextView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [instructionsTextView.heightAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];
    
    // Present the modal view controller
    [self presentViewController:modalVC animated:YES completion:nil];
}

- (void)processPlanPurchase:(NSDictionary *)plan {
    // Show loading indicator
    [self.activityIndicator startAnimating];
    
    // For example:
    [[APIManager sharedManager] purchasePlanWithToken:self.authToken 
                                   planId:plan[@"id"] 
                                   completion:^(BOOL success, NSError *error) {
        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            // Stop loading indicator
            [self.activityIndicator stopAnimating];
            
            if (success) {
                // Show success message
                UIAlertController *alert = [UIAlertController 
                                           alertControllerWithTitle:@"Purchase Successful" 
                                           message:[NSString stringWithFormat:@"You have successfully purchased %@.", plan[@"name"]]
                                           preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                                 actionWithTitle:@"OK" 
                                 style:UIAlertActionStyleDefault 
                                 handler:^(UIAlertAction * _Nonnull action) {
                                     // Update the stored plan name immediately
                                     [[NSUserDefaults standardUserDefaults] setObject:plan[@"name"] forKey:@"UserPlanName"];
                                     [[NSUserDefaults standardUserDefaults] synchronize];
                                     
                                     // Update the plan display in the account view
                                     self.planValueLabel.text = [plan[@"name"] uppercaseString];
                                     
                                     // Refresh user data and plans
                                     [self refreshUserData];
                                     
                                     // Reload the plan slider to show the updated current plan
                                     if (self.planSliderView) {
                                         [self.planSliderView loadPlans];
                                     }
                                 }]];
                
                [self presentViewController:alert animated:YES completion:nil];
                
            } else {
                // Show error message
                UIAlertController *alert = [UIAlertController 
                                           alertControllerWithTitle:@"Purchase Failed" 
                                           message:error.localizedDescription ?: @"Unable to complete purchase. Please try again."
                                           preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                                 actionWithTitle:@"OK" 
                                 style:UIAlertActionStyleDefault 
                                 handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

#pragma mark - Data Refreshing Methods

- (void)refreshUserData {
    [self refreshUserDataForceRefresh:NO];
}

- (void)refreshUserDataForceRefresh:(BOOL)forceRefresh {
    if (!self.authToken) {
        NSLog(@"[WeaponX] Cannot refresh user data: no auth token");
        [self.refreshControl endRefreshing];
        return;
    }
    
    NSLog(@"[WeaponX] Refreshing user data with token: %@", self.authToken);
    
    // Fetch user data
    [[APIManager sharedManager] fetchUserDataWithToken:self.authToken completion:^(NSDictionary *userData, NSError *error) {
        // End refreshing if it was triggered by pull-to-refresh
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.refreshControl endRefreshing];
        });
        
        if (error) {
            NSLog(@"[WeaponX] Error fetching user data: %@", error.localizedDescription);
            
            // Show error alert on force refresh
            if (forceRefresh) {
                dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                                      message:[NSString stringWithFormat:@"Failed to refresh: %@", error.localizedDescription]
                                                            preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
                });
            }
            return;
        }
        
        if (!userData) {
            NSLog(@"[WeaponX] No user data received from API");
            if (forceRefresh) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                                      message:@"Failed to refresh: No data received"
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                });
            }
        return;
    }
    
        NSLog(@"[WeaponX] Received user data from API: %@", userData);
        
        
        // Process the userData to handle any NSNull values
        NSMutableDictionary *processedUserData = [NSMutableDictionary dictionary];
        
        [userData enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([obj isKindOfClass:[NSNull class]]) {
                if ([key isEqualToString:@"id"] || [key isEqualToString:@"user_id"]) {
                    processedUserData[key] = @0;
                } else {
                    processedUserData[key] = @"";
                }
            } else {
                processedUserData[key] = obj;
            }
        }];
        
        
        NSLog(@"[WeaponX] Processing user data, raw API response: %@", userData);
        
        // Ensure required fields exist
        if (!processedUserData[@"id"]) processedUserData[@"id"] = @0;
        if (!processedUserData[@"name"]) processedUserData[@"name"] = @"";
        if (!processedUserData[@"email"]) processedUserData[@"email"] = @"";
        if (!processedUserData[@"avatar"]) processedUserData[@"avatar"] = @"";
        if (!processedUserData[@"role"]) processedUserData[@"role"] = @"user";
        if (!processedUserData[@"created_at"]) processedUserData[@"created_at"] = @"";
        if (!processedUserData[@"updated_at"]) processedUserData[@"updated_at"] = @"";
        
        // Handle Telegram tag - check different possible field names
        NSString *telegramTag = nil;
        
        // Check multiple possible field names for Telegram tag
        if (userData[@"telegram_tag"] && ![userData[@"telegram_tag"] isKindOfClass:[NSNull class]]) {
            telegramTag = userData[@"telegram_tag"];
            NSLog(@"[WeaponX] Found Telegram tag under 'telegram_tag': %@", telegramTag);
        } else if (userData[@"telegram"] && ![userData[@"telegram"] isKindOfClass:[NSNull class]]) {
            telegramTag = userData[@"telegram"];
            NSLog(@"[WeaponX] Found Telegram tag under 'telegram': %@", telegramTag);
        } else if (userData[@"telegramTag"] && ![userData[@"telegramTag"] isKindOfClass:[NSNull class]]) {
            telegramTag = userData[@"telegramTag"];
            NSLog(@"[WeaponX] Found Telegram tag under 'telegramTag': %@", telegramTag);
        } else {
            NSLog(@"[WeaponX] No Telegram tag found in API response");
        }
        
        
        // Set the Telegram tag in processed data
        processedUserData[@"telegram_tag"] = telegramTag ?: @"";
        
        NSLog(@"[WeaponX] Final Telegram tag for display: %@", processedUserData[@"telegram_tag"]);
        
        // Save processed user data to NSUserDefaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:processedUserData forKey:@"WeaponXUserInfo"];
        [defaults synchronize];
        
        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self.userData = processedUserData;
            [self updateUserInfoDisplay];
            
            // Fetch and display plan information after user data is updated
            [self fetchAndDisplayPlanData];
            
            // Update the plan slider
            [self updatePlanSlider];
            
            // Show success message on force refresh
            if (forceRefresh) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success" 
                                                                                  message:@"Account information refreshed successfully"
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

#pragma mark - View Lifecycle

// Add this method to update content size when layout changes
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Update scroll view content size to ensure all content is visible
    [self updateScrollViewContentSize];
}

- (UIImage *)createDeviceIcon {
    // Create a CGRect for drawing
    CGRect rect = CGRectMake(0, 0, 30, 30);
    
    // Begin graphics context
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Draw a smartphone shape
    CGContextSetFillColorWithColor(context, [UIColor clearColor].CGColor);
    CGContextFillRect(context, rect);
    
    // Set stroke color to green
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor);
    CGContextSetLineWidth(context, 2.0);
    
    // Draw smartphone outline
    CGRect deviceRect = CGRectMake(8, 5, 14, 22);
    CGFloat cornerRadius = 3.0;
    
    // Draw rounded rectangle for device
    CGContextMoveToPoint(context, deviceRect.origin.x + cornerRadius, deviceRect.origin.y);
    // Top edge
    CGContextAddLineToPoint(context, deviceRect.origin.x + deviceRect.size.width - cornerRadius, deviceRect.origin.y);
    // Top right corner
    CGContextAddArcToPoint(context, deviceRect.origin.x + deviceRect.size.width, deviceRect.origin.y, 
                          deviceRect.origin.x + deviceRect.size.width, deviceRect.origin.y + cornerRadius, cornerRadius);
    // Right edge
    CGContextAddLineToPoint(context, deviceRect.origin.x + deviceRect.size.width, 
                          deviceRect.origin.y + deviceRect.size.height - cornerRadius);
    // Bottom right corner
    CGContextAddArcToPoint(context, deviceRect.origin.x + deviceRect.size.width, deviceRect.origin.y + deviceRect.size.height, 
                          deviceRect.origin.x + deviceRect.size.width - cornerRadius, deviceRect.origin.y + deviceRect.size.height, cornerRadius);
    // Bottom edge
    CGContextAddLineToPoint(context, deviceRect.origin.x + cornerRadius, deviceRect.origin.y + deviceRect.size.height);
    // Bottom left corner
    CGContextAddArcToPoint(context, deviceRect.origin.x, deviceRect.origin.y + deviceRect.size.height, 
                          deviceRect.origin.x, deviceRect.origin.y + deviceRect.size.height - cornerRadius, cornerRadius);
    // Left edge
    CGContextAddLineToPoint(context, deviceRect.origin.x, deviceRect.origin.y + cornerRadius);
    // Top left corner
    CGContextAddArcToPoint(context, deviceRect.origin.x, deviceRect.origin.y, 
                          deviceRect.origin.x + cornerRadius, deviceRect.origin.y, cornerRadius);
    
    // Draw home button
    CGRect buttonRect = CGRectMake(deviceRect.origin.x + deviceRect.size.width/2 - 2, 
                                 deviceRect.origin.y + deviceRect.size.height - 5, 4, 2);
    CGContextAddEllipseInRect(context, buttonRect);
    
    // Stroke the path
    CGContextStrokePath(context);
    
    // Get the image from the graphics context
    UIImage *deviceIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return deviceIcon;
}

// App update methods have been removed to disable this functionality

#pragma mark - App Update Methods

// Setup update buttons in the info card (legacy method)
- (void)setupUpdateButtons {
    // This is now handled by setupUpdateButtonsInContainer
    // Create a temporary container and call the new method
    UIView *tempContainer = [[UIView alloc] init];
    tempContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.userInfoCard addSubview:tempContainer];
    
    // Position below the last item in the user info card (for backward compatibility)
    [NSLayoutConstraint activateConstraints:@[
        [tempContainer.topAnchor constraintEqualToAnchor:self.appVersionValueLabel.bottomAnchor constant:15.0],
        [tempContainer.leadingAnchor constraintEqualToAnchor:self.userInfoCard.leadingAnchor constant:15.0],
        [tempContainer.trailingAnchor constraintEqualToAnchor:self.userInfoCard.trailingAnchor constant:-15.0],
        [tempContainer.heightAnchor constraintEqualToConstant:50.0]
    ]];
    
    // Call the new method with the temporary container
    [self setupUpdateButtonsInContainer:tempContainer];
    
    // Ensure the userInfoCard bottom constraint accounts for the new buttons
    NSLayoutConstraint *userInfoCardBottomConstraint = [self.userInfoCard.bottomAnchor constraintEqualToAnchor:tempContainer.bottomAnchor constant:15.0];
    userInfoCardBottomConstraint.active = YES;
}

// Check for updates manually
- (void)checkForUpdatesManually:(id)sender {
    // Show loading indicator
    UIActivityIndicatorView *activityIndicator;
    if (@available(iOS 13.0, *)) {
        activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    } else {
        // Use the appropriate style for iOS 12 and below
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        #pragma clang diagnostic pop
    }
    activityIndicator.center = ((UIButton *)sender).center;
    [self.userInfoCard addSubview:activityIndicator];
    [activityIndicator startAnimating];
    
    // Disable the button while checking
    ((UIButton *)sender).enabled = NO;
    
    // Get current app version
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildNumberString = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSInteger buildNumber = [buildNumberString integerValue];
    
    // Check for updates
    [self checkForUpdatesWithVersion:currentVersion buildNumber:buildNumber completion:^(BOOL updateAvailable, NSDictionary *updateInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Remove activity indicator
            [activityIndicator removeFromSuperview];
            ((UIButton *)sender).enabled = YES;
            
            if (updateAvailable) {
                [self showUpdateAlert:updateInfo];
            } else {
                [self showNoUpdateAlert];
            }
        });
    }];
}

// Check for updates with given version and build number
- (void)checkForUpdatesWithVersion:(NSString *)version buildNumber:(NSInteger)buildNumber completion:(void (^)(BOOL updateAvailable, NSDictionary *updateInfo))completion {
    // We'll use a hybrid approach that both checks the API endpoint and directly checks the repo
    
    // First try the direct repo check method, which is more reliable for Sileo
    [self checkDirectRepoForUpdates:version buildNumber:buildNumber completion:^(BOOL directUpdateAvailable, NSDictionary *directUpdateInfo) {
        if (directUpdateAvailable) {
            // If we found an update directly from the repo, return it immediately
            completion(YES, directUpdateInfo);
            return;
        }
        
        // If no direct update was found, try the API method as fallback
        // Get API URL
        NSURL *url = [NSURL URLWithString:@"https://hydra.weaponx.us/api/app/check-updates"];
        
        // Create request
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setHTTPMethod:@"POST"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        
        // Prepare request body
        NSDictionary *requestData = @{
            @"current_version": version,
            @"build_number": @(buildNumber)
        };
        
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestData options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] JSON serialization error: %@", jsonError);
            completion(NO, nil);
            return;
        }
        
        [request setHTTPBody:jsonData];
        
        // Create data task
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"[WeaponX] Error checking for updates: %@", error);
                completion(NO, nil);
                return;
            }
            
            
            // Parse response
            NSError *jsonParseError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonParseError];
            
            if (jsonParseError) {
                NSLog(@"[WeaponX] JSON parsing error: %@", jsonParseError);
                completion(NO, nil);
                return;
            }
            
            BOOL updateAvailable = [json[@"update_available"] boolValue];
            NSDictionary *updateInfo = json[@"version"];
            
            completion(updateAvailable, updateInfo);
        }];
        
        [task resume];
    }];
}

// Direct check of the repo for updates (more reliable for Sileo compatibility)
- (void)checkDirectRepoForUpdates:(NSString *)currentVersion buildNumber:(NSInteger)currentBuildNumber completion:(void (^)(BOOL updateAvailable, NSDictionary *updateInfo))completion {
    // Use a direct repo check approach for Sileo
    NSURL *repoPackagesURL = [NSURL URLWithString:@"https://hydra.weaponx.us/repo/Packages"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:repoPackagesURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] Error checking repo directly: %@", error);
            completion(NO, nil);
            return;
        }
        
        NSString *packagesContent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!packagesContent) {
            NSLog(@"[WeaponX] Could not read repo Packages file");
            completion(NO, nil);
            return;
        }
        
        NSString *packageName = @"com.hydra.projectx";
        BOOL foundPackage = NO;
        NSString *repoVersion = nil;
        NSInteger repoBuildNumber = 0;
        
        // Parse the Packages file to find our package
        NSArray *packages = [packagesContent componentsSeparatedByString:@"\n\n"];
        for (NSString *package in packages) {
            if ([package containsString:packageName]) {
                foundPackage = YES;
                
                // Extract version
                NSRegularExpression *versionRegex = [NSRegularExpression regularExpressionWithPattern:@"Version: ([0-9.]+)" options:0 error:nil];
                NSTextCheckingResult *versionMatch = [versionRegex firstMatchInString:package options:0 range:NSMakeRange(0, package.length)];
                if (versionMatch && versionMatch.numberOfRanges > 1) {
                    repoVersion = [package substringWithRange:[versionMatch rangeAtIndex:1]];
                }
                
                // Extract build number from control section or filename
                NSRegularExpression *buildNumberRegex = [NSRegularExpression regularExpressionWithPattern:@"([0-9]+)\\+debug" options:0 error:nil];
                NSTextCheckingResult *buildMatch = [buildNumberRegex firstMatchInString:package options:0 range:NSMakeRange(0, package.length)];
                if (buildMatch && buildMatch.numberOfRanges > 1) {
                    NSString *buildStr = [package substringWithRange:[buildMatch rangeAtIndex:1]];
                    repoBuildNumber = [buildStr integerValue];
                }
                
                break;
            }
        }
        
        if (!foundPackage || !repoVersion) {
            NSLog(@"[WeaponX] Package not found in repo or version not detected");
            completion(NO, nil);
            return;
        }
        
        // Check if the repo version is newer
        BOOL isNewerVersion = NO;
        NSArray *repoVersionParts = [repoVersion componentsSeparatedByString:@"."];
        NSArray *currentVersionParts = [currentVersion componentsSeparatedByString:@"."];
        
        // Compare version numbers (e.g., 1.0.1 > 1.0.0)
        if (repoVersionParts.count > 0 && currentVersionParts.count > 0) {
            for (NSInteger i = 0; i < MIN(repoVersionParts.count, currentVersionParts.count); i++) {
                NSInteger repoPart = [repoVersionParts[i] integerValue];
                NSInteger currentPart = [currentVersionParts[i] integerValue];
                
                if (repoPart > currentPart) {
                    isNewerVersion = YES;
                    break;
                } else if (repoPart < currentPart) {
                    break;
                }
                // If equal, continue to next part
            }
            
            // If all checked parts are equal, but repo version has more parts
            if (!isNewerVersion && repoVersionParts.count > currentVersionParts.count) {
                isNewerVersion = YES;
            }
        }
        
        // If versions are the same, check build number
        if (!isNewerVersion && [repoVersion isEqualToString:currentVersion]) {
            isNewerVersion = (repoBuildNumber > currentBuildNumber);
        }
        
        if (isNewerVersion) {
            // Create an update info dictionary similar to what the API would return
            NSDictionary *updateInfo = @{
                @"version": repoVersion,
                @"build_number": @(repoBuildNumber),
                @"changelog": @"Update available from repository. See details in Sileo.",
                @"human_size": @"Download in Sileo"
            };
            
            completion(YES, updateInfo);
        } else {
            completion(NO, nil);
        }
    }];
    
    [task resume];
}

// Show alert when update is available
- (void)showUpdateAlert:(NSDictionary *)updateInfo {
    NSString *version = updateInfo[@"version"];
    NSString *buildNumber = [NSString stringWithFormat:@"%@", updateInfo[@"build_number"]];
    NSString *changelog = updateInfo[@"changelog"];
    NSString *size = updateInfo[@"human_size"];
    
    NSString *message = [NSString stringWithFormat:@"Version: %@ (Build %@)\nSize: %@\n\nChangelog:\n%@", 
                         version, buildNumber, size, changelog];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Update Available" 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Sileo" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self openSileoRepo];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Show alert when no update is available
- (void)showNoUpdateAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Updates Available" 
                                                                   message:@"You are using the latest version." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Add repo to Sileo
- (void)addRepoToSileo:(id)sender {
    [self openSileoRepo];
}

// Open Sileo with the repository URL
- (void)openSileoRepo {
    NSString *repoURL = @"sileo://source/https://hydra.weaponx.us/repo/";
    NSURL *url = [NSURL URLWithString:repoURL];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        if (@available(iOS 10.0, *)) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                if (!success) {
                    [self showSileoNotInstalledAlert];
                }
            }];
        } else {
            // Use the deprecated method for iOS 9 and below with compiler warning suppression
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            BOOL success = [[UIApplication sharedApplication] openURL:url];
            #pragma clang diagnostic pop
            if (!success) {
                [self showSileoNotInstalledAlert];
            }
        }
    } else {
        [self showSileoNotInstalledAlert];
    }
}

// Show alert when Sileo is not installed
- (void)showSileoNotInstalledAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sileo Not Found" 
                                                                   message:@"Sileo appears not to be installed. Please install Sileo or add the repository manually: https://hydra.weaponx.us/repo/" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Schedule automatic update checks
- (void)scheduleUpdateChecks {
    // Cancel any existing timers
    if (self.updateCheckTimer) {
        [self.updateCheckTimer invalidate];
        self.updateCheckTimer = nil;
    }
    
    // Set update check interval (12 hours = 43200 seconds for checking twice a day)
    NSTimeInterval updateInterval = 43200; 
    
    // Schedule timer for regular update checks
    self.updateCheckTimer = [NSTimer scheduledTimerWithTimeInterval:updateInterval
                                                             target:self
                                                           selector:@selector(performAutomaticUpdateCheck)
                                                           userInfo:nil
                                                            repeats:YES];
    
    // Also perform an initial check
    [self performAutomaticUpdateCheck];
}

// Perform automatic update check
- (void)performAutomaticUpdateCheck {
    // Get current app version
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildNumberString = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSInteger buildNumber = [buildNumberString integerValue];
    
    // Check for updates silently
    [self checkForUpdatesWithVersion:currentVersion buildNumber:buildNumber completion:^(BOOL updateAvailable, NSDictionary *updateInfo) {
        if (updateAvailable) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showUpdateNotification:updateInfo];
            });
        }
    }];
}

// Show notification when update is available
- (void)showUpdateNotification:(NSDictionary *)updateInfo {
    NSString *version = updateInfo[@"version"];
    NSString *buildNumber = [NSString stringWithFormat:@"%@", updateInfo[@"build_number"]];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Update Found" 
                                                                   message:[NSString stringWithFormat:@"Version %@ (Build %@) is available", version, buildNumber]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Sileo" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self openSileoRepo];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Setup update buttons in the provided container
- (void)setupUpdateButtonsInContainer:(UIView *)updateButtonsContainer {
    // Create the Check Update button
    UIButton *checkUpdateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    checkUpdateButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create the Add Repo button
    UIButton *addRepoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    addRepoButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Configure appearance with a modern, sleek design
    if (@available(iOS 15.0, *)) {
        // Check Update button with pill shape
        UIButtonConfiguration *updateConfig = [UIButtonConfiguration filledButtonConfiguration];
        updateConfig.cornerStyle = UIButtonConfigurationCornerStyleCapsule; // Pill-shaped
        updateConfig.title = @"Check Update";
        updateConfig.image = [UIImage systemImageNamed:@"arrow.up.doc.fill"];
        updateConfig.imagePlacement = NSDirectionalRectEdgeLeading;
        updateConfig.imagePadding = 5; // Reduced from 6 to 5 for smaller size
        updateConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 8, 4, 8); // Reduced insets for smaller buttons
        updateConfig.buttonSize = UIButtonConfigurationSizeSmall; // Smaller button size
        updateConfig.baseBackgroundColor = [UIColor systemGreenColor];
        updateConfig.baseForegroundColor = [UIColor blackColor]; // Dark text on green for better visibility
        
        // Make font smaller
        UIFont *smallerFont = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        updateConfig.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            [newAttributes setObject:smallerFont forKey:NSFontAttributeName];
            return newAttributes;
        };
        
        // Add a subtle shadow effect
        checkUpdateButton.layer.shadowColor = [UIColor blackColor].CGColor;
        checkUpdateButton.layer.shadowOffset = CGSizeMake(0, 2);
        checkUpdateButton.layer.shadowRadius = 2.0; // Reduced shadow
        checkUpdateButton.layer.shadowOpacity = 0.2;
        
        checkUpdateButton.configuration = updateConfig;
        
        // Add Repo button with pill shape
        UIButtonConfiguration *repoConfig = [UIButtonConfiguration filledButtonConfiguration];
        repoConfig.cornerStyle = UIButtonConfigurationCornerStyleCapsule; // Pill-shaped
        repoConfig.title = @"Add Repo";
        // Ensure SF Symbol loads properly
        UIImage *repoImage = [UIImage systemImageNamed:@"plus.circle.fill"]; // Changed from plus.circle.dashed to plus.circle.fill which is better supported
        repoConfig.image = repoImage;
        repoConfig.imagePlacement = NSDirectionalRectEdgeLeading;
        repoConfig.imagePadding = 5; // Reduced from 6 to 5 for smaller size
        repoConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 8, 4, 8); // Reduced insets for smaller buttons
        repoConfig.buttonSize = UIButtonConfigurationSizeSmall; // Smaller button size
        repoConfig.baseBackgroundColor = [UIColor systemBlueColor];
        repoConfig.baseForegroundColor = [UIColor blackColor]; // Dark text on blue for better visibility
        
        // Make font smaller
        repoConfig.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            [newAttributes setObject:smallerFont forKey:NSFontAttributeName];
            return newAttributes;
        };
        
        // Add a subtle shadow effect
        addRepoButton.layer.shadowColor = [UIColor blackColor].CGColor;
        addRepoButton.layer.shadowOffset = CGSizeMake(0, 2);
        addRepoButton.layer.shadowRadius = 2.0; // Reduced shadow
        addRepoButton.layer.shadowOpacity = 0.2;
        
        addRepoButton.configuration = repoConfig;
    } else {
        // For iOS 14 and below, use a more compact design
        // Check Update button
        [checkUpdateButton setTitle:@"Check Update" forState:UIControlStateNormal];
        [checkUpdateButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal]; // Dark text on green for better visibility
        checkUpdateButton.backgroundColor = [UIColor systemGreenColor];
        checkUpdateButton.layer.cornerRadius = 18; // Increased rounding for pill shape
        
        // Add shadow
        checkUpdateButton.layer.shadowColor = [UIColor blackColor].CGColor;
        checkUpdateButton.layer.shadowOffset = CGSizeMake(0, 2);
        checkUpdateButton.layer.shadowRadius = 3.0;
        checkUpdateButton.layer.shadowOpacity = 0.2;
        
        // Add Repo button
        [addRepoButton setTitle:@"Add Repo" forState:UIControlStateNormal];
        [addRepoButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal]; // Dark text on blue for better visibility
        addRepoButton.backgroundColor = [UIColor systemBlueColor];
        addRepoButton.layer.cornerRadius = 18; // Increased rounding for pill shape
        
        // Add shadow
        addRepoButton.layer.shadowColor = [UIColor blackColor].CGColor;
        addRepoButton.layer.shadowOffset = CGSizeMake(0, 2);
        addRepoButton.layer.shadowRadius = 3.0;
        addRepoButton.layer.shadowOpacity = 0.2;
        
        // Add SF Symbol if available
        if (@available(iOS 13.0, *)) {
            // Create a more compact layout for the Check Update button
            UIStackView *updateStack = [[UIStackView alloc] init];
            updateStack.translatesAutoresizingMaskIntoConstraints = NO;
            updateStack.axis = UILayoutConstraintAxisHorizontal;
            updateStack.alignment = UIStackViewAlignmentCenter;
            updateStack.spacing = 6; // Reduced spacing
            [checkUpdateButton addSubview:updateStack];
            
            // Add icon
            UIImageView *updateIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.doc.fill"]];
            updateIconView.translatesAutoresizingMaskIntoConstraints = NO;
            updateIconView.contentMode = UIViewContentModeScaleAspectFit;
            updateIconView.tintColor = [UIColor blackColor]; // Match text color
            [updateStack addArrangedSubview:updateIconView];
            
            // Add label
            UILabel *updateLabel = [[UILabel alloc] init];
            updateLabel.translatesAutoresizingMaskIntoConstraints = NO;
            updateLabel.text = @"Check Update";
            updateLabel.textColor = [UIColor blackColor]; // Match icon color
            updateLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; // Slightly smaller, but bolder
            [updateStack addArrangedSubview:updateLabel];
            
            // Center the stack in the button
            [NSLayoutConstraint activateConstraints:@[
                [updateStack.centerXAnchor constraintEqualToAnchor:checkUpdateButton.centerXAnchor],
                [updateStack.centerYAnchor constraintEqualToAnchor:checkUpdateButton.centerYAnchor],
                [updateIconView.widthAnchor constraintEqualToConstant:18], // Smaller icon
                [updateIconView.heightAnchor constraintEqualToConstant:18]  // Smaller icon
            ]];
            
            // Clear default title
            [checkUpdateButton setTitle:@"" forState:UIControlStateNormal];
            
            // Create a more compact layout for the Add Repo button
            UIStackView *repoStack = [[UIStackView alloc] init];
            repoStack.translatesAutoresizingMaskIntoConstraints = NO;
            repoStack.axis = UILayoutConstraintAxisHorizontal;
            repoStack.alignment = UIStackViewAlignmentCenter;
            repoStack.spacing = 6; // Reduced spacing
            [addRepoButton addSubview:repoStack];
            
            // Add icon
            UIImageView *repoIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.dashed"]];
            repoIconView.translatesAutoresizingMaskIntoConstraints = NO;
            repoIconView.contentMode = UIViewContentModeScaleAspectFit;
            repoIconView.tintColor = [UIColor blackColor]; // Match text color
            [repoStack addArrangedSubview:repoIconView];
            
            // Add label
            UILabel *repoLabel = [[UILabel alloc] init];
            repoLabel.translatesAutoresizingMaskIntoConstraints = NO;
            repoLabel.text = @"Add Repo";
            repoLabel.textColor = [UIColor blackColor]; // Match icon color
            repoLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; // Slightly smaller, but bolder
            [repoStack addArrangedSubview:repoLabel];
            
            // Center the stack in the button
            [NSLayoutConstraint activateConstraints:@[
                [repoStack.centerXAnchor constraintEqualToAnchor:addRepoButton.centerXAnchor],
                [repoStack.centerYAnchor constraintEqualToAnchor:addRepoButton.centerYAnchor],
                [repoIconView.widthAnchor constraintEqualToConstant:18], // Smaller icon
                [repoIconView.heightAnchor constraintEqualToConstant:18]  // Smaller icon
            ]];
            
            // Clear default title
            [addRepoButton setTitle:@"" forState:UIControlStateNormal];
        }
    }
    
    [checkUpdateButton addTarget:self action:@selector(checkForUpdatesManually:) forControlEvents:UIControlEventTouchUpInside];
    [updateButtonsContainer addSubview:checkUpdateButton];
    
    [addRepoButton addTarget:self action:@selector(addRepoToSileo:) forControlEvents:UIControlEventTouchUpInside];
    [updateButtonsContainer addSubview:addRepoButton];
    
    // Layout the buttons side by side with a subtle gradient background
    UIView *gradientBackground = [[UIView alloc] init];
    gradientBackground.translatesAutoresizingMaskIntoConstraints = NO;
    gradientBackground.backgroundColor = [UIColor clearColor];
    gradientBackground.layer.cornerRadius = 20; // Rounded corners
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = gradientBackground.bounds;
    gradient.cornerRadius = 20;
    
    // Set colors based on iOS version
    if (@available(iOS 13.0, *)) {
        UIColor *topColorDark = [UIColor colorWithRed:0.12 green:0.12 blue:0.12 alpha:1.0];
        UIColor *bottomColorDark = [UIColor colorWithRed:0.08 green:0.08 blue:0.08 alpha:1.0];
        UIColor *topColorLight = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
        UIColor *bottomColorLight = [UIColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0];
        
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            gradient.colors = @[(id)topColorDark.CGColor, (id)bottomColorDark.CGColor];
        } else {
            gradient.colors = @[(id)topColorLight.CGColor, (id)bottomColorLight.CGColor];
        }
    } else {
        UIColor *topColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.12 alpha:1.0];
        UIColor *bottomColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.08 alpha:1.0];
        gradient.colors = @[(id)topColor.CGColor, (id)bottomColor.CGColor];
    }
    
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    
    [gradientBackground.layer insertSublayer:gradient atIndex:0];
    [updateButtonsContainer insertSubview:gradientBackground atIndex:0];
    
    [NSLayoutConstraint activateConstraints:@[
        // Gradient background
        [gradientBackground.leadingAnchor constraintEqualToAnchor:updateButtonsContainer.leadingAnchor],
        [gradientBackground.trailingAnchor constraintEqualToAnchor:updateButtonsContainer.trailingAnchor],
        [gradientBackground.topAnchor constraintEqualToAnchor:updateButtonsContainer.topAnchor],
        [gradientBackground.bottomAnchor constraintEqualToAnchor:updateButtonsContainer.bottomAnchor],
        
        // Buttons layout with more spacing between them
        [checkUpdateButton.leadingAnchor constraintEqualToAnchor:updateButtonsContainer.leadingAnchor constant:4],
        [checkUpdateButton.topAnchor constraintEqualToAnchor:updateButtonsContainer.topAnchor constant:2],
        [checkUpdateButton.bottomAnchor constraintEqualToAnchor:updateButtonsContainer.bottomAnchor constant:-2],
        [checkUpdateButton.widthAnchor constraintEqualToAnchor:updateButtonsContainer.widthAnchor multiplier:0.47],
        
        [addRepoButton.trailingAnchor constraintEqualToAnchor:updateButtonsContainer.trailingAnchor constant:-4],
        [addRepoButton.topAnchor constraintEqualToAnchor:updateButtonsContainer.topAnchor constant:2],
        [addRepoButton.bottomAnchor constraintEqualToAnchor:updateButtonsContainer.bottomAnchor constant:-2],
        [addRepoButton.widthAnchor constraintEqualToAnchor:updateButtonsContainer.widthAnchor multiplier:0.47]
    ]];
    
    // Layout subviews to ensure gradient is properly sized
    [updateButtonsContainer layoutIfNeeded];
    gradient.frame = gradientBackground.bounds;
}

- (void)setupSupportButton {
    // Create Support button
    self.supportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.supportButton setTitle:@"Support & Announcements" forState:UIControlStateNormal];
    self.supportButton.backgroundColor = [UIColor systemBlueColor];
    self.supportButton.tintColor = [UIColor whiteColor];
    self.supportButton.layer.cornerRadius = 10;
    [self.supportButton addTarget:self action:@selector(supportButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.supportButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.supportButton];
    
    // Add badge view
    UILabel *badgeLabel = [[UILabel alloc] init];
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    badgeLabel.backgroundColor = [UIColor systemRedColor];
    badgeLabel.textColor = [UIColor whiteColor];
    badgeLabel.font = [UIFont boldSystemFontOfSize:12];
    badgeLabel.textAlignment = NSTextAlignmentCenter;
    badgeLabel.layer.cornerRadius = 10;
    badgeLabel.clipsToBounds = YES;
    badgeLabel.tag = 999;
    badgeLabel.hidden = YES;
    [self.supportButton addSubview:badgeLabel];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        [badgeLabel.topAnchor constraintEqualToAnchor:self.supportButton.topAnchor constant:-5],
        [badgeLabel.trailingAnchor constraintEqualToAnchor:self.supportButton.trailingAnchor constant:5],
        [badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:20],
        [badgeLabel.heightAnchor constraintEqualToConstant:20]
    ]];
    
    // Update notification count
    [self updateSupportButtonBadge];
}

- (void)updateSupportButtonBadge {
    // Only update badge if user is authenticated
    if (![self isLoggedIn]) {
        return;
    }
    
    [[APIManager sharedManager] getNotificationCount:^(NSInteger unreadBroadcasts, NSInteger unreadTicketReplies, NSInteger totalCount, NSError *error) {
        if (error) {
            NSLog(@"Error fetching notification count: %@", error);
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UILabel *badgeLabel = [self.supportButton viewWithTag:999];
            
            if (totalCount > 0) {
                badgeLabel.text = [NSString stringWithFormat:@"%ld", (long)totalCount];
                badgeLabel.hidden = NO;
                
                // Adjust size based on number of digits
                if (totalCount < 10) {
                    [badgeLabel.widthAnchor constraintEqualToConstant:20].active = YES;
                } else if (totalCount < 100) {
                    [badgeLabel.widthAnchor constraintEqualToConstant:25].active = YES;
                } else {
                    [badgeLabel.widthAnchor constraintEqualToConstant:30].active = YES;
                }
            } else {
                badgeLabel.hidden = YES;
            }
        });
    }];
}

- (void)supportButtonTapped {
    SupportViewController *supportVC = [[SupportViewController alloc] init];
    supportVC.tabBarController = self.tabBarController;
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:supportVC];
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - UI Layout

- (void)setupInterfaceForLoggedInUser {
    // ... existing code ...
    
    // Add Support button to your layout
    [self setupSupportButton];
    
    // Adjust the layout constraints to include the Support button
    // Insert in layout constraints
    // For example, add to your layout constraints array:
    [NSLayoutConstraint activateConstraints:@[
        [self.supportButton.topAnchor constraintEqualToAnchor:self.logoutButton.bottomAnchor constant:20],
        [self.supportButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.supportButton.widthAnchor constraintEqualToConstant:240],
        [self.supportButton.heightAnchor constraintEqualToConstant:44]
    ]];
    
    // ... continue with existing code ...
}

- (void)contactSupportTapped {
    NSLog(@"[WeaponX] 📱 Contact support tapped, navigating to Support tab");
    
    // First dismiss the account view controller if it's presented modally
    [self dismissViewControllerAnimated:YES completion:^{
        // Modern approach to get the key window for iOS 13+
        UIWindow *keyWindow = nil;
        
        // Get all connected scenes
        NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
        for (UIScene *scene in scenes) {
            // Find the active scene
            if (scene.activationState == UISceneActivationStateForegroundActive && 
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                // Find the key window in this scene
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
                if (keyWindow) break;
            }
        }
        
        // Fallback if we couldn't find the key window
        if (!keyWindow) {
            // Try any window from the active scene
            for (UIScene *scene in scenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    if (windowScene.windows.count > 0) {
                        keyWindow = windowScene.windows.firstObject;
                        break;
                    }
                }
            }
            
            // If still no window, use the delegate window as a last resort
            if (!keyWindow) {
                keyWindow = [UIApplication sharedApplication].delegate.window;
            }
        }
        
        // Get the tab bar controller from the window
        if (keyWindow) {
            UITabBarController *tabBarController = (UITabBarController *)keyWindow.rootViewController;
            
            if ([tabBarController isKindOfClass:[UITabBarController class]]) {
                // Switch to the Support tab (index 3)
                [tabBarController setSelectedIndex:3];
                NSLog(@"[WeaponX] 🔄 Switched to Support tab");
            } else {
                NSLog(@"[WeaponX] ❌ Root view controller is not a tab bar controller");
            }
        } else {
            NSLog(@"[WeaponX] ❌ Failed to find key window");
        }
    }];
}

// Add a method to initialize the button text
- (void)initializePlanButton {
    // Start with loading state
    self.daysRemainingLabel.text = @"LOADING...";
    self.daysRemainingLabel.alpha = 1.0;
    [self setupPulseAnimationForLabel:self.daysRemainingLabel];
    
    // Set a timer to ensure we're not stuck in loading state
    if (self.loadingTimeoutTimer) {
        [self.loadingTimeoutTimer invalidate];
    }
    self.loadingTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 
                                                            target:self 
                                                          selector:@selector(checkPlanStatusForButton) 
                                                          userInfo:nil 
                                                           repeats:NO];
}

// Method to check plan status specifically for the button display
- (void)checkPlanStatusForButton {
    NSLog(@"[WeaponX] Checking plan status for button display");
    
    // Get the reliable plan info from the UI labels as mentioned by the user
    NSString *planNameFromLabel = self.planValueLabel.text;
    NSString *planExpiryFromLabel = self.planExpiryLabel.text;
    
    NSLog(@"[WeaponX] Plan info from UI labels - Name: %@, Expiry: %@", 
          planNameFromLabel ?: @"<nil>", 
          planExpiryFromLabel ?: @"<nil>");
    
    // If we don't have valid data from labels yet, wait a bit longer
    if (!planNameFromLabel || [planNameFromLabel isEqualToString:@"LOADING..."] || 
        planNameFromLabel.length == 0) {
        
        NSLog(@"[WeaponX] No valid plan info from UI labels yet, waiting");
        
        // Give it a bit more time and check again
        if (self.loadingTimeoutTimer) {
            [self.loadingTimeoutTimer invalidate];
        }
        
        self.loadingTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 
                                                                target:self 
                                                              selector:@selector(checkPlanStatusForButton) 
                                                              userInfo:nil 
                                                               repeats:NO];
        return;
    }
    
    // FIX: Add check for "INACTIVE" status to prevent treating it as an active plan
    if ([planNameFromLabel isEqualToString:@"INACTIVE"]) {
        NSLog(@"[WeaponX] Plan is explicitly marked INACTIVE");
        
        // Check if we have days remaining despite the INACTIVE status
        BOOL hasDaysRemaining = NO;
        
        if (planExpiryFromLabel) {
            if ([planExpiryFromLabel containsString:@"EXPIRES IN"] || 
                ([planExpiryFromLabel containsString:@"VALID UNTIL"] && ![planExpiryFromLabel containsString:@"EXPIRED"])) {
                hasDaysRemaining = YES;
                NSLog(@"[WeaponX] ⚠️ Plan marked INACTIVE but has days remaining: %@", planExpiryFromLabel);
            }
        }
        
        // If we have days remaining, this is a data inconsistency - force it to be ACTIVE
        if (hasDaysRemaining) {
            NSLog(@"[WeaponX] 🔄 Correcting inconsistent state: plan marked INACTIVE but has days remaining");
            
            // Update both UI and model
            self.planValueLabel.text = @"ACTIVE";
            self.planValueLabel.textColor = [UIColor greenColor];
            
            // Update user defaults
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setBool:YES forKey:@"WeaponXHasActivePlan"];
            [defaults setBool:YES forKey:@"WeaponXServerConfirmedActivePlan"];
            [defaults synchronize];
            
            // Get days remaining for button display
            [self extractDaysRemainingFromExpiryLabel:planExpiryFromLabel];
        } else {
            // It's truly inactive, show the appropriate UI
            self.daysRemainingLabel.text = @"GET PLAN";
            [self setupPulseAnimationForLabel:self.daysRemainingLabel];
            self.daysRemainingLabel.alpha = 1.0;
            self.isGetPlanMode = YES;
        }
        
        return;
    }
    
    // Check if user has an active plan
    if (![planNameFromLabel isEqualToString:@"NO_PLAN"] && 
        ![planNameFromLabel isEqualToString:@"ERROR_LOADING_PLAN_DATA"] && 
        ![planNameFromLabel isEqualToString:@"NO_PLAN_DATA_AVAILABLE"]) {
        
        NSLog(@"[WeaponX] User has active plan: %@", planNameFromLabel);
        
        // Extract days remaining from expiry label
        NSInteger daysRemaining = [self extractDaysRemainingFromExpiryLabel:planExpiryFromLabel];
        
        // Always use days remaining format for active plans
        if (daysRemaining > 0) {
            // Instead of directly setting the value, animate the counter
            [self animateDaysRemainingButtonCounter:daysRemaining];
            self.isGetPlanMode = NO; // Not in get plan mode
        } else if (daysRemaining == 0) {
            // Plan expired
            self.daysRemainingLabel.text = @"PLAN EXPIRED";
            [self setupPulseAnimationForLabel:self.daysRemainingLabel];
            self.daysRemainingLabel.alpha = 1.0;
            self.isGetPlanMode = NO; // Not in get plan mode
        } else {
            // Fallback for active plan but unknown days
            self.daysRemainingLabel.text = @"ACTIVE PLAN";
            [self setupPulseAnimationForLabel:self.daysRemainingLabel];
            self.daysRemainingLabel.alpha = 1.0;
            self.isGetPlanMode = NO; // Not in get plan mode
        }
        
        return;
    }
    
    // At this point, user has no active plan, check if they've claimed trial
    NSLog(@"[WeaponX] User has no active plan, checking if trial has been claimed");
    
    // Check trial status with API
    [[APIManager sharedManager] fetchUserPlanWithToken:self.authToken completion:^(NSDictionary *planData, NSError *error) {
        // Process on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"[WeaponX] Error checking trial status: %@", error);
                
                // In case of error, default to GET TRIAL (can be corrected later)
                self.daysRemainingLabel.text = @"GET TRIAL";
                [self setupPulseAnimationForLabel:self.daysRemainingLabel];
                self.daysRemainingLabel.alpha = 1.0;
                self.isGetPlanMode = YES; // In get plan mode
                return;
            }
            
            // Check if user has already used trial
            BOOL hasUsedTrial = [self hasUserClaimedTrialFromPlanData:planData];
            
            if (hasUsedTrial) {
                // User has claimed trial, show GET PLAN
                NSLog(@"[WeaponX] User has claimed trial, showing GET PLAN");
                self.daysRemainingLabel.text = @"GET PLAN";
                [self setupPulseAnimationForLabel:self.daysRemainingLabel];
                self.daysRemainingLabel.alpha = 1.0;
                self.isGetPlanMode = YES; // In get plan mode
            } else {
                // User has not claimed trial, show GET TRIAL
                NSLog(@"[WeaponX] User has not claimed trial, showing GET TRIAL");
                self.daysRemainingLabel.text = @"GET TRIAL";
                [self setupPulseAnimationForLabel:self.daysRemainingLabel];
                self.daysRemainingLabel.alpha = 1.0;
                self.isGetPlanMode = YES; // In get plan mode
            }
        });
    }];
}

// Helper method to extract days remaining from expiry label
- (NSInteger)extractDaysRemainingFromExpiryLabel:(NSString *)planExpiryFromLabel {
    NSInteger daysRemaining = -1;
    
    if (!planExpiryFromLabel) {
        return daysRemaining;
    }
    
    // Check for "EXPIRES IN X DAYS" format
    if ([planExpiryFromLabel containsString:@"EXPIRES IN"]) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"EXPIRES IN (\\d+) DAYS?" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:planExpiryFromLabel options:0 range:NSMakeRange(0, planExpiryFromLabel.length)];
        
        if (match && match.numberOfRanges > 1) {
            NSRange daysRange = [match rangeAtIndex:1];
            NSString *daysString = [planExpiryFromLabel substringWithRange:daysRange];
            daysRemaining = [daysString integerValue];
            
            NSLog(@"[WeaponX] Extracted days remaining: %ld", (long)daysRemaining);
        }
    } 
    // Check for "VALID UNTIL: YYYY-MM-DD" format
    else if ([planExpiryFromLabel containsString:@"VALID UNTIL:"]) {
        // Extract date from "VALID UNTIL: YYYY-MM-DD" format
        NSArray *parts = [planExpiryFromLabel componentsSeparatedByString:@": "];
        if (parts.count > 1) {
            NSString *dateStr = parts[1];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd"];
            NSDate *expiryDate = [formatter dateFromString:dateStr];
            
            if (expiryDate) {
                NSCalendar *calendar = [NSCalendar currentCalendar];
                NSDateComponents *components = [calendar components:NSCalendarUnitDay
                                                           fromDate:[NSDate date]
                                                             toDate:expiryDate
                                                            options:0];
                daysRemaining = [components day];
                NSLog(@"[WeaponX] Calculated days remaining from expiry date: %ld", (long)daysRemaining);
            }
        }
    }
    
    return daysRemaining;
}

#pragma mark - Helper Methods

- (NSString *)getDeviceUUID {
    // Get device UUID (identifierForVendor)
    NSUUID *uuid = [[UIDevice currentDevice] identifierForVendor];
    if (uuid) {
        return [uuid UUIDString];
    }
    return @"Unknown";
}

- (void)deviceUuidLabelTapped:(UITapGestureRecognizer *)gesture {
    NSString *uuid = [self getDeviceUUID];
    
    // Copy to clipboard
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [pasteboard setString:uuid];
    
    // Show feedback to user
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"UUID Copied"
                                                                   message:@"Device UUID has been copied to clipboard."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Add this method to handle the manage devices button tap
- (void)manageDevicesButtonTapped {
    NSLog(@"[WeaponX] Manage devices button tapped");
    
    // Check if we have an auth token
    if (!self.authToken) {
        NSLog(@"[WeaponX] Cannot open devices view - no auth token");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                       message:@"You must be logged in to manage devices." 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Create devices view controller
    DevicesViewController *devicesVC = [[DevicesViewController alloc] initWithAuthToken:self.authToken];
    
    // Create navigation controller to hold the devices view
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:devicesVC];
    
    // Present the view controller
    [self presentViewController:navController animated:YES completion:nil];
}

// Add this method to handle network status changes
- (void)handleNetworkStatusChanged:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    BOOL isOnline = [[userInfo objectForKey:@"isOnline"] boolValue];
    
    if (isOnline) {
        // Network became available - refresh data if we're visible
        if (self.isViewLoaded && self.view.window) {
            [self refreshUIAfterNetworkChange];
        }
    }
}

// Handle when network becomes available - specific handler for direct notification
- (void)handleNetworkBecameAvailable:(NSNotification *)notification {
    NSLog(@"[WeaponX] 🌐 Network became available - refreshing account data");
    
    // Only refresh if we're visible
    if (self.isViewLoaded && self.view.window) {
        // Show the loading indicator
        [self showLoadingIndicator];
        
        // Refresh the user's plan data
        [[APIManager sharedManager] refreshUserPlan];
        
        // Refresh user data if logged in
        NSString *token = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXAuthToken"];
        if (token) {
            [[APIManager sharedManager] fetchUserDataWithToken:token completion:^(NSDictionary *userData, NSError *error) {
                // Hide loading indicator
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self hideLoadingIndicator];
                    
                    if (error) {
                        NSLog(@"[WeaponX] ❌ Error refreshing user data: %@", error);
                        // Show error message using UIAlertController instead of toast
                        UIAlertController *alert = [UIAlertController 
                                                  alertControllerWithTitle:@"Error" 
                                                  message:@"Could not refresh user data" 
                                                  preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:alert animated:YES completion:nil];
                    } else {
                        NSLog(@"[WeaponX] ✅ Successfully refreshed user data");
                        // Update the UI with the new data
                        [self updateUI];
                    }
                });
            }];
        } else {
            [self hideLoadingIndicator];
        }
    }
}

// Method to handle UI refresh notifications
- (void)handleUIRefreshRequired:(NSNotification *)notification {
    NSLog(@"[WeaponX] 🔄 AccountViewController received UI refresh notification");
    
    // Only refresh if we're visible
    if (self.isViewLoaded && self.view.window) {
        [self updateUIWithPlanData];
    }
}

// Add this utility method to show loading state in UI
- (void)showLoadingIndicators {
    // Update telegram section
    if (self.telegramValueLabel) {
        self.telegramValueLabel.text = @"Loading...";
    }
    
    // Update plan section
    if (self.planNameLabel) {
        self.planNameLabel.text = @"Loading...";
    }
    
    // Update devices section
    if (self.deviceLimitValueLabel) {
        self.deviceLimitValueLabel.text = @"Loading...";
    }
}

// Add method to refresh UI after network changes
- (void)refreshUIAfterNetworkChange {
    NSLog(@"[WeaponX] 🔄 AccountViewController refreshing UI after network change");
    
    // Show loading indicator
    [self showLoadingIndicator];
    
    // Get the API manager
    APIManager *apiManager = [APIManager sharedManager];
    
    // Check if we have network and auth token
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults objectForKey:@"WeaponXAuthToken"];
    
    if ([apiManager isNetworkAvailable] && token) {
        NSLog(@"[WeaponX] 🔄 Refreshing account data with network available");
        
        // Refresh plan data first
        [apiManager refreshUserPlan];
        
        // Give time for plan data to update, then refresh UI
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Refresh UI components with latest data from NSUserDefaults
            [self updateUIWithPlanData];
            
            // Hide loading indicator
            [self hideLoadingIndicator];
        });
    } else {
        NSLog(@"[WeaponX] ℹ️ Cannot refresh account data: %@, %@", 
              [apiManager isNetworkAvailable] ? @"Network available" : @"Network unavailable",
              token ? @"Have token" : @"No token");
        
        // Just update UI with whatever data we have stored
        [self updateUIWithPlanData];
        
        // Hide loading indicator
        [self hideLoadingIndicator];
    }
}

// Method to show loading indicator
- (void)showLoadingIndicator {
    if (!self.loadingIndicator) {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.loadingIndicator.hidesWhenStopped = YES;
        self.loadingIndicator.center = self.view.center;
        [self.view addSubview:self.loadingIndicator];
    }
    
    [self.loadingIndicator startAnimating];
    
    // Update any loading text labels if they exist
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"LOADING..."]) {
                label.hidden = NO;
            }
        }
    }
}

// Method to hide loading indicator
- (void)hideLoadingIndicator {
    [self.loadingIndicator stopAnimating];
    
    // Update any loading text labels if they exist
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if ([label.text isEqualToString:@"LOADING..."]) {
                label.hidden = YES;
            }
        }
    }
}

// Method to update UI with plan data
- (void)updateUIWithPlanData {
    NSLog(@"[WeaponX] 🔄 Updating account UI with latest plan data");
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *planData = [defaults objectForKey:@"WeaponXUserPlan"];
    
    if (planData) {
        // Update plan name label
        NSString *planName = [planData objectForKey:@"user_plan_name"];
        
        // If plan name is null/nil or empty, try to get it from the plan dictionary
        if ((!planName || [planName length] == 0) && [planData objectForKey:@"plan"] && 
            [[planData objectForKey:@"plan"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *plan = [planData objectForKey:@"plan"];
            
            // Try to get plan name from the plan dictionary
            if ([plan objectForKey:@"name"] && [[plan objectForKey:@"name"] length] > 0) {
                planName = [plan objectForKey:@"name"];
                NSLog(@"[WeaponX] ℹ️ Using plan name from plan dictionary: %@", planName);
            } 
            // If no name but we have ID, use that
            else if ([plan objectForKey:@"id"]) {
                planName = [NSString stringWithFormat:@"Plan %@", [plan objectForKey:@"id"]];
                NSLog(@"[WeaponX] ℹ️ Using plan ID as name: %@", planName);
            }
            // Last resort - use a generic name if we have days remaining
            else if ([plan objectForKey:@"days_remaining"] && 
                    [[plan objectForKey:@"days_remaining"] integerValue] > 0) {
                planName = @"Active Plan";
                NSLog(@"[WeaponX] ℹ️ Using generic name 'Active Plan' because days remaining > 0");
            }
        }
        
        if (planName && self.planNameLabel) {
            self.planNameLabel.text = planName;
            NSLog(@"[WeaponX] ✅ Updated plan name label: %@", planName);
        } else if (self.planNameLabel) {
            // If still no plan name but we know the plan is active (from expiry date), use a generic name
            if (self.planExpiryLabel && self.planExpiryLabel.text && 
                [self.planExpiryLabel.text containsString:@"Expires:"]) {
                self.planNameLabel.text = @"Active Plan";
                NSLog(@"[WeaponX] ℹ️ Using fallback name 'Active Plan' based on expiry date");
            } else {
                self.planNameLabel.text = @"Unknown Plan";
                NSLog(@"[WeaponX] ⚠️ Using fallback name 'Unknown Plan'");
            }
        }
        
        // Update plan expiry label
        NSString *expiryString = [planData objectForKey:@"expiry_date"];
        if (expiryString && self.planExpiryLabel) {
            // Format date for display
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
            NSDate *expiryDate = [formatter dateFromString:expiryString];
            
            if (expiryDate) {
                [formatter setDateFormat:@"MMM d, yyyy"];
                NSString *formattedDate = [formatter stringFromDate:expiryDate];
                self.planExpiryLabel.text = [NSString stringWithFormat:@"Expires: %@", formattedDate];
                NSLog(@"[WeaponX] ✅ Updated plan expiry label: %@", formattedDate);
            } else {
                self.planExpiryLabel.text = [NSString stringWithFormat:@"Expires: %@", expiryString];
            }
        }
        
        // Update plan value label if it exists
        if (self.planValueLabel) {
            BOOL hasPlan = [[planData objectForKey:@"has_plan"] boolValue];
            
            // Also check for days remaining or valid expiration date
            BOOL hasValidExpiration = NO;
            
            // Check expiry date from plan data
            NSString *expiryString = nil;
            if ([planData objectForKey:@"plan"] && [[planData objectForKey:@"plan"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *plan = [planData objectForKey:@"plan"];
                
                // Check for explicit expiration date
                if ([plan objectForKey:@"expiration_date"]) {
                    expiryString = [[plan objectForKey:@"expiration_date"] description];
                    
                    // Parse the date to check if it's in the future
                    if (expiryString.length > 0) {
                        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                        [formatter setDateFormat:@"yyyy-MM-dd"];
                        NSDate *expiryDate = [formatter dateFromString:expiryString];
                        
                        if (expiryDate && [expiryDate compare:[NSDate date]] == NSOrderedDescending) {
                            hasValidExpiration = YES;
                            NSLog(@"[WeaponX] ✅ Plan has valid expiration date in the future: %@", expiryString);
                        }
                    }
                }
                
                // Check for days remaining
                if ([plan objectForKey:@"days_remaining"]) {
                    NSInteger daysRemaining = [[plan objectForKey:@"days_remaining"] integerValue];
                    if (daysRemaining > 0) {
                        hasValidExpiration = YES;
                        NSLog(@"[WeaponX] ✅ Plan has days remaining: %ld", (long)daysRemaining);
                    }
                }
            }
            
            // If we have days remaining or a valid expiration date, the plan should be considered active
            // regardless of what the has_plan flag says
            if (hasValidExpiration) {
                hasPlan = YES;
                NSLog(@"[WeaponX] ✅ Overriding plan status to ACTIVE because days remaining or valid expiration date exists");
            }
            
            // Set UI based on determined status
            self.planValueLabel.text = hasPlan ? @"ACTIVE" : @"INACTIVE";
            self.planValueLabel.textColor = hasPlan ? [UIColor greenColor] : [UIColor redColor];
            NSLog(@"[WeaponX] ✅ Updated plan value label: %@", hasPlan ? @"ACTIVE" : @"INACTIVE");
            
            // Also update the NSUserDefaults for consistency
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setBool:hasPlan forKey:@"WeaponXHasActivePlan"];
            [defaults synchronize];
        }
        
        // Log plan info for debugging
        NSLog(@"[WeaponX] Plan info from updated UI - Name: %@, Expiry: %@", 
              self.planNameLabel.text, self.planExpiryLabel.text);
    } else {
        NSLog(@"[WeaponX] ⚠️ No plan data available to update UI");
        
        // Set default values if no plan data
        if (self.planNameLabel) {
            self.planNameLabel.text = @"No Plan";
        }
        if (self.planExpiryLabel) {
            self.planExpiryLabel.text = @"Not Applicable";
        }
        if (self.planValueLabel) {
            self.planValueLabel.text = @"INACTIVE";
            self.planValueLabel.textColor = [UIColor redColor];
        }
    }
    
    // Refresh the view layout
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

// Method to handle plan data updated notification
- (void)handlePlanDataUpdated:(NSNotification *)notification {
    NSLog(@"[WeaponX] 🔄 AccountViewController received plan data updated notification");
    
    // Only update UI if view is visible
    if (self.isViewLoaded && self.view.window) {
        // Update UI with the new plan data
        [self updateUIWithPlanData];
        
        // Post a notification that the UI has been updated
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXAccountUIUpdated" object:nil];
    }
}

// Add this method below extractDaysRemainingFromExpiryLabel
- (void)animateDaysRemainingButtonCounter:(NSInteger)daysRemaining {
    // Initial setup
    self.daysRemainingLabel.alpha = 1.0;
    
    // Start with 0
    self.daysRemainingLabel.text = @"0 DAYS REMAINING";
    
    // Setup timer for counting animation
    NSTimeInterval animationDuration = 1.5; // Total animation time
    NSTimeInterval interval = animationDuration / MIN(daysRemaining, 30); // Cap at 30 steps max
    
    // Calculate step size to avoid too many updates for large numbers
    NSInteger stepSize = daysRemaining > 30 ? MAX(1, daysRemaining / 30) : 1;
    __block NSInteger currentCount = 0;
    
    // Setup timer
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        currentCount += stepSize;
        
        if (currentCount >= daysRemaining) {
            // Final value
            currentCount = daysRemaining;
            [timer invalidate];
            
            // Show the final text and start the subtle glow animation
            self.daysRemainingLabel.text = [NSString stringWithFormat:@"%ld DAYS REMAINING", (long)daysRemaining];
            [self setupPulseAnimationForLabel:self.daysRemainingLabel];
        } else {
            // Update with current count during animation
            self.daysRemainingLabel.text = [NSString stringWithFormat:@"%ld DAYS REMAINING", (long)currentCount];
        }
    }];
    
    // Start the timer
    [timer fire];
}

// Helper method to check if user has claimed trial from plan data
- (BOOL)hasUserClaimedTrialFromPlanData:(NSDictionary *)planData {
    BOOL hasUsedTrial = NO;
    
    NSLog(@"[WeaponX] Checking trial status from plan data: %@", planData);
    
    if (!planData) {
        return NO;
    }
    
    // Check all possible paths for trial status
    if ([planData objectForKey:@"has_used_trial"] != nil) {
        hasUsedTrial = [planData[@"has_used_trial"] boolValue];
        NSLog(@"[WeaponX] Found has_used_trial in root: %@", hasUsedTrial ? @"YES" : @"NO");
    } else if ([planData objectForKey:@"trial_used"] != nil) {
        hasUsedTrial = [planData[@"trial_used"] boolValue];
        NSLog(@"[WeaponX] Found trial_used in root: %@", hasUsedTrial ? @"YES" : @"NO");
    } else if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
        // Check in plan object
        NSDictionary *planObj = planData[@"plan"];
        
        if ([planObj objectForKey:@"has_used_trial"] != nil) {
            hasUsedTrial = [planObj[@"has_used_trial"] boolValue];
            NSLog(@"[WeaponX] Found has_used_trial in plan: %@", hasUsedTrial ? @"YES" : @"NO");
        } else if ([planObj objectForKey:@"trial_used"] != nil) {
            hasUsedTrial = [planObj[@"trial_used"] boolValue];
            NSLog(@"[WeaponX] Found trial_used in plan: %@", hasUsedTrial ? @"YES" : @"NO");
        } else if ([planObj objectForKey:@"is_trial"] != nil && [planObj[@"is_trial"] boolValue]) {
            // Current plan is a trial plan
            hasUsedTrial = YES;
            NSLog(@"[WeaponX] Current plan is marked as trial");
        } else if (planObj[@"id"] != nil && ([planObj[@"id"] isEqual:@(1)] || [planObj[@"id"] isEqual:@"1"])) {
            // Plan ID 1 is the trial plan
            hasUsedTrial = YES;
            NSLog(@"[WeaponX] Current plan has ID 1 (trial plan)");
        }
    } else if (planData[@"history"] && [planData[@"history"] isKindOfClass:[NSArray class]]) {
        // Check if user had trial plan in history
        NSArray *history = planData[@"history"];
        for (NSDictionary *historyItem in history) {
            if ([historyItem isKindOfClass:[NSDictionary class]]) {
                if ([historyItem[@"plan_id"] isEqual:@(1)] || [historyItem[@"plan_id"] isEqual:@"1"]) {
                    hasUsedTrial = YES;
                    NSLog(@"[WeaponX] Found trial plan in history");
                    break;
                }
            }
        }
    }
    
    return hasUsedTrial;
}

- (void)openSupportTicketForPlan:(NSDictionary *)plan {
    // This method opens the support ticket screen for creating a purchase request
    
    // Create and present the support view controller
    SupportViewController *supportVC = [[SupportViewController alloc] init];
    supportVC.tabBarController = self.tabBarController;
    
    // Store plan information in user defaults temporarily for the support ticket
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:plan[@"id"] forKey:@"PendingPurchasePlanId"];
    [defaults setObject:plan[@"name"] forKey:@"PendingPurchasePlanName"];
    [defaults setObject:plan[@"price"] forKey:@"PendingPurchasePlanPrice"];
    [defaults synchronize];
    
    // Present support view in a navigation controller
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:supportVC];
    [self presentViewController:navController animated:YES completion:nil];
}

// Add this after showManualPaymentInstructions method
- (void)dismissManualPaymentView:(UIButton *)sender {
    // Safely dismiss the presented view controller
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Add debug methods for touch events
- (void)loginButtonTouchDown:(UIButton *)sender {
    NSLog(@"[WeaponX] 👇 Login button touch down detected");
}

- (void)loginButtonTouchUpInside:(UIButton *)sender {
    NSLog(@"[WeaponX] 👆 Login button touch up inside detected");
    // Call loginButtonTapped directly to ensure it gets called
    [self loginButtonTapped];
}

- (void)loginViewTapped:(UITapGestureRecognizer *)gestureRecognizer {
    NSLog(@"[WeaponX] 👆 Login view tapped at: %@", NSStringFromCGPoint([gestureRecognizer locationInView:self.loginView]));
}

- (void)loginButtonDirectTap:(UITapGestureRecognizer *)gestureRecognizer {
    NSLog(@"[WeaponX] 👆 Login button direct tap detected");
    [self loginButtonTapped];
}

@end
