// IPStatusViewController.m
#import "IPStatusViewController.h"
#import "IPStatusCacheManager.h"

#import "ScoreMeterView.h"

@interface IPStatusViewController ()
@property (nonatomic, strong) ScoreMeterView *scoreMeterView;
@property (nonatomic, strong) UILabel *scoreLabel;
@property (nonatomic, strong) UIStackView *mainStackView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIButton *refreshButton;
@property (nonatomic, strong) UIButton *viewCachedButton; // New button for viewing cached IP details
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) NSMutableDictionary *collapsibleCards; // Track collapsible cards
@property (nonatomic, strong) UISegmentedControl *cacheSelector; // For selecting cached IP statuses
@property (nonatomic, strong) UILabel *cacheInfoLabel; // Shows info about the selected cache
@end

@implementation IPStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IP Status";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.collapsibleCards = [NSMutableDictionary dictionary];
    
    [self setupUI];
    [self displayCachedIPStatus];
}

- (void)setupUI {
    // Setup scroll view
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;     // Hide vertical scroll indicator
    self.scrollView.showsHorizontalScrollIndicator = NO;   // Hide horizontal scroll indicator
    [self.view addSubview:self.scrollView];
    
    // Main stack view
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.spacing = 16;
    self.mainStackView.alignment = UIStackViewAlignmentCenter;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStackView];
    
    // Score meter view
    self.scoreMeterView = [[ScoreMeterView alloc] initWithFrame:CGRectMake(0, 0, 160, 120)];
    self.scoreMeterView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainStackView addArrangedSubview:self.scoreMeterView];

    // Score label
    self.scoreLabel = [[UILabel alloc] init];
    self.scoreLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.scoreLabel.textAlignment = NSTextAlignmentCenter;
    self.scoreLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainStackView addArrangedSubview:self.scoreLabel];
    
    // Setup refresh button
    self.refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.refreshButton setTitle:@"Fetch NEW IP Details" forState:UIControlStateNormal];
    [self.refreshButton addTarget:self action:@selector(fetchAndDisplayIPStatus) forControlEvents:UIControlEventTouchUpInside];
    self.refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainStackView addArrangedSubview:self.refreshButton];

    // Setup view cached button
    self.viewCachedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.viewCachedButton setTitle:@"Recent IP'S Details" forState:UIControlStateNormal];
    [self.viewCachedButton addTarget:self action:@selector(showCachedIPDetails) forControlEvents:UIControlEventTouchUpInside];
    self.viewCachedButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainStackView addArrangedSubview:self.viewCachedButton];
    
    // Setup activity indicator
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.hidesWhenStopped = YES;
    [self.mainStackView addArrangedSubview:self.activityIndicator];
    
    // Add cache selector
    [self setupCacheSelector];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        // Scroll view constraints
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        // Main stack view constraints
        [self.mainStackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20],
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:20],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-20],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.mainStackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-40],
        
        // Score meter constraints
        [self.scoreMeterView.widthAnchor constraintEqualToConstant:160],
        [self.scoreMeterView.heightAnchor constraintEqualToConstant:120],

        // Refresh button constraints
        [self.refreshButton.heightAnchor constraintEqualToConstant:44],
        [self.refreshButton.widthAnchor constraintEqualToConstant:200],

        // View cached button constraints
        [self.viewCachedButton.heightAnchor constraintEqualToConstant:44],
        [self.viewCachedButton.widthAnchor constraintEqualToConstant:200]
    ]];
}

- (void)setupCacheSelector {
    // Create a container view for the cache selector
    UIView *cacheSelectorContainer = [[UIView alloc] init];
    cacheSelectorContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
    cacheSelectorContainer.layer.cornerRadius = 12;
    cacheSelectorContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainStackView addArrangedSubview:cacheSelectorContainer];
    
    // Create a stack view for the cache selector and info label
    UIStackView *cacheStack = [[UIStackView alloc] init];
    cacheStack.axis = UILayoutConstraintAxisVertical;
    cacheStack.spacing = 8;
    cacheStack.translatesAutoresizingMaskIntoConstraints = NO;
    [cacheSelectorContainer addSubview:cacheStack];
    
    // Create the segmented control with initial items
    self.cacheSelector = [[UISegmentedControl alloc] initWithItems:@[@"Current"]];
    self.cacheSelector.selectedSegmentIndex = 0;
    [self.cacheSelector addTarget:self action:@selector(cacheSelectorChanged:) forControlEvents:UIControlEventValueChanged];
    [cacheStack addArrangedSubview:self.cacheSelector];
    
    // Create the info label
    self.cacheInfoLabel = [[UILabel alloc] init];
    self.cacheInfoLabel.text = @"Showing most recent IP check";
    self.cacheInfoLabel.font = [UIFont systemFontOfSize:12];
    self.cacheInfoLabel.textColor = [UIColor secondaryLabelColor];
    self.cacheInfoLabel.textAlignment = NSTextAlignmentCenter;
    [cacheStack addArrangedSubview:self.cacheInfoLabel];
    
    // Set up constraints
    [NSLayoutConstraint activateConstraints:@[
        [cacheStack.topAnchor constraintEqualToAnchor:cacheSelectorContainer.topAnchor constant:12],
        [cacheStack.leadingAnchor constraintEqualToAnchor:cacheSelectorContainer.leadingAnchor constant:12],
        [cacheStack.trailingAnchor constraintEqualToAnchor:cacheSelectorContainer.trailingAnchor constant:-12],
        [cacheStack.bottomAnchor constraintEqualToAnchor:cacheSelectorContainer.bottomAnchor constant:-12]
    ]];
    
    // Add width constraint to the container
    [cacheSelectorContainer.widthAnchor constraintEqualToAnchor:self.mainStackView.widthAnchor].active = YES;
    
    // Update the cache selector with available caches
    [self updateCacheSelector];
}

- (void)cacheSelectorChanged:(UISegmentedControl *)sender {
    NSInteger selectedIndex = sender.selectedSegmentIndex;
    
    // If "Current" is selected (index 0), show the most recent IP status
    if (selectedIndex == 0) {
        NSDictionary *cached = [[IPStatusCacheManager sharedManager] loadLastIPStatus];
        if (cached) {
            [self displayIPStatusFromDictionary:cached];
            
            // Update the cache info label
            NSDictionary *scamalytics = cached[@"scamalytics"];
            NSString *ip = [self safeString:scamalytics[@"ip"]];
            NSString *timestamp = [self safeString:cached[@"timestamp"]];
            self.cacheInfoLabel.text = [NSString stringWithFormat:@"IP: %@ - %@", ip, timestamp];
        }
    } else {
        // For other indices, show the corresponding cached IP status
        // Note: We subtract 1 from the index because "Current" is at index 0
        NSInteger cacheIndex = selectedIndex - 1;
        [self displayCachedIPStatusAtIndex:cacheIndex];
    }
}

- (void)displayCachedIPStatusAtIndex:(NSInteger)index {
    NSDictionary *cached = [[IPStatusCacheManager sharedManager] getIPStatusAtIndex:index];
    if (cached) {
        // Update the cache info label
        NSDictionary *scamalytics = cached[@"scamalytics"];
        if ([scamalytics isKindOfClass:[NSDictionary class]]) {
            NSString *ip = [self safeString:scamalytics[@"ip"]];
            NSString *timestamp = [self safeString:cached[@"timestamp"]];
            self.cacheInfoLabel.text = [NSString stringWithFormat:@"IP: %@ - %@", ip, timestamp];
        }
        
        // Display the cached data
        [self displayIPStatusFromDictionary:cached];
    } else {
        // No cache at this index
        self.cacheInfoLabel.text = @"No cached data available";
        
        // Clear the UI
        [self clearIPStatusDisplay];
    }
}

- (NSString *)getTimestampFromCache:(NSInteger)index {
    NSDictionary *cached = [[IPStatusCacheManager sharedManager] getIPStatusAtIndex:index];
    if (cached && cached[@"timestamp"]) {
        return [NSString stringWithFormat:@"%@", cached[@"timestamp"]];
    }
    return @"Unknown date";
}

- (void)clearIPStatusDisplay {
    // Clear all cards
    for (UIView *card in self.mainStackView.arrangedSubviews) {
        if (![card isEqual:self.scoreMeterView] && 
            ![card isEqual:self.scoreLabel] && 
            ![card isEqual:self.refreshButton] &&
            ![card isEqual:self.viewCachedButton] &&
            ![card isEqual:self.activityIndicator] &&
            ![card isEqual:self.cacheSelector.superview]) {
            [self.mainStackView removeArrangedSubview:card];
            [card removeFromSuperview];
        }
    }
    
    // Clear collapsible cards dictionary
    [self.collapsibleCards removeAllObjects];
    
    // Reset score meter
    self.scoreMeterView.score = 0;
    self.scoreMeterView.scoreLabel = @"Risk Score";
    self.scoreLabel.text = @"IP Score: 0 (Unknown)";
    [self.scoreMeterView setNeedsDisplay];
}

- (void)displayCachedIPStatus {
    // Update the cache selector based on available caches
    [self updateCacheSelector];
    
    // Try to load the most recent cache
    NSDictionary *cached = [[IPStatusCacheManager sharedManager] loadLastIPStatus];
    if (cached) {
        [self displayIPStatusFromDictionary:cached];
    } else {
        [self clearIPStatusDisplay];
        
        // Show a message to the user
        UILabel *noDataLabel = [[UILabel alloc] init];
        noDataLabel.text = @"No cached IP data available. Tap 'Fetch IP Details' to get started.";
        noDataLabel.textAlignment = NSTextAlignmentCenter;
        noDataLabel.numberOfLines = 0;
        noDataLabel.textColor = [UIColor secondaryLabelColor];
        [self.mainStackView addArrangedSubview:noDataLabel];
    }
}

- (void)updateCacheSelector {
    NSInteger cacheCount = [[IPStatusCacheManager sharedManager] getCacheCount];
    
    // Remove the old segmented control
    [self.cacheSelector removeFromSuperview];
    
    // Create a new segmented control with the correct number of segments
    NSMutableArray *segmentTitles = [NSMutableArray array];
    
    // Always add "Current" as the first option
    [segmentTitles addObject:@"Current"];
    
    // Add previous entries with timestamps
    for (NSInteger i = 0; i < cacheCount; i++) {
        NSDictionary *cached = [[IPStatusCacheManager sharedManager] getIPStatusAtIndex:i];
        if (cached) {
            NSDictionary *scamalytics = cached[@"scamalytics"];
            NSString *ip = [self safeString:scamalytics[@"ip"]];
            NSString *timestamp = [self safeString:cached[@"timestamp"]];
            
            // Format the segment title to include both IP and timestamp
            NSString *segmentTitle = [NSString stringWithFormat:@"%@ (%@)", ip, timestamp];
            [segmentTitles addObject:segmentTitle];
        }
    }
    
    // Create a new segmented control
    self.cacheSelector = [[UISegmentedControl alloc] initWithItems:segmentTitles];
    self.cacheSelector.selectedSegmentIndex = 0;
    [self.cacheSelector addTarget:self action:@selector(cacheSelectorChanged:) forControlEvents:UIControlEventValueChanged];
    
    // Add the new segmented control to the stack
    UIView *superview = self.cacheSelector.superview;
    if ([superview isKindOfClass:[UIStackView class]]) {
        UIStackView *cacheStack = (UIStackView *)superview;
        [cacheStack insertArrangedSubview:self.cacheSelector atIndex:0];
    }
    
    // Show/hide cache selector based on cache count
    UIView *containerView = self.cacheSelector.superview.superview;
    if (containerView) {
        containerView.hidden = (cacheCount == 0);
    }
    
    // Update the cache info label
    if (cacheCount > 0) {
        NSDictionary *cached = [[IPStatusCacheManager sharedManager] getIPStatusAtIndex:0];
        if (cached) {
            NSDictionary *scamalytics = cached[@"scamalytics"];
            NSString *ip = [self safeString:scamalytics[@"ip"]];
            NSString *timestamp = [self safeString:cached[@"timestamp"]];
            self.cacheInfoLabel.text = [NSString stringWithFormat:@"IP: %@ - %@", ip, timestamp];
        }
    } else {
        self.cacheInfoLabel.text = @"No cached data available";
    }
}

- (void)fetchAndDisplayIPStatus {
    [self.activityIndicator startAnimating];
    self.refreshButton.enabled = NO;

    // Use the multi-service consensus approach for IP detection
    [self fetchCurrentIPWithConsensus:^(NSString *ip, NSError *error) {
        if (error) {
            [self handleError:@"Failed to fetch IP address" withDetails:error.localizedDescription];
            return;
        }
                
        if (!ip || ip.length == 0) {
            [self handleError:@"Invalid IP response" withDetails:@"Could not parse IP address"];
            return;
        }
            
        // Step 2: Call Scamalytics API
        NSString *apiURLString = [NSString stringWithFormat:@"https://api12.scamalytics.com/v3/weaponxhydra/?key=f5622a6ea5ff9748bf9d6e26cf3d59c2eef67c62324e706859c58fc3beb73a6e&ip=%@", ip];
        NSURL *apiURL = [NSURL URLWithString:apiURLString];
        
        NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        NSURLSessionDataTask *apiTask = [session dataTaskWithURL:apiURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            void (^handleFallback)(void) = ^{
                // Fallback to secondary API
                NSString *fallbackURLString = [NSString stringWithFormat:@"https://api12.scamalytics.com/v3/virusdenied9/?key=9852557d3e93e4f732f84fbc3b33a07609cae66d40fe8cbc8eccda6e68cc8e03&ip=%@", ip];
                NSURL *fallbackURL = [NSURL URLWithString:fallbackURLString];
                NSURLSessionDataTask *fallbackTask = [session dataTaskWithURL:fallbackURL completionHandler:^(NSData *fallbackData, NSURLResponse *fallbackResponse, NSError *fallbackError) {
                    if (fallbackError) {
                        [self handleError:@"API Error" withDetails:@"Both primary and fallback IP detail APIs failed."];
                        return;
                    }
                    NSError *fallbackJsonError;
                    NSDictionary *fallbackResult = [NSJSONSerialization JSONObjectWithData:fallbackData options:0 error:&fallbackJsonError];
                    if (fallbackJsonError || !fallbackResult) {
                        [self handleError:@"Parse Error" withDetails:@"Failed to parse fallback IP details."];
                        return;
                    }
                    // Add timestamp before saving
                    NSMutableDictionary *resultWithTimestamp = [fallbackResult mutableCopy];
                    if (resultWithTimestamp && !resultWithTimestamp[@"timestamp"]) {
                        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                        formatter.dateStyle = NSDateFormatterShortStyle;
                        formatter.timeStyle = NSDateFormatterMediumStyle;
                        resultWithTimestamp[@"timestamp"] = [formatter stringFromDate:[NSDate date]];
                    }
                    [[IPStatusCacheManager sharedManager] saveIPStatus:resultWithTimestamp];
                    // Update the cache selector and display the new data
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self updateCacheSelector];
                        [self displayIPStatusFromDictionary:resultWithTimestamp];
                    });
                }];
                [fallbackTask resume];
            };
            if (error) {
                [self handleError:@"API Error" withDetails:@"Failed to fetch IP details. Trying fallback API..."];
                handleFallback();
                return;
            }
            NSError *apiJsonError;
            NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&apiJsonError];
            if (apiJsonError || !result) {
                [self handleError:@"Parse Error" withDetails:@"Failed to parse IP details. Trying fallback API..."];
                handleFallback();
                return;
            }
            // Add timestamp before saving
            NSMutableDictionary *resultWithTimestamp = [result mutableCopy];
            if (resultWithTimestamp && !resultWithTimestamp[@"timestamp"]) {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.dateStyle = NSDateFormatterShortStyle;
                formatter.timeStyle = NSDateFormatterMediumStyle;
                resultWithTimestamp[@"timestamp"] = [formatter stringFromDate:[NSDate date]];
            }
            [[IPStatusCacheManager sharedManager] saveIPStatus:resultWithTimestamp];
            // Update the cache selector and display the new data
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateCacheSelector];
                [self displayIPStatusFromDictionary:resultWithTimestamp];
            });
        }];
        
        [apiTask resume];
    }];
}

- (void)fetchCurrentIPWithConsensus:(void (^)(NSString *ip, NSError *error))completion {
    // Define the services to check - prioritize the fastest ones
    NSArray *services = @[
        @{@"url": @"https://ifconfig.me/ip", @"isJSON": @NO},
        @{@"url": @"https://api.myip.com", @"isJSON": @YES, @"key": @"ip"},
        @{@"url": @"http://ip-api.com/json", @"isJSON": @YES, @"key": @"query"}
    ];
    
    // Create a dictionary to count occurrences of each IP
    NSMutableDictionary *ipCounts = [NSMutableDictionary dictionary];
    NSMutableArray *errors = [NSMutableArray array];
    
    // Create a dispatch group to track all requests
    dispatch_group_t group = dispatch_group_create();
    
    // Create a serial queue for thread safety
    dispatch_queue_t queue = dispatch_queue_create("com.yourapp.ipconsensus", DISPATCH_QUEUE_SERIAL);
    
    // Use a shared session configuration with optimized settings
    static NSURLSessionConfiguration *sharedConfig = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        sharedConfig.timeoutIntervalForRequest = 8.0;  // 8 seconds timeout
        sharedConfig.timeoutIntervalForResource = 20.0; // 20 seconds resource timeout
        sharedConfig.HTTPMaximumConnectionsPerHost = 3; // Limit concurrent connections
    });
    
    // Create a shared session
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sharedConfig];
    
    // Check each service
    for (NSDictionary *service in services) {
        dispatch_group_enter(group);
        
        [self fetchIPFromService:service[@"url"] 
                         isJSON:[service[@"isJSON"] boolValue] 
                           key:service[@"key"]
                     withSession:session
                     completion:^(NSString *ip, NSError *error) {
            dispatch_async(queue, ^{
                if (ip) {
                    // Increment count for this IP
                    NSNumber *count = ipCounts[ip];
                    if (count) {
                        ipCounts[ip] = @([count integerValue] + 1);
                    } else {
                        ipCounts[ip] = @1;
                    }
                } else if (error) {
                    [errors addObject:error];
                }
                
                dispatch_group_leave(group);
            });
        }];
    }
    
    // When all requests complete, find the most common IP
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // Find the IP with the highest count
        NSString *mostCommonIP = nil;
        NSInteger highestCount = 0;
        
        for (NSString *ip in ipCounts) {
            NSInteger count = [ipCounts[ip] integerValue];
            if (count > highestCount) {
                highestCount = count;
                mostCommonIP = ip;
            }
        }
        
        // If we have a consensus (at least 2 services returned the same IP)
        if (highestCount >= 2) {
            completion(mostCommonIP, nil);
        } else {
            // No consensus, use the first successful result if available
            if (mostCommonIP) {
                completion(mostCommonIP, nil);
            } else {
                // All services failed
                NSError *consensusError = [NSError errorWithDomain:@"com.yourapp.ipconsensus" 
                                                             code:1001 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"All IP services failed", 
                                                                    @"underlyingErrors": errors}];
                completion(nil, consensusError);
            }
        }
    });
}

- (void)fetchIPFromService:(NSString *)urlString 
                    isJSON:(BOOL)isJSON 
                      key:(NSString *)jsonKey 
                withSession:(NSURLSession *)session
                completion:(void (^)(NSString *ip, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        if (isJSON) {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) {
                completion(nil, jsonError);
                return;
            }
            
            NSString *ip = json[jsonKey];
            if (!ip || ip.length == 0) {
                NSError *missingError = [NSError errorWithDomain:@"com.yourapp.ipconsensus" 
                                                           code:1002 
                                                       userInfo:@{NSLocalizedDescriptionKey: @"IP not found in JSON response"}];
                completion(nil, missingError);
                return;
            }
            
            completion(ip, nil);
        } else {
            NSString *ip = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            ip = [ip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            if (!ip || ip.length == 0) {
                NSError *emptyError = [NSError errorWithDomain:@"com.yourapp.ipconsensus" 
                                                          code:1003 
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Empty IP response"}];
                completion(nil, emptyError);
                return;
            }
            
            completion(ip, nil);
        }
    }];
    
    [task resume];
}

- (void)handleError:(NSString *)title withDetails:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.activityIndicator stopAnimating];
        self.refreshButton.enabled = YES;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                     message:message
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)displayIPStatusFromDictionary:(NSDictionary *)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.activityIndicator stopAnimating];
        self.refreshButton.enabled = YES;
        
        // Clear existing info views
        for (UIView *view in self.mainStackView.arrangedSubviews) {
            if (![view isEqual:self.scoreMeterView] && 
                ![view isEqual:self.scoreLabel] && 
                ![view isEqual:self.refreshButton] &&
                ![view isEqual:self.viewCachedButton] &&
                ![view isEqual:self.activityIndicator]) {
                [self.mainStackView removeArrangedSubview:view];
                [view removeFromSuperview];
            }
        }
        
        // Clear collapsible cards dictionary
        [self.collapsibleCards removeAllObjects];
        
    NSDictionary *scamalytics = result[@"scamalytics"];
        if (![scamalytics isKindOfClass:[NSDictionary class]]) {
            [self handleError:@"Data Error" withDetails:@"Invalid response format"];
        return;
    }
        
        // Update score meter
    NSInteger score = [scamalytics[@"scamalytics_score"] integerValue];
        NSString *risk = [self safeString:scamalytics[@"scamalytics_risk"]];
        self.scoreMeterView.score = score;
        self.scoreMeterView.scoreLabel = @"Risk Score";
        self.scoreLabel.text = [NSString stringWithFormat:@"IP Score: %ld (%@)", (long)score, risk];
        [self.scoreMeterView setNeedsDisplay];
        
        // Add API Status Card
        [self addInfoCardWithTitle:@"API Status" dictionary:scamalytics keys:@[
            @[@"status", @"Status"],
            @[@"mode", @"Mode"]
        ]];
        
        // Add info cards
        [self addInfoCardWithTitle:@"IP Details" dictionary:scamalytics keys:@[
            @[@"ip", @"IP Address"],
            @[@"scamalytics_isp", @"ISP"],
            @[@"scamalytics_org", @"Organization"],
            @[@"scamalytics_isp_score", @"ISP Score"],
            @[@"scamalytics_isp_risk", @"ISP Risk Level"]
        ]];
        
        NSDictionary *proxy = scamalytics[@"scamalytics_proxy"];
        if ([proxy isKindOfClass:[NSDictionary class]]) {
            [self addInfoCardWithTitle:@"Proxy Information" dictionary:proxy keys:@[
                @[@"is_datacenter", @"Datacenter"],
                @[@"is_vpn", @"VPN"],
                @[@"is_google", @"Google"],
                @[@"is_apple_icloud_private_relay", @"iCloud Private Relay"],
                @[@"is_amazon_aws", @"Amazon AWS"]
            ]];
        }
        
        NSDictionary *external = result[@"external_datasources"];
        
        // --- Proxy & Security Details Card ---
        NSMutableDictionary *proxySecurityDict = [NSMutableDictionary dictionary];
        
        // Add ip2proxy data
        NSDictionary *ip2proxy = external[@"ip2proxy"];
        if ([ip2proxy isKindOfClass:[NSDictionary class]]) {
            if (ip2proxy[@"proxy_type"]) proxySecurityDict[@"Proxy Type"] = [self safeString:ip2proxy[@"proxy_type"]];
        }
        
        // Add ip2proxy_lite data
        NSDictionary *ip2proxy_lite = external[@"ip2proxy_lite"];
        if ([ip2proxy_lite isKindOfClass:[NSDictionary class]]) {
            if (ip2proxy_lite[@"proxy_last_seen"]) proxySecurityDict[@"Proxy Last Seen"] = [self safeString:ip2proxy_lite[@"proxy_last_seen"]];
            if (ip2proxy_lite[@"usage_type"]) proxySecurityDict[@"Usage Type"] = [self safeString:ip2proxy_lite[@"usage_type"]];
            if (ip2proxy_lite[@"ip_provider"]) proxySecurityDict[@"IP Provider"] = [self safeString:ip2proxy_lite[@"ip_provider"]];
            if (ip2proxy_lite[@"ip_blacklist_type"]) proxySecurityDict[@"IP Blacklist Type"] = [self safeString:ip2proxy_lite[@"ip_blacklist_type"]];
        }
        
        // Add x4bnet data
        NSDictionary *x4bnet = external[@"x4bnet"];
        if ([x4bnet isKindOfClass:[NSDictionary class]]) {
            if (x4bnet[@"is_bot_operamini"]) proxySecurityDict[@"Bot (Opera Mini)"] = [x4bnet[@"is_bot_operamini"] boolValue] ? @"Yes" : @"No";
            if (x4bnet[@"is_bot_semrush"]) proxySecurityDict[@"Bot (Semrush)"] = [x4bnet[@"is_bot_semrush"] boolValue] ? @"Yes" : @"No";
        }
        
        if (proxySecurityDict.count > 0) {
            NSMutableArray *proxySecurityArr = [NSMutableArray array];
            for (NSString *key in proxySecurityDict) {
                [proxySecurityArr addObject:@{ @"key": key, @"value": proxySecurityDict[key] }];
            }
            [self addInfoCardWithTitle:@"Proxy & Security Details" dictionary:@{} keys:@[]];
            UIView *lastCard = self.mainStackView.arrangedSubviews.lastObject;
            if ([lastCard isKindOfClass:[UIView class]]) {
                UIStackView *stack = lastCard.subviews.firstObject;
                if ([stack isKindOfClass:[UIStackView class]]) {
                    for (NSDictionary *row in proxySecurityArr) {
                        UILabel *rowLabel = [[UILabel alloc] init];
                        rowLabel.font = [UIFont systemFontOfSize:15];
                        rowLabel.textColor = [UIColor secondaryLabelColor];
                        rowLabel.numberOfLines = 0;
                        rowLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"key"], row[@"value"]];
                        [stack addArrangedSubview:rowLabel];
                    }
                }
            }
        }
        
        // --- Blacklist Status Card ---
        NSMutableDictionary *blacklistDict = [NSMutableDictionary dictionary];
        if ([scamalytics objectForKey:@"is_blacklisted_external"]) {
            blacklistDict[@"Scamalytics External Blacklist"] = [[scamalytics objectForKey:@"is_blacklisted_external"] boolValue] ? @"Yes" : @"No";
        }
        if ([external isKindOfClass:[NSDictionary class]]) {
            NSDictionary *firehol = external[@"firehol"];
            if ([firehol isKindOfClass:[NSDictionary class]]) {
                if (firehol[@"ip_blacklisted_30"]) blacklistDict[@"Firehol Blacklisted (30d)"] = [firehol[@"ip_blacklisted_30"] boolValue] ? @"Yes" : @"No";
                if (firehol[@"ip_blacklisted_1day"]) blacklistDict[@"Firehol Blacklisted (1d)"] = [firehol[@"ip_blacklisted_1day"] boolValue] ? @"Yes" : @"No";
            }
            NSDictionary *ipsum = external[@"ipsum"];
            if ([ipsum isKindOfClass:[NSDictionary class]]) {
                if (ipsum[@"ip_blacklisted"]) blacklistDict[@"Ipsum Blacklisted"] = [ipsum[@"ip_blacklisted"] boolValue] ? @"Yes" : @"No";
                if (ipsum[@"num_blacklists"]) blacklistDict[@"Ipsum Num Blacklists"] = [self safeString:ipsum[@"num_blacklists"]];
            }
            NSDictionary *spamhaus = external[@"spamhaus_drop"];
            if ([spamhaus isKindOfClass:[NSDictionary class]]) {
                if (spamhaus[@"ip_blacklisted"]) blacklistDict[@"Spamhaus DROP Blacklisted"] = [spamhaus[@"ip_blacklisted"] boolValue] ? @"Yes" : @"No";
            }
            NSDictionary *x4bnet = external[@"x4bnet"];
            if ([x4bnet isKindOfClass:[NSDictionary class]]) {
                if (x4bnet[@"is_tor"]) blacklistDict[@"Tor Node"] = [x4bnet[@"is_tor"] boolValue] ? @"Yes" : @"No";
                if (x4bnet[@"is_blacklisted_spambot"]) blacklistDict[@"Spambot"] = [x4bnet[@"is_blacklisted_spambot"] boolValue] ? @"Yes" : @"No";
                if (x4bnet[@"is_vpn"]) blacklistDict[@"VPN (x4bnet)"] = [x4bnet[@"is_vpn"] boolValue] ? @"Yes" : @"No";
                if (x4bnet[@"is_datacenter"]) blacklistDict[@"Datacenter (x4bnet)"] = [x4bnet[@"is_datacenter"] boolValue] ? @"Yes" : @"No";
            }
        }
        if (blacklistDict.count > 0) {
            NSMutableArray *blacklistArr = [NSMutableArray array];
            for (NSString *key in blacklistDict) {
                [blacklistArr addObject:@{ @"key": key, @"value": blacklistDict[key] }];
            }
            [self addInfoCardWithTitle:@"Blacklist Status" dictionary: @{ } keys:@[]];
            UIView *lastCard = self.mainStackView.arrangedSubviews.lastObject;
            if ([lastCard isKindOfClass:[UIView class]]) {
                UIStackView *stack = lastCard.subviews.firstObject;
                if ([stack isKindOfClass:[UIStackView class]]) {
                    UIView *contentView = stack.arrangedSubviews.lastObject;
                    if ([contentView isKindOfClass:[UIView class]]) {
                        UIStackView *contentStack = contentView.subviews.firstObject;
                        if ([contentStack isKindOfClass:[UIStackView class]]) {
                    for (NSDictionary *row in blacklistArr) {
            UILabel *rowLabel = [[UILabel alloc] init];
                        rowLabel.font = [UIFont systemFontOfSize:15];
            rowLabel.textColor = [UIColor secondaryLabelColor];
            rowLabel.numberOfLines = 0;
                        rowLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"key"], row[@"value"]];
                                [contentStack addArrangedSubview:rowLabel];
                            }
                            
                            // Check if all values are "No" and expand the card if there's a "Yes"
                            BOOL allNo = YES;
                            for (NSDictionary *row in blacklistArr) {
                                if ([row[@"value"] isEqualToString:@"Yes"]) {
                                    allNo = NO;
                                    break;
                                }
                            }
                            
                            // If all values are "No", keep the card collapsed
                            if (allNo) {
                                NSDictionary *cardInfo = self.collapsibleCards[@"Blacklist Status"];
                                if (cardInfo) {
                                    UIView *contentView = cardInfo[@"contentView"];
                                    UIImageView *chevron = cardInfo[@"chevron"];
                                    contentView.hidden = YES;
                                    chevron.image = [UIImage systemImageNamed:@"chevron.right"];
                                }
                            } else {
                                // If there's at least one "Yes", expand the card
                                NSDictionary *cardInfo = self.collapsibleCards[@"Blacklist Status"];
                                if (cardInfo) {
                                    UIView *contentView = cardInfo[@"contentView"];
                                    UIImageView *chevron = cardInfo[@"chevron"];
                                    contentView.hidden = NO;
                                    chevron.image = [UIImage systemImageNamed:@"chevron.down"];
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // --- ASN/Provider Details Card ---
        NSMutableArray *asnArr = [NSMutableArray array];
        NSDictionary *maxmind = external[@"maxmind_geolite2"];
        if ([maxmind isKindOfClass:[NSDictionary class]]) {
            if (maxmind[@"asn"]) [asnArr addObject:@{ @"key": @"ASN (MaxMind)", @"value": [self safeString:maxmind[@"asn"]] }];
            if (maxmind[@"as_name"]) [asnArr addObject:@{ @"key": @"AS Name (MaxMind)", @"value": [self safeString:maxmind[@"as_name"]] }];
        }
        NSDictionary *ipinfo = external[@"ipinfo"];
        if ([ipinfo isKindOfClass:[NSDictionary class]]) {
            if (ipinfo[@"asn"]) [asnArr addObject:@{ @"key": @"ASN (ipinfo)", @"value": [self safeString:ipinfo[@"asn"]] }];
            if (ipinfo[@"as_name"]) [asnArr addObject:@{ @"key": @"AS Name (ipinfo)", @"value": [self safeString:ipinfo[@"as_name"]] }];
            if (ipinfo[@"as_domain"]) [asnArr addObject:@{ @"key": @"AS Domain (ipinfo)", @"value": [self safeString:ipinfo[@"as_domain"]] }];
            if (ipinfo[@"ip_range_from"]) [asnArr addObject:@{ @"key": @"IP Range From", @"value": [self safeString:ipinfo[@"ip_range_from"]] }];
            if (ipinfo[@"ip_range_to"]) [asnArr addObject:@{ @"key": @"IP Range To", @"value": [self safeString:ipinfo[@"ip_range_to"]] }];
        }
        if (asnArr.count > 0) {
            [self addInfoCardWithTitle:@"ASN / Provider Details" dictionary:@{} keys:@[]];
            UIView *lastCard = self.mainStackView.arrangedSubviews.lastObject;
            if ([lastCard isKindOfClass:[UIView class]]) {
                UIStackView *stack = lastCard.subviews.firstObject;
                if ([stack isKindOfClass:[UIStackView class]]) {
                    for (NSDictionary *row in asnArr) {
                        UILabel *rowLabel = [[UILabel alloc] init];
                        rowLabel.font = [UIFont systemFontOfSize:15];
                        rowLabel.textColor = [UIColor secondaryLabelColor];
                        rowLabel.numberOfLines = 0;
                        rowLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"key"], row[@"value"]];
                        [stack addArrangedSubview:rowLabel];
                    }
                }
            }
        }
        
        // --- Google-Specific Information Card ---
        NSMutableDictionary *googleDict = [NSMutableDictionary dictionary];
        NSDictionary *google = external[@"google"];
        if ([google isKindOfClass:[NSDictionary class]]) {
            if (google[@"is_google_general"]) googleDict[@"Google General"] = [google[@"is_google_general"] boolValue] ? @"Yes" : @"No";
            if (google[@"is_googlebot"]) googleDict[@"Googlebot"] = [google[@"is_googlebot"] boolValue] ? @"Yes" : @"No";
            if (google[@"is_special_crawler"]) googleDict[@"Special Crawler"] = [google[@"is_special_crawler"] boolValue] ? @"Yes" : @"No";
            if (google[@"is_user_triggered_fetcher"]) googleDict[@"User Triggered Fetcher"] = [google[@"is_user_triggered_fetcher"] boolValue] ? @"Yes" : @"No";
        }
        
        if (googleDict.count > 0) {
            NSMutableArray *googleArr = [NSMutableArray array];
            for (NSString *key in googleDict) {
                [googleArr addObject:@{ @"key": key, @"value": googleDict[key] }];
            }
            [self addInfoCardWithTitle:@"Google-Specific Information" dictionary:@{} keys:@[]];
            UIView *lastCard = self.mainStackView.arrangedSubviews.lastObject;
            if ([lastCard isKindOfClass:[UIView class]]) {
                UIStackView *stack = lastCard.subviews.firstObject;
                if ([stack isKindOfClass:[UIStackView class]]) {
                    UIView *contentView = stack.arrangedSubviews.lastObject;
                    if ([contentView isKindOfClass:[UIView class]]) {
                        UIStackView *contentStack = contentView.subviews.firstObject;
                        if ([contentStack isKindOfClass:[UIStackView class]]) {
                            for (NSDictionary *row in googleArr) {
                                UILabel *rowLabel = [[UILabel alloc] init];
                                rowLabel.font = [UIFont systemFontOfSize:15];
                                rowLabel.textColor = [UIColor secondaryLabelColor];
                                rowLabel.numberOfLines = 0;
                                rowLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"key"], row[@"value"]];
                                [contentStack addArrangedSubview:rowLabel];
                            }
                            
                            // Check if all values are "No" and expand the card if there's a "Yes"
                            BOOL allNo = YES;
                            for (NSDictionary *row in googleArr) {
                                if ([row[@"value"] isEqualToString:@"Yes"]) {
                                    allNo = NO;
                                    break;
                                }
                            }
                            
                            // If all values are "No", keep the card collapsed
                            if (allNo) {
                                NSDictionary *cardInfo = self.collapsibleCards[@"Google-Specific Information"];
                                if (cardInfo) {
                                    UIView *contentView = cardInfo[@"contentView"];
                                    UIImageView *chevron = cardInfo[@"chevron"];
                                    contentView.hidden = YES;
                                    chevron.image = [UIImage systemImageNamed:@"chevron.right"];
                                }
                            } else {
                                // If there's at least one "Yes", expand the card
                                NSDictionary *cardInfo = self.collapsibleCards[@"Google-Specific Information"];
                                if (cardInfo) {
                                    UIView *contentView = cardInfo[@"contentView"];
                                    UIImageView *chevron = cardInfo[@"chevron"];
                                    contentView.hidden = NO;
                                    chevron.image = [UIImage systemImageNamed:@"chevron.down"];
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // --- API Credits Card ---
        NSDictionary *credits = scamalytics[@"credits"];
        if ([credits isKindOfClass:[NSDictionary class]]) {
            [self addInfoCardWithTitle:@"API Credits" dictionary:credits keys:@[
                @[@"used", @"Used"],
                @[@"remaining", @"Remaining"],
                @[@"last_sync_timestamp_utc", @"Last Sync"],
                @[@"seconds_elapsed_since_last_sync", @"Seconds Since Last Sync"],
                @[@"note", @"Note"],
            ]];
        }
        if (scamalytics[@"exec"]) {
            [self addInfoCardWithTitle:@"API Execution Time" dictionary:@{ @"exec": scamalytics[@"exec"] } keys:@[ @[@"exec", @"Execution Time"] ]];
        }
        
        // --- Historical Data Card ---
        NSDictionary *dbip = external[@"dbip"];
        if ([dbip isKindOfClass:[NSDictionary class]] && dbip[@"history_monthly"]) {
            NSDictionary *history = dbip[@"history_monthly"];
            if ([history isKindOfClass:[NSDictionary class]] && history.count > 0) {
                NSMutableArray *historyArr = [NSMutableArray array];
                for (NSString *month in history) {
                    NSDictionary *monthData = history[month];
                    if ([monthData isKindOfClass:[NSDictionary class]]) {
                        NSString *ispName = [self safeString:monthData[@"isp_name"]];
                        NSString *orgName = [self safeString:monthData[@"org_name"]];
                        [historyArr addObject:@{ @"key": month, @"value": [NSString stringWithFormat:@"ISP: %@, Org: %@", ispName, orgName] }];
                    }
                }
                
                if (historyArr.count > 0) {
                    [self addInfoCardWithTitle:@"Historical Data" dictionary:@{} keys:@[]];
                    UIView *lastCard = self.mainStackView.arrangedSubviews.lastObject;
                    if ([lastCard isKindOfClass:[UIView class]]) {
                        UIStackView *stack = lastCard.subviews.firstObject;
                        if ([stack isKindOfClass:[UIStackView class]]) {
                            UIView *contentView = stack.arrangedSubviews.lastObject;
                            if ([contentView isKindOfClass:[UIView class]]) {
                                UIStackView *contentStack = contentView.subviews.firstObject;
                                if ([contentStack isKindOfClass:[UIStackView class]]) {
                                    for (NSDictionary *row in historyArr) {
                                        UILabel *rowLabel = [[UILabel alloc] init];
                                        rowLabel.font = [UIFont systemFontOfSize:15];
                                        rowLabel.textColor = [UIColor secondaryLabelColor];
                                        rowLabel.numberOfLines = 0;
                                        rowLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"key"], row[@"value"]];
                                        [contentStack addArrangedSubview:rowLabel];
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // --- Data Source Last Updated Card ---
        if ([external isKindOfClass:[NSDictionary class]]) {
            NSMutableArray *dsArr = [NSMutableArray array];
            for (NSString *dsKey in external) {
                NSDictionary *ds = external[dsKey];
                if ([ds isKindOfClass:[NSDictionary class]]) {
                    if (ds[@"last_updated_timestamp_utc"]) {
                    NSString *label = [NSString stringWithFormat:@"%@ Last Updated", dsKey];
                    [dsArr addObject:@{ @"key": label, @"value": [self safeString:ds[@"last_updated_timestamp_utc"]] }];
                    }
                    if (ds[@"datasource_name"]) {
                        NSString *label = [NSString stringWithFormat:@"%@ Source", dsKey];
                        [dsArr addObject:@{ @"key": label, @"value": [self safeString:ds[@"datasource_name"]] }];
                    }
                    if (ds[@"license_info"]) {
                        NSString *label = [NSString stringWithFormat:@"%@ License", dsKey];
                        [dsArr addObject:@{ @"key": label, @"value": [self safeString:ds[@"license_info"]] }];
                    }
                }
            }
            if (dsArr.count > 0) {
                [self addInfoCardWithTitle:@"Data Sources Information" dictionary:@{} keys:@[]];
                UIView *lastCard = self.mainStackView.arrangedSubviews.lastObject;
                if ([lastCard isKindOfClass:[UIView class]]) {
                    UIStackView *stack = lastCard.subviews.firstObject;
                    if ([stack isKindOfClass:[UIStackView class]]) {
                        UIView *contentView = stack.arrangedSubviews.lastObject;
                        if ([contentView isKindOfClass:[UIView class]]) {
                            UIStackView *contentStack = contentView.subviews.firstObject;
                            if ([contentStack isKindOfClass:[UIStackView class]]) {
                        for (NSDictionary *row in dsArr) {
                            UILabel *rowLabel = [[UILabel alloc] init];
                            rowLabel.font = [UIFont systemFontOfSize:15];
                            rowLabel.textColor = [UIColor secondaryLabelColor];
                            rowLabel.numberOfLines = 0;
                            rowLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"key"], row[@"value"]];
                                    [contentStack addArrangedSubview:rowLabel];
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // --- Enhanced Location Card ---
        NSMutableDictionary *locationDict = [NSMutableDictionary dictionary];
        
        // Add dbip data
        if ([dbip isKindOfClass:[NSDictionary class]]) {
            if (dbip[@"ip_country_name"]) locationDict[@"Country"] = [self safeString:dbip[@"ip_country_name"]];
            if (dbip[@"ip_state_name"]) locationDict[@"State"] = [self safeString:dbip[@"ip_state_name"]];
            if (dbip[@"ip_city"]) locationDict[@"City"] = [self safeString:dbip[@"ip_city"]];
            if (dbip[@"ip_postcode"]) locationDict[@"Postal Code"] = [self safeString:dbip[@"ip_postcode"]];
            if (dbip[@"ip_geolocation"]) locationDict[@"Coordinates"] = [self safeString:dbip[@"ip_geolocation"]];
            if (dbip[@"connection_type"]) locationDict[@"Connection Type"] = [self safeString:dbip[@"connection_type"]];
        }
        
        // Add maxmind data
        if ([maxmind isKindOfClass:[NSDictionary class]]) {
            if (maxmind[@"ip_time_zone"]) locationDict[@"Time Zone"] = [self safeString:maxmind[@"ip_time_zone"]];
            if (maxmind[@"ip_location_accuracy_km"]) locationDict[@"Location Accuracy"] = [NSString stringWithFormat:@"%@ km", [self safeString:maxmind[@"ip_location_accuracy_km"]]];
            if (maxmind[@"ip_metro_code"]) locationDict[@"Metro Code"] = [self safeString:maxmind[@"ip_metro_code"]];
        }
        
        // Add ipinfo data
        if ([ipinfo isKindOfClass:[NSDictionary class]]) {
            if (ipinfo[@"ip_continent_code"]) locationDict[@"Continent Code"] = [self safeString:ipinfo[@"ip_continent_code"]];
            if (ipinfo[@"ip_continent_name"]) locationDict[@"Continent Name"] = [self safeString:ipinfo[@"ip_continent_name"]];
        }
        
        if (locationDict.count > 0) {
            NSMutableArray *locationArr = [NSMutableArray array];
            for (NSString *key in locationDict) {
                [locationArr addObject:@{ @"key": key, @"value": locationDict[key] }];
            }
            [self addInfoCardWithTitle:@"Location Information" dictionary:@{} keys:@[]];
            UIView *lastCard = self.mainStackView.arrangedSubviews.lastObject;
            if ([lastCard isKindOfClass:[UIView class]]) {
                UIStackView *stack = lastCard.subviews.firstObject;
                if ([stack isKindOfClass:[UIStackView class]]) {
                    for (NSDictionary *row in locationArr) {
                        UILabel *rowLabel = [[UILabel alloc] init];
                        rowLabel.font = [UIFont systemFontOfSize:15];
                        rowLabel.textColor = [UIColor secondaryLabelColor];
                        rowLabel.numberOfLines = 0;
                        rowLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"key"], row[@"value"]];
                        [stack addArrangedSubview:rowLabel];
                    }
                }
            }
        }
    });
}

- (void)addInfoCardWithTitle:(NSString *)title dictionary:(NSDictionary *)dict keys:(NSArray *)keys {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    card.layer.cornerRadius = 12;
    
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    
    // Create header view with title and chevron
    UIView *headerView = [[UIView alloc] init];
    headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:headerView];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [headerView addSubview:titleLabel];
    
    // Add chevron image view
    UIImageView *chevronImageView = [[UIImageView alloc] init];
    chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [headerView addSubview:chevronImageView];
    
    // Set up constraints for header view
    [NSLayoutConstraint activateConstraints:@[
        [headerView.heightAnchor constraintEqualToConstant:44],
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
        [chevronImageView.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
        [chevronImageView.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
        [chevronImageView.widthAnchor constraintEqualToConstant:20],
        [chevronImageView.heightAnchor constraintEqualToConstant:20]
    ]];
    
    // Create content view for the card
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:contentView];
    
    // Add content stack view
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 8;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:contentStack];
    
    // Set up constraints for content stack
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];
    
    // Add content to the stack
    for (NSArray *keyPair in keys) {
        NSString *key = keyPair[0];
        NSString *displayName = keyPair[1];
        id value = dict[key];
        
        NSString *displayValue;
        if ([value isKindOfClass:[NSNumber class]] && [value isKindOfClass:[NSNumber class]]) {
            displayValue = [(NSNumber *)value boolValue] ? @"Yes" : @"No";
        } else {
            displayValue = [self safeString:value];
        }
        
        if (displayValue.length > 0 && ![displayValue isEqualToString:@"-"]) {
            UILabel *label = [[UILabel alloc] init];
            label.text = [NSString stringWithFormat:@"%@: %@", displayName, displayValue];
            label.font = [UIFont systemFontOfSize:15];
            label.numberOfLines = 0;
            [contentStack addArrangedSubview:label];
        }
    }
    
    // Set up constraints for the card
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]
    ]];
    
    [self.mainStackView addArrangedSubview:card];
    
    // Add width constraint to the card
    [card.widthAnchor constraintEqualToAnchor:self.mainStackView.widthAnchor].active = YES;
    
    // Check if this is a collapsible card
    BOOL isCollapsible = [title isEqualToString:@"Historical Data"] || 
                         [title isEqualToString:@"API Credits"] || 
                         [title isEqualToString:@"Data Sources Information"];
    
    if (isCollapsible) {
        // Store the card and its content view for later reference
        self.collapsibleCards[title] = @{
            @"card": card,
            @"contentView": contentView,
            @"chevron": chevronImageView
        };
        
        // Initially collapse the content
        contentView.hidden = YES;
        chevronImageView.image = [UIImage systemImageNamed:@"chevron.right"];
        
        // Add tap gesture recognizer to the header
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCardExpansion:)];
        [headerView addGestureRecognizer:tapGesture];
        headerView.userInteractionEnabled = YES;
        
        // Add a visual indicator that the card is tappable
        headerView.backgroundColor = [UIColor tertiarySystemBackgroundColor];
        headerView.layer.cornerRadius = 8;
    } else {
        // For non-collapsible cards, just show the chevron as down
        chevronImageView.image = [UIImage systemImageNamed:@"chevron.down"];
    }
}

- (void)toggleCardExpansion:(UITapGestureRecognizer *)gesture {
    UIView *headerView = gesture.view;
    
    // Find the card title
    UILabel *titleLabel = headerView.subviews.firstObject;
    NSString *title = titleLabel.text;
    
    // Get the stored information for this card
    NSDictionary *cardInfo = self.collapsibleCards[title];
    if (!cardInfo) return;
    
    UIView *contentView = cardInfo[@"contentView"];
    UIImageView *chevron = cardInfo[@"chevron"];
    
    // Toggle visibility with animation
    [UIView animateWithDuration:0.3 animations:^{
        if (contentView.hidden) {
            contentView.hidden = NO;
            chevron.image = [UIImage systemImageNamed:@"chevron.down"];
        } else {
            contentView.hidden = YES;
            chevron.image = [UIImage systemImageNamed:@"chevron.right"];
        }
    }];
}

- (NSString *)safeString:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value length] > 0 ? value : @"-";
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value stringValue];
    }
    return @"-";
}

- (void)showCachedIPDetails {
    // Get all cached IP statuses
    NSArray *cachedStatuses = [[IPStatusCacheManager sharedManager] getAllCachedIPStatuses];
    
    if (cachedStatuses.count == 0) {
        // Show alert if no cached data
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Cached Data"
                                                                     message:@"There are no cached IP statuses available. Fetch an IP status first."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Create action sheet to show cached IP statuses
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"Select Cached IP Status"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add an action for each cached IP status
    for (NSInteger i = 0; i < cachedStatuses.count; i++) {
        NSDictionary *status = cachedStatuses[i];
        NSDictionary *scamalytics = status[@"scamalytics"];
        NSString *ip = [self safeString:scamalytics[@"ip"]];
        NSString *timestamp = [self safeString:status[@"timestamp"]];
        
        NSString *title = [NSString stringWithFormat:@"%@ - %@", ip, timestamp];
        
        [actionSheet addAction:[UIAlertAction actionWithTitle:title
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * _Nonnull action) {
            // Display the selected IP status
            [self displayIPStatusFromDictionary:status];
            
            // Update the cache selector to match the selected index
            self.cacheSelector.selectedSegmentIndex = i;
            
            // Update the cache info label
            self.cacheInfoLabel.text = [NSString stringWithFormat:@"IP: %@ - %@", ip, timestamp];
        }]];
    }
    
    // Add cancel action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
    
    // Present the action sheet
    [self presentViewController:actionSheet animated:YES completion:nil];
}

@end
