#import "ToolViewController.h"
#import "IPStatusViewController.h"
#import "UberOrderViewController.h"
#import "URLMonitor.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <netdb.h>
#import <sys/socket.h>
#import <fcntl.h>
#import "DoorDashOrderViewController.h"

// For network activities
@interface NetworkSpeedTest : NSObject

@property (nonatomic, copy) void (^progressHandler)(float progress, NSString *status);
@property (nonatomic, copy) void (^updateHandler)(double downloadSpeed, double uploadSpeed);
@property (nonatomic, copy) void (^completionHandler)(NSDictionary *results, NSError *error);
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *downloadTask;
@property (nonatomic, strong) NSURLSessionUploadTask *uploadTask;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval endTime;
@property (nonatomic, assign) long long totalBytesReceived;
@property (nonatomic, assign) long long totalBytesSent;
@property (nonatomic, assign) BOOL isCancelled;
@property (nonatomic, strong) NSTimer *progressUpdateTimer;

- (void)startTest;
- (void)cancel;

@end

@implementation NetworkSpeedTest

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForResource = 30.0;
        config.HTTPMaximumConnectionsPerHost = 5;
        
        self.session = [NSURLSession sessionWithConfiguration:config 
                                                     delegate:nil 
                                                delegateQueue:[NSOperationQueue mainQueue]];
        self.isCancelled = NO;
    }
    return self;
}

- (void)startTest {
    [self testDownloadSpeed];
}

- (void)testDownloadSpeed {
    if (self.isCancelled) return;
    
    if (self.progressHandler) {
        self.progressHandler(0.0, @"Testing download speed...");
    }
    
    // Use a smaller file size for slower connections (5MB instead of 25MB)
    NSURL *url = [NSURL URLWithString:@"https://speed.cloudflare.com/__down?bytes=5000000"];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    self.startTime = CFAbsoluteTimeGetCurrent();
    self.totalBytesReceived = 0;
    
    // Start progress update timer for real-time feedback
    self.progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 
                                                               target:self 
                                                             selector:@selector(updateDownloadProgress) 
                                                             userInfo:nil 
                                                              repeats:YES];
    
    __weak typeof(self) weakSelf = self;
    
    self.downloadTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        [strongSelf.progressUpdateTimer invalidate];
        strongSelf.progressUpdateTimer = nil;
        
        if (strongSelf.isCancelled) return;
        
        if (error) {
            if (strongSelf.completionHandler) {
                strongSelf.completionHandler(nil, error);
            }
            return;
        }
        
        strongSelf.endTime = CFAbsoluteTimeGetCurrent();
        strongSelf.totalBytesReceived = [data length];
        
        NSTimeInterval duration = strongSelf.endTime - strongSelf.startTime;
        double bytesPerSecond = strongSelf.totalBytesReceived / duration;
        double megabitsPerSecond = (bytesPerSecond * 8) / 1000000.0;
        
        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        results[@"downloadSpeed"] = @(megabitsPerSecond);
        
        if (strongSelf.progressHandler) {
            strongSelf.progressHandler(0.5, @"Download test complete. Testing upload speed...");
        }
        
        [strongSelf testUploadSpeed:results];
    }];
    
    [self.downloadTask resume];
}

- (void)updateDownloadProgress {
    // Calculate approximate current speed based on elapsed time
    NSTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval elapsedTime = currentTime - self.startTime;
    
    // Get the current task metrics if available
    if (elapsedTime > 0.5) {
        [self.downloadTask.originalRequest.URL checkResourceIsReachableAndReturnError:nil];
        
        // Just provide a rough estimate based on connection time
        double estimatedSpeed = 0;
        if (self.updateHandler) {
            self.updateHandler(estimatedSpeed, 0);
        }
    }
}

- (void)testUploadSpeed:(NSMutableDictionary *)results {
    if (self.isCancelled) return;
    
    // Generate smaller data to upload (512KB instead of 1MB)
    NSMutableData *uploadData = [NSMutableData dataWithCapacity:512 * 1024];
    for (NSInteger i = 0; i < 512 * 1024 / sizeof(uint32_t); i++) {
        uint32_t randomBits = arc4random();
        [uploadData appendBytes:(void*)&randomBits length:sizeof(uint32_t)];
    }
    
    NSURL *url = [NSURL URLWithString:@"https://speed.cloudflare.com/__up"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    
    self.startTime = CFAbsoluteTimeGetCurrent();
    self.totalBytesSent = 0;
    
    // Start progress update timer for real-time feedback
    self.progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 
                                                               target:self 
                                                             selector:@selector(updateUploadProgress) 
                                                             userInfo:nil 
                                                              repeats:YES];
    
    __weak typeof(self) weakSelf = self;
    
    self.uploadTask = [self.session uploadTaskWithRequest:request fromData:uploadData completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        [strongSelf.progressUpdateTimer invalidate];
        strongSelf.progressUpdateTimer = nil;
        
        if (strongSelf.isCancelled) return;
        
        if (error) {
            if (strongSelf.completionHandler) {
                strongSelf.completionHandler(results, error);
            }
            return;
        }
        
        strongSelf.endTime = CFAbsoluteTimeGetCurrent();
        strongSelf.totalBytesSent = [uploadData length];
        
        NSTimeInterval duration = strongSelf.endTime - strongSelf.startTime;
        double bytesPerSecond = strongSelf.totalBytesSent / duration;
        double megabitsPerSecond = (bytesPerSecond * 8) / 1000000.0;
        
        results[@"uploadSpeed"] = @(megabitsPerSecond);
        
        if (strongSelf.progressHandler) {
            strongSelf.progressHandler(1.0, @"Speed test complete");
        }
        
        if (strongSelf.completionHandler) {
            strongSelf.completionHandler(results, nil);
        }
    }];
    
    [self.uploadTask resume];
}

- (void)updateUploadProgress {
    // Calculate approximate current speed based on elapsed time
    NSTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval elapsedTime = currentTime - self.startTime;
    
    // Get the current task metrics if available
    if (elapsedTime > 0.5) {
        // Just provide a rough estimate based on connection time
        double downloadSpeed = [self.downloadTask.originalRequest.URL checkResourceIsReachableAndReturnError:nil] ? 
                              [[NSUserDefaults standardUserDefaults] doubleForKey:@"lastDownloadSpeed"] : 0;
        
        if (self.updateHandler) {
            self.updateHandler(downloadSpeed, 0);
        }
    }
}

- (void)cancel {
    self.isCancelled = YES;
    [self.downloadTask cancel];
    [self.uploadTask cancel];
    [self.progressUpdateTimer invalidate];
    self.progressUpdateTimer = nil;
}

@end

// For ping test - simplified version
@interface SimplePingHelper : NSObject

@property (nonatomic, copy) void (^pingResultHandler)(NSTimeInterval pingTime, BOOL isSuccess, NSInteger pingNumber);
@property (nonatomic, copy) void (^pingCompleteHandler)(NSTimeInterval averagePing, NSInteger successCount, NSInteger totalCount);
@property (nonatomic, strong) NSString *host;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *pingResults;
@property (nonatomic, assign) NSInteger pingsCompleted;
@property (nonatomic, assign) NSInteger pingsSuccess;
@property (nonatomic, assign) NSInteger totalPings;
@property (nonatomic, assign) BOOL isCancelled;

- (instancetype)initWithHost:(NSString *)host;
- (void)startPingTest;
- (void)cancelPingTest;

@end

@implementation SimplePingHelper

- (instancetype)initWithHost:(NSString *)host {
    self = [super init];
    if (self) {
        // Prepare clean hostname
        _host = [self cleanHostname:host];
        _pingResults = [NSMutableArray array];
        _pingsCompleted = 0;
        _pingsSuccess = 0;
        _totalPings = 5;
        _isCancelled = NO;
        
        // Create session configuration
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 2.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (NSString *)cleanHostname:(NSString *)hostname {
    // Remove protocol if present
    NSString *cleanHost = hostname;
    
    if ([cleanHost hasPrefix:@"https://"]) {
        cleanHost = [cleanHost substringFromIndex:8];
    } else if ([cleanHost hasPrefix:@"http://"]) {
        cleanHost = [cleanHost substringFromIndex:7];
    }
    
    // Remove trailing slash
    if ([cleanHost hasSuffix:@"/"]) {
        cleanHost = [cleanHost substringToIndex:cleanHost.length - 1];
    }
    
    // Remove path components
    NSRange slashRange = [cleanHost rangeOfString:@"/"];
    if (slashRange.location != NSNotFound) {
        cleanHost = [cleanHost substringToIndex:slashRange.location];
    }
    
    return cleanHost;
}

- (void)startPingTest {
    if (self.isCancelled) return;
    
    // Reset ping counters
    self.pingsCompleted = 0;
    self.pingsSuccess = 0;
    [self.pingResults removeAllObjects];
    
    // Start first ping
    [self performSinglePing];
}

- (void)performSinglePing {
    if (self.isCancelled) return;
    
    if (self.pingsCompleted >= self.totalPings) {
        // All pings done, calculate final results
        [self calculateFinalResults];
        return;
    }
    
    NSInteger currentPingNumber = self.pingsCompleted + 1;
    NSTimeInterval startTime = CFAbsoluteTimeGetCurrent();
    
    // First, try to create the most reliable URL possible
    NSString *urlString;
    // Try HTTPS first
    urlString = [NSString stringWithFormat:@"https://%@", self.host];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        // Try HTTP if HTTPS URL creation failed
        urlString = [NSString stringWithFormat:@"http://%@", self.host];
        url = [NSURL URLWithString:urlString];
        
        if (!url) {
            // Both failed, report as timeout
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.isCancelled) return;
                
                NSTimeInterval timeoutValue = 2000; // 2 seconds = timeout
                self.pingsCompleted++;
                
                // Report individual ping result
                if (self.pingResultHandler) {
                    self.pingResultHandler(timeoutValue, NO, currentPingNumber);
                }
                
                // Schedule next ping with delay
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self performSinglePing];
                });
            });
            return;
        }
    }
    
    // Create a HEAD request to minimize data transfer
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"HEAD"];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSTimeInterval endTime = CFAbsoluteTimeGetCurrent();
        NSTimeInterval pingTime = (endTime - startTime) * 1000; // Convert to ms
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.isCancelled) return;
            
            self.pingsCompleted++;
            
            if (!error && response) {
                // Successful ping
                self.pingsSuccess++;
                [self.pingResults addObject:@(pingTime)];
                
                // Report individual ping result
                if (self.pingResultHandler) {
                    self.pingResultHandler(pingTime, YES, currentPingNumber);
                }
            } else {
                // Failed ping (timeout or error) - use max time
                NSTimeInterval timeoutValue = 2000; // 2 seconds = timeout
                
                // Report individual ping result
                if (self.pingResultHandler) {
                    self.pingResultHandler(timeoutValue, NO, currentPingNumber);
                }
            }
            
            // Schedule next ping with delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self performSinglePing];
            });
        });
    }];
    
    [task resume];
}

- (void)calculateFinalResults {
    if (self.isCancelled) return;
    
    NSTimeInterval averagePing = 0;
    
    if (self.pingsSuccess > 0) {
        // Calculate average of successful pings
        double total = 0;
        for (NSNumber *result in self.pingResults) {
            total += [result doubleValue];
        }
        averagePing = total / self.pingsSuccess;
    }
    
    // Call completion handler
    if (self.pingCompleteHandler) {
        self.pingCompleteHandler(averagePing, self.pingsSuccess, self.totalPings);
    }
}

- (void)cancelPingTest {
    self.isCancelled = YES;
    [self.session invalidateAndCancel];
}

@end

@interface ToolViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *pingView;
@property (nonatomic, strong) UIView *speedTestView;
@property (nonatomic, strong) UILabel *pingResultLabel;
@property (nonatomic, strong) UILabel *pingLiveLabel;
@property (nonatomic, strong) UIActivityIndicatorView *pingActivityIndicator;
@property (nonatomic, strong) UILabel *speedTestResultLabel;
@property (nonatomic, strong) UILabel *speedLiveLabel;
@property (nonatomic, strong) UIActivityIndicatorView *speedTestActivityIndicator;
@property (nonatomic, strong) UIProgressView *speedTestProgressView;
@property (nonatomic, strong) UITextField *pingHostTextField;
@property (nonatomic, strong) UIButton *pingStartButton;
@property (nonatomic, strong) UIButton *speedTestStartButton;
@property (nonatomic, strong) SimplePingHelper *pingTest;
@property (nonatomic, strong) NetworkSpeedTest *speedTest;
@property (nonatomic, strong) NSTimer *statusUpdateTimer;

@end

@implementation ToolViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Network Tools";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Register for monitoring status changes 
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                            selector:@selector(monitoringStatusChanged:) 
                                                name:@"UberMonitoringStatusChanged" 
                                              object:nil];
    
    // Add periodic timer to update monitoring status
    self.statusUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                     target:self
                                   selector:@selector(periodicStatusUpdate)
                                   userInfo:nil
                                    repeats:YES];
    
    // Add Done button
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                               target:self 
                                                                               action:@selector(dismissViewController)];
    self.navigationItem.leftBarButtonItem = doneButton;
    
    // Initialize table view
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
    
    // Register table view cells
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ToolCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Refresh the table to update monitoring status
    [self.tableView reloadData];
}

#pragma mark - Table View Data Source / Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5; // IP Status, Uber Orders, DoorDash Orders, Ping, and Speed Test sections
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1; // One cell per section
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"IP STATUS";
    } else if (section == 1) {
        // Use the same monitoring status logic as UberOrderViewController
        BOOL isActive = [URLMonitor isMonitoringActive];
        BOOL isConnected = [URLMonitor isNetworkConnected];
        
        if (isActive) {
            // Get remaining time if available
            NSTimeInterval remainingTime = [URLMonitor getRemainingMonitoringTime];
            
            if (remainingTime > 0) {
                int minutes = (int)ceil(remainingTime / 60.0);
                if (minutes > 1) {
                    return [NSString stringWithFormat:@"UBER ORDER IDS - CAPTURING ACTIVE (%d MINUTES REMAINING)", minutes];
                } else {
                    return [NSString stringWithFormat:@"UBER ORDER IDS - CAPTURING ACTIVE (%d MINUTE REMAINING)", minutes];
                }
            } else {
                return @"UBER ORDER IDS - CAPTURING ACTIVE";
            }
        } else if (!isConnected) {
            return @"UBER ORDER IDS - NETWORK OFFLINE (CAPTURING WILL ACTIVATE)";
        } else {
            return @"UBER ORDER IDS";
        }
    } else if (section == 2) {
        // DoorDash section header
        BOOL isActive = [URLMonitor isMonitoringActive];
        BOOL isConnected = [URLMonitor isNetworkConnected];
        
        if (isActive) {
            // Get remaining time if available
            NSTimeInterval remainingTime = [URLMonitor getRemainingMonitoringTime];
            
            if (remainingTime > 0) {
                int minutes = (int)ceil(remainingTime / 60.0);
                if (minutes > 1) {
                    return [NSString stringWithFormat:@"DOORDASH ORDER IDS - CAPTURING ACTIVE (%d MINUTES REMAINING)", minutes];
                } else {
                    return [NSString stringWithFormat:@"DOORDASH ORDER IDS - CAPTURING ACTIVE (%d MINUTE REMAINING)", minutes];
                }
            } else {
                return @"DOORDASH ORDER IDS - CAPTURING ACTIVE";
            }
        } else if (!isConnected) {
            return @"DOORDASH ORDER IDS - NETWORK OFFLINE (CAPTURING WILL ACTIVATE)";
        } else {
            return @"DOORDASH ORDER IDS";
        }
    } else if (section == 3) {
        return @"PING TEST";
    } else {
        return @"INTERNET SPEED TEST";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ToolCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    // Remove any existing subviews
    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }
    
    if (indexPath.section == 0) {
        // IP Status Cell
        [self configureIPStatusCell:cell];
    } else if (indexPath.section == 1) {
        // Uber Order IDs Cell
        [self configureUberOrdersCell:cell];
    } else if (indexPath.section == 2) {
        // DoorDash Order IDs Cell
        [self configureDoorDashOrdersCell:cell];
    } else if (indexPath.section == 3) {
        // Ping Test Cell
        [self configurePingCell:cell];
    } else {
        // Speed Test Cell
        [self configureSpeedTestCell:cell];
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return 180; // Reduced height for IP status cell
    } else if (indexPath.section == 1) {
        return 180; // Height for Uber orders cell
    } else if (indexPath.section == 2) {
        return 180; // Height for DoorDash orders cell
    } else if (indexPath.section == 3) {
        return 180; // Reduced height for ping cell
    } else {
        return 180; // Reduced height for speed test cell
    }
}

#pragma mark - Cell Configuration

- (void)configureIPStatusCell:(UITableViewCell *)cell {
    // Create IP Status view if it doesn't exist
    UIView *ipStatusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, 180)];
    ipStatusView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Container with gradient background
    UIView *cardContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 12, cell.contentView.bounds.size.width - 30, 156)];
    cardContainer.backgroundColor = [UIColor systemBlueColor];
    cardContainer.layer.cornerRadius = 12;
    
    // Add gradient layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = cardContainer.bounds;
    gradient.colors = @[(id)[[UIColor colorWithRed:0.4 green:0.2 blue:0.7 alpha:1.0] CGColor],
                         (id)[[UIColor colorWithRed:0.2 green:0.1 blue:0.5 alpha:1.0] CGColor]];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    gradient.cornerRadius = 12;
    [cardContainer.layer insertSublayer:gradient atIndex:0];
    
    // Add icon image view
    UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(20, 20, 40, 40)];
    iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    iconImageView.image = [UIImage systemImageNamed:@"shield.checkerboard"];
    iconImageView.tintColor = [UIColor whiteColor];
    [cardContainer addSubview:iconImageView];
    
    // Add title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, cardContainer.bounds.size.width - 40, 30)];
    titleLabel.text = @"Check IP Status";
    titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor whiteColor];
    [cardContainer addSubview:titleLabel];
    
    // Add description label
    UILabel *descriptionLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 105, cardContainer.bounds.size.width - 40, 40)];
    descriptionLabel.text = @"Analyze your IP for risk factors, location, and proxy detection";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = [UIColor whiteColor];
    descriptionLabel.numberOfLines = 2;
    [cardContainer addSubview:descriptionLabel];
    
    // Add arrow indicator
    UIImageView *arrowImageView = [[UIImageView alloc] initWithFrame:CGRectMake(cardContainer.bounds.size.width - 35, cardContainer.bounds.size.height/2 - 15, 24, 24)];
    arrowImageView.contentMode = UIViewContentModeScaleAspectFit;
    arrowImageView.image = [UIImage systemImageNamed:@"chevron.right.circle.fill"];
    arrowImageView.tintColor = [UIColor whiteColor];
    [cardContainer addSubview:arrowImageView];
    
    // Add shadow to the card container
    cardContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    cardContainer.layer.shadowOffset = CGSizeMake(0, 2);
    cardContainer.layer.shadowRadius = 4;
    cardContainer.layer.shadowOpacity = 0.2;
    
    [ipStatusView addSubview:cardContainer];
    [cell.contentView addSubview:ipStatusView];
    
    // Configure tap gesture
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openIPStatusScreen)];
    [cardContainer addGestureRecognizer:tapGesture];
    cardContainer.userInteractionEnabled = YES;
}

- (void)configureUberOrdersCell:(UITableViewCell *)cell {
    // Create Uber Orders view
    UIView *uberOrdersView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, 180)];
    uberOrdersView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Container with gradient background
    UIView *cardContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 12, cell.contentView.bounds.size.width - 30, 156)];
    cardContainer.backgroundColor = [UIColor systemOrangeColor];
    cardContainer.layer.cornerRadius = 12;
    
    // Add gradient layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = cardContainer.bounds;
    gradient.colors = @[(id)[[UIColor colorWithRed:0.9 green:0.5 blue:0.0 alpha:1.0] CGColor],
                         (id)[[UIColor colorWithRed:0.8 green:0.3 blue:0.0 alpha:1.0] CGColor]];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    gradient.cornerRadius = 12;
    [cardContainer.layer insertSublayer:gradient atIndex:0];
    
    // Add icon image view
    UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(20, 20, 40, 40)];
    iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    iconImageView.image = [UIImage systemImageNamed:@"qrcode"];
    iconImageView.tintColor = [UIColor whiteColor];
    [cardContainer addSubview:iconImageView];
    
    // Add title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 65, cardContainer.bounds.size.width - 40, 24)];
    titleLabel.text = @"Uber Order Tracker";
    titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor whiteColor];
    [cardContainer addSubview:titleLabel];
    
    // Get recent orders
    NSArray *recentOrders = [UberOrderViewController getRecentOrderIDs:2];
    
    // Status label showing monitoring status - use same format as UberOrderViewController
    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 94, cardContainer.bounds.size.width - 40, 18)];
    statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    statusLabel.textColor = [UIColor whiteColor];
    
    // Get current monitoring state using same logic as UberOrderViewController
    BOOL isActive = [URLMonitor isMonitoringActive];
    BOOL isConnected = [URLMonitor isNetworkConnected];
    
    if (isActive) {
        // Get remaining time if available
        NSTimeInterval remainingTime = [URLMonitor getRemainingMonitoringTime];
        
        if (remainingTime > 0) {
            int minutes = (int)ceil(remainingTime / 60.0);
            if (minutes > 1) {
                statusLabel.text = [NSString stringWithFormat:@"Monitoring: ACTIVE (%d minutes remaining)", minutes];
            } else {
                statusLabel.text = [NSString stringWithFormat:@"Monitoring: ACTIVE (%d minute remaining)", minutes];
            }
        } else {
            statusLabel.text = @"Monitoring: ACTIVE";
        }
    } else if (!isConnected) {
        statusLabel.text = @"Network OFFLINE (monitoring will activate)";
    } else {
        statusLabel.text = @"Monitoring: Inactive";
    }
    [cardContainer addSubview:statusLabel];
    
    // Recent orders container
    if (recentOrders.count > 0) {
        // Add recent orders label
        int yOffset = 115;
        for (int i = 0; i < MIN(2, recentOrders.count); i++) {
            NSDictionary *orderData = recentOrders[i];
            NSString *orderID = orderData[@"orderID"];
            NSDate *timestamp = orderData[@"timestamp"];
            
            // Format the order ID (truncate if needed)
            NSString *shortOrderID = orderID;
            if (orderID.length > 12) {
                shortOrderID = [NSString stringWithFormat:@"%@...", [orderID substringToIndex:12]];
            }
            
            // Format time ago
            NSString *timeAgo = [UberOrderViewController getTimeElapsedString:timestamp];
            
            // Create order info label
            UILabel *orderLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yOffset, cardContainer.bounds.size.width - 40, 16)];
            orderLabel.text = [NSString stringWithFormat:@"%@ • %@", shortOrderID, timeAgo];
            orderLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
            orderLabel.textColor = [UIColor whiteColor];
            [cardContainer addSubview:orderLabel];
            
            yOffset += 20;
        }
    } else {
        // No orders message
        UILabel *noOrdersLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 115, cardContainer.bounds.size.width - 40, 30)];
        noOrdersLabel.text = isActive ? 
            @"Waiting to capture Uber orders..." : 
            @"Enable monitoring to track orders";
        noOrdersLabel.font = [UIFont systemFontOfSize:12];
        noOrdersLabel.textColor = [UIColor whiteColor];
        noOrdersLabel.alpha = 0.8;
        [cardContainer addSubview:noOrdersLabel];
    }
    
    // Add arrow indicator
    UIImageView *arrowImageView = [[UIImageView alloc] initWithFrame:CGRectMake(cardContainer.bounds.size.width - 35, cardContainer.bounds.size.height/2 - 15, 24, 24)];
    arrowImageView.contentMode = UIViewContentModeScaleAspectFit;
    arrowImageView.image = [UIImage systemImageNamed:@"chevron.right.circle.fill"];
    arrowImageView.tintColor = [UIColor whiteColor];
    [cardContainer addSubview:arrowImageView];
    
    // Add shadow to the card container
    cardContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    cardContainer.layer.shadowOffset = CGSizeMake(0, 2);
    cardContainer.layer.shadowRadius = 4;
    cardContainer.layer.shadowOpacity = 0.2;
    
    [uberOrdersView addSubview:cardContainer];
    [cell.contentView addSubview:uberOrdersView];
    
    // Configure tap gesture
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openUberOrdersScreen)];
    [cardContainer addGestureRecognizer:tapGesture];
    cardContainer.userInteractionEnabled = YES;
}

- (void)configureDoorDashOrdersCell:(UITableViewCell *)cell {
    // Create DoorDash Orders view
    UIView *doorDashOrdersView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, 180)];
    doorDashOrdersView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Container with gradient background
    UIView *cardContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 12, cell.contentView.bounds.size.width - 30, 156)];
    cardContainer.backgroundColor = [UIColor systemRedColor];
    cardContainer.layer.cornerRadius = 12;
    
    // Add gradient layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = cardContainer.bounds;
    gradient.colors = @[(id)[[UIColor colorWithRed:0.9 green:0.1 blue:0.1 alpha:1.0] CGColor],
                         (id)[[UIColor colorWithRed:0.7 green:0.0 blue:0.0 alpha:1.0] CGColor]];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    gradient.cornerRadius = 12;
    [cardContainer.layer insertSublayer:gradient atIndex:0];
    
    // Add icon image view
    UIImageView *iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(20, 20, 40, 40)];
    iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    iconImageView.image = [UIImage systemImageNamed:@"bag"];
    iconImageView.tintColor = [UIColor whiteColor];
    [cardContainer addSubview:iconImageView];
    
    // Add title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 65, cardContainer.bounds.size.width - 40, 24)];
    titleLabel.text = @"DoorDash Order Tracker";
    titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor whiteColor];
    [cardContainer addSubview:titleLabel];
    
    // Get recent orders
    NSArray *recentOrders = [DoorDashOrderViewController getRecentOrderIDs:2];
    
    if (recentOrders.count > 0) {
        // Show recent order IDs
        UILabel *ordersLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 95, cardContainer.bounds.size.width - 40, 50)];
        
        NSMutableString *ordersText = [NSMutableString string];
        for (NSDictionary *order in recentOrders) {
            NSString *orderID = order[@"orderID"];
            NSDate *timestamp = order[@"timestamp"];
            // Truncate the ID to make it more readable
            NSString *shortID = [orderID substringToIndex:MIN(16, orderID.length)];
            
            NSString *timeAgo = [DoorDashOrderViewController getTimeElapsedString:timestamp];
            [ordersText appendFormat:@"%@... (%@)\n", shortID, timeAgo];
        }
        
        ordersLabel.text = ordersText;
        ordersLabel.numberOfLines = 0;
        ordersLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
        ordersLabel.textColor = [UIColor whiteColor];
        [cardContainer addSubview:ordersLabel];
    } else {
        // Show "No orders yet" message
        UILabel *noOrdersLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 95, cardContainer.bounds.size.width - 40, 50)];
        noOrdersLabel.text = @"No orders captured yet.\nTap to view instructions.";
        noOrdersLabel.numberOfLines = 0;
        noOrdersLabel.font = [UIFont systemFontOfSize:14];
        noOrdersLabel.textColor = [UIColor whiteColor];
        [cardContainer addSubview:noOrdersLabel];
    }
    
    // Add tap gesture recognizer
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openDoorDashOrdersScreen)];
    [cardContainer addGestureRecognizer:tapGesture];
    cardContainer.userInteractionEnabled = YES;
    
    [doorDashOrdersView addSubview:cardContainer];
    [cell.contentView addSubview:doorDashOrdersView];
}

- (void)configurePingCell:(UITableViewCell *)cell {
    // Create ping view if it doesn't exist
    if (!self.pingView) {
        self.pingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, 180)];
        self.pingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Host input container with inline label + field
        UIView *hostContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 12, cell.contentView.bounds.size.width - 30, 36)];
        hostContainer.backgroundColor = [UIColor systemGray6Color];
        hostContainer.layer.cornerRadius = 10;
        [self.pingView addSubview:hostContainer];
        
        // Host label
        UILabel *hostLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 50, 36)];
        hostLabel.text = @"Host:";
        hostLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [hostContainer addSubview:hostLabel];
        
        // Host text field
        self.pingHostTextField = [[UITextField alloc] initWithFrame:CGRectMake(60, 0, hostContainer.bounds.size.width - 70, 36)];
        self.pingHostTextField.placeholder = @"8.8.8.8";
        self.pingHostTextField.borderStyle = UITextBorderStyleNone;
        self.pingHostTextField.backgroundColor = [UIColor clearColor];
        self.pingHostTextField.keyboardType = UIKeyboardTypeURL;
        self.pingHostTextField.autocorrectionType = UITextAutocorrectionTypeNo;
        self.pingHostTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.pingHostTextField.returnKeyType = UIReturnKeyDone;
        self.pingHostTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [hostContainer addSubview:self.pingHostTextField];
        
        // Start button
        self.pingStartButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.pingStartButton.frame = CGRectMake(15, 57, cell.contentView.bounds.size.width - 30, 36);
        [self.pingStartButton setTitle:@"Start Ping Test" forState:UIControlStateNormal];
        self.pingStartButton.backgroundColor = [UIColor systemBlueColor];
        self.pingStartButton.tintColor = [UIColor whiteColor];
        self.pingStartButton.layer.cornerRadius = 10;
        self.pingStartButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [self.pingStartButton addTarget:self action:@selector(startPingTest:) forControlEvents:UIControlEventTouchUpInside];
        [self.pingView addSubview:self.pingStartButton];
        
        // Activity indicator
        self.pingActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.pingActivityIndicator.center = CGPointMake(self.pingStartButton.frame.origin.x + 25, self.pingStartButton.center.y);
        self.pingActivityIndicator.hidesWhenStopped = YES;
        [self.pingView addSubview:self.pingActivityIndicator];
        
        // Results container
        UIView *resultsContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 102, cell.contentView.bounds.size.width - 30, 70)];
        resultsContainer.backgroundColor = [UIColor systemGray6Color];
        resultsContainer.layer.cornerRadius = 10;
        [self.pingView addSubview:resultsContainer];
        
        // Live ping results label
        self.pingLiveLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, resultsContainer.bounds.size.width - 20, 24)];
        self.pingLiveLabel.textAlignment = NSTextAlignmentCenter;
        self.pingLiveLabel.numberOfLines = 1;
        self.pingLiveLabel.text = @"";
        self.pingLiveLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
        [resultsContainer addSubview:self.pingLiveLabel];
        
        // Divider
        UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(10, 38, resultsContainer.bounds.size.width - 20, 1)];
        divider.backgroundColor = [UIColor separatorColor];
        [resultsContainer addSubview:divider];
        
        // Result label
        self.pingResultLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 39, resultsContainer.bounds.size.width - 20, 24)];
        self.pingResultLabel.textAlignment = NSTextAlignmentCenter;
        self.pingResultLabel.numberOfLines = 2;
        self.pingResultLabel.text = @"Results will appear here";
        self.pingResultLabel.font = [UIFont systemFontOfSize:14];
        [resultsContainer addSubview:self.pingResultLabel];
    }
    
    [cell.contentView addSubview:self.pingView];
}

- (void)configureSpeedTestCell:(UITableViewCell *)cell {
    // Create speed test view if it doesn't exist
    if (!self.speedTestView) {
        self.speedTestView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, 180)];
        self.speedTestView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Start button
        self.speedTestStartButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.speedTestStartButton.frame = CGRectMake(15, 12, cell.contentView.bounds.size.width - 30, 36);
        [self.speedTestStartButton setTitle:@"Start Speed Test" forState:UIControlStateNormal];
        self.speedTestStartButton.backgroundColor = [UIColor systemBlueColor];
        self.speedTestStartButton.tintColor = [UIColor whiteColor];
        self.speedTestStartButton.layer.cornerRadius = 10;
        self.speedTestStartButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [self.speedTestStartButton addTarget:self action:@selector(startSpeedTest) forControlEvents:UIControlEventTouchUpInside];
        [self.speedTestView addSubview:self.speedTestStartButton];
        
        // Activity indicator
        self.speedTestActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.speedTestActivityIndicator.center = CGPointMake(self.speedTestStartButton.frame.origin.x + 25, self.speedTestStartButton.center.y);
        self.speedTestActivityIndicator.hidesWhenStopped = YES;
        [self.speedTestView addSubview:self.speedTestActivityIndicator];
        
        // Results container
        UIView *resultsContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 57, cell.contentView.bounds.size.width - 30, 115)];
        resultsContainer.backgroundColor = [UIColor systemGray6Color];
        resultsContainer.layer.cornerRadius = 10;
        [self.speedTestView addSubview:resultsContainer];
        
        // Progress view
        self.speedTestProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        self.speedTestProgressView.frame = CGRectMake(15, 15, resultsContainer.bounds.size.width - 30, 10);
        self.speedTestProgressView.trackTintColor = [UIColor systemGray5Color];
        self.speedTestProgressView.progressTintColor = [UIColor systemGreenColor];
        self.speedTestProgressView.layer.cornerRadius = 2;
        self.speedTestProgressView.clipsToBounds = YES; 
        self.speedTestProgressView.transform = CGAffineTransformMakeScale(1.0, 1.5); // Make progress bar slightly taller
        self.speedTestProgressView.hidden = YES;
        [resultsContainer addSubview:self.speedTestProgressView];
        
        // Status label
        self.speedTestResultLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 35, resultsContainer.bounds.size.width - 30, 24)];
        self.speedTestResultLabel.textAlignment = NSTextAlignmentCenter;
        self.speedTestResultLabel.numberOfLines = 1;
        self.speedTestResultLabel.text = @"Ready";
        self.speedTestResultLabel.font = [UIFont systemFontOfSize:14];
        [resultsContainer addSubview:self.speedTestResultLabel];
        
        // Divider
        UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(15, 65, resultsContainer.bounds.size.width - 30, 1)];
        divider.backgroundColor = [UIColor separatorColor];
        [resultsContainer addSubview:divider];
        
        // Live speed results label
        self.speedLiveLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 70, resultsContainer.bounds.size.width - 30, 38)];
        self.speedLiveLabel.textAlignment = NSTextAlignmentCenter;
        self.speedLiveLabel.numberOfLines = 2;
        self.speedLiveLabel.text = @"";
        self.speedLiveLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
        [resultsContainer addSubview:self.speedLiveLabel];
    }
    
    [cell.contentView addSubview:self.speedTestView];
}

#pragma mark - Ping Test Methods

- (void)startPingTest:(id)sender {
    // Dismiss keyboard if active
    [self.view endEditing:YES];
    
    // Get host from text field
    NSString *host = self.pingHostTextField.text;
    if (host.length == 0) {
        host = @"8.8.8.8"; // Default to Google DNS if no host is provided
    }
    
    // Update UI
    [self.pingStartButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.pingStartButton removeTarget:self action:@selector(startPingTest:) forControlEvents:UIControlEventTouchUpInside];
    [self.pingStartButton addTarget:self action:@selector(cancelPingTest) forControlEvents:UIControlEventTouchUpInside];
    [self.pingActivityIndicator startAnimating];
    self.pingResultLabel.text = @"Testing...";
    self.pingResultLabel.textColor = [UIColor labelColor];
    self.pingLiveLabel.text = @"";
    self.pingLiveLabel.textColor = [UIColor labelColor];
    
    // Create and start ping test
    self.pingTest = [[SimplePingHelper alloc] initWithHost:host];
    
    __weak typeof(self) weakSelf = self;
    
    // Set up individual ping result handler
    self.pingTest.pingResultHandler = ^(NSTimeInterval pingTime, BOOL isSuccess, NSInteger pingNumber) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        // Update live result label
        NSString *resultText;
        UIColor *resultColor;
        
        if (isSuccess) {
            resultText = [NSString stringWithFormat:@"Ping #%ld: %.1f ms", (long)pingNumber, pingTime];
            
            // Set color based on ping time
            if (pingTime < 50) {
                resultColor = [UIColor systemGreenColor];
            } else if (pingTime < 100) {
                resultColor = [UIColor systemYellowColor];
            } else {
                resultColor = [UIColor systemRedColor];
            }
        } else {
            resultText = [NSString stringWithFormat:@"Ping #%ld: Timeout", (long)pingNumber];
            resultColor = [UIColor systemRedColor];
        }
        
        strongSelf.pingLiveLabel.text = resultText;
        strongSelf.pingLiveLabel.textColor = resultColor;
    };
    
    // Set up completion handler
    self.pingTest.pingCompleteHandler = ^(NSTimeInterval averagePing, NSInteger successCount, NSInteger totalCount) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        [strongSelf.pingActivityIndicator stopAnimating];
        
        if (successCount == 0) {
            // All pings failed
            strongSelf.pingResultLabel.text = @"Cannot reach host";
            strongSelf.pingResultLabel.textColor = [UIColor systemRedColor];
        } else {
            // Calculate packet loss percentage
            CGFloat packetLoss = 100.0 * (totalCount - successCount) / totalCount;
            
            NSString *result = [NSString stringWithFormat:@"%.1f ms | %.0f%% loss", 
                               averagePing, packetLoss];
            
            strongSelf.pingResultLabel.text = result;
            
            // Set color based on average ping time
            if (averagePing < 50) {
                strongSelf.pingResultLabel.textColor = [UIColor systemGreenColor];
            } else if (averagePing < 100) {
                strongSelf.pingResultLabel.textColor = [UIColor systemYellowColor];
            } else {
                strongSelf.pingResultLabel.textColor = [UIColor systemRedColor];
            }
        }
        
        // Reset the ping button
        [strongSelf.pingStartButton setTitle:@"Start Ping Test" forState:UIControlStateNormal];
        [strongSelf.pingStartButton removeTarget:strongSelf action:@selector(cancelPingTest) forControlEvents:UIControlEventTouchUpInside];
        [strongSelf.pingStartButton addTarget:strongSelf action:@selector(startPingTest:) forControlEvents:UIControlEventTouchUpInside];
    };
    
    [self.pingTest startPingTest];
}

- (void)cancelPingTest {
    [self.pingTest cancelPingTest];
    
    // Reset UI
    [self.pingActivityIndicator stopAnimating];
    self.pingResultLabel.text = @"Cancelled";
    self.pingResultLabel.textColor = [UIColor labelColor];
    self.pingLiveLabel.text = @"";
    
    [self.pingStartButton setTitle:@"Start Ping Test" forState:UIControlStateNormal];
    [self.pingStartButton removeTarget:self action:@selector(cancelPingTest) forControlEvents:UIControlEventTouchUpInside];
    [self.pingStartButton addTarget:self action:@selector(startPingTest:) forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - Speed Test Methods

- (void)startSpeedTest {
    // Update UI
    [self.speedTestStartButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.speedTestStartButton removeTarget:self action:@selector(startSpeedTest) forControlEvents:UIControlEventTouchUpInside];
    [self.speedTestStartButton addTarget:self action:@selector(cancelSpeedTest) forControlEvents:UIControlEventTouchUpInside];
    [self.speedTestActivityIndicator startAnimating];
    self.speedTestProgressView.hidden = NO;
    self.speedTestProgressView.progress = 0.0;
    self.speedTestResultLabel.text = @"Initializing...";
    self.speedTestResultLabel.textColor = [UIColor labelColor];
    self.speedLiveLabel.text = @"";
    self.speedLiveLabel.textColor = [UIColor labelColor];
    
    // Create and start speed test
    self.speedTest = [[NetworkSpeedTest alloc] init];
    
    __weak typeof(self) weakSelf = self;
    
    // Add live update handler
    self.speedTest.updateHandler = ^(double downloadSpeed, double uploadSpeed) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (downloadSpeed > 0) {
            // Show live download speed
            strongSelf.speedLiveLabel.text = [NSString stringWithFormat:@"↓ %.2f Mbps", downloadSpeed];
            strongSelf.speedLiveLabel.textColor = [UIColor systemBlueColor];
        } else if (uploadSpeed > 0) {
            // Show live upload speed
            strongSelf.speedLiveLabel.text = [NSString stringWithFormat:@"↑ %.2f Mbps", uploadSpeed];
            strongSelf.speedLiveLabel.textColor = [UIColor systemPurpleColor];
        }
    };
    
    self.speedTest.progressHandler = ^(float progress, NSString *status) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf.speedTestProgressView.progress = progress;
        strongSelf.speedTestResultLabel.text = status;
    };
    
    self.speedTest.completionHandler = ^(NSDictionary *results, NSError *error) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        [strongSelf.speedTestActivityIndicator stopAnimating];
        strongSelf.speedTestProgressView.hidden = YES;
        
        if (error) {
            strongSelf.speedTestResultLabel.text = @"Error occurred";
            strongSelf.speedLiveLabel.text = error.localizedDescription;
            strongSelf.speedLiveLabel.textColor = [UIColor systemRedColor];
        } else {
            NSNumber *downloadSpeed = results[@"downloadSpeed"];
            NSNumber *uploadSpeed = results[@"uploadSpeed"];
            
            // Save last download speed for reference
            [[NSUserDefaults standardUserDefaults] setDouble:[downloadSpeed doubleValue] forKey:@"lastDownloadSpeed"];
            
            // Update results display
            strongSelf.speedTestResultLabel.text = @"Test Complete";
            
            NSString *result = [NSString stringWithFormat:@"↓ %.2f Mbps\n↑ %.2f Mbps", 
                                [downloadSpeed doubleValue], [uploadSpeed doubleValue]];
            
            strongSelf.speedLiveLabel.text = result;
            
            // Change color based on speeds
            double avgSpeed = ([downloadSpeed doubleValue] + [uploadSpeed doubleValue]) / 2.0;
            if (avgSpeed < 2) { // Lower threshold for proxy connections
                strongSelf.speedLiveLabel.textColor = [UIColor systemRedColor];
            } else if (avgSpeed < 10) { // Lower medium threshold
                strongSelf.speedLiveLabel.textColor = [UIColor systemYellowColor];
            } else {
                strongSelf.speedLiveLabel.textColor = [UIColor systemGreenColor];
            }
        }
        
        // Reset button
        [strongSelf.speedTestStartButton setTitle:@"Start Speed Test" forState:UIControlStateNormal];
        [strongSelf.speedTestStartButton removeTarget:strongSelf action:@selector(cancelSpeedTest) forControlEvents:UIControlEventTouchUpInside];
        [strongSelf.speedTestStartButton addTarget:strongSelf action:@selector(startSpeedTest) forControlEvents:UIControlEventTouchUpInside];
    };
    
    [self.speedTest startTest];
}

- (void)cancelSpeedTest {
    [self.speedTest cancel];
    
    // Reset UI
    [self.speedTestActivityIndicator stopAnimating];
    self.speedTestProgressView.hidden = YES;
    self.speedTestResultLabel.text = @"Cancelled";
    self.speedTestResultLabel.textColor = [UIColor labelColor];
    self.speedLiveLabel.text = @"";
    
    [self.speedTestStartButton setTitle:@"Start Speed Test" forState:UIControlStateNormal];
    [self.speedTestStartButton removeTarget:self action:@selector(cancelSpeedTest) forControlEvents:UIControlEventTouchUpInside];
    [self.speedTestStartButton addTarget:self action:@selector(startSpeedTest) forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - IP Status Methods

- (void)openIPStatusScreen {
    // Create IP Status view controller
    IPStatusViewController *ipStatusVC = [[IPStatusViewController alloc] init];
    
    // Wrap in navigation controller for consistent UI
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:ipStatusVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // Present the view controller
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - Uber Orders Methods

- (void)openUberOrdersScreen {
    // Create Uber Orders view controller
    UberOrderViewController *uberOrdersVC = [UberOrderViewController sharedInstance];
    
    // Wrap in navigation controller for consistent UI
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:uberOrdersVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // Present the view controller
    [self presentViewController:navController animated:YES completion:^{
        // This ensures when returning from the Uber orders screen, we refresh the UI
        [NSNotificationCenter.defaultCenter addObserver:self 
                                              selector:@selector(refreshMonitoringStatus) 
                                                  name:UIApplicationWillEnterForegroundNotification 
                                                object:nil];
    }];
}

- (void)openDoorDashOrdersScreen {
    // Create DoorDash Orders view controller
    DoorDashOrderViewController *doorDashOrdersVC = [DoorDashOrderViewController sharedInstance];
    
    // Wrap in navigation controller for consistent UI
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:doorDashOrdersVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // Present the view controller
    [self presentViewController:navController animated:YES completion:^{
        // This ensures when returning from the DoorDash orders screen, we refresh the UI
        [NSNotificationCenter.defaultCenter addObserver:self 
                                              selector:@selector(refreshMonitoringStatus) 
                                                  name:UIApplicationWillEnterForegroundNotification 
                                                object:nil];
    }];
}

#pragma mark - ViewController Methods

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)monitoringStatusChanged:(NSNotification *)notification {
    // Update the order sections to reflect monitoring status changes
    NSIndexSet *sections = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)];
    [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
}

- (void)refreshMonitoringStatus {
    // Force refresh the order sections to show current monitoring status
    NSIndexSet *sections = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)];
    [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
    
    // Remove the observer since we only need it once
    [NSNotificationCenter.defaultCenter removeObserver:self 
                                               name:UIApplicationWillEnterForegroundNotification 
                                             object:nil];
}

- (void)periodicStatusUpdate {
    // Update the order sections to reflect current monitoring status
    NSIndexSet *sections = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)];
    [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
}

- (void)dealloc {
    // Clean up notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Invalidate the status update timer
    [self.statusUpdateTimer invalidate];
    self.statusUpdateTimer = nil;

    // Cancel any active ping test
    [self cancelPingTest];
    
    // Cancel any active speed test
    [self cancelSpeedTest];
    
    // Invalidate timers
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    // Clean up any other resources
    if (self.pingTest) {
        [self.pingTest cancelPingTest];
        self.pingTest = nil;
    }
    
    if (self.speedTest) {
        [self.speedTest cancel];
        self.speedTest = nil;
    }
}

@end 