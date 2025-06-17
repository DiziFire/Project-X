#import "TelegramUI.h"
#import "TelegramManager.h"

@interface TelegramUI () <UITextFieldDelegate>

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UITextField *tagTextField;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIView *editContainer;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIColor *primaryColor;
@property (nonatomic, strong) NSString *currentTelegramTag;
@property (nonatomic, strong) NSString *authToken;
@property (nonatomic, copy) void (^updateActionBlock)(NSString *newTag);
@property (nonatomic, strong) UILabel *helperLabel; // Helper label for recovery message

@end

@implementation TelegramUI

- (instancetype)initWithFrame:(CGRect)frame primaryColor:(UIColor *)primaryColor {
    self = [super initWithFrame:frame];
    if (self) {
        _primaryColor = primaryColor;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.layer.cornerRadius = 0.0; // Remove rounded corners for a more terminal-like look
    self.layer.masksToBounds = YES;
    self.backgroundColor = [UIColor clearColor]; // No background for inline style
    
    // Create title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"TELEGRAM";
    titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont boldSystemFontOfSize:14.0]; // Match other section titles
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        titleLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Bright green for dark mode
            } else {
                return [UIColor colorWithRed:0.0 green:0.6 blue:0.3 alpha:1.0]; // Darker green for light mode
            }
        }];
    } else {
        titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0]; // Default bright green
    }
    
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:titleLabel];
    self.titleLabel = titleLabel;
    
    // Create value label
    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.text = @"Not linked";
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        self.valueLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor whiteColor]; // White text for dark mode
            } else {
                return [UIColor blackColor]; // Black text for light mode
            }
        }];
    } else {
        self.valueLabel.textColor = [UIColor whiteColor];
    }
    
    self.valueLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont systemFontOfSize:14.0]; // Match other values
    self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.valueLabel];
    
    // Create helper label for recovery message
    self.helperLabel = [[UILabel alloc] init];
    self.helperLabel.text = @"Link Telegram ID for account recovery and help";
    self.helperLabel.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont systemFontOfSize:11.0]; // Smaller font
    self.helperLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.helperLabel.textAlignment = NSTextAlignmentLeft;
    self.helperLabel.numberOfLines = 1;
    
    // Dynamic color based on interface style
    if (@available(iOS 13.0, *)) {
        self.helperLabel.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:1.0]; // Light gray for dark mode
            } else {
                return [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0]; // Darker gray for light mode
            }
        }];
    } else {
        self.helperLabel.textColor = [UIColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:1.0]; // Default light gray
    }
    
    self.helperLabel.hidden = YES; // Initially hidden, will show based on telegram tag status
    [self addSubview:self.helperLabel];
    
    // Create edit button
    self.editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.editButton setTitle:@"Link" forState:UIControlStateNormal];
    [self.editButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    // Dynamic background color based on interface style
    if (@available(iOS 13.0, *)) {
        self.editButton.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0]; // Darker green for dark mode
            } else {
                return [UIColor colorWithRed:0.0 green:0.6 blue:0.0 alpha:1.0]; // Brighter green for light mode
            }
        }];
    } else {
        self.editButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0]; // Default green background
    }
    
    self.editButton.layer.cornerRadius = 4.0; // Smaller corner radius for sharper look
    self.editButton.layer.borderWidth = 1.0;
    self.editButton.layer.borderColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.0 alpha:1.0].CGColor;
    [self.editButton addTarget:self action:@selector(editButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.editButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.editButton.titleLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont systemFontOfSize:12.0]; // Smaller font
    [self addSubview:self.editButton];
    
    // Container for edit mode (initially hidden)
    self.editContainer = [[UIView alloc] init];
    self.editContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.editContainer.hidden = YES;
    self.editContainer.alpha = 0.0;
    [self addSubview:self.editContainer];
    
    // Text field for telegram tag input
    self.tagTextField = [[UITextField alloc] init];
    self.tagTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.tagTextField.placeholder = @"Your Telegram username";
    self.tagTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.tagTextField.font = [UIFont systemFontOfSize:14.0];
    self.tagTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tagTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tagTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.tagTextField.delegate = self;
    self.tagTextField.returnKeyType = UIReturnKeyDone;
    
    // Custom styling for text field
    if (@available(iOS 13.0, *)) {
        self.tagTextField.backgroundColor = [UIColor tertiarySystemBackgroundColor];
        self.tagTextField.textColor = [UIColor labelColor];
    } else {
        self.tagTextField.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
        self.tagTextField.textColor = [UIColor whiteColor];
        self.tagTextField.attributedPlaceholder = [[NSAttributedString alloc] 
                                               initWithString:@"Your Telegram username" 
                                               attributes:@{NSForegroundColorAttributeName: [UIColor lightGrayColor]}];
    }
    
    // Left view for @ symbol
    UILabel *atSymbol = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    atSymbol.text = @"@";
    atSymbol.textAlignment = NSTextAlignmentCenter;
    
    if (@available(iOS 13.0, *)) {
        atSymbol.textColor = [UIColor secondaryLabelColor];
    } else {
        atSymbol.textColor = [UIColor lightGrayColor];
    }
    
    self.tagTextField.leftView = atSymbol;
    self.tagTextField.leftViewMode = UITextFieldViewModeAlways;
    
    [self.editContainer addSubview:self.tagTextField];
    
    // Save button
    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.saveButton setTitle:@"Save" forState:UIControlStateNormal];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0]; // Green background
    self.saveButton.layer.cornerRadius = 5.0;
    self.saveButton.titleLabel.font = [UIFont systemFontOfSize:14.0];
    [self.saveButton addTarget:self action:@selector(saveButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.editContainer addSubview:self.saveButton];
    
    // Cancel button
    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.cancelButton setTitleColor:[UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0] forState:UIControlStateNormal];
    self.cancelButton.backgroundColor = [UIColor clearColor];
    self.cancelButton.layer.cornerRadius = 5.0;
    self.cancelButton.layer.borderWidth = 1.0;
    self.cancelButton.layer.borderColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.0 alpha:1.0].CGColor;
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:14.0];
    [self.cancelButton addTarget:self action:@selector(cancelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.editContainer addSubview:self.cancelButton];
    
    // Activity indicator
    if (@available(iOS 13.0, *)) {
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
#pragma clang diagnostic pop
    }
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self addSubview:self.activityIndicator];
    
    // Set up constraints for inline layout
    [NSLayoutConstraint activateConstraints:@[
        // Title label constraints - fixed width like other sections
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [titleLabel.widthAnchor constraintEqualToConstant:70.0], // Match other section title widths
        [titleLabel.heightAnchor constraintEqualToConstant:30.0],
        
        // Value label constraints - inline with title
        [self.valueLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [self.valueLabel.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:10.0],
        [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.editButton.leadingAnchor constant:-10.0],
        
        // Edit button constraints - wider button for better visibility
        [self.editButton.centerYAnchor constraintEqualToAnchor:self.valueLabel.centerYAnchor],
        [self.editButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.editButton.widthAnchor constraintEqualToConstant:70.0],
        [self.editButton.heightAnchor constraintEqualToConstant:26.0],
        
        // Edit container constraints - position it below the title/value
        [self.editContainer.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [self.editContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.editContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.editContainer.heightAnchor constraintEqualToConstant:70.0],
        
        // Text field constraints
        [self.tagTextField.topAnchor constraintEqualToAnchor:self.editContainer.topAnchor],
        [self.tagTextField.leadingAnchor constraintEqualToAnchor:self.editContainer.leadingAnchor],
        [self.tagTextField.trailingAnchor constraintEqualToAnchor:self.editContainer.trailingAnchor],
        [self.tagTextField.heightAnchor constraintEqualToConstant:30.0],
        
        // Save button constraints
        [self.saveButton.topAnchor constraintEqualToAnchor:self.tagTextField.bottomAnchor constant:8.0],
        [self.saveButton.trailingAnchor constraintEqualToAnchor:self.editContainer.trailingAnchor],
        [self.saveButton.widthAnchor constraintEqualToConstant:60.0],
        [self.saveButton.heightAnchor constraintEqualToConstant:26.0],
        
        // Cancel button constraints
        [self.cancelButton.topAnchor constraintEqualToAnchor:self.tagTextField.bottomAnchor constant:8.0],
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.saveButton.leadingAnchor constant:-8.0],
        [self.cancelButton.widthAnchor constraintEqualToConstant:60.0],
        [self.cancelButton.heightAnchor constraintEqualToConstant:26.0],
        
        // Activity indicator constraints
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.valueLabel.centerYAnchor],
        [self.activityIndicator.trailingAnchor constraintEqualToAnchor:self.editButton.leadingAnchor constant:-8.0],
        
        // Helper label constraints
        [self.helperLabel.topAnchor constraintEqualToAnchor:self.valueLabel.bottomAnchor constant:2.0],
        [self.helperLabel.leadingAnchor constraintEqualToAnchor:self.valueLabel.leadingAnchor],
        [self.helperLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0]
    ]];
}

- (void)setupConstraints {
    // Title label constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.titleLabel.heightAnchor constraintEqualToConstant:20]
    ]];
    
    // Value label constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.valueLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.valueLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.valueLabel.trailingAnchor constraintEqualToAnchor:self.editButton.leadingAnchor constant:-8]
    ]];
    
    // Edit button constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.editButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.editButton.centerYAnchor constraintEqualToAnchor:self.valueLabel.centerYAnchor],
        [self.editButton.widthAnchor constraintEqualToConstant:70],
        [self.editButton.heightAnchor constraintEqualToConstant:30]
    ]];
    
    // Edit container constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.editContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.editContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.editContainer.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.editContainer.heightAnchor constraintEqualToConstant:70]
    ]];
    
    // Text field constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.tagTextField.leadingAnchor constraintEqualToAnchor:self.editContainer.leadingAnchor],
        [self.tagTextField.trailingAnchor constraintEqualToAnchor:self.editContainer.trailingAnchor],
        [self.tagTextField.topAnchor constraintEqualToAnchor:self.editContainer.topAnchor],
        [self.tagTextField.heightAnchor constraintEqualToConstant:30]
    ]];
    
    // Button container for save and cancel
    [NSLayoutConstraint activateConstraints:@[
        [self.saveButton.topAnchor constraintEqualToAnchor:self.tagTextField.bottomAnchor constant:8],
        [self.saveButton.trailingAnchor constraintEqualToAnchor:self.editContainer.trailingAnchor],
        [self.saveButton.widthAnchor constraintEqualToConstant:60],
        [self.saveButton.heightAnchor constraintEqualToConstant:30],
        
        [self.cancelButton.topAnchor constraintEqualToAnchor:self.tagTextField.bottomAnchor constant:8],
        [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.saveButton.leadingAnchor constant:-8],
        [self.cancelButton.widthAnchor constraintEqualToConstant:60],
        [self.cancelButton.heightAnchor constraintEqualToConstant:30]
    ]];
    
    // Activity indicator constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.valueLabel.centerYAnchor],
        [self.activityIndicator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor]
    ]];
}

#pragma mark - Public Methods

- (void)updateWithTelegramTag:(NSString *)telegramTag {
    self.currentTelegramTag = telegramTag;
    
    // Stop any ongoing activity indicator and restore edit button
    [self.activityIndicator stopAnimating];
    [self.editButton setHidden:NO];
    
    if (telegramTag && ![telegramTag isEqual:@""] && telegramTag.length > 0) {
        // Show telegram tag with @ symbol
        NSString *displayTag = telegramTag;
        
        // Add @ if it doesn't already have one
        if (![displayTag hasPrefix:@"@"]) {
            displayTag = [@"@" stringByAppendingString:displayTag];
        }
        
        self.valueLabel.text = displayTag;
        [self.editButton setTitle:@"Edit" forState:UIControlStateNormal];
        
        // Hide helper label when Telegram is linked
        self.helperLabel.hidden = YES;
    } else {
        self.valueLabel.text = @"Not linked";
        [self.editButton setTitle:@"Link" forState:UIControlStateNormal];
        
        // Show helper label when Telegram is not linked
        self.helperLabel.hidden = NO;
    }
    
    // Ensure edit mode is not showing
    [self toggleEditMode:NO];
}

- (void)setUpdateActionBlock:(void (^)(NSString *))actionBlock {
    _updateActionBlock = actionBlock;
}

- (void)setAuthToken:(NSString *)token {
    _authToken = token;
}

#pragma mark - Button Actions

- (void)editButtonTapped {
    [self toggleEditMode:YES];
    
    // Pre-fill the text field with current tag (without @ symbol)
    if (self.currentTelegramTag && self.currentTelegramTag.length > 0) {
        NSString *tagWithoutAt = self.currentTelegramTag;
        if ([tagWithoutAt hasPrefix:@"@"]) {
            tagWithoutAt = [tagWithoutAt substringFromIndex:1];
        }
        self.tagTextField.text = tagWithoutAt;
    } else {
        self.tagTextField.text = @"";
    }
    
    // Focus the text field
    [self.tagTextField becomeFirstResponder];
}

- (void)saveButtonTapped {
    [self.tagTextField resignFirstResponder];
    
    NSString *tagText = self.tagTextField.text;
    
    // Validate the input
    if (tagText.length > 0 && ![[TelegramManager sharedManager] isValidTelegramTag:tagText]) {
        // Show validation error
        [self showAlert:@"Invalid Telegram Username" 
                message:@"Username must be 5-32 characters and can only contain letters, numbers, and underscores."];
        return;
    }
    
    // Show loading indicator
    [self.editButton setHidden:YES];
    [self.activityIndicator startAnimating];
    
    // Call the update action block
    if (self.updateActionBlock) {
        self.updateActionBlock(tagText);
    }
    
    // Hide the edit mode
    [self toggleEditMode:NO];
}

- (void)cancelButtonTapped {
    [self.tagTextField resignFirstResponder];
    [self toggleEditMode:NO];
}

#pragma mark - Private Methods

- (void)toggleEditMode:(BOOL)showEdit {
    // Set the text field value to current tag first
    self.tagTextField.text = self.currentTelegramTag;
    
    // Ensure edit container is visible before animation
    if (showEdit) {
        self.editContainer.hidden = NO;
    }
    
    // Set up animations
    [UIView animateWithDuration:0.3 animations:^{
        if (showEdit) {
            // Show edit mode
            self.editContainer.alpha = 1.0;
            self.editButton.alpha = 0.0;
            
            // Adjust self height to accommodate the edit container
            for (NSLayoutConstraint *constraint in self.constraints) {
                if (constraint.firstAttribute == NSLayoutAttributeHeight) {
                    constraint.constant = 100.0;  // Increased height to show edit container
                    break;
                }
            }
            
            [self layoutIfNeeded];
            
        } else {
            // Hide edit mode
            self.editContainer.alpha = 0.0;
            self.editButton.alpha = 1.0;
            
            // Reset height
            for (NSLayoutConstraint *constraint in self.constraints) {
                if (constraint.firstAttribute == NSLayoutAttributeHeight) {
                    constraint.constant = 30.0;  // Original height
                    break;
                }
            }
            
            [self layoutIfNeeded];
        }
    } completion:^(BOOL finished) {
        if (!showEdit) {
            self.editContainer.hidden = YES;
        }
        
        // Notify superview about height change
        if ([self.superview isKindOfClass:[UIView class]]) {
            [self.superview layoutIfNeeded];
        }
    }];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    
    [alert addAction:okAction];
    
    // Find the view controller to present from
    UIViewController *topController = nil;
    
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        topController = window.rootViewController;
                        break;
                    }
                }
                if (topController) break;
            }
        }
        // Fallback if no key window found
        if (!topController) {
            UIWindowScene *windowScene = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.anyObject;
            if (windowScene.windows.count > 0) {
                topController = windowScene.windows.firstObject.rootViewController;
            }
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        topController = [UIApplication sharedApplication].keyWindow.rootViewController;
#pragma clang diagnostic pop
    }
    
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    [topController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.tagTextField) {
        [self saveButtonTapped];
        return YES;
    }
    return NO;
}

@end 