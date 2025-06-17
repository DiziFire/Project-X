#import "LoginViewController.h"
#import <UIKit/UIKit.h>
#import "TabBarController.h"
#import "SignupViewController.h"
#import "TokenManager.h"
#import <IOKit/IOKitLib.h>
#import <sys/utsname.h>

@interface LoginViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *logoImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *passwordVisibilityButton;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *signupButton;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Login";
    
    // Set hacker theme
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor blackColor];
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    } else {
        self.view.backgroundColor = [UIColor blackColor];
    }
    
    [self setupUI];
    
    // Add tap gesture to dismiss keyboard when tapping outside text fields
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO; // Allow touches to pass through to subviews
    [self.view addGestureRecognizer:tapGesture];
    
    // Load and pre-fill last successful login credentials if available
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

- (void)setupUI {
    // Card View (Container) with hacker style
    self.cardView = [[UIView alloc] init];
    self.cardView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.12 alpha:1.0]; // Very dark blue-gray
    self.cardView.layer.cornerRadius = 8.0; // More angular for hacker style
    self.cardView.layer.borderWidth = 1.0;
    self.cardView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.6].CGColor; // Neon green border
    self.cardView.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8].CGColor; // Neon green glow
    self.cardView.layer.shadowOffset = CGSizeMake(0, 0);
    self.cardView.layer.shadowRadius = 10.0;
    self.cardView.layer.shadowOpacity = 0.5;
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cardView];
    
    // Logo Image View with hacker theme
    self.logoImageView = [[UIImageView alloc] init];
    self.logoImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.logoImageView.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    self.logoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Use a system symbol for the logo with hacker theme
    if (@available(iOS 13.0, *)) {
        self.logoImageView.image = [UIImage systemImageNamed:@"lock.shield.fill"];
    } else {
        // Fallback for older iOS versions
        self.logoImageView.image = [UIImage imageNamed:@"AppIcon"];
    }
    [self.cardView addSubview:self.logoImageView];
    
    // Title Label with hacker theme
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @">> WEAPON X ACCESS";
    self.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:22.0] ?: [UIFont boldSystemFontOfSize:22.0];
    self.titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:self.titleLabel];
    
    // Subtitle Label with hacker theme
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = @"AUTHORIZATION REQUIRED";
    subtitleLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    subtitleLabel.textColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1.0]; // Light gray
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:subtitleLabel];
    
    // Email Container with hacker theme
    UIView *emailContainer = [[UIView alloc] init];
    emailContainer.translatesAutoresizingMaskIntoConstraints = NO;
    emailContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0]; // Slightly lighter dark
    emailContainer.layer.cornerRadius = 6.0; // More angular for hacker style
    emailContainer.layer.borderWidth = 1.0;
    emailContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4].CGColor; // Subtle neon border
    [self.cardView addSubview:emailContainer];
    
    // Email icon with hacker theme
    UIImageView *emailIcon = [[UIImageView alloc] init];
    emailIcon.translatesAutoresizingMaskIntoConstraints = NO;
    emailIcon.contentMode = UIViewContentModeScaleAspectFit;
    emailIcon.image = [UIImage systemImageNamed:@"envelope.fill"];
    emailIcon.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    [emailContainer addSubview:emailIcon];
    
    // Email Field with hacker theme
    self.emailField = [[UITextField alloc] init];
    self.emailField.placeholder = @"Email ID";
    self.emailField.attributedPlaceholder = [[NSAttributedString alloc] 
                                           initWithString:@"Email ID" 
                                           attributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0]}];
    self.emailField.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green text
    self.emailField.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.emailField.keyboardAppearance = UIKeyboardAppearanceDark; // Dark keyboard
    self.emailField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.emailField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.emailField.borderStyle = UITextBorderStyleNone;
    self.emailField.backgroundColor = [UIColor clearColor];
    self.emailField.returnKeyType = UIReturnKeyNext;
    self.emailField.delegate = self;
    self.emailField.translatesAutoresizingMaskIntoConstraints = NO;
    [emailContainer addSubview:self.emailField];
    
    // Password Container with hacker theme
    UIView *passwordContainer = [[UIView alloc] init];
    passwordContainer.translatesAutoresizingMaskIntoConstraints = NO;
    passwordContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0]; // Slightly lighter dark
    passwordContainer.layer.cornerRadius = 6.0; // More angular for hacker style
    passwordContainer.layer.borderWidth = 1.0;
    passwordContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4].CGColor; // Subtle neon border
    [self.cardView addSubview:passwordContainer];
    
    // Password icon with hacker theme
    UIImageView *passwordIcon = [[UIImageView alloc] init];
    passwordIcon.translatesAutoresizingMaskIntoConstraints = NO;
    passwordIcon.contentMode = UIViewContentModeScaleAspectFit;
    passwordIcon.image = [UIImage systemImageNamed:@"lock.fill"];
    passwordIcon.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    [passwordContainer addSubview:passwordIcon];
    
    // Password Field with hacker theme
    self.passwordField = [[UITextField alloc] init];
    self.passwordField.placeholder = @"Passkey";
    self.passwordField.attributedPlaceholder = [[NSAttributedString alloc] 
                                              initWithString:@"Passkey" 
                                              attributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0]}];
    self.passwordField.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green text
    self.passwordField.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.passwordField.secureTextEntry = YES;
    self.passwordField.keyboardAppearance = UIKeyboardAppearanceDark; // Dark keyboard
    self.passwordField.borderStyle = UITextBorderStyleNone;
    self.passwordField.backgroundColor = [UIColor clearColor];
    self.passwordField.returnKeyType = UIReturnKeyDone;
    self.passwordField.delegate = self;
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    [passwordContainer addSubview:self.passwordField];
    
    // Password Visibility Button (Eye Icon) with hacker theme
    self.passwordVisibilityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        [self.passwordVisibilityButton setImage:[UIImage systemImageNamed:@"eye.slash"] forState:UIControlStateNormal];
    } else {
        [self.passwordVisibilityButton setTitle:@"👁" forState:UIControlStateNormal];
    }
    self.passwordVisibilityButton.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8]; // Neon green
    self.passwordVisibilityButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.passwordVisibilityButton addTarget:self action:@selector(togglePasswordVisibility) forControlEvents:UIControlEventTouchUpInside];
    [passwordContainer addSubview:self.passwordVisibilityButton]; // Add to password container instead of card view
    
    // Login Button with hacker style
    self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.loginButton setTitle:@"ACCESS SYSTEM" forState:UIControlStateNormal];
    [self.loginButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.loginButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    self.loginButton.layer.cornerRadius = 6.0; // More angular for hacker style
    self.loginButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16.0] ?: [UIFont boldSystemFontOfSize:16.0];
    self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    // Explicitly enable user interaction
    self.loginButton.userInteractionEnabled = YES;
    // Add shadow to make button more visible
    self.loginButton.clipsToBounds = NO;
    self.loginButton.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
    self.loginButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.loginButton.layer.shadowRadius = 8.0;
    self.loginButton.layer.shadowOpacity = 0.8;
    [self.loginButton addTarget:self action:@selector(loginButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.loginButton];
    
    // Signup Button with hacker style
    self.signupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.signupButton setTitle:@"REGISTER NEW IDENTITY" forState:UIControlStateNormal];
    [self.signupButton setTitleColor:[UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8] forState:UIControlStateNormal]; // Neon green
    self.signupButton.titleLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont systemFontOfSize:12.0];
    self.signupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.signupButton addTarget:self action:@selector(signupButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.signupButton];
    
    // Activity Indicator with hacker theme
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.color = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    self.activityIndicator.hidesWhenStopped = YES;
    [self.cardView addSubview:self.activityIndicator];
    
    // Card View constraints
    [NSLayoutConstraint activateConstraints:@[
        // Card View
        [self.cardView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-50], // Move card up a bit
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        // Logo Image View
        [self.logoImageView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:30],
        [self.logoImageView.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.logoImageView.widthAnchor constraintEqualToConstant:60],
        [self.logoImageView.heightAnchor constraintEqualToConstant:60],
        
        // Title Label
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.logoImageView.bottomAnchor constant:16],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        
        // Subtitle Label
        [subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        
        // Email Container
        [emailContainer.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:25],
        [emailContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [emailContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [emailContainer.heightAnchor constraintEqualToConstant:50],
        
        // Email Icon
        [emailIcon.leadingAnchor constraintEqualToAnchor:emailContainer.leadingAnchor constant:15],
        [emailIcon.centerYAnchor constraintEqualToAnchor:emailContainer.centerYAnchor],
        [emailIcon.widthAnchor constraintEqualToConstant:20],
        [emailIcon.heightAnchor constraintEqualToConstant:20],
        
        // Email Field
        [self.emailField.leadingAnchor constraintEqualToAnchor:emailIcon.trailingAnchor constant:10],
        [self.emailField.trailingAnchor constraintEqualToAnchor:emailContainer.trailingAnchor constant:-15],
        [self.emailField.topAnchor constraintEqualToAnchor:emailContainer.topAnchor],
        [self.emailField.bottomAnchor constraintEqualToAnchor:emailContainer.bottomAnchor],
        
        // Password Container
        [passwordContainer.topAnchor constraintEqualToAnchor:emailContainer.bottomAnchor constant:15],
        [passwordContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [passwordContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [passwordContainer.heightAnchor constraintEqualToConstant:50],
        
        // Password Icon
        [passwordIcon.leadingAnchor constraintEqualToAnchor:passwordContainer.leadingAnchor constant:15],
        [passwordIcon.centerYAnchor constraintEqualToAnchor:passwordContainer.centerYAnchor],
        [passwordIcon.widthAnchor constraintEqualToConstant:20],
        [passwordIcon.heightAnchor constraintEqualToConstant:20],
        
        // Password Field
        [self.passwordField.leadingAnchor constraintEqualToAnchor:passwordIcon.trailingAnchor constant:10],
        [self.passwordField.trailingAnchor constraintEqualToAnchor:self.passwordVisibilityButton.leadingAnchor constant:-5],
        [self.passwordField.topAnchor constraintEqualToAnchor:passwordContainer.topAnchor],
        [self.passwordField.bottomAnchor constraintEqualToAnchor:passwordContainer.bottomAnchor],
        
        // Password Visibility Button
        [self.passwordVisibilityButton.centerYAnchor constraintEqualToAnchor:passwordContainer.centerYAnchor],
        [self.passwordVisibilityButton.trailingAnchor constraintEqualToAnchor:passwordContainer.trailingAnchor constant:-10],
        [self.passwordVisibilityButton.widthAnchor constraintEqualToConstant:30],
        [self.passwordVisibilityButton.heightAnchor constraintEqualToConstant:30],
        
        // Login Button
        [self.loginButton.topAnchor constraintEqualToAnchor:passwordContainer.bottomAnchor constant:25],
        [self.loginButton.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.loginButton.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.loginButton.heightAnchor constraintEqualToConstant:50],
        
        // Signup Button
        [self.signupButton.topAnchor constraintEqualToAnchor:self.loginButton.bottomAnchor constant:15],
        [self.signupButton.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.signupButton.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-20],
        
        // Activity Indicator
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.loginButton.centerYAnchor]
    ]];
    
    // Contact Support Section (outside card view)
    UILabel *contactSupportLabel = [[UILabel alloc] init];
    contactSupportLabel.text = @"CONTACT SUPPORT";
    contactSupportLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    contactSupportLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    contactSupportLabel.textAlignment = NSTextAlignmentCenter;
    contactSupportLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:contactSupportLabel];
    
    // Social Icons Stack View
    UIStackView *socialIconsStack = [[UIStackView alloc] init];
    socialIconsStack.axis = UILayoutConstraintAxisHorizontal;
    socialIconsStack.distribution = UIStackViewDistributionEqualSpacing;
    socialIconsStack.alignment = UIStackViewAlignmentCenter;
    socialIconsStack.spacing = 30;
    socialIconsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:socialIconsStack];
    
    // Telegram Button
    UIButton *telegramButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [telegramButton setImage:[UIImage systemImageNamed:@"paperplane.fill"] forState:UIControlStateNormal];
    telegramButton.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    [telegramButton addTarget:self action:@selector(openTelegram) forControlEvents:UIControlEventTouchUpInside];
    
    // Web Button
    UIButton *webButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [webButton setImage:[UIImage systemImageNamed:@"globe"] forState:UIControlStateNormal];
    webButton.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    [webButton addTarget:self action:@selector(openWebsite) forControlEvents:UIControlEventTouchUpInside];
    
    // Add buttons to stack view
    [socialIconsStack addArrangedSubview:telegramButton];
    [socialIconsStack addArrangedSubview:webButton];
    
    // Constraints for contact support section
    [NSLayoutConstraint activateConstraints:@[
        // Contact Support Label
        [contactSupportLabel.topAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:30],
        [contactSupportLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        // Social Icons Stack
        [socialIconsStack.topAnchor constraintEqualToAnchor:contactSupportLabel.bottomAnchor constant:15],
        [socialIconsStack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [socialIconsStack.heightAnchor constraintEqualToConstant:44],
        
        // Individual icon sizes
        [telegramButton.widthAnchor constraintEqualToConstant:44],
        [telegramButton.heightAnchor constraintEqualToConstant:44],
        [webButton.widthAnchor constraintEqualToConstant:44],
        [webButton.heightAnchor constraintEqualToConstant:44]
    ]];
}

- (void)togglePasswordVisibility {
    // Toggle password visibility
    self.passwordField.secureTextEntry = !self.passwordField.secureTextEntry;
    
    // Update the button image
    if (@available(iOS 13.0, *)) {
        UIImage *image = self.passwordField.secureTextEntry ? 
            [UIImage systemImageNamed:@"eye.slash"] : 
            [UIImage systemImageNamed:@"eye"];
        [self.passwordVisibilityButton setImage:image forState:UIControlStateNormal];
    } else {
        // Fallback for earlier iOS versions
        NSString *title = self.passwordField.secureTextEntry ? @"👁" : @"🙈";
        [self.passwordVisibilityButton setTitle:title forState:UIControlStateNormal];
    }
}

- (void)loginButtonTapped {
    NSLog(@"[WeaponX] Login button tapped - starting login process");
    [self.activityIndicator startAnimating];
    self.loginButton.enabled = NO;
    
    // Add hacker-style glitch animation for button
    [self addGlitchAnimation:self.loginButton];
    
    NSString *email = self.emailField.text;
    NSString *password = self.passwordField.text;
    
    // Validate input
    if (!email.length || !password.length) {
        [self showHackerAlertWithTitle:@"Input Error" message:@"Email and password required"];
        [self.activityIndicator stopAnimating];
        self.loginButton.enabled = YES; // Re-enable button on validation error
        return;
    }
    
    // Enhanced logging
    NSLog(@"[WeaponX] Starting login process for email: %@", email);
    
    // Try multiple URL formats for shared hosting compatibility
    // Only use production URLs
    NSArray *possibleURLs = @[
        @"https://hydra.weaponx.us/api/login",
        @"https://hydra.weaponx.us/index.php/api/login",
        @"https://hydra.weaponx.us/login"
    ];
    
    [self tryLoginWithURLs:possibleURLs atIndex:0 email:email password:password];
}

// New method to try login with multiple URLs
- (void)tryLoginWithURLs:(NSArray *)urls atIndex:(NSUInteger)index email:(NSString *)email password:(NSString *)password {
    if (index >= urls.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            self.loginButton.enabled = YES;
            [self showHackerAlertWithTitle:@"Connection Error" message:@"Unable to establish secure connection to server"];
        });
        return;
    }
    
    NSString *urlString = urls[index];
    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[WeaponX] Trying login URL (%lu of %lu): %@", (unsigned long)(index + 1), (unsigned long)urls.count, url);
    
    // First, check if we need to get a CSRF token
    if ([urlString containsString:@"hydra.weaponx.us"]) {
        // For the production server, we'll first make a GET request to get the CSRF token
        [self getCSRFTokenForURL:urlString completion:^(NSString *csrfToken) {
            [self performLoginWithURL:urlString csrfToken:csrfToken email:email password:password completion:^(BOOL success, NSHTTPURLResponse *response, NSData *data, NSError *error) {
                if (!success) {
                    // Try the next URL if this one failed
                    [self tryLoginWithURLs:urls atIndex:index + 1 email:email password:password];
                } else {
                    // Handle the successful response
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self handleLoginResponse:data response:response error:error email:email password:password];
                    });
                }
            }];
        }];
    } else {
        // For local development, we'll skip the CSRF token
        // But we'll still use a session configuration that handles cookies properly
        [self performLoginWithURL:urlString csrfToken:nil email:email password:password completion:^(BOOL success, NSHTTPURLResponse *response, NSData *data, NSError *error) {
            if (!success) {
                // Try the next URL if this one failed
                [self tryLoginWithURLs:urls atIndex:index + 1 email:email password:password];
            } else {
                // Handle the successful response
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self handleLoginResponse:data response:response error:error email:email password:password];
                });
            }
        }];
    }
}

// Helper method to get CSRF token
- (void)getCSRFTokenForURL:(NSString *)urlString completion:(void (^)(NSString *))completion {
    // Extract the base URL (without the path)
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *baseURLString = [NSString stringWithFormat:@"%@://%@", url.scheme, url.host];
    NSURL *baseURL = [NSURL URLWithString:baseURLString];
    
    NSLog(@"[WeaponX] Getting CSRF token from: %@", baseURLString);
    
    // First, clear any existing cookies for this domain to avoid stale tokens
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *existingCookies = [cookieStorage cookiesForURL:baseURL];
    for (NSHTTPCookie *cookie in existingCookies) {
        NSLog(@"[WeaponX] Removing existing cookie: %@ = %@", cookie.name, cookie.value);
        [cookieStorage deleteCookie:cookie];
    }
    
    // Create a session configuration that allows cookies
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
    configuration.HTTPShouldSetCookies = YES;
    configuration.HTTPCookieStorage = cookieStorage;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:baseURL];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];  // Laravel recognizes this as an AJAX request
    request.HTTPShouldHandleCookies = YES;
    
    NSLog(@"[WeaponX] Sending request headers: %@", [request allHTTPHeaderFields]);
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] Error getting CSRF token: %@", error);
            completion(nil);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] CSRF token response status: %ld", (long)httpResponse.statusCode);
        
        NSString *csrfToken = nil;
        
        // Check for Set-Cookie header which might contain the XSRF-TOKEN
        NSDictionary *headers = httpResponse.allHeaderFields;
        NSLog(@"[WeaponX] Response headers: %@", headers);
        
        // Check for Set-Cookie header
        NSString *setCookieHeader = headers[@"Set-Cookie"];
        if (setCookieHeader) {
            NSLog(@"[WeaponX] Set-Cookie header found: %@", setCookieHeader);
            if ([setCookieHeader containsString:@"XSRF-TOKEN"]) {
                NSArray *cookieParts = [setCookieHeader componentsSeparatedByString:@";"];
                for (NSString *part in cookieParts) {
                    if ([part containsString:@"XSRF-TOKEN"]) {
                        NSArray *tokenParts = [part componentsSeparatedByString:@"="];
                        if (tokenParts.count > 1) {
                            csrfToken = tokenParts[1];
                            NSLog(@"[WeaponX] Extracted CSRF token from Set-Cookie: %@", csrfToken);
                        }
                    }
                }
            }
        }
        
        // Log all cookies for debugging
        NSArray *cookies = [cookieStorage cookiesForURL:baseURL];
        NSLog(@"[WeaponX] All cookies after request for %@:", baseURLString);
        for (NSHTTPCookie *cookie in cookies) {
            NSLog(@"[WeaponX] Cookie: %@ = %@", cookie.name, cookie.value);
            if ([cookie.name isEqualToString:@"XSRF-TOKEN"]) {
                csrfToken = cookie.value;
                NSLog(@"[WeaponX] Found CSRF token in cookies: %@", csrfToken);
            }
        }
        
        // Also check response headers for CSRF token
        for (NSString *key in headers) {
            if ([key caseInsensitiveCompare:@"X-CSRF-TOKEN"] == NSOrderedSame) {
                csrfToken = headers[key];
                NSLog(@"[WeaponX] Found CSRF token in headers: %@", csrfToken);
                break;
            }
        }
        
        // If we found a token, URL decode it if needed
        if (csrfToken) {
            csrfToken = [csrfToken stringByRemovingPercentEncoding];
            NSLog(@"[WeaponX] URL decoded CSRF token: %@", csrfToken);
        } else {
            NSLog(@"[WeaponX] No CSRF token found in cookies or headers");
            // Try to parse the response body for a token
            if (data) {
                NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"[WeaponX] Response body: %@", responseString);
                
                // Try to parse as JSON
                NSError *jsonError;
                NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (!jsonError && jsonResponse[@"csrf_token"]) {
                    csrfToken = jsonResponse[@"csrf_token"];
                    NSLog(@"[WeaponX] Found CSRF token in response body: %@", csrfToken);
                }
            }
        }
        
        completion(csrfToken);
    }];
    
    [task resume];
}

// Helper method to perform login with optional CSRF token
- (void)performLoginWithURL:(NSString *)urlString csrfToken:(NSString *)csrfToken email:(NSString *)email password:(NSString *)password completion:(void (^)(BOOL success, NSHTTPURLResponse *response, NSData *data, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    
    // Create a session configuration that allows cookies
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
    configuration.HTTPShouldSetCookies = YES;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    request.HTTPShouldHandleCookies = YES;
    
    // Add CSRF token if available - use X-XSRF-TOKEN header which Laravel expects
    if (csrfToken) {
        [request setValue:csrfToken forHTTPHeaderField:@"X-XSRF-TOKEN"];
        NSLog(@"[WeaponX] Adding CSRF token to login request with header X-XSRF-TOKEN: %@", csrfToken);
    } else {
        NSLog(@"[WeaponX] No CSRF token available, proceeding without it since login route should be excluded from CSRF verification");
    }
    
    request.timeoutInterval = 30.0;
    
    // Convert email to lowercase to ensure case-insensitive login
    NSString *lowercaseEmail = [email lowercaseString];
    
    // Get device unique identifiers
    NSDictionary *deviceIdentifiers = [self getDeviceIdentifiers];
    
    // Create login payload
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
        @"email": lowercaseEmail,
        @"password": password,
        @"device_model": [self getDetailedDeviceModel],
        @"device_name": [[UIDevice currentDevice] name],
        @"system_version": [[UIDevice currentDevice] systemVersion]
    }];
    
    // Add device identifiers to the login payload if available
    if (deviceIdentifiers[@"device_uuid"]) {
        body[@"device_uuid"] = deviceIdentifiers[@"device_uuid"];
    }
    
    if (deviceIdentifiers[@"device_serial"]) {
        body[@"device_serial"] = deviceIdentifiers[@"device_serial"];
    }
    
    NSLog(@"[WeaponX] Login payload: %@", @{
        @"email": lowercaseEmail, 
        @"password": @"[REDACTED]",
        @"device_model": [self getDetailedDeviceModel],
        @"device_name": [[UIDevice currentDevice] name],
        @"system_version": [[UIDevice currentDevice] systemVersion],
        @"device_uuid": deviceIdentifiers[@"device_uuid"] ?: @"Not available",
        @"device_serial": deviceIdentifiers[@"device_serial"] ?: @"Not available"
    });
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    
    if (error) {
        NSLog(@"[WeaponX] Failed to serialize JSON: %@", error);
        if (completion) {
            completion(NO, nil, nil, error);
        }
        return;
    }
    
    [request setHTTPBody:jsonData];
    
    NSLog(@"[WeaponX] Sending login request to %@...", urlString);
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] Login response status code: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] Login response headers: %@", httpResponse.allHeaderFields);
        
        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[WeaponX] Login response body: %@", responseString);
        }
        
        if (error) {
            NSLog(@"[WeaponX] Network error during login with URL %@: %@", urlString, error);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, httpResponse, data, error);
                }
            });
            return;
        }
        
        // If we get a 404 or other error, consider it a failure
        if (httpResponse.statusCode == 404 || httpResponse.statusCode >= 500) {
            NSLog(@"[WeaponX] URL %@ returned status %ld, considering as failure", urlString, (long)httpResponse.statusCode);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, httpResponse, data, nil);
                }
            });
            return;
        }
        
        // If we get a CSRF token mismatch (419), try to get a new token and retry
        if (httpResponse.statusCode == 419) {
            NSLog(@"[WeaponX] CSRF token mismatch (419), trying to get a new token");
            [self getCSRFTokenForURL:urlString completion:^(NSString *newCsrfToken) {
                if (newCsrfToken) {
                    [self performLoginWithURL:urlString csrfToken:newCsrfToken email:email password:password completion:completion];
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) {
                            completion(NO, httpResponse, data, nil);
                        }
                    });
                }
            }];
            return;
        }
        
        // Consider any other response as a success for the URL attempt
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(YES, httpResponse, data, nil);
            }
        });
    }];
    
    [task resume];
}

// Handle login API response
- (void)handleLoginResponse:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error email:(NSString *)email password:(NSString *)password {
    dispatch_async(dispatch_get_main_queue(), ^{
    [self.activityIndicator stopAnimating];
        [UIView animateWithDuration:0.3 animations:^{
            self.loginButton.alpha = 1.0;
        }];
    });
    
    if (error) {
        NSLog(@"[WeaponX] Login error: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showHackerAlertWithTitle:@"Connection Error" message:@"Could not connect to server. Check your internet connection and try again."];
        });
                return;
            }
            
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    
    if (httpResponse.statusCode == 200) {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
            NSLog(@"[WeaponX] Error parsing login response: %@", jsonError);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showHackerAlertWithTitle:@"Login Failed" message:@"Invalid response from server. Try again later."];
            });
                return;
            }
            
        // Log the structure of the response to help with debugging
        NSLog(@"[WeaponX] Login response structure - Keys: %@", [json allKeys]);
        NSLog(@"[WeaponX] Login response message: %@", json[@"message"]);
        NSLog(@"[WeaponX] Login response has token: %@", json[@"token"] ? @"YES" : @"NO");
        NSLog(@"[WeaponX] Login response has user: %@", json[@"user"] ? @"YES" : @"NO");
        
        // Check if login was successful - either by "success" field or "message" field
        BOOL isSuccessful = [json[@"success"] boolValue] || 
                           ([json[@"message"] isKindOfClass:[NSString class]] && 
                            [json[@"message"] isEqualToString:@"Login successful"]);
        
        if (isSuccessful) {
            // Successfully authenticated
            
            NSLog(@"[WeaponX] Login successful: %@", json);
            
            // Check for minimum allowed version
            if (json[@"min_allowed_version"]) {
                NSString *minAllowedVersion = json[@"min_allowed_version"];
                NSLog(@"[WeaponX] Server returned minimum allowed version: %@", minAllowedVersion);
                
                // Get current app version
                NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                NSLog(@"[WeaponX] Current app version: %@", currentVersion);
                
                // Compare versions
                NSComparisonResult result = [currentVersion compare:minAllowedVersion options:NSNumericSearch];
                if (result == NSOrderedAscending) {
                    // Current version is lower than minimum allowed version
                    NSLog(@"[WeaponX] App version %@ is below minimum allowed version %@", currentVersion, minAllowedVersion);
                    
                    // If we have a hacking animation overlay, make sure it completes before showing the alert
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // First ensure any running animation completes or is hidden
                        [self completeOrHideHackingAnimation];
                        
                        NSString *message = [NSString stringWithFormat:@"This app version (%@) is no longer supported. Please update to version %@ or later. --- SERVERS ARE DOWN FOR OLD VERSIONS ---", currentVersion, minAllowedVersion];
                        
                        UIAlertController *alert = [UIAlertController 
                            alertControllerWithTitle:@"Update Required" 
                            message:message
                            preferredStyle:UIAlertControllerStyleAlert];
                        
                        UIAlertAction *updateAction = [UIAlertAction 
                            actionWithTitle:@"DOWNLOAD UPDATE" 
                            style:UIAlertActionStyleDefault 
                            handler:^(UIAlertAction * _Nonnull action) {
                                // Open the repository URL
                                NSURL *repoURL = [NSURL URLWithString:@"https://hydra.weaponx.us/repo/"];
                                if ([[UIApplication sharedApplication] canOpenURL:repoURL]) {
                                    [[UIApplication sharedApplication] openURL:repoURL options:@{} completionHandler:nil];
                                }
                            }];
                        
                        // Style the button to match the app's theme
                        [updateAction setValue:[UIColor systemBlueColor] forKey:@"titleTextColor"];
                        
                        [alert addAction:updateAction];
                        
                        // Present alert after ensuring animations are complete
                        [self presentViewController:alert animated:YES completion:nil];
                    });
                    
                    return;
                }
            }
            
            if (json[@"token"] && json[@"user"]) {
                // Extract token
    NSString *token = json[@"token"];
                NSDictionary *user = json[@"user"];
                
                // Extract user ID from token
                NSString *tokenUserId = [[TokenManager sharedInstance] extractUserIdFromToken:token];
                
                // Get user ID from user info
                NSString *userInfoId = [NSString stringWithFormat:@"%@", user[@"id"]];
                
                // Check if token user ID doesn't match the user info ID
                if (tokenUserId && ![tokenUserId isEqualToString:userInfoId]) {
                    NSLog(@"[WeaponX] WARNING: Token user ID (%@) doesn't match user info ID (%@)", 
                          tokenUserId, userInfoId);
                    
                    // Try to reset the token to match the user ID
                    [self resetUserTokenForUserId:userInfoId completion:^(NSString *newToken, NSError *tokenError) {
                        if (tokenError) {
                            NSLog(@"[WeaponX] Failed to reset user token: %@", tokenError);
                            
                            // Add additional logging for troubleshooting
                            if ([tokenError.domain isEqualToString:@"NSURLErrorDomain"]) {
                                NSLog(@"[WeaponX] Network error during token reset: %@", tokenError.localizedDescription);
                            } else if ([tokenError.domain isEqualToString:@"TokenManagerErrorDomain"]) {
                                NSLog(@"[WeaponX] Server error during token reset: %@", tokenError.localizedDescription);
                            }
                            
                            // Continue with the original token as fallback
                            NSLog(@"[WeaponX] Using original token as fallback");
                            [self completeLoginWithToken:token userInfo:user];
                        } else if (newToken) {
                            NSLog(@"[WeaponX] Successfully reset token to match user ID: %@", userInfoId);
                            
                            // Verify the new token format
                            NSString *newTokenUserId = [[TokenManager sharedInstance] extractUserIdFromToken:newToken];
                            
                            if (newTokenUserId && [newTokenUserId isEqualToString:userInfoId]) {
                                NSLog(@"[WeaponX] Verified new token has correct user ID: %@", newTokenUserId);
                            } else if (newTokenUserId) {
                                NSLog(@"[WeaponX] WARNING: New token still has incorrect user ID: %@ (expected: %@)", 
                                      newTokenUserId, userInfoId);
                            }
                            
                            // Add a short delay to ensure token propagation to server
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                // Use the new token instead
                                [self completeLoginWithToken:newToken userInfo:user];
                            });
                        } else {
                            NSLog(@"[WeaponX] Token reset did not return a new token, using original token as fallback");
                            // Continue with the original token as fallback
                            [self completeLoginWithToken:token userInfo:user];
                        }
                    }];
                } else {
                    // Token and user ID match, proceed normally
                    [self completeLoginWithToken:token userInfo:user];
                }
            } else {
                NSLog(@"[WeaponX] Login response missing token or user info");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showHackerAlertWithTitle:@"Login Failed" message:@"Invalid response from server. Try again later."];
                });
            }
        } else {
            // Server returned success = false or no success indicator
            NSLog(@"[WeaponX] Login failed: %@", json[@"message"]);
            NSString *errorMessage = json[@"message"] ?: @"Invalid credentials or server error.";
            
            // Additional check to avoid showing Access Denied when message indicates success
            if ([errorMessage isEqualToString:@"Login successful"]) {
                // This is actually a success case but our earlier check might have missed it
                // Try to extract token and user info as a fallback
                NSString *token = json[@"token"];
                NSDictionary *user = json[@"user"];
                
                if (token && user) {
                    NSLog(@"[WeaponX] Found valid token and user info despite missing success flag");
                    [self completeLoginWithToken:token userInfo:user];
                    return;
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showHackerAlertWithTitle:@"Access Denied" message:errorMessage];
            });
        }
    } else {
        // HTTP error
        NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"[WeaponX] Login failed with status code: %ld, response: %@", (long)httpResponse.statusCode, responseString);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showHackerAlertWithTitle:@"Login Failed" 
                                   message:[NSString stringWithFormat:@"Server returned status code: %ld", (long)httpResponse.statusCode]];
        });
    }
}

- (void)signupButtonTapped {
    // Present the dedicated signup view controller
    NSLog(@"[WeaponX] Opening dedicated signup screen");
    
    SignupViewController *signupVC = [[SignupViewController alloc] init];
    
    // Set completion handler to dismiss login screen after successful signup
    signupVC.signupCompletionHandler = ^{
        NSLog(@"[WeaponX] Signup completed successfully, returning to login screen");
        
        // We no longer dismiss the login screen since the user now needs to log in manually
        // Instead, the signup screen dismisses itself to show the login screen again
    };
    
    // Present the signup view controller modally
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:signupVC];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)toggleAlertPasswordVisibility:(UIButton *)sender {
    // Find the password field in the alert
    UIAlertController *alert = (UIAlertController *)self.presentedViewController;
    if (![alert isKindOfClass:[UIAlertController class]]) return;
    
    UITextField *passwordField = alert.textFields[2];
    passwordField.secureTextEntry = !passwordField.secureTextEntry;
    
    // Update the button image
    if (@available(iOS 13.0, *)) {
        UIImage *image = passwordField.secureTextEntry ? 
            [UIImage systemImageNamed:@"eye.slash"] : 
            [UIImage systemImageNamed:@"eye"];
        [sender setImage:image forState:UIControlStateNormal];
    } else {
        NSString *title = passwordField.secureTextEntry ? @"👁" : @"🙈";
        [sender setTitle:title forState:UIControlStateNormal];
    }
}

- (void)performSignupWithName:(NSString *)name email:(NSString *)email password:(NSString *)password {
    [self.activityIndicator startAnimating];
    self.signupButton.enabled = NO;
    
    // Validate input
    if (!name.length || !email.length || !password.length) {
        [self showHackerAlertWithTitle:@"Input Error" message:@"Please fill in all fields"];
        return;
    }
    
    // Enhanced logging
    NSLog(@"[WeaponX] Starting signup process for email: %@", email);
    
    // Try multiple URL formats for shared hosting compatibility
    // Include both HTTP and HTTPS options for local development
    NSArray *possibleURLs = @[
        @"https://hydra.weaponx.us/api/register",
        @"https://hydra.weaponx.us/index.php/api/register",
        @"https://hydra.weaponx.us/register",
        @"http://localhost/api/register",
        @"http://127.0.0.1/api/register",
        @"http://localhost:8000/api/register"  // Default Laravel development port
    ];
    
    [self tryRegistrationWithURLs:possibleURLs atIndex:0 name:name email:email password:password];
}

// New method to try registration with multiple URLs
- (void)tryRegistrationWithURLs:(NSArray *)urls atIndex:(NSUInteger)index name:(NSString *)name email:(NSString *)email password:(NSString *)password {
    if (index >= urls.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            self.signupButton.enabled = YES;
            [self showHackerAlertWithTitle:@"Connection Error" message:@"Unable to establish secure connection to server"];
        });
        return;
    }
    
    NSString *urlString = urls[index];
    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[WeaponX] Trying registration URL (%lu of %lu): %@", (unsigned long)(index + 1), (unsigned long)urls.count, url);
    
    // First, check if we need to get a CSRF token
    if ([urlString containsString:@"hydra.weaponx.us"]) {
        // For the production server, we'll first make a GET request to get the CSRF token
        [self getCSRFTokenForURL:urlString completion:^(NSString *csrfToken) {
            [self performRegistrationWithURL:urlString csrfToken:csrfToken name:name email:email password:password completion:^(BOOL success, NSHTTPURLResponse *response, NSData *data, NSError *error) {
                if (!success) {
                    // Try the next URL if this one failed
                    [self tryRegistrationWithURLs:urls atIndex:index + 1 name:name email:email password:password];
                } else {
                    // Handle the successful response
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self handleRegistrationResponse:data response:response error:error name:name email:email password:password];
                    });
                }
            }];
        }];
    } else {
        // For local development, we'll skip the CSRF token
        [self performRegistrationWithURL:urlString csrfToken:nil name:name email:email password:password completion:^(BOOL success, NSHTTPURLResponse *response, NSData *data, NSError *error) {
            if (!success) {
                // Try the next URL if this one failed
                [self tryRegistrationWithURLs:urls atIndex:index + 1 name:name email:email password:password];
            } else {
                // Handle the successful response
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self handleRegistrationResponse:data response:response error:error name:name email:email password:password];
                });
            }
        }];
    }
}

// Helper method to perform registration with optional CSRF token
- (void)performRegistrationWithURL:(NSString *)urlString csrfToken:(NSString *)csrfToken name:(NSString *)name email:(NSString *)email password:(NSString *)password completion:(void (^)(BOOL success, NSHTTPURLResponse *response, NSData *data, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Add CSRF token if available - use X-XSRF-TOKEN header which Laravel expects
    if (csrfToken) {
        [request setValue:csrfToken forHTTPHeaderField:@"X-XSRF-TOKEN"];
        NSLog(@"[WeaponX] Adding CSRF token to request with header X-XSRF-TOKEN: %@", csrfToken);
    }
    
    request.timeoutInterval = 30.0;
    
    NSDictionary *body = @{
        @"name": name,
        @"email": email,
        @"password": password,
        @"password_confirmation": password
    };
    
    NSLog(@"[WeaponX] Registration payload: %@", @{@"name": name, @"email": email, @"password": @"[REDACTED]", @"password_confirmation": @"[REDACTED]"});
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    
    if (error) {
        NSLog(@"[WeaponX] Failed to serialize JSON: %@", error);
        completion(NO, nil, nil, error);
        return;
    }
    
    request.HTTPBody = jsonData;
    
    NSLog(@"[WeaponX] Sending registration request to %@...", urlString);
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] Registration response status code: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] Registration response headers: %@", httpResponse.allHeaderFields);
        
        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[WeaponX] Registration response body: %@", responseString);
        }
            
            if (error) {
            NSLog(@"[WeaponX] Network error during registration with URL %@: %@", urlString, error);
            completion(NO, httpResponse, data, error);
                return;
            }
            
        // If we get a 404 or other error, consider it a failure
        if (httpResponse.statusCode == 404 || httpResponse.statusCode >= 500) {
            NSLog(@"[WeaponX] URL %@ returned status %ld, considering as failure", urlString, (long)httpResponse.statusCode);
            completion(NO, httpResponse, data, nil);
            return;
        }
        
        // If we get a CSRF token mismatch (419), try to get a new token and retry
        if (httpResponse.statusCode == 419) {
            NSLog(@"[WeaponX] CSRF token mismatch (419), trying to get a new token");
            [self getCSRFTokenForURL:urlString completion:^(NSString *newCsrfToken) {
                if (newCsrfToken) {
                    [self performRegistrationWithURL:urlString csrfToken:newCsrfToken name:name email:email password:password completion:completion];
                } else {
                    completion(NO, httpResponse, data, nil);
                }
            }];
                return;
            }
            
        // Consider any other response as a success for the URL attempt
        completion(YES, httpResponse, data, nil);
    }];
    
    [task resume];
}

// Helper method to handle registration response
- (void)handleRegistrationResponse:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error name:(NSString *)name email:(NSString *)email password:(NSString *)password {
    [self.activityIndicator stopAnimating];
    self.signupButton.enabled = YES;
    
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    
    if (httpResponse.statusCode != 200 && httpResponse.statusCode != 201) {
        // Try to parse error message from response if available
        NSString *errorMessage = @"REGISTRATION FAILED: SECURITY PROTOCOL VIOLATION";
        if (data) {
            NSError *jsonError;
            NSDictionary *errorJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!jsonError && errorJson[@"message"]) {
                errorMessage = [NSString stringWithFormat:@"REGISTRATION FAILED: %@", errorJson[@"message"]];
            } else if (!jsonError && errorJson[@"error"]) {
                errorMessage = [NSString stringWithFormat:@"REGISTRATION FAILED: %@", errorJson[@"error"]];
            }
            
            if (!jsonError) {
                NSLog(@"[WeaponX] Registration error JSON: %@", errorJson);
            } else {
                NSLog(@"[WeaponX] Failed to parse error JSON: %@", jsonError);
            }
        }
        NSLog(@"[WeaponX] Registration failed with status code: %ld, message: %@", (long)httpResponse.statusCode, errorMessage);
        [self showHackerAlertWithTitle:@"Registration Error" message:errorMessage];
        return;
    }
    
    // Handle successful registration
    NSLog(@"[WeaponX] Registration successful");
    
    // Show a success alert to the user
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@">> IDENTITY CREATED" 
                                                                   message:@"Your account has been successfully created. You can now log in with your credentials." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"ACCESS LOGIN" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // Dismiss the signup screen to return to login screen
        [self dismissViewControllerAnimated:YES completion:^{
            NSLog(@"[WeaponX] Returned to login screen after successful registration");
            
            // If we have a completion handler, call it with a NO parameter to indicate
            // that we should NOT auto-dismiss the login screen (since we want the user to log in)
            if (self.signupCompletionHandler) {
                // We're not passing any parameters since there's no auto-login
                self.signupCompletionHandler();
            }
        }];
    }];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

// Use TokenManager for token reset operations
- (void)resetUserTokenForUserId:(NSString *)userId completion:(void (^)(NSString *, NSError *))completion {
    NSLog(@"[WeaponX] LoginViewController requesting token reset for user ID: %@", userId);
    
    // Use the TokenManager to reset the token
    [[TokenManager sharedInstance] resetTokenForUserId:userId completion:^(NSString *newToken, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] Token reset failed: %@", error);
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        if (!newToken) {
            NSLog(@"[WeaponX] Token reset returned no new token");
            if (completion) {
                NSError *noTokenError = [NSError errorWithDomain:@"com.weaponx.auth" 
                                                           code:401 
                                                       userInfo:@{NSLocalizedDescriptionKey: @"No token returned from reset"}];
                completion(nil, noTokenError);
            }
            return;
        }
        
        NSLog(@"[WeaponX] Token reset successful, saving new token");
        
        // Save the new token via TokenManager to ensure proper storage
        NSString *extractedUserId = [[TokenManager sharedInstance] extractUserIdFromToken:newToken];
        [[TokenManager sharedInstance] saveToken:newToken withUserId:extractedUserId ?: userId];
        
        // Call completion with the new token
        if (completion) {
            completion(newToken, nil);
        }
    }];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.emailField) {
        [self.passwordField becomeFirstResponder];
    } else if (textField == self.passwordField) {
        [textField resignFirstResponder];
        [self loginButtonTapped];
    }
    return YES;
}

#pragma mark - User Plan Data

- (void)fetchUserPlanData:(NSString *)token {
    if (!token || token.length == 0) {
        NSLog(@"[WeaponX] Cannot fetch user plan: no auth token provided");
        return;
    }
    
    NSLog(@"[WeaponX] Fetching user plan data with token for user ID extraction");
    
    // Get user ID from defaults using TokenManager
    NSString *serverUserId = [[TokenManager sharedInstance] getServerUserId];
    
    // Try multiple URL formats for shared hosting compatibility
    NSArray *possibleURLs = @[
        [NSString stringWithFormat:@"%@/api/user/plan", [self apiBaseUrl]],
        [NSString stringWithFormat:@"%@/index.php/api/user/plan", [self apiBaseUrl]],
        [NSString stringWithFormat:@"%@/api/plan", [self apiBaseUrl]],  // Additional endpoint option
        [NSString stringWithFormat:@"%@/api/user", [self apiBaseUrl]]   // Fallback to user info which might include plan
    ];
    
    // Add delay before fetching plan data to allow token propagation
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Use our enhanced API request method with retry logic
        NSString *urlString = possibleURLs[0];
        NSURL *url = [NSURL URLWithString:urlString];
        
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        [headers setObject:[NSString stringWithFormat:@"Bearer %@", token] forKey:@"Authorization"];
        [headers setObject:@"application/json" forKey:@"Accept"];
        
        // Add server user ID if available to help server properly identify the user
        if (serverUserId) {
            [headers setObject:serverUserId forKey:@"X-User-Id"];
        }
        
        // Add token ID for debugging
        NSArray *tokenParts = [token componentsSeparatedByString:@"|"];
        if (tokenParts.count > 0) {
            [headers setObject:tokenParts[0] forKey:@"X-Token-Id"];
        }
        
        NSLog(@"[WeaponX] Fetching plan data with headers: %@", headers);
        
        // Use enhanced API request method with retry logic
        [self performAPIRequestWithURL:url 
                               method:@"GET" 
                                 body:nil 
                              headers:headers 
                           retryCount:0 
                           maxRetries:3 
                           completion:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (error || httpResponse.statusCode != 200 || !data) {
                NSLog(@"[WeaponX] Error fetching plan: %@, status: %ld", error, (long)httpResponse.statusCode);
                
                // Check for 401 status and try to reset token if needed
                if (httpResponse.statusCode == 401) {
                    NSLog(@"[WeaponX] Plan fetch returned 401, attempting token reset");
                    
                    // Try to reset the token if we have a user ID
                    if (serverUserId) {
                        [[TokenManager sharedInstance] resetTokenForUserId:serverUserId completion:^(NSString *newToken, NSError *tokenError) {
                            if (tokenError) {
                                NSLog(@"[WeaponX] Failed to reset token: %@", tokenError);
                            } else if (newToken) {
                                NSLog(@"[WeaponX] Successfully reset token, will retry plan fetch after delay");
                                // Try again with new token after a delay
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    [self fetchUserPlanData:newToken];
                                });
                            }
                        }];
                    }
                }
                
                // Try next URL if this one failed
                if (possibleURLs.count > 1) {
                    NSArray *remainingURLs = [possibleURLs subarrayWithRange:NSMakeRange(1, possibleURLs.count - 1)];
                    [self tryFetchPlanWithURLs:remainingURLs atIndex:0 token:token];
                } else {
                    // Create a default plan if we can't fetch from server
                    NSLog(@"[WeaponX] Failed to fetch plan from all URLs, creating default plan");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                        NSDictionary *defaultPlan = @{
                            @"plan": @"basic",
                            @"features": @[@"core_access", @"basic_features"]
                        };
                        [defaults setObject:defaultPlan forKey:@"WeaponXUserPlan"];
                        [defaults synchronize];
                        
                        // Post notification that plan data is available
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserPlanDidUpdate" object:nil];
                    });
                }
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] Failed to parse plan response: %@", jsonError);
            return;
        }
        
        NSLog(@"[WeaponX] Successfully fetched user plan: %@", json);
            
            // Check for nested plan data structure
            NSDictionary *planData = json;
            if (json[@"data"] && [json[@"data"] isKindOfClass:[NSDictionary class]]) {
                planData = json[@"data"];
                NSLog(@"[WeaponX] Found plan data in 'data' field");
            } else if (json[@"user"] && [json[@"user"] isKindOfClass:[NSDictionary class]] && 
                      json[@"user"][@"plan"] && [json[@"user"][@"plan"] isKindOfClass:[NSDictionary class]]) {
                planData = json[@"user"][@"plan"];
                NSLog(@"[WeaponX] Found plan data in 'user.plan' field");
            }
        
        // Save plan data
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:planData forKey:@"WeaponXUserPlan"];
            [defaults synchronize];
            
            // Post notification that plan data is available
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserPlanDidUpdate" object:nil];
        });
        }];
    });
}

// Method to perform API requests with retries after token reset
- (void)performAPIRequestWithURL:(NSURL *)url 
                          method:(NSString *)method 
                            body:(NSData *)body 
                         headers:(NSDictionary *)headers 
                      retryCount:(NSInteger)retryCount 
                      maxRetries:(NSInteger)maxRetries 
                      completion:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completion {
    
    NSLog(@"[WeaponX] Making %@ request to %@ (retry %ld/%ld)", method, url, (long)retryCount, (long)maxRetries);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    
    if (body) {
        request.HTTPBody = body;
    }
    
    if (headers) {
        for (NSString *key in headers) {
            [request setValue:headers[key] forHTTPHeaderField:key];
        }
    }
    
    // Set timeout to be more forgiving on slower networks
    request.timeoutInterval = 30.0;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSInteger statusCode = httpResponse ? httpResponse.statusCode : 0;
        
        // Log response information
        NSLog(@"[WeaponX] Response status: %ld for %@", (long)statusCode, url);
        
        // Handle network errors
        if (error) {
            NSLog(@"[WeaponX] Network error: %@", error);
            
            // Retry for network errors if we haven't reached the max
            if (retryCount < maxRetries) {
                NSLog(@"[WeaponX] Retrying request after network error (%ld/%ld)", (long)(retryCount+1), (long)maxRetries);
                
                // Increasing backoff delay
                NSTimeInterval delay = pow(2.0, retryCount) * 0.5;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self performAPIRequestWithURL:url 
                                           method:method 
                                             body:body 
                                          headers:headers 
                                       retryCount:(retryCount + 1) 
                                       maxRetries:maxRetries 
                                       completion:completion];
                });
                return;
            }
        }
        
        // Handle auth errors (401)
        if (statusCode == 401) {
            NSLog(@"[WeaponX] Auth error (401) received");
            
            // Check if we have token in Authorization header
            NSString *authHeader = headers[@"Authorization"];
            if ([authHeader hasPrefix:@"Bearer "] && retryCount < maxRetries) {
                NSString *token = [authHeader substringFromIndex:7]; // Skip "Bearer "
                NSString *userId = [[TokenManager sharedInstance] getServerUserId];
                
                // Log the token information for debugging
                NSLog(@"[WeaponX] Auth error with token starting with: %@...", token.length > 5 ? [token substringToIndex:5] : token);
                
                // Try to reset token if we have a user ID
                if (userId) {
                    NSLog(@"[WeaponX] Resetting token for user ID: %@", userId);
                    
                    [[TokenManager sharedInstance] resetTokenForUserId:userId completion:^(NSString *newToken, NSError *tokenError) {
                        if (tokenError || !newToken) {
                            NSLog(@"[WeaponX] Failed to reset token: %@", tokenError);
                            // Complete with the original result
                            completion(data, response, error);
                            return;
                        }
                        
                        NSLog(@"[WeaponX] Token reset successful, retrying with new token");
                        
                        // Create new headers with the updated token
                        NSMutableDictionary *newHeaders = [NSMutableDictionary dictionaryWithDictionary:headers];
                        [newHeaders setObject:[NSString stringWithFormat:@"Bearer %@", newToken] forKey:@"Authorization"];
                        
                        // Retry after a delay
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self performAPIRequestWithURL:url 
                                                   method:method 
                                                     body:body 
                                                  headers:newHeaders 
                                               retryCount:(retryCount + 1) 
                                               maxRetries:maxRetries 
                                               completion:completion];
                        });
                    }];
                    return;
                }
            }
        }
        
        // For server errors (5xx), retry with backoff
        if (statusCode >= 500 && retryCount < maxRetries) {
            NSLog(@"[WeaponX] Server error (%ld), retrying (%ld/%ld)", (long)statusCode, (long)(retryCount+1), (long)maxRetries);
            
            // Increasing backoff delay
            NSTimeInterval delay = pow(2.0, retryCount) * 0.5;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self performAPIRequestWithURL:url 
                                       method:method 
                                         body:body 
                                      headers:headers 
                                   retryCount:(retryCount + 1) 
                                   maxRetries:maxRetries 
                                   completion:completion];
            });
            return;
        }
        
        // Complete with the final result
        completion(data, response, error);
    }];
    
    [task resume];
}

// Helper method to show alerts with hacker style
- (void)showHackerAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    // Check if this is a 403 status code error (banned user)
    if ([message containsString:@"403"]) {
        // Create a modified message with BANNED text
        NSString *enhancedMessage = [NSString stringWithFormat:@"%@\n\nBANNED", message];
        alert.message = enhancedMessage;
        
        // Create Telegram support button with icon
        NSString *telegramTitle = @"CONTACT SUPPORT 📱";
        UIAlertAction *telegramAction = [UIAlertAction actionWithTitle:telegramTitle 
                                                               style:UIAlertActionStyleDefault 
                                                             handler:^(UIAlertAction * _Nonnull action) {
            NSURL *telegramURL = [NSURL URLWithString:@"https://t.me/Hydraosmo"];
            [[UIApplication sharedApplication] openURL:telegramURL options:@{} completionHandler:nil];
        }];
        
        [alert addAction:telegramAction];
        return [self presentViewController:alert animated:YES completion:nil];
    }
    
    // Default ACKNOWLEDGE button for non-banned cases
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"ACKNOWLEDGE" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// New method to animate hacking-style terminal text
- (void)animateHackingTextInLabel:(UILabel *)label completion:(void (^)(void))completion {
    NSArray *hackingLines = @[
        @"> ESTABLISHING SECURE CONNECTION",
        @"> VALIDATING CREDENTIALS",
        @"> DECRYPTING ACCESS TOKENS",
        @"> RETRIEVING USER DATA",
        @"> INITIALIZING ENCRYPTION PROTOCOLS",
        @"> AUTHENTICATING USER SESSION",
        @"> ACCESS GRANTED"
    ];
    
    // Increase the delay between lines for better visibility
    NSTimeInterval delayBetweenLines = 0.6;
    NSTimeInterval charDelay = 0.03;
    
    __block NSMutableString *currentText = [NSMutableString string];
    __block NSUInteger currentLineIndex = 0;
    
    // Use weak reference to self to avoid retain cycles
    __weak typeof(self) weakSelf = self;
    
    // Define the animateLine block with weak-strong dance to avoid retain cycles
    __block __weak void (^weakAnimateLine)(void);
    __block void (^animateLine)(void) = ^{
        // Create strong reference to weak self
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (currentLineIndex >= hackingLines.count) {
            // All lines animated, call completion after a longer delay
            // Keep the animation visible for at least 1.5 seconds after completion
            NSLog(@"[WeaponX] All animation lines completed, waiting 1.5 seconds before dismissing");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (completion) {
                    completion();
                }
            });
            return;
        }
        
        NSLog(@"[WeaponX] Animating line %lu: %@", (unsigned long)currentLineIndex, hackingLines[currentLineIndex]);
        NSString *line = hackingLines[currentLineIndex];
        [strongSelf animateTypingText:line inLabel:label currentText:currentText charDelay:charDelay completion:^{
            [currentText appendString:@"\n"];
            label.text = currentText;
            currentLineIndex++;
            
            // Animate next line after delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayBetweenLines * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Use weak reference to the block
                if (weakAnimateLine) weakAnimateLine();
            });
        }];
    };
    weakAnimateLine = animateLine;
    
    // Start animating the first line
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[WeaponX] Starting terminal text animation");
        animateLine();
    });
}

// Helper method to animate typing effect
- (void)animateTypingText:(NSString *)text inLabel:(UILabel *)label currentText:(NSMutableString *)currentText charDelay:(NSTimeInterval)charDelay completion:(void (^)(void))completion {
    __block NSUInteger charIndex = 0;
    
    // Recursive block to type character by character with weak self reference
    __weak typeof(self) weakSelf = self;
    __block __weak void (^weakTypeNextChar)(void);
    __block void (^typeNextChar)(void);
    
    typeNextChar = ^{
        // Create strong reference to weak self to ensure we exist during this block execution
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (charIndex >= text.length) {
            // All characters typed
            if (completion) {
                completion();
            }
            return;
        }
        
        // Add next character
        unichar character = [text characterAtIndex:charIndex];
        [currentText appendString:[NSString stringWithCharacters:&character length:1]];
        label.text = currentText;
        charIndex++;
        
        // Randomize delay slightly for realistic typing
        NSTimeInterval randomDelay = charDelay * (0.8 + (0.4 * (float)arc4random() / UINT32_MAX));
        
        // Schedule next character - use weak reference to avoid retain cycle
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(randomDelay * NSEC_PER_SEC)), 
                       dispatch_get_main_queue(), ^{
                           if (weakTypeNextChar) weakTypeNextChar();
                       });
    };
    
    weakTypeNextChar = typeNextChar;
    
    // Start typing
    typeNextChar();
}

// Helper method to extract user ID from a token
- (NSString *)extractUserIdFromToken:(NSString *)token {
    if (!token || token.length == 0) {
        NSLog(@"[WeaponX] Cannot extract user ID from empty token");
        return nil;
    }
    
    NSArray *tokenParts = [token componentsSeparatedByString:@"|"];
    if (tokenParts.count > 0) {
        NSString *userIdFromToken = tokenParts[0];
        NSLog(@"[WeaponX] Extracted user ID from token: %@", userIdFromToken);
        return userIdFromToken;
    }
    
    NSLog(@"[WeaponX] Failed to extract user ID from token format");
    return nil;
}

// Helper method to get API base URL
- (NSString *)apiBaseUrl {
    // Always use production URL
    return @"https://hydra.weaponx.us";
}

// Add the missing method for trying to fetch plan with URLs
- (void)tryFetchPlanWithURLs:(NSArray *)urls atIndex:(NSUInteger)index token:(NSString *)token {
    if (index >= urls.count) {
        NSLog(@"[WeaponX] Failed to fetch user plan after trying all URLs");
        return;
    }
    
    NSString *urlString = urls[index];
    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[WeaponX] Trying to fetch plan from URL (%lu of %lu): %@", (unsigned long)(index + 1), (unsigned long)urls.count, url);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Add server user ID if available to help server properly identify the user
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *serverUserId = [defaults objectForKey:@"WeaponXServerUserId"];
    if (serverUserId) {
        [request setValue:serverUserId forHTTPHeaderField:@"X-User-Id"];
    }
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (error || httpResponse.statusCode != 200 || !data) {
            NSLog(@"[WeaponX] Error fetching plan from %@: %@, status: %ld", urlString, error, (long)httpResponse.statusCode);
            // Try next URL
            [self tryFetchPlanWithURLs:urls atIndex:index + 1 token:token];
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] Failed to parse plan response: %@", jsonError);
            // Try next URL
            [self tryFetchPlanWithURLs:urls atIndex:index + 1 token:token];
            return;
        }
        
        NSLog(@"[WeaponX] Successfully fetched user plan: %@", json);
        
        // Save plan data
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:json forKey:@"WeaponXUserPlan"];
            [defaults synchronize];
            
            // Post notification that plan data is available
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserPlanDidUpdate" object:nil];
        });
    }];
    
    [task resume];
}

// Helper method to complete login with a token
- (void)completeLoginWithToken:(NSString *)token userInfo:(NSDictionary *)userInfo {
    NSLog(@"[WeaponX] Completing login with token");
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Extract user ID from token for validation using TokenManager
    NSString *tokenUserId = [[TokenManager sharedInstance] extractUserIdFromToken:token];
    
    // Store user ID separately for validation
    NSString *userId = nil;
    if (userInfo[@"id"]) {
        userId = [NSString stringWithFormat:@"%@", userInfo[@"id"]];
        
        // Log warning if IDs don't match
        if (tokenUserId && ![tokenUserId isEqualToString:userId]) {
            NSLog(@"[WeaponX] WARNING: Token user ID (%@) doesn't match user info ID (%@)", 
                  tokenUserId, userId);
        } else {
            NSLog(@"[WeaponX] VERIFIED: Token user ID matches user info ID: %@", userId);
        }
    }
    
    // Use TokenManager to save the token
    [[TokenManager sharedInstance] saveToken:token withUserId:userId];
    
    // Still save the userInfo directly in NSUserDefaults
    [defaults setObject:userInfo forKey:@"WeaponXUserInfo"];
    
    // Store username and email directly for easier access
    if (userInfo[@"name"]) {
        [defaults setObject:userInfo[@"name"] forKey:@"Username"];
        NSLog(@"[WeaponX] Saved username: %@", userInfo[@"name"]);
    }
    if (userInfo[@"email"]) {
        [defaults setObject:userInfo[@"email"] forKey:@"UserEmail"];
        NSLog(@"[WeaponX] Saved user email: %@", userInfo[@"email"]);
        
        // Save the last successful login credentials
        // Note: Storing passwords in plain text is generally not recommended for security reasons
        // A more secure approach would be to use the iOS Keychain
        NSString *lastEmail = self.emailField.text;
        NSString *lastPassword = self.passwordField.text;
        
        if (lastEmail && lastPassword) {
            [defaults setObject:lastEmail forKey:@"LastLoginEmail"];
            [defaults setObject:lastPassword forKey:@"LastLoginPassword"];
            NSLog(@"[WeaponX] Saved last successful login credentials for quick login");
        }
    }
    
    // Save current timestamp as login time
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    [defaults setObject:@(currentTime) forKey:@"LastLoginTimestamp"];
    
    // Save a flag indicating this is a first-time login if it's registration
    if ([defaults objectForKey:@"IsRegistrationLogin"]) {
        NSLog(@"[WeaponX] This login is from a registration flow");
        [defaults removeObjectForKey:@"IsRegistrationLogin"];
    }
    
    [defaults synchronize];
    NSLog(@"[WeaponX] Authentication data saved and synchronized");
    
    // Fetch user plan data
    if (token) {
        [self fetchUserPlanData:token];
    }
    
    // Post notification for successful login
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserDidLogin" object:nil];
    
    // Present Account tab after login
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
    if ([tabBarController isKindOfClass:NSClassFromString(@"TabBarController")]) {
        // Dismiss login, then switch to account tab
        [self dismissViewControllerAnimated:YES completion:^{
            [(TabBarController *)tabBarController switchToAccountTab];
            if (self.loginCompletionHandler) {
                self.loginCompletionHandler();
            }
        }];
    } else {
        // Fallback: just dismiss
        [self dismissViewControllerAnimated:YES completion:^{
            if (self.loginCompletionHandler) {
                self.loginCompletionHandler();
            }
        }];
    }
}

// Helper method to get device unique identifiers
- (NSDictionary *)getDeviceIdentifiers {
    NSMutableDictionary *identifiers = [NSMutableDictionary dictionary];
    
    // Get device UUID (identifierForVendor)
    NSUUID *uuid = [[UIDevice currentDevice] identifierForVendor];
    if (uuid) {
        identifiers[@"device_uuid"] = [uuid UUIDString];
    }
    
    // Get device serial number from iOKit (for jailbroken devices)
    NSString *serialNumber = nil;
    
    // Use IOKit to get serial number if possible (requires jailbroken device)
    // This method will work on jailbroken iOS 15-16 with Dopamine rootless jailbreak
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
    if (platformExpert) {
        CFTypeRef serialNumberRef = IORegistryEntryCreateCFProperty(platformExpert, CFSTR("IOPlatformSerialNumber"), kCFAllocatorDefault, 0);
        if (serialNumberRef) {
            serialNumber = (__bridge_transfer NSString *)serialNumberRef;
            IOObjectRelease(platformExpert);
        }
    }
    
    if (serialNumber) {
        identifiers[@"device_serial"] = serialNumber;
    }
    
    return identifiers;
}

// Method to get detailed device model
- (NSString *)getDetailedDeviceModel {
    // First try to get the machine model from system info
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *modelIdentifier = [NSString stringWithCString:systemInfo.machine 
                                                  encoding:NSUTF8StringEncoding];
    
    // Map the identifier to a human-readable device model
    NSDictionary *deviceNamesByCode = @{
        // iPhones
        @"iPhone1,1": @"iPhone",
        @"iPhone1,2": @"iPhone 3G",
        @"iPhone2,1": @"iPhone 3GS",
        @"iPhone3,1": @"iPhone 4",
        @"iPhone3,2": @"iPhone 4",
        @"iPhone3,3": @"iPhone 4",
        @"iPhone4,1": @"iPhone 4S",
        @"iPhone5,1": @"iPhone 5",
        @"iPhone5,2": @"iPhone 5",
        @"iPhone5,3": @"iPhone 5C",
        @"iPhone5,4": @"iPhone 5C",
        @"iPhone6,1": @"iPhone 5S",
        @"iPhone6,2": @"iPhone 5S",
        @"iPhone7,1": @"iPhone 6 Plus",
        @"iPhone7,2": @"iPhone 6",
        @"iPhone8,1": @"iPhone 6S",
        @"iPhone8,2": @"iPhone 6S Plus",
        @"iPhone8,4": @"iPhone SE",
        @"iPhone9,1": @"iPhone 7",
        @"iPhone9,2": @"iPhone 7 Plus",
        @"iPhone9,3": @"iPhone 7",
        @"iPhone9,4": @"iPhone 7 Plus",
        @"iPhone10,1": @"iPhone 8",
        @"iPhone10,2": @"iPhone 8 Plus",
        @"iPhone10,3": @"iPhone X",
        @"iPhone10,4": @"iPhone 8",
        @"iPhone10,5": @"iPhone 8 Plus",
        @"iPhone10,6": @"iPhone X",
        @"iPhone11,2": @"iPhone XS",
        @"iPhone11,4": @"iPhone XS Max",
        @"iPhone11,6": @"iPhone XS Max",
        @"iPhone11,8": @"iPhone XR",
        @"iPhone12,1": @"iPhone 11",
        @"iPhone12,3": @"iPhone 11 Pro",
        @"iPhone12,5": @"iPhone 11 Pro Max",
        @"iPhone13,1": @"iPhone 12 Mini",
        @"iPhone13,2": @"iPhone 12",
        @"iPhone13,3": @"iPhone 12 Pro",
        @"iPhone13,4": @"iPhone 12 Pro Max",
        @"iPhone14,2": @"iPhone 13 Pro",
        @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,4": @"iPhone 13 Mini",
        @"iPhone14,5": @"iPhone 13",
        @"iPhone14,6": @"iPhone SE (3rd generation)",
        @"iPhone14,7": @"iPhone 14",
        @"iPhone14,8": @"iPhone 14 Plus",
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        @"iPhone16,1": @"iPhone 15 Pro",
        @"iPhone16,2": @"iPhone 15 Pro Max",
        
        // iPads
        @"iPad1,1": @"iPad",
        @"iPad2,1": @"iPad 2",
        @"iPad2,2": @"iPad 2",
        @"iPad2,3": @"iPad 2",
        @"iPad2,4": @"iPad 2",
        @"iPad2,5": @"iPad Mini",
        @"iPad2,6": @"iPad Mini",
        @"iPad2,7": @"iPad Mini",
        @"iPad3,1": @"iPad 3",
        @"iPad3,2": @"iPad 3",
        @"iPad3,3": @"iPad 3",
        @"iPad3,4": @"iPad 4",
        @"iPad3,5": @"iPad 4",
        @"iPad3,6": @"iPad 4",
        @"iPad4,1": @"iPad Air",
        @"iPad4,2": @"iPad Air",
        @"iPad4,3": @"iPad Air",
        @"iPad4,4": @"iPad Mini 2",
        @"iPad4,5": @"iPad Mini 2",
        @"iPad4,6": @"iPad Mini 2",
        @"iPad4,7": @"iPad Mini 3",
        @"iPad4,8": @"iPad Mini 3",
        @"iPad4,9": @"iPad Mini 3",
        @"iPad5,1": @"iPad Mini 4",
        @"iPad5,2": @"iPad Mini 4",
        @"iPad5,3": @"iPad Air 2",
        @"iPad5,4": @"iPad Air 2",
        @"iPad6,3": @"iPad Pro (9.7-inch)",
        @"iPad6,4": @"iPad Pro (9.7-inch)",
        @"iPad6,7": @"iPad Pro (12.9-inch)",
        @"iPad6,8": @"iPad Pro (12.9-inch)",
        @"iPad6,11": @"iPad (5th generation)",
        @"iPad6,12": @"iPad (5th generation)",
        @"iPad7,1": @"iPad Pro (12.9-inch) (2nd generation)",
        @"iPad7,2": @"iPad Pro (12.9-inch) (2nd generation)",
        @"iPad7,3": @"iPad Pro (10.5-inch)",
        @"iPad7,4": @"iPad Pro (10.5-inch)",
        @"iPad7,5": @"iPad (6th generation)",
        @"iPad7,6": @"iPad (6th generation)",
        @"iPad7,11": @"iPad (7th generation)",
        @"iPad7,12": @"iPad (7th generation)",
        @"iPad8,1": @"iPad Pro (11-inch)",
        @"iPad8,2": @"iPad Pro (11-inch)",
        @"iPad8,3": @"iPad Pro (11-inch)",
        @"iPad8,4": @"iPad Pro (11-inch)",
        @"iPad8,5": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,6": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,7": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,8": @"iPad Pro (12.9-inch) (3rd generation)",
        @"iPad8,9": @"iPad Pro (11-inch) (2nd generation)",
        @"iPad8,10": @"iPad Pro (11-inch) (2nd generation)",
        @"iPad8,11": @"iPad Pro (12.9-inch) (4th generation)",
        @"iPad8,12": @"iPad Pro (12.9-inch) (4th generation)",
        
        // iPod Touch
        @"iPod1,1": @"iPod Touch",
        @"iPod2,1": @"iPod Touch (2nd generation)",
        @"iPod3,1": @"iPod Touch (3rd generation)",
        @"iPod4,1": @"iPod Touch (4th generation)",
        @"iPod5,1": @"iPod Touch (5th generation)",
        @"iPod7,1": @"iPod Touch (6th generation)",
        @"iPod9,1": @"iPod Touch (7th generation)",
        
        // Simulator
        @"i386": @"Simulator",
        @"x86_64": @"Simulator",
        @"arm64": @"Simulator"
    };
    
    NSString *deviceName = deviceNamesByCode[modelIdentifier];
    
    if (!deviceName) {
        if ([modelIdentifier rangeOfString:@"iPhone"].location != NSNotFound) {
            deviceName = @"iPhone";
        } else if ([modelIdentifier rangeOfString:@"iPad"].location != NSNotFound) {
            deviceName = @"iPad";
        } else if ([modelIdentifier rangeOfString:@"iPod"].location != NSNotFound) {
            deviceName = @"iPod Touch";
        } else {
            deviceName = @"iOS Device";
        }
    }
    
    NSLog(@"[WeaponX] Device model identifier: %@, mapped to: %@", modelIdentifier, deviceName);
    return deviceName;
}

// Add hacker-style glitch animation for button
- (void)addGlitchAnimation:(UIButton *)button {
    // Save original state
    UIColor *originalBackgroundColor = button.backgroundColor;
    UIColor *originalTitleColor = [button titleColorForState:UIControlStateNormal];
    NSString *originalTitle = [button titleForState:UIControlStateNormal];
    
    // First glitch the button immediately
    button.backgroundColor = [UIColor colorWithRed:0.1 green:0.9 blue:0.3 alpha:0.7];
    [button setTitle:@"4CC3551NG_5Y5T3M" forState:UIControlStateNormal];

    // Get the key window to display animation on top of everything
    UIWindow *mainWindow = nil;
    if (@available(iOS 13.0, *)) {
        // Get the first connected scene's window for iOS 13+
        NSArray<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes.allObjects;
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && 
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        mainWindow = window;
                        break;
                    }
                }
                if (!mainWindow) {
                    mainWindow = windowScene.windows.firstObject;
                }
                break;
            }
        }
    } else {
        // For iOS 12 and below, use the deprecated API
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        mainWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    
    if (!mainWindow) {
        NSLog(@"[WeaponX] ERROR: Could not find main window for animation");
        // Fallback - use our current view since we couldn't find a window
        mainWindow = self.view.window;
        if (!mainWindow) {
            NSLog(@"[WeaponX] ERROR: Could not find any window for animation");
            return;
        }
    }
    
    NSLog(@"[WeaponX] Found main window with frame: %@", NSStringFromCGRect(mainWindow.bounds));
    
    // Create a fullscreen overlay view with a "noise" pattern
    UIView *hackingOverlay = [[UIView alloc] initWithFrame:mainWindow.bounds];
    hackingOverlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.92];
    hackingOverlay.alpha = 0;
    
    // Add a subtle noise pattern as background
    UIView *noiseView = [[UIView alloc] initWithFrame:hackingOverlay.bounds];
    noiseView.alpha = 0.05;
    noiseView.backgroundColor = [UIColor colorWithPatternImage:[self generateNoiseImage]];
    [hackingOverlay addSubview:noiseView];
    
    // Make sure overlay stays on top
    hackingOverlay.layer.zPosition = 9999;
    
    // Create the terminal text view with styled border
    UIView *terminalView = [[UIView alloc] initWithFrame:CGRectMake(20, 100, mainWindow.bounds.size.width - 40, mainWindow.bounds.size.height - 200)];
    terminalView.backgroundColor = [UIColor colorWithRed:0.02 green:0.05 blue:0.05 alpha:1.0];
    terminalView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
    terminalView.layer.borderWidth = 2.0;
    terminalView.layer.cornerRadius = 5.0;
    
    // Add subtle inner shadow to terminal
    CALayer *innerShadow = [CALayer layer];
    innerShadow.frame = terminalView.bounds;
    innerShadow.backgroundColor = [UIColor clearColor].CGColor;
    innerShadow.shadowColor = [UIColor colorWithRed:0 green:1 blue:0.4 alpha:0.5].CGColor;
    innerShadow.shadowOffset = CGSizeZero;
    innerShadow.shadowRadius = 6;
    innerShadow.shadowOpacity = 1.0;
    innerShadow.masksToBounds = YES;
    [terminalView.layer addSublayer:innerShadow];
    
    // Add a terminal header
    UIView *terminalHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, terminalView.bounds.size.width, 30)];
    terminalHeader.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.3 alpha:1.0];
    
    UILabel *terminalTitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, terminalHeader.bounds.size.width - 20, 30)];
    terminalTitle.text = @"WEAPON-X SECURE ACCESS TERMINAL v3.4.2";
    terminalTitle.font = [UIFont fontWithName:@"Menlo-Bold" size:12] ?: [UIFont boldSystemFontOfSize:12];
    terminalTitle.textColor = [UIColor blackColor];
    
    // Add blinking activity indicator to header
    UIView *activityDot = [[UIView alloc] initWithFrame:CGRectMake(terminalHeader.bounds.size.width - 20, 15, 8, 8)];
    activityDot.backgroundColor = [UIColor redColor];
    activityDot.layer.cornerRadius = 4.0;
    activityDot.tag = 1001; // For reference in animation
    
    [terminalHeader addSubview:terminalTitle];
    [terminalHeader addSubview:activityDot];
    [terminalView addSubview:terminalHeader];
    
    // Create the terminal output label
    UILabel *terminalLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, terminalView.bounds.size.width - 20, terminalView.bounds.size.height - 50)];
    terminalLabel.font = [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    terminalLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    terminalLabel.numberOfLines = 0;
    // Initialize with terminal header
    NSString *initText = @"WEAPON-X SECURITY GATEWAY [Version 3.4.2]\n";
    initText = [initText stringByAppendingString:@"© 2025 Weapon-X Security. All rights reserved.\n\n"];
    initText = [initText stringByAppendingString:@"INITIALIZING SECURE ACCESS PROTOCOL...\n"];
    terminalLabel.text = initText;
    
    // Add a scroll view so we can show more text
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 40, terminalView.bounds.size.width - 20, terminalView.bounds.size.height - 50)];
    scrollView.backgroundColor = [UIColor clearColor];
    scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [terminalView addSubview:scrollView];
    [scrollView addSubview:terminalLabel];
    
    [hackingOverlay addSubview:terminalView];
    [mainWindow addSubview:hackingOverlay];
    
    NSLog(@"[WeaponX] Added hacking animation overlay to main window (LoginViewController)");
    
    // Start the activity dot blinking
    [self animateActivityDot:activityDot];
    
    // Create a mutable string for the animation
    NSMutableString *animatedText = [NSMutableString stringWithString:initText];
    
    // Generate unique identifiers for this session
    NSString *sessionId = [NSString stringWithFormat:@"SES%08X", arc4random_uniform(0xFFFFFFFF)];
    NSString *securityKey = [self generateRandomHexString:32];
    NSString *ipAddress = [self generateRandomIPAddress];
    NSString *serverNode = [NSString stringWithFormat:@"node%d.wx-sec.net", arc4random_uniform(12) + 1];
    NSString *uid = [NSString stringWithFormat:@"uid%d", arc4random_uniform(10000)];
    NSString *gid = [NSString stringWithFormat:@"gid%d", arc4random_uniform(100)];
    NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *kernel = [NSString stringWithFormat:@"WX-Kernel-%d.%d.%d", 
                  arc4random_uniform(5) + 4, 
                  arc4random_uniform(20), 
                  arc4random_uniform(90)];
    
    // Advanced terminal command sequence for login
    NSArray *hackingSequence = @[
        @{@"command": [NSString stringWithFormat:@"ssh admin@%@", serverNode], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"Establishing secure connection to gateway server..."], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"RSA key fingerprint is %@", [self generateRandomHexString:16]], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Connection established."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"uname -a"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"%@ %@ %@ #1 SMP %@ %@ x86_64", kernel, serverNode, timestamp, uid, gid], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"./authenticate --secure --method=credential_validation"], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"Validating credentials..."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Generating session key: %@", securityKey], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"Session ID: %@", sessionId], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Client IP: %@", ipAddress], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"cat /proc/meminfo | grep Mem"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"MemTotal:       16384000 kB"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"MemFree:         4196428 kB"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"MemAvailable:   10485760 kB"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"./verify_security_level --user=CURRENT --required=2"], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"Checking user privileges..."], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"User has required access level."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"./initiate_secure_tunnel --dest=CORE"], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"TLS handshake initiated with gateway.core.systems"], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Cipher Suite: TLS_AES_256_GCM_SHA384"], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Secure channel established"], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"sudo netstat -tulpn | grep LISTEN"], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"tcp   0   0 0.0.0.0:22     0.0.0.0:*     LISTEN  997/sshd"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"tcp   0   0 127.0.0.1:631  0.0.0.0:*     LISTEN  1032/cupsd"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"tcp6  0   0 ::1:631        :::*          LISTEN  1032/cupsd"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"AUTHENTICATION SUCCESSFUL"], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"ACCESS GRANTED - Welcome back, Agent"], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Loading secure environment..."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"sudo systemctl status weapon-x.service"], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"● weapon-x.service - Weapon X Security Core"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"   Loaded: loaded (/etc/systemd/system/weapon-x.service)"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"   Active: active (running) since %@", timestamp], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"   Memory: 245.2M"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"   CGroup: /system.slice/weapon-x.service"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"exit"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"Connection to %@ closed.", serverNode], @"delay": @0.5},
    ];
    
    // Fade in the overlay immediately
    [UIView animateWithDuration:0.2 animations:^{
        hackingOverlay.alpha = 1.0;
    } completion:^(BOOL finished) {
        NSLog(@"[WeaponX] Hacking overlay visible in LoginViewController, starting animation");
        
        // Add a safety timeout to ensure the animation doesn't get stuck
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)), 
                      dispatch_get_main_queue(), ^{
            // If animation is still visible after timeout, force dismiss it
            if (hackingOverlay.superview != nil) {
                NSLog(@"[WeaponX] Safety timeout triggered - animation may have stalled");
                [UIView animateWithDuration:0.3 animations:^{
                    hackingOverlay.alpha = 0;
                } completion:^(BOOL finished) {
                    [hackingOverlay removeFromSuperview];
                    
                    // Restore button after animation completes
                    button.backgroundColor = originalBackgroundColor;
                    [button setTitle:originalTitle forState:UIControlStateNormal];
                    [button setTitleColor:originalTitleColor forState:UIControlStateNormal];
                }];
            }
        });
        
        // Animate the terminal text with advanced command sequences
        [self animateAdvancedTerminalWithSequence:hackingSequence
                                         inLabel:terminalLabel
                                      scrollView:scrollView
                                     currentText:animatedText
                                    currentIndex:0
                                      completion:^{
            NSLog(@"[WeaponX] Animation completed in LoginViewController, waiting before dismissal");
            
            // Wait before dismissing
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), 
                          dispatch_get_main_queue(), ^{
                // Fade out animation
                [UIView animateWithDuration:0.3 animations:^{
                    hackingOverlay.alpha = 0;
                } completion:^(BOOL finished) {
                    [hackingOverlay removeFromSuperview];
                    
                    // Restore button after animation completes
                    button.backgroundColor = originalBackgroundColor;
                    [button setTitle:originalTitle forState:UIControlStateNormal];
                    [button setTitleColor:originalTitleColor forState:UIControlStateNormal];
                }];
            });
        }];
    }];
}

// Generate noise image for the background texture
- (UIImage *)generateNoiseImage {
    CGSize size = CGSizeMake(200, 200);
    UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Fill with black
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
    
    // Add random noise pixels
    for (int y = 0; y < size.height; y++) {
        for (int x = 0; x < size.width; x++) {
            float alpha = (arc4random_uniform(100) < 20) ? 0.15 : 0.0;
            CGContextSetRGBFillColor(context, 0.0, 1.0, 0.4, alpha);
            CGContextFillRect(context, CGRectMake(x, y, 1, 1));
        }
    }
    
    UIImage *noiseImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return noiseImage;
}

// Animate the activity indicator dot
- (void)animateActivityDot:(UIView *)dot {
    [UIView animateWithDuration:0.6
                     animations:^{
                         dot.alpha = 0.3;
                     }
                     completion:^(BOOL finished) {
                         [UIView animateWithDuration:0.6
                                          animations:^{
                                              dot.alpha = 1.0;
                                          }
                                          completion:^(BOOL finished) {
                                              [self animateActivityDot:dot];
                                          }];
                     }];
}

// Generate a random IP address string
- (NSString *)generateRandomIPAddress {
    NSInteger octet1 = 10 + arc4random_uniform(240);
    NSInteger octet2 = arc4random_uniform(255);
    NSInteger octet3 = arc4random_uniform(255);
    NSInteger octet4 = 1 + arc4random_uniform(254);
    return [NSString stringWithFormat:@"%ld.%ld.%ld.%ld", (long)octet1, (long)octet2, (long)octet3, (long)octet4];
}

// Generate a random hex string of specified length
- (NSString *)generateRandomHexString:(NSInteger)length {
    NSString *characters = @"0123456789ABCDEF";
    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    
    for (NSInteger i = 0; i < length; i++) {
        NSUInteger randomIndex = arc4random_uniform((uint32_t)[characters length]);
        unichar character = [characters characterAtIndex:randomIndex];
        [result appendFormat:@"%C", character];
    }
    
    return result;
}

// Helper to type out commands character by character
- (void)animateTypingCommand:(NSString *)command 
                     inLabel:(UILabel *)label 
                 currentText:(NSMutableString *)currentText
                  completion:(void (^)(void))completion {
    
    // For reliability, use a simple timer approach rather than recursion
    __block NSUInteger charIndex = 0;
    __block NSTimer *typingTimer = nil;
    
    // Create a timer callback function - 50% faster (0.025 instead of 0.05)
    typingTimer = [NSTimer scheduledTimerWithTimeInterval:0.025 repeats:YES block:^(NSTimer *timer) {
        // Check if we've reached the end of the command
        if (charIndex >= command.length) {
            [typingTimer invalidate];
            typingTimer = nil;
            // Remove this NSLog statement
            // NSLog(@"[WeaponX] Finished typing command: %@", command);
            if (completion) {
                completion();
            }
            return;
        }
        
        // Add the next character to the text
        unichar character = [command characterAtIndex:charIndex];
        NSString *charString = [NSString stringWithCharacters:&character length:1];
        [currentText appendString:charString];
        label.text = currentText;
        charIndex++;
        
        // NSLog(@"[WeaponX] Typing character %@ at index %lu of command", charString, (unsigned long)charIndex);
    }];
    
    // Make sure the timer is added to the current run loop
    [[NSRunLoop currentRunLoop] addTimer:typingTimer forMode:NSRunLoopCommonModes];
}

// Advanced method for animating terminal with more realistic command sequence
- (void)animateAdvancedTerminalWithSequence:(NSArray *)sequence
                                    inLabel:(UILabel *)label
                                 scrollView:(UIScrollView *)scrollView
                                currentText:(NSMutableString *)currentText
                               currentIndex:(NSUInteger)index
                                 completion:(void (^)(void))completion {
    
    // All lines done
    if (index >= sequence.count) {
        NSLog(@"[WeaponX] Advanced terminal sequence completed in LoginViewController");
        if (completion) {
            completion();
        }
        return;
    }
    
    NSDictionary *commandInfo = sequence[index];
    NSString *commandText = commandInfo[@"command"];
    // Use half the delay time to speed up by 50%
    NSTimeInterval delay = [commandInfo[@"delay"] doubleValue] * 0.5;
    
    // Determine if this is a command (starts with non-whitespace) or output
    BOOL isCommand = commandText.length > 0 && ![commandText hasPrefix:@" "];
    
    // For commands, show a command prompt
    if (isCommand && commandText.length > 0) {
        [currentText appendString:@"\nwx$ "];
    } else if (commandText.length > 0) {
        [currentText appendString:@"\n"];
    }
    
    // For commands, animate typing
    if (isCommand && commandText.length > 0) {
        [self animateTypingCommand:commandText inLabel:label currentText:currentText completion:^{
            // Update scroll view
            [self updateScrollView:scrollView forLabel:label];
            
            // Move to next command after delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), 
                          dispatch_get_main_queue(), ^{
                // Continue with next command
                [self animateAdvancedTerminalWithSequence:sequence 
                                                 inLabel:label 
                                              scrollView:scrollView
                                              currentText:currentText 
                                              currentIndex:index + 1
                                                completion:completion];
            });
        }];
    } else {
        // For output lines, show immediately with newline
        if (commandText.length > 0) {
            [currentText appendString:commandText];
        }
        label.text = currentText;
        
        // Update scroll view
        [self updateScrollView:scrollView forLabel:label];
        
        // Move to next step
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), 
                       dispatch_get_main_queue(), ^{
            // Continue with next line
            [self animateAdvancedTerminalWithSequence:sequence 
                                             inLabel:label 
                                          scrollView:scrollView
                                          currentText:currentText 
                                          currentIndex:index + 1
                                            completion:completion];
        });
    }
}

// Helper to update scroll view to always show the latest text
- (void)updateScrollView:(UIScrollView *)scrollView forLabel:(UILabel *)label {
    CGSize labelSize = [label sizeThatFits:CGSizeMake(label.bounds.size.width, CGFLOAT_MAX)];
    label.frame = CGRectMake(0, 0, scrollView.bounds.size.width, labelSize.height);
    scrollView.contentSize = labelSize;
    
    // Scroll to bottom
    CGPoint bottomOffset = CGPointMake(0, MAX(0, labelSize.height - scrollView.bounds.size.height));
    [scrollView setContentOffset:bottomOffset animated:YES];
}

// Helper method to ensure animations are complete before showing alerts
- (void)completeOrHideHackingAnimation {
    // Check if we have a hacking animation running
    UIView *hackingOverlay = [self.view viewWithTag:9999]; // Assuming hacking overlay has a tag
    if (hackingOverlay) {
        // If animation is running, complete it or hide it
        [UIView animateWithDuration:0.3 animations:^{
            hackingOverlay.alpha = 0;
        } completion:^(BOOL finished) {
            [hackingOverlay removeFromSuperview];
        }];
    }
    
    // Stop any activity indicators
    [self.activityIndicator stopAnimating];
    
    // Make sure login button is enabled and visible
    [UIView animateWithDuration:0.3 animations:^{
        self.loginButton.alpha = 1.0;
        self.loginButton.enabled = YES;
    }];
}

- (void)openTelegram {
    NSURL *telegramURL = [NSURL URLWithString:@"https://t.me/hydraosomo"];
    if ([[UIApplication sharedApplication] canOpenURL:telegramURL]) {
        [[UIApplication sharedApplication] openURL:telegramURL options:@{} completionHandler:nil];
    }
}

- (void)openWebsite {
    NSURL *websiteURL = [NSURL URLWithString:@"https://hydra.weaponx.us/"];
    if ([[UIApplication sharedApplication] canOpenURL:websiteURL]) {
        [[UIApplication sharedApplication] openURL:websiteURL options:@{} completionHandler:nil];
    }
}

@end