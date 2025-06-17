#import "UberOrderViewController.h"
#import "URLMonitor.h"

@interface UberOrderViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *orderData; // Array of dictionaries with orderID and timestamp
@property (nonatomic, strong) UILabel *noDataLabel;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@end

// Forward declarations for callbacks
static void uberOrderCapturedNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void monitoringStateChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

@implementation UberOrderViewController

#pragma mark - URL Scheme Handling

// Add this method to handle URL scheme
+ (BOOL)handleURLScheme:(NSURL *)url {
    // Check if this is our URL scheme
    if (![url.scheme isEqualToString:@"weaponx"]) {
        return NO;
    }
    
    // Check if this is for storing Uber order
    if ([url.host isEqualToString:@"store-uber-order"]) {
        // Parse URL components
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *orderID = nil;
        NSDate *timestamp = nil;
        
        // Extract parameters from query items
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"id"]) {
                orderID = item.value;
            } else if ([item.name isEqualToString:@"timestamp"]) {
                double timestampValue = [item.value doubleValue];
                if (timestampValue > 0) {
                    timestamp = [NSDate dateWithTimeIntervalSince1970:timestampValue];
                }
            }
        }
        
        // Validate and store the order ID
        if (orderID && orderID.length > 0) {
            // Use the existing method to add the order ID
            [UberOrderViewController addOrderID:orderID timestamp:timestamp ?: [NSDate date]];
            
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - Lifecycle

+ (instancetype)sharedInstance {
    static UberOrderViewController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[UberOrderViewController alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _orderData = [NSMutableArray array];
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [_dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
        
        // Load saved order data
        [self loadOrderData];
        
        // Register for Darwin notifications from UberURLHooks
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                      (__bridge const void *)(self),
                                      uberOrderCapturedNotificationCallback,
                                      CFSTR("com.weaponx.uberOrderCaptured"),
                                      NULL,
                                      CFNotificationSuspensionBehaviorDeliverImmediately);
        
        // Also register for monitoring state changes to update UI
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                      (__bridge const void *)(self),
                                      monitoringStateChangedCallback,
                                      CFSTR("com.weaponx.uberMonitoringChanged"),
                                      NULL,
                                      CFNotificationSuspensionBehaviorDeliverImmediately);
        
        // Start file system monitoring timer
        [self setupFileMonitoring];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Uber Order IDs";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Add Done button to navigation bar
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                               target:self 
                                                                               action:@selector(dismissViewController)];
    self.navigationItem.leftBarButtonItem = doneButton;
    
    // Add Clear All button to navigation bar
    UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithTitle:@"Clear All" 
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self 
                                                                   action:@selector(clearAllOrderIDs)];
    
    // Add Info button to navigation bar
    UIBarButtonItem *infoButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
                                                     style:UIBarButtonItemStylePlain
                                                    target:self
                                                    action:@selector(showInstructions)];
    
    self.navigationItem.rightBarButtonItems = @[clearButton, infoButton];
    
    // Setup table view
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Add tableView to the view
    [self.view addSubview:self.tableView];
    
    // Add no data label
    self.noDataLabel = [[UILabel alloc] init];
    self.noDataLabel.text = @"No Uber order IDs captured yet.\n\n"
                           @"HOW TO CAPTURE IDS:\n"
                           @"1. Open the Uber app and go to your orders page\n"
                           @"2. Turn off WiFi and mobile data (airplane mode)\n"
                           @"3. Browse order details in the Uber app\n"
                           @"4. Order IDs will be automatically captured\n"
                           @"5. Return to WeaponX to view captured IDs\n\n"
                           @"Monitoring automatically activates when offline and stays active for 3 minutes.";
    self.noDataLabel.numberOfLines = 0;
    self.noDataLabel.textAlignment = NSTextAlignmentCenter;
    self.noDataLabel.textColor = [UIColor secondaryLabelColor];
    self.noDataLabel.font = [UIFont systemFontOfSize:14];
    self.noDataLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.noDataLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.noDataLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.noDataLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.noDataLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.noDataLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40]
    ]];
    
    // Initialize network monitoring
    [URLMonitor setupNetworkMonitoring];
    
    // Update UI
    [self updateUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Force reload the order data every time the view appears
    [self loadOrderData];
    
    // Update UI to reflect current data
    [self updateUI];
    
    // Update section header to show monitoring state
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Add a manual reload button for testing
    UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                  target:self
                                                                                  action:@selector(manualReload)];
    self.navigationItem.rightBarButtonItems = @[self.navigationItem.rightBarButtonItems[0], 
                                               self.navigationItem.rightBarButtonItems[1], 
                                               refreshButton];
}

#pragma mark - Public Methods

+ (void)addOrderID:(NSString *)orderID timestamp:(NSDate *)timestamp {
    if (!orderID || orderID.length == 0) return;
    
    // Create the new order entry
    NSDictionary *orderEntry = @{
        @"orderID": orderID,
        @"timestamp": timestamp ?: [NSDate date]
    };
    
    // Save to NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Load existing order IDs
    NSMutableArray *orderIDs = [[defaults objectForKey:@"UberCapturedOrderIDs"] mutableCopy];
    if (!orderIDs) {
        orderIDs = [NSMutableArray array];
    }
    
    // Check if order ID already exists
    BOOL exists = NO;
    for (NSDictionary *entry in orderIDs) {
        if ([entry[@"orderID"] isEqualToString:orderID]) {
            exists = YES;
            break;
        }
    }
    
    // Only add if it doesn't exist
    if (!exists) {
        [orderIDs insertObject:orderEntry atIndex:0]; // Add to top
        
        // Keep only the last 50 entries
        if (orderIDs.count > 50) {
            [orderIDs removeObjectsInRange:NSMakeRange(50, orderIDs.count - 50)];
        }
        
        // Save back to NSUserDefaults with both keys for compatibility
        [defaults setObject:orderIDs forKey:@"UberCapturedOrderIDs"];
        [defaults setObject:orderIDs forKey:@"UberOrderData"]; // Also save to the old key
        
        // Also notify the shared instance to reload if it exists
        UberOrderViewController *sharedInstance = [UberOrderViewController sharedInstance];
        if (sharedInstance) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [sharedInstance loadOrderData];
                [sharedInstance updateUI];
            });
        }
    }
}

+ (NSArray *)getRecentOrderIDs:(NSInteger)count {
    UberOrderViewController *instance = [UberOrderViewController sharedInstance];
    NSMutableArray *recentOrders = [NSMutableArray array];
    
    // Load if not already loaded
    if (instance.orderData.count == 0) {
        [instance loadOrderData];
    }
    
    // Get the most recent orders up to the requested count
    NSInteger maxCount = MIN(count, instance.orderData.count);
    for (NSInteger i = 0; i < maxCount; i++) {
        [recentOrders addObject:instance.orderData[i]];
    }
    
    return recentOrders;
}

+ (NSString *)getTimeElapsedString:(NSDate *)timestamp {
    if (!timestamp) return @"";
    
    NSTimeInterval timeInterval = -[timestamp timeIntervalSinceNow];
    
    // Less than a minute
    if (timeInterval < 60) {
        return @"just now";
    }
    // Less than an hour
    else if (timeInterval < 3600) {
        int minutes = (int)timeInterval / 60;
        return [NSString stringWithFormat:@"%d min%@ ago", minutes, minutes > 1 ? @"s" : @""];
    }
    // Less than a day
    else if (timeInterval < 86400) {
        int hours = (int)timeInterval / 3600;
        return [NSString stringWithFormat:@"%d hour%@ ago", hours, hours > 1 ? @"s" : @""];
    }
    // Less than a week
    else if (timeInterval < 604800) {
        int days = (int)timeInterval / 86400;
        return [NSString stringWithFormat:@"%d day%@ ago", days, days > 1 ? @"s" : @""];
    }
    // More than a week
    else {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterShortStyle];
        [formatter setTimeStyle:NSDateFormatterNoStyle];
        return [formatter stringFromDate:timestamp];
    }
}

#pragma mark - Private Methods

- (void)loadOrderData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *allOrderData = [NSMutableArray array];
    
    // Check all possible NSUserDefaults keys for order IDs
    NSArray *savedData = [defaults objectForKey:@"UberOrderData"];
    if (savedData && savedData.count > 0) {
        for (NSDictionary *orderEntry in savedData) {
            [self mergeOrderEntry:orderEntry intoArray:allOrderData];
        }
    }
    
    NSArray *newSavedData = [defaults objectForKey:@"UberCapturedOrderIDs"];
    if (newSavedData && newSavedData.count > 0) {
        for (NSDictionary *orderEntry in newSavedData) {
            [self mergeOrderEntry:orderEntry intoArray:allOrderData];
        }
    }
    
    // Sort by timestamp (newest first)
    [allOrderData sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSDate *date1 = [obj1 objectForKey:@"timestamp"];
        NSDate *date2 = [obj2 objectForKey:@"timestamp"];
        return [date2 compare:date1];
    }];
    
    // Update our data
    self.orderData = allOrderData;
}

- (void)mergeOrderEntry:(NSDictionary *)orderEntry intoArray:(NSMutableArray *)array {
    if (!orderEntry || !orderEntry[@"orderID"]) return;
    
    NSString *newOrderID = orderEntry[@"orderID"];
    BOOL isDuplicate = NO;
    
    for (NSDictionary *existingOrder in array) {
        if ([existingOrder[@"orderID"] isEqualToString:newOrderID]) {
            isDuplicate = YES;
            break;
        }
    }
    
    if (!isDuplicate) {
        [array addObject:orderEntry];
    }
}

- (void)saveOrderData {
    // Save to NSUserDefaults for cross-process communication
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Save to both keys for backward compatibility
    [defaults setObject:self.orderData forKey:@"UberOrderData"];
    [defaults setObject:self.orderData forKey:@"UberCapturedOrderIDs"];
    // No need to call synchronize, iOS handles this automatically
    
    // Post notification that the data has changed
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)@"com.weaponx.uberOrderDataChanged",
                                         NULL, NULL, YES);
}

- (void)updateUI {
    self.noDataLabel.hidden = (self.orderData.count > 0);
    [self.tableView reloadData];
}

- (void)clearAllOrderIDs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear All Order IDs" 
                                                                  message:@"Are you sure you want to delete all captured Uber order IDs?" 
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self.orderData removeAllObjects];
        [self saveOrderData];
        [self updateUI];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyOrderIDToClipboard:(NSString *)orderID {
    // Use URL format for copying
    NSString *orderURL = [self getOrderURLForID:orderID];
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = orderURL;
    
    // Show a toast notification
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil
                                                                 message:@"Order URL copied to clipboard"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:toast animated:YES completion:nil];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1; // Only one section now (order IDs)
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.orderData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *orderCellId = @"OrderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:orderCellId];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:orderCellId];
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
        cell.textLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightRegular];
    }
    
    if (indexPath.row < self.orderData.count) {
        NSDictionary *order = self.orderData[indexPath.row];
        NSString *orderID = order[@"orderID"];
        NSDate *timestamp = order[@"timestamp"];
        
        // Format "time ago" string
        NSString *timeAgoStr = [UberOrderViewController getTimeElapsedString:timestamp];
        
        cell.textLabel.text = orderID;
        cell.detailTextLabel.text = timeAgoStr;
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    BOOL isActive = [URLMonitor isMonitoringActive];
    BOOL isConnected = [URLMonitor isNetworkConnected];
    
    if (isActive) {
        // Get remaining time if available
        NSTimeInterval remainingTime = [URLMonitor getRemainingMonitoringTime];
        
        if (remainingTime > 0) {
            int minutes = (int)ceil(remainingTime / 60.0);
            if (minutes > 1) {
                return [NSString stringWithFormat:@"ORDER IDS - CAPTURING ACTIVE (%d MINUTES REMAINING)", minutes];
            } else {
                return [NSString stringWithFormat:@"ORDER IDS - CAPTURING ACTIVE (%d MINUTE REMAINING)", minutes];
            }
        } else {
            return @"ORDER IDS - CAPTURING ACTIVE";
        }
    } else if (!isConnected) {
        return @"ORDER IDS - NETWORK OFFLINE (CAPTURING WILL ACTIVATE)";
    } else {
        return @"CAPTURED ORDER IDS";
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Delete action
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                              title:@"Delete"
                                                                            handler:^(UIContextualAction * _Nonnull action, UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        // Confirm deletion
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Order ID" 
                                                                      message:@"Are you sure you want to delete this order ID?" 
                                                               preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            completionHandler(NO);
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            // Use the safe delete method
            [self safelyDeleteOrderAtIndex:indexPath.row fromTableView:tableView];
            completionHandler(YES);
        }]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }];
    
    // Return the configuration with all actions
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    return configuration;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.orderData.count) {
        NSDictionary *order = self.orderData[indexPath.row];
        NSString *orderID = order[@"orderID"];
        
        // Share action
        UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                 title:@"Share"
                                                                               handler:^(UIContextualAction * _Nonnull action, UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            if (indexPath.row < self.orderData.count) {
                [self shareOrderURL:orderID];
            }
            completionHandler(YES);
        }];
        shareAction.backgroundColor = [UIColor systemBlueColor];
        
        // Open action
        UIContextualAction *openAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                title:@"Open"
                                                                              handler:^(UIContextualAction * _Nonnull action, UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            if (indexPath.row < self.orderData.count) {
                [self openOrderURL:orderID];
            }
            completionHandler(YES);
        }];
        openAction.backgroundColor = [UIColor systemGreenColor];
        
        // Return the configuration with all actions
        UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[openAction, shareAction]];
        return configuration;
    } else {
        return nil;
    }
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // Copy order ID to clipboard when selected
    NSDictionary *order = self.orderData[indexPath.row];
    NSString *orderID = order[@"orderID"];
    [self copyOrderIDToClipboard:orderID];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.orderData.count) {
        NSDictionary *order = self.orderData[indexPath.row];
        NSString *orderID = order[@"orderID"];
        NSDate *timestamp = order[@"timestamp"];
        
        // Format timestamp string
        NSString *timeStr = [self.dateFormatter stringFromDate:timestamp];
        NSString *timeAgoStr = [UberOrderViewController getTimeElapsedString:timestamp];
        NSString *orderURL = [self getOrderURLForID:orderID];
        
        // Show details alert with additional options
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Order ID Details"
                                                                      message:[NSString stringWithFormat:@"ID: %@\nCaptured: %@ (%@)\nURL: %@", 
                                                                                orderID, timeStr, timeAgoStr, orderURL]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy URL" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self copyOrderIDToClipboard:orderID];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Share" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self shareOrderURL:orderID];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Open in Browser" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self openOrderURL:orderID];
        }]];
        
        // Add Delete option
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            // Confirm deletion
            UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Confirm Delete"
                                                                              message:@"Are you sure you want to delete this order ID?"
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            
            [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                // Use the safe delete method
                [self safelyDeleteOrderAtIndex:indexPath.row fromTableView:tableView];
            }]];
            
            [self presentViewController:confirmAlert animated:YES completion:nil];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)dealloc {
    // Remove Darwin notification observer
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                     (__bridge const void *)(self),
                                     CFSTR("com.weaponx.uberOrderCaptured"),
                                     NULL);
    
    // Remove NSNotificationCenter observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)manualReload {
    // Reload data from NSUserDefaults
    [self loadOrderData];
    [self updateUI];
    
    // Check if we have any data
    if (self.orderData.count > 0) {
        // Show success alert with data count
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Data Reloaded"
                                                                      message:[NSString stringWithFormat:@"Found %lu Uber order IDs in NSUserDefaults", (unsigned long)self.orderData.count]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        // No data found, offer to create sample data
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Create Sample Order ID?"
                                                                      message:@"No Uber order IDs found. Would you like to create a sample order ID for testing?"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            // Create a sample order ID
            NSString *sampleOrderID = @"986af4af-551a-45b9-af40-6581bbc892aa";
            NSDate *timestamp = [NSDate date];
            
            // Add directly to NSUserDefaults using the class method
            [UberOrderViewController addOrderID:sampleOrderID timestamp:timestamp];
            
            // Reload to display the new data
            [self loadOrderData];
            [self updateUI];
            
            // Show success alert
            UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:@"Sample Data Created"
                                                                              message:[NSString stringWithFormat:@"Sample order ID created: %@", sampleOrderID]
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [resultAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:resultAlert animated:YES completion:nil];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleCancel handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)setupFileMonitoring {
    // Register for NSUserDefaults changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDefaultsChanged:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
    
    // Also register for monitoring status changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(monitoringStatusChanged:)
                                                 name:@"UberMonitoringStatusChanged"
                                               object:nil];
    
    // Check user defaults periodically
    [NSTimer scheduledTimerWithTimeInterval:5.0 // Check every 5 seconds
                                     target:self
                                   selector:@selector(checkUserDefaults)
                                   userInfo:nil
                                    repeats:YES];
    
    // Check monitoring status periodically
    [NSTimer scheduledTimerWithTimeInterval:3.0 // Check every 3 seconds
                                     target:self
                                   selector:@selector(checkMonitoringStatus)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)userDefaultsChanged:(NSNotification *)notification {
    [self checkUserDefaults];
}

- (void)checkUserDefaults {
    static NSInteger lastCount = 0;
    
    // Get current count
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *orderData = [defaults objectForKey:@"UberCapturedOrderIDs"];
    if (!orderData) {
        orderData = [defaults objectForKey:@"UberOrderData"];
    }
    
    NSInteger currentCount = orderData.count;
    
    // Check if count changed
    if (currentCount != lastCount) {
        lastCount = currentCount;
        
        // Reload data
        [self loadOrderData];
        [self updateUI];
    }
}

- (void)monitoringStatusChanged:(NSNotification *)notification {
    // Update UI when monitoring status changes
    [self checkMonitoringStatus];
}

- (void)checkMonitoringStatus {
    // Check if we should force a UI update based on monitoring state
    BOOL isActive = [URLMonitor isMonitoringActive];
    
    // Store the value to detect changes
    static BOOL lastActiveState = NO;
    
    if (isActive != lastActiveState) {
        // The monitoring state has changed, update UI
        lastActiveState = isActive;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update section title to reflect monitoring state
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
        });
    }
}

// Helper method to generate the full Uber order URL
- (NSString *)getOrderURLForID:(NSString *)orderID {
    return [NSString stringWithFormat:@"https://www.ubereats.com/orders/%@", orderID];
}

// Share order URL
- (void)shareOrderURL:(NSString *)orderID {
    NSString *orderURL = [self getOrderURLForID:orderID];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] 
                                           initWithActivityItems:@[orderURL]
                                           applicationActivities:nil];
    
    // On iPad, we need to set the source view for the popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        NSInteger row = [self.orderData indexOfObjectPassingTest:^BOOL(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj[@"orderID"] isEqualToString:orderID];
        }];
        
        if (row != NSNotFound) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
            activityVC.popoverPresentationController.sourceView = cell;
            activityVC.popoverPresentationController.sourceRect = cell.bounds;
        } else {
            activityVC.popoverPresentationController.sourceView = self.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
        }
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

// Open order URL in browser
- (void)openOrderURL:(NSString *)orderID {
    NSString *orderURL = [self getOrderURLForID:orderID];
    NSURL *url = [NSURL URLWithString:orderURL];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Open URL"
                                                                              message:@"Unable to open the Uber order URL."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invalid URL"
                                                                      message:@"The URL format is not valid."
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

// Add a safe delete method that all delete operations will use
- (void)safelyDeleteOrderAtIndex:(NSInteger)index fromTableView:(UITableView *)tableView {
    // Ensure we're on the main thread
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self safelyDeleteOrderAtIndex:index fromTableView:tableView];
        });
        return;
    }
    
    // Validate index
    if (index < 0 || index >= self.orderData.count) {
        return;
    }
    
    // Create a new mutable copy of the order data
    NSMutableArray *updatedArray = [self.orderData mutableCopy];
    
    // Remove the item at the specified index
    [updatedArray removeObjectAtIndex:index];
    
    // Update the data source
    self.orderData = updatedArray;
    
    // Save changes
    [self saveOrderData];
    
    // Update the UI
    [self updateUI];
}

// Add callback for monitoring state changes
static void monitoringStateChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UberOrderViewController *controller = (__bridge UberOrderViewController *)observer;
        [controller checkMonitoringStatus];
    });
}

static void uberOrderCapturedNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Load the captured order IDs from NSUserDefaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // First try the new format key
        NSArray *orderData = [defaults objectForKey:@"UberCapturedOrderIDs"];
        
        // If not found, try the old key
        if (!orderData || orderData.count == 0) {
            orderData = [defaults objectForKey:@"UberOrderData"];
        }
        
        if (orderData && orderData.count > 0) {
            // Get the latest order
            NSDictionary *latestOrder = orderData[0];
            NSString *orderID = latestOrder[@"orderID"];
            NSDate *timestamp = latestOrder[@"timestamp"];
            
            // Add to our local storage and update UI
            [UberOrderViewController addOrderID:orderID timestamp:timestamp];
            
            // Post notification to update main tool screen
            [[NSNotificationCenter defaultCenter] postNotificationName:@"UberMonitoringStatusChanged" object:nil];
        }
    });
}

- (void)showInstructions {
    // Show alert with detailed instructions
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"How to Capture Uber Order IDs" 
                                                                  message:@"The network-based monitoring system automatically activates when your internet connection is down.\n\n"
                                                                         @"To capture Uber order IDs:\n\n"
                                                                         @"1. Open the Uber app and navigate to your Orders section\n\n"
                                                                         @"2. Put your device in Airplane Mode (or turn off both WiFi and cellular data)\n\n"
                                                                         @"3. Browse through your Uber orders - the IDs will be automatically captured\n\n"
                                                                         @"4. Return to WeaponX to see your captured order IDs\n\n"
                                                                         @"The monitoring automatically stays active for 3 minutes when offline, and extends as needed if you're still offline."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Got it!" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end 