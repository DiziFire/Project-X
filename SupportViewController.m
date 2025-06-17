#import "SupportViewController.h"
#import "APIManager.h"
#import <objc/runtime.h>

// Forward declarations
@interface BroadcastTableViewCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *contentLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *unreadIndicator;
- (void)configureCellWithBroadcast:(NSDictionary *)broadcast;
@end

@interface TicketTableViewCell : UITableViewCell
@property (nonatomic, strong) UILabel *subjectLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *categoryLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *replyIndicator;
- (void)configureCellWithTicket:(NSDictionary *)ticket;
@end

@interface CreateTicketViewController : UIViewController
@property (nonatomic, copy) void (^ticketCreatedHandler)(void);
@end

@interface TicketDetailViewController : UIViewController
@property (nonatomic, strong) NSNumber *ticketId;
@property (nonatomic, copy) void (^ticketUpdatedHandler)(void);
@end

@interface BroadcastDetailViewController : UIViewController
@property (nonatomic, strong) NSNumber *broadcastId;
@end

@interface SupportViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *broadcastContainer;
@property (nonatomic, strong) UIView *ticketsContainer;
@property (nonatomic, strong) UITableView *broadcastTableView;
@property (nonatomic, strong) UITableView *ticketsTableView;
@property (nonatomic, strong) UIButton *createTicketButton;
@property (nonatomic, strong) UILabel *broadcastsHeaderLabel;
@property (nonatomic, strong) UILabel *ticketsHeaderLabel;
@property (nonatomic, strong) UIRefreshControl *broadcastRefreshControl;
@property (nonatomic, strong) UIRefreshControl *ticketsRefreshControl;
@property (nonatomic, strong) UIButton *expandBroadcastsButton;
@property (nonatomic, strong) UIActivityIndicatorView *broadcastsLoadingIndicator;
@property (nonatomic, strong) UIActivityIndicatorView *ticketsLoadingIndicator;
@property (nonatomic, strong) UILabel *noBroadcastsLabel;
@property (nonatomic, strong) UILabel *noTicketsLabel;

@property (nonatomic, strong) NSArray *broadcasts;
@property (nonatomic, strong) NSArray *tickets;
@property (nonatomic, assign) BOOL isBroadcastsExpanded;
@property (nonatomic, assign) CGFloat defaultBroadcastHeight;
@property (nonatomic, assign) CGFloat expandedBroadcastHeight;
@end

@implementation SupportViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Support";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Add Telegram button to left side of navigation bar
    UIButton *telegramButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [telegramButton setImage:[UIImage systemImageNamed:@"paperplane.fill"] forState:UIControlStateNormal];
    telegramButton.tintColor = [UIColor systemBlueColor];
    telegramButton.frame = CGRectMake(0, 0, 30, 30);
    
    // Add a glow effect to the telegram button
    telegramButton.layer.shadowColor = [UIColor systemBlueColor].CGColor;
    telegramButton.layer.shadowOffset = CGSizeMake(0, 0);
    telegramButton.layer.shadowOpacity = 0.8;
    telegramButton.layer.shadowRadius = 4.0;
    
    [telegramButton addTarget:self action:@selector(telegramButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *telegramBarButton = [[UIBarButtonItem alloc] initWithCustomView:telegramButton];
    self.navigationItem.leftBarButtonItem = telegramBarButton;
    
    // Add account button to navigation bar
    UIBarButtonItem *accountButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"] 
                                                       style:UIBarButtonItemStylePlain 
                                                      target:self 
                                                      action:@selector(navigateToAccountTab)];
    // Add a glow effect to the account button
    UIButton *accountButtonView = [accountButton valueForKey:@"_view"];
    if (accountButtonView) {
        accountButtonView.tintColor = [UIColor systemBlueColor];
        accountButtonView.layer.shadowColor = [UIColor systemBlueColor].CGColor;
        accountButtonView.layer.shadowOffset = CGSizeMake(0, 0);
        accountButtonView.layer.shadowOpacity = 0.8;
        accountButtonView.layer.shadowRadius = 4.0;
    }
    self.navigationItem.rightBarButtonItem = accountButton;
    
    // Initialize properties
    self.broadcasts = @[];
    self.tickets = @[];
    self.isBroadcastsExpanded = NO;
    self.defaultBroadcastHeight = 0.2; // 20% of screen height
    self.expandedBroadcastHeight = 0.6; // 60% of screen height
    self.hasShownOfflineAlert = NO;
    
    [self setupUI];
    
    // Add refresh controls
    self.broadcastRefreshControl = [[UIRefreshControl alloc] init];
    [self.broadcastRefreshControl addTarget:self action:@selector(loadBroadcasts) forControlEvents:UIControlEventValueChanged];
    [self.broadcastTableView addSubview:self.broadcastRefreshControl];
    
    self.ticketsRefreshControl = [[UIRefreshControl alloc] init];
    [self.ticketsRefreshControl addTarget:self action:@selector(loadTickets) forControlEvents:UIControlEventValueChanged];
    [self.ticketsTableView addSubview:self.ticketsRefreshControl];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Reset the offline alert flag when the view appears
    self.hasShownOfflineAlert = NO;
    
    // Check internet connectivity before loading data
    [self checkInternetConnectivity];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Cancel any ongoing connectivity task when view disappears
    if (self.connectivityTask) {
        [self.connectivityTask cancel];
        self.connectivityTask = nil;
    }
}

#pragma mark - Internet Connectivity

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
        [self handleOfflineState];
        return;
    }
    
    if (!baseURL) {
        [self handleOfflineState];
        return;
    }
    
    // Create a URL for connectivity check
    NSURL *url = [NSURL URLWithString:baseURL];
    if (!url) {
        [self handleOfflineState];
        return;
    }
    
    // Create and start request
    NSURLRequest *request = [NSURLRequest requestWithURL:url 
                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                        timeoutInterval:4.0];
    
    // Use a weak reference to self to avoid retain cycles
    __weak typeof(self) weakSelf = self;
    
    self.connectivityTask = [[NSURLSession sharedSession] dataTaskWithRequest:request 
                                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Get back to main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            if (error) {
                [strongSelf handleOfflineState];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
                [strongSelf handleOnlineState];
            } else {
                [strongSelf handleOfflineState];
            }
        });
    }];
    
    [self.connectivityTask resume];
}

- (void)handleOnlineState {
    // User is online, load data
    [self loadData];
}

- (void)handleOfflineState {
    // Only show the alert once per tab open
    if (!self.hasShownOfflineAlert) {
        [self showOfflineAlert];
        self.hasShownOfflineAlert = YES;
    }
    
    // Update UI to show offline state
    [self updateUIForOfflineState];
}

- (void)showOfflineAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Offline" 
                                                               message:@"Use internet for accessing support features" 
                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateUIForOfflineState {
    // Stop loading indicators
    [self.broadcastsLoadingIndicator stopAnimating];
    [self.ticketsLoadingIndicator stopAnimating];
    [self.broadcastRefreshControl endRefreshing];
    [self.ticketsRefreshControl endRefreshing];
    
    // Show offline messages
    self.noBroadcastsLabel.text = @"Offline: Use internet for accessing broadcasts";
    self.noBroadcastsLabel.hidden = NO;
    
    self.noTicketsLabel.text = @"Offline: Use internet for accessing support tickets";
    self.noTicketsLabel.hidden = NO;
}

- (void)setupUI {
    // Replace the hardcoded gradient with a dynamic color
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = self.view.bounds;
    
    if (@available(iOS 13.0, *)) {
        gradientLayer.colors = @[(id)[UIColor systemBackgroundColor].CGColor,
                               (id)[UIColor secondarySystemBackgroundColor].CGColor];
    } else {
        gradientLayer.colors = @[(id)[UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0].CGColor,
                               (id)[UIColor colorWithRed:0.98 green:0.98 blue:1.0 alpha:1.0].CGColor];
    }
    
    gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    [self.view.layer insertSublayer:gradientLayer atIndex:0];
    
    // Create container view
    self.containerView = [[UIView alloc] init];
    self.containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.containerView];
    
    // Setup broadcast container with enhanced card-like appearance
    self.broadcastContainer = [[UIView alloc] init];
    self.broadcastContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.broadcastContainer.backgroundColor = [UIColor systemBackgroundColor];
    self.broadcastContainer.layer.cornerRadius = 16;
    self.broadcastContainer.clipsToBounds = YES;
    
    // Replace hardcoded shadow colors with dynamic colors
    if (@available(iOS 13.0, *)) {
        self.broadcastContainer.layer.shadowColor = [UIColor separatorColor].CGColor;
    } else {
        self.broadcastContainer.layer.shadowColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.3 alpha:0.3].CGColor;
    }
    self.broadcastContainer.layer.shadowOffset = CGSizeMake(0, 4);
    self.broadcastContainer.layer.shadowOpacity = 0.4;
    self.broadcastContainer.layer.shadowRadius = 8;
    self.broadcastContainer.layer.masksToBounds = NO;
    
    // Create a separate content view for the broadcasts to allow shadows with rounded corners
    UIView *broadcastContentView = [[UIView alloc] init];
    broadcastContentView.translatesAutoresizingMaskIntoConstraints = NO;
    broadcastContentView.backgroundColor = [UIColor systemBackgroundColor];
    broadcastContentView.layer.cornerRadius = 16;
    broadcastContentView.clipsToBounds = YES;
    [self.broadcastContainer addSubview:broadcastContentView];
    [self.containerView addSubview:self.broadcastContainer];
    
    // Setup broadcast header with modern typography and accent
    self.broadcastsHeaderLabel = [[UILabel alloc] init];
    self.broadcastsHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.broadcastsHeaderLabel.text = @"Broadcasts";
    if (@available(iOS 13.0, *)) {
        self.broadcastsHeaderLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        self.broadcastsHeaderLabel.textColor = [UIColor labelColor];
    } else {
        self.broadcastsHeaderLabel.font = [UIFont boldSystemFontOfSize:18];
    }
    [broadcastContentView addSubview:self.broadcastsHeaderLabel];
    
    // Add a subtle accent line under the header - use tintColor for system theme support
    UIView *broadcastAccentLine = [[UIView alloc] init];
    broadcastAccentLine.translatesAutoresizingMaskIntoConstraints = NO;
    broadcastAccentLine.backgroundColor = [UIColor systemBlueColor];
    broadcastAccentLine.layer.cornerRadius = 1;
    [broadcastContentView addSubview:broadcastAccentLine];
    
    // Setup expand button with enhanced appearance
    self.expandBroadcastsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.expandBroadcastsButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.image = [UIImage systemImageNamed:@"chevron.down"];
        config.baseForegroundColor = [UIColor systemBlueColor];
        [self.expandBroadcastsButton setConfiguration:config];
    } else {
        [self.expandBroadcastsButton setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
        self.expandBroadcastsButton.tintColor = [UIColor systemBlueColor];
    }
    
    // Replace hardcoded background with a dynamic color
    if (@available(iOS 13.0, *)) {
        self.expandBroadcastsButton.backgroundColor = [UIColor systemFillColor];
    } else {
        self.expandBroadcastsButton.backgroundColor = [UIColor colorWithWhite:0.95 alpha:0.3];
    }
    self.expandBroadcastsButton.layer.cornerRadius = 15;
    
    [self.expandBroadcastsButton addTarget:self action:@selector(toggleBroadcastsExpansion) forControlEvents:UIControlEventTouchUpInside];
    [broadcastContentView addSubview:self.expandBroadcastsButton];
    
    // Setup broadcast table view with enhanced appearance
    self.broadcastTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.broadcastTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.broadcastTableView.delegate = self;
    self.broadcastTableView.dataSource = self;
    self.broadcastTableView.rowHeight = UITableViewAutomaticDimension;
    self.broadcastTableView.estimatedRowHeight = 100;
    self.broadcastTableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.broadcastTableView.backgroundColor = [UIColor clearColor];
    self.broadcastTableView.separatorColor = [UIColor separatorColor];
    self.broadcastTableView.separatorInset = UIEdgeInsetsMake(0, 15, 0, 15);
    self.broadcastTableView.layer.cornerRadius = 12;
    [self.broadcastTableView registerClass:[BroadcastTableViewCell class] forCellReuseIdentifier:@"BroadcastCell"];
    [broadcastContentView addSubview:self.broadcastTableView];
    
    // No broadcasts label with improved styling
    self.noBroadcastsLabel = [[UILabel alloc] init];
    self.noBroadcastsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.noBroadcastsLabel.text = @"No broadcasts available";
    self.noBroadcastsLabel.textAlignment = NSTextAlignmentCenter;
    self.noBroadcastsLabel.textColor = [UIColor systemGrayColor];
    self.noBroadcastsLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.noBroadcastsLabel.hidden = YES;
    [broadcastContentView addSubview:self.noBroadcastsLabel];
    
    // Broadcasts loading indicator
    self.broadcastsLoadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.broadcastsLoadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.broadcastsLoadingIndicator.hidesWhenStopped = YES;
    [broadcastContentView addSubview:self.broadcastsLoadingIndicator];
    
    // Setup tickets container with enhanced card-like appearance
    self.ticketsContainer = [[UIView alloc] init];
    self.ticketsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.ticketsContainer.backgroundColor = [UIColor systemBackgroundColor];
    self.ticketsContainer.layer.cornerRadius = 16;
    self.ticketsContainer.clipsToBounds = YES;
    
    // Change ticket container shadow to dynamic color
    if (@available(iOS 13.0, *)) {
        self.ticketsContainer.layer.shadowColor = [UIColor separatorColor].CGColor;
    } else {
        self.ticketsContainer.layer.shadowColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.3 alpha:0.3].CGColor;
    }
    self.ticketsContainer.layer.shadowOffset = CGSizeMake(0, 4);
    self.ticketsContainer.layer.shadowOpacity = 0.4;
    self.ticketsContainer.layer.shadowRadius = 8;
    self.ticketsContainer.layer.masksToBounds = NO;
    
    // Create a separate content view for the tickets to allow shadows with rounded corners
    UIView *ticketsContentView = [[UIView alloc] init];
    ticketsContentView.translatesAutoresizingMaskIntoConstraints = NO;
    ticketsContentView.backgroundColor = [UIColor systemBackgroundColor];
    ticketsContentView.layer.cornerRadius = 16;
    ticketsContentView.clipsToBounds = YES;
    [self.ticketsContainer addSubview:ticketsContentView];
    [self.containerView addSubview:self.ticketsContainer];
    
    // Setup tickets header with modern typography
    self.ticketsHeaderLabel = [[UILabel alloc] init];
    self.ticketsHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.ticketsHeaderLabel.text = @"Support Tickets";
    if (@available(iOS 13.0, *)) {
        self.ticketsHeaderLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        self.ticketsHeaderLabel.textColor = [UIColor labelColor];
    } else {
        self.ticketsHeaderLabel.font = [UIFont boldSystemFontOfSize:18];
    }
    [ticketsContentView addSubview:self.ticketsHeaderLabel];
    
    // Add a subtle accent line under the header - use tintColor for system theme support
    UIView *ticketsAccentLine = [[UIView alloc] init];
    ticketsAccentLine.translatesAutoresizingMaskIntoConstraints = NO;
    ticketsAccentLine.backgroundColor = [UIColor systemBlueColor];
    ticketsAccentLine.layer.cornerRadius = 1;
    [ticketsContentView addSubview:ticketsAccentLine];
    
    // Create ticket button with a more prominent, modern design
    self.createTicketButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.createTicketButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Using the modern UIButtonConfiguration API for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        config.title = @"Create Ticket";
        config.baseBackgroundColor = [UIColor systemBlueColor];
        config.baseForegroundColor = [UIColor systemBackgroundColor];
        config.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
        
        UIImage *addImage = [UIImage systemImageNamed:@"plus"];
        config.image = addImage;
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 6;
        
        [self.createTicketButton setConfiguration:config];
    } else {
        // For iOS 14 and below, create a completely custom approach
        // First, remove all existing constraints
        [self.createTicketButton removeConstraints:self.createTicketButton.constraints];
        
        // Set up basic button properties
        [self.createTicketButton setTitle:@"Create Ticket" forState:UIControlStateNormal];
        self.createTicketButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        self.createTicketButton.backgroundColor = [UIColor systemBlueColor];
        
        if (@available(iOS 13.0, *)) {
            [self.createTicketButton setTitleColor:[UIColor systemBackgroundColor] forState:UIControlStateNormal];
        } else {
            [self.createTicketButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        }
        
        self.createTicketButton.layer.cornerRadius = 10.0;
        
        // Set fixed dimensions that include padding
        [self.createTicketButton.heightAnchor constraintEqualToConstant:36.0].active = YES;
        [self.createTicketButton.widthAnchor constraintEqualToConstant:140.0].active = YES;
        
        // Create a container stack view to hold the icon and text
        UIStackView *buttonStack = [[UIStackView alloc] init];
        buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
        buttonStack.axis = UILayoutConstraintAxisHorizontal;
        buttonStack.alignment = UIStackViewAlignmentCenter;
        buttonStack.distribution = UIStackViewDistributionFill;
        buttonStack.spacing = 6.0;
        [self.createTicketButton addSubview:buttonStack];
        
        // Add plus icon
        UIImageView *plusIcon = [[UIImageView alloc] init];
        plusIcon.translatesAutoresizingMaskIntoConstraints = NO;
        plusIcon.image = [UIImage systemImageNamed:@"plus"];
        
        if (@available(iOS 13.0, *)) {
            plusIcon.tintColor = [UIColor systemBackgroundColor];
        } else {
            plusIcon.tintColor = [UIColor whiteColor];
        }
        
        plusIcon.contentMode = UIViewContentModeScaleAspectFit;
        [buttonStack addArrangedSubview:plusIcon];
        
        // Set fixed size for the icon
        [plusIcon.widthAnchor constraintEqualToConstant:16.0].active = YES;
        [plusIcon.heightAnchor constraintEqualToConstant:16.0].active = YES;
        
        // Add label for text
        UILabel *buttonLabel = [[UILabel alloc] init];
        buttonLabel.translatesAutoresizingMaskIntoConstraints = NO;
        buttonLabel.text = @"Create Ticket";
        
        if (@available(iOS 13.0, *)) {
            buttonLabel.textColor = [UIColor systemBackgroundColor];
        } else {
            buttonLabel.textColor = [UIColor whiteColor];
        }
        
        buttonLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        [buttonStack addArrangedSubview:buttonLabel];
        
        // Position the stack view in the center of the button
        [NSLayoutConstraint activateConstraints:@[
            [buttonStack.centerXAnchor constraintEqualToAnchor:self.createTicketButton.centerXAnchor],
            [buttonStack.centerYAnchor constraintEqualToAnchor:self.createTicketButton.centerYAnchor],
            [buttonStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.createTicketButton.leadingAnchor constant:12],
            [buttonStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.createTicketButton.trailingAnchor constant:-12]
        ]];
        
        // Hide the default title
        [self.createTicketButton setTitle:@"" forState:UIControlStateNormal];
    }
    
    // Add a subtle shadow to the button with dynamic color
    if (@available(iOS 13.0, *)) {
        self.createTicketButton.layer.shadowColor = [UIColor systemBlueColor].CGColor;
    } else {
        self.createTicketButton.layer.shadowColor = [UIColor systemBlueColor].CGColor;
    }
    self.createTicketButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.createTicketButton.layer.shadowOpacity = 0.5;
    self.createTicketButton.layer.shadowRadius = 4;
    
    [self.createTicketButton addTarget:self action:@selector(createTicket) forControlEvents:UIControlEventTouchUpInside];
    [ticketsContentView addSubview:self.createTicketButton];
    
    // Setup tickets table view with enhanced appearance
    self.ticketsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.ticketsTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.ticketsTableView.delegate = self;
    self.ticketsTableView.dataSource = self;
    self.ticketsTableView.rowHeight = UITableViewAutomaticDimension;
    self.ticketsTableView.estimatedRowHeight = 80;
    self.ticketsTableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.ticketsTableView.backgroundColor = [UIColor clearColor];
    self.ticketsTableView.separatorColor = [UIColor separatorColor];
    self.ticketsTableView.separatorInset = UIEdgeInsetsMake(0, 15, 0, 15);
    self.ticketsTableView.layer.cornerRadius = 12;
    [self.ticketsTableView registerClass:[TicketTableViewCell class] forCellReuseIdentifier:@"TicketCell"];
    [ticketsContentView addSubview:self.ticketsTableView];
    
    // No tickets label
    self.noTicketsLabel = [[UILabel alloc] init];
    self.noTicketsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.noTicketsLabel.text = @"No support tickets available";
    self.noTicketsLabel.textAlignment = NSTextAlignmentCenter;
    self.noTicketsLabel.textColor = [UIColor systemGrayColor];
    self.noTicketsLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.noTicketsLabel.hidden = YES;
    [ticketsContentView addSubview:self.noTicketsLabel];
    
    // Tickets loading indicator
    self.ticketsLoadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.ticketsLoadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.ticketsLoadingIndicator.hidesWhenStopped = YES;
    [ticketsContentView addSubview:self.ticketsLoadingIndicator];
    
    // Setup layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Container view
        [self.containerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.containerView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:10],
        [self.containerView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [self.containerView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        
        // Broadcast container
        [self.broadcastContainer.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [self.broadcastContainer.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [self.broadcastContainer.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [self.broadcastContainer.heightAnchor constraintEqualToAnchor:self.containerView.heightAnchor multiplier:self.defaultBroadcastHeight],
        
        // Broadcast content view
        [broadcastContentView.topAnchor constraintEqualToAnchor:self.broadcastContainer.topAnchor],
        [broadcastContentView.leadingAnchor constraintEqualToAnchor:self.broadcastContainer.leadingAnchor],
        [broadcastContentView.trailingAnchor constraintEqualToAnchor:self.broadcastContainer.trailingAnchor],
        [broadcastContentView.bottomAnchor constraintEqualToAnchor:self.broadcastContainer.bottomAnchor],
        
        // Broadcast header label
        [self.broadcastsHeaderLabel.topAnchor constraintEqualToAnchor:broadcastContentView.topAnchor constant:16],
        [self.broadcastsHeaderLabel.leadingAnchor constraintEqualToAnchor:broadcastContentView.leadingAnchor constant:20],
        
        // Broadcast accent line
        [broadcastAccentLine.topAnchor constraintEqualToAnchor:self.broadcastsHeaderLabel.bottomAnchor constant:6],
        [broadcastAccentLine.leadingAnchor constraintEqualToAnchor:self.broadcastsHeaderLabel.leadingAnchor],
        [broadcastAccentLine.widthAnchor constraintEqualToConstant:40],
        [broadcastAccentLine.heightAnchor constraintEqualToConstant:2],
        
        // Expand button
        [self.expandBroadcastsButton.centerYAnchor constraintEqualToAnchor:self.broadcastsHeaderLabel.centerYAnchor],
        [self.expandBroadcastsButton.trailingAnchor constraintEqualToAnchor:broadcastContentView.trailingAnchor constant:-20],
        [self.expandBroadcastsButton.widthAnchor constraintEqualToConstant:30],
        [self.expandBroadcastsButton.heightAnchor constraintEqualToConstant:30],
        
        // Broadcast table view
        [self.broadcastTableView.topAnchor constraintEqualToAnchor:broadcastAccentLine.bottomAnchor constant:12],
        [self.broadcastTableView.leadingAnchor constraintEqualToAnchor:broadcastContentView.leadingAnchor constant:0],
        [self.broadcastTableView.trailingAnchor constraintEqualToAnchor:broadcastContentView.trailingAnchor constant:0],
        [self.broadcastTableView.bottomAnchor constraintEqualToAnchor:broadcastContentView.bottomAnchor constant:0],
        
        // No broadcasts label
        [self.noBroadcastsLabel.centerXAnchor constraintEqualToAnchor:self.broadcastTableView.centerXAnchor],
        [self.noBroadcastsLabel.centerYAnchor constraintEqualToAnchor:self.broadcastTableView.centerYAnchor],
        
        // Broadcasts loading indicator
        [self.broadcastsLoadingIndicator.centerXAnchor constraintEqualToAnchor:self.broadcastTableView.centerXAnchor],
        [self.broadcastsLoadingIndicator.centerYAnchor constraintEqualToAnchor:self.broadcastTableView.centerYAnchor],
        
        // Tickets container
        [self.ticketsContainer.topAnchor constraintEqualToAnchor:self.broadcastContainer.bottomAnchor constant:16],
        [self.ticketsContainer.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [self.ticketsContainer.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [self.ticketsContainer.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor],
        
        // Tickets content view
        [ticketsContentView.topAnchor constraintEqualToAnchor:self.ticketsContainer.topAnchor],
        [ticketsContentView.leadingAnchor constraintEqualToAnchor:self.ticketsContainer.leadingAnchor],
        [ticketsContentView.trailingAnchor constraintEqualToAnchor:self.ticketsContainer.trailingAnchor],
        [ticketsContentView.bottomAnchor constraintEqualToAnchor:self.ticketsContainer.bottomAnchor],
        
        // Tickets header label
        [self.ticketsHeaderLabel.topAnchor constraintEqualToAnchor:ticketsContentView.topAnchor constant:16],
        [self.ticketsHeaderLabel.leadingAnchor constraintEqualToAnchor:ticketsContentView.leadingAnchor constant:20],
        
        // Tickets accent line
        [ticketsAccentLine.topAnchor constraintEqualToAnchor:self.ticketsHeaderLabel.bottomAnchor constant:6],
        [ticketsAccentLine.leadingAnchor constraintEqualToAnchor:self.ticketsHeaderLabel.leadingAnchor],
        [ticketsAccentLine.widthAnchor constraintEqualToConstant:40],
        [ticketsAccentLine.heightAnchor constraintEqualToConstant:2],
        
        // Create ticket button
        [self.createTicketButton.centerYAnchor constraintEqualToAnchor:self.ticketsHeaderLabel.centerYAnchor],
        [self.createTicketButton.trailingAnchor constraintEqualToAnchor:ticketsContentView.trailingAnchor constant:-20],
        
        // Tickets table view
        [self.ticketsTableView.topAnchor constraintEqualToAnchor:ticketsAccentLine.bottomAnchor constant:12],
        [self.ticketsTableView.leadingAnchor constraintEqualToAnchor:ticketsContentView.leadingAnchor constant:0],
        [self.ticketsTableView.trailingAnchor constraintEqualToAnchor:ticketsContentView.trailingAnchor constant:0],
        [self.ticketsTableView.bottomAnchor constraintEqualToAnchor:ticketsContentView.bottomAnchor constant:0],
        
        // No tickets label
        [self.noTicketsLabel.centerXAnchor constraintEqualToAnchor:self.ticketsTableView.centerXAnchor],
        [self.noTicketsLabel.centerYAnchor constraintEqualToAnchor:self.ticketsTableView.centerYAnchor],
        
        // Tickets loading indicator
        [self.ticketsLoadingIndicator.centerXAnchor constraintEqualToAnchor:self.ticketsTableView.centerXAnchor],
        [self.ticketsLoadingIndicator.centerYAnchor constraintEqualToAnchor:self.ticketsTableView.centerYAnchor],
    ]];
}

#pragma mark - Data Loading

- (void)loadData {
    [self loadBroadcasts];
    [self loadTickets];
}

- (void)loadBroadcasts {
    [self.broadcastsLoadingIndicator startAnimating];
    self.noBroadcastsLabel.hidden = YES;
    
    [[APIManager sharedManager] getBroadcasts:^(NSArray *broadcasts, NSInteger unreadCount, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.broadcastsLoadingIndicator stopAnimating];
            [self.broadcastRefreshControl endRefreshing];
            
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:@"Failed to load broadcasts. Please try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            self.broadcasts = broadcasts;
            [self.broadcastTableView reloadData];
            
            self.noBroadcastsLabel.hidden = self.broadcasts.count > 0;
        });
    }];
}

- (void)loadTickets {
    [self.ticketsLoadingIndicator startAnimating];
    self.noTicketsLabel.hidden = YES;
    
    [[APIManager sharedManager] getUserTickets:^(NSArray *tickets, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.ticketsLoadingIndicator stopAnimating];
            [self.ticketsRefreshControl endRefreshing];
            
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:@"Failed to load support tickets. Please try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            self.tickets = tickets;
            [self.ticketsTableView reloadData];
            
            self.noTicketsLabel.hidden = self.tickets.count > 0;
        });
    }];
}

#pragma mark - UI Actions

- (void)toggleBroadcastsExpansion {
    self.isBroadcastsExpanded = !self.isBroadcastsExpanded;
    
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isBroadcastsExpanded) {
            [self.expandBroadcastsButton setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
            [self.broadcastContainer.heightAnchor constraintEqualToAnchor:self.containerView.heightAnchor multiplier:self.expandedBroadcastHeight].active = YES;
        } else {
            [self.expandBroadcastsButton setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
            [self.broadcastContainer.heightAnchor constraintEqualToAnchor:self.containerView.heightAnchor multiplier:self.defaultBroadcastHeight].active = YES;
        }
        [self.view layoutIfNeeded];
    }];
}

- (void)createTicket {
    CreateTicketViewController *createVC = [[CreateTicketViewController alloc] init];
    createVC.ticketCreatedHandler = ^{
        [self loadTickets];
    };
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:createVC];
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.broadcastTableView) {
        return self.broadcasts.count;
    } else if (tableView == self.ticketsTableView) {
        return self.tickets.count;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.broadcastTableView) {
        BroadcastTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BroadcastCell" forIndexPath:indexPath];
        NSDictionary *broadcast = self.broadcasts[indexPath.row];
        [cell configureCellWithBroadcast:broadcast];
        return cell;
    } else if (tableView == self.ticketsTableView) {
        TicketTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TicketCell" forIndexPath:indexPath];
        NSDictionary *ticket = self.tickets[indexPath.row];
        
        [cell configureCellWithTicket:ticket];
        return cell;
    }
    return [[UITableViewCell alloc] init];
}

#pragma mark - UITableViewDelegate Methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (tableView == self.broadcastTableView) {
        NSDictionary *broadcast = self.broadcasts[indexPath.row];
        NSNumber *broadcastId = broadcast[@"id"];
        
        [self openBroadcastDetail:broadcastId];
        
    } else if (tableView == self.ticketsTableView) {
        NSDictionary *ticket = self.tickets[indexPath.row];
        NSNumber *ticketId = ticket[@"id"];
        
        [self openTicketDetail:ticketId];
    }
}

- (void)openBroadcastDetail:(NSNumber *)broadcastId {
    if (!broadcastId) {
        return;
    }
    
    for (int i = 0; i < self.broadcasts.count; i++) {
        NSDictionary *broadcast = self.broadcasts[i];
        NSNumber *id = broadcast[@"id"];
        
        if ([id isEqual:broadcastId]) {
            // Found the broadcast, now open its detail view
            BroadcastDetailViewController *detailVC = [[BroadcastDetailViewController alloc] init];
            detailVC.broadcastId = broadcastId;
            [self.navigationController pushViewController:detailVC animated:YES];
            
            // Mark as read in the local data
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
            NSMutableArray *updatedBroadcasts = [self.broadcasts mutableCopy];
            NSMutableDictionary *updatedBroadcast = [broadcast mutableCopy];
            updatedBroadcast[@"is_read"] = @YES;
            updatedBroadcasts[i] = updatedBroadcast;
            self.broadcasts = updatedBroadcasts;
            [self.broadcastTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            
            return;
        }
    }
    
    // If broadcast not found in the current list, load it directly
    BroadcastDetailViewController *detailVC = [[BroadcastDetailViewController alloc] init];
    detailVC.broadcastId = broadcastId;
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (void)openTicketDetail:(NSNumber *)ticketId {
    if (!ticketId) {
        return;
    }
    
    for (int i = 0; i < self.tickets.count; i++) {
        NSDictionary *ticket = self.tickets[i];
        NSNumber *id = ticket[@"id"];
        
        if ([id isEqual:ticketId]) {
            // Found the ticket, now open its detail view
            TicketDetailViewController *detailVC = [[TicketDetailViewController alloc] init];
            detailVC.ticketId = ticketId;
            detailVC.ticketUpdatedHandler = ^{
                [self loadTickets];
            };
            [self.navigationController pushViewController:detailVC animated:YES];
            return;
        }
    }
    
    // If ticket not found in the current list, load it directly
    TicketDetailViewController *detailVC = [[TicketDetailViewController alloc] init];
    detailVC.ticketId = ticketId;
    detailVC.ticketUpdatedHandler = ^{
        [self loadTickets];
    };
    [self.navigationController pushViewController:detailVC animated:YES];
}

#pragma mark - Navigation

- (void)navigateToAccountTab {
    // Find the TabBarController using a reliable approach
    UITabBarController *tabBarController = nil;
    
    // Method 1: Check if we're inside a UITabBarController
    if (self.tabBarController != nil) {
        tabBarController = self.tabBarController;
    }
    
    // Method 2: Try to find it through the app delegate's window
    if (!tabBarController) {
        UIWindow *window = [UIApplication sharedApplication].delegate.window;
        if (window.rootViewController && [window.rootViewController isKindOfClass:[UITabBarController class]]) {
            tabBarController = (UITabBarController *)window.rootViewController;
        }
    }
    
    // Method 3: Check our parent view controllers
    if (!tabBarController) {
        UIViewController *parentVC = self.parentViewController;
        while (parentVC != nil) {
            if ([parentVC isKindOfClass:[UITabBarController class]]) {
                tabBarController = (UITabBarController *)parentVC;
                break;
            }
            parentVC = parentVC.parentViewController;
        }
    }
    
    // Now try to use the tab bar controller's switchToAccountTab method
    if (tabBarController && [tabBarController respondsToSelector:@selector(switchToAccountTab)]) {
        [tabBarController performSelector:@selector(switchToAccountTab)];
        return;
    }
    
    // Fallback: Directly select the account tab (index 3)
    if (tabBarController) {
        dispatch_async(dispatch_get_main_queue(), ^{
            tabBarController.selectedIndex = 3;
        });
    } else {
        // Post a notification as a last resort
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SwitchToAccountTab" object:nil];
    }
}

// Helper method to debug view hierarchy
- (NSString *)describeViewHierarchy:(UIViewController *)viewController {
    NSMutableString *description = [NSMutableString string];
    UIViewController *currentVC = viewController;
    int level = 0;
    
    while (currentVC != nil) {
        [description appendFormat:@"\nLevel %d: %@", level, [currentVC class]];
        currentVC = currentVC.parentViewController;
        level++;
    }
    
    return description;
}

// Helper method to debug view hierarchy from a specific view
- (NSString *)describeViewHierarchyFromView:(UIView *)view {
    NSMutableString *description = [NSMutableString string];
    UIView *currentView = view;
    int level = 0;
    
    while (currentView != nil) {
        [description appendFormat:@"\nLevel %d: %@", level, [currentView class]];
        currentView = currentView.superview;
        level++;
    }
    
    return description;
}

#pragma mark - Telegram Support

- (void)telegramButtonTapped {
    UIViewController *alertVC = [[UIViewController alloc] init];
    alertVC.view.backgroundColor = [UIColor clearColor];
    
    // Create a container view with blur effect that adapts to system theme
    UIBlurEffect *blurEffect;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }
    
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = alertVC.view.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [alertVC.view addSubview:blurView];
    
    // Create a container for the content
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (@available(iOS 13.0, *)) {
        containerView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    } else {
        containerView.backgroundColor = [UIColor blackColor];
    }
    
    containerView.layer.cornerRadius = 16.0;
    containerView.clipsToBounds = YES;
    [alertVC.view addSubview:containerView];
    
    // Add title label
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Get Connected with admin directly on telegram";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    
    if (@available(iOS 13.0, *)) {
        titleLabel.textColor = [UIColor labelColor];
    } else {
        titleLabel.textColor = [UIColor whiteColor];
    }
    
    titleLabel.numberOfLines = 0;
    [containerView addSubview:titleLabel];
    
    // Add Telegram button with dynamic colors
    UIButton *telegramLinkButton = [UIButton buttonWithType:UIButtonTypeCustom];
    telegramLinkButton.translatesAutoresizingMaskIntoConstraints = NO;
    [telegramLinkButton setImage:[UIImage systemImageNamed:@"paperplane.circle.fill"] forState:UIControlStateNormal];
    telegramLinkButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    telegramLinkButton.tintColor = [UIColor systemBlueColor];
    [telegramLinkButton addTarget:self action:@selector(openTelegramLink) forControlEvents:UIControlEventTouchUpInside];
    [containerView addSubview:telegramLinkButton];
    
    // Create buttons container
    UIStackView *buttonsStackView = [[UIStackView alloc] init];
    buttonsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    buttonsStackView.axis = UILayoutConstraintAxisHorizontal;
    buttonsStackView.distribution = UIStackViewDistributionFillEqually;
    buttonsStackView.spacing = 10;
    [containerView addSubview:buttonsStackView];
    
    // Add open button
    UIButton *openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    openButton.translatesAutoresizingMaskIntoConstraints = NO;
    [openButton setTitle:@"Open" forState:UIControlStateNormal];
    openButton.backgroundColor = [UIColor systemBlueColor];
    openButton.layer.cornerRadius = 8.0;
    
    if (@available(iOS 13.0, *)) {
        [openButton setTitleColor:[UIColor systemBackgroundColor] forState:UIControlStateNormal];
    } else {
        [openButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    
    [openButton addTarget:self action:@selector(openTelegramLink) forControlEvents:UIControlEventTouchUpInside];
    [buttonsStackView addArrangedSubview:openButton];
    
    // Add close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    
    if (@available(iOS 13.0, *)) {
        closeButton.backgroundColor = [UIColor systemGray3Color];
        [closeButton setTitleColor:[UIColor systemBackgroundColor] forState:UIControlStateNormal];
    } else {
        closeButton.backgroundColor = [UIColor systemGrayColor];
        [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    
    closeButton.layer.cornerRadius = 8.0;
    
    // Use a direct approach for dismissing the popup
    [closeButton addTarget:self action:@selector(dismissTelegramPopup:) forControlEvents:UIControlEventTouchUpInside];
    [buttonsStackView addArrangedSubview:closeButton];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        // Container constraints
        [containerView.centerXAnchor constraintEqualToAnchor:alertVC.view.centerXAnchor],
        [containerView.centerYAnchor constraintEqualToAnchor:alertVC.view.centerYAnchor],
        [containerView.widthAnchor constraintEqualToConstant:300],
        
        // Title label constraints
        [titleLabel.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-20],
        
        // Telegram button constraints
        [telegramLinkButton.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:20],
        [telegramLinkButton.centerXAnchor constraintEqualToAnchor:containerView.centerXAnchor],
        [telegramLinkButton.widthAnchor constraintEqualToConstant:60],
        [telegramLinkButton.heightAnchor constraintEqualToConstant:60],
        
        // Buttons stack view constraints
        [buttonsStackView.topAnchor constraintEqualToAnchor:telegramLinkButton.bottomAnchor constant:20],
        [buttonsStackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:20],
        [buttonsStackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-20],
        [buttonsStackView.heightAnchor constraintEqualToConstant:44],
        [buttonsStackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-20],
    ]];
    
    // Ensure buttons have proper height
    [openButton.heightAnchor constraintEqualToConstant:44].active = YES;
    [closeButton.heightAnchor constraintEqualToConstant:44].active = YES;
    
    // Present the alert
    alertVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    alertVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:alertVC animated:YES completion:nil];
}

// Properly dismiss the telegram popup with sender
- (void)dismissTelegramPopup:(UIButton *)sender {
    // Safely dismiss the presented view controller
    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)openTelegramLink {
    NSURL *telegramURL = [NSURL URLWithString:@"https://t.me/Hydraosmo"];
    
    if ([[UIApplication sharedApplication] canOpenURL:telegramURL]) {
        [[UIApplication sharedApplication] openURL:telegramURL options:@{} completionHandler:nil];
    } else {
        // Show error if the URL cannot be opened
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                   message:@"Unable to open Telegram link."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end

#pragma mark - BroadcastTableViewCell Implementation

@implementation BroadcastTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Add modern selection style
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        UIView *selectedBgView = [[UIView alloc] init];
        
        if (@available(iOS 13.0, *)) {
            selectedBgView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        } else {
            selectedBgView.backgroundColor = [UIColor colorWithRed:0.9 green:0.95 blue:1.0 alpha:0.5];
        }
        
        self.selectedBackgroundView = selectedBgView;
        
        // Modern accessory
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
        // Add a card-like container to the content view for better visual hierarchy
        UIView *cardContainer = [[UIView alloc] init];
        cardContainer.translatesAutoresizingMaskIntoConstraints = NO;
        cardContainer.backgroundColor = [UIColor clearColor];
        cardContainer.layer.cornerRadius = 8;
        [self.contentView addSubview:cardContainer];
        
        // Unread indicator with dynamic color
        self.unreadIndicator = [[UIView alloc] init];
        self.unreadIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        self.unreadIndicator.backgroundColor = [UIColor systemBlueColor];
        self.unreadIndicator.layer.cornerRadius = 4;
        
        // Add a subtle glow to the unread indicator with appropriate color
        self.unreadIndicator.layer.shadowColor = [UIColor systemBlueColor].CGColor;
        self.unreadIndicator.layer.shadowOffset = CGSizeMake(0, 0);
        self.unreadIndicator.layer.shadowOpacity = 0.6;
        self.unreadIndicator.layer.shadowRadius = 3.0;
        
        [cardContainer addSubview:self.unreadIndicator];
        
        // Title label with modern typography
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(iOS 13.0, *)) {
            self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        } else {
            self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        }
        self.titleLabel.numberOfLines = 1;
        [cardContainer addSubview:self.titleLabel];
        
        // Content label with improved readability
        self.contentLabel = [[UILabel alloc] init];
        self.contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.contentLabel.font = [UIFont systemFontOfSize:14];
        if (@available(iOS 13.0, *)) {
            self.contentLabel.textColor = [UIColor secondaryLabelColor];
        } else {
            self.contentLabel.textColor = [UIColor darkGrayColor];
        }
        self.contentLabel.numberOfLines = 2;
        [cardContainer addSubview:self.contentLabel];
        
        // Date label with subtle styling
        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.dateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        if (@available(iOS 13.0, *)) {
            self.dateLabel.textColor = [UIColor tertiaryLabelColor];
        } else {
            self.dateLabel.textColor = [UIColor systemGrayColor];
        }
        self.dateLabel.textAlignment = NSTextAlignmentRight;
        [cardContainer addSubview:self.dateLabel];
        
        // Setup constraints with improved spacing
        [NSLayoutConstraint activateConstraints:@[
            // Card container
            [cardContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [cardContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:0],
            [cardContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-0],
            [cardContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            
            // Unread indicator
            [self.unreadIndicator.leadingAnchor constraintEqualToAnchor:cardContainer.leadingAnchor constant:15],
            [self.unreadIndicator.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.unreadIndicator.widthAnchor constraintEqualToConstant:8],
            [self.unreadIndicator.heightAnchor constraintEqualToConstant:8],
            
            // Title label
            [self.titleLabel.topAnchor constraintEqualToAnchor:cardContainer.topAnchor constant:10],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.unreadIndicator.trailingAnchor constant:12],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.dateLabel.leadingAnchor constant:-8],
            
            // Date label
            [self.dateLabel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.dateLabel.trailingAnchor constraintEqualToAnchor:cardContainer.trailingAnchor constant:-32], // Account for accessory
            [self.dateLabel.widthAnchor constraintLessThanOrEqualToConstant:100],
            
            // Content label with proper spacing
            [self.contentLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
            [self.contentLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.contentLabel.trailingAnchor constraintEqualToAnchor:cardContainer.trailingAnchor constant:-16],
            [self.contentLabel.bottomAnchor constraintLessThanOrEqualToAnchor:cardContainer.bottomAnchor constant:-10]
        ]];
    }
    return self;
}

- (void)configureCellWithBroadcast:(NSDictionary *)broadcast {
    // Set title
    self.titleLabel.text = broadcast[@"title"] ?: @"Untitled Broadcast";
    
    // Process content for preview - strip HTML tags if present
    NSString *content = broadcast[@"content"] ?: @"";
    // Simple HTML tag stripping - for a more accurate solution, consider using NSAttributedString
    if ([content containsString:@"<"] && [content containsString:@">"]) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:NSRegularExpressionCaseInsensitive error:nil];
        content = [regex stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0, content.length) withTemplate:@""];
    }
    
    // Trim whitespace and newlines
    content = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Set content
    self.contentLabel.text = content.length > 0 ? content : @"No content";
    
    // Format date if available
    NSString *createdAt = broadcast[@"created_at"];
    if (createdAt) {
        NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
        [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        NSDate *date = [inputFormatter dateFromString:createdAt];
        
        if (!date) {
            // Try alternative format without milliseconds
            [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
            date = [inputFormatter dateFromString:createdAt];
        }
        
        if (date) {
            // Check if date is today, yesterday, or older
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSDateComponents *components = [calendar components:NSCalendarUnitDay|NSCalendarUnitMonth|NSCalendarUnitYear fromDate:date toDate:[NSDate date] options:0];
            
            NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
            
            if (components.year > 0) {
                [outputFormatter setDateFormat:@"MM/dd/yy"];
            } else if (components.month > 0 || components.day > 1) {
                [outputFormatter setDateFormat:@"MMM d"];
            } else if (components.day == 1) {
                self.dateLabel.text = @"Yesterday";
                return;
            } else {
                [outputFormatter setDateFormat:@"h:mm a"];
                self.dateLabel.text = [[outputFormatter stringFromDate:date] lowercaseString];
                return;
            }
            
            self.dateLabel.text = [outputFormatter stringFromDate:date];
        } else {
            self.dateLabel.text = @"";
        }
    } else {
        self.dateLabel.text = @"";
    }
    
    // Set unread indicator visibility
    BOOL isRead = [broadcast[@"is_read"] boolValue];
    self.unreadIndicator.hidden = isRead;
    
    // Add subtle animation for unread indicator
    if (!isRead) {
        // Subtle pulse animation for unread indicator
        [UIView animateWithDuration:1.5 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat animations:^{
            self.unreadIndicator.transform = CGAffineTransformMakeScale(1.3, 1.3);
            self.unreadIndicator.alpha = 0.7;
        } completion:^(BOOL finished) {
            self.unreadIndicator.transform = CGAffineTransformIdentity;
            self.unreadIndicator.alpha = 1.0;
        }];
    } else {
        // Reset any animations if the broadcast is read
        self.unreadIndicator.transform = CGAffineTransformIdentity;
        self.unreadIndicator.alpha = 1.0;
        [self.unreadIndicator.layer removeAllAnimations];
    }
}

@end

#pragma mark - TicketTableViewCell Implementation

@implementation TicketTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
        // Subject label
        self.subjectLabel = [[UILabel alloc] init];
        self.subjectLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subjectLabel.font = [UIFont boldSystemFontOfSize:16];
        self.subjectLabel.numberOfLines = 1;
        [self.contentView addSubview:self.subjectLabel];
        
        // Status label
        self.statusLabel = [[UILabel alloc] init];
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.statusLabel.font = [UIFont systemFontOfSize:12];
        self.statusLabel.textAlignment = NSTextAlignmentCenter;
        self.statusLabel.layer.cornerRadius = 8;
        self.statusLabel.clipsToBounds = YES;
        [self.contentView addSubview:self.statusLabel];
        
        // Category label
        self.categoryLabel = [[UILabel alloc] init];
        self.categoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.categoryLabel.font = [UIFont systemFontOfSize:14];
        
        if (@available(iOS 13.0, *)) {
            self.categoryLabel.textColor = [UIColor secondaryLabelColor];
        } else {
            self.categoryLabel.textColor = [UIColor darkGrayColor];
        }
        
        [self.contentView addSubview:self.categoryLabel];
        
        // Date label
        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.dateLabel.font = [UIFont systemFontOfSize:12];
        self.dateLabel.textColor = [UIColor systemGrayColor];
        [self.contentView addSubview:self.dateLabel];
        
        // Reply indicator with dynamic color
        self.replyIndicator = [[UIImageView alloc] init];
        self.replyIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        self.replyIndicator.image = [UIImage systemImageNamed:@"bubble.left.fill"];
        self.replyIndicator.tintColor = [UIColor systemBlueColor];
        self.replyIndicator.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:self.replyIndicator];
        
        // Setup constraints
        [NSLayoutConstraint activateConstraints:@[
            // Subject label
            [self.subjectLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [self.subjectLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
            [self.subjectLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-80],
            
            // Status label
            [self.statusLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-40],
            [self.statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:60],
            [self.statusLabel.heightAnchor constraintEqualToConstant:20],
            
            // Category label
            [self.categoryLabel.topAnchor constraintEqualToAnchor:self.subjectLabel.bottomAnchor constant:4],
            [self.categoryLabel.leadingAnchor constraintEqualToAnchor:self.subjectLabel.leadingAnchor],
            [self.categoryLabel.trailingAnchor constraintEqualToAnchor:self.subjectLabel.trailingAnchor],
            
            // Date label
            [self.dateLabel.topAnchor constraintEqualToAnchor:self.categoryLabel.bottomAnchor constant:4],
            [self.dateLabel.leadingAnchor constraintEqualToAnchor:self.categoryLabel.leadingAnchor],
            [self.dateLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
            
            // Reply indicator
            [self.replyIndicator.centerYAnchor constraintEqualToAnchor:self.dateLabel.centerYAnchor],
            [self.replyIndicator.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-40],
            [self.replyIndicator.widthAnchor constraintEqualToConstant:20],
            [self.replyIndicator.heightAnchor constraintEqualToConstant:20]
        ]];
    }
    return self;
}

- (void)configureCellWithTicket:(NSDictionary *)ticket {
    self.subjectLabel.text = ticket[@"subject"] ?: @"No Subject";
    
    // Set category
    id category = ticket[@"category"];
    if ([category isKindOfClass:[NSDictionary class]]) {
        // Use the category name from the dictionary
        self.categoryLabel.text = category[@"name"] ?: @"General";
    } else if ([category isKindOfClass:[NSString class]]) {
        // Use the string value directly
        self.categoryLabel.text = category;
    } else {
        // Fallback to general
        self.categoryLabel.text = @"General";
    }
    
    // Set status label with dynamic color aware status indicators
    NSString *status = ticket[@"status"];
    self.statusLabel.text = [self capitalizedStatus:status];
    
    if ([status isEqualToString:@"open"]) {
        if (@available(iOS 13.0, *)) {
            self.statusLabel.backgroundColor = [UIColor systemYellowColor];
            self.statusLabel.textColor = [UIColor labelColor];
        } else {
            self.statusLabel.backgroundColor = [UIColor systemYellowColor];
            self.statusLabel.textColor = [UIColor darkTextColor];
        }
    } else if ([status isEqualToString:@"in_progress"]) {
        self.statusLabel.backgroundColor = [UIColor systemBlueColor];
        if (@available(iOS 13.0, *)) {
            self.statusLabel.textColor = [UIColor systemBackgroundColor];
        } else {
            self.statusLabel.textColor = [UIColor whiteColor];
        }
    } else if ([status isEqualToString:@"closed"] || [status isEqualToString:@"resolved"]) {
        self.statusLabel.backgroundColor = [UIColor systemGreenColor];
        if (@available(iOS 13.0, *)) {
            self.statusLabel.textColor = [UIColor systemBackgroundColor];
        } else {
            self.statusLabel.textColor = [UIColor whiteColor];
        }
    } else {
        // Default appearance for unknown status
        self.statusLabel.backgroundColor = [UIColor systemGrayColor];
        if (@available(iOS 13.0, *)) {
            self.statusLabel.textColor = [UIColor systemBackgroundColor];
        } else {
            self.statusLabel.textColor = [UIColor whiteColor];
        }
    }
    
    // Format date if available
    NSString *createdAt = ticket[@"created_at"];
    if (createdAt) {
        NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
        [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        NSDate *date = [inputFormatter dateFromString:createdAt];
        
        if (!date) {
            // Try alternative format without milliseconds
            [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
            date = [inputFormatter dateFromString:createdAt];
        }
        
        if (date) {
            // Check if date is today, yesterday, or older
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSDateComponents *components = [calendar components:NSCalendarUnitDay|NSCalendarUnitMonth|NSCalendarUnitYear fromDate:date toDate:[NSDate date] options:0];
            
            NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
            
            if (components.year > 0) {
                [outputFormatter setDateFormat:@"MM/dd/yy"];
            } else if (components.month > 0 || components.day > 1) {
                [outputFormatter setDateFormat:@"MMM d"];
            } else if (components.day == 1) {
                self.dateLabel.text = @"Yesterday";
                return;
            } else {
                [outputFormatter setDateFormat:@"h:mm a"];
                self.dateLabel.text = [[outputFormatter stringFromDate:date] lowercaseString];
                return;
            }
            
            self.dateLabel.text = [outputFormatter stringFromDate:date];
        } else {
            self.dateLabel.text = @"";
        }
    } else {
        self.dateLabel.text = @"";
    }
    
    // Show/hide reply indicator based on whether there are admin replies or unread messages
    BOOL hasAdminReply = [ticket[@"has_admin_reply"] boolValue] || [ticket[@"has_unread_replies"] boolValue];
    self.replyIndicator.hidden = !hasAdminReply;
    
    // Ensure the status label is visible
    self.statusLabel.hidden = NO;
}

- (NSString *)capitalizedStatus:(NSString *)status {
    if ([status isEqualToString:@"in_progress"]) {
        return @"In Progress";
    }
    return [status capitalizedString];
}

@end