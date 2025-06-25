#import "VarCleanViewController.h"

@interface VarCleanViewController ()
@property (nonatomic, strong) NSMutableArray *tableData;

// Floating action buttons
@property (nonatomic, strong) UIButton *selectAllFloatingButton;
@property (nonatomic, strong) UIButton *cleanFloatingButton;
@end

@implementation VarCleanViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"RootHide VarClean";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Setup table view
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.clearsSelectionOnViewWillAppear = NO;
    
    // Setup refresh control
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    refreshControl.tintColor = [UIColor systemOrangeColor];
    [refreshControl addTarget:self action:@selector(manualRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refreshControl;
    
    // Initialize data
    self.tableData = [[NSMutableArray alloc] init];
    
    // Setup floating action buttons
    [self setupFloatingActionButtons];
    
    // Load data
    self.tableData = [self updateData:NO];
}

- (void)setupFloatingActionButtons {
    // Select All floating button
    self.selectAllFloatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        config.buttonSize = UIButtonConfigurationSizeLarge;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.background.backgroundColor = [UIColor systemBlueColor];
        config.baseForegroundColor = [UIColor whiteColor];
        [self.selectAllFloatingButton setConfiguration:config];
    } else {
        [self.selectAllFloatingButton setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateNormal];
        self.selectAllFloatingButton.backgroundColor = [UIColor systemBlueColor];
        self.selectAllFloatingButton.tintColor = [UIColor whiteColor];
        self.selectAllFloatingButton.layer.cornerRadius = 30;
        self.selectAllFloatingButton.layer.masksToBounds = YES;
    }
    
    self.selectAllFloatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.selectAllFloatingButton.layer.shadowOffset = CGSizeMake(0, 4);
    self.selectAllFloatingButton.layer.shadowOpacity = 0.3;
    self.selectAllFloatingButton.layer.shadowRadius = 8;
    self.selectAllFloatingButton.layer.masksToBounds = NO;
    
    self.selectAllFloatingButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.selectAllFloatingButton addTarget:self action:@selector(batchSelect) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.selectAllFloatingButton];
    
    // Clean floating button
    self.cleanFloatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.image = [UIImage systemImageNamed:@"trash.fill"];
        config.buttonSize = UIButtonConfigurationSizeLarge;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.background.backgroundColor = [UIColor systemOrangeColor];
        config.baseForegroundColor = [UIColor whiteColor];
        [self.cleanFloatingButton setConfiguration:config];
    } else {
        [self.cleanFloatingButton setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
        self.cleanFloatingButton.backgroundColor = [UIColor systemOrangeColor];
        self.cleanFloatingButton.tintColor = [UIColor whiteColor];
        self.cleanFloatingButton.layer.cornerRadius = 30;
        self.cleanFloatingButton.layer.masksToBounds = YES;
    }
    
    self.cleanFloatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cleanFloatingButton.layer.shadowOffset = CGSizeMake(0, 4);
    self.cleanFloatingButton.layer.shadowOpacity = 0.3;
    self.cleanFloatingButton.layer.shadowRadius = 8;
    self.cleanFloatingButton.layer.masksToBounds = NO;
    
    self.cleanFloatingButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cleanFloatingButton addTarget:self action:@selector(varClean) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cleanFloatingButton];
    
    // Position floating buttons
    [NSLayoutConstraint activateConstraints:@[
        [self.selectAllFloatingButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [self.selectAllFloatingButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [self.selectAllFloatingButton.widthAnchor constraintEqualToConstant:60],
        [self.selectAllFloatingButton.heightAnchor constraintEqualToConstant:60],
        
        [self.cleanFloatingButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [self.cleanFloatingButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:40],
        [self.cleanFloatingButton.widthAnchor constraintEqualToConstant:60],
        [self.cleanFloatingButton.heightAnchor constraintEqualToConstant:60]
    ]];
}

- (void)batchSelect {
    int selected = 0;
    for(NSDictionary* group in self.tableData) {
        for(NSMutableDictionary* item in group[@"items"]) {
            if(![item[@"checked"] boolValue]) {
                item[@"checked"] = @YES;
                selected++;
            }
        }
    }
    if(selected==0) for(NSDictionary* group in self.tableData) {
        for(NSMutableDictionary* item in group[@"items"]) {
            if([item[@"checked"] boolValue]) {
                item[@"checked"] = @NO;
            }
        }
    }
    [self.tableView reloadData];
}

- (void)startRefresh:(BOOL)keepState {
    [self.tableView.refreshControl beginRefreshing];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSMutableArray* newData = [self updateData:keepState];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.tableData = newData;
            [self.tableView reloadData];
            [self.tableView.refreshControl endRefreshing];
        });
    });
}

- (void)manualRefresh {
    [self startRefresh:NO];
}

- (void)updateForRules:(NSDictionary*)rules customed:(NSMutableDictionary*)customedRules newData:(NSMutableArray*)newData keepState:(BOOL)keepState {
    for (NSString* path in rules) {
        NSMutableArray *folders = [[NSMutableArray alloc] init];
        NSMutableArray *files = [[NSMutableArray alloc] init];
        
        NSDictionary* ruleItem = [rules objectForKey:path];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:path error:nil];
        
        NSArray *whiteList = ruleItem[@"whitelist"];
        NSArray *blackList = ruleItem[@"blacklist"];
        
        NSDictionary* customedRuleItem = customedRules[path];
        NSArray* customedWhiteList = customedRuleItem[@"whitelist"];
        NSArray* customedBlackList = customedRuleItem[@"blacklist"];
        [customedRules removeObjectForKey:path];
        
        NSMutableDictionary *tableGroup = @{
            @"group": path,
            @"items": @[]
        }.mutableCopy;
        
        for (NSString *file in contents) {
            
            BOOL checked = NO;
            
            // blacklist priority
            if([self checkFileInList:file List:blackList])
            {
                if([self checkFileInList:file List:customedWhiteList]) {
                    checked = NO;
                } else {
                    checked = YES;
                }
            }
            else if([self checkFileInList:file List:customedBlackList])
            {
                checked = YES;
            }
            else if([self checkFileInList:file List:whiteList])
            {
                continue;
            }
            else if([ruleItem[@"default"] isEqualToString:@"blacklist"])
            {
                if([self checkFileInList:file List:customedWhiteList] || [customedRuleItem[@"default"] isEqualToString:@"whitelist"]) {
                    checked = NO;
                }
                else {
                    checked = YES;
                }
            }
            else if([ruleItem[@"default"] isEqualToString:@"whitelist"])
            {
                if([customedRuleItem[@"default"] isEqualToString:@"blacklist"]) {
                    checked = YES;
                } else {
                    continue;
                }
            }
            else
            {
                if([self checkFileInList:file List:customedWhiteList] || [customedRuleItem[@"default"] isEqualToString:@"whitelist"]) {
                    checked = NO;
                }
                else if([customedRuleItem[@"default"] isEqualToString:@"blacklist"]) {
                    checked = YES;
                }
                else {
                    checked = NO;
                }
            }
            
            if(keepState)
            {
                for(NSDictionary* group in self.tableData)
                {
                    if([group[@"group"] isEqualToString:path])
                    {
                        for(NSDictionary* item in group[@"items"])
                        {
                            if([item[@"name"] isEqualToString:file])
                            {
                                checked = [item[@"checked"] boolValue];
                                break;
                            }
                        }
                        break;
                    }
                }
            }
            
            NSString *filePath = [path stringByAppendingPathComponent:file];
            
            BOOL isDirectory = NO;
            BOOL exists = [fileManager fileExistsAtPath:filePath isDirectory:&isDirectory];
            BOOL isFolder = exists && isDirectory;
            
            NSMutableDictionary *tableItem = @{
                @"name": file,
                @"path": filePath,
                @"isFolder": @(isFolder),
                @"checked": @(checked),
            }.mutableCopy;
            
            if(isFolder) {
                [folders addObject:tableItem];
            } else {
                [files addObject:tableItem];
            }
        }
        
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        NSArray *sortedFolders = [folders sortedArrayUsingDescriptors:@[sortDescriptor]];
        NSArray *sortedFiles = [files sortedArrayUsingDescriptors:@[sortDescriptor]];
        
        tableGroup[@"items"] = [[sortedFolders arrayByAddingObjectsFromArray:sortedFiles] mutableCopy];
        [newData addObject:tableGroup];
    }
}

- (NSMutableArray*)updateData:(BOOL)keepState {
    NSLog(@"updateData...");
    NSMutableArray* newData = [[NSMutableArray alloc] init];
    
    // Load JSON once - use standard JSON parsing since we removed comments
    NSString *jsonPath = [NSBundle.mainBundle pathForResource:@"VarCleanRules" ofType:@"json"];
    NSLog(@"JSON path: %@", jsonPath);
    
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    if (!jsonData) {
        NSLog(@"Failed to load VarCleanRules.json from path: %@", jsonPath);
        return newData;
    }
    
    NSLog(@"JSON data loaded, size: %lu bytes", (unsigned long)jsonData.length);

    NSError *err = nil;
    // Use standard JSON parsing instead of commented parsing
    NSDictionary *rules = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&err];
    if (err || !rules) {
        NSLog(@"JSON parsing error: %@", err);
        return newData;
    }
    
    NSLog(@"JSON parsed successfully, rules count: %lu", (unsigned long)rules.count);
    NSLog(@"Rules keys: %@", [rules allKeys]);

    // Use same rules as both default and "customed"
    NSMutableDictionary *customedRules = [rules mutableCopy];

    [self updateForRules:rules customed:customedRules newData:newData keepState:keepState];
    [self updateForRules:customedRules customed:nil newData:newData keepState:keepState];

    NSComparator sorter = ^NSComparisonResult(NSDictionary* a, NSDictionary* b)
    {
        if([a[@"items"] count]!=0 && [b[@"items"] count]==0) return NSOrderedAscending;
        if([a[@"items"] count]==0 && [b[@"items"] count]!=0) return NSOrderedDescending;
        
        return [a[@"group"] compare:b[@"group"]];
    };
    [newData sortUsingComparator:sorter];
    
    return newData;
}

- (BOOL)checkFileInList:(NSString *)fileName List:(NSArray*)list {
    for (NSObject* item in list) {
        if([item isKindOfClass:NSString.class]) {
            if ([fileName isEqualToString:(NSString*)item]) {
                return YES;
            }
        } else if([item isKindOfClass:NSDictionary.class]) {
            NSDictionary* condition = (NSDictionary*)item;
            NSString *name = condition[@"name"];
            NSString *match = condition[@"match"];
            
            if ([match isEqualToString:@"include"]) {
                if ([fileName rangeOfString:name].location != NSNotFound) {
                    return YES;
                }
            } else if ([match isEqualToString:@"regexp"]) {
                NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:name options:0 error:nil];
                NSUInteger result = [regex numberOfMatchesInString:fileName options:0 range:NSMakeRange(0, fileName.length)];
                if(result != 0) return YES;
            }
        }
    }
    return NO;
}

- (void)varClean {
    // Collect all the files marked for deletion
    NSMutableArray *filesToDelete = [NSMutableArray array];
    for (NSDictionary* group in self.tableData) {
        for (NSDictionary* item in group[@"items"]) {
            if ([item[@"checked"] boolValue]) {
                [filesToDelete addObject:item[@"path"]];
            }
        }
    }
    
    // If no files are selected, show an alert and return
    if (filesToDelete.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Files Selected"
                                                                       message:@"Please select files to clean."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Create a string listing all the files to delete
    NSMutableString *fileList = [NSMutableString string];
    for (NSString *filePath in filesToDelete) {
        [fileList appendFormat:@"%@\n", filePath];
    }
    
    // Show a confirmation popup with the list of files
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Confirm Deletion"
                                                                             message:[NSString stringWithFormat:@"You are about to delete the following files:\n\n%@", fileList]
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    // Add a "Confirm" button
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Confirm"
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction * _Nonnull action) {
        [self performDeletion];
    }];
    
    // Add a "Cancel" button
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    
    [alertController addAction:confirmAction];
    [alertController addAction:cancelAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)performDeletion {
    [self.tableView.refreshControl beginRefreshing];
    
    for (NSDictionary* group in [self.tableData copy]) {
        for (NSDictionary* item in [group[@"items"] copy]) {
            if (![item[@"checked"] boolValue]) continue;
            
            NSLog(@"Deleting: %@", item[@"path"]);
            
            NSError *err;
            if (![NSFileManager.defaultManager removeItemAtPath:item[@"path"] error:&err]) {
                NSLog(@"Deletion failed: %@", err);
                continue;
            }
            
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[group[@"items"] indexOfObject:item]
                                                        inSection:[self.tableData indexOfObject:group]];
            [group[@"items"] removeObject:item];
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationLeft];
        }
    }
    
    [self.tableView.refreshControl endRefreshing];
    
    self.tableData = [self updateData:NO];
    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.tableData.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSDictionary *groupData = self.tableData[section];
    NSArray *items = groupData[@"items"];
    return items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSDictionary *groupData = self.tableData[section];
    return groupData[@"group"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    
    NSDictionary *groupData = self.tableData[indexPath.section];
    NSArray *items = groupData[@"items"];
    
    NSDictionary *item = items[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@",[item[@"isFolder"] boolValue] ? @"🗂️" : @"📄", item[@"name"]];
    
    BOOL selected = [item[@"checked"] boolValue];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *groupData = self.tableData[indexPath.section];
    NSArray *items = groupData[@"items"];
    NSMutableDictionary *item = items[indexPath.row];
    
    BOOL newstate = ![item[@"checked"] boolValue];
    item[@"checked"] = @(newstate);
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = newstate ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
}

@end