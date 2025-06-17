#import "DoorDashOrderViewController.h"
#import "URLMonitor.h"

@interface DoorDashOrderViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *orderData; // Array of dictionaries with orderID and timestamp
@property (nonatomic, strong) UILabel *noDataLabel;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@end

// Forward declarations for callbacks
static void doorDashOrderCapturedNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void monitoringStateChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

// Function to toggle monitoring
extern void setMonitoringEnabled(BOOL enabled);

@implementation DoorDashOrderViewController

#pragma mark - URL Scheme Handling

// Add this method to handle URL scheme
+ (BOOL)handleURLScheme:(NSURL *)url {
    // Check if this is our URL scheme
    if (![url.scheme isEqualToString:@"weaponx"]) {
        NSLog(@"[DoorDashOrder] ❌ Rejected URL with wrong scheme: %@", url.scheme);
        return NO;
    }
    
    // Check if this is for storing DoorDash order
    if ([url.host isEqualToString:@"store-doordash-order"]) {
        NSLog(@"[DoorDashOrder] 📲 Received DoorDash order URL scheme: %@", url);
        
        // Parse URL components
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *orderID = nil;
        NSDate *timestamp = nil;
        
        // Extract parameters from query items
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"id"]) {
                orderID = item.value;
                NSLog(@"[DoorDashOrder] 🏷️ Found order ID parameter: %@", orderID);
            } else if ([item.name isEqualToString:@"timestamp"]) {
                double timestampValue = [item.value doubleValue];
                if (timestampValue > 0) {
                    timestamp = [NSDate dateWithTimeIntervalSince1970:timestampValue];
                    NSLog(@"[DoorDashOrder] ⏰ Found timestamp parameter: %@", timestamp);
                }
            }
        }
        
        // Validate and store the order ID
        if (orderID && orderID.length > 0) {
            NSLog(@"[DoorDashOrder] 🎯 Processing DoorDash order ID: %@", orderID);
            
            // Use the existing method to add the order ID
            [DoorDashOrderViewController addOrderID:orderID timestamp:timestamp ?: [NSDate date]];
            
            NSLog(@"[DoorDashOrder] ✅ Successfully handled DoorDash order ID from URL scheme");
            return YES;
        } else {
            NSLog(@"[DoorDashOrder] ❌ Invalid DoorDash order ID in URL scheme");
        }
    } else {
        NSLog(@"[DoorDashOrder] ⚠️ URL has correct scheme but wrong host: %@", url.host);
    }
    
    return NO;
}

#pragma mark - Lifecycle

+ (instancetype)sharedInstance {
    static DoorDashOrderViewController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DoorDashOrderViewController alloc] init];
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
        
        // Register for Darwin notifications from URLHooks
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                      (__bridge const void *)(self),
                                      doorDashOrderCapturedNotificationCallback,
                                      CFSTR("com.weaponx.doorDashOrderCaptured"),
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
    
    self.title = @"DoorDash Order IDs";
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
    
    // Set navigation bar buttons
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
    self.noDataLabel.text = @"No DoorDash order IDs captured yet.\n\n"
                           @"HOW TO CAPTURE IDS:\n"
                           @"1. Open the DoorDash app and go to your orders page\n"
                           @"2. Turn off WiFi and mobile data (airplane mode)\n"
                           @"3. Browse order details in the DoorDash app\n"
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
    
    // Always print this log when the view appears to confirm the controller is working
    NSLog(@"[DoorDashOrder_DEBUG] 🖥️ DoorDash Order view controller appeared");
    
    // Debug info about current order data
    NSLog(@"[DoorDashOrder_DEBUG] 📋 Current order count: %lu", (unsigned long)self.orderData.count);
    
    // Check NSUserDefaults directly
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *savedData = [defaults objectForKey:@"DoorDashCapturedOrderIDs"];
    if (savedData) {
        NSLog(@"[DoorDashOrder_DEBUG] 💾 NSUserDefaults contains %lu DoorDash orders", (unsigned long)savedData.count);
        // Log the first few order IDs
        NSInteger count = MIN(savedData.count, 3);
        for (NSInteger i = 0; i < count; i++) {
            NSDictionary *order = savedData[i];
            NSLog(@"[DoorDashOrder_DEBUG] 🔖 Order #%ld: %@ (%@)", 
                  (long)i + 1, 
                  order[@"orderID"], 
                  order[@"timestamp"]);
        }
    } else {
        NSLog(@"[DoorDashOrder_DEBUG] ⚠️ No DoorDash orders in NSUserDefaults");
    }
}

#pragma mark - Public Methods

+ (void)addOrderID:(NSString *)orderID timestamp:(NSDate *)timestamp {
    if (!orderID || orderID.length == 0) {
        NSLog(@"[DoorDashOrder] ❌ Attempted to add empty or nil order ID");
        return;
    }
    
    NSLog(@"[DoorDashOrder] 📝 Adding DoorDash order ID: %@", orderID);
    NSLog(@"[DoorDashOrder] 🔗 Full URL: https://track.doordash.com/share/%@/track", orderID);
    
    // Create the new order entry
    NSDictionary *orderEntry = @{
        @"orderID": orderID,
        @"timestamp": timestamp ?: [NSDate date],
        @"type": @"doordash"
    };
    
    NSLog(@"[DoorDashOrder] 📦 Created order entry with timestamp: %@", orderEntry[@"timestamp"]);
    
    // Save to NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSLog(@"[DoorDashOrder] 🔍 Accessing NSUserDefaults to store order");
    
    // Load existing order IDs
    NSMutableArray *orderIDs = [[defaults objectForKey:@"DoorDashCapturedOrderIDs"] mutableCopy];
    if (!orderIDs) {
        orderIDs = [NSMutableArray array];
        NSLog(@"[DoorDashOrder] 🆕 Creating new DoorDash orders array in NSUserDefaults");
    } else {
        NSLog(@"[DoorDashOrder] 📋 Found existing orders array with %lu entries", (unsigned long)orderIDs.count);
    }
    
    // Check if order ID already exists
    BOOL exists = NO;
    for (NSDictionary *entry in orderIDs) {
        if ([entry[@"orderID"] isEqualToString:orderID]) {
            exists = YES;
            NSLog(@"[DoorDashOrder] 🔄 Found duplicate order ID at index %lu", (unsigned long)[orderIDs indexOfObject:entry]);
            break;
        }
    }
    
    // Only add if it doesn't exist
    if (!exists) {
        NSLog(@"[DoorDashOrder] ➕ Inserting new DoorDash order ID at index 0");
        [orderIDs insertObject:orderEntry atIndex:0]; // Add to top
        
        // Keep only the last 50 entries
        if (orderIDs.count > 50) {
            NSLog(@"[DoorDashOrder] 🧹 Trimming DoorDash orders list from %lu to 50 entries", (unsigned long)orderIDs.count);
            [orderIDs removeObjectsInRange:NSMakeRange(50, orderIDs.count - 50)];
        }
        
        // Save back to NSUserDefaults
        [defaults setObject:orderIDs forKey:@"DoorDashCapturedOrderIDs"];
        NSLog(@"[DoorDashOrder] 💾 Saved DoorDash order data with %lu entries", (unsigned long)orderIDs.count);
        
        // Also notify the shared instance to reload if it exists
        DoorDashOrderViewController *sharedInstance = [DoorDashOrderViewController sharedInstance];
        if (sharedInstance) {
            NSLog(@"[DoorDashOrder] 🔄 Notifying shared instance to reload data");
            dispatch_async(dispatch_get_main_queue(), ^{
                [sharedInstance loadOrderData];
                NSLog(@"[DoorDashOrder] 📊 Shared instance reloaded data");
                [sharedInstance updateUI];
                NSLog(@"[DoorDashOrder] 🖥️ UI updated with new data");
            });
        } else {
            NSLog(@"[DoorDashOrder] ℹ️ No shared instance exists yet, skipping UI update");
        }
    } else {
        NSLog(@"[DoorDashOrder] ⏭️ DoorDash order ID already exists, skipping");
    }
}

+ (NSArray *)getRecentOrderIDs:(NSInteger)count {
    DoorDashOrderViewController *instance = [DoorDashOrderViewController sharedInstance];
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
    NSLog(@"[DoorDashOrder] 📂 Loading order data from NSUserDefaults");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *savedData = [defaults objectForKey:@"DoorDashCapturedOrderIDs"];
    
    if (savedData) {
        NSLog(@"[DoorDashOrder] ✅ Found %lu order entries in NSUserDefaults", (unsigned long)savedData.count);
        self.orderData = [savedData mutableCopy];
    } else {
        NSLog(@"[DoorDashOrder] ℹ️ No order data found in NSUserDefaults");
        self.orderData = [NSMutableArray array];
    }
}

- (void)saveOrderData {
    // Save to NSUserDefaults for cross-process communication
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.orderData forKey:@"DoorDashCapturedOrderIDs"];
    
    // Post notification that the data has changed
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)@"com.weaponx.doorDashOrderDataChanged",
                                         NULL, NULL, YES);
}

- (void)updateUI {
    self.noDataLabel.hidden = (self.orderData.count > 0);
    [self.tableView reloadData];
}

- (void)clearAllOrderIDs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear All Order IDs" 
                                                                  message:@"Are you sure you want to delete all captured DoorDash order IDs?" 
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
    return 1;
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
        NSString *timeAgoStr = [DoorDashOrderViewController getTimeElapsedString:timestamp];
        
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
        return @"CAPTURED DOORDASH ORDER IDS";
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
            // Use the same deletion method as the accessory button delete to avoid crashes
            // Remove the item
            [self.orderData removeObjectAtIndex:indexPath.row];
            [self saveOrderData];
            [self updateUI]; // Use updateUI instead of deleteRowsAtIndexPaths
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

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.orderData.count) {
        NSDictionary *order = self.orderData[indexPath.row];
        NSString *orderID = order[@"orderID"];
        NSDate *timestamp = order[@"timestamp"];
        
        // Format timestamp string
        NSString *timeStr = [self.dateFormatter stringFromDate:timestamp];
        NSString *timeAgoStr = [DoorDashOrderViewController getTimeElapsedString:timestamp];
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
                // Remove the item
                [self.orderData removeObjectAtIndex:indexPath.row];
                [self saveOrderData];
                [self updateUI];
            }]];
            
            [self presentViewController:confirmAlert animated:YES completion:nil];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        
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
}

- (void)userDefaultsChanged:(NSNotification *)notification {
    [self checkUserDefaults];
}

- (void)checkUserDefaults {
    static NSInteger lastCount = 0;
    
    // Get current count
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *orderData = [defaults objectForKey:@"DoorDashCapturedOrderIDs"];
    
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

// Helper method to generate the full DoorDash order URL
- (NSString *)getOrderURLForID:(NSString *)orderID {
    return [NSString stringWithFormat:@"https://track.doordash.com/share/%@/track", orderID];
}

// Share order URL
- (void)shareOrderURL:(NSString *)orderID {
    NSString *orderURL = [self getOrderURLForID:orderID];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] 
                                           initWithActivityItems:@[orderURL]
                                           applicationActivities:nil];
    
    // On iPad, we need to set the source view for the popover
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
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
                                                                              message:@"Unable to open the DoorDash order URL."
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

- (void)showInstructions {
    // Show alert with detailed instructions
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"How to Capture DoorDash Order IDs" 
                                                                  message:@"The network-based monitoring system automatically activates when your internet connection is down.\n\n"
                                                                         @"To capture DoorDash order IDs:\n\n"
                                                                         @"1. Open the DoorDash app and navigate to your Orders section\n\n"
                                                                         @"2. Put your device in Airplane Mode (or turn off both WiFi and cellular data)\n\n"
                                                                         @"3. Browse through your DoorDash orders - the IDs will be automatically captured\n\n"
                                                                         @"4. Return to WeaponX to see your captured order IDs\n\n"
                                                                         @"The monitoring automatically stays active for 3 minutes when offline, and extends as needed if you're still offline."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Got it!" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    // Remove Darwin notification observer
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                     (__bridge const void *)(self),
                                     CFSTR("com.weaponx.doorDashOrderCaptured"),
                                     NULL);
    
    // Remove NSNotificationCenter observer
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Add callback for monitoring state changes
static void monitoringStateChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        DoorDashOrderViewController *controller = (__bridge DoorDashOrderViewController *)observer;
        [controller checkMonitoringStatus];
    });
}

static void doorDashOrderCapturedNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"[DoorDashOrder] 📢 Received doorDashOrderCaptured notification");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[DoorDashOrder] 🧵 Processing notification on main thread");
        
        // Get the controller instance
        DoorDashOrderViewController *controller = (__bridge DoorDashOrderViewController *)observer;
        
        // Load the captured order IDs from NSUserDefaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSLog(@"[DoorDashOrder] 🔍 Checking NSUserDefaults for order data");
        NSArray *orderData = [defaults objectForKey:@"DoorDashCapturedOrderIDs"];
        
        if (orderData && orderData.count > 0) {
            NSLog(@"[DoorDashOrder] 📋 Found %lu order entries", (unsigned long)orderData.count);
            
            // Update the controller's order data
            controller.orderData = [orderData mutableCopy];
            
            // Force UI update on the main thread
            [controller updateUI];
            
            // Get the latest order for logging
            NSDictionary *latestOrder = orderData[0];
            NSString *orderID = latestOrder[@"orderID"];
            NSDate *timestamp = latestOrder[@"timestamp"];
            
            NSLog(@"[DoorDashOrder] 🔍 Found latest DoorDash order ID: %@", orderID);
            NSLog(@"[DoorDashOrder] ⏰ Timestamp: %@", timestamp);
        } else {
            NSLog(@"[DoorDashOrder] ⚠️ No DoorDash order data found in NSUserDefaults");
        }
    });
}

@end 