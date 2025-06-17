#import "VersionManagementViewController.h"
#import "ProjectXLogging.h"

@interface VersionManagementViewController ()
@property (nonatomic, strong) UIBarButtonItem *addButton;
@property (nonatomic, strong) UIBarButtonItem *doneButton;
@property (nonatomic, strong) UIBarButtonItem *fetchButton;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) NSURLSessionDataTask *currentVersionTask;
@property (nonatomic, strong) NSArray *appVersions;
@property (nonatomic, strong) NSArray *filteredVersions;
@end

@implementation VersionManagementViewController

#pragma mark - Initialization

- (instancetype)initWithBundleID:(NSString *)bundleID appInfo:(NSDictionary *)appInfo {
    self = [super init];
    if (self) {
        _bundleID = bundleID;
        _appInfo = appInfo;
        _maxVersionsPerApp = 10; // Maximum number of versions to manage
        
        // Get active version index if available
        NSNumber *activeIndexObj = appInfo[@"activeVersionIndex"];
        _activeVersionIndex = activeIndexObj ? [activeIndexObj integerValue] : -1;
        
        // Initialize versions array
        _versions = [NSMutableArray array];
        
        // Load saved versions for this bundle ID
        [self loadVersionsForBundleID:bundleID];
    }
    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Set up the view
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Set up navigation bar
    self.doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                    target:self 
                                                                    action:@selector(doneButtonTapped)];
    self.navigationItem.rightBarButtonItem = self.doneButton;
    
    self.addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
                                                                   target:self 
                                                                   action:@selector(addButtonTapped)];
    
    // Add fetch button
    self.fetchButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"]
                                                      style:UIBarButtonItemStylePlain
                                                     target:self
                                                     action:@selector(fetchVersionsButtonTapped)];
    self.fetchButton.tintColor = [UIColor systemGreenColor];
    
    self.navigationItem.leftBarButtonItems = @[self.addButton, self.fetchButton];
    
    // Setup loading indicator
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.center = self.view.center;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];
    
    // Add explanation text at the top
    UILabel *explanationLabel = [[UILabel alloc] init];
    explanationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    explanationLabel.text = @"You can add multiple versions for this app. Use the + button to add manually or the download button to fetch from App Store.";
    explanationLabel.textAlignment = NSTextAlignmentCenter;
    explanationLabel.textColor = [UIColor secondaryLabelColor];
    explanationLabel.numberOfLines = 0;
    explanationLabel.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:explanationLabel];
    
    // Set up table view with improved style
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 110;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"VersionCell"];
    [self.view addSubview:self.tableView];
    
    // Set up empty state view
    self.emptyStateView = [[UIView alloc] init];
    self.emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyStateView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.emptyStateView];
    
    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    emptyLabel.text = @"No versions added yet\nTap the + button to add a version";
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.textColor = [UIColor secondaryLabelColor];
    emptyLabel.numberOfLines = 0;
    [self.emptyStateView addSubview:emptyLabel];
    
    UIButton *addVersionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    addVersionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [addVersionButton setTitle:@"Add Version" forState:UIControlStateNormal];
    [addVersionButton addTarget:self action:@selector(addButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    addVersionButton.backgroundColor = [UIColor systemBlueColor];
    addVersionButton.layer.cornerRadius = 12;
    addVersionButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [addVersionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.emptyStateView addSubview:addVersionButton];
    
    // Set up layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Explanation label constraints
        [explanationLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [explanationLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [explanationLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        
        // Table view constraints
        [self.tableView.topAnchor constraintEqualToAnchor:explanationLabel.bottomAnchor constant:16],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        // Empty state view constraints
        [self.emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyStateView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.emptyStateView.heightAnchor constraintEqualToConstant:200],
        
        // Empty label constraints
        [emptyLabel.topAnchor constraintEqualToAnchor:self.emptyStateView.topAnchor],
        [emptyLabel.leadingAnchor constraintEqualToAnchor:self.emptyStateView.leadingAnchor constant:16],
        [emptyLabel.trailingAnchor constraintEqualToAnchor:self.emptyStateView.trailingAnchor constant:-16],
        
        // Add version button constraints
        [addVersionButton.topAnchor constraintEqualToAnchor:emptyLabel.bottomAnchor constant:20],
        [addVersionButton.centerXAnchor constraintEqualToAnchor:self.emptyStateView.centerXAnchor],
        [addVersionButton.widthAnchor constraintEqualToConstant:150],
        [addVersionButton.heightAnchor constraintEqualToConstant:44]
    ]];
    
    // Update empty state visibility
    [self updateEmptyStateVisibility];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [self updateEmptyStateVisibility];
}

#pragma mark - UI Updates

- (void)updateEmptyStateVisibility {
    self.emptyStateView.hidden = (self.versions.count > 0);
    self.tableView.hidden = !self.emptyStateView.hidden;
    
    // Only allow adding more versions if we're under the limit
    self.addButton.enabled = (self.versions.count < self.maxVersionsPerApp);
}

#pragma mark - Action Handlers

- (void)doneButtonTapped {
    // Notify delegate that versions were updated (if delegate is set)
    if ([self.delegate respondsToSelector:@selector(versionManagementDidUpdateVersions)]) {
        [self.delegate versionManagementDidUpdateVersions];
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)addButtonTapped {
    if (self.versions.count >= self.maxVersionsPerApp) {
        [self showAlertWithTitle:@"Maximum Reached" 
                         message:[NSString stringWithFormat:@"You can only add up to %ld versions per app.", (long)self.maxVersionsPerApp]];
        return;
    }
    
    [self showAddVersionDialog];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2; // Section 0: Current active version info, Section 1: Saved versions
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 1; // Real version info
    } else {
        return self.versions.count;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil; // We'll use custom view for header instead of title
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 40)];
    headerView.backgroundColor = [UIColor clearColor];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, tableView.bounds.size.width - 32, 24)];
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor labelColor];
    
    if (section == 0) {
        titleLabel.text = @"Current App Information";
    } else {
        if (self.versions.count > 0) {
            titleLabel.text = [NSString stringWithFormat:@"Saved Versions (%lu)", (unsigned long)self.versions.count];
        } else {
            titleLabel.text = @"Saved Versions";
        }
    }
    
    [headerView addSubview:titleLabel];
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 40.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"VersionCell" forIndexPath:indexPath];
    
    // Remove any existing subviews (for reused cells)
    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }
    
    // Configure the cell
    cell.textLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.backgroundColor = [UIColor clearColor];
    
    if (indexPath.section == 0) {
        // Current app info section with improved layout
        NSString *realVersion = self.appInfo[@"version"] ?: @"Unknown";
        NSString *realBuild = self.appInfo[@"build"] ?: @"Unknown";
        
        // Create container with shadows and rounded corners
        UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(12, 5, cell.contentView.bounds.size.width - 24, 70)];
        cardView.backgroundColor = [UIColor systemBackgroundColor];
        cardView.layer.cornerRadius = 12;
        cardView.layer.shadowColor = [UIColor blackColor].CGColor;
        cardView.layer.shadowOffset = CGSizeMake(0, 2);
        cardView.layer.shadowRadius = 4;
        cardView.layer.shadowOpacity = 0.1;
        cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:cardView];
        
        // Card title
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, cardView.bounds.size.width - 32, 20)];
        titleLabel.text = @"Actual App Info";
        titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor secondaryLabelColor];
        titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cardView addSubview:titleLabel];
        
        // Version and Build with a table-like layout
        UIView *infoContainer = [[UIView alloc] initWithFrame:CGRectMake(16, 32, cardView.bounds.size.width - 32, 30)];
        infoContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cardView addSubview:infoContainer];
        
        // Version label
        UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 60, 30)];
        versionLabel.text = @"Version:";
        versionLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        versionLabel.textColor = [UIColor labelColor];
        [infoContainer addSubview:versionLabel];
        
        UILabel *versionValue = [[UILabel alloc] initWithFrame:CGRectMake(70, 0, infoContainer.bounds.size.width - 80, 30)];
        versionValue.text = realVersion;
        versionValue.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        versionValue.textColor = [UIColor systemBlueColor];
        versionValue.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [infoContainer addSubview:versionValue];
        
        // Build label
        UILabel *buildLabel = [[UILabel alloc] initWithFrame:CGRectMake(infoContainer.bounds.size.width - 120, 0, 50, 30)];
        buildLabel.text = @"Build:";
        buildLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        buildLabel.textColor = [UIColor labelColor];
        buildLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [infoContainer addSubview:buildLabel];
        
        UILabel *buildValue = [[UILabel alloc] initWithFrame:CGRectMake(infoContainer.bounds.size.width - 65, 0, 65, 30)];
        buildValue.text = realBuild;
        buildValue.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
        buildValue.textColor = [UIColor systemGreenColor];
        buildValue.textAlignment = NSTextAlignmentRight;
        buildValue.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [infoContainer addSubview:buildValue];
        
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
    } else {
        // Saved versions section
        if (indexPath.row < self.versions.count) {
            NSDictionary *versionEntry = self.versions[indexPath.row];
            NSString *displayName = versionEntry[@"displayName"];
            NSString *version = versionEntry[@"version"];
            NSString *build = versionEntry[@"build"];
            
            // Card style container
            UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(12, 5, cell.contentView.bounds.size.width - 24, 100)];
            cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            cardView.layer.cornerRadius = 12;
            cardView.layer.shadowColor = [UIColor blackColor].CGColor;
            cardView.layer.shadowOffset = CGSizeMake(0, 2);
            cardView.layer.shadowRadius = 4;
            cardView.layer.shadowOpacity = 0.1;
            
            // Set card background color based on active status
            if (indexPath.row == self.activeVersionIndex) {
                // Use dynamic color that works in both light and dark mode
                if (@available(iOS 13.0, *)) {
                    cardView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
                        if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                            return [UIColor colorWithRed:0.2 green:0.3 blue:0.5 alpha:1.0]; // Darker blue for dark mode
                        } else {
                            return [UIColor colorWithRed:0.9 green:0.95 blue:1.0 alpha:1.0]; // Light blue for light mode
                        }
                    }];
                } else {
                    cardView.backgroundColor = [UIColor colorWithRed:0.9 green:0.95 blue:1.0 alpha:1.0]; // Light blue for iOS < 13
                }
                
                UIView *activeIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4, cardView.bounds.size.height)];
                activeIndicator.backgroundColor = [UIColor systemBlueColor];
                activeIndicator.layer.cornerRadius = 2;
                [cardView addSubview:activeIndicator];
            } else {
                cardView.backgroundColor = [UIColor systemBackgroundColor];
            }
            
            [cell.contentView addSubview:cardView];
            
            // Version name with badge if active
            UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, cardView.bounds.size.width - 32, 24)];
            nameLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
            nameLabel.text = displayName;
            nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            
            if (indexPath.row == self.activeVersionIndex) {
                nameLabel.textColor = [UIColor systemBlueColor];
                
                // Active badge
                UIView *activeBadge = [[UIView alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 65, 12, 56, 22)];
                activeBadge.backgroundColor = [UIColor systemBlueColor];
                activeBadge.layer.cornerRadius = 11;
                activeBadge.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                [cardView addSubview:activeBadge];
                
                UILabel *activeText = [[UILabel alloc] initWithFrame:activeBadge.bounds];
                activeText.text = @"ACTIVE";
                activeText.textColor = [UIColor whiteColor];
                activeText.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
                activeText.textAlignment = NSTextAlignmentCenter;
                [activeBadge addSubview:activeText];
            } else {
                nameLabel.textColor = [UIColor labelColor];
            }
            
            [cardView addSubview:nameLabel];
            
            // Divider line
            UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(16, 44, cardView.bounds.size.width - 32, 1)];
            divider.backgroundColor = [UIColor separatorColor];
            divider.alpha = 0.5;
            divider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cardView addSubview:divider];
            
            // Version and build info
            UIView *infoContainer = [[UIView alloc] initWithFrame:CGRectMake(16, 52, cardView.bounds.size.width - 32, 24)];
            infoContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cardView addSubview:infoContainer];
            
            // Version info
            UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 55, 24)];
            versionLabel.text = @"Version:";
            versionLabel.font = [UIFont systemFontOfSize:14];
            versionLabel.textColor = [UIColor secondaryLabelColor];
            [infoContainer addSubview:versionLabel];
            
            UILabel *versionValue = [[UILabel alloc] initWithFrame:CGRectMake(60, 0, infoContainer.bounds.size.width / 2 - 60, 24)];
            versionValue.text = version;
            versionValue.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            // Make sure version value is visible in dark mode for active cells
            if (indexPath.row == self.activeVersionIndex) {
                if (@available(iOS 13.0, *)) {
                    versionValue.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
                        if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                            return [UIColor colorWithWhite:0.9 alpha:1.0]; // Light color for dark mode active cells
                        } else {
                            return [UIColor labelColor]; // Default for light mode
                        }
                    }];
                } else {
                    versionValue.textColor = [UIColor labelColor];
                }
            } else {
                versionValue.textColor = [UIColor labelColor];
            }
            [infoContainer addSubview:versionValue];
            
            // Build info (if available)
            if (build.length > 0) {
                UILabel *buildLabel = [[UILabel alloc] initWithFrame:CGRectMake(infoContainer.bounds.size.width / 2, 0, 40, 24)];
                buildLabel.text = @"Build:";
                buildLabel.font = [UIFont systemFontOfSize:14];
                buildLabel.textColor = [UIColor secondaryLabelColor];
                buildLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                [infoContainer addSubview:buildLabel];
                
                UILabel *buildValue = [[UILabel alloc] initWithFrame:CGRectMake(infoContainer.bounds.size.width / 2 + 45, 0, infoContainer.bounds.size.width / 2 - 45, 24)];
                buildValue.text = build;
                buildValue.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
                // Make sure build value is visible in dark mode for active cells
                if (indexPath.row == self.activeVersionIndex) {
                    if (@available(iOS 13.0, *)) {
                        buildValue.textColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
                            if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                                return [UIColor colorWithWhite:0.9 alpha:1.0]; // Light color for dark mode active cells
                            } else {
                                return [UIColor labelColor]; // Default for light mode
                            }
                        }];
                    } else {
                        buildValue.textColor = [UIColor labelColor];
                    }
                } else {
                    buildValue.textColor = [UIColor labelColor];
                }
                buildValue.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
                [infoContainer addSubview:buildValue];
            }
            
            // Action buttons container
            UIView *buttonContainer = [[UIView alloc] initWithFrame:CGRectMake(16, 76, cardView.bounds.size.width - 32, 30)];
            buttonContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cardView addSubview:buttonContainer];
            
            // Create a horizontal stack of buttons
            CGFloat buttonWidth = 70;
            CGFloat spacing = 8;
            
            // Edit button
            UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
            editButton.frame = CGRectMake(0, 0, buttonWidth, 30);
            [editButton setTitle:@"Edit" forState:UIControlStateNormal];
            editButton.backgroundColor = [UIColor systemBackgroundColor];
            editButton.layer.cornerRadius = 8;
            editButton.layer.borderWidth = 1;
            editButton.layer.borderColor = [UIColor systemBlueColor].CGColor;
            [editButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
            editButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            editButton.tag = indexPath.row;
            [editButton addTarget:self action:@selector(editButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [buttonContainer addSubview:editButton];
            
            // Delete button
            UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
            deleteButton.frame = CGRectMake(buttonWidth + spacing, 0, buttonWidth, 30);
            [deleteButton setTitle:@"Delete" forState:UIControlStateNormal];
            deleteButton.backgroundColor = [UIColor systemBackgroundColor];
            deleteButton.layer.cornerRadius = 8;
            deleteButton.layer.borderWidth = 1;
            deleteButton.layer.borderColor = [UIColor systemRedColor].CGColor;
            [deleteButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
            deleteButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            deleteButton.tag = indexPath.row;
            [deleteButton addTarget:self action:@selector(deleteButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [buttonContainer addSubview:deleteButton];
            
            // Use button (only for non-active versions)
            if (indexPath.row != self.activeVersionIndex) {
                UIButton *useButton = [UIButton buttonWithType:UIButtonTypeSystem];
                useButton.frame = CGRectMake(buttonContainer.bounds.size.width - buttonWidth, 0, buttonWidth, 30);
                [useButton setTitle:@"Use" forState:UIControlStateNormal];
                useButton.backgroundColor = [UIColor systemGreenColor];
                useButton.layer.cornerRadius = 8;
                [useButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                useButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
                useButton.tag = indexPath.row;
                useButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                [useButton addTarget:self action:@selector(useButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
                [buttonContainer addSubview:useButton];
            }
            
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    
    return cell;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only add swipe actions to the versions section
    if (indexPath.section == 0) {
        return nil;
    }
    
    __weak typeof(self) weakSelf = self;
    
    // Edit action
    UIContextualAction *editAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                             title:@"Edit"
                                                                           handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf editVersionAtIndex:indexPath.row];
        completionHandler(YES);
    }];
    editAction.backgroundColor = [UIColor systemBlueColor];
    
    // Delete action
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf showDeleteConfirmationForVersionAtIndex:indexPath.row completion:completionHandler];
    }];
    
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, editAction]];
    config.performsFirstActionWithFullSwipe = NO;
    
    return config;
}

#pragma mark - Version Management

- (void)loadVersionsForBundleID:(NSString *)bundleID {
    // Try rootless path first
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        
        // Fallback to standard path if needed
        if (![fileManager fileExistsAtPath:prefsPath]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        }
    }
    
    // Load multi-version spoofing data
    NSDictionary *multiVersionDict = [NSDictionary dictionaryWithContentsOfFile:multiVersionFile];
    NSDictionary *multiVersions = multiVersionDict[@"MultiVersions"];
    
    if (multiVersions) {
        NSArray *savedVersions = multiVersions[bundleID];
        if (savedVersions && [savedVersions isKindOfClass:[NSArray class]]) {
            [self.versions addObjectsFromArray:savedVersions];
            PXLog(@"[VersionManagement] Loaded %lu versions for %@", (unsigned long)self.versions.count, bundleID);
        }
    }
    
    [self updateEmptyStateVisibility];
}

- (void)saveVersions {
    // Try rootless path first
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        
        // Fallback to standard path if needed
        if (![fileManager fileExistsAtPath:prefsPath]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        }
    }
    
    // Create directory if it doesn't exist
    if (![fileManager fileExistsAtPath:prefsPath]) {
        NSError *error = nil;
        [fileManager createDirectoryAtPath:prefsPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            PXLog(@"[VersionManagement] Failed to create preferences directory: %@", error.localizedDescription);
            return;
        }
    }
    
    // Load existing multi-version data
    NSMutableDictionary *multiVersionDict = [[NSDictionary dictionaryWithContentsOfFile:multiVersionFile] mutableCopy];
    if (!multiVersionDict) {
        multiVersionDict = [NSMutableDictionary dictionary];
    }
    
    NSMutableDictionary *multiVersions = [multiVersionDict[@"MultiVersions"] mutableCopy];
    if (!multiVersions) {
        multiVersions = [NSMutableDictionary dictionary];
    }
    
    // Update with new versions
    multiVersions[self.bundleID] = self.versions;
    multiVersionDict[@"MultiVersions"] = multiVersions;
    multiVersionDict[@"LastUpdated"] = [NSDate date];
    
    // Save to file
    BOOL success = [multiVersionDict writeToFile:multiVersionFile atomically:YES];
    if (success) {
        PXLog(@"[VersionManagement] Successfully saved %lu versions for %@", (unsigned long)self.versions.count, self.bundleID);
    } else {
        PXLog(@"[VersionManagement] Failed to save versions data");
    }
    
    // Also update the active version in the version_spoof.plist
    [self updateActiveVersionInSpoofPlist];
}

- (NSString *)getAppVersionFilePath {
    // Get the active profile ID
    NSString *profileId = nil;
    
    // Try to get from IdentifierManager if available
    Class idManagerClass = NSClassFromString(@"IdentifierManager");
    if (idManagerClass && [idManagerClass respondsToSelector:@selector(sharedManager)]) {
        id idManager = [idManagerClass performSelector:@selector(sharedManager)];
        if ([idManager respondsToSelector:@selector(getActiveProfileId)]) {
            profileId = [idManager performSelector:@selector(getActiveProfileId)];
        }
    }
    
    // Fallback if no profile ID found
    if (!profileId) {
        // First check the primary profile info file
        NSString *centralInfoPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
        NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
        
        profileId = centralInfo[@"ProfileId"];
        if (!profileId) {
            // If not found, check the legacy active_profile_info.plist
            NSString *activeInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
            NSDictionary *activeInfo = [NSDictionary dictionaryWithContentsOfFile:activeInfoPath];
            profileId = activeInfo[@"ProfileId"];
        }
        
        if (!profileId) {
            PXLog(@"[VersionManagement] No profile ID found, using default shared storage");
            return nil;
        }
    }
    
    // Build the path to this profile's app versions directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *appVersionsDir = [profileDir stringByAppendingPathComponent:@"app_versions"];
    
    // Create the directory if it doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:appVersionsDir]) {
        NSDictionary *attributes = @{NSFilePosixPermissions: @0755,
                                    NSFileOwnerAccountName: @"mobile"};
        
        NSError *dirError = nil;
        if (![fileManager createDirectoryAtPath:appVersionsDir 
                    withIntermediateDirectories:YES 
                                     attributes:attributes
                                          error:&dirError]) {
            PXLog(@"[VersionManagement] Error creating app versions directory: %@", dirError);
            return nil;
        }
    }
    
    // Create a safe filename from the bundle ID
    NSString *safeFilename = [self.bundleID stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    safeFilename = [safeFilename stringByAppendingString:@"_version.plist"];
    
    return [appVersionsDir stringByAppendingPathComponent:safeFilename];
}

- (void)updateActiveVersionInSpoofPlist {
    // Try profile-specific storage first
    NSString *appVersionFile = [self getAppVersionFilePath];
    BOOL usingProfileStorage = (appVersionFile != nil);
    
    // Get the shared storage paths as fallback
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (!usingProfileStorage && ![fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
        
        // Fallback to standard path if needed
        if (![fileManager fileExistsAtPath:prefsPath]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
        }
    }
    
    if (usingProfileStorage) {
        // Using profile-specific storage - directly save app data to its own file
        NSMutableDictionary *appVersionData = [NSMutableDictionary dictionary];
        
        // Set active version index and info
        if (self.activeVersionIndex >= 0 && self.activeVersionIndex < self.versions.count) {
            NSDictionary *activeVersion = self.versions[self.activeVersionIndex];
            appVersionData[@"activeVersionIndex"] = @(self.activeVersionIndex);
            appVersionData[@"spoofedVersion"] = activeVersion[@"version"];
            appVersionData[@"spoofedBuild"] = activeVersion[@"build"];
        } else {
            // No active version
            appVersionData[@"activeVersionIndex"] = @(-1);
            [appVersionData removeObjectForKey:@"spoofedVersion"];
            [appVersionData removeObjectForKey:@"spoofedBuild"];
        }
        
        // Get app name from existing data
        NSString *appName = self.appInfo[@"name"];
        if (appName) {
            appVersionData[@"name"] = appName;
        }
        appVersionData[@"bundleID"] = self.bundleID;
        appVersionData[@"lastUpdated"] = [NSDate date];
        
        // Save to profile-specific file
        BOOL success = [appVersionData writeToFile:appVersionFile atomically:YES];
        if (success) {
            PXLog(@"[VersionManagement] Successfully saved version data to profile-specific file for %@", self.bundleID);
        } else {
            PXLog(@"[VersionManagement] Failed to save to profile-specific file, will try shared storage");
            usingProfileStorage = NO; // Fall back to shared storage
        }
    }
    
    // If profile-specific storage failed or wasn't available, use shared storage
    if (!usingProfileStorage) {
        // Load existing version spoof data
        NSMutableDictionary *versionSpoofDict = [[NSDictionary dictionaryWithContentsOfFile:versionSpoofFile] mutableCopy];
        if (!versionSpoofDict) {
            versionSpoofDict = [NSMutableDictionary dictionary];
        }
        
        NSMutableDictionary *spoofedVersions = [versionSpoofDict[@"SpoofedVersions"] mutableCopy];
        if (!spoofedVersions) {
            spoofedVersions = [NSMutableDictionary dictionary];
        }
        
        // Update or create app entry
        NSMutableDictionary *appEntry = [spoofedVersions[self.bundleID] mutableCopy];
        if (!appEntry) {
            appEntry = [NSMutableDictionary dictionary];
        }
        
        // Set active version index and info
        if (self.activeVersionIndex >= 0 && self.activeVersionIndex < self.versions.count) {
            NSDictionary *activeVersion = self.versions[self.activeVersionIndex];
            appEntry[@"activeVersionIndex"] = @(self.activeVersionIndex);
            appEntry[@"spoofedVersion"] = activeVersion[@"version"];
            appEntry[@"spoofedBuild"] = activeVersion[@"build"];
        } else {
            // No active version
            appEntry[@"activeVersionIndex"] = @(-1);
            [appEntry removeObjectForKey:@"spoofedVersion"];
            [appEntry removeObjectForKey:@"spoofedBuild"];
        }
        
        // Get app name from existing data
        NSString *appName = self.appInfo[@"name"];
        if (appName) {
            appEntry[@"name"] = appName;
        }
        
        // Update dictionaries
        spoofedVersions[self.bundleID] = appEntry;
        versionSpoofDict[@"SpoofedVersions"] = spoofedVersions;
        versionSpoofDict[@"LastUpdated"] = [NSDate date];
        
        // Save to file
        BOOL success = [versionSpoofDict writeToFile:versionSpoofFile atomically:YES];
        if (success) {
            PXLog(@"[VersionManagement] Successfully updated version spoof data for %@", self.bundleID);
        } else {
            PXLog(@"[VersionManagement] Failed to update version spoof data");
        }
    }
    
    // Post notification to refresh UI
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.appVersionDataChanged" object:nil];
}

- (void)activateVersionAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.versions.count) {
        return;
    }
    
    // Set the active version index
    self.activeVersionIndex = index;
    
    // Save the changes
    [self saveVersions];
    
    // Refresh the table view
    [self.tableView reloadData];
    
    // Show confirmation toast
    NSDictionary *versionEntry = self.versions[index];
    NSString *displayName = versionEntry[@"displayName"];
    
    // Show alert with success message
    [self showAlertWithTitle:@"Version Activated" 
                     message:[NSString stringWithFormat:@"Now using '%@'", displayName]];
}

- (void)showAddVersionDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add New Version"
                                                                   message:@"Enter version and build information"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Version Name (e.g. v1.2.3)";
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Version Number (e.g. 1.2.3)";
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Build Number (e.g. 1234)";
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *displayName = alert.textFields[0].text;
        NSString *versionNumber = alert.textFields[1].text;
        NSString *buildNumber = alert.textFields[2].text;
        
        if (displayName.length == 0 || versionNumber.length == 0) {
            // Show error - name and version are required
            [self showAlertWithTitle:@"Error" message:@"Version name and number are required"];
            return;
        }
        
        // Create version entry
        NSDictionary *versionEntry = @{
            @"displayName": displayName,
            @"version": versionNumber,
            @"build": buildNumber.length > 0 ? buildNumber : @"",
            @"dateAdded": [NSDate date]
        };
        
        // Add to versions array
        [self.versions addObject:versionEntry];
        
        // If this is the first version added, make it active
        if (self.versions.count == 1) {
            self.activeVersionIndex = 0;
        }
        
        // Save the changes
        [self saveVersions];
        
        // Refresh the UI
        [self.tableView reloadData];
        [self updateEmptyStateVisibility];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editVersionAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.versions.count) {
        return;
    }
    
    NSDictionary *versionEntry = self.versions[index];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Version"
                                                                   message:@"Update version information"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Version Name (e.g. v1.2.3)";
        textField.text = versionEntry[@"displayName"];
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Version Number (e.g. 1.2.3)";
        textField.text = versionEntry[@"version"];
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Build Number (e.g. 1234)";
        textField.text = versionEntry[@"build"];
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *displayName = alert.textFields[0].text;
        NSString *versionNumber = alert.textFields[1].text;
        NSString *buildNumber = alert.textFields[2].text;
        
        if (displayName.length == 0 || versionNumber.length == 0) {
            // Show error - name and version are required
            [self showAlertWithTitle:@"Error" message:@"Version name and number are required"];
            return;
        }
        
        // Create updated version entry
        NSMutableDictionary *updatedEntry = [versionEntry mutableCopy];
        updatedEntry[@"displayName"] = displayName;
        updatedEntry[@"version"] = versionNumber;
        updatedEntry[@"build"] = buildNumber.length > 0 ? buildNumber : @"";
        
        // Update versions array
        self.versions[index] = updatedEntry;
        
        // Save the changes
        [self saveVersions];
        
        // Refresh the UI
        [self.tableView reloadData];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDeleteConfirmationForVersionAtIndex:(NSInteger)index completion:(void (^)(BOOL))completionHandler {
    if (index < 0 || index >= self.versions.count) {
        if (completionHandler) completionHandler(NO);
        return;
    }
    
    NSDictionary *versionEntry = self.versions[index];
    NSString *displayName = versionEntry[@"displayName"];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Version"
                                                                   message:[NSString stringWithFormat:@"Are you sure you want to delete '%@'?", displayName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (completionHandler) completionHandler(NO);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteVersionAtIndex:index];
        if (completionHandler) completionHandler(YES);
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteVersionAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.versions.count) {
        return;
    }
    
    // Get the version to be deleted
    NSDictionary *versionEntry = self.versions[index];
    NSString *displayName = versionEntry[@"displayName"];
    
    // Remove the version
    [self.versions removeObjectAtIndex:index];
    
    // Handle active version index updates
    if (self.activeVersionIndex == index) {
        // The active version was deleted
        if (self.versions.count > 0) {
            // Set first available version as active
            self.activeVersionIndex = 0;
        } else {
            // No versions left
            self.activeVersionIndex = -1;
        }
    } else if (self.activeVersionIndex > index) {
        // Need to adjust active index since we removed a version before it
        self.activeVersionIndex--;
    }
    
    // Save the changes
    [self saveVersions];
    
    // Refresh the UI
    [self.tableView reloadData];
    [self updateEmptyStateVisibility];
    
    // Show confirmation
    [self showAlertWithTitle:@"Version Deleted" 
                     message:[NSString stringWithFormat:@"Successfully deleted '%@'", displayName]];
}

#pragma mark - Helper Methods

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Button Action Handlers

- (void)editButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    [self editVersionAtIndex:index];
}

- (void)deleteButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    [self showDeleteConfirmationForVersionAtIndex:index completion:nil];
}

- (void)useButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    [self activateVersionAtIndex:index];
}

#pragma mark - Fetch Versions

- (void)fetchVersionsButtonTapped {
    [self fetchAppVersions];
}

- (void)fetchAppVersions {
    NSString *bundleID = self.bundleID;
    
    if (!bundleID || ![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
        [self showAlertWithTitle:@"Error" message:@"Invalid bundle ID"];
        return;
    }
    
    // Show loading indicator
    [self.loadingIndicator startAnimating];
    
    // Build iTunes lookup URL
    NSString *lookupUrlString = [NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@&entity=software&country=us", bundleID];
    NSURL *lookupUrl = [NSURL URLWithString:lookupUrlString];
    
    if (!lookupUrl) {
        [self showAlertWithTitle:@"Error" message:@"Invalid App Store URL"];
        [self.loadingIndicator stopAnimating];
        return;
    }
    
    // Make the App Store API request
    PXLog(@"[VersionManagement] Making API request to: %@", lookupUrlString);
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:lookupUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            PXLog(@"[VersionManagement] API request failed with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                [self showAlertWithTitle:@"Error" message:[NSString stringWithFormat:@"API request failed: %@", error.localizedDescription]];
            });
            return;
        }
        
        if (!data) {
            PXLog(@"[VersionManagement] No data received from API");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                [self showAlertWithTitle:@"Error" message:@"No data received from App Store"];
            });
            return;
        }
        
        // Parse the JSON response
        PXLog(@"[VersionManagement] Received data from API, length: %lu", (unsigned long)data.length);
        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        
        if (jsonErr) {
            PXLog(@"[VersionManagement] JSON parsing failed: %@", jsonErr);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                [self showAlertWithTitle:@"Error" message:[NSString stringWithFormat:@"Failed to parse response: %@", jsonErr.localizedDescription]];
            });
            return;
        }
        
        // Check if we got any results
        NSArray *results = json[@"results"];
        if (!results || ![results isKindOfClass:[NSArray class]] || results.count == 0) {
            PXLog(@"[VersionManagement] No results found for bundleID: %@", bundleID);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                [self showAlertWithTitle:@"Error" message:@"No App Store entry found for this bundle ID."];
            });
            return;
        }
        
        NSDictionary *appStoreInfo = results.firstObject;
        
        // Get the app ID for version history
        NSString *appId = appStoreInfo[@"trackId"];
        if (!appId) {
            PXLog(@"[VersionManagement] No track ID found in app info");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                [self showAlertWithTitle:@"Error" message:@"Could not retrieve app ID for version history."];
            });
            return;
        }
        
        // Now fetch version history using the app ID
        NSString *historyUrlString = [NSString stringWithFormat:@"https://apis.bilin.eu.org/history/%@", appId];
        NSURL *historyUrl = [NSURL URLWithString:historyUrlString];
        
        if (!historyUrl) {
            PXLog(@"[VersionManagement] Invalid URL for version history: %@", historyUrlString);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                [self showAlertWithTitle:@"Error" message:@"Invalid URL for version history."];
            });
            return;
        }
        
        PXLog(@"[VersionManagement] Fetching version history from: %@", historyUrlString);
        
        NSURLSessionDataTask *historyTask = [[NSURLSession sharedSession] dataTaskWithURL:historyUrl completionHandler:^(NSData *historyData, NSURLResponse *historyResponse, NSError *historyError) {
            if (historyError) {
                PXLog(@"[VersionManagement] Version history request failed: %@", historyError);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.loadingIndicator stopAnimating];
                    [self showAlertWithTitle:@"Error" message:@"Failed to fetch version history."];
                });
                return;
            }
            
            if (!historyData) {
                PXLog(@"[VersionManagement] No data received for version history");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.loadingIndicator stopAnimating];
                    [self showAlertWithTitle:@"Error" message:@"No version history data received."];
                });
                return;
            }
            
            NSError *historyJsonErr = nil;
            NSDictionary *historyJson = [NSJSONSerialization JSONObjectWithData:historyData options:0 error:&historyJsonErr];
            if (historyJsonErr || !historyJson || ![historyJson isKindOfClass:[NSDictionary class]]) {
                PXLog(@"[VersionManagement] Version history JSON parsing failed: %@", historyJsonErr);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.loadingIndicator stopAnimating];
                    [self showAlertWithTitle:@"Error" message:@"Invalid version history response."];
                });
                return;
            }
            
            NSArray *versions = historyJson[@"data"];
            if (![versions isKindOfClass:[NSArray class]]) {
                PXLog(@"[VersionManagement] No version history found");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.loadingIndicator stopAnimating];
                    [self showAlertWithTitle:@"Error" message:@"No version history found for this app."];
                });
                return;
            }
            
            PXLog(@"[VersionManagement] Found %lu versions in history", (unsigned long)versions.count);
            
            // Process versions
            NSMutableArray *processedVersions = [NSMutableArray array];
            
            // Add current version first with proper iOS version info
            NSMutableDictionary *currentVersion = [NSMutableDictionary dictionary];
            currentVersion[@"version"] = appStoreInfo[@"version"];
            currentVersion[@"releaseDate"] = appStoreInfo[@"currentVersionReleaseDate"];
            
            // Get build number for current version
            NSString *currentBuildNumber = appStoreInfo[@"build"];
            if (currentBuildNumber && currentBuildNumber.length > 0) {
                currentVersion[@"build"] = currentBuildNumber;
            }
            
            // Get minimum OS version from current app info
            NSString *currentMinOSVersion = appStoreInfo[@"minimumOsVersion"];
            if (currentMinOSVersion && currentMinOSVersion.length > 0) {
                currentVersion[@"minimumOSVersion"] = currentMinOSVersion;
            } else {
                currentVersion[@"minimumOSVersion"] = @"Unknown";
            }
            currentVersion[@"isCurrent"] = @YES;
            [processedVersions addObject:currentVersion];
            
            // Add historical versions with proper iOS version info
            for (NSDictionary *version in versions) {
                if (![version isKindOfClass:[NSDictionary class]]) continue;
                
                NSMutableDictionary *versionInfo = [NSMutableDictionary dictionary];
                versionInfo[@"version"] = version[@"bundle_version"];
                versionInfo[@"releaseDate"] = version[@"created_at"] ?: @"Unknown";
                
                // Get build number from version history
                NSString *buildNumber = version[@"build"];
                if (!buildNumber || buildNumber.length == 0) {
                    // Try alternate build number field
                    buildNumber = version[@"build_number"];
                }
                if (!buildNumber || buildNumber.length == 0) {
                    // Try to get from version details
                    NSDictionary *versionDetails = version[@"version_details"];
                    if ([versionDetails isKindOfClass:[NSDictionary class]]) {
                        buildNumber = versionDetails[@"build"];
                        if (!buildNumber || buildNumber.length == 0) {
                            buildNumber = versionDetails[@"build_number"];
                        }
                    }
                }
                if (buildNumber && buildNumber.length > 0) {
                    versionInfo[@"build"] = buildNumber;
                }
                
                // Get minimum OS version from version history API
                NSString *minOSVersion = version[@"minimum_os_version"];
                if (!minOSVersion || [minOSVersion isEqualToString:@""]) {
                    // If not available in version history, try to get from app info
                    minOSVersion = appStoreInfo[@"minimumOsVersion"];
                }
                
                // If still not available, try to get from version-specific info
                if (!minOSVersion || [minOSVersion isEqualToString:@""]) {
                    NSDictionary *versionDetails = version[@"version_details"];
                    if ([versionDetails isKindOfClass:[NSDictionary class]]) {
                        minOSVersion = versionDetails[@"minimum_os_version"];
                    }
                }
                
                versionInfo[@"minimumOSVersion"] = minOSVersion ?: @"Unknown";
                versionInfo[@"isCurrent"] = @NO;
                [processedVersions addObject:versionInfo];
            }
            
            // Sort versions by release date (newest first)
            [processedVersions sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
                NSString *date1 = obj1[@"releaseDate"];
                NSString *date2 = obj2[@"releaseDate"];
                
                // Handle "Unknown" dates
                if ([date1 isEqualToString:@"Unknown"]) return NSOrderedAscending;
                if ([date2 isEqualToString:@"Unknown"]) return NSOrderedDescending;
                
                // Parse dates
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
                
                NSDate *date1Obj = [formatter dateFromString:date1];
                NSDate *date2Obj = [formatter dateFromString:date2];
                
                if (!date1Obj) return NSOrderedAscending;
                if (!date2Obj) return NSOrderedDescending;
                
                return [date2Obj compare:date1Obj];
            }];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.appVersions = processedVersions;
                [self.loadingIndicator stopAnimating];
                [self showVersionSelectionPopup];
            });
        }];
        
        [historyTask resume];
    }];
    
    [task resume];
    self.currentVersionTask = task;
}

- (void)showVersionSelectionPopup {
    if (!self.appVersions || self.appVersions.count == 0) {
        [self showAlertWithTitle:@"Error" message:@"No versions available"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Select Version"
                                                                   message:@"Choose a version to add"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add top 10 most recent versions for better UX
    NSInteger count = MIN(10, self.appVersions.count);
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *version = self.appVersions[i];
        NSString *versionNum = version[@"version"];
        NSString *build = version[@"build"] ?: @"unknown";
        NSString *minOS = version[@"minimumOSVersion"] ?: @"unknown";
        
        NSString *title = [NSString stringWithFormat:@"%@ (Build: %@, iOS %@+)", versionNum, build, minOS];
        
        [alert addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self addVersionFromAppStore:version];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // For iPad
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 
                                                                   self.view.bounds.size.height / 2, 
                                                                   1, 1);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addVersionFromAppStore:(NSDictionary *)versionInfo {
    NSString *version = versionInfo[@"version"];
    NSString *build = versionInfo[@"build"];
    NSString *minOS = versionInfo[@"minimumOSVersion"];
    
    NSString *displayName = [NSString stringWithFormat:@"v%@ (iOS %@+)", version, minOS];
    
    // Create version entry
    NSDictionary *versionEntry = @{
        @"displayName": displayName,
        @"version": version,
        @"build": build ?: @"",
        @"minOS": minOS ?: @"Unknown",
        @"dateAdded": [NSDate date]
    };
    
    // Check if this version already exists
    BOOL versionExists = NO;
    for (NSDictionary *existingVersion in self.versions) {
        if ([existingVersion[@"version"] isEqualToString:version] && [existingVersion[@"build"] isEqualToString:build ?: @""]) {
            versionExists = YES;
            break;
        }
    }
    
    if (versionExists) {
        [self showAlertWithTitle:@"Version Exists" message:@"This version is already in your list."];
        return;
    }
    
    // Add to versions array
    [self.versions addObject:versionEntry];
    
    // If this is the first version added, make it active
    if (self.versions.count == 1) {
        self.activeVersionIndex = 0;
    }
    
    // Save the changes
    [self saveVersions];
    
    // Refresh the UI
    [self.tableView reloadData];
    [self updateEmptyStateVisibility];
    
    // Show confirmation
    [self showAlertWithTitle:@"Version Added" message:[NSString stringWithFormat:@"Successfully added %@", displayName]];
}

#pragma mark - Update table view height for row to accommodate the buttons

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return 84; // App info section - increased for card with padding
    } else {
        return 112; // Version cells with buttons - increased for card with padding
    }
}

// Add footer to the versions section to explain usage
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == 1 && self.versions.count > 0) {
        UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30)];
        footerView.backgroundColor = [UIColor clearColor];
        
        UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, tableView.bounds.size.width - 32, 30)];
        infoLabel.text = @"Tap 'Use' to make a version active";
        infoLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        infoLabel.textColor = [UIColor secondaryLabelColor];
        infoLabel.textAlignment = NSTextAlignmentCenter;
        [footerView addSubview:infoLabel];
        
        return footerView;
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 1 && self.versions.count > 0) {
        return 30.0;
    }
    return 0.0;
}

@end 