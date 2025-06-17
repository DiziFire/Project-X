#import "DevicesViewController.h"
#import "APIManager.h"

// Define cell identifiers
static NSString *const kDeviceTableCellIdentifier = @"DeviceTableCell";
static NSString *const kDeviceCardCellIdentifier = @"DeviceCardCell";

// Custom collection view cell for device cards
@interface DeviceCardCell : UICollectionViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *deviceNameLabel;
@property (nonatomic, strong) UILabel *deviceIdLabel;
@property (nonatomic, strong) UILabel *deviceModelLabel;
@property (nonatomic, strong) UILabel *lastSeenLabel;
@property (nonatomic, strong) UIView *statusBadge;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) void (^removeAction)(void);

- (void)configureWithDevice:(NSDictionary *)device isCurrentDevice:(BOOL)isCurrentDevice;
@end

@implementation DeviceCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    // Create card view with dynamic background color
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.layer.cornerRadius = 16.0;
    self.cardView.layer.masksToBounds = NO;
    
    // Add dynamic shadow
    self.cardView.layer.shadowRadius = 8.0;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 4);
    self.cardView.layer.shadowOpacity = 0.1;
    
    if (@available(iOS 13.0, *)) {
        self.cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.cardView.layer.shadowColor = [UIColor systemGrayColor].CGColor;
    } else {
        self.cardView.backgroundColor = [UIColor colorWithRed:0.12 green:0.15 blue:0.24 alpha:1.0];
        self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    }
    [self.contentView addSubview:self.cardView];
    
    // Create icon container with a softer color
    self.iconContainer = [[UIView alloc] init];
    self.iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconContainer.layer.cornerRadius = 30;
    
    if (@available(iOS 13.0, *)) {
        self.iconContainer.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:1.0]; // Dark mode
            } else {
                return [UIColor colorWithRed:0.92 green:0.92 blue:0.96 alpha:1.0]; // Light mode
            }
        }];
    } else {
        self.iconContainer.backgroundColor = [UIColor colorWithRed:0.08 green:0.1 blue:0.16 alpha:0.7];
    }
    [self.cardView addSubview:self.iconContainer];
    
    // Create icon image view with dynamic tint color
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    if (@available(iOS 13.0, *)) {
        self.iconImageView.tintColor = [UIColor systemBlueColor];
    } else {
        self.iconImageView.tintColor = [UIColor colorWithRed:0 green:0.76 blue:1.0 alpha:1.0]; // #00c3ff
    }
    [self.iconContainer addSubview:self.iconImageView];
    
    // Create device name label
    self.deviceNameLabel = [[UILabel alloc] init];
    self.deviceNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceNameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    if (@available(iOS 13.0, *)) {
        self.deviceNameLabel.textColor = [UIColor labelColor];
    } else {
        self.deviceNameLabel.textColor = [UIColor whiteColor];
    }
    [self.cardView addSubview:self.deviceNameLabel];
    
    // Create device ID label
    self.deviceIdLabel = [[UILabel alloc] init];
    self.deviceIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceIdLabel.font = [UIFont systemFontOfSize:12];
    if (@available(iOS 13.0, *)) {
        self.deviceIdLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.deviceIdLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    }
    [self.cardView addSubview:self.deviceIdLabel];
    
    // Create device model label
    self.deviceModelLabel = [[UILabel alloc] init];
    self.deviceModelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceModelLabel.font = [UIFont systemFontOfSize:14];
    if (@available(iOS 13.0, *)) {
        self.deviceModelLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.deviceModelLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    }
    [self.cardView addSubview:self.deviceModelLabel];
    
    // Create last seen label
    self.lastSeenLabel = [[UILabel alloc] init];
    self.lastSeenLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.lastSeenLabel.font = [UIFont systemFontOfSize:12];
    if (@available(iOS 13.0, *)) {
        self.lastSeenLabel.textColor = [UIColor tertiaryLabelColor];
    } else {
        self.lastSeenLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    }
    [self.cardView addSubview:self.lastSeenLabel];
    
    // Create status badge
    self.statusBadge = [[UIView alloc] init];
    self.statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBadge.layer.cornerRadius = 14.0; // Adjusted corner radius for larger badge
    self.statusBadge.layer.masksToBounds = YES;
    [self.cardView addSubview:self.statusBadge];
    
    // Create status label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.statusBadge addSubview:self.statusLabel];
    
    // Create remove button with dynamic colors
    UIButton *removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    removeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [removeButton setTitle:@"Remove" forState:UIControlStateNormal];
    removeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    removeButton.layer.cornerRadius = 10.0;
    removeButton.layer.masksToBounds = YES;
    
    // Add red tint to remove button
    if (@available(iOS 13.0, *)) {
        [removeButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        removeButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
    } else {
        [removeButton setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
        removeButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.1];
    }
    
    [removeButton addTarget:self action:@selector(removeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:removeButton];
    
    // Layout constraints for card view
    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
    ]];
    
    // Layout constraints for icon container and image
    [NSLayoutConstraint activateConstraints:@[
        [self.iconContainer.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:20],
        [self.iconContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.iconContainer.widthAnchor constraintEqualToConstant:60],
        [self.iconContainer.heightAnchor constraintEqualToConstant:60],
        
        [self.iconImageView.centerXAnchor constraintEqualToAnchor:self.iconContainer.centerXAnchor],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.iconContainer.centerYAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:35],
        [self.iconImageView.heightAnchor constraintEqualToConstant:35],
    ]];
    
    // Layout constraints for labels and badge
    [NSLayoutConstraint activateConstraints:@[
        [self.deviceNameLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:20],
        [self.deviceNameLabel.leadingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor constant:16],
        [self.deviceNameLabel.trailingAnchor constraintEqualToAnchor:self.statusBadge.leadingAnchor constant:-12],
        
        [self.deviceIdLabel.topAnchor constraintEqualToAnchor:self.deviceNameLabel.bottomAnchor constant:6],
        [self.deviceIdLabel.leadingAnchor constraintEqualToAnchor:self.deviceNameLabel.leadingAnchor],
        [self.deviceIdLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16],
        
        [self.deviceModelLabel.topAnchor constraintEqualToAnchor:self.deviceIdLabel.bottomAnchor constant:6],
        [self.deviceModelLabel.leadingAnchor constraintEqualToAnchor:self.deviceNameLabel.leadingAnchor],
        [self.deviceModelLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16],
        
        [self.lastSeenLabel.topAnchor constraintEqualToAnchor:self.deviceModelLabel.bottomAnchor constant:10],
        [self.lastSeenLabel.leadingAnchor constraintEqualToAnchor:self.deviceNameLabel.leadingAnchor],
        [self.lastSeenLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16],
        
        [self.statusBadge.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:20],
        [self.statusBadge.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.statusBadge.widthAnchor constraintEqualToConstant:78],
        [self.statusBadge.heightAnchor constraintEqualToConstant:28],
        
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.statusBadge.centerXAnchor],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.statusBadge.centerYAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusBadge.leadingAnchor constant:4],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusBadge.trailingAnchor constant:-4],
        
        [removeButton.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [removeButton.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [removeButton.topAnchor constraintEqualToAnchor:self.lastSeenLabel.bottomAnchor constant:20],
        [removeButton.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-20],
        [removeButton.heightAnchor constraintEqualToConstant:46],
    ]];
}

- (void)removeButtonTapped {
    if (self.removeAction) {
        self.removeAction();
    }
}

- (void)configureWithDevice:(NSDictionary *)device isCurrentDevice:(BOOL)isCurrentDevice {
    // Set device name
    NSString *deviceName = device[@"device_name"];
    self.deviceNameLabel.text = deviceName ?: @"Unknown Device";
    
    // Set device UUID (truncated for display)
    NSString *deviceUUID = device[@"device_uuid"];
    if (deviceUUID.length > 16) {
        NSString *truncatedUUID = [NSString stringWithFormat:@"ID: %@%@", 
                                 [deviceUUID substringToIndex:16], 
                                 @"..."];
        self.deviceIdLabel.text = truncatedUUID;
    } else {
        self.deviceIdLabel.text = [NSString stringWithFormat:@"ID: %@", deviceUUID ?: @"Unknown"];
    }
    
    // Set device model
    NSString *deviceModel = device[@"device_model"];
    self.deviceModelLabel.text = deviceModel ?: @"Unknown Type";
    
    // Add a special border for the current device
    if (isCurrentDevice) {
        if (@available(iOS 13.0, *)) {
            self.cardView.layer.borderWidth = 2.0;
            self.cardView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:1.0].CGColor; // #0078FF
        } else {
            self.cardView.layer.borderWidth = 2.0;
            self.cardView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:1.0].CGColor; // #0078FF
        }
    } else {
        self.cardView.layer.borderWidth = 0.0;
    }
    
    // Set last seen date with proper formatting
    // Check both possible field names from the API
    NSString *lastSeen = device[@"last_seen_at"] ?: device[@"last_seen"];
    if (lastSeen && ![lastSeen isKindOfClass:[NSNull class]] && ![lastSeen isEqualToString:@""]) {
        // Format date if available
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
        NSDate *lastSeenDate = [dateFormatter dateFromString:lastSeen];
        
        if (!lastSeenDate) {
            // Try alternative format without milliseconds
            dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
            lastSeenDate = [dateFormatter dateFromString:lastSeen];
        }
        
        if (lastSeenDate) {
            // Calculate time ago in a human-readable format
            NSTimeInterval timeSinceNow = -[lastSeenDate timeIntervalSinceNow];
            
            NSString *timeAgoString;
            if (timeSinceNow < 60) {
                timeAgoString = @"Just now";
            } else if (timeSinceNow < 3600) {
                int minutes = (int)(timeSinceNow / 60);
                timeAgoString = [NSString stringWithFormat:@"%d %@ ago", minutes, minutes == 1 ? @"minute" : @"minutes"];
            } else if (timeSinceNow < 86400) {
                int hours = (int)(timeSinceNow / 3600);
                timeAgoString = [NSString stringWithFormat:@"%d %@ ago", hours, hours == 1 ? @"hour" : @"hours"];
            } else if (timeSinceNow < 604800) {
                int days = (int)(timeSinceNow / 86400);
                timeAgoString = [NSString stringWithFormat:@"%d %@ ago", days, days == 1 ? @"day" : @"days"];
            } else {
                NSDateFormatter *displayFormatter = [[NSDateFormatter alloc] init];
                displayFormatter.dateStyle = NSDateFormatterMediumStyle;
                displayFormatter.timeStyle = NSDateFormatterShortStyle;
                timeAgoString = [displayFormatter stringFromDate:lastSeenDate];
            }
            
            self.lastSeenLabel.text = [NSString stringWithFormat:@"Last seen: %@", timeAgoString];
        } else {
            self.lastSeenLabel.text = @"Last seen: Unknown";
        }
    } else {
        self.lastSeenLabel.text = @"Last seen: Never";
    }
    
    // Determine if device is active based on status and last_seen_at
    BOOL isActive = NO;
    
    // First check explicit status field
    NSString *status = device[@"status"];
    if (status && ![status isKindOfClass:[NSNull class]]) {
        isActive = [status isEqualToString:@"online"] || [status isEqualToString:@"active"];
    } else if (device[@"is_active"] && ![device[@"is_active"] isKindOfClass:[NSNull class]]) {
        // Check boolean is_active field
        isActive = [device[@"is_active"] boolValue];
    } else if (lastSeen && ![lastSeen isKindOfClass:[NSNull class]] && ![lastSeen isEqualToString:@""]) {
        // If no explicit status, determine based on last seen time
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
        NSDate *lastSeenDate = [dateFormatter dateFromString:lastSeen];
        
        if (!lastSeenDate) {
            // Try alternative format without milliseconds
            dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
            lastSeenDate = [dateFormatter dateFromString:lastSeen];
        }
        
        if (lastSeenDate) {
            // Consider active if seen in the last 5 minutes
            NSTimeInterval timeSinceLastSeen = -[lastSeenDate timeIntervalSinceNow];
            isActive = (timeSinceLastSeen < 300); // 5 minutes in seconds
        }
    }
    
    // Set status badge with dynamic colors
    // Remove any existing gradient layers
    for (CALayer *layer in self.statusBadge.layer.sublayers) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }
    
    // Instead of using gradient, use a solid color as shown in screenshot
    if (isCurrentDevice) {
        // Current device styling with solid color
        if (@available(iOS 13.0, *)) {
            self.statusBadge.backgroundColor = [UIColor colorWithRed:0.0 green:0.81 blue:0.41 alpha:1.0]; // #00CF69
            self.statusLabel.text = @"CURRENT";
            self.statusLabel.textColor = [UIColor whiteColor];
        } else {
            self.statusBadge.backgroundColor = [UIColor colorWithRed:0.0 green:0.81 blue:0.41 alpha:1.0]; // #00CF69
            self.statusLabel.text = @"CURRENT";
            self.statusLabel.textColor = [UIColor whiteColor];
        }
        
        // Set device icon
        if (@available(iOS 13.0, *)) {
            self.iconImageView.image = [UIImage systemImageNamed:@"applelogo"];
        }
    } else if (isActive) {
        // Active device styling with solid color
        if (@available(iOS 13.0, *)) {
            self.statusBadge.backgroundColor = [UIColor colorWithRed:0.0 green:0.81 blue:0.41 alpha:1.0]; // #00CF69
            self.statusLabel.text = @"ACTIVE";
            self.statusLabel.textColor = [UIColor whiteColor];
        } else {
            self.statusBadge.backgroundColor = [UIColor colorWithRed:0.0 green:0.81 blue:0.41 alpha:1.0]; // #00CF69
            self.statusLabel.text = @"ACTIVE";
            self.statusLabel.textColor = [UIColor whiteColor];
        }
        
        // Set device icon
        if (@available(iOS 13.0, *)) {
            self.iconImageView.image = [UIImage systemImageNamed:@"applelogo"];
        }
    } else {
        // Inactive device styling with solid color
        if (@available(iOS 13.0, *)) {
            self.statusBadge.backgroundColor = [UIColor systemGrayColor];
            self.statusLabel.text = @"INACTIVE";
            self.statusLabel.textColor = [UIColor whiteColor];
        } else {
            self.statusBadge.backgroundColor = [UIColor colorWithWhite:0.6 alpha:1.0];
            self.statusLabel.text = @"INACTIVE";
            self.statusLabel.textColor = [UIColor whiteColor];
        }
        
        // Set device icon
        if (@available(iOS 13.0, *)) {
            self.iconImageView.image = [UIImage systemImageNamed:@"applelogo"];
            // For inactive devices, use a grayed out appearance
            self.iconImageView.tintColor = [UIColor systemGrayColor];
        }
    }
    
    // Remove gradient code since we're using solid colors
    // Instead add shadow to make it pop
    self.statusBadge.layer.shadowColor = [UIColor blackColor].CGColor;
    self.statusBadge.layer.shadowOffset = CGSizeMake(0, 2);
    self.statusBadge.layer.shadowRadius = 3.0;
    self.statusBadge.layer.shadowOpacity = 0.1;
    self.statusBadge.layer.masksToBounds = NO;
    
    // For current device, we'll disable the remove action
    if (isCurrentDevice) {
        self.removeAction = nil;
        
        // Find and update the remove button
        for (UIView *subview in self.cardView.subviews) {
            if ([subview isKindOfClass:[UIButton class]]) {
                UIButton *removeButton = (UIButton *)subview;
                removeButton.enabled = NO;
                if (@available(iOS 13.0, *)) {
                    removeButton.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.1];
                    [removeButton setTitleColor:[UIColor systemGrayColor] forState:UIControlStateNormal];
                } else {
                    removeButton.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.1];
                    [removeButton setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateNormal];
                }
            }
        }
    }
}

@end

@implementation DevicesViewController

#pragma mark - Initialization

- (instancetype)initWithAuthToken:(NSString *)authToken {
    self = [super init];
    if (self) {
        _authToken = authToken;
        _devices = @[];
        _deviceLimit = 0;
        
        // Get current device UUID for comparison
        NSUUID *uuid = [[UIDevice currentDevice] identifierForVendor];
        if (uuid) {
            _currentDeviceUUID = [uuid UUIDString];
        }
    }
    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set up navigation
    self.title = @"Manage Devices";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    
    // Add a refresh button
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh 
                                                                                   target:self 
                                                                                   action:@selector(refreshDevices)];
    self.navigationItem.rightBarButtonItem = refreshButton;
    
    // Set background color that adapts to system theme
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1.0];
    }
    
    // Add iPad-specific layout adaptations
    BOOL isIPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    
    // Create flow layout with iPad adaptations
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 16;
    layout.minimumLineSpacing = 16;
    
    // Calculate item size based on device type
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat itemWidth;
    
    if (isIPad) {
        // For iPad, show 2 or 3 items per row depending on width
        NSInteger itemsPerRow = screenWidth >= 1024 ? 3 : 2;
        itemWidth = (screenWidth - (16 * (itemsPerRow + 1))) / itemsPerRow;
    } else {
        // For iPhone, show 1 item per row
        itemWidth = screenWidth - 32;
    }
    
    layout.itemSize = CGSizeMake(itemWidth, 140);
    layout.sectionInset = UIEdgeInsetsMake(16, 16, 16, 16);
    
    // Create collection view with layout
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [self.collectionView registerClass:[DeviceCardCell class] forCellWithReuseIdentifier:kDeviceCardCellIdentifier];
    [self.view addSubview:self.collectionView];
    
    // Setup constraints with iPad adaptations
    CGFloat topPadding = isIPad ? 32 : 16;
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:topPadding],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    // Add refresh control
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshDevices) forControlEvents:UIControlEventValueChanged];
    self.collectionView.refreshControl = self.refreshControl;
    
    // Set up activity indicator with dynamic colors
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    if (@available(iOS 13.0, *)) {
        self.activityIndicator.color = [UIColor systemBlueColor];
    } else {
        self.activityIndicator.color = [UIColor colorWithRed:0 green:0.76 blue:1.0 alpha:1.0]; // #00c3ff
    }
    [self.view addSubview:self.activityIndicator];
    
    // Set up empty state label with dynamic colors
    self.emptyStateLabel = [[UILabel alloc] init];
    self.emptyStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateLabel.font = [UIFont systemFontOfSize:16];
    self.emptyStateLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyStateLabel.text = @"No devices found";
    if (@available(iOS 13.0, *)) {
        self.emptyStateLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.emptyStateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    }
    self.emptyStateLabel.hidden = YES;
    [self.view addSubview:self.emptyStateLabel];
    
    // Layout constraints for activity indicator and empty state label
    [NSLayoutConstraint activateConstraints:@[
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        
        [self.emptyStateLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyStateLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    
    // Load devices
    [self refreshDevices];
}

#pragma mark - Device Data Management

- (void)refreshDevices {
    // Show activity indicator
    [self.activityIndicator startAnimating];
    
    // Hide empty state label while loading
    self.emptyStateLabel.hidden = YES;
    
    // Set loading state for device count display
    self.deviceCountLabel.text = @"Fetching...";
    // Apply smaller font size for the loading text
    self.deviceCountLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:10];
    
    self.deviceSlashLabel.text = @"";
    self.deviceLimitLabel.text = @"";
    self.deviceLimitProgressView.progress = 0.0;
    
    // Get user data from APIManager
    APIManager *apiManager = [APIManager sharedManager];
    NSDictionary *userData = [apiManager currentUserData];
    
    // First fetch plan data (exactly as AccountViewController does)
    [apiManager fetchUserPlanWithToken:self.authToken completion:^(NSDictionary *planData, NSError *planError) {
        // Use exact same approach as AccountViewController to get device count
        NSNumber *deviceLimit = nil;
        NSNumber *currentDeviceCount = nil;
        BOOL usingCustomDeviceLimit = NO;
        
        // First check if we have the using_custom_device_limit flag (matching AccountViewController)
        if (planData && planData[@"using_custom_device_limit"] && 
            ![planData[@"using_custom_device_limit"] isKindOfClass:[NSNull class]]) {
            
            usingCustomDeviceLimit = [planData[@"using_custom_device_limit"] boolValue];
        }
        
        // Get device limit - exactly match AccountViewController approach
        // First check for custom device limit field (from API)
        if (userData && userData[@"custom_device_limit"] && 
            ![userData[@"custom_device_limit"] isKindOfClass:[NSNull class]] && 
            ![userData[@"custom_device_limit"] isEqual:@""] &&
            [userData[@"custom_device_limit"] intValue] > 0) {
            
            deviceLimit = userData[@"custom_device_limit"];
        } 
        // If no custom limit, try to get from device_limit field
        else if (userData && userData[@"device_limit"] && 
                 ![userData[@"device_limit"] isKindOfClass:[NSNull class]] && 
                 ![userData[@"device_limit"] isEqual:@""] &&
                 [userData[@"device_limit"] intValue] > 0) {
            
            deviceLimit = userData[@"device_limit"];
        }
        // If still no limit, try to get from plan data
        else if (planData) {
            // Check for plan max_devices in different possible locations
            NSNumber *planDeviceLimit = nil;
            
            // Try format 1: plan data in planData[@"plan"]
            if (planData[@"plan"] && [planData[@"plan"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *plan = planData[@"plan"];
                
                // Check for max_devices with value > 0
                if (plan[@"max_devices"] && 
                    ![plan[@"max_devices"] isKindOfClass:[NSNull class]] && 
                    ![plan[@"max_devices"] isEqual:@""]) {
                    
                    // Convert to NSNumber if it's a string
                    if ([plan[@"max_devices"] isKindOfClass:[NSString class]]) {
                        int intValue = [plan[@"max_devices"] intValue];
                        planDeviceLimit = @(intValue);
                    } else if ([plan[@"max_devices"] isKindOfClass:[NSNumber class]]) {
                        planDeviceLimit = plan[@"max_devices"];
                    }
                } 
                // Check for device_limit with value > 0
                else if (plan[@"device_limit"] && 
                         ![plan[@"device_limit"] isKindOfClass:[NSNull class]] && 
                         ![plan[@"device_limit"] isEqual:@""]) {
                    
                    // Convert to NSNumber if it's a string
                    if ([plan[@"device_limit"] isKindOfClass:[NSString class]]) {
                        int intValue = [plan[@"device_limit"] intValue];
                        planDeviceLimit = @(intValue);
                    } else if ([plan[@"device_limit"] isKindOfClass:[NSNumber class]]) {
                        planDeviceLimit = plan[@"device_limit"];
                    }
                } 
                // Check for devices with value > 0
                else if (plan[@"devices"] && 
                         ![plan[@"devices"] isKindOfClass:[NSNull class]] && 
                         ![plan[@"devices"] isEqual:@""]) {
                    
                    // Convert to NSNumber if it's a string
                    if ([plan[@"devices"] isKindOfClass:[NSString class]]) {
                        int intValue = [plan[@"devices"] intValue];
                        planDeviceLimit = @(intValue);
                    } else if ([plan[@"devices"] isKindOfClass:[NSNumber class]]) {
                        planDeviceLimit = plan[@"devices"];
                    }
                }
            } 
            // Try format 2: plan data directly in planData
            else if (planData[@"max_devices"] && 
                     ![planData[@"max_devices"] isKindOfClass:[NSNull class]] && 
                     ![planData[@"max_devices"] isEqual:@""]) {
                
                // Convert to NSNumber if it's a string
                if ([planData[@"max_devices"] isKindOfClass:[NSString class]]) {
                    planDeviceLimit = @([planData[@"max_devices"] intValue]);
                } else {
                    planDeviceLimit = planData[@"max_devices"];
                }
            } 
            else if (planData[@"device_limit"] && 
                     ![planData[@"device_limit"] isKindOfClass:[NSNull class]] && 
                     ![planData[@"device_limit"] isEqual:@""]) {
                
                // Convert to NSNumber if it's a string
                if ([planData[@"device_limit"] isKindOfClass:[NSString class]]) {
                    planDeviceLimit = @([planData[@"device_limit"] intValue]);
                } else {
                    planDeviceLimit = planData[@"device_limit"];
                }
            } 
            else if (planData[@"devices"] && 
                     ![planData[@"devices"] isKindOfClass:[NSNull class]] && 
                     ![planData[@"devices"] isEqual:@""]) {
                
                // Convert to NSNumber if it's a string
                if ([planData[@"devices"] isKindOfClass:[NSString class]]) {
                    planDeviceLimit = @([planData[@"devices"] intValue]);
                } else {
                    planDeviceLimit = planData[@"devices"];
                }
            }
            
            // If we found a valid plan device limit, use it
            if (planDeviceLimit) {
                deviceLimit = planDeviceLimit;
            }
        }
        
        // Set a default limit if none was found
        if (!deviceLimit || [deviceLimit intValue] <= 0) {
            deviceLimit = @1; // Default to 1 device if no valid limit found
        }
        
        // Safely get the current device count - exactly match AccountViewController approach
        if (userData && userData[@"active_devices_count"] && 
            ![userData[@"active_devices_count"] isKindOfClass:[NSNull class]] &&
            ![userData[@"active_devices_count"] isEqual:@""]) {
            
            currentDeviceCount = userData[@"active_devices_count"];
        } else if (planData && planData[@"active_devices_count"] && 
                ![planData[@"active_devices_count"] isKindOfClass:[NSNull class]] &&
                ![planData[@"active_devices_count"] isEqual:@""]) {
            
            currentDeviceCount = planData[@"active_devices_count"];
        } else {
            // Default to 0 if no data available (match AccountViewController)
            currentDeviceCount = @0;
        }
        
        // Ensure we have NSNumber objects instead of strings for both counts
        if ([currentDeviceCount isKindOfClass:[NSString class]]) {
            currentDeviceCount = @([currentDeviceCount intValue]);
        }
        
        if ([deviceLimit isKindOfClass:[NSString class]]) {
            deviceLimit = @([deviceLimit intValue]);
        }
        
        // Now that we have accurate count data, fetch the actual devices
        [apiManager getUserDevices:^(NSArray *devices, NSInteger unusedDeviceLimit, NSError *error) {
            // Update UI on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                // Stop loading indicators
                [self.activityIndicator stopAnimating];
                [self.refreshControl endRefreshing];
                
                if (error) {
                    self.emptyStateLabel.text = @"Error loading devices";
                    self.emptyStateLabel.hidden = NO;
                    return;
                }
                
                // Update data
                self.devices = devices;
                
                // Set device limit from data fetched above (matching AccountViewController approach)
                self.deviceLimit = [deviceLimit integerValue];
                
                // Update the UI with the correct values
                NSInteger actualDeviceCount = [currentDeviceCount integerValue];
                NSInteger actualDeviceLimit = [deviceLimit integerValue];
                
                // Format the display text the same way as in AccountViewController
                self.deviceCountLabel.text = [NSString stringWithFormat:@"%ld", (long)actualDeviceCount];
                // Restore original font size when showing actual device count
                self.deviceCountLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:18];
                
                // Update device limit label with custom indicator if needed
                if (usingCustomDeviceLimit) {
                    self.deviceLimitLabel.text = [NSString stringWithFormat:@"%ld (custom)", (long)actualDeviceLimit];
                } else {
                    self.deviceLimitLabel.text = [NSString stringWithFormat:@"%ld", (long)actualDeviceLimit];
                }
                
                // Animate the progress change
                [UIView animateWithDuration:0.5 animations:^{
                    float progress = actualDeviceLimit > 0 ? (float)actualDeviceCount / (float)actualDeviceLimit : 0.0;
                    // Cap at 100%
                    progress = MIN(progress, 1.0);
                    self.deviceLimitProgressView.progress = progress;
                }];
                
                // Update empty state based on device list (not count)
                if (devices.count == 0) {
                    self.emptyStateLabel.hidden = NO;
                } else {
                    self.emptyStateLabel.hidden = YES;
                }
                
                // Reload collection view
                [self.collectionView reloadData];
            });
        }];
    }];
}

#pragma mark - Device Count Display Setup

- (void)setupDeviceCountDisplay {
    // Create device count display with a clean, simple look
    // Create device count label with dynamic colors
    self.deviceCountLabel = [[UILabel alloc] init];
    self.deviceCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceCountLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:18];
    self.deviceCountLabel.textAlignment = NSTextAlignmentRight;
    self.deviceCountLabel.text = @"Fetching...";
    
    // Apply smaller font size when showing "Fetching..." text
    if ([self.deviceCountLabel.text isEqualToString:@"Fetching..."]) {
        self.deviceCountLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:10];
    }
    
    if (@available(iOS 13.0, *)) {
        self.deviceCountLabel.textColor = [UIColor systemBlueColor];
    } else {
        self.deviceCountLabel.textColor = [UIColor colorWithRed:0 green:0.76 blue:1.0 alpha:1.0]; // #00c3ff
    }
    [self.view addSubview:self.deviceCountLabel];
    
    // Create slash label with dynamic colors
    self.deviceSlashLabel = [[UILabel alloc] init];
    self.deviceSlashLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceSlashLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    self.deviceSlashLabel.textAlignment = NSTextAlignmentCenter;
    self.deviceSlashLabel.text = @"";
    if (@available(iOS 13.0, *)) {
        self.deviceSlashLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.deviceSlashLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    }
    [self.view addSubview:self.deviceSlashLabel];
    
    // Create device limit label with dynamic colors
    self.deviceLimitLabel = [[UILabel alloc] init];
    self.deviceLimitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceLimitLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    self.deviceLimitLabel.textAlignment = NSTextAlignmentLeft;
    self.deviceLimitLabel.text = @"";
    if (@available(iOS 13.0, *)) {
        self.deviceLimitLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        self.deviceLimitLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    }
    [self.view addSubview:self.deviceLimitLabel];
    
    // Create "DEVICES USED" label with dynamic colors
    UILabel *devicesUsedLabel = [[UILabel alloc] init];
    devicesUsedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    devicesUsedLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    devicesUsedLabel.textAlignment = NSTextAlignmentCenter;
    devicesUsedLabel.text = @"DEVICES USED";
    if (@available(iOS 13.0, *)) {
        devicesUsedLabel.textColor = [UIColor tertiaryLabelColor];
    } else {
        devicesUsedLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    }
    [self.view addSubview:devicesUsedLabel];
    
    // Create progress view with gradient
    // Create progress view with dynamic colors
    self.deviceLimitProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.deviceLimitProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        self.deviceLimitProgressView.trackTintColor = [UIColor tertiarySystemFillColor];
    } else {
        self.deviceLimitProgressView.trackTintColor = [UIColor colorWithRed:0.24 green:0.24 blue:0.4 alpha:0.2];
    }
    
    // Create gradient layer for progress view with dynamic colors
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = CGRectMake(0, 0, self.view.bounds.size.width, 4);
    
    if (@available(iOS 13.0, *)) {
        gradientLayer.colors = @[
            (id)[UIColor systemBlueColor].CGColor,
            (id)[UIColor systemPurpleColor].CGColor
        ];
    } else {
        gradientLayer.colors = @[
            (id)[UIColor colorWithRed:0 green:0.76 blue:1.0 alpha:1.0].CGColor,  // #00c3ff
            (id)[UIColor colorWithRed:1.0 green:0 blue:1.0 alpha:1.0].CGColor    // #ff00ff
        ];
    }
    
    gradientLayer.startPoint = CGPointMake(0, 0.5);
    gradientLayer.endPoint = CGPointMake(1.0, 0.5);
    
    // Apply gradient to progress view
    UIView *gradientView = [[UIView alloc] init];
    gradientView.translatesAutoresizingMaskIntoConstraints = NO;
    [gradientView.layer addSublayer:gradientLayer];
    gradientView.clipsToBounds = YES;
    [self.view addSubview:gradientView];
    
    // Add progress view
    self.deviceLimitProgressView.progress = 0.0;
    self.deviceLimitProgressView.layer.cornerRadius = 2.0;
    self.deviceLimitProgressView.clipsToBounds = YES;
    [self.view addSubview:self.deviceLimitProgressView];
    
    // Layout constraints for the device count display
    [NSLayoutConstraint activateConstraints:@[
        // Position deviceCountLabel in the center of the view horizontally
        [self.deviceCountLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-10],
        [self.deviceCountLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        
        // Position the slash after deviceCountLabel
        [self.deviceSlashLabel.centerYAnchor constraintEqualToAnchor:self.deviceCountLabel.centerYAnchor],
        [self.deviceSlashLabel.leadingAnchor constraintEqualToAnchor:self.deviceCountLabel.trailingAnchor constant:2],
        
        // Position deviceLimitLabel after the slash
        [self.deviceLimitLabel.centerYAnchor constraintEqualToAnchor:self.deviceCountLabel.centerYAnchor],
        [self.deviceLimitLabel.leadingAnchor constraintEqualToAnchor:self.deviceSlashLabel.trailingAnchor constant:2],
        
        // Position devicesUsedLabel below the count display
        [devicesUsedLabel.topAnchor constraintEqualToAnchor:self.deviceCountLabel.bottomAnchor constant:4],
        [devicesUsedLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        // Position progress view
        [self.deviceLimitProgressView.topAnchor constraintEqualToAnchor:devicesUsedLabel.bottomAnchor constant:8],
        [self.deviceLimitProgressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.deviceLimitProgressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.deviceLimitProgressView.heightAnchor constraintEqualToConstant:4],
        
        // Position gradient view to match progress view
        [gradientView.topAnchor constraintEqualToAnchor:self.deviceLimitProgressView.topAnchor],
        [gradientView.leadingAnchor constraintEqualToAnchor:self.deviceLimitProgressView.leadingAnchor],
        [gradientView.trailingAnchor constraintEqualToAnchor:self.deviceLimitProgressView.trailingAnchor],
        [gradientView.bottomAnchor constraintEqualToAnchor:self.deviceLimitProgressView.bottomAnchor],
    ]];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.devices.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DeviceCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kDeviceCardCellIdentifier forIndexPath:indexPath];
    
    // Configure cell
    NSDictionary *device = self.devices[indexPath.row];
    NSString *deviceUUID = device[@"device_uuid"];
    BOOL isCurrentDevice = [deviceUUID isEqualToString:self.currentDeviceUUID];
    
    // Configure the cell with device data
    [cell configureWithDevice:device isCurrentDevice:isCurrentDevice];
    
    // Set up remove action
    __weak typeof(self) weakSelf = self;
    cell.removeAction = ^{
        // Check if this is the current device
        if (isCurrentDevice) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Current Device"
                                                                           message:@"You cannot remove the device you're currently using."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        // Show removal confirmation alert
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove Device"
                                                                       message:@"Are you sure you want to remove this device?"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancelAction];
        
        UIAlertAction *removeAction = [UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [weakSelf removeDeviceWithUUID:deviceUUID];
        }];
        [alert addAction:removeAction];
        
        [weakSelf presentViewController:alert animated:YES completion:nil];
    };
    
    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    // Calculate cell size based on the collection view width
    CGFloat width = collectionView.bounds.size.width;
    return CGSizeMake(width, 210); // Increased height for better spacing
}

#pragma mark - Device Management

- (void)removeDeviceWithUUID:(NSString *)deviceUUID {
    // Show activity indicator
    [self.activityIndicator startAnimating];
    
    // Use APIManager to remove device
    APIManager *apiManager = [APIManager sharedManager];
    
    [apiManager removeUserDevice:deviceUUID completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            
            if (error || !success) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:@"Failed to remove device. Please try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            // Show success message
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                           message:@"Device has been removed."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
            
            // Refresh devices list
            [self refreshDevices];
        });
    }];
}

// Add iPad orientation support
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskPortrait;
}

// Update collection view layout on rotation
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        BOOL isIPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
        UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
        
        CGFloat screenWidth = size.width;
        CGFloat itemWidth;
        
        if (isIPad) {
            NSInteger itemsPerRow = screenWidth >= 1024 ? 3 : 2;
            itemWidth = (screenWidth - (16 * (itemsPerRow + 1))) / itemsPerRow;
        } else {
            itemWidth = screenWidth - 32;
        }
        
        layout.itemSize = CGSizeMake(itemWidth, 140);
        [self.collectionView.collectionViewLayout invalidateLayout];
    } completion:nil];
}

@end