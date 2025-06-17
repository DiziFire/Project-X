#import "PlanSliderView.h"
#import "APIManager.h"

// Plan Cell class for displaying individual plans
@interface PlanCell : UICollectionViewCell

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UILabel *deviceLimitLabel;
@property (nonatomic, strong) UIButton *purchaseButton;
@property (nonatomic, strong) NSDictionary *planData;

- (void)configureWithPlan:(NSDictionary *)plan;

@end

@implementation PlanCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    // Create container view with modern glassmorphism styling
    self.containerView = [[UIView alloc] init];
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.containerView.layer.cornerRadius = 18.0;
    self.containerView.clipsToBounds = YES;
    
    // Create and add blur effect for glassmorphism
    if (@available(iOS 13.0, *)) {
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:blurView];
        
        // Make blur fill container
        [NSLayoutConstraint activateConstraints:@[
            [blurView.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
            [blurView.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
            [blurView.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
            [blurView.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor]
        ]];
    }
    
    // Apply glassmorphism styling
    if (@available(iOS 13.0, *)) {
        // Dark mode/light mode adaptive background with transparency
        self.containerView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.12 green:0.12 blue:0.13 alpha:0.7]; // Dark semi-transparent
            } else {
                return [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.6]; // Light semi-transparent
            }
        }];
        
        // Subtle green border for hacker aesthetic
        self.containerView.layer.borderColor = [UIColor systemGreenColor].CGColor;
    } else {
        self.containerView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.8];
        self.containerView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
    }
    
    // Refined border and shadow for glassmorphism
    self.containerView.layer.borderWidth = 0.5;
    
    // Outer container to allow shadow to be visible
    UIView *shadowContainer = [[UIView alloc] init];
    shadowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    shadowContainer.clipsToBounds = NO;
    shadowContainer.backgroundColor = [UIColor clearColor];
    
    // Add shadow to shadow container
    shadowContainer.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
    shadowContainer.layer.shadowOffset = CGSizeMake(0, 0);
    shadowContainer.layer.shadowRadius = 15.0;
    shadowContainer.layer.shadowOpacity = 0.3;
    shadowContainer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 100, 100) cornerRadius:18.0].CGPath;
    
    [self.contentView addSubview:shadowContainer];
    [shadowContainer addSubview:self.containerView];
    
    // Title label with hacker-style monospace font
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:17.0] ?: [UIFont monospacedSystemFontOfSize:17.0 weight:UIFontWeightBold];
    
    if (@available(iOS 13.0, *)) {
        self.titleLabel.textColor = [UIColor systemGreenColor];
    } else {
        self.titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    }
    self.titleLabel.numberOfLines = 1;
    [self.containerView addSubview:self.titleLabel];
    
    // Description label with improved styling
    self.descriptionLabel = [[UILabel alloc] init];
    self.descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.descriptionLabel.font = [UIFont fontWithName:@"Menlo" size:12.0] ?: [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    
    if (@available(iOS 13.0, *)) {
        self.descriptionLabel.textColor = [UIColor labelColor];
    } else {
        self.descriptionLabel.textColor = [UIColor whiteColor];
    }
    self.descriptionLabel.numberOfLines = 2;
    [self.containerView addSubview:self.descriptionLabel];
    
    // Price label with improved terminal-style formatting
    self.priceLabel = [[UILabel alloc] init];
    self.priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.priceLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:15.0] ?: [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightBold];
    
    if (@available(iOS 13.0, *)) {
        self.priceLabel.textColor = [UIColor systemGreenColor];
    } else {
        self.priceLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    }
    [self.containerView addSubview:self.priceLabel];
    
    // Device limit label with small font size
    self.deviceLimitLabel = [[UILabel alloc] init];
    self.deviceLimitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceLimitLabel.font = [UIFont fontWithName:@"Menlo" size:10.0] ?: [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    
    if (@available(iOS 13.0, *)) {
        self.deviceLimitLabel.textColor = [UIColor secondaryLabelColor]; // Use secondary color for less emphasis
    } else {
        self.deviceLimitLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0]; // Light gray on older iOS
    }
    self.deviceLimitLabel.numberOfLines = 1;
    self.deviceLimitLabel.textAlignment = NSTextAlignmentCenter;
    [self.containerView addSubview:self.deviceLimitLabel];
    
    // Purchase button with modern glassmorphism look
    self.purchaseButton = [[UIButton alloc] init];
    self.purchaseButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.purchaseButton.layer.cornerRadius = 10.0;
    
    // Apply glassmorphism to button too
    if (@available(iOS 13.0, *)) {
        UIBlurEffect *buttonBlurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        UIVisualEffectView *buttonBlurView = [[UIVisualEffectView alloc] initWithEffect:buttonBlurEffect];
        buttonBlurView.translatesAutoresizingMaskIntoConstraints = NO;
        buttonBlurView.layer.cornerRadius = 10.0;
        buttonBlurView.clipsToBounds = YES;
        [self.purchaseButton insertSubview:buttonBlurView atIndex:0];
        
        [NSLayoutConstraint activateConstraints:@[
            [buttonBlurView.topAnchor constraintEqualToAnchor:self.purchaseButton.topAnchor],
            [buttonBlurView.leadingAnchor constraintEqualToAnchor:self.purchaseButton.leadingAnchor],
            [buttonBlurView.trailingAnchor constraintEqualToAnchor:self.purchaseButton.trailingAnchor],
            [buttonBlurView.bottomAnchor constraintEqualToAnchor:self.purchaseButton.bottomAnchor]
        ]];
        
        // Tint overlay on top of blur
        UIView *tintView = [[UIView alloc] init];
        tintView.translatesAutoresizingMaskIntoConstraints = NO;
        tintView.backgroundColor = [UIColor systemGreenColor];
        tintView.alpha = 0.7;
        tintView.layer.cornerRadius = 10.0;
        tintView.clipsToBounds = YES;
        [self.purchaseButton insertSubview:tintView atIndex:1];
        
        [NSLayoutConstraint activateConstraints:@[
            [tintView.topAnchor constraintEqualToAnchor:self.purchaseButton.topAnchor],
            [tintView.leadingAnchor constraintEqualToAnchor:self.purchaseButton.leadingAnchor],
            [tintView.trailingAnchor constraintEqualToAnchor:self.purchaseButton.trailingAnchor],
            [tintView.bottomAnchor constraintEqualToAnchor:self.purchaseButton.bottomAnchor]
        ]];
    } else {
        self.purchaseButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:0.9];
    }
    
    [self.purchaseButton setTitle:@"[PURCHASE]" forState:UIControlStateNormal];
    [self.purchaseButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.purchaseButton.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:14.0] ?: [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightBold];
    
    // Add subtle button glow effect
    self.purchaseButton.layer.shadowColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:1.0].CGColor;
    self.purchaseButton.layer.shadowOffset = CGSizeMake(0, 0);
    self.purchaseButton.layer.shadowRadius = 6.0;
    self.purchaseButton.layer.shadowOpacity = 0.5;
    
    [self.purchaseButton addTarget:self action:@selector(purchaseButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.containerView addSubview:self.purchaseButton];
    
    // Constraints for shadow container
    [NSLayoutConstraint activateConstraints:@[
        [shadowContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [shadowContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:5],
        [shadowContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-5],
        [shadowContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4]
    ]];
    
    // Layout constraints for container view inside shadow container
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.topAnchor constraintEqualToAnchor:shadowContainer.topAnchor],
        [self.containerView.leadingAnchor constraintEqualToAnchor:shadowContainer.leadingAnchor],
        [self.containerView.trailingAnchor constraintEqualToAnchor:shadowContainer.trailingAnchor],
        [self.containerView.bottomAnchor constraintEqualToAnchor:shadowContainer.bottomAnchor]
    ]];
    
    // Layout constraints for content inside container - more compact
    [NSLayoutConstraint activateConstraints:@[
        // Title label - reduced top padding
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:12],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-12],
        
        // Description label - closer to title
        [self.descriptionLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
        [self.descriptionLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:12],
        [self.descriptionLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-12],
        
        // Price label - more compact
        [self.priceLabel.topAnchor constraintEqualToAnchor:self.descriptionLabel.bottomAnchor constant:10],
        [self.priceLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:12],
        [self.priceLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-12],
        
        // Device limit label - between price and purchase button
        [self.deviceLimitLabel.topAnchor constraintEqualToAnchor:self.priceLabel.bottomAnchor constant:4],
        [self.deviceLimitLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:12],
        [self.deviceLimitLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-12],
        
        // Purchase button - adjusted to account for device limit label
        [self.purchaseButton.topAnchor constraintEqualToAnchor:self.deviceLimitLabel.bottomAnchor constant:10],
        [self.purchaseButton.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:12],
        [self.purchaseButton.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-12],
        [self.purchaseButton.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor constant:-12],
        [self.purchaseButton.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)configureWithPlan:(NSDictionary *)plan {
    self.planData = plan;
    
    // Set data from plan dictionary with terminal-style formatting
    // Hacker-style prefix and uppercase for title
    self.titleLabel.text = [NSString stringWithFormat:@"> %@", [plan[@"name"] uppercaseString]];
    
    // Format description with terminal-style leading indicator
    NSString *rawDescription = plan[@"description"];
    if (rawDescription.length > 0) {
        // Add terminal-style formatting to description
        self.descriptionLabel.text = [NSString stringWithFormat:@"// %@", rawDescription];
    } else {
        self.descriptionLabel.text = @"// No description available";
    }
    
    // Format price with appropriate currency and terminal-style formatting
    NSNumber *price = plan[@"price"];
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterCurrencyStyle;
    formatter.currencyCode = plan[@"currency"] ?: @"USD";
    
    // Terminal/hacker style price display
    NSString *formattedPrice = [formatter stringFromNumber:price];
    self.priceLabel.text = [NSString stringWithFormat:@"COST: %@", formattedPrice];
    
    // Set device limit information
    NSNumber *deviceLimit = plan[@"device_limit"];
    if (deviceLimit != nil && ![deviceLimit isKindOfClass:[NSNull class]]) {
        int limitValue = [deviceLimit intValue];
        NSString *deviceText = limitValue == 1 ? @"device" : @"devices";
        self.deviceLimitLabel.text = [NSString stringWithFormat:@"LIMIT: %d %@", limitValue, deviceText];
    } else {
        // Try alternative keys that might contain the device limit
        deviceLimit = plan[@"devices"] ?: plan[@"max_devices"] ?: plan[@"device_count"];
        if (deviceLimit != nil && ![deviceLimit isKindOfClass:[NSNull class]]) {
            int limitValue = [deviceLimit intValue];
            NSString *deviceText = limitValue == 1 ? @"device" : @"devices";
            self.deviceLimitLabel.text = [NSString stringWithFormat:@"LIMIT: %d %@", limitValue, deviceText];
        } else {
            // Default if no device limit information is found
            self.deviceLimitLabel.text = @"LIMIT: check website";
        }
    }
    
    // Check if the plan is disabled (downgrade not allowed)
    BOOL isDisabled = [plan[@"disabled"] boolValue];
    
    // Update button state based on plan status
    if ([plan[@"purchased"] boolValue]) {
        // Show "CURRENT PLAN" for the user's active subscription
        [self.purchaseButton setTitle:@"[CURRENT PLAN]" forState:UIControlStateNormal];
        
        // Enhanced styling for current plan
        if (@available(iOS 13.0, *)) {
            // Use a more prominent color for current plan
            UIColor *currentPlanColor = [UIColor systemBlueColor];
            
            // Apply gradient effect to the button
            CAGradientLayer *gradientLayer = [CAGradientLayer layer];
            gradientLayer.frame = self.purchaseButton.bounds;
            gradientLayer.colors = @[(id)[currentPlanColor colorWithAlphaComponent:0.7].CGColor, 
                                     (id)[currentPlanColor colorWithAlphaComponent:0.9].CGColor];
            gradientLayer.startPoint = CGPointMake(0.0, 0.5);
            gradientLayer.endPoint = CGPointMake(1.0, 0.5);
            gradientLayer.cornerRadius = 10.0;
            
            // Remove any existing gradient
            CALayer *oldGradient = nil;
            for (CALayer *layer in self.purchaseButton.layer.sublayers) {
                if ([layer isKindOfClass:[CAGradientLayer class]]) {
                    oldGradient = layer;
                    break;
                }
            }
            [oldGradient removeFromSuperlayer];
            
            // Insert the gradient
            [self.purchaseButton.layer insertSublayer:gradientLayer atIndex:0];
            
            // Ensure the button background is clear to show gradient
            for (UIView *subview in self.purchaseButton.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                    subview.alpha = 0.2; // Reduce blur effect opacity
                }
            }
        } else {
            self.purchaseButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.9];
        }
        
        // Make text white for better contrast on blue background
        [self.purchaseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        
        // Add a special glow effect to highlight current plan
        self.purchaseButton.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0].CGColor;
        self.purchaseButton.layer.shadowOffset = CGSizeMake(0, 0);
        self.purchaseButton.layer.shadowRadius = 8.0;
        self.purchaseButton.layer.shadowOpacity = 0.7;
        
        // Add a special border to indicate current plan
        self.containerView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0].CGColor;
        self.containerView.layer.borderWidth = 1.5;
        
        // Disable button since it's already the current plan
        self.purchaseButton.enabled = NO;
    } else if (isDisabled) {
        // Handle disabled (downgrade not allowed) plans
        NSString *disabledReason = plan[@"disabled_reason"] ?: @"UNAVAILABLE";
        [self.purchaseButton setTitle:[NSString stringWithFormat:@"[%@]", disabledReason] forState:UIControlStateNormal];
        self.purchaseButton.enabled = NO;
        
        // Gray out disabled plans
        if (@available(iOS 13.0, *)) {
            // Remove any gradient layers
            CALayer *gradientLayer = nil;
            for (CALayer *layer in self.purchaseButton.layer.sublayers) {
                if ([layer isKindOfClass:[CAGradientLayer class]]) {
                    gradientLayer = layer;
                    break;
                }
            }
            [gradientLayer removeFromSuperlayer];
            
            self.purchaseButton.backgroundColor = [UIColor systemGray4Color];
            [self.purchaseButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        } else {
            self.purchaseButton.backgroundColor = [UIColor colorWithWhite:0.6 alpha:0.8];
            [self.purchaseButton setTitleColor:[UIColor darkTextColor] forState:UIControlStateNormal];
        }
        
        // Dim the container for disabled plans
        self.containerView.alpha = 0.7;
        
        // No glow for disabled plans
        self.purchaseButton.layer.shadowOpacity = 0.1;
        
        // Add a red border to indicate plan is not available
        self.containerView.layer.borderColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.5].CGColor;
        self.containerView.layer.borderWidth = 0.5;
    } else {
        [self.purchaseButton setTitle:@"[PURCHASE]" forState:UIControlStateNormal];
        
        // Use green for available plans
        if (@available(iOS 13.0, *)) {
            self.purchaseButton.backgroundColor = [UIColor systemGreenColor];
            
            // Reset any visual effect views to normal opacity
            for (UIView *subview in self.purchaseButton.subviews) {
                if ([subview isKindOfClass:[UIVisualEffectView class]]) {
                    subview.alpha = 1.0;
                }
            }
            
            // Remove any gradient layers
            CALayer *gradientLayer = nil;
            for (CALayer *layer in self.purchaseButton.layer.sublayers) {
                if ([layer isKindOfClass:[CAGradientLayer class]]) {
                    gradientLayer = layer;
                    break;
                }
            }
            [gradientLayer removeFromSuperlayer];
        } else {
            self.purchaseButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
        }
        
        // Reset text color to black for purchase button
        [self.purchaseButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        
        // Reset shadow to normal
        self.purchaseButton.layer.shadowColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:1.0].CGColor;
        self.purchaseButton.layer.shadowOffset = CGSizeMake(0, 0);
        self.purchaseButton.layer.shadowRadius = 6.0;
        self.purchaseButton.layer.shadowOpacity = 0.5;
        
        // Reset container border to default green
        if (@available(iOS 13.0, *)) {
            self.containerView.layer.borderColor = [UIColor systemGreenColor].CGColor;
        } else {
            self.containerView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
        }
        self.containerView.layer.borderWidth = 0.5;
        
        // Reset container opacity
        self.containerView.alpha = 1.0;
        
        self.purchaseButton.enabled = YES;
    }
}

- (void)purchaseButtonTapped {
    // Use responder chain to handle purchase
    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[PlanSliderView class]]) {
            [(PlanSliderView *)responder handlePlanPurchase:self.planData];
            break;
        }
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.descriptionLabel.text = nil;
    self.priceLabel.text = nil;
    self.planData = nil;
    [self.purchaseButton setTitle:@"[PURCHASE]" forState:UIControlStateNormal];
    
    // Reset to appropriate default color
    if (@available(iOS 13.0, *)) {
        self.purchaseButton.backgroundColor = [UIColor systemGreenColor];
    } else {
        self.purchaseButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    }
    
    // Reset button text color
    [self.purchaseButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    
    // Reset container border
    if (@available(iOS 13.0, *)) {
        self.containerView.layer.borderColor = [UIColor systemGreenColor].CGColor;
    } else {
        self.containerView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
    }
    self.containerView.layer.borderWidth = 0.5;
    
    // Reset shadow
    self.purchaseButton.layer.shadowColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:1.0].CGColor;
    self.purchaseButton.layer.shadowRadius = 6.0;
    self.purchaseButton.layer.shadowOpacity = 0.5;
    
    // Remove any gradients
    CALayer *gradientLayer = nil;
    for (CALayer *layer in self.purchaseButton.layer.sublayers) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) {
            gradientLayer = layer;
            break;
        }
    }
    [gradientLayer removeFromSuperlayer];
    
    self.purchaseButton.enabled = YES;
}

@end

// MARK: - PlanSliderView Implementation
@interface PlanSliderView ()

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) NSString *currentPlanId;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UILabel *deviceLimitLabel;
@property (nonatomic, strong) UIButton *purchaseButton;

@end

@implementation PlanSliderView

- (instancetype)initWithFrame:(CGRect)frame authToken:(NSString *)authToken {
    self = [super initWithFrame:frame];
    if (self) {
        _authToken = authToken;
        _plans = @[];
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    // Apply clear background to allow parent styling to show through
    self.backgroundColor = [UIColor clearColor];
    
    // Modern title label with improved appearance
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"SUBSCRIPTION PLANS";
    self.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:18.0] ?: [UIFont monospacedSystemFontOfSize:18.0 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    
    // Enhanced terminal-inspired styling
    if (@available(iOS 13.0, *)) {
        self.titleLabel.textColor = [UIColor systemGreenColor];
        // Add subtle shadow for glow effect
        self.titleLabel.layer.shadowColor = [UIColor systemGreenColor].CGColor;
    } else {
        self.titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
        self.titleLabel.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0].CGColor;
    }
    
    // Add terminal-style text glow
    self.titleLabel.layer.shadowOffset = CGSizeMake(0, 0);
    self.titleLabel.layer.shadowRadius = 4.0;
    self.titleLabel.layer.shadowOpacity = 0.6;
    [self addSubview:self.titleLabel];
    
    // Error label with improved terminal styling
    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.text = @">> Error: Unable to load plans. Retry connection? <<";
    self.errorLabel.font = [UIFont fontWithName:@"Menlo" size:14.0] ?: [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.errorLabel.textColor = [UIColor systemRedColor];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.hidden = YES;
    [self addSubview:self.errorLabel];
    
    // Collection view with improved layout for better card visibility
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 15;
    layout.minimumInteritemSpacing = 15;
    // Wider section insets to prevent cards from touching edges
    layout.sectionInset = UIEdgeInsetsMake(4, 16, 4, 16);
    
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.clipsToBounds = NO; // Important for showing full card with shadow
    
    // Improve scrolling performance
    self.collectionView.decelerationRate = UIScrollViewDecelerationRateFast;
    self.collectionView.alwaysBounceHorizontal = YES;
    
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    
    // Disable pagination for smoother scrolling
    self.collectionView.pagingEnabled = NO;
    if (@available(iOS 11.0, *)) {
        self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    
    // Register cell class
    [self.collectionView registerClass:[PlanCell class] forCellWithReuseIdentifier:@"PlanCell"];
    [self addSubview:self.collectionView];
    
    // Activity indicator with themed styling
    if (@available(iOS 13.0, *)) {
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.activityIndicator.color = [UIColor systemGreenColor];
    } else {
        // For iOS 12 and below, use the constructor with frame then set style
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Suppress the deprecation warning - this code will only run on iOS 12 and below
        self.activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
        #pragma clang diagnostic pop
        
        self.activityIndicator.color = [UIColor colorWithRed:0.0 green:0.9 blue:0.4 alpha:1.0];
    }
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self addSubview:self.activityIndicator];
    
    // Layout constraints for optimized display with better collection view positioning
    [NSLayoutConstraint activateConstraints:@[
        // Title label with centered layout
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        
        // Error label
        [self.errorLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:12],
        [self.errorLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.errorLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        
        // Collection view with better vertical positioning
        [self.collectionView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:10],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        
        // Activity indicator
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.collectionView.centerYAnchor]
    ]];
}

- (void)setLoading:(BOOL)loading {
    _loading = loading;
    
    if (loading) {
        [self.activityIndicator startAnimating];
        self.collectionView.hidden = YES;
    self.errorLabel.hidden = YES;
        
        // Add a terminal-style loading message
        self.errorLabel.text = @">> Connecting to server... <<";
        self.errorLabel.hidden = NO;
    } else {
        [self.activityIndicator stopAnimating];
        
        // Only hide the collection view if there are no plans
        if (self.plans.count > 0) {
            NSLog(@"[WeaponX] Showing %lu plans in collection view", (unsigned long)self.plans.count);
            self.collectionView.hidden = NO;
            self.errorLabel.hidden = YES;
            
            // Ensure collection view is reloaded with current plans
            [self.collectionView reloadData];
            
            // Ensure first plan is visible by scrolling to it
            if (self.plans.count > 0) {
                [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0] 
                                            atScrollPosition:UICollectionViewScrollPositionLeft 
                                                    animated:YES];
            }
        } else {
            NSLog(@"[WeaponX] No plans available to display");
            self.collectionView.hidden = YES;
            self.errorLabel.text = @">> Error: No subscription plans found <<";
            self.errorLabel.hidden = NO;
        }
    }
}

#pragma mark - Loading Plans

- (void)loadPlans {
    [self loadPlansWithCompletion:nil];
}

- (void)loadPlansWithCompletion:(void (^)(BOOL success))completion {
    self.loading = YES;
    
    NSLog(@"[WeaponX] PlanSliderView loading plans with token: %@", self.authToken);
    
    // First fetch the user's current plan to identify it in the slider
    [[APIManager sharedManager] fetchUserPlanWithToken:self.authToken completion:^(NSDictionary *planData, NSError *error) {
        if (!error && planData) {
            NSLog(@"[WeaponX] Fetched user's current plan: %@", planData);
            
            // Extract plan ID based on different possible response formats
            if ([planData objectForKey:@"has_plan"] != nil && [planData[@"has_plan"] boolValue] && planData[@"plan"]) {
                self.currentPlanId = [planData[@"plan"][@"id"] stringValue];
            } else if (planData[@"id"]) {
                self.currentPlanId = [planData[@"id"] stringValue];
            } else if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
                self.currentPlanId = [planData[@"plan"][@"id"] stringValue];
            }
            
            NSLog(@"[WeaponX] Current plan ID: %@", self.currentPlanId ?: @"None");
        } else {
            NSLog(@"[WeaponX] Failed to fetch user's current plan: %@", error.localizedDescription ?: @"Unknown error");
            self.currentPlanId = nil;
        }
        
        // Now fetch all available plans
        [self fetchAllPlansWithCompletion:completion];
    }];
}

- (void)fetchAllPlansWithCompletion:(void (^)(BOOL success))completion {
    // Get all available plans from API
    [[APIManager sharedManager] fetchAllPlansWithToken:self.authToken completion:^(NSArray *plans, NSError *error) {
        // Switch to main thread for UI updates
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            
            if (error) {
                NSLog(@"[WeaponX] Error loading plans: %@", error.localizedDescription);
                self.errorLabel.text = @"Failed to load plans. Please try again.";
                self.errorLabel.hidden = NO;
                self.collectionView.hidden = YES;
                
                if (completion) {
                    completion(NO);
                }
                return;
            }
            
            if (plans.count > 0) {
                NSLog(@"[WeaponX] Loaded %lu plans successfully", (unsigned long)plans.count);
                
                // Filter out plan with ID 1
                NSMutableArray *filteredPlans = [NSMutableArray array];
                for (NSDictionary *plan in plans) {
                    NSString *planIdString = [plan[@"id"] stringValue];
                    NSInteger planId = [planIdString integerValue];
                    
                    // Skip plan with ID 1
                    if (planId == 1) {
                        NSLog(@"[WeaponX] Filtering out plan ID 1: %@", plan[@"name"]);
                        continue;
                    }
                    
                    [filteredPlans addObject:plan];
                }
                
                NSLog(@"[WeaponX] Filtered %lu plans down to %lu plans after removing plan ID 1", 
                      (unsigned long)plans.count, (unsigned long)filteredPlans.count);
                
                // Mark the current plan as purchased
                if (self.currentPlanId) {
                    NSMutableArray *updatedPlans = [NSMutableArray arrayWithCapacity:filteredPlans.count];
                    
                    // Find current plan to get its price
                    NSNumber *currentPlanPrice = nil;
                    NSString *currentPlanId = self.currentPlanId;
                    
                    for (NSDictionary *plan in filteredPlans) {
                        NSString *planId = [plan[@"id"] stringValue];
                        if ([planId isEqualToString:currentPlanId]) {
                            currentPlanPrice = plan[@"price"];
                            break;
                        }
                    }
                    
                    for (NSDictionary *plan in filteredPlans) {
                        NSMutableDictionary *updatedPlan = [plan mutableCopy];
                        NSString *planId = [plan[@"id"] stringValue];
                        
                        // Mark as purchased if this is the current plan
                        if ([planId isEqualToString:self.currentPlanId]) {
                            updatedPlan[@"purchased"] = @YES;
                            NSLog(@"[WeaponX] Marked plan %@ as current plan", planId);
                        } else {
                            updatedPlan[@"purchased"] = @NO;
                            
                            // Disable downgrade - mark plans with lower prices as unavailable
                            if (currentPlanPrice && plan[@"price"] && [plan[@"price"] compare:currentPlanPrice] == NSOrderedAscending) {
                                updatedPlan[@"disabled"] = @YES;
                                updatedPlan[@"disabled_reason"] = @"No Downgrade";
                                NSLog(@"[WeaponX] Marked plan %@ as disabled (downgrade not allowed)", planId);
                            }
                        }
                        
                        [updatedPlans addObject:updatedPlan];
                    }
                    
                    self.plans = updatedPlans;
                } else {
                    self.plans = filteredPlans;
                }
                
                // Hide error message and show collection view only if we have plans after filtering
                if (self.plans.count > 0) {
                    self.errorLabel.hidden = YES;
                    self.collectionView.hidden = NO;
        [self.collectionView reloadData];
                } else {
                    // If we filtered out all plans, show an appropriate message
                    self.collectionView.hidden = YES;
                    self.errorLabel.text = @"No subscription plans available for your account.";
                    self.errorLabel.hidden = NO;
                }
                
                if (completion) {
                    completion(YES);
                }
            } else {
                NSLog(@"[WeaponX] No plans loaded from API");
                self.errorLabel.text = @"No subscription plans available.";
                self.errorLabel.hidden = NO;
                self.collectionView.hidden = YES;
                
                if (completion) {
                    completion(NO);
                }
            }
        });
    }];
}

- (void)reloadData {
    [self.collectionView reloadData];
}

- (void)handlePlanPurchase:(NSDictionary *)plan {
    // Check if this plan is disabled (downgrade not allowed)
    if ([plan[@"disabled"] boolValue]) {
        // Show an alert explaining why this plan is not available
        NSString *reason = plan[@"disabled_reason"] ?: @"This plan is not available for your account.";
        
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Plan Not Available" 
            message:reason
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        // Use modern way to find view controller to present alert
        UIViewController *topVC = [self findTopViewController];
        [topVC presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Check if this is the current plan
    NSString *planId = [plan[@"id"] stringValue];
    if ([planId isEqualToString:self.currentPlanId]) {
        // This is already the current plan, show an alert
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Current Plan" 
            message:@"You are already subscribed to this plan." 
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        // Use modern way to find view controller to present alert
        UIViewController *topVC = [self findTopViewController];
        [topVC presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Get current plan and its price
    NSDecimalNumber *selectedPlanPrice = nil;
    if (plan[@"price"]) {
        if ([plan[@"price"] isKindOfClass:[NSNumber class]]) {
            selectedPlanPrice = [NSDecimalNumber decimalNumberWithDecimal:[plan[@"price"] decimalValue]];
        } else if ([plan[@"price"] isKindOfClass:[NSString class]]) {
            selectedPlanPrice = [NSDecimalNumber decimalNumberWithString:plan[@"price"]];
        }
    }
    
    // Find user's current plan price from the loaded plans
    NSDecimalNumber *currentPlanPrice = nil;
    for (NSDictionary *loadedPlan in self.plans) {
        NSString *loadedPlanId = [loadedPlan[@"id"] stringValue];
        if ([loadedPlanId isEqualToString:self.currentPlanId]) {
            if (loadedPlan[@"price"]) {
                if ([loadedPlan[@"price"] isKindOfClass:[NSNumber class]]) {
                    currentPlanPrice = [NSDecimalNumber decimalNumberWithDecimal:[loadedPlan[@"price"] decimalValue]];
                } else if ([loadedPlan[@"price"] isKindOfClass:[NSString class]]) {
                    currentPlanPrice = [NSDecimalNumber decimalNumberWithString:loadedPlan[@"price"]];
                }
            }
            break;
        }
    }
    
    // Prevent downgrading
    if (self.currentPlanId && currentPlanPrice && selectedPlanPrice && 
        [selectedPlanPrice compare:currentPlanPrice] == NSOrderedAscending) {
        // Selected plan is cheaper than current plan - prevent downgrade
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"No Downgrade" 
            message:@"You cannot downgrade from a higher-priced plan to a lower-priced plan. Only upgrades are allowed." 
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        UIViewController *topVC = [self findTopViewController];
        [topVC presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // If this is an upgrade/downgrade, confirm with the user
    if (self.currentPlanId) {
        NSString *message = [NSString stringWithFormat:@"Are you sure you want to change your subscription to %@?", plan[@"name"]];
        
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Change Subscription" 
            message:message 
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"Cancel" 
            style:UIAlertActionStyleCancel 
            handler:nil]];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"Confirm" 
            style:UIAlertActionStyleDefault 
            handler:^(UIAlertAction * _Nonnull action) {
                // Proceed with purchase
                [self proceedWithPlanPurchase:plan];
            }]];
        
        // Use modern way to find view controller to present alert
        UIViewController *topVC = [self findTopViewController];
        [topVC presentViewController:alert animated:YES completion:nil];
    } else {
        // New subscription, proceed directly
        [self proceedWithPlanPurchase:plan];
    }
}

// Helper method to find top view controller without using keyWindow
- (UIViewController *)findTopViewController {
    UIViewController *rootVC = nil;
    
    // Get the key window using the modern approach for iOS 13+
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        rootVC = window.rootViewController;
                        break;
                    }
                }
                if (rootVC) break;
            }
        }
        
        // Fallback if we couldn't find the key window
        if (!rootVC) {
            UIWindowScene *windowScene = (UIWindowScene *)[connectedScenes anyObject];
            rootVC = windowScene.windows.firstObject.rootViewController;
        }
    } else {
        // Fallback for iOS 12 and below (though this is less likely to be used in iOS 15)
        rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
    }
    
    // Navigate through presented view controllers to find the topmost one
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    return rootVC;
}

- (void)proceedWithPlanPurchase:(NSDictionary *)plan {
    if ([self.delegate respondsToSelector:@selector(planSliderView:didPurchasePlan:)]) {
        [self.delegate planSliderView:self didPurchasePlan:plan];
        
        // After purchase is initiated, update the UI to show loading state
        self.loading = YES;
        self.errorLabel.text = @"Processing purchase...";
        self.errorLabel.hidden = NO;
        
        // Set a timeout to check for purchase completion
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // After 10 seconds, reload plans to reflect any changes
            [self loadPlans];
        });
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.plans.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    PlanCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"PlanCell" forIndexPath:indexPath];
    
    if (indexPath.item < self.plans.count) {
        [cell configureWithPlan:self.plans[indexPath.item]];
    }
    
    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    // Calculate optimal size to ensure cards are fully visible
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    
    // Calculate width to ensure cards are properly sized but not too wide
    // Use slightly narrower width to ensure cards aren't cut off horizontally
    CGFloat width;
    if (screenWidth >= 380) {
        // Wider screens - show more of the card
        width = screenWidth * 0.40; // Slightly reduced width
    } else {
        // Smaller screens - use smaller cards
        width = screenWidth * 0.60;
    }
    
    // Reduced height to ensure content fits completely
    CGFloat height = 190;
    
    return CGSizeMake(width, height);
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item < self.plans.count) {
        NSDictionary *selectedPlan = self.plans[indexPath.item];
        
        if ([self.delegate respondsToSelector:@selector(planSliderView:didSelectPlan:)]) {
            [self.delegate planSliderView:self didSelectPlan:selectedPlan];
        }
    }
}

#pragma mark - Height Calculation

- (CGFloat)getContentHeight {
    // Calculate optimal height for slider view with new card layout
    CGFloat screenHeight = UIScreen.mainScreen.bounds.size.height;
    CGFloat titleHeight = 40; // Title + spacing
    
    // Dynamically adjust collection height based on device 
    CGFloat collectionHeight;
    
    if (self.plans.count > 0) {
        // When plans are available, ensure enough height for full card visibility
        // Increase heights to accommodate device limit label
        if (screenHeight > 700) { // Larger devices
            collectionHeight = 240; // Increased from 220 to account for device limit
        } else { // Smaller devices
            collectionHeight = 220; // Increased from 200 to account for device limit
        }
        NSLog(@"[WeaponX] Using collection height: %f for %lu plans (includes device limit)", collectionHeight, (unsigned long)self.plans.count);
    } else {
        // When loading or showing error, use less height
        collectionHeight = 150;
        NSLog(@"[WeaponX] Using smaller collection height: %f (no plans)", collectionHeight);
    }
    
    // Account for bottom padding and potential device adjustments
    CGFloat bottomPadding = 20;
    
    // Add extra height for scrolling comfort and to ensure full card visibility
    CGFloat totalHeight = titleHeight + collectionHeight + bottomPadding;
    
    // Ensure minimum height for consistent layout across devices
    totalHeight = MAX(totalHeight, 250);
    
    NSLog(@"[WeaponX] PlanSliderView total height: %f", totalHeight);
    return totalHeight;
}

- (void)setupConstraints {
    // Create container view if it doesn't exist
    if (!self.containerView) {
        self.containerView = [[UIView alloc] init];
        self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.containerView];
    }

    // Create labels if they don't exist
    if (!self.titleLabel) {
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.titleLabel];
    }

    if (!self.descriptionLabel) {
        self.descriptionLabel = [[UILabel alloc] init];
        self.descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.descriptionLabel];
    }

    if (!self.priceLabel) {
        self.priceLabel = [[UILabel alloc] init];
        self.priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.priceLabel];
    }

    if (!self.deviceLimitLabel) {
        self.deviceLimitLabel = [[UILabel alloc] init];
        self.deviceLimitLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.deviceLimitLabel];
    }

    if (!self.purchaseButton) {
        self.purchaseButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.purchaseButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.containerView addSubview:self.purchaseButton];
    }

    // Add iPad-specific layout adaptations
    BOOL isIPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    CGFloat horizontalPadding = isIPad ? 40 : 16;
    CGFloat maxWidth = isIPad ? 600 : 400;
    
    // Container view constraints with iPad adaptations
    [NSLayoutConstraint activateConstraints:@[
        [self.containerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.containerView.topAnchor constraintEqualToAnchor:self.topAnchor constant:horizontalPadding],
        [self.containerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-horizontalPadding],
        [self.containerView.widthAnchor constraintLessThanOrEqualToConstant:maxWidth],
        [self.containerView.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-(horizontalPadding * 2)],
        [self.containerView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:horizontalPadding],
        [self.containerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-horizontalPadding]
    ]];
    
    // Content constraints with iPad adaptations
    CGFloat contentPadding = isIPad ? 24 : 16;
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.containerView.topAnchor constant:contentPadding],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:contentPadding],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-contentPadding],
        
        [self.descriptionLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:contentPadding/2],
        [self.descriptionLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:contentPadding],
        [self.descriptionLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-contentPadding],
        
        [self.priceLabel.topAnchor constraintEqualToAnchor:self.descriptionLabel.bottomAnchor constant:contentPadding],
        [self.priceLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:contentPadding],
        [self.priceLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-contentPadding],
        
        [self.deviceLimitLabel.topAnchor constraintEqualToAnchor:self.priceLabel.bottomAnchor constant:contentPadding/2],
        [self.deviceLimitLabel.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:contentPadding],
        [self.deviceLimitLabel.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-contentPadding],
        
        [self.purchaseButton.topAnchor constraintEqualToAnchor:self.deviceLimitLabel.bottomAnchor constant:contentPadding],
        [self.purchaseButton.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor constant:contentPadding],
        [self.purchaseButton.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor constant:-contentPadding],
        [self.purchaseButton.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor constant:-contentPadding],
        [self.purchaseButton.heightAnchor constraintEqualToConstant:isIPad ? 44 : 36]
    ]];
}

@end 