#import "DeviceSpecificSpoofingViewController.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "IdentifierManager.h"
#import "DeviceModelManager.h"
#import "ProfileIndicatorView.h"
#import "ProfileManager.h"
#import "ProfileButtonsView.h"
#import "ProfileManagerViewController.h"
#import "DeviceSpecificSpoofingViewController+EditLabel.h"

@interface DeviceSpecificSpoofingViewController ()
@property (nonatomic, strong) UIView *profileIndicatorView;
@property (nonatomic, strong) UILabel *profileLabel; // Track the label for updates
@property (nonatomic, strong) UIView *imeiCard;
@property (nonatomic, strong) UIView *meidCard;
@property (nonatomic, strong) UIView *deviceModelCard;
@property (nonatomic, strong) UIView *deviceThemeCard; // New property for Device Theme card
@property (nonatomic, strong) ProfileButtonsView *profileButtonsView;
// Properties for advanced identifiers functionality
@property (nonatomic, assign) BOOL showAdvancedIdentifiers;
@property (nonatomic, strong) UIButton *showAdvancedButton;
@property (nonatomic, strong) NSMutableArray *advancedIdentifierCards;
@property (nonatomic, strong) UIStackView *mainStackView;
@end

@implementation DeviceSpecificSpoofingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Device Specific Spoofing";

    // Remove placeholder label if present
    for (UIView *subview in self.view.subviews) {
        [subview removeFromSuperview];
    }

    // Initialize advanced identifiers array
    self.advancedIdentifierCards = [NSMutableArray array];
    self.showAdvancedIdentifiers = NO;

    // Add vertical profile indicator bar (left side)
    [self setupProfileIndicator];
    // Profile indicator is now pinned to the left edge, not inside the stack view.

    // Add profile buttons view (right side, vertically centered)
    self.profileButtonsView = [[ProfileButtonsView alloc] initWithFrame:CGRectZero];
    self.profileButtonsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileButtonsView.layer.zPosition = 1000; // Ensure overlay is above cards
    self.profileButtonsView.clipsToBounds = NO;
    self.profileButtonsView.userInteractionEnabled = YES;
    // Optional: add a subtle background for visibility
    // self.profileButtonsView.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.2];
    [self.view addSubview:self.profileButtonsView];
    __weak typeof(self) weakSelf = self;
    self.profileButtonsView.onNewProfileTapped = ^{
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Create New Profile"
                                                                                 message:nil
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Profile Name";
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Short Description (optional)";
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        NSString *sampleProfileID = [[ProfileManager sharedManager] generateProfileID];
        alertController.message = [NSString stringWithFormat:@"NEW Profile ID: %@", sampleProfileID];
        UIAlertAction *createAction = [UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *profileName = alertController.textFields.firstObject.text;
            NSString *profileDesc = alertController.textFields.count > 1 ? alertController.textFields[1].text : @"";
            if (profileName.length > 0) {
                // Use the convenience method to add a profile (does not set custom profileId)
                [[ProfileManager sharedManager] addProfileWithName:profileName shortDescription:profileDesc];

                // Generate IMEI/MEID if missing for the new profile
                IdentifierManager *manager = [IdentifierManager sharedManager];
                if (![manager currentValueForIdentifier:@"IMEI"]) {
                    NSString *imei = [manager generateIMEI];
                    if (imei) [manager setCustomIMEI:imei];
                }
                if (![manager currentValueForIdentifier:@"MEID"]) {
                    NSString *meid = [manager generateMEID];
                    if (meid) [manager setCustomMEID:meid];
                }

                // Generate Device Model if missing for the new profile
                if (![manager currentValueForIdentifier:@"DeviceModel"]) {
                    NSString *deviceModel = [manager generateDeviceModel];
                    if (deviceModel) {
                        [manager setCustomDeviceModel:deviceModel];
                        NSLog(@"[DeviceSpecificSpoofingVC] Generated device model for new profile: %@", deviceModel);
                    }
                }
                
                // Generate Device Theme if missing for the new profile
                if (![manager currentValueForIdentifier:@"DeviceTheme"]) {
                    NSString *deviceTheme = [manager generateDeviceTheme];
                    if (deviceTheme) {
                        [manager setCustomDeviceTheme:deviceTheme];
                        NSLog(@"[DeviceSpecificSpoofingVC] Generated device theme for new profile: %@", deviceTheme);
                    }
                }
                
                [weakSelf refreshProfileUI]; // Immediately update UI after new profile and identifier generation

            }
        }];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        [alertController addAction:createAction];
        [alertController addAction:cancelAction];
        [weakSelf presentViewController:alertController animated:YES completion:nil];
    };
    self.profileButtonsView.onManageProfilesTapped = ^{
        ProfileManagerViewController *profileVC = [[ProfileManagerViewController alloc] initWithProfiles:nil];
        profileVC.delegate = (id<ProfileManagerViewControllerDelegate>)weakSelf;
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:profileVC];
        navController.modalPresentationStyle = UIModalPresentationPageSheet;
        [weakSelf presentViewController:navController animated:YES completion:nil];
    };



    // --- SCROLLABLE LAYOUT ---
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    // Create main stack view for all identifiers
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.spacing = 24;
    self.mainStackView.alignment = UIStackViewAlignmentFill;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:self.mainStackView];

    // Device Model Card (always shown)
    self.deviceModelCard = [self createIdentifierCardWithTitle:@"Device Model" key:@"DeviceModel"];
    [self.mainStackView addArrangedSubview:self.deviceModelCard];

    // Add Device Theme Card (visible by default)
    self.deviceThemeCard = [self createIdentifierCardWithTitle:@"Device Theme" key:@"DeviceTheme"];
    [self.mainStackView addArrangedSubview:self.deviceThemeCard];

    // Add "Show Advanced" button
    [self addShowAdvancedButton];

    // Add MEID card (advanced/hidden by default)
    self.meidCard = [self createIdentifierCardWithTitle:@"MEID" key:@"MEID"];
    [self.advancedIdentifierCards addObject:self.meidCard];
    self.meidCard.hidden = YES;
    [self.mainStackView addArrangedSubview:self.meidCard];

    // Add IMEI card (advanced/hidden by default)
    self.imeiCard = [self createIdentifierCardWithTitle:@"IMEI" key:@"IMEI"];
    [self.advancedIdentifierCards addObject:self.imeiCard];
    self.imeiCard.hidden = YES;
    [self.mainStackView addArrangedSubview:self.imeiCard];

    // Layout scrollView and stackView
    // The profile indicator bar is 30pt wide, so offset the scrollView by 30pt left margin
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.mainStackView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:32],
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor constant:16],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor constant:-16],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [self.mainStackView.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-32],
    ]];

    // Overlay profileButtonsView on the right edge, vertically centered, always visible (not inside scroll view or stack)
    [self.view addSubview:self.profileButtonsView];
    [NSLayoutConstraint activateConstraints:@[
        [self.profileButtonsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:11],
        [self.profileButtonsView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.profileButtonsView.widthAnchor constraintEqualToConstant:60],
        [self.profileButtonsView.heightAnchor constraintEqualToConstant:136],
    ]];
}

// Method to add the "Show Advanced" button
- (void)addShowAdvancedButton {
    // Create a container for the button with padding
    UIView *buttonContainer = [[UIView alloc] init];
    buttonContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainStackView addArrangedSubview:buttonContainer];
    
    // Create the "Show Advanced" button
    self.showAdvancedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.showAdvancedButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Configure button with modern appearance
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        config.baseBackgroundColor = [UIColor systemBlueColor];
        config.baseForegroundColor = [UIColor whiteColor];
        config.title = @"Show Advanced Identifiers";
        config.image = [UIImage systemImageNamed:@"chevron.down"];
        config.imagePlacement = NSDirectionalRectEdgeTrailing;
        config.imagePadding = 8;
        config.contentInsets = NSDirectionalEdgeInsetsMake(8, 16, 8, 16);
        self.showAdvancedButton.configuration = config;
    } else {
        // Fallback for older iOS versions
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Create a basic button for iOS 14 and below
        [self.showAdvancedButton setTitle:@"Show Advanced Identifiers" forState:UIControlStateNormal];
        [self.showAdvancedButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.showAdvancedButton.backgroundColor = [UIColor systemBlueColor];
        self.showAdvancedButton.layer.cornerRadius = 10;
        
        // Use contentEdgeInsets with diagnostic suppression
        self.showAdvancedButton.contentEdgeInsets = UIEdgeInsetsMake(8, 16, 8, 16);
#pragma clang diagnostic pop
        
        // Add chevron icon manually for older iOS
        UIImageView *chevronIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
        chevronIcon.tintColor = [UIColor whiteColor];
        chevronIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [self.showAdvancedButton addSubview:chevronIcon];
        
        [NSLayoutConstraint activateConstraints:@[
            [chevronIcon.trailingAnchor constraintEqualToAnchor:self.showAdvancedButton.trailingAnchor constant:-8],
            [chevronIcon.centerYAnchor constraintEqualToAnchor:self.showAdvancedButton.centerYAnchor],
            [chevronIcon.widthAnchor constraintEqualToConstant:12],
            [chevronIcon.heightAnchor constraintEqualToConstant:12]
        ]];
    }
    
    [self.showAdvancedButton addTarget:self action:@selector(toggleAdvancedIdentifiers:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:self.showAdvancedButton];
    
    // Center the button in its container
    [NSLayoutConstraint activateConstraints:@[
        [self.showAdvancedButton.centerXAnchor constraintEqualToAnchor:buttonContainer.centerXAnchor],
        [self.showAdvancedButton.topAnchor constraintEqualToAnchor:buttonContainer.topAnchor constant:8],
        [self.showAdvancedButton.bottomAnchor constraintEqualToAnchor:buttonContainer.bottomAnchor constant:-8],
        [self.showAdvancedButton.widthAnchor constraintLessThanOrEqualToAnchor:buttonContainer.widthAnchor constant:-32]
    ]];
    
    // Add some spacing after the button
    [self.mainStackView setCustomSpacing:16 afterView:buttonContainer];
}

// Method to toggle advanced identifiers visibility
- (void)toggleAdvancedIdentifiers:(UIButton *)sender {
    // Toggle the state
    self.showAdvancedIdentifiers = !self.showAdvancedIdentifiers;
    
    // Update button appearance
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = self.showAdvancedButton.configuration;
        if (self.showAdvancedIdentifiers) {
            config.title = @"Hide Advanced Identifiers";
            config.image = [UIImage systemImageNamed:@"chevron.up"];
        } else {
            config.title = @"Show Advanced Identifiers";
            config.image = [UIImage systemImageNamed:@"chevron.down"];
        }
        self.showAdvancedButton.configuration = config;
    } else {
        // Update for older iOS versions
        if (self.showAdvancedIdentifiers) {
            [self.showAdvancedButton setTitle:@"Hide Advanced Identifiers" forState:UIControlStateNormal];
            
            // Update chevron icon
            for (UIView *subview in self.showAdvancedButton.subviews) {
                if ([subview isKindOfClass:[UIImageView class]]) {
                    UIImageView *imageView = (UIImageView *)subview;
                    imageView.image = [UIImage systemImageNamed:@"chevron.up"];
                    break;
                }
            }
        } else {
            [self.showAdvancedButton setTitle:@"Show Advanced Identifiers" forState:UIControlStateNormal];
            
            // Update chevron icon
            for (UIView *subview in self.showAdvancedButton.subviews) {
                if ([subview isKindOfClass:[UIImageView class]]) {
                    UIImageView *imageView = (UIImageView *)subview;
                    imageView.image = [UIImage systemImageNamed:@"chevron.down"];
                    break;
                }
            }
        }
    }
    
    // Toggle visibility of advanced identifiers with animation
    if (self.showAdvancedIdentifiers) {
        // Show the advanced identifier views with a sequential animation
        [UIView animateWithDuration:0.3 animations:^{
            for (NSInteger i = 0; i < self.advancedIdentifierCards.count; i++) {
                UIView *card = self.advancedIdentifierCards[i];
                card.hidden = NO;
                card.alpha = 0;
                
                // Add a slight delay between each view appearing
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.3 animations:^{
                        card.alpha = 1.0;
                    }];
                });
            }
        }];
        
        // Scroll to show the first advanced identifier
        if (self.advancedIdentifierCards.count > 0) {
            UIView *firstCard = self.advancedIdentifierCards.firstObject;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                CGRect frame = [firstCard convertRect:firstCard.bounds toView:self.view];
                UIScrollView *scrollView = nil;
                for (UIView *view in self.view.subviews) {
                    if ([view isKindOfClass:[UIScrollView class]]) {
                        scrollView = (UIScrollView *)view;
                        break;
                    }
                }
                if (scrollView) {
                    [scrollView scrollRectToVisible:frame animated:YES];
                }
            });
        }
    } else {
        // Hide the advanced identifier views
        [UIView animateWithDuration:0.2 animations:^{
            for (UIView *card in self.advancedIdentifierCards) {
                card.alpha = 0;
            }
        } completion:^(BOOL finished) {
            for (UIView *card in self.advancedIdentifierCards) {
                card.hidden = YES;
            }
        }];
    }
}

- (void)setupProfileIndicator {
    if (self.profileIndicatorView) {
        [self.profileIndicatorView removeFromSuperview];
    }
    self.profileIndicatorView = [[UIView alloc] init];
    self.profileIndicatorView.backgroundColor = [UIColor clearColor];
    self.profileIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.profileIndicatorView];

    // Add rotated label for profile number
    self.profileLabel = [[UILabel alloc] init];
    self.profileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileLabel.textColor = [UIColor systemBlueColor];
    self.profileLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    self.profileLabel.textAlignment = NSTextAlignmentCenter;
    self.profileLabel.numberOfLines = 0;

    // Get current profile ID
    NSString *profileId = @"?";
    NSDictionary *profileInfo = nil;
    NSString *centralProfileInfoPath = [[ProfileManager sharedManager] centralProfileInfoPath];
    if (centralProfileInfoPath) {
        profileInfo = [NSDictionary dictionaryWithContentsOfFile:centralProfileInfoPath];
        if (profileInfo && profileInfo[@"ProfileId"]) {
            profileId = profileInfo[@"ProfileId"];
        }
    }
    self.profileLabel.text = [NSString stringWithFormat:@"\u2190------------------ Profile Num: %@ -----------------\u2192", profileId];
    self.profileLabel.transform = CGAffineTransformMakeRotation(-M_PI_2);
    [self.profileIndicatorView addSubview:self.profileLabel];

    // Pin the indicator to the left edge, vertically centered
    [NSLayoutConstraint activateConstraints:@[
        [self.profileIndicatorView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:-8],
        [self.profileIndicatorView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.profileIndicatorView.widthAnchor constraintEqualToConstant:30],
        [self.profileIndicatorView.heightAnchor constraintEqualToConstant:260],
        [self.profileLabel.centerXAnchor constraintEqualToAnchor:self.profileIndicatorView.centerXAnchor],
        [self.profileLabel.centerYAnchor constraintEqualToAnchor:self.profileIndicatorView.centerYAnchor],
        [self.profileLabel.widthAnchor constraintLessThanOrEqualToConstant:UIScreen.mainScreen.bounds.size.height - 48]
    ]];
}


- (UIView *)createIdentifierCardWithTitle:(NSString *)title key:(NSString *)key {
    // For Device Model, show both the model name and string if key is DeviceModel

    // --- GLASSMORPHISM CARD CONTAINER ---
    UIView *containerView = [[UIView alloc] init];
    containerView.backgroundColor = [UIColor clearColor];
    containerView.layer.cornerRadius = 20;
    containerView.clipsToBounds = YES;
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.layer.borderWidth = 0.5;
    containerView.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.2].CGColor;
    containerView.layer.shadowColor = [UIColor blackColor].CGColor;
    containerView.layer.shadowOffset = CGSizeMake(0, 4);
    containerView.layer.shadowRadius = 8;
    containerView.layer.shadowOpacity = 0.1;

    // Blur effect
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:blurView];
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];

    // Vibrancy effect for content
    UIVibrancyEffect *vibrancyEffect = [UIVibrancyEffect effectForBlurEffect:blurEffect];
    UIVisualEffectView *vibrancyView = [[UIVisualEffectView alloc] initWithEffect:vibrancyEffect];
    vibrancyView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:vibrancyView];
    [NSLayoutConstraint activateConstraints:@[
        [vibrancyView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [vibrancyView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [vibrancyView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [vibrancyView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];

    // Create vertical stack for identifier and controls (OUTSIDE blur/vibrancy)
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 10;
    contentStack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
    contentStack.layoutMarginsRelativeArrangement = YES;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:contentStack];

    // Setup content stack constraints
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];

    // NOTE: Do NOT add controlsStack or switchStatusStack to a vibrancyView or blurView!
    // They must be added to contentStack directly for proper UISwitch color rendering.

    // Determine enabled state for coloring and toggle
    BOOL isEnabled = [[IdentifierManager sharedManager] isIdentifierEnabled:key];
    // Create identifier container with background
    UIView *identifierContainer = [[UIView alloc] init];
    identifierContainer.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.1];
    identifierContainer.layer.cornerRadius = 12;
    identifierContainer.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [UIColor labelColor];
    // Inline pencil icon (like ProjectXViewController)
    if (@available(iOS 15.0, *)) {
        UIImage *pencilImg = [[UIImage systemImageNamed:@"pencil"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        NSTextAttachment *iconAttachment = [[NSTextAttachment alloc] init];
        iconAttachment.image = pencilImg;
        CGFloat iconSize = 16;
        iconAttachment.bounds = CGRectMake(0, -2, iconSize, iconSize);
        NSAttributedString *space = [[NSAttributedString alloc] initWithString:@"  "];
        NSAttributedString *titleString = [[NSAttributedString alloc] initWithString:title attributes:@{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:16],
            NSForegroundColorAttributeName: [UIColor labelColor]
        }];
        NSMutableAttributedString *full = [[NSMutableAttributedString alloc] initWithAttributedString:titleString];
        [full appendAttributedString:space];
        [full appendAttributedString:[NSAttributedString attributedStringWithAttachment:iconAttachment]];
        titleLabel.attributedText = full;
        titleLabel.tintColor = [UIColor systemGrayColor];
        // Tap gesture for editing
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(editIdentifierLabelTapped:)];
        titleLabel.userInteractionEnabled = YES;
        [titleLabel addGestureRecognizer:tap];
        objc_setAssociatedObject(tap, "identifierKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        titleLabel.text = [NSString stringWithFormat:@"%@ ✏️", title];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(editIdentifierLabelTapped:)];
        titleLabel.userInteractionEnabled = YES;
        [titleLabel addGestureRecognizer:tap];
        objc_setAssociatedObject(tap, "identifierKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *copyConfig = [UIButtonConfiguration plainButtonConfiguration];
        copyConfig.image = [UIImage systemImageNamed:@"doc.on.doc"];
        copyConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        copyConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
        copyConfig.baseForegroundColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
        copyConfig.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
        copyButton.configuration = copyConfig;
    } else {
        [copyButton setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
        copyButton.tintColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    }
    copyButton.accessibilityLabel = [NSString stringWithFormat:@"Copy %@", title];
    [copyButton addTarget:self action:@selector(copyIdentifierValue:) forControlEvents:UIControlEventTouchUpInside];
    // Assign proper tags to match the identifier type
    if ([key isEqualToString:@"IMEI"]) copyButton.tag = 1;
    else if ([key isEqualToString:@"MEID"]) copyButton.tag = 2;
    else if ([key isEqualToString:@"DeviceModel"]) copyButton.tag = 3;
    else if ([key isEqualToString:@"DeviceTheme"]) copyButton.tag = 4;
    
    // Add info button for Device Model only
    UIButton *infoButton = nil;
    if ([key isEqualToString:@"DeviceModel"]) {
        infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *infoConfig = [UIButtonConfiguration plainButtonConfiguration];
            infoConfig.image = [UIImage systemImageNamed:@"info.circle"];
            infoConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
            infoConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
            infoConfig.baseForegroundColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
            infoConfig.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
            infoButton.configuration = infoConfig;
        } else {
            [infoButton setImage:[UIImage systemImageNamed:@"info.circle"] forState:UIControlStateNormal];
            infoButton.tintColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
        }
        infoButton.accessibilityLabel = @"Device Specifications";
        infoButton.tag = 3; // Match device model tag
        [infoButton addTarget:self action:@selector(showDeviceSpecsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    }

    UIStackView *headerStack = [[UIStackView alloc] init];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.alignment = UIStackViewAlignmentCenter;
    headerStack.distribution = UIStackViewDistributionFill;
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [headerStack setCustomSpacing:12 afterView:titleLabel];
    
    // Add buttons to header stack
    [headerStack addArrangedSubview:titleLabel];
    if (infoButton) {
        [headerStack addArrangedSubview:infoButton];
    }
    [headerStack addArrangedSubview:copyButton];
    
    [contentStack addArrangedSubview:headerStack];

    // --- IDENTIFIER VALUE ---
    // (identifierContainer already declared above, just use it here)

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightRegular];
    valueLabel.textColor = [UIColor labelColor];
    valueLabel.numberOfLines = 1;
    valueLabel.adjustsFontSizeToFitWidth = YES;
    valueLabel.minimumScaleFactor = 0.7;
    
    // Special handling for DeviceModel to show the correct format
    if ([key isEqualToString:@"DeviceModel"]) {
        NSString *deviceModel = [[IdentifierManager sharedManager] currentValueForIdentifier:key];
        valueLabel.text = deviceModel ?: @"Not Set";
    } else {
    valueLabel.text = [[IdentifierManager sharedManager] currentValueForIdentifier:key] ?: @"Not Set";
    }
    
    valueLabel.textAlignment = NSTextAlignmentCenter;
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.tag = 100;
    [identifierContainer addSubview:valueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [valueLabel.topAnchor constraintEqualToAnchor:identifierContainer.topAnchor constant:12],
        [valueLabel.leadingAnchor constraintEqualToAnchor:identifierContainer.leadingAnchor constant:12],
        [valueLabel.trailingAnchor constraintEqualToAnchor:identifierContainer.trailingAnchor constant:-12],
        [valueLabel.bottomAnchor constraintEqualToAnchor:identifierContainer.bottomAnchor constant:-12]
    ]];
    [contentStack addArrangedSubview:identifierContainer];

    // --- CONTROLS STACK ---
    UIStackView *controlsStack = [[UIStackView alloc] init];
    controlsStack.axis = UILayoutConstraintAxisHorizontal;
    controlsStack.distribution = UIStackViewDistributionEqualSpacing;
    controlsStack.alignment = UIStackViewAlignmentCenter;
    controlsStack.spacing = 10;
    controlsStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Switch + Status
    UIStackView *switchStatusStack = [[UIStackView alloc] init];
    switchStatusStack.axis = UILayoutConstraintAxisHorizontal;
    switchStatusStack.spacing = 8;
    switchStatusStack.alignment = UIStackViewAlignmentCenter;

    UILabel *stateLabel = [[UILabel alloc] init];
    stateLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    stateLabel.textColor = isEnabled ? [UIColor systemBlueColor] : [UIColor labelColor];
    stateLabel.text = isEnabled ? @"Enabled" : @"Disabled";
    stateLabel.tag = 100;

    UISwitch *enabledSwitch = [[UISwitch alloc] init];
    enabledSwitch.on = isEnabled;
    enabledSwitch.onTintColor = [UIColor systemBlueColor];
    [enabledSwitch addTarget:self action:@selector(identifierSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    // Assign unique tags: 1=IMEI, 2=MEID, 3=DeviceModel, 4=DeviceTheme
    if ([key isEqualToString:@"IMEI"]) enabledSwitch.tag = 1;
    else if ([key isEqualToString:@"MEID"]) enabledSwitch.tag = 2;
    else if ([key isEqualToString:@"DeviceModel"]) enabledSwitch.tag = 3;
    else if ([key isEqualToString:@"DeviceTheme"]) enabledSwitch.tag = 4;

    [switchStatusStack addArrangedSubview:stateLabel];
    [switchStatusStack addArrangedSubview:enabledSwitch];
    // Set color after adding to view hierarchy
    enabledSwitch.onTintColor = [UIColor systemBlueColor];
    enabledSwitch.tintColor = [UIColor systemBlueColor]; // fallback for some iOS versions
    NSLog(@"%@ switch state: %d, onTintColor: %@", key, enabledSwitch.on, enabledSwitch.onTintColor);
    [enabledSwitch setNeedsDisplay];
    [enabledSwitch setNeedsLayout];

    // Generate button
    UIButton *generateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *generateConfig = [UIButtonConfiguration plainButtonConfiguration];
        generateConfig.image = [UIImage systemImageNamed:@"arrow.clockwise"];
        generateConfig.title = @"Generate";
        generateConfig.imagePlacement = NSDirectionalRectEdgeLeading;
        generateConfig.imagePadding = 4;
        generateConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        generateConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.15];
        generateConfig.baseForegroundColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
        generateConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 6, 4, 6);
        generateButton.configuration = generateConfig;
        generateButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        generateButton.layer.cornerRadius = 10;
        generateButton.clipsToBounds = YES;
    } else {
        [generateButton setTitle:@"Generate" forState:UIControlStateNormal];
        [generateButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
        generateButton.tintColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
        generateButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    }
    // Assign unique tags: 1=IMEI, 2=MEID, 3=DeviceModel, 4=DeviceTheme
    if ([key isEqualToString:@"IMEI"]) generateButton.tag = 1;
    else if ([key isEqualToString:@"MEID"]) generateButton.tag = 2;
    else if ([key isEqualToString:@"DeviceModel"]) generateButton.tag = 3;
    else if ([key isEqualToString:@"DeviceTheme"]) generateButton.tag = 4;
    [generateButton addTarget:self action:@selector(generateIdentifier:) forControlEvents:UIControlEventTouchUpInside];
    generateButton.accessibilityLabel = [NSString stringWithFormat:@"Generate %@", title];

    // Add controls to controlsStack
    [controlsStack addArrangedSubview:copyButton];
    [controlsStack addArrangedSubview:switchStatusStack];
    [controlsStack addArrangedSubview:generateButton];
    [contentStack addArrangedSubview:controlsStack];

    // Tag for IMEI/MEID
    if ([key isEqualToString:@"IMEI"]) containerView.tag = 200;
    if ([key isEqualToString:@"MEID"]) containerView.tag = 201;

    // --- WIDTH: Match ProjectXViewController ---
    // Do NOT set a fixed width. Let the card stretch to fill the parent stack view.
    // Set hugging/compression priorities to allow stretching.
    [containerView setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [containerView setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    // IMPORTANT: Ensure the parent stack view (where you add these cards) is constrained to the safe area with 16pt leading/trailing margins and alignment = UIStackViewAlignmentFill.

    return containerView;
}

// Helper to map device string to user-friendly name
- (NSString *)deviceModelNameForString:(NSString *)deviceString {
    NSDictionary *deviceMap = @{
        @"iPhone8,1": @"iPhone 6s",
        @"iPhone8,2": @"iPhone 6s Plus",
        @"iPhone8,4": @"iPhone SE (1st Gen)",
        @"iPhone9,1": @"iPhone 7",
        @"iPhone9,2": @"iPhone 7 Plus",
        @"iPhone10,1": @"iPhone 8",
        @"iPhone10,2": @"iPhone 8 Plus",
        @"iPhone10,3": @"iPhone X",
        @"iPhone11,8": @"iPhone XR",
        @"iPhone11,2": @"iPhone XS",
        @"iPhone11,6": @"iPhone XS Max",
        @"iPhone12,1": @"iPhone 11",
        @"iPhone12,3": @"iPhone 11 Pro",
        @"iPhone12,5": @"iPhone 11 Pro Max",
        @"iPhone12,8": @"iPhone SE (2nd Gen)",
        @"iPhone13,1": @"iPhone 12 mini",
        @"iPhone13,2": @"iPhone 12",
        @"iPhone13,3": @"iPhone 12 Pro",
        @"iPhone13,4": @"iPhone 12 Pro Max",
        @"iPhone14,4": @"iPhone 13 mini",
        @"iPhone14,5": @"iPhone 13",
        @"iPhone14,2": @"iPhone 13 Pro",
        @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,6": @"iPhone SE (3rd Gen)",
        @"iPhone14,7": @"iPhone 14",
        @"iPhone14,8": @"iPhone 14 Plus",
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        @"iPhone16,1": @"iPhone 15 Pro",
        @"iPhone16,2": @"iPhone 15 Pro Max",
        @"iPhone16,3": @"iPhone 16",
        @"iPhone16,4": @"iPhone 16 Plus",
        @"iPhone16,5": @"iPhone 16 Pro",
        @"iPhone16,6": @"iPhone 16 Pro Max",
        @"iPad7,5": @"iPad (6th Gen)",
        @"iPad7,11": @"iPad (7th Gen)",
        @"iPad11,6": @"iPad (8th Gen)",
        @"iPad12,1": @"iPad (9th Gen)",
        @"iPad13,18": @"iPad (10th Gen)",
        @"iPad11,3": @"iPad Air (3rd Gen)",
        @"iPad13,1": @"iPad Air (4th Gen)",
        @"iPad13,16": @"iPad Air (5th Gen)",
        @"iPad8,1": @"iPad Pro 11\" (1st Gen)",
        @"iPad8,9": @"iPad Pro 11\" (2nd Gen)",
        @"iPad13,4": @"iPad Pro 11\" (3rd Gen)",
        @"iPad14,3": @"iPad Pro 11\" (4th Gen)",
        @"iPad8,5": @"iPad Pro 12.9\" (3rd Gen)",
        @"iPad8,11": @"iPad Pro 12.9\" (4th Gen)",
        @"iPad13,8": @"iPad Pro 12.9\" (5th Gen)",
        @"iPad14,5": @"iPad Pro 12.9\" (6th Gen)",
        @"iPad11,1": @"iPad Mini (5th Gen)",
        @"iPad14,1": @"iPad Mini (6th Gen)"
    };
    return deviceMap[deviceString];
}


// MARK: - Profile/Identifier UI Refresh
- (void)refreshProfileUI {
    // Update profile label
    NSString *profileId = @"?";
    NSDictionary *profileInfo = nil;
    NSString *centralProfileInfoPath = [[ProfileManager sharedManager] centralProfileInfoPath];
    if (centralProfileInfoPath) {
        profileInfo = [NSDictionary dictionaryWithContentsOfFile:centralProfileInfoPath];
        if (profileInfo && profileInfo[@"ProfileId"]) {
            profileId = profileInfo[@"ProfileId"];
        }
    }
    if (self.profileLabel) {
        self.profileLabel.text = [NSString stringWithFormat:@"←------------------ Profile Num: %@ -----------------→", profileId];
    }
    
    // Update IMEI/MEID labels
    for (UIView *card in @[self.imeiCard, self.meidCard]) {
        UILabel *valueLabel = [card viewWithTag:100];
        NSString *key = (card.tag == 200) ? @"IMEI" : @"MEID";
        if (valueLabel && key) {
            valueLabel.text = [[IdentifierManager sharedManager] currentValueForIdentifier:key] ?: @"Not Set";
        }
    }
    
    // Update Device Model label and state
    if (self.deviceModelCard) {
        UILabel *valueLabel = [self.deviceModelCard viewWithTag:100];
        if (valueLabel) {
            NSString *deviceModel = [[IdentifierManager sharedManager] currentValueForIdentifier:@"DeviceModel"];
            if (deviceModel) {
                valueLabel.text = deviceModel; // Only show the model string (iPhone15,2)
            } else {
                valueLabel.text = @"Not Set";
        }
        }
        
        // Also update the state label (Enabled/Disabled)
        [self updateStateForCard:self.deviceModelCard withIdentifierType:@"DeviceModel"];
    }
    
    // Update Device Theme label and state
    if (self.deviceThemeCard) {
        UILabel *valueLabel = [self.deviceThemeCard viewWithTag:100];
        if (valueLabel) {
            NSString *deviceTheme = [[IdentifierManager sharedManager] currentValueForIdentifier:@"DeviceTheme"];
            valueLabel.text = deviceTheme ?: @"Not Set";
        }
        
        // Also update the state label (Enabled/Disabled)
        [self updateStateForCard:self.deviceThemeCard withIdentifierType:@"DeviceTheme"];
    }
}

// Helper method to update the state label and switch for a card
- (void)updateStateForCard:(UIView *)card withIdentifierType:(NSString *)identifierType {
    if (!card) {
        NSLog(@"[WeaponX] Warning: Attempted to update state for nil card with identifier type: %@", identifierType);
        return;
    }
    
        UISwitch *enabledSwitch = nil;
        UILabel *stateLabel = nil;
    
    // Find controls
    for (UIView *sub in card.subviews) {
            for (UIView *sub2 in sub.subviews) {
            if ([sub2 isKindOfClass:[UIStackView class]]) {
                for (UIView *sub3 in [(UIStackView *)sub2 arrangedSubviews]) {
                    if ([sub3 isKindOfClass:[UIStackView class]]) {
                        for (UIView *sub4 in [(UIStackView *)sub3 arrangedSubviews]) {
                            if ([sub4 isKindOfClass:[UISwitch class]]) enabledSwitch = (UISwitch *)sub4;
                            if ([sub4 isKindOfClass:[UILabel class]] && sub4.tag == 100) stateLabel = (UILabel *)sub4;
                        }
                    }
                    if ([sub3 isKindOfClass:[UIButton class]]) {
                        UIButton *button = (UIButton *)sub3;
                        // Also update button colors based on enabled state
                        if ([identifierType isEqualToString:@"DeviceTheme"] && button.tag == 4) {
                            BOOL isEnabled = [[IdentifierManager sharedManager] isIdentifierEnabled:identifierType];
                            if (@available(iOS 15.0, *)) {
                                UIButtonConfiguration *cfg = [button.configuration copy];
                                cfg.baseForegroundColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
                                button.configuration = cfg;
                            } else {
                                button.tintColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
                            }
                        }
                    }
                }
            }
        }
    }
    
        if (enabledSwitch && stateLabel) {
        BOOL isEnabled = [[IdentifierManager sharedManager] isIdentifierEnabled:identifierType];
            enabledSwitch.on = isEnabled;
            stateLabel.text = isEnabled ? @"Enabled" : @"Disabled";
            stateLabel.textColor = isEnabled ? [UIColor systemBlueColor] : [UIColor labelColor];
        
        // Log that we updated the card state
        NSLog(@"[WeaponX] Updated card state for %@: %@", identifierType, isEnabled ? @"Enabled" : @"Disabled");
    } else {
        NSLog(@"[WeaponX] Warning: Could not find controls for %@ card", identifierType);
    }
}

// MARK: - Actions
- (void)editIdentifierValue:(UIButton *)sender {
    NSString *key = sender.tag == 1 ? @"IMEI" : @"MEID";
    NSString *title = [key isEqualToString:@"IMEI"] ? @"IMEI" : @"MEID";
    NSString *currentValue = [[IdentifierManager sharedManager] currentValueForIdentifier:key] ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Edit %@", title]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentValue;
        textField.placeholder = [NSString stringWithFormat:@"Enter %@", title];
        textField.keyboardType = UIKeyboardTypeASCIICapable;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newValue = alert.textFields.firstObject.text;
        if (newValue.length > 0 && ![newValue isEqualToString:currentValue]) {
            if ([key isEqualToString:@"IMEI"]) {
                [[IdentifierManager sharedManager] setCustomIMEI:newValue];
            } else if ([key isEqualToString:@"MEID"]) {
                [[IdentifierManager sharedManager] setCustomMEID:newValue];
            }
            // Find the card and update the value label
            UIView *targetCard = (sender.tag == 1) ? weakSelf.imeiCard : weakSelf.meidCard;
            for (UIView *sub in targetCard.subviews) {
                if ([sub isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)sub;
                    if (!(label.font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold)) {
                        label.text = newValue;
                        break;
                    }
                }
            }
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyIdentifierValue:(UIButton *)sender {
    NSString *key = nil;
    if (sender.tag == 1) key = @"IMEI";
    else if (sender.tag == 2) key = @"MEID";
    else if (sender.tag == 3) key = @"DeviceModel";
    else if (sender.tag == 4) key = @"DeviceTheme";
    
    if (!key) {
        NSLog(@"[WeaponX] Warning: Unknown identifier type for copy button with tag %ld", (long)sender.tag);
        return;
    }
    
    NSString *value = [[IdentifierManager sharedManager] currentValueForIdentifier:key] ?: @"Not Set";
    if (value) {
        UIPasteboard.generalPasteboard.string = value;
        if (@available(iOS 15.0, *)) {
            // Enhanced visual feedback for copy action (same as ProjectXViewController)
            UIColor *originalColor = sender.tintColor;
            UIButtonConfiguration *originalConfig = sender.configuration;
            UIButtonConfiguration *successConfig = [originalConfig copy];
            successConfig.image = [UIImage systemImageNamed:@"checkmark"];
            successConfig.baseForegroundColor = [UIColor systemGreenColor];
            [UIView animateWithDuration:0.2 animations:^{
                sender.configuration = successConfig;
            } completion:^(BOOL finished) {
                // Show success state for a moment
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    // Animate back to original state
                    [UIView animateWithDuration:0.2 animations:^{
                        UIButtonConfiguration *revertConfig = [originalConfig copy];
                        revertConfig.baseForegroundColor = originalColor;
                        sender.configuration = revertConfig;
                    }];
                });
            }];
        }
        
        NSLog(@"[WeaponX] Copied %@ value to clipboard: %@", key, value);
    }
}

- (void)identifierSwitchChanged:(UISwitch *)sender {
    NSString *key = nil;
    if (sender.tag == 1) key = @"IMEI";
    else if (sender.tag == 2) key = @"MEID";
    else if (sender.tag == 3) key = @"DeviceModel";
    else if (sender.tag == 4) key = @"DeviceTheme";
    [[IdentifierManager sharedManager] setIdentifierEnabled:sender.isOn forType:key];
    
    // Update UI colors for controls and state label
    UIView *card = nil;
    if (sender.tag == 1) {
        card = self.imeiCard;
    } else if (sender.tag == 2) {
        card = self.meidCard;
    } else if (sender.tag == 3) {
        card = self.deviceModelCard;
    } else if (sender.tag == 4) {
        card = self.deviceThemeCard;
    }
    
    if (!card) {
        NSLog(@"[WeaponX] Warning: Could not find card for identifier %@", key);
        return;
    }
    
    UILabel *stateLabel = nil;
    UIButton *copyButton = nil;
    UIButton *generateButton = nil;
    
    // Find controls
    for (UIView *sub in card.subviews) {
        for (UIView *sub2 in sub.subviews) {
            if ([sub2 isKindOfClass:[UIStackView class]]) {
                UIStackView *controlsStack = (UIStackView *)sub2;
                for (UIView *ctrl in controlsStack.arrangedSubviews) {
                    if ([ctrl isKindOfClass:[UIStackView class]]) {
                        UIStackView *switchStack = (UIStackView *)ctrl;
                        for (UIView *ssub in switchStack.arrangedSubviews) {
                            if ([ssub isKindOfClass:[UILabel class]]) stateLabel = (UILabel *)ssub;
                        }
                    }
                    if ([ctrl isKindOfClass:[UIButton class]]) {
                        UIButton *btn = (UIButton *)ctrl;
                        if (btn.tag == sender.tag) generateButton = btn;
                        else copyButton = btn;
                    }
                }
            }
        }
    }
    
    BOOL isEnabled = sender.isOn;
    if (stateLabel) stateLabel.textColor = isEnabled ? [UIColor systemBlueColor] : [UIColor labelColor];
    if (stateLabel) stateLabel.text = isEnabled ? @"Enabled" : @"Disabled";

    if (@available(iOS 15.0, *)) {
        if (copyButton) {
            UIButtonConfiguration *cfg = [copyButton.configuration copy];
            cfg.baseForegroundColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
            copyButton.configuration = cfg;
        }
        if (generateButton) {
            UIButtonConfiguration *cfg = [generateButton.configuration copy];
            cfg.baseForegroundColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
            generateButton.configuration = cfg;
        }
    } else {
        if (copyButton) copyButton.tintColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
        if (generateButton) generateButton.tintColor = isEnabled ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    }
}


- (void)generateIdentifier:(UIButton *)sender {
    NSString *key = nil;
    if (sender.tag == 1) key = @"IMEI";
    else if (sender.tag == 2) key = @"MEID";
    else if (sender.tag == 3) key = @"DeviceModel";
    else if (sender.tag == 4) key = @"DeviceTheme";
    
    NSString *newValue = nil;
    if ([key isEqualToString:@"IMEI"]) {
        newValue = [[IdentifierManager sharedManager] generateIMEI];
        if (newValue) {
            [[IdentifierManager sharedManager] setCustomIMEI:newValue];
        }
    } else if ([key isEqualToString:@"MEID"]) {
        newValue = [[IdentifierManager sharedManager] generateMEID];
        if (newValue) {
            [[IdentifierManager sharedManager] setCustomMEID:newValue];
        }
    } else if ([key isEqualToString:@"DeviceModel"]) {
        newValue = [[IdentifierManager sharedManager] generateDeviceModel];
        if (newValue) {
            [[IdentifierManager sharedManager] setCustomDeviceModel:newValue];
            
            // Get detailed device specifications
            [self showDeviceSpecificationsForModel:newValue];
        }
    } else if ([key isEqualToString:@"DeviceTheme"]) {
        // For DeviceTheme, we'll toggle between Light and Dark
        // instead of generating a random value every time
        newValue = [[IdentifierManager sharedManager] toggleDeviceTheme];
    }
    
    // Update the value label in the card
    if (newValue) {
        UIView *card = nil;
        if (sender.tag == 1) card = self.imeiCard;
        else if (sender.tag == 2) card = self.meidCard;
        else if (sender.tag == 3) card = self.deviceModelCard;
        else if (sender.tag == 4) card = self.deviceThemeCard;
        
        UILabel *valueLabel = [card viewWithTag:100];
        if ([valueLabel isKindOfClass:[UILabel class]]) {
            if ([key isEqualToString:@"DeviceModel"] && newValue) {
                // Use DeviceModelManager directly to ensure consistency
                NSString *modelName = [[DeviceModelManager sharedManager] deviceModelNameForString:newValue];
                if (modelName) {
                    valueLabel.text = newValue; // Only show the model string (iPhone15,2)
                } else {
                    valueLabel.text = newValue;
                }
            } else {
                valueLabel.text = newValue ?: @"Not Set";
            }
        }
    }
}

// Helper to show the device specs alert
- (void)showDeviceSpecsAlertWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Device Specifications"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// New helper method to show device specifications after model generation
- (void)showDeviceSpecificationsForModel:(NSString *)modelIdentifier {
    if (!modelIdentifier) return;
    
    IdentifierManager *identifierManager = [IdentifierManager sharedManager];
    
    // Always fetch from IdentifierManager which gets data from plist files
    NSDictionary *specs = [identifierManager getDeviceModelSpecifications];
    if (!specs) {
        // Fallback to DeviceModelManager if no specs found in plist
        DeviceModelManager *deviceManager = [DeviceModelManager sharedManager];
        NSString *modelName = [deviceManager deviceModelNameForString:modelIdentifier];
        NSString *screenResolution = [deviceManager screenResolutionForModel:modelIdentifier];
        NSString *viewportResolution = [deviceManager viewportResolutionForModel:modelIdentifier];
        CGFloat devicePixelRatio = [deviceManager devicePixelRatioForModel:modelIdentifier];
        NSInteger screenDensity = [deviceManager screenDensityForModel:modelIdentifier];
        NSString *cpuArchitecture = [deviceManager cpuArchitectureForModel:modelIdentifier];
        NSInteger deviceMemory = [deviceManager deviceMemoryForModel:modelIdentifier];
        NSString *gpuFamily = [deviceManager gpuFamilyForModel:modelIdentifier];
        NSInteger cpuCoreCount = [deviceManager cpuCoreCountForModel:modelIdentifier];
        NSString *metalFeatureSet = [deviceManager metalFeatureSetForModel:modelIdentifier];
        NSDictionary *webGLInfo = [deviceManager webGLInfoForModel:modelIdentifier];
        
        NSString *webGLDetails = [NSString stringWithFormat:
                                @"WebGL Vendor: %@\n"
                                @"WebGL Renderer: %@\n"
                                @"Unmasked Vendor: %@\n"
                                @"Unmasked Renderer: %@",
                                webGLInfo[@"webglVendor"] ?: @"Apple",
                                webGLInfo[@"webglRenderer"] ?: @"Apple GPU",
                                webGLInfo[@"unmaskedVendor"] ?: @"Apple Inc.",
                                webGLInfo[@"unmaskedRenderer"] ?: gpuFamily];
        
        NSString *message = [NSString stringWithFormat:
                             @"Device: %@\n"
                             @"Model ID: %@\n\n"
                             @"Screen Resolution: %@\n"
                             @"Viewport Resolution: %@\n"
                             @"Device Pixel Ratio: %.1f\n"
                             @"Screen Density: %ld PPI\n"
                             @"Device Memory: %ld GB\n"
                             @"CPU Architecture: %@\n"
                             @"CPU Cores: %ld\n"
                             @"GPU Family: %@\n"
                             @"Metal Feature Set: %@\n\n"
                             @"WebGL Info:\n%@",
                             modelName,
                             modelIdentifier,
                             screenResolution,
                             viewportResolution,
                             devicePixelRatio,
                             (long)screenDensity,
                             (long)deviceMemory,
                             cpuArchitecture,
                             (long)cpuCoreCount,
                             gpuFamily,
                             metalFeatureSet,
                             webGLDetails];
        
        [self showDeviceSpecsAlertWithMessage:message];
    } else {
        // Use the specifications from plist
        NSDictionary *webGLInfo = specs[@"webGLInfo"];
        NSString *webGLDetails = [NSString stringWithFormat:
                                @"WebGL Vendor: %@\n"
                                @"WebGL Renderer: %@\n"
                                @"Unmasked Vendor: %@\n"
                                @"Unmasked Renderer: %@",
                                webGLInfo[@"webglVendor"] ?: @"Apple",
                                webGLInfo[@"webglRenderer"] ?: @"Apple GPU",
                                webGLInfo[@"unmaskedVendor"] ?: @"Apple Inc.",
                                webGLInfo[@"unmaskedRenderer"] ?: specs[@"gpuFamily"]];
        
        NSString *message = [NSString stringWithFormat:
                             @"Device: %@\n"
                             @"Model ID: %@\n\n"
                             @"Screen Resolution: %@\n"
                             @"Viewport Resolution: %@\n"
                             @"Device Pixel Ratio: %.1f\n"
                             @"Screen Density: %ld PPI\n"
                             @"Device Memory: %ld GB\n"
                             @"CPU Architecture: %@\n"
                             @"CPU Cores: %ld\n"
                             @"GPU Family: %@\n"
                             @"Metal Feature Set: %@\n\n"
                             @"WebGL Info:\n%@",
                             specs[@"name"],
                             specs[@"value"],
                             specs[@"screenResolution"],
                             specs[@"viewportResolution"],
                             [specs[@"devicePixelRatio"] floatValue],
                             (long)[specs[@"screenDensity"] integerValue],
                             (long)[specs[@"deviceMemory"] integerValue],
                             specs[@"cpuArchitecture"],
                             (long)[specs[@"cpuCoreCount"] integerValue],
                             specs[@"gpuFamily"],
                             specs[@"metalFeatureSet"],
                             webGLDetails];
        
        [self showDeviceSpecsAlertWithMessage:message];
    }
}

// New method to handle info button tap
- (void)showDeviceSpecsButtonTapped:(UIButton *)sender {
    // Retrieve current device model
    NSString *currentDeviceModel = [[IdentifierManager sharedManager] currentValueForIdentifier:@"DeviceModel"];
    if (currentDeviceModel) {
        [self showDeviceSpecificationsForModel:currentDeviceModel];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Device Specifications"
                                                                       message:@"No device model is currently set. Please generate a device model first."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
