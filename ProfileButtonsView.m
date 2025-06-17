#import "ProfileButtonsView.h"

@interface ProfileButtonsView ()

@property (nonatomic, strong) UIButton *addProfileButton;
@property (nonatomic, strong) UIButton *manageProfilesButton;
@property (nonatomic, strong) UIStackView *buttonStack;

@end

@implementation ProfileButtonsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        [self setupButtons];
    }
    return self;
}

- (void)setupButtons {
    // Create container view
    self.backgroundColor = [UIColor clearColor];
    
    // Create stack view for buttons
    self.buttonStack = [[UIStackView alloc] init];
    self.buttonStack.axis = UILayoutConstraintAxisVertical;
    self.buttonStack.spacing = 10;
    self.buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.buttonStack];
    
    // Create buttons
    self.addProfileButton = [self createButtonWithIcon:@"plus.circle.fill" title:@"New"];
    self.manageProfilesButton = [self createButtonWithIcon:@"folder.fill" title:@"Profiles"];
    
    // Add buttons to stack
    [self.buttonStack addArrangedSubview:self.addProfileButton];
    [self.buttonStack addArrangedSubview:self.manageProfilesButton];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.buttonStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.buttonStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.buttonStack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.buttonStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (UIButton *)createButtonWithIcon:(NSString *)iconName title:(NSString *)title {
    // Create button configuration
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    
    // Configure background
    config.background.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.5];
    config.background.cornerRadius = 22;
    
    // Configure image and text
    UIImage *icon = [UIImage systemImageNamed:iconName];
    config.image = icon;
    config.title = title;
    config.imagePlacement = NSDirectionalRectEdgeTop;
    config.imagePadding = 8;
    
    // Configure text attributes
    UIFont *font = [UIFont systemFontOfSize:8 weight:UIFontWeightMedium];
    NSDictionary *attributeDict = @{NSFontAttributeName: font};
    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:attributeDict];
    config.attributedTitle = attributedTitle;
    
    // Set colors
    config.baseForegroundColor = [UIColor systemBlueColor];
    
    // Create button with configuration
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add targets
    if ([title isEqualToString:@"New"]) {
        [button addTarget:self action:@selector(newProfileTapped) forControlEvents:UIControlEventTouchUpInside];
    } else {
        [button addTarget:self action:@selector(manageProfilesTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    
    // Set size constraints
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:45],
        [button.heightAnchor constraintEqualToConstant:45]
    ]];
    
    return button;
}

#pragma mark - Button Actions

- (void)newProfileTapped {
    if (self.onNewProfileTapped) {
        self.onNewProfileTapped();
    }
}

- (void)manageProfilesTapped {
    if (self.onManageProfilesTapped) {
        self.onManageProfilesTapped();
    }
}

@end 