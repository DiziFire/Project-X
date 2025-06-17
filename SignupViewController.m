#import "SignupViewController.h"
#import "TokenManager.h"
#import "LoginViewController.h"
#import <UIKit/UIKit.h>
#import <IOKit/IOKitLib.h>
#import <sys/utsname.h>

@interface SignupViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *logoImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *confirmPasswordField;
@property (nonatomic, strong) UIButton *passwordVisibilityButton;
@property (nonatomic, strong) UIButton *confirmPasswordVisibilityButton;
@property (nonatomic, strong) UIButton *signupButton;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIView *nameContainer;
@property (nonatomic, strong) UIView *emailContainer;
@property (nonatomic, strong) UIView *passwordContainer;
@property (nonatomic, strong) UIView *confirmPasswordContainer;
@property (nonatomic, strong) UILabel *passwordRequirementsLabel;
@end

@implementation SignupViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Create Account";
    
    // Set hacker theme
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor blackColor];
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    } else {
        self.view.backgroundColor = [UIColor blackColor];
    }
    
    [self setupUI];
    
    // Initialize password requirements display
    [self validatePassword:@""];
    
    // Add tap gesture to dismiss keyboard when tapping outside text fields
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tapGesture];
}

// Method to dismiss keyboard
- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - UITextFieldDelegate Methods

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameField) {
        [self.emailField becomeFirstResponder];
    } else if (textField == self.emailField) {
        [self.passwordField becomeFirstResponder];
    } else if (textField == self.passwordField) {
        [self.confirmPasswordField becomeFirstResponder];
    } else if (textField == self.confirmPasswordField) {
        [textField resignFirstResponder];
        [self signupButtonTapped];
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Only apply validation for the password field
    if (textField == self.passwordField) {
        // Get the updated text after the change
        NSString *updatedText = [textField.text stringByReplacingCharactersInRange:range withString:string];
        
        // Call password validation after a short delay to allow the text to update
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self validatePassword:updatedText];
        });
    }
    return YES;
}

#pragma mark - Password Validation

- (void)validatePassword:(NSString *)password {
    // Define regex patterns for validation
    NSString *lengthPattern = @".{8,}"; // At least 8 characters
    NSString *digitPattern = @".*\\d.*"; // At least one digit
    NSString *letterPattern = @".*[A-Za-z].*"; // At least one letter (upper or lower)
    NSString *specialCharPattern = @".*[!@#$%^&*(),.?\":{}|<>].*"; // At least one special character
    
    // Check each requirement
    BOOL hasMinLength = [self matchesPattern:lengthPattern forString:password];
    BOOL hasDigit = [self matchesPattern:digitPattern forString:password];
    BOOL hasLetter = [self matchesPattern:letterPattern forString:password];
    BOOL hasSpecialChar = [self matchesPattern:specialCharPattern forString:password];
    
    // Count requirements met
    NSInteger requirementsMet = hasMinLength + hasDigit + hasLetter + hasSpecialChar;
    
    // Compact display format with symbols
    NSString *checkmark = @"✓";
    NSString *xmark = @"✗";
    
    NSString *lengthStatus = hasMinLength ? checkmark : xmark;
    NSString *digitStatus = hasDigit ? checkmark : xmark;
    NSString *letterStatus = hasLetter ? checkmark : xmark;
    NSString *specialStatus = hasSpecialChar ? checkmark : xmark;
    
    // Create compact requirements text
    NSString *requirementsText = [NSString stringWithFormat:@"%@ 8+ chars • %@ 1+ number • %@ 1+ letter • %@ 1+ special", 
                                  lengthStatus, digitStatus, letterStatus, specialStatus];
    
    // Determine password strength color and prefix
    UIColor *strengthColor;
    NSString *strengthPrefix;
    if (requirementsMet <= 2) {
        strengthColor = [UIColor redColor];
        strengthPrefix = @"[WEAK] ";
    } else if (requirementsMet <= 3) {
        strengthColor = [UIColor orangeColor];
        strengthPrefix = @"[MODERATE] ";
    } else {
        strengthColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
        strengthPrefix = @"[STRONG] ";
    }
    
    // Update the requirements label
    self.passwordRequirementsLabel.text = [strengthPrefix stringByAppendingString:requirementsText];
    self.passwordRequirementsLabel.textColor = strengthColor;
    
    // Make label visible
    self.passwordRequirementsLabel.hidden = NO;
}

- (BOOL)matchesPattern:(NSString *)pattern forString:(NSString *)string {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", pattern];
    return [predicate evaluateWithObject:string];
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
        self.logoImageView.image = [UIImage systemImageNamed:@"person.badge.plus.fill"];
    } else {
        // Fallback for older iOS versions
        self.logoImageView.image = [UIImage imageNamed:@"AppIcon"];
    }
    [self.cardView addSubview:self.logoImageView];
    
    // Title Label with hacker theme
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @">> CREATE NEW IDENTITY";
    self.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:22.0] ?: [UIFont boldSystemFontOfSize:22.0];
    self.titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:self.titleLabel];
    
    // Subtitle Label with hacker theme
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = @"ENTER CREDENTIALS FOR NEW USER";
    subtitleLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    subtitleLabel.textColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1.0]; // Light gray
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cardView addSubview:subtitleLabel];
    
    // Name field container for styling with hacker theme
    self.nameContainer = [[UIView alloc] init];
    self.nameContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0]; // Slightly lighter dark
    self.nameContainer.layer.cornerRadius = 6.0; // More angular for hacker style
    self.nameContainer.layer.borderWidth = 1.0;
    self.nameContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4].CGColor; // Subtle neon border
    [self.cardView addSubview:self.nameContainer];
    
    // Name icon with hacker theme
    UIImageView *nameIcon = [[UIImageView alloc] init];
    nameIcon.translatesAutoresizingMaskIntoConstraints = NO;
    nameIcon.contentMode = UIViewContentModeScaleAspectFit;
    nameIcon.image = [UIImage systemImageNamed:@"person.fill"];
    nameIcon.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    [self.nameContainer addSubview:nameIcon];
    
    // Name Field with hacker theme
    self.nameField = [[UITextField alloc] init];
    self.nameField.placeholder = @"Agent Name";
    self.nameField.attributedPlaceholder = [[NSAttributedString alloc] 
                                          initWithString:@"Agent Name" 
                                          attributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0]}];
    self.nameField.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green text
    self.nameField.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.nameField.keyboardAppearance = UIKeyboardAppearanceDark; // Dark keyboard
    self.nameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.nameField.borderStyle = UITextBorderStyleNone;
    self.nameField.backgroundColor = [UIColor clearColor];
    self.nameField.returnKeyType = UIReturnKeyNext;
    self.nameField.delegate = self;
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nameContainer addSubview:self.nameField];
    
    // Email field container for styling with hacker theme
    self.emailContainer = [[UIView alloc] init];
    self.emailContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0]; // Slightly lighter dark
    self.emailContainer.layer.cornerRadius = 6.0; // More angular for hacker style
    self.emailContainer.layer.borderWidth = 1.0;
    self.emailContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4].CGColor; // Subtle neon border
    [self.cardView addSubview:self.emailContainer];
    
    // Email icon with hacker theme
    UIImageView *emailIcon = [[UIImageView alloc] init];
    emailIcon.translatesAutoresizingMaskIntoConstraints = NO;
    emailIcon.contentMode = UIViewContentModeScaleAspectFit;
    emailIcon.image = [UIImage systemImageNamed:@"envelope.fill"];
    emailIcon.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    [self.emailContainer addSubview:emailIcon];
    
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
    [self.emailContainer addSubview:self.emailField];
    
    // Password field container for styling with hacker theme
    self.passwordContainer = [[UIView alloc] init];
    self.passwordContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0]; // Slightly lighter dark
    self.passwordContainer.layer.cornerRadius = 6.0; // More angular for hacker style
    self.passwordContainer.layer.borderWidth = 1.0;
    self.passwordContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4].CGColor; // Subtle neon border
    [self.cardView addSubview:self.passwordContainer];
    
    // Password icon with hacker theme
    UIImageView *passwordIcon = [[UIImageView alloc] init];
    passwordIcon.translatesAutoresizingMaskIntoConstraints = NO;
    passwordIcon.contentMode = UIViewContentModeScaleAspectFit;
    passwordIcon.image = [UIImage systemImageNamed:@"lock.fill"];
    passwordIcon.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    [self.passwordContainer addSubview:passwordIcon];
    
    // Password field with hacker theme
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
    self.passwordField.returnKeyType = UIReturnKeyNext;
    self.passwordField.delegate = self;
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.passwordContainer addSubview:self.passwordField];
    
    // Confirm password field container for styling with hacker theme
    self.confirmPasswordContainer = [[UIView alloc] init];
    self.confirmPasswordContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.confirmPasswordContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0]; // Slightly lighter dark
    self.confirmPasswordContainer.layer.cornerRadius = 6.0; // More angular for hacker style
    self.confirmPasswordContainer.layer.borderWidth = 1.0;
    self.confirmPasswordContainer.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4].CGColor; // Subtle neon border
    [self.cardView addSubview:self.confirmPasswordContainer];
    
    // Confirm password icon with hacker theme
    UIImageView *confirmPasswordIcon = [[UIImageView alloc] init];
    confirmPasswordIcon.translatesAutoresizingMaskIntoConstraints = NO;
    confirmPasswordIcon.contentMode = UIViewContentModeScaleAspectFit;
    confirmPasswordIcon.image = [UIImage systemImageNamed:@"lock.shield.fill"];
    confirmPasswordIcon.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    [self.confirmPasswordContainer addSubview:confirmPasswordIcon];
    
    // Confirm password field with hacker theme
    self.confirmPasswordField = [[UITextField alloc] init];
    self.confirmPasswordField.placeholder = @"Confirm Passkey";
    self.confirmPasswordField.attributedPlaceholder = [[NSAttributedString alloc] 
                                                     initWithString:@"Confirm Passkey" 
                                                     attributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1.0]}];
    self.confirmPasswordField.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green text
    self.confirmPasswordField.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0];
    self.confirmPasswordField.secureTextEntry = YES;
    self.confirmPasswordField.keyboardAppearance = UIKeyboardAppearanceDark; // Dark keyboard
    self.confirmPasswordField.borderStyle = UITextBorderStyleNone;
    self.confirmPasswordField.backgroundColor = [UIColor clearColor];
    self.confirmPasswordField.returnKeyType = UIReturnKeyDone;
    self.confirmPasswordField.delegate = self;
    self.confirmPasswordField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.confirmPasswordContainer addSubview:self.confirmPasswordField];
    
    // Create eye button for password
    self.passwordVisibilityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.passwordVisibilityButton.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        [self.passwordVisibilityButton setImage:[UIImage systemImageNamed:@"eye.slash"] forState:UIControlStateNormal];
    } else {
        [self.passwordVisibilityButton setTitle:@"👁" forState:UIControlStateNormal];
    }
    self.passwordVisibilityButton.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8]; // Neon green
    self.passwordVisibilityButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.passwordVisibilityButton addTarget:self action:@selector(togglePasswordVisibility:) forControlEvents:UIControlEventTouchUpInside];
    // Add the visibility button INSIDE the password container
    [self.passwordContainer addSubview:self.passwordVisibilityButton];
    
    // Create eye button for confirm password
    self.confirmPasswordVisibilityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.confirmPasswordVisibilityButton.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        [self.confirmPasswordVisibilityButton setImage:[UIImage systemImageNamed:@"eye.slash"] forState:UIControlStateNormal];
    } else {
        [self.confirmPasswordVisibilityButton setTitle:@"👁" forState:UIControlStateNormal];
    }
    self.confirmPasswordVisibilityButton.tintColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    // Add the confirm visibility button INSIDE the confirm password container
    [self.confirmPasswordVisibilityButton addTarget:self action:@selector(toggleConfirmPasswordVisibility:) forControlEvents:UIControlEventTouchUpInside];
    [self.confirmPasswordContainer addSubview:self.confirmPasswordVisibilityButton];
    
    // Password Requirements Label with hacker theme
    self.passwordRequirementsLabel = [[UILabel alloc] init];
    self.passwordRequirementsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordRequirementsLabel.textAlignment = NSTextAlignmentLeft;
    self.passwordRequirementsLabel.font = [UIFont fontWithName:@"Menlo" size:9.0] ?: [UIFont systemFontOfSize:9.0]; // Smaller font size
    self.passwordRequirementsLabel.textColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1.0];
    self.passwordRequirementsLabel.numberOfLines = 0; // Multiple lines
    // Compact form with requirements on a single line
    self.passwordRequirementsLabel.text = @"REQUIREMENTS: 8+ chars • 1+ number • 1+ letter • 1+ special char";
    self.passwordRequirementsLabel.hidden = NO; // Show by default for better visibility
    self.passwordRequirementsLabel.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.15 alpha:0.9];
    self.passwordRequirementsLabel.layer.cornerRadius = 4.0; // Smaller corner radius
    self.passwordRequirementsLabel.layer.masksToBounds = YES;
    
    // Add some padding
    self.passwordRequirementsLabel.layer.borderWidth = 1;
    self.passwordRequirementsLabel.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.4].CGColor;
    
    // Add padding for the text using insets via a UIEdgeInsets and Core Text
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.firstLineHeadIndent = 8.0;
    paragraphStyle.headIndent = 8.0;
    paragraphStyle.tailIndent = -8.0;
    
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:self.passwordRequirementsLabel.text];
    [attributedText addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, attributedText.length)];
    self.passwordRequirementsLabel.attributedText = attributedText;
    
    [self.cardView addSubview:self.passwordRequirementsLabel];
    
    // Signup Button with hacker style
    self.signupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.signupButton setTitle:@"INITIALIZE USER" forState:UIControlStateNormal];
    [self.signupButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.signupButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    self.signupButton.layer.cornerRadius = 6.0; // More angular for hacker style
    self.signupButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:16.0] ?: [UIFont boldSystemFontOfSize:16.0];
    self.signupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.signupButton addTarget:self action:@selector(signupButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.signupButton];
    
    // Login Button with hacker style
    self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.loginButton setTitle:@"RETURN TO LOGIN" forState:UIControlStateNormal];
    [self.loginButton setTitleColor:[UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.8] forState:UIControlStateNormal]; // Neon green
    self.loginButton.titleLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont systemFontOfSize:12.0];
    self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loginButton addTarget:self action:@selector(loginButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.loginButton];
    
    // Activity Indicator with hacker theme
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.color = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Neon green
    self.activityIndicator.hidesWhenStopped = YES;
    [self.cardView addSubview:self.activityIndicator];
    
    // Layout Constraints
    [NSLayoutConstraint activateConstraints:@[
        // Card View
        [self.cardView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
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
        
        // Name Container
        [self.nameContainer.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:25],
        [self.nameContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.nameContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.nameContainer.heightAnchor constraintEqualToConstant:50],
        
        // Name Icon
        [nameIcon.leadingAnchor constraintEqualToAnchor:self.nameContainer.leadingAnchor constant:15],
        [nameIcon.centerYAnchor constraintEqualToAnchor:self.nameContainer.centerYAnchor],
        [nameIcon.widthAnchor constraintEqualToConstant:20],
        [nameIcon.heightAnchor constraintEqualToConstant:20],
        
        // Name Field
        [self.nameField.leadingAnchor constraintEqualToAnchor:nameIcon.trailingAnchor constant:10],
        [self.nameField.trailingAnchor constraintEqualToAnchor:self.nameContainer.trailingAnchor constant:-15],
        [self.nameField.topAnchor constraintEqualToAnchor:self.nameContainer.topAnchor],
        [self.nameField.bottomAnchor constraintEqualToAnchor:self.nameContainer.bottomAnchor],
        
        // Email Container
        [self.emailContainer.topAnchor constraintEqualToAnchor:self.nameContainer.bottomAnchor constant:15],
        [self.emailContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.emailContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.emailContainer.heightAnchor constraintEqualToConstant:50],
        
        // Email Icon
        [emailIcon.leadingAnchor constraintEqualToAnchor:self.emailContainer.leadingAnchor constant:15],
        [emailIcon.centerYAnchor constraintEqualToAnchor:self.emailContainer.centerYAnchor],
        [emailIcon.widthAnchor constraintEqualToConstant:20],
        [emailIcon.heightAnchor constraintEqualToConstant:20],
        
        // Email Field
        [self.emailField.leadingAnchor constraintEqualToAnchor:emailIcon.trailingAnchor constant:10],
        [self.emailField.trailingAnchor constraintEqualToAnchor:self.emailContainer.trailingAnchor constant:-15],
        [self.emailField.topAnchor constraintEqualToAnchor:self.emailContainer.topAnchor],
        [self.emailField.bottomAnchor constraintEqualToAnchor:self.emailContainer.bottomAnchor],
        
        // Password Container
        [self.passwordContainer.topAnchor constraintEqualToAnchor:self.emailContainer.bottomAnchor constant:15],
        [self.passwordContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.passwordContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.passwordContainer.heightAnchor constraintEqualToConstant:50],
        
        // Password Icon
        [passwordIcon.leadingAnchor constraintEqualToAnchor:self.passwordContainer.leadingAnchor constant:15],
        [passwordIcon.centerYAnchor constraintEqualToAnchor:self.passwordContainer.centerYAnchor],
        [passwordIcon.widthAnchor constraintEqualToConstant:20],
        [passwordIcon.heightAnchor constraintEqualToConstant:20],
        
        // Password Field
        [self.passwordField.leadingAnchor constraintEqualToAnchor:passwordIcon.trailingAnchor constant:10],
        [self.passwordField.trailingAnchor constraintEqualToAnchor:self.passwordVisibilityButton.leadingAnchor constant:-5],
        [self.passwordField.topAnchor constraintEqualToAnchor:self.passwordContainer.topAnchor],
        [self.passwordField.bottomAnchor constraintEqualToAnchor:self.passwordContainer.bottomAnchor],
        
        // Password Visibility Button
        [self.passwordVisibilityButton.centerYAnchor constraintEqualToAnchor:self.passwordContainer.centerYAnchor],
        [self.passwordVisibilityButton.trailingAnchor constraintEqualToAnchor:self.passwordContainer.trailingAnchor constant:-10],
        [self.passwordVisibilityButton.widthAnchor constraintEqualToConstant:30],
        [self.passwordVisibilityButton.heightAnchor constraintEqualToConstant:30],
        
        // Confirm Password Container
        [self.confirmPasswordContainer.topAnchor constraintEqualToAnchor:self.passwordRequirementsLabel.bottomAnchor constant:8],
        [self.confirmPasswordContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.confirmPasswordContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.confirmPasswordContainer.heightAnchor constraintEqualToConstant:50],
        
        // Confirm Password Icon
        [confirmPasswordIcon.leadingAnchor constraintEqualToAnchor:self.confirmPasswordContainer.leadingAnchor constant:15],
        [confirmPasswordIcon.centerYAnchor constraintEqualToAnchor:self.confirmPasswordContainer.centerYAnchor],
        [confirmPasswordIcon.widthAnchor constraintEqualToConstant:20],
        [confirmPasswordIcon.heightAnchor constraintEqualToConstant:20],
        
        // Confirm Password Field
        [self.confirmPasswordField.leadingAnchor constraintEqualToAnchor:confirmPasswordIcon.trailingAnchor constant:10],
        [self.confirmPasswordField.trailingAnchor constraintEqualToAnchor:self.confirmPasswordVisibilityButton.leadingAnchor constant:-5],
        [self.confirmPasswordField.topAnchor constraintEqualToAnchor:self.confirmPasswordContainer.topAnchor],
        [self.confirmPasswordField.bottomAnchor constraintEqualToAnchor:self.confirmPasswordContainer.bottomAnchor],
        
        // Confirm Password Visibility Button
        [self.confirmPasswordVisibilityButton.centerYAnchor constraintEqualToAnchor:self.confirmPasswordContainer.centerYAnchor],
        [self.confirmPasswordVisibilityButton.trailingAnchor constraintEqualToAnchor:self.confirmPasswordContainer.trailingAnchor constant:-10],
        [self.confirmPasswordVisibilityButton.widthAnchor constraintEqualToConstant:30],
        [self.confirmPasswordVisibilityButton.heightAnchor constraintEqualToConstant:30],
        
        // Signup Button
        [self.signupButton.topAnchor constraintEqualToAnchor:self.confirmPasswordContainer.bottomAnchor constant:25],
        [self.signupButton.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.signupButton.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.signupButton.heightAnchor constraintEqualToConstant:50],
        
        // Login Button
        [self.loginButton.topAnchor constraintEqualToAnchor:self.signupButton.bottomAnchor constant:15],
        [self.loginButton.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.loginButton.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-20],
        
        // Activity Indicator
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.signupButton.centerYAnchor],
        
        // Password Requirements Label
        [self.passwordRequirementsLabel.topAnchor constraintEqualToAnchor:self.passwordContainer.bottomAnchor constant:5],
        [self.passwordRequirementsLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.passwordRequirementsLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.passwordRequirementsLabel.heightAnchor constraintEqualToConstant:30],
    ]];
}

#pragma mark - Button Actions

- (void)togglePasswordVisibility:(UIButton *)sender {
    self.passwordField.secureTextEntry = !self.passwordField.secureTextEntry;
    
    if (@available(iOS 13.0, *)) {
        UIImage *image = self.passwordField.secureTextEntry ? 
            [UIImage systemImageNamed:@"eye.slash"] : 
            [UIImage systemImageNamed:@"eye"];
        [self.passwordVisibilityButton setImage:image forState:UIControlStateNormal];
    } else {
        // Fallback for earlier iOS versions
        NSString *title = self.passwordField.secureTextEntry ? @"👁" : @"👁‍🗨";
        [self.passwordVisibilityButton setTitle:title forState:UIControlStateNormal];
    }
}

- (void)toggleConfirmPasswordVisibility:(UIButton *)sender {
    self.confirmPasswordField.secureTextEntry = !self.confirmPasswordField.secureTextEntry;
    
    if (@available(iOS 13.0, *)) {
        UIImage *image = self.confirmPasswordField.secureTextEntry ? 
            [UIImage systemImageNamed:@"eye.slash"] : 
            [UIImage systemImageNamed:@"eye"];
        [self.confirmPasswordVisibilityButton setImage:image forState:UIControlStateNormal];
    } else {
        // Fallback for earlier iOS versions
        NSString *title = self.confirmPasswordField.secureTextEntry ? @"👁" : @"👁‍🗨";
        [self.confirmPasswordVisibilityButton setTitle:title forState:UIControlStateNormal];
    }
}

- (void)signupButtonTapped {
    // Validate input fields
    NSString *name = self.nameField.text;
    NSString *email = self.emailField.text;
    NSString *password = self.passwordField.text;
    NSString *confirmPassword = self.confirmPasswordField.text;
    
    // Basic validation
    if (name.length == 0 || email.length == 0 || password.length == 0 || confirmPassword.length == 0) {
        [self showAlertWithTitle:@">> INPUT ERROR" message:@"ALL FIELDS REQUIRED FOR IDENTITY CREATION"];
        return;
    }
    
    // Email validation
    NSPredicate *emailPredicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", 
                                   @"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"];
    if (![emailPredicate evaluateWithObject:email]) {
        [self showAlertWithTitle:@">> EMAIL VALIDATION ERROR" message:@"INVALID EMAIL FORMAT DETECTED"];
        return;
    }
    
    // Password validation
    if (password.length < 8) {
        [self showAlertWithTitle:@">> SECURITY ISSUE" message:@"PASSWORD MUST BE AT LEAST 8 CHARACTERS"];
        return;
    }
    
    // Check for requirement of digits, uppercase, lowercase, and special characters
    NSString *digitPattern = @".*\\d.*"; // At least one digit
    NSString *letterPattern = @".*[A-Za-z].*"; // At least one letter (upper or lower)
    NSString *specialCharPattern = @".*[!@#$%^&*(),.?\":{}|<>].*"; // At least one special character
    
    BOOL hasDigit = [self matchesPattern:digitPattern forString:password];
    BOOL hasLetter = [self matchesPattern:letterPattern forString:password];
    BOOL hasSpecialChar = [self matchesPattern:specialCharPattern forString:password];
    
    if (!hasDigit) {
        [self showAlertWithTitle:@">> SECURITY ISSUE" message:@"PASSWORD MUST INCLUDE AT LEAST ONE NUMBER"];
        return;
    }
    
    if (!hasLetter) {
        [self showAlertWithTitle:@">> SECURITY ISSUE" message:@"PASSWORD MUST INCLUDE AT LEAST ONE LETTER"];
        return;
    }
    
    if (!hasSpecialChar) {
        [self showAlertWithTitle:@">> SECURITY ISSUE" message:@"PASSWORD MUST INCLUDE AT LEAST ONE SPECIAL CHARACTER"];
        return;
    }
    
    // Check if passwords match
    if (![password isEqualToString:confirmPassword]) {
        [self showAlertWithTitle:@">> PASSKEY MISMATCH" message:@"PASSKEYS DO NOT MATCH"];
        return;
    }
    
    // Start loading indicator
    [self.activityIndicator startAnimating];
    self.signupButton.enabled = NO;
    
    // Add hacker-style glitch animation for button
    [self addGlitchAnimation:self.signupButton];
    
    // Call the API to register the user
    NSLog(@"[WeaponX] Registering new user with email: %@", email);
    
    // Try multiple URL formats for shared hosting compatibility
    // Include only production URLs - no local development
    NSArray *possibleURLs = @[
        @"https://hydra.weaponx.us/api/register",
        @"https://hydra.weaponx.us/index.php/api/register",
        @"https://hydra.weaponx.us/register"
    ];
    
    [self tryRegistrationWithURLs:possibleURLs atIndex:0 name:name email:email password:password];
}

// Method to try registration with multiple URLs
- (void)tryRegistrationWithURLs:(NSArray *)urls atIndex:(NSUInteger)index name:(NSString *)name email:(NSString *)email password:(NSString *)password {
    if (index >= urls.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            self.signupButton.enabled = YES;
            [self showAlertWithTitle:@">> CONNECTION ERROR" message:@"UNABLE TO ESTABLISH SECURE CONNECTION TO SERVER"];
        });
        return;
    }
    
    NSString *urlString = urls[index];
    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[WeaponX] Trying registration URL (%lu of %lu): %@", (unsigned long)(index + 1), (unsigned long)urls.count, url);
    
    // First, check if we need to get a CSRF token for the production server
    if ([urlString containsString:@"hydra.weaponx.us"]) {
        // For the production server, we'll first make a GET request to get the CSRF token
        [self getCSRFTokenForURL:urlString completion:^(NSString *csrfToken) {
            [self performRegistrationWithURL:urlString csrfToken:csrfToken name:name email:email password:password];
        }];
    } else {
        // For local development, we can skip the CSRF token
        [self performRegistrationWithURL:urlString csrfToken:nil name:name email:email password:password];
    }
}

// Helper method to get CSRF token - similar to LoginViewController
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
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(csrfToken);
        });
    }];
    
    [task resume];
}

// Helper method to perform registration with optional CSRF token
- (void)performRegistrationWithURL:(NSString *)urlString csrfToken:(NSString *)csrfToken name:(NSString *)name email:(NSString *)email password:(NSString *)password {
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
        NSLog(@"[WeaponX] Adding CSRF token to registration request with header X-XSRF-TOKEN: %@", csrfToken);
    } else {
        NSLog(@"[WeaponX] No CSRF token available, proceeding without it since registration route might be excluded from CSRF verification");
    }
    
    request.timeoutInterval = 30.0;
    
    // Convert email to lowercase to ensure case-insensitive registration
    NSString *lowercaseEmail = [email lowercaseString];
    
    // Get device unique identifiers
    NSDictionary *deviceIdentifiers = [self getDeviceIdentifiers];
    
    // Create registration payload
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
        @"name": name,
        @"email": lowercaseEmail,
        @"password": password,
        @"password_confirmation": password,
        @"device_model": [self getDetailedDeviceModel],
        @"device_name": [[UIDevice currentDevice] name],
        @"system_version": [[UIDevice currentDevice] systemVersion]
    }];
    
    // Add device identifiers to the registration payload if available
    if (deviceIdentifiers[@"device_uuid"]) {
        body[@"device_uuid"] = deviceIdentifiers[@"device_uuid"];
    }
    
    if (deviceIdentifiers[@"device_serial"]) {
        body[@"device_serial"] = deviceIdentifiers[@"device_serial"];
    }
    
    NSLog(@"[WeaponX] Registration payload: %@", @{
        @"name": name, 
        @"email": lowercaseEmail, 
        @"password": @"[REDACTED]", 
        @"password_confirmation": @"[REDACTED]",
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
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            self.signupButton.enabled = YES;
            [self showAlertWithTitle:@">> SYSTEM ERROR" message:@"INTERNAL ENCRYPTION ERROR"];
        });
        return;
    }
    
    request.HTTPBody = jsonData;
    
    NSLog(@"[WeaponX] Sending registration request to %@...", urlString);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] Registration response status code: %ld", (long)httpResponse.statusCode);
        NSLog(@"[WeaponX] Registration response headers: %@", httpResponse.allHeaderFields);
        
        if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"[WeaponX] Registration response body: %@", responseString);
        }
        
        if (error || httpResponse.statusCode == 404 || httpResponse.statusCode >= 500) {
            NSLog(@"[WeaponX] URL %@ returned status %ld, error: %@", urlString, (long)httpResponse.statusCode, error);
            // Try next URL
            dispatch_async(dispatch_get_main_queue(), ^{
                [self tryRegistrationWithURLs:@[
                    @"https://hydra.weaponx.us/api/register",
                    @"https://hydra.weaponx.us/index.php/api/register",
                    @"https://hydra.weaponx.us/register"
                ] atIndex:[urlString isEqualToString:@"https://hydra.weaponx.us/api/register"] ? 1 : 
                          ([urlString isEqualToString:@"https://hydra.weaponx.us/index.php/api/register"] ? 2 : 0)
                             name:name email:email password:password];
            });
            return;
        }
        
        // If we get a CSRF token mismatch (419), try to get a new token and retry
        if (httpResponse.statusCode == 419) {
            NSLog(@"[WeaponX] CSRF token mismatch (419), trying to get a new token");
            [self getCSRFTokenForURL:urlString completion:^(NSString *newCsrfToken) {
                if (newCsrfToken) {
                    [self performRegistrationWithURL:urlString csrfToken:newCsrfToken name:name email:email password:password];
                } else {
                    // Try next URL if we couldn't get a token
                    [self tryRegistrationWithURLs:@[
                        @"https://hydra.weaponx.us/api/register",
                        @"https://hydra.weaponx.us/index.php/api/register",
                        @"https://hydra.weaponx.us/register"
                    ] atIndex:[urlString isEqualToString:@"https://hydra.weaponx.us/api/register"] ? 1 : 
                              ([urlString isEqualToString:@"https://hydra.weaponx.us/index.php/api/register"] ? 2 : 0)
                                name:name email:email password:password];
                }
            }];
            return;
        }
        
        // Handle the response on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleRegistrationResponse:data response:httpResponse error:error name:name email:email password:password];
        });
    }];
    
    [task resume];
}

// Handle registration response from the server
- (void)handleRegistrationResponse:(NSData *)data response:(NSHTTPURLResponse *)httpResponse error:(NSError *)error name:(NSString *)name email:(NSString *)email password:(NSString *)password {
    [self.activityIndicator stopAnimating];
    self.signupButton.enabled = YES;
    
    if (httpResponse.statusCode != 200 && httpResponse.statusCode != 201) {
        // Try to parse error message from response
        NSString *errorMessage = @"REGISTRATION FAILED: SECURITY PROTOCOL VIOLATION";
        if (data) {
            NSError *jsonError;
            NSDictionary *errorJson = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!jsonError && errorJson[@"message"]) {
                errorMessage = [NSString stringWithFormat:@"REGISTRATION FAILED: %@", errorJson[@"message"]];
            } else if (!jsonError && errorJson[@"error"]) {
                errorMessage = [NSString stringWithFormat:@"REGISTRATION FAILED: %@", errorJson[@"error"]];
            }
        }
        NSLog(@"[WeaponX] Registration failed with status code: %ld, message: %@", (long)httpResponse.statusCode, errorMessage);
        [self showAlertWithTitle:@">> REGISTRATION ERROR" message:errorMessage];
        return;
    }
    
    // Registration successful
    NSLog(@"[WeaponX] Registration successful");
    
    // Save user info to NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Clear any previous authentication data first
    NSLog(@"[WeaponX] Clearing all previous authentication data");
    [defaults removeObjectForKey:@"WeaponXAuthToken"];
    [defaults removeObjectForKey:@"WeaponXUserInfo"];
    [defaults removeObjectForKey:@"Username"];
    [defaults removeObjectForKey:@"UserEmail"];
    [defaults removeObjectForKey:@"WeaponXUserPlan"];
    [defaults removeObjectForKey:@"LastLoginTimestamp"];
    [defaults removeObjectForKey:@"SessionData"];
    [defaults removeObjectForKey:@"WeaponXServerUserId"];
    [defaults synchronize];
    
    // Try to extract token and user data from response
    NSError *jsonError;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    
    if (!jsonError && json[@"token"]) {
        // Some APIs return token directly after registration
        NSLog(@"[WeaponX] Registration response included auth token");
        
        NSString *token = json[@"token"];
        NSLog(@"[WeaponX] Received token: %@", token);
        
        // Parse token to extract user ID
        NSString *userIdFromToken = nil;
        if ([token containsString:@"|"]) {
            NSArray *tokenParts = [token componentsSeparatedByString:@"|"];
            if (tokenParts.count > 0) {
                userIdFromToken = tokenParts.firstObject;
                NSLog(@"[WeaponX] Extracted user ID from token: %@", userIdFromToken);
            }
        }
        
        // Get user info from response
        NSDictionary *userInfo = json[@"user"];
        NSString *userInfoId = nil;
        
        if (userInfo && userInfo[@"id"]) {
            userInfoId = [NSString stringWithFormat:@"%@", userInfo[@"id"]];
            NSLog(@"[WeaponX] User info contains ID: %@", userInfoId);
            
            // Always store the actual user ID from response separately
            [defaults setObject:userInfoId forKey:@"WeaponXServerUserId"];
        }
        
        // Check if token user ID doesn't match the user info ID
        if (userIdFromToken && userInfoId && ![userIdFromToken isEqualToString:userInfoId]) {
            NSLog(@"[WeaponX] WARNING: Token user ID (%@) doesn't match user info ID (%@)", userIdFromToken, userInfoId);
            
            // Clear URL cache before attempting token reset
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            
            // Use the reset-usertoken.php endpoint to get a new token with the correct user ID
            [self resetUserTokenForUserId:userInfoId completion:^(NSString *newToken, NSError *tokenError) {
                if (tokenError) {
                    NSLog(@"[WeaponX] Failed to reset user token: %@", tokenError);
                    
                    // Add additional logging for troubleshooting
                    if ([tokenError.domain isEqualToString:@"NSURLErrorDomain"]) {
                        NSLog(@"[WeaponX] Network error during token reset: %@", tokenError.localizedDescription);
                    } else if ([tokenError.domain isEqualToString:@"SignupViewControllerErrorDomain"]) {
                        NSLog(@"[WeaponX] Server error during token reset: %@", tokenError.localizedDescription);
                    }
                    
                    // Continue with the original token as fallback
                    NSLog(@"[WeaponX] Using original token as fallback");
                    [self completeRegistrationWithToken:token userInfo:userInfo name:name email:email];
                } else if (newToken) {
                    NSLog(@"[WeaponX] Successfully reset token to match user ID: %@", userInfoId);
                    
                    // Verify the new token format
                    NSArray *newTokenParts = [newToken componentsSeparatedByString:@"|"];
                    if (newTokenParts.count > 0) {
                        NSString *newUserIdFromToken = newTokenParts[0];
                        
                        if ([newUserIdFromToken isEqualToString:userInfoId]) {
                            NSLog(@"[WeaponX] Verified new token has correct user ID: %@", newUserIdFromToken);
                        } else {
                            NSLog(@"[WeaponX] WARNING: New token still has incorrect user ID: %@ (expected: %@)", 
                                  newUserIdFromToken, userInfoId);
                        }
                    }
                    
                    // Add a short delay to ensure token propagation to server
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        // Use the new token instead
                        [self completeRegistrationWithToken:newToken userInfo:userInfo name:name email:email];
                    });
                } else {
                    NSLog(@"[WeaponX] Token reset did not return a new token, using original token as fallback");
                    // Continue with the original token as fallback
                    [self completeRegistrationWithToken:token userInfo:userInfo name:name email:email];
                }
            }];
        } else {
            // Token and user ID match, proceed normally
            [self completeRegistrationWithToken:token userInfo:userInfo name:name email:email];
        }
    } else {
        // If the API doesn't return a token, we need to auto-login in a second step
        NSLog(@"[WeaponX] Registration response did not include token, need to auto-login");
        
        // Show success message
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@">> ACCESS GRANTED" 
                                                                   message:@"IDENTITY CREATED - INITIATING AUTO-LOGIN" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
        
        [self presentViewController:alert animated:YES completion:^{
            // Dismiss the alert after a short delay and proceed with login
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:^{
                    // Auto-login
                    [self performAutoLoginWithEmail:email password:password];
                }];
            });
        }];
    }
}

// Helper method to complete registration with a token
- (void)completeRegistrationWithToken:(NSString *)token userInfo:(NSDictionary *)userInfo name:(NSString *)name email:(NSString *)email {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Store the token
    [defaults setObject:token forKey:@"WeaponXAuthToken"];
    
    if (userInfo) {
        [defaults setObject:userInfo forKey:@"WeaponXUserInfo"];
        
        // Store username and email directly for easier access
        if (userInfo[@"name"]) {
            [defaults setObject:userInfo[@"name"] forKey:@"Username"];
        } else {
            [defaults setObject:name forKey:@"Username"];
        }
        
        if (userInfo[@"email"]) {
            [defaults setObject:userInfo[@"email"] forKey:@"UserEmail"];
        } else {
            [defaults setObject:email forKey:@"UserEmail"];
        }
        } else {
            // Create a basic user info dictionary
        NSDictionary *basicUserInfo = @{
                @"name": name,
                @"email": email
            };
        
        [defaults setObject:basicUserInfo forKey:@"WeaponXUserInfo"];
        
        // Store username and email directly for easier access
        [defaults setObject:name forKey:@"Username"];
        [defaults setObject:email forKey:@"UserEmail"];
        
        // In this case, make an additional API call to get the user ID from the server
        NSLog(@"[WeaponX] No user info in signup response - will fetch user data to get correct server ID");
        
        // Create API Manager instance if needed
        Class apiManagerClass = NSClassFromString(@"APIManager");
        if (apiManagerClass) {
            id apiManager = [apiManagerClass performSelector:@selector(sharedManager)];
            if (apiManager && [apiManager respondsToSelector:@selector(fetchUserDataWithToken:completion:)]) {
                NSLog(@"[WeaponX] Fetching user data to get server ID after signup");
                
                // Add a short delay before making the API call to ensure token propagation
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [apiManager performSelector:@selector(fetchUserDataWithToken:completion:) 
                                    withObject:token 
                                    withObject:^(NSDictionary *userData, NSError *error) {
                        if (!error && userData && userData[@"id"]) {
                            NSString *serverId = [NSString stringWithFormat:@"%@", userData[@"id"]];
                            NSLog(@"[WeaponX] Fetched server user ID: %@ after signup", serverId);
                            
                            // Save the server ID
                            NSMutableDictionary *updatedUserInfo = [[defaults objectForKey:@"WeaponXUserInfo"] mutableCopy];
                            updatedUserInfo[@"id"] = serverId;
                            [defaults setObject:updatedUserInfo forKey:@"WeaponXUserInfo"];
                            [defaults setObject:serverId forKey:@"WeaponXServerUserId"];
        [defaults synchronize];
                        } else if (error) {
                            NSLog(@"[WeaponX] Error fetching user data after signup: %@", error);
                            
                            // If we got a 401 error, try to use our retry mechanism with direct API call
                            if ([error.domain isEqualToString:@"NSURLErrorDomain"] || 
                                ([error.domain isEqualToString:@"APIManagerErrorDomain"] && error.code == 401)) {
                                
                                NSLog(@"[WeaponX] Got 401 error when fetching user data - will try manual API call with retries");
                                
                                // Get the API URL for user data
                                NSString *baseUrl = [self apiBaseUrl];
                                NSString *userDataUrl = [NSString stringWithFormat:@"%@/api/user", baseUrl];
                                
                                // Setup headers with token
                                NSDictionary *headers = @{
                                    @"Accept": @"application/json",
                                    @"Authorization": [NSString stringWithFormat:@"Bearer %@", token]
                                };
                                
                                // Make API request with retry
                                [self performAPIRequestWithURL:[NSURL URLWithString:userDataUrl]
                                                       method:@"GET"
                                                         body:nil
                                                      headers:headers
                                                   retryCount:0
                                                   maxRetries:3
                                                   completion:^(NSData *data, NSURLResponse *response, NSError *reqError) {
                                    if (!reqError && data) {
                                        NSError *jsonError;
                                        NSDictionary *userData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                                        
                                        if (!jsonError && userData && userData[@"id"]) {
                                            NSString *serverId = [NSString stringWithFormat:@"%@", userData[@"id"]];
                                            NSLog(@"[WeaponX] Successfully fetched user ID: %@ with retry mechanism", serverId);
                                            
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                // Save the server ID
                                                NSMutableDictionary *updatedUserInfo = [[defaults objectForKey:@"WeaponXUserInfo"] mutableCopy];
                                                updatedUserInfo[@"id"] = serverId;
                                                [defaults setObject:updatedUserInfo forKey:@"WeaponXUserInfo"];
                                                [defaults setObject:serverId forKey:@"WeaponXServerUserId"];
                                                [defaults synchronize];
                                            });
                                        } else {
                                            NSLog(@"[WeaponX] Failed to parse user data with retry mechanism: %@", jsonError ?: @"No user ID in response");
                                        }
                                    } else {
                                        NSLog(@"[WeaponX] Failed to fetch user data with retry mechanism: %@", reqError ?: @"No data received");
                                    }
                                }];
                            }
                        }
                    }];
                });
            }
        }
    }
    
    [defaults synchronize];
    NSLog(@"[WeaponX] Authentication data saved and synchronized");
        
        // Post notification for successful login
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserDidLogin" object:nil];
        
        // Show success message and dismiss
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@">> ACCESS GRANTED" 
                                                                   message:@"IDENTITY SUCCESSFULLY CREATED" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"CONTINUE" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            // Call completion handler and dismiss all screens
            if (self.signupCompletionHandler) {
                // First dismiss the signup screen
                [self dismissViewControllerAnimated:YES completion:^{
                    // Then let the completion handler handle any parent dismissals
                    self.signupCompletionHandler();
                }];
            } else {
                // Just dismiss the signup screen
                [self dismissViewControllerAnimated:YES completion:nil];
            }
        }]];
        
        [self presentViewController:alert animated:YES completion:nil];
}

// Method to reset user token
- (void)resetUserTokenForUserId:(NSString *)userId completion:(void (^)(NSString *newToken, NSError *error))completion {
    NSString *baseUrl = [self apiBaseUrl];
    NSString *resetUrl = [NSString stringWithFormat:@"%@/reset-usertoken.php?user_id=%@", baseUrl, userId];
    
    NSLog(@"[WeaponX] Attempting to reset token for user ID: %@", userId);
    NSLog(@"[WeaponX] Reset URL: %@", resetUrl);
    
    // Clear URL cache before making the request
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSLog(@"[WeaponX] Cleared URL cache before token reset request");
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:resetUrl]];
    
    // Add useful headers for debugging
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:userId forHTTPHeaderField:@"X-Expected-User-Id"];
    // Add cache control headers
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:[NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]] forHTTPHeaderField:@"X-Timestamp"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[WeaponX] Error resetting user token: %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSLog(@"[WeaponX] Token reset failed with status code: %ld", (long)httpResponse.statusCode);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *httpError = [NSError errorWithDomain:@"SignupViewControllerErrorDomain" 
                                                             code:httpResponse.statusCode 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to reset token"}];
                    completion(nil, httpError);
                });
            }
            return;
        }
        
        if (data) {
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] Error parsing token reset response: %@", jsonError);
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, jsonError);
                    });
                }
                return;
            }
            
            NSLog(@"[WeaponX] Token reset response: %@", responseDict);
            
            // Check for new token in different response formats
            NSString *newToken = nil;
            
            // First try to get token from data.new_token (current format)
            if (responseDict[@"data"] && [responseDict[@"data"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *data = responseDict[@"data"];
                newToken = data[@"new_token"];
                if (newToken) {
                    NSLog(@"[WeaponX] Found new token in data.new_token: %@", newToken);
                }
            }
            
            // Then try details.new_token (older format)
            if (!newToken && responseDict[@"details"] && [responseDict[@"details"] isKindOfClass:[NSDictionary class]]) {
                newToken = responseDict[@"details"][@"new_token"];
                if (newToken) {
                    NSLog(@"[WeaponX] Found new token in details.new_token: %@", newToken);
                }
            }
            
            // If not found, try the data array format (very old format)
            if (!newToken && [responseDict[@"success"] boolValue] && responseDict[@"data"] && [responseDict[@"data"] isKindOfClass:[NSArray class]]) {
                NSArray *results = responseDict[@"data"];
                if (results.count > 0 && [results[0] isKindOfClass:[NSDictionary class]]) {
                    newToken = results[0][@"new_token"];
                    if (newToken) {
                        NSLog(@"[WeaponX] Found new token in data[0].new_token: %@", newToken);
                    }
                }
            }
            
            // Direct token key check
            if (!newToken && responseDict[@"token"]) {
                newToken = responseDict[@"token"];
                NSLog(@"[WeaponX] Found new token in direct token key: %@", newToken);
            }
            
            // If still not found, log the available keys
            if (!newToken) {
                NSLog(@"[WeaponX] No token found in expected locations. Available keys: %@", [responseDict allKeys]);
                
                if (responseDict[@"data"]) {
                    NSLog(@"[WeaponX] Data content type: %@, value: %@", 
                          NSStringFromClass([responseDict[@"data"] class]),
                          responseDict[@"data"]);
                }
            }
            
            if (newToken) {
                NSLog(@"[WeaponX] Successfully reset token for user ID: %@", userId);
                
                // Add a delay before returning the new token to ensure server propagation
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    NSLog(@"[WeaponX] Waiting 1 second after token reset to ensure server propagation");
                    if (completion) {
                        completion(newToken, nil);
                    }
                });
                return;
            }
            
            NSLog(@"[WeaponX] Token reset response did not contain a new token");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *dataError = [NSError errorWithDomain:@"SignupViewControllerErrorDomain" 
                                                            code:0 
                                                        userInfo:@{NSLocalizedDescriptionKey: @"No new token in response"}];
                    completion(nil, dataError);
                });
            }
        } else {
            NSLog(@"[WeaponX] No data received from token reset endpoint");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *noDataError = [NSError errorWithDomain:@"SignupViewControllerErrorDomain" 
                                                              code:0 
                                                          userInfo:@{NSLocalizedDescriptionKey: @"No data received"}];
                    completion(nil, noDataError);
                });
            }
        }
    }];
    
    [task resume];
}

// Helper method to get API base URL
- (NSString *)apiBaseUrl {
    // Always use production URL
    return @"https://hydra.weaponx.us";
}

// Method to perform auto-login after registration
- (void)performAutoLoginWithEmail:(NSString *)email password:(NSString *)password {
    NSLog(@"[WeaponX] Performing auto-login after registration");
    [self.activityIndicator startAnimating];
    
    // Convert email to lowercase to ensure case-insensitive login
    NSString *lowercaseEmail = [email lowercaseString];
    
    // Try multiple URL formats for login
    NSArray *possibleURLs = @[
        @"https://hydra.weaponx.us/api/login",
        @"https://hydra.weaponx.us/index.php/api/login",
        @"https://hydra.weaponx.us/login",
        @"http://localhost/api/login",
        @"http://127.0.0.1/api/login",
        @"http://localhost:8000/api/login"
    ];
    
    [self tryLoginWithURLs:possibleURLs atIndex:0 email:lowercaseEmail password:password];
}

// Method to try login with multiple URLs
- (void)tryLoginWithURLs:(NSArray *)urls atIndex:(NSUInteger)index email:(NSString *)email password:(NSString *)password {
    if (index >= urls.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            [self showAlertWithTitle:@">> CONNECTION ERROR" message:@"AUTO-LOGIN FAILED - PLEASE LOGIN MANUALLY"];
            // Still dismiss the signup screen
            [self dismissViewControllerAnimated:YES completion:^{
                if (self.signupCompletionHandler) {
                    self.signupCompletionHandler();
                }
            }];
        });
        return;
    }
    
    NSString *urlString = urls[index];
    NSURL *url = [NSURL URLWithString:urlString];
    NSLog(@"[WeaponX] Trying login URL (%lu of %lu): %@", (unsigned long)(index + 1), (unsigned long)urls.count, url);
    
    // Create request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // Email should already be lowercase from performAutoLoginWithEmail, but ensure it here as well
    NSString *lowercaseEmail = [email lowercaseString];
    
    // Create login payload
    NSDictionary *body = @{
        @"email": lowercaseEmail,
        @"password": password
    };
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    
    if (error) {
        NSLog(@"[WeaponX] Failed to serialize JSON for login: %@", error);
        [self tryLoginWithURLs:urls atIndex:index + 1 email:email password:password];
        return;
    }
    
    request.HTTPBody = jsonData;
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[WeaponX] Auto-login response status code: %ld", (long)httpResponse.statusCode);
        
        if (error || httpResponse.statusCode == 404 || httpResponse.statusCode >= 500) {
            NSLog(@"[WeaponX] URL %@ returned status %ld, error: %@", urlString, (long)httpResponse.statusCode, error);
            // Try next URL
            [self tryLoginWithURLs:urls atIndex:index + 1 email:email password:password];
            return;
        }
        
        // Handle login response
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleLoginResponse:data response:httpResponse error:error email:email password:password];
        });
    }];
    
    [task resume];
}

// Handle login response
- (void)handleLoginResponse:(NSData *)data response:(NSHTTPURLResponse *)httpResponse error:(NSError *)error email:(NSString *)email password:(NSString *)password {
    [self.activityIndicator stopAnimating];
    
    if (httpResponse.statusCode != 200 && httpResponse.statusCode != 201) {
        NSLog(@"[WeaponX] Auto-login failed with status code: %ld", (long)httpResponse.statusCode);
        [self showAlertWithTitle:@">> AUTO-LOGIN FAILED" message:@"PLEASE LOG IN MANUALLY"];
        
        // Still dismiss the signup screen
        [self dismissViewControllerAnimated:YES completion:^{
            if (self.signupCompletionHandler) {
                self.signupCompletionHandler();
            }
        }];
        return;
    }
    
    // Login successful
    NSLog(@"[WeaponX] Auto-login successful");
    
    // Parse response
    NSError *jsonError;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    
    if (jsonError) {
        NSLog(@"[WeaponX] Failed to parse login response: %@", jsonError);
        [self showAlertWithTitle:@">> DECRYPTION ERROR" message:@"LOGIN SUCCESSFUL BUT DATA CORRUPTED"];
        return;
    }
    
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
            
            NSString *message = [NSString stringWithFormat:@"This app version (%@) is no longer supported. Please update to version %@ or later.", currentVersion, minAllowedVersion];
            [self showAlertWithTitle:@">> UPDATE REQUIRED" message:message];
            return;
        }
    }
    
    // Clear any previous authentication data first
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSLog(@"[WeaponX] Clearing all previous authentication data");
    [defaults removeObjectForKey:@"WeaponXAuthToken"];
    [defaults removeObjectForKey:@"WeaponXUserInfo"];
    [defaults removeObjectForKey:@"Username"];
    [defaults removeObjectForKey:@"UserEmail"];
    [defaults removeObjectForKey:@"WeaponXUserPlan"];
    [defaults removeObjectForKey:@"LastLoginTimestamp"];
    [defaults removeObjectForKey:@"SessionData"];
    [defaults removeObjectForKey:@"WeaponXServerUserId"];
    [defaults synchronize];
    
    // Extract and save token
    NSString *token = json[@"token"];
    if (!token) {
        NSLog(@"[WeaponX] Error: No token found in login response");
        [self showAlertWithTitle:@">> AUTH ERROR" message:@"NO TOKEN RECEIVED FROM SERVER"];
        return;
    }
    
    NSLog(@"[WeaponX] Received token: %@", token);
    
    // Parse token to extract user ID
    NSString *userIdFromToken = nil;
    if ([token containsString:@"|"]) {
        NSArray *tokenParts = [token componentsSeparatedByString:@"|"];
        if (tokenParts.count > 0) {
            userIdFromToken = tokenParts.firstObject;
            NSLog(@"[WeaponX] Extracted user ID from token: %@", userIdFromToken);
        }
    } else {
        NSLog(@"[WeaponX] Warning: Token format does not contain expected separator '|'");
    }
    
    // Save the token
    [defaults setObject:token forKey:@"WeaponXAuthToken"];
    
    // Process user data
    if (json[@"user"]) {
        NSMutableDictionary *userInfo = [json[@"user"] mutableCopy];
        
        // Convert IDs to string for consistent comparison
        NSString *userInfoId = [NSString stringWithFormat:@"%@", userInfo[@"id"]];
        
        // Check if token user ID doesn't match the user info ID
        if (userIdFromToken && userInfoId && ![userIdFromToken isEqualToString:userInfoId]) {
            NSLog(@"[WeaponX] WARNING: Token user ID (%@) doesn't match user info ID (%@)", userIdFromToken, userInfoId);
            
            // Clear URL cache before attempting token reset
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            
            // Use the reset-usertoken.php endpoint to get a new token with the correct user ID
            [self resetUserTokenForUserId:userInfoId completion:^(NSString *newToken, NSError *tokenError) {
                if (tokenError) {
                    NSLog(@"[WeaponX] Failed to reset user token: %@", tokenError);
                    
                    // Add additional logging for troubleshooting
                    if ([tokenError.domain isEqualToString:@"NSURLErrorDomain"]) {
                        NSLog(@"[WeaponX] Network error during token reset: %@", tokenError.localizedDescription);
                    } else if ([tokenError.domain isEqualToString:@"SignupViewControllerErrorDomain"]) {
                        NSLog(@"[WeaponX] Server error during token reset: %@", tokenError.localizedDescription);
                    }
                    
                    // Continue with the original token as fallback
                    NSLog(@"[WeaponX] Using original token as fallback");
                    [self completeLoginWithToken:token userInfo:userInfo];
                } else if (newToken) {
                    NSLog(@"[WeaponX] Successfully reset token to match user ID: %@", userInfoId);
                    
                    // Verify the new token format
                    NSArray *newTokenParts = [newToken componentsSeparatedByString:@"|"];
                    if (newTokenParts.count > 0) {
                        NSString *newUserIdFromToken = newTokenParts[0];
                        
                        if ([newUserIdFromToken isEqualToString:userInfoId]) {
                            NSLog(@"[WeaponX] Verified new token has correct user ID: %@", newUserIdFromToken);
                        } else {
                            NSLog(@"[WeaponX] WARNING: New token still has incorrect user ID: %@ (expected: %@)", 
                                  newUserIdFromToken, userInfoId);
                        }
                    }
                    
                    // Add a short delay to ensure token propagation to server
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        // Use the new token instead
                        [self completeLoginWithToken:newToken userInfo:userInfo];
                    });
                } else {
                    NSLog(@"[WeaponX] Token reset did not return a new token, using original token as fallback");
                    // Continue with the original token as fallback
                    [self completeLoginWithToken:token userInfo:userInfo];
                }
            }];
        } else {
            // Token and user ID match, proceed normally
            [self completeLoginWithToken:token userInfo:userInfo];
        }
    } else {
        NSLog(@"[WeaponX] Warning: No user data found in login response");
        // Create basic user info based on email and token
        NSDictionary *userInfo = @{
            @"email": email,
            @"id": userIdFromToken ?: @""
        };
        
        if (!userIdFromToken) {
            NSLog(@"[WeaponX] WARNING: No user ID available from token during signup");
        }
        
        [self completeLoginWithToken:token userInfo:userInfo];
    }
}

// Helper method to complete login with a token
- (void)completeLoginWithToken:(NSString *)token userInfo:(NSDictionary *)userInfo {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Save the token and user info
    [defaults setObject:token forKey:@"WeaponXAuthToken"];
    [defaults setObject:userInfo forKey:@"WeaponXUserInfo"];
    
    // Save the server ID explicitly for other parts of the app to use
    if (userInfo[@"id"]) {
        NSString *userInfoId = [NSString stringWithFormat:@"%@", userInfo[@"id"]];
        [defaults setObject:userInfoId forKey:@"WeaponXServerUserId"];
    }
    
    // Store username and email directly for easier access
    if (userInfo[@"name"]) {
        [defaults setObject:userInfo[@"name"] forKey:@"Username"];
    }
    if (userInfo[@"email"]) {
        [defaults setObject:userInfo[@"email"] forKey:@"UserEmail"];
    }
    
    [defaults synchronize];
    NSLog(@"[WeaponX] Authentication data saved and synchronized");
    
    // Post notification for successful login
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WeaponXUserDidLogin" object:nil];
    
    // Show success message
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@">> ACCESS GRANTED" 
                                                               message:@"LOGIN SUCCESSFUL" 
                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"CONTINUE" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // Call completion handler and dismiss all screens
        if (self.signupCompletionHandler) {
            // First dismiss the signup screen
            [self dismissViewControllerAnimated:YES completion:^{
                // Then let the completion handler handle any parent dismissals
                self.signupCompletionHandler();
            }];
        } else {
            // Just dismiss the signup screen
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)loginButtonTapped {
    // Dismiss view controller and return to login screen
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Helper Methods

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"ACKNOWLEDGE" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Add hacker-style glitch animation for button
- (void)addGlitchAnimation:(UIButton *)button {
    // Save original state
    UIColor *originalBackgroundColor = button.backgroundColor;
    UIColor *originalTitleColor = [button titleColorForState:UIControlStateNormal];
    NSString *originalTitle = [button titleForState:UIControlStateNormal];
    
    // First glitch the button immediately
        button.backgroundColor = [UIColor colorWithRed:0.1 green:0.9 blue:0.3 alpha:0.7];
    [button setTitle:@"1N1T14L1Z1NG_U53R" forState:UIControlStateNormal];

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
    terminalTitle.text = @"WEAPON-X IDENTITY CREATION MODULE v2.1.8";
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
    NSString *initText = @"WEAPON-X IDENTITY CREATION [Version 2.1.8]\n";
    initText = [initText stringByAppendingString:@"© 2025 Weapon-X Security. All rights reserved.\n\n"];
    initText = [initText stringByAppendingString:@"INITIALIZING USER CREATION PROTOCOL...\n"];
    terminalLabel.text = initText;
    
    // Add a scroll view so we can show more text
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 40, terminalView.bounds.size.width - 20, terminalView.bounds.size.height - 50)];
    scrollView.backgroundColor = [UIColor clearColor];
    scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [terminalView addSubview:scrollView];
    [scrollView addSubview:terminalLabel];
    
    [hackingOverlay addSubview:terminalView];
    [mainWindow addSubview:hackingOverlay];
    
    NSLog(@"[WeaponX] Added hacking animation overlay to main window (SignupViewController)");
    
    // Start the activity dot blinking
    [self animateActivityDot:activityDot];
    
    // Create a mutable string for the animation
    NSMutableString *animatedText = [NSMutableString stringWithString:initText];
    
    // Generate unique identifiers for this registration
    NSString *userId = [NSString stringWithFormat:@"WX%08X", arc4random_uniform(0xFFFFFFFF)];
    NSString *securityKey = [self generateRandomHexString:32];
    NSString *ipAddress = [self generateRandomIPAddress];
    NSString *userHash = [self generateRandomHexString:16];
    NSString *timestamp = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *macAddr = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", 
                   arc4random_uniform(255), arc4random_uniform(255), 
                   arc4random_uniform(255), arc4random_uniform(255), 
                   arc4random_uniform(255), arc4random_uniform(255)];
    NSString *diskSpace = [NSString stringWithFormat:@"%d", arc4random_uniform(900) + 100];
    NSString *kernelVer = [NSString stringWithFormat:@"%d.%d.%d", 
                     arc4random_uniform(5) + 4, 
                     arc4random_uniform(20), 
                     arc4random_uniform(90)];

    // Advanced terminal command sequence for user creation
    NSArray *hackingSequence = @[
        @{@"command": [NSString stringWithFormat:@"sudo ./create_user --module=weapon_x_identity"], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"Generating user template..."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Creating user cryptographic identity..."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"User ID assigned: %@", userId], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Security classification: LEVEL 3 - RESTRICTED"], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"ifconfig"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"        inet %@  netmask 255.255.255.0  broadcast 10.0.2.255", ipAddress], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"        ether %@  txqueuelen 1000  (Ethernet)", macAddr], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"./init_security_protocols --user=%@", userId], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"Generating asymmetric key pair..."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Running entropy collection for secure key generation..."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Computing SHA-256 verification hash: %@", userHash], @"delay": @0.8},
        @{@"command": [NSString stringWithFormat:@"Assigning security key: %@", securityKey], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Encrypting user credentials with AES-256..."], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Salting and hashing password..."], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"df -h | grep /dev"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"/dev/sda1       %dG   %@G   %dG  25%%  /", arc4random_uniform(200) + 100, diskSpace, arc4random_uniform(80) + 20], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"/dev/sdb1       %dG  3.2G   %dG  10%%  /mnt/secure", arc4random_uniform(50) + 10, arc4random_uniform(40) + 5], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.2},
        @{@"command": [NSString stringWithFormat:@"./connect_db --secure --operation=INSERT"], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Database connection established via TLSv1.3"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"INSERT INTO users (id, credentials, hash, security_level, created_at) VALUES ('%@', '********', '%@', 3, %@)", userId, userHash, timestamp], @"delay": @0.9},
        @{@"command": [NSString stringWithFormat:@"Query executed successfully. 1 row affected."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Committing transaction..."], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"./assign_permissions --user=%@ --level=3", userId], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Setting default access controls..."], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"Registering device: %@", [self getCurrentDeviceInfo]], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"Whitelisting IP: %@", ipAddress], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"lsb_release -a"], @"delay": @0.5},
        @{@"command": [NSString stringWithFormat:@"Distributor ID: WeaponX"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"Description:    Weapon X Security OS %@", kernelVer], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"Release:        %@", kernelVer], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"Codename:       shadowcat"], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"IDENTITY CREATION SUCCESSFUL"], @"delay": @0.7},
        @{@"command": [NSString stringWithFormat:@"USER REGISTERED - Welcome, Agent"], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@""], @"delay": @0.3},
        @{@"command": [NSString stringWithFormat:@"journalctl -n 5"], @"delay": @0.6},
        @{@"command": [NSString stringWithFormat:@"May 16 04:38:12 weaponx systemd[1]: Started User Registration Service."], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"May 16 04:38:14 weaponx kernel: [%d]: New user registered", arc4random_uniform(9000) + 1000], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"May 16 04:38:15 weaponx kernel: [%d]: Permission tables updated", arc4random_uniform(9000) + 1000], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"May 16 04:38:16 weaponx kernel: [%d]: Security policy applied", arc4random_uniform(9000) + 1000], @"delay": @0.4},
        @{@"command": [NSString stringWithFormat:@"May 16 04:38:18 weaponx systemd[1]: Stopping User Registration Service..."], @"delay": @0.4},
    ];
    
    // Fade in the overlay immediately
    [UIView animateWithDuration:0.2 animations:^{
        hackingOverlay.alpha = 1.0;
    } completion:^(BOOL finished) {
        NSLog(@"[WeaponX] Hacking overlay visible in SignupViewController, starting animation");
        
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
            NSLog(@"[WeaponX] Animation completed in SignupViewController, waiting before dismissal");
            
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

// Get current device info for display in terminal
- (NSString *)getCurrentDeviceInfo {
    UIDevice *device = [UIDevice currentDevice];
    NSString *deviceInfo = [NSString stringWithFormat:@"%@ (%@ %@)", 
                           device.name, 
                           device.model, 
                           device.systemVersion];
    return deviceInfo;
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

// Advanced method for animating terminal with more realistic command sequence
- (void)animateAdvancedTerminalWithSequence:(NSArray *)sequence
                                    inLabel:(UILabel *)label
                                 scrollView:(UIScrollView *)scrollView
                                currentText:(NSMutableString *)currentText
                               currentIndex:(NSUInteger)index
                                 completion:(void (^)(void))completion {
    
    // All lines done
    if (index >= sequence.count) {
        NSLog(@"[WeaponX] Advanced terminal sequence completed in SignupViewController");
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
            NSLog(@"[WeaponX] Finished typing command: %@", command);
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
    }];
    
    // Make sure the timer is added to the current run loop
    [[NSRunLoop currentRunLoop] addTimer:typingTimer forMode:NSRunLoopCommonModes];
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

// Method to perform API requests with retries after token reset
- (void)performAPIRequestWithURL:(NSURL *)url 
                          method:(NSString *)method 
                            body:(NSData *)body 
                         headers:(NSDictionary *)headers
                      retryCount:(int)retryCount
                      maxRetries:(int)maxRetries
                      completion:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completion {
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method ?: @"GET";
    
    if (body) {
        request.HTTPBody = body;
    }
    
    // Add headers
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }
    
    // Add cache control headers
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:[NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]] forHTTPHeaderField:@"X-Timestamp"];
    
    // Log the API request
    NSLog(@"[WeaponX] Making API request to %@ with retry count %d/%d", url.absoluteString, retryCount, maxRetries);
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        // Handle errors
        if (error) {
            NSLog(@"[WeaponX] API request error: %@", error);
            if (completion) {
                completion(data, response, error);
            }
            return;
        }
        
        // Check for 401 Unauthorized and retry if we haven't exceeded max retries
        if (httpResponse.statusCode == 401 && retryCount < maxRetries) {
            NSLog(@"[WeaponX] Received 401 Unauthorized, retry %d/%d", retryCount + 1, maxRetries);
            
            // Calculate exponential backoff delay
            NSTimeInterval delay = pow(2, retryCount) * 0.5; // 0.5s, 1s, 2s, 4s...
            
            // Log expected retry time
            NSLog(@"[WeaponX] Will retry in %.1f seconds", delay);
            
            // Wait before retrying
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Clear URL cache before retrying
                [[NSURLCache sharedURLCache] removeAllCachedResponses];
                
                // Try again with incremented retry count
                [self performAPIRequestWithURL:url 
                                        method:method 
                                          body:body 
                                       headers:headers 
                                    retryCount:retryCount + 1 
                                    maxRetries:maxRetries 
                                    completion:completion];
            });
            return;
        }
        
        // For all other responses, just call completion
        if (completion) {
            completion(data, response, error);
        }
    }];
    
    [task resume];
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
    
    return deviceName;
}

@end