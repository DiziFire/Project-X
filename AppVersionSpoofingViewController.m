#import "AppVersionSpoofingViewController.h"

// Class extension for private method declaration
@interface AppVersionSpoofingViewController ()
// All private properties
@property (nonatomic, strong) UILabel *emptyStateLabel;
@property (nonatomic, strong) UIViewController *versionsPopupVC;
@property (nonatomic, strong) UITableView *versionsTableView;
@property (nonatomic, strong) UISearchBar *versionSearchBar;
@property (nonatomic, strong) NSArray *appVersions;
@property (nonatomic, strong) NSArray *filteredVersions;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) NSString *selectedBundleID;
@property (nonatomic, strong) NSURLSessionDataTask *currentVersionTask;
@property (nonatomic, strong) NSString *appStoreConnectKey;
@property (nonatomic, strong) NSString *appStoreConnectKeyId;
@property (nonatomic, strong) NSString *appStoreConnectIssuerId;
@property (nonatomic, readwrite) NSInteger maxVersionsPerApp;
@property (nonatomic, strong) NSString *currentlyEditingBundleID;
- (void)persistSpoofingToggleForBundleID:(NSString *)bundleID enabled:(BOOL)enabled;
@end
#import "ProjectXLogging.h"
#import "DownloadResourcesViewController.h"
#import "VersionManagementViewController.h"

@implementation AppVersionSpoofingViewController

// Show toast in viewDidAppear if message is set
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.toastMessageToShow && self.toastMessageToShow.length > 0) {
        [self showToastWithMessage:self.toastMessageToShow];
        self.toastMessageToShow = nil;
    }
}

// Helper method to show a toast-like notification at the top
- (void)showToastWithMessage:(NSString *)message {
    CGFloat toastHeight = 60.0;
    CGFloat padding = 16.0;
    UILabel *toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, 44 + padding, self.view.frame.size.width - 2 * padding, toastHeight)];
    toastLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    toastLabel.textColor = [UIColor whiteColor];
    toastLabel.textAlignment = NSTextAlignmentCenter;
    toastLabel.font = [UIFont boldSystemFontOfSize:16.0];
    toastLabel.text = message;
    toastLabel.numberOfLines = 2;
    toastLabel.layer.cornerRadius = 12;
    toastLabel.layer.masksToBounds = YES;
    toastLabel.alpha = 0.0;
    toastLabel.userInteractionEnabled = NO;
    toastLabel.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:toastLabel];

    [UIView animateWithDuration:0.3 animations:^{
        toastLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastLabel.alpha = 0.0;
            } completion:^(BOOL finished2) {
                [toastLabel removeFromSuperview];
            }];
        });
    }];
}


#pragma mark - Copy Popup Logic
- (void)showCopyPopupForApp:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row < self.appsData.count) {
        NSString *bundleID = self.appsData.allKeys[row];
        NSDictionary *appInfo = self.appsData[bundleID];
        NSString *realVersion = appInfo[@"version"] ?: @"Unknown";
        NSString *realBuild = appInfo[@"build"] ?: @"Unknown";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Real Version & Build"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        // Version row
        UIAlertAction *copyVersion = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Copy Version (%@)", realVersion]
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
            [UIPasteboard generalPasteboard].string = realVersion;
            [self showCopiedAlert:@"Version copied!"];
        }];
        // Build row
        UIAlertAction *copyBuild = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Copy Build (%@)", realBuild]
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
            [UIPasteboard generalPasteboard].string = realBuild;
            [self showCopiedAlert:@"Build copied!"];
        }];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:copyVersion];
        [alert addAction:copyBuild];
        [alert addAction:cancel];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
- (void)showCopiedAlert:(NSString *)msg {
    UIAlertController *copied = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:copied animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [copied dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

#pragma mark - UICollectionView Header for Info Alert
- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    if (kind == UICollectionElementKindSectionHeader) {
        UICollectionReusableView *headerView = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"InfoHeader" forIndexPath:indexPath];
        // Remove previous subviews if any
        for (UIView *subview in headerView.subviews) {
            [subview removeFromSuperview];
        }
        UIView *infoBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, collectionView.bounds.size.width, 200)];
        infoBox.backgroundColor = [UIColor colorWithRed:0.97 green:0.98 blue:1.0 alpha:1.0];
        infoBox.layer.cornerRadius = 10;
        infoBox.layer.borderWidth = 1.2;
        infoBox.layer.borderColor = [UIColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:0.25].CGColor;
        infoBox.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, infoBox.bounds.size.width - 24, 180)];
        infoLabel.numberOfLines = 0;
        infoLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        infoLabel.textColor = [UIColor colorWithRed:0.15 green:0.22 blue:0.35 alpha:1.0];
        infoLabel.text = @"How to Spoof App Version and Build:\n\n• Use the toggle switch to enable spoofing for the app you want to spoof.\n• Use the Edit button to manually enter a version and build number to spoof the app.\n• Use the Fetch button to retrieve a list of available versions. You can select a version from the list, but you will need to find the correct build number yourself. To do this, install the desired version of the app and check its real build number in the installed app's info.";
        infoLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [infoBox addSubview:infoLabel];
        [headerView addSubview:infoBox];
        return headerView;
    }
    return [UICollectionReusableView new];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    return CGSizeMake(collectionView.bounds.size.width, 200);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"App Version Spoofing";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // Initialize data
    self.appsData = [NSMutableDictionary dictionary];
    self.multiVersionData = [NSMutableDictionary dictionary];
    self.maxVersionsPerApp = 10; // Allow up to 10 versions per app
    
    // Create collection view layout
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumLineSpacing = 20;
    layout.minimumInteritemSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(20, 20, 20, 20);
    
    // Calculate item size (adjust for different screen sizes)
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat itemWidth = screenWidth - 40; // Full width minus left and right margins
    layout.itemSize = CGSizeMake(itemWidth, 160); // Increased height to fit both version and build
    
    // Create collection view
    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.alwaysBounceVertical = YES;
    [self.view addSubview:self.collectionView];
    
    // Register cell class
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"AppCard"];
    // Register header class
    [self.collectionView registerClass:[UICollectionReusableView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"InfoHeader"];
    
    // Setup empty state label
    self.emptyStateLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    self.emptyStateLabel.text = @"No apps found in scope list.\nAdd apps through the Scope tab first.";
    self.emptyStateLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyStateLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyStateLabel.numberOfLines = 0;
    self.emptyStateLabel.center = self.view.center;
    self.emptyStateLabel.hidden = YES;
    [self.view addSubview:self.emptyStateLabel];
    
    // Add button to add new app
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] 
                                 initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                 target:self 
                                 action:@selector(addButtonTapped)];
    
    // Add back button
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc]
                                  initWithImage:[UIImage systemImageNamed:@"chevron.left"]
                                  style:UIBarButtonItemStylePlain
                                  target:self
                                  action:@selector(backButtonTapped)];
    
    self.navigationItem.leftBarButtonItem = backButton;
    self.navigationItem.rightBarButtonItem = addButton;
    
    // Load apps data
    [self loadAppsData];
}

// Add back button functionality
- (void)backButtonTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Override the view controller presentation
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Find the tab bar controller and make sure it stays visible
    UIViewController *parentVC = self;
    while (parentVC.parentViewController && ![parentVC.parentViewController isKindOfClass:[UITabBarController class]]) {
        parentVC = parentVC.parentViewController;
    }
    
    if ([parentVC.parentViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)parentVC.parentViewController;
        tabBarController.tabBar.hidden = NO;
    }
}

- (NSString *)getAppVersionFilePathForBundleID:(NSString *)bundleID {
    if (!bundleID) return nil;
    
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
            PXLog(@"[AppVersionSpoofing] No profile ID found, using default shared storage");
            return nil;
        }
    }
    
    // Build the path to this profile's app versions directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *appVersionsDir = [profileDir stringByAppendingPathComponent:@"app_versions"];
    
    // Check if the directory exists
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:appVersionsDir]) {
        return nil;
    }
    
    // Create a safe filename from the bundle ID
    NSString *safeFilename = [bundleID stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    safeFilename = [safeFilename stringByAppendingString:@"_version.plist"];
    
    NSString *fullPath = [appVersionsDir stringByAppendingPathComponent:safeFilename];
    
    // Only return if file exists
    if ([fileManager fileExistsAtPath:fullPath]) {
        return fullPath;
    }
    
    return nil;
}

- (void)loadAppsData {
    // Try rootless path first
    NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
    NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
    NSString *versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
    NSString *multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
    
    // Fallback to standard path if rootless path doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:prefsPath]) {
        // Try Dopamine 2 path
        prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
        scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
        multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        
        // Fallback to standard path if needed
        if (![fileManager fileExistsAtPath:prefsPath]) {
            prefsPath = @"/var/mobile/Library/Preferences";
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
            versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
            multiVersionFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.multi_version_spoof.plist"];
        }
    }
    
    PXLog(@"[AppVersionSpoofing] Trying to load apps from: %@", scopedAppsFile);
    PXLog(@"[AppVersionSpoofing] Trying to load version spoof data from: %@", versionSpoofFile);
    PXLog(@"[AppVersionSpoofing] Trying to load multi-version spoof data from: %@", multiVersionFile);
    
    // Load scoped apps from the global scope file
    NSDictionary *scopedAppsDict = [NSDictionary dictionaryWithContentsOfFile:scopedAppsFile];
    NSDictionary *savedApps = scopedAppsDict[@"ScopedApps"];
    
    // Load version spoofing data from global file
    NSDictionary *versionSpoofDict = [NSDictionary dictionaryWithContentsOfFile:versionSpoofFile];
    NSDictionary *spoofedVersions = versionSpoofDict[@"SpoofedVersions"];
    
    // Load multi-version spoofing data
    NSDictionary *multiVersionDict = [NSDictionary dictionaryWithContentsOfFile:multiVersionFile];
    NSDictionary *multiVersions = multiVersionDict[@"MultiVersions"];
    if (multiVersions) {
        self.multiVersionData = [multiVersions mutableCopy];
    }
    
    if (savedApps && savedApps.count > 0) {
        self.appsData = [savedApps mutableCopy];
        
        // For each app in saved apps, check if we have version spoofing info
        if (spoofedVersions) {
            for (NSString *bundleID in self.appsData.allKeys) {
                NSMutableDictionary *appInfo = [self.appsData[bundleID] mutableCopy];
                NSDictionary *spoofInfo = spoofedVersions[bundleID];
                
                // Get toggle state ONLY from global file
                if (spoofInfo) {
                    // Add spoofed version if available
                    if (spoofInfo[@"spoofedVersion"]) {
                        appInfo[@"spoofedVersion"] = spoofInfo[@"spoofedVersion"];
                    }
                    // Add spoofed build if available
                    if (spoofInfo[@"spoofedBuild"]) {
                        appInfo[@"spoofedBuild"] = spoofInfo[@"spoofedBuild"];
                    }
                    // Add spoofingEnabled toggle state
                    if (spoofInfo[@"spoofingEnabled"]) {
                        appInfo[@"spoofingEnabled"] = spoofInfo[@"spoofingEnabled"];
                    } else {
                        appInfo[@"spoofingEnabled"] = @NO;
                    }
                    // Add activeVersionIndex if available
                    if (spoofInfo[@"activeVersionIndex"]) {
                        appInfo[@"activeVersionIndex"] = spoofInfo[@"activeVersionIndex"];
                    }
                } else {
                    // Set default toggle state if no info available
                    appInfo[@"spoofingEnabled"] = @NO;
                }
                
                // We should still load version and build data from profile files
                // but toggle state always comes from global file
                NSString *profileVersionFile = [self getAppVersionFilePathForBundleID:bundleID];
                if (profileVersionFile) {
                    // Load only version/build data from profile-specific file
                    NSDictionary *appVersionData = [NSDictionary dictionaryWithContentsOfFile:profileVersionFile];
                    if (appVersionData) {
                        // Add spoofed version if available
                        if (appVersionData[@"spoofedVersion"]) {
                            appInfo[@"spoofedVersion"] = appVersionData[@"spoofedVersion"];
                        }
                        // Add spoofed build if available
                        if (appVersionData[@"spoofedBuild"]) {
                            appInfo[@"spoofedBuild"] = appVersionData[@"spoofedBuild"];
                        }
                        // IMPORTANT: Ignore spoofingEnabled from profile file
                        // The toggle state should only come from the global plist
                        
                        // Add activeVersionIndex if available
                        if (appVersionData[@"activeVersionIndex"]) {
                            appInfo[@"activeVersionIndex"] = appVersionData[@"activeVersionIndex"];
                        }
                    }
                }
                
                self.appsData[bundleID] = appInfo;
            }
        }
        
        PXLog(@"[AppVersionSpoofing] Loaded %lu apps from scope list", (unsigned long)self.appsData.count);
        PXLog(@"[AppVersionSpoofing] Loaded %lu spoofed app versions", (unsigned long)spoofedVersions.count);
        PXLog(@"[AppVersionSpoofing] Loaded %lu multi-version configurations", (unsigned long)self.multiVersionData.count);
        self.emptyStateLabel.hidden = YES;
    } else {
        PXLog(@"[AppVersionSpoofing] No apps found in scope list");
        self.emptyStateLabel.hidden = NO;
    }
    
    [self.collectionView reloadData];
}

- (void)addButtonTapped {
    // Open scope tab where apps can be added
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Apps"
                                                                   message:@"Please add apps to the scope list using the ProjectX tab (HomeTab)."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.appsData.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    // Declare bundleID and appInfo at the top for use in all UI code
    NSString *bundleID = self.appsData.allKeys[indexPath.row];
    NSDictionary *appInfo = self.appsData[bundleID];
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AppCard" forIndexPath:indexPath];

    // Remove reused subviews
    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }

    // Reset cell properties
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.layer.cornerRadius = 20;
    cell.layer.masksToBounds = YES;
    
    // Create blur effect with dynamic style based on appearance
    UIBlurEffect *blurEffect;
    if (@available(iOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        } else {
            blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
        }
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    }
    
    // Create background container with proper corner radius
    UIView *backgroundContainer = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    backgroundContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backgroundContainer.backgroundColor = [UIColor clearColor];
    backgroundContainer.layer.cornerRadius = 20;
    backgroundContainer.clipsToBounds = YES;
    [cell.contentView insertSubview:backgroundContainer atIndex:0];
    
    // Add blur effect view
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = backgroundContainer.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backgroundContainer addSubview:blurView];
    
    // Add subtle gradient overlay with dynamic colors
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = backgroundContainer.bounds;
    gradientLayer.cornerRadius = 20;
    if (@available(iOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            gradientLayer.colors = @[
                (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.15].CGColor,
                (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor
            ];
        } else {
            gradientLayer.colors = @[
                (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.35].CGColor,
                (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.15].CGColor
            ];
        }
    } else {
        gradientLayer.colors = @[
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.35].CGColor,
            (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.15].CGColor
        ];
    }
    gradientLayer.locations = @[@0.0, @1.0];
    [backgroundContainer.layer insertSublayer:gradientLayer above:blurView.layer];
    
    // Add subtle border with dynamic color
    UIView *borderView = [[UIView alloc] initWithFrame:backgroundContainer.bounds];
    borderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    borderView.layer.cornerRadius = 20;
    borderView.layer.borderWidth = 0.5;
    if (@available(iOS 13.0, *)) {
        if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            borderView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
        } else {
            borderView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.1].CGColor;
        }
    } else {
        borderView.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.1].CGColor;
    }
    [backgroundContainer addSubview:borderView];
    
    // Add subtle shadow
    cell.layer.shadowColor = [UIColor blackColor].CGColor;
    cell.layer.shadowOffset = CGSizeMake(0, 4);
    cell.layer.shadowRadius = 12;
    cell.layer.shadowOpacity = 0.1;
    cell.layer.masksToBounds = NO;
    
    // Create a container view for content to ensure proper clipping
    UIView *contentContainer = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    contentContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    contentContainer.backgroundColor = [UIColor clearColor];
    [cell.contentView addSubview:contentContainer];
    
    CGFloat padding = 16;
    CGFloat cardWidth = cell.contentView.bounds.size.width;
    CGFloat y = padding;

    // Add UISwitch for spoofing toggle (left side) with glass effect
    UISwitch *spoofSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    spoofSwitch.onTintColor = [UIColor systemBlueColor];
    spoofSwitch.tag = indexPath.row;
    BOOL spoofingEnabled = [appInfo[@"spoofingEnabled"] boolValue];
    spoofSwitch.on = spoofingEnabled;
    [spoofSwitch addTarget:self action:@selector(toggleSpoofingSwitch:) forControlEvents:UIControlEventValueChanged];
    spoofSwitch.center = CGPointMake(padding + spoofSwitch.bounds.size.width/2, y + 20);
    [contentContainer addSubview:spoofSwitch];

    // App Name label with glass effect
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding + 56, y, cardWidth - (padding*2 + 56), 26)];
    nameLabel.text = appInfo[@"name"] ?: bundleID;
    nameLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    nameLabel.textColor = [UIColor labelColor];
    [contentContainer addSubview:nameLabel];
    y += 28;

    // Check for multiple versions
    NSArray *multiVersions = self.multiVersionData[bundleID];
    NSInteger versionCount = multiVersions ? multiVersions.count : 0;
    
    // Bundle ID label with glass effect
    NSString *bundleText = versionCount > 0 ? 
        [NSString stringWithFormat:@"%@ (%ld versions)", bundleID, (long)versionCount] : 
        bundleID;
    
    UILabel *bundleLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding + 56, y, cardWidth - (padding*2 + 56), 18)];
    bundleLabel.text = bundleText;
    bundleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    bundleLabel.textColor = [UIColor secondaryLabelColor];
    [contentContainer addSubview:bundleLabel];
    y += 20;

    // Real version/build with glass effect
    NSString *realVersion = appInfo[@"version"] ?: @"Unknown";
    NSString *realBuild = appInfo[@"build"] ?: @"";
    UILabel *realLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding + 56, y, cardWidth - (padding*2 + 56) - 28, 18)];
    if (realVersion.length > 0 && realBuild.length > 0) {
        realLabel.text = [NSString stringWithFormat:@"Real: %@ (%@)", realVersion, realBuild];
    } else if (realVersion.length > 0) {
        realLabel.text = [NSString stringWithFormat:@"Real: %@", realVersion];
    } else if (realBuild.length > 0) {
        realLabel.text = [NSString stringWithFormat:@"Real Build: %@", realBuild];
    } else {
        realLabel.text = @"Real: Unknown";
    }
    realLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    realLabel.textColor = [UIColor tertiaryLabelColor];
    [contentContainer addSubview:realLabel];
    // Add copy button next to realLabel
    UIButton *copyRealBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyRealBtn.frame = CGRectMake(CGRectGetMaxX(realLabel.frame) + 2, y, 24, 18);
    [copyRealBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copyRealBtn.tintColor = [UIColor systemGrayColor];
    copyRealBtn.tag = indexPath.row;
    [copyRealBtn addTarget:self action:@selector(showCopyPopupForApp:) forControlEvents:UIControlEventTouchUpInside];
    [contentContainer addSubview:copyRealBtn];
    y += 20;

    // Spoofed Version/Build with glass effect
    NSString *spoofedVersion = appInfo[@"spoofedVersion"];
    NSString *spoofedBuild = appInfo[@"spoofedBuild"];
    UILabel *spoofedLabel = nil;
    if (spoofedVersion.length > 0 || spoofedBuild.length > 0) {
        spoofedLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding + 56, y, cardWidth - (padding*2 + 56), 18)];
        
        // If there are multiple versions, show which one is active
        if (versionCount > 0) {
            NSNumber *activeIndexObj = appInfo[@"activeVersionIndex"];
            NSInteger activeIndex = activeIndexObj ? [activeIndexObj integerValue] : -1;
            
            if (activeIndex >= 0 && activeIndex < versionCount) {
                NSDictionary *activeVersion = multiVersions[activeIndex];
                NSString *displayName = activeVersion[@"displayName"];
                
                if (spoofedVersion.length > 0 && spoofedBuild.length > 0) {
                    spoofedLabel.text = [NSString stringWithFormat:@"Spoofed: %@ (%@) [%@]", spoofedVersion, spoofedBuild, displayName];
                } else if (spoofedVersion.length > 0) {
                    spoofedLabel.text = [NSString stringWithFormat:@"Spoofed: %@ [%@]", spoofedVersion, displayName];
                } else {
                    spoofedLabel.text = [NSString stringWithFormat:@"Spoofed Build: %@ [%@]", spoofedBuild, displayName];
                }
            } else {
                // Use standard format if active index is invalid
                if (spoofedVersion.length > 0 && spoofedBuild.length > 0) {
                    spoofedLabel.text = [NSString stringWithFormat:@"Spoofed: %@ (%@)", spoofedVersion, spoofedBuild];
                } else if (spoofedVersion.length > 0) {
                    spoofedLabel.text = [NSString stringWithFormat:@"Spoofed: %@", spoofedVersion];
                } else {
                    spoofedLabel.text = [NSString stringWithFormat:@"Spoofed Build: %@", spoofedBuild];
                }
            }
        } else {
            // Standard format for single version
            if (spoofedVersion.length > 0 && spoofedBuild.length > 0) {
                spoofedLabel.text = [NSString stringWithFormat:@"Spoofed: %@ (%@)", spoofedVersion, spoofedBuild];
            } else if (spoofedVersion.length > 0) {
                spoofedLabel.text = [NSString stringWithFormat:@"Spoofed: %@", spoofedVersion];
            } else {
                spoofedLabel.text = [NSString stringWithFormat:@"Spoofed Build: %@", spoofedBuild];
            }
        }
        
        spoofedLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
        spoofedLabel.textColor = [UIColor systemGreenColor];
        [contentContainer addSubview:spoofedLabel];
        y += 20;
    }

    // Button row with glass effect
    CGFloat buttonWidth = 100;
    CGFloat buttonHeight = 34;
    CGFloat buttonSpacing = 16;
    CGFloat buttonY = y + 4;
    CGFloat totalWidth = buttonWidth * 2 + buttonSpacing;
    CGFloat buttonRowX = (cardWidth - totalWidth) / 2;

    // Edit button with glass effect
    UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    editButton.frame = CGRectMake(buttonRowX, buttonY, buttonWidth, buttonHeight);
    [editButton setTitle:@"Edit" forState:UIControlStateNormal];
    editButton.backgroundColor = [UIColor systemBlueColor];
    editButton.tintColor = [UIColor whiteColor];
    editButton.layer.cornerRadius = 17;
    editButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    editButton.tag = indexPath.row;
    [editButton addTarget:self action:@selector(editAppButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [contentContainer addSubview:editButton];

    // Fetch button with glass effect
    UIButton *fetchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    fetchButton.frame = CGRectMake(buttonRowX + buttonWidth + buttonSpacing, buttonY, buttonWidth, buttonHeight);
    [fetchButton setTitle:@"Fetch" forState:UIControlStateNormal];
    fetchButton.backgroundColor = [UIColor systemGreenColor];
    fetchButton.tintColor = [UIColor whiteColor];
    fetchButton.layer.cornerRadius = 17;
    fetchButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    fetchButton.tag = indexPath.row;
    [fetchButton addTarget:self action:@selector(fetchAppButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [contentContainer addSubview:fetchButton];

    return cell;
}

// Handle fetch button

- (void)fetchAppButtonTapped:(UIButton *)sender {
    PXLog(@"[AppVersionSpoofing] Fetch button tapped for index: %ld", (long)sender.tag);
    
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= self.appsData.allKeys.count) {
        PXLog(@"[AppVersionSpoofing] Invalid index for fetch: %ld", (long)idx);
        return;
    }
    
    NSString *bundleID = self.appsData.allKeys[idx];
    if (!bundleID || ![bundleID isKindOfClass:[NSString class]]) {
        PXLog(@"[AppVersionSpoofing] Invalid bundleID for fetch");
        return;
    }
    
    // Store the selected bundle ID for later use
    self.selectedBundleID = bundleID;
    
    PXLog(@"[AppVersionSpoofing] Fetching versions for bundleID: %@", bundleID);
    
    // Display a loading indicator
    if (!self.loadingIndicator) {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        self.loadingIndicator.center = self.view.center;
        [self.view addSubview:self.loadingIndicator];
    }
    
    // Instead of creating a popup, just open the version management screen
    NSDictionary *appInfo = self.appsData[bundleID];
    
    // Create and navigate to version management view controller
    VersionManagementViewController *versionVC = [[VersionManagementViewController alloc] initWithBundleID:bundleID appInfo:appInfo];
    versionVC.delegate = self;
    versionVC.title = [NSString stringWithFormat:@"%@ Versions", appInfo[@"name"] ?: @"App"];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:versionVC];
    [self presentViewController:navController animated:YES completion:^{
        // Once the screen is presented, automatically trigger the fetch versions action
        [versionVC fetchVersionsButtonTapped];
    }];
}

- (void)closeVersionsPopup {
    PXLog(@"[AppVersionSpoofing] Attempting to close versions popup");
    
    // Cancel any ongoing network requests
    [self.currentVersionTask cancel];
    self.currentVersionTask = nil;
    
    if (!self.versionsPopupVC) {
        PXLog(@"[AppVersionSpoofing] Warning: versionsPopupVC is nil when attempting to close");
        return;
    }
    
    // Check if popup is already being dismissed
    if (self.versionsPopupVC.isBeingDismissed) {
        PXLog(@"[AppVersionSpoofing] Warning: versionsPopupVC is already being dismissed");
        return;
    }
    
    // Stop loading indicator if it's animating
    if (self.loadingIndicator.isAnimating) {
        [self.loadingIndicator stopAnimating];
    }
    
    // Reset table view state
    self.versionsTableView.hidden = NO;
    self.filteredVersions = nil;
    self.appVersions = nil;
    [self.versionsTableView reloadData];
    
    // Check if popup is still valid and presented
    if (![self.versionsPopupVC isBeingPresented] && !self.versionsPopupVC.presentingViewController) {
        PXLog(@"[AppVersionSpoofing] Warning: versionsPopupVC is not currently presented");
        self.versionsPopupVC = nil;
        return;
    }
    
    // Use strong reference to prevent premature deallocation
    UIViewController *popupVC = self.versionsPopupVC;
    [popupVC dismissViewControllerAnimated:YES completion:^{
        PXLog(@"[AppVersionSpoofing] Successfully dismissed versions popup");
        // Only clear if it's still the same popup
        if (self.versionsPopupVC == popupVC) {
            self.versionsPopupVC = nil;
        }
    }];
}

- (void)showErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Add missing dismissKeyboard method
- (void)dismissKeyboard {
    [self.versionSearchBar resignFirstResponder];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    PXLog(@"[AppVersionSpoofing] Number of rows in section %ld: %lu", (long)section, (unsigned long)self.filteredVersions.count);
    return self.filteredVersions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PXLog(@"[AppVersionSpoofing] Configuring cell for row %ld", (long)indexPath.row);
    
    static NSString *cellID = @"VersionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        PXLog(@"[AppVersionSpoofing] Created new cell");
    }
    
    // Clear any existing subviews
    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }
    
    if (indexPath.row < self.filteredVersions.count) {
        NSDictionary *ver = self.filteredVersions[indexPath.row];
        PXLog(@"[AppVersionSpoofing] Version data for row %ld: %@", (long)indexPath.row, ver);
        
        // Create a container view for better layout
        UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cell.contentView.bounds.size.width, 76)];
        containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        containerView.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:containerView];
        
        // Version and Build label (left side)
        UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, containerView.bounds.size.width - 32, 20)];
        versionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        versionLabel.textColor = [UIColor labelColor];
        versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        NSString *buildStr = ver[@"build"];
        if (buildStr && buildStr.length > 0) {
            versionLabel.text = [NSString stringWithFormat:@"%@ (%@)", ver[@"version"], buildStr];
        } else {
            versionLabel.text = ver[@"version"];
        }
        [containerView addSubview:versionLabel];

        // Enhanced highlight if this is the installed version
        NSString *installedVersion = self.appsData[self.selectedBundleID][@"version"];
        if (installedVersion && [ver[@"version"] isEqualToString:installedVersion]) {
            containerView.backgroundColor = [UIColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:0.18]; // Vibrant blue with transparency
            containerView.layer.cornerRadius = 12;
            containerView.layer.borderWidth = 2.0;
            containerView.layer.borderColor = [UIColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:0.8].CGColor;
            containerView.layer.masksToBounds = YES;
            versionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
            versionLabel.textColor = [UIColor colorWithRed:0.20 green:0.40 blue:0.80 alpha:1.0];
            // Add a checkmark or 'Installed' label
            UILabel *installedLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(versionLabel.frame) + 8, versionLabel.frame.origin.y, 70, 20)];
            installedLabel.text = @"✓ Installed";
            installedLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            installedLabel.textColor = [UIColor colorWithRed:0.20 green:0.60 blue:0.20 alpha:1.0];
            installedLabel.backgroundColor = [UIColor clearColor];
            [containerView addSubview:installedLabel];
        }
        
        // App name label (right side)
        UILabel *appNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(containerView.bounds.size.width - 150, 12, 134, 20)];
        appNameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        appNameLabel.textColor = [UIColor secondaryLabelColor];
        appNameLabel.textAlignment = NSTextAlignmentRight;
        appNameLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        
        // Get app name from appsData
        NSString *appName = self.appsData[self.selectedBundleID][@"name"];
        if (!appName || appName.length == 0) {
            appName = self.selectedBundleID;
        }
        appNameLabel.text = appName;
        [containerView addSubview:appNameLabel];
        
        // Release date label
        UILabel *dateLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 32, containerView.bounds.size.width - 32, 16)];
        dateLabel.font = [UIFont systemFontOfSize:13];
        dateLabel.textColor = [UIColor secondaryLabelColor];
        dateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        // Format the release date
        NSString *releaseDate = ver[@"releaseDate"];
        if (releaseDate && releaseDate.length > 0) {
            NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
            [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
            NSDate *date = [inputFormatter dateFromString:releaseDate];
            
            if (date) {
                NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
                [outputFormatter setDateFormat:@"MMM d, yyyy"];
                dateLabel.text = [outputFormatter stringFromDate:date];
            } else {
                dateLabel.text = releaseDate;
            }
        }
        [containerView addSubview:dateLabel];
        
        // Compatibility label
        UILabel *compatibilityLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 48, containerView.bounds.size.width - 32, 16)];
        compatibilityLabel.font = [UIFont systemFontOfSize:13];
        compatibilityLabel.textColor = [UIColor tertiaryLabelColor];
        compatibilityLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        // Get compatibility info
        NSString *minOSVersion = ver[@"minimumOSVersion"];
        if (minOSVersion && minOSVersion.length > 0) {
            compatibilityLabel.text = [NSString stringWithFormat:@"iOS %@ or later", minOSVersion];
        } else {
            compatibilityLabel.text = @"iOS compatibility unknown";
        }
        [containerView addSubview:compatibilityLabel];
        
        // Add a separator line
        UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(16, 75, containerView.bounds.size.width - 32, 1)];
        separator.backgroundColor = [UIColor separatorColor];
        separator.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [containerView addSubview:separator];
        
        PXLog(@"[AppVersionSpoofing] Cell configured with version: %@, date: %@, compatibility: %@", 
              versionLabel.text, dateLabel.text, compatibilityLabel.text);

        // --- Add [use version info] Button ---
        UIButton *useVersionInfoButton = [UIButton buttonWithType:UIButtonTypeSystem];
        useVersionInfoButton.frame = CGRectMake(containerView.bounds.size.width - 174, 40, 74, 28); // 84px left of Install
        useVersionInfoButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [useVersionInfoButton setTitle:@"[use version info]" forState:UIControlStateNormal];
        useVersionInfoButton.backgroundColor = [UIColor systemGrayColor];
        [useVersionInfoButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        useVersionInfoButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        useVersionInfoButton.layer.cornerRadius = 8;
        useVersionInfoButton.tag = indexPath.row;
        [useVersionInfoButton addTarget:self action:@selector(useVersionInfoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [containerView addSubview:useVersionInfoButton];

        // --- Add Install Button ---
        UIButton *installButton = [UIButton buttonWithType:UIButtonTypeSystem];
        installButton.frame = CGRectMake(containerView.bounds.size.width - 90, 40, 74, 28);
        installButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [installButton setTitle:@"Install" forState:UIControlStateNormal];
        installButton.backgroundColor = [UIColor systemBlueColor];
        [installButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        installButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        installButton.layer.cornerRadius = 8;
        installButton.tag = indexPath.row;
        [installButton addTarget:self action:@selector(installButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [containerView addSubview:installButton];
    }
    
    return cell;
}

// Update the table view delegate to set the row height
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 76;
}

// Add this method to ensure proper cell spacing

// Action for [use version info] button
- (void)useVersionInfoButtonTapped:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row < self.filteredVersions.count) {
        NSDictionary *verDict = self.filteredVersions[row];
        NSString *ver = verDict[@"version"];
        NSString *build = verDict[@"build"];
        
        if (!ver || ![ver isKindOfClass:[NSString class]] || ver.length == 0) {
            PXLog(@"[AppVersionSpoofing] Invalid version data in [use version info] button");
            [self showErrorAlert:@"Invalid version data. Please try again."];
            return;
        }
        
        if (!self.selectedBundleID || ![self.selectedBundleID isKindOfClass:[NSString class]] || self.selectedBundleID.length == 0) {
            PXLog(@"[AppVersionSpoofing] No bundleID selected for version spoofing");
            [self showErrorAlert:@"No app selected. Please try again."];
            return;
        }
        
        [self setSpoofedVersion:ver build:build forBundleID:self.selectedBundleID reload:YES];
        [self closeVersionsPopup];
    }
}

- (void)installButtonTapped:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row < self.filteredVersions.count) {
        NSDictionary *verDict = self.filteredVersions[row];
        NSString *ver = verDict[@"version"];
        // build is not used, so do not assign it to avoid unused variable warning
        if (!ver || ![ver isKindOfClass:[NSString class]] || ver.length == 0) {
            PXLog(@"[AppVersionSpoofing] Invalid version data in install button");
            [self showErrorAlert:@"Invalid version data. Please try again."];
            return;
        }
        if (!self.selectedBundleID || ![self.selectedBundleID isKindOfClass:[NSString class]] || self.selectedBundleID.length == 0) {
            PXLog(@"[AppVersionSpoofing] No bundleID selected for install");
            [self showErrorAlert:@"No app selected. Please try again."];
            return;
        }
        // Present DownloadResourcesViewController modally
        PXLog(@"[AppVersionSpoofing] Attempting to present DownloadResourcesViewController");
        Class downloadVCClass = NSClassFromString(@"DownloadResourcesViewController");
        if (downloadVCClass) {
            PXLog(@"[AppVersionSpoofing] DownloadResourcesViewController class found: %@", downloadVCClass);
            UIViewController *downloadVC = [[downloadVCClass alloc] init];
            UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:downloadVC];
            navVC.modalPresentationStyle = UIModalPresentationFormSheet;
            void (^presentBlock)(void) = ^{
                PXLog(@"[AppVersionSpoofing] Presenting DownloadResourcesViewController inside UINavigationController");
                [self presentViewController:navVC animated:YES completion:^{
                    PXLog(@"[AppVersionSpoofing] DownloadResourcesViewController has been presented");
                }];
            };
            if (self.presentedViewController) {
                PXLog(@"[AppVersionSpoofing] Dismissing currently presented view controller before presenting DownloadResourcesViewController");
                [self dismissViewControllerAnimated:YES completion:presentBlock];
            } else {
                presentBlock();
            }
        } else {
            PXLog(@"[AppVersionSpoofing] DownloadResourcesViewController class not found");
            [self showErrorAlert:@"Unable to open Download Resources page."];
        }
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 0.1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.1;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row < self.filteredVersions.count) {
        NSDictionary *verDict = self.filteredVersions[indexPath.row];
        NSString *ver = verDict[@"version"];
        NSString *build = verDict[@"build"];
        
        if (!ver || ![ver isKindOfClass:[NSString class]] || ver.length == 0) {
            PXLog(@"[AppVersionSpoofing] Invalid version data in selected row");
            [self showErrorAlert:@"Invalid version data. Please try again."];
            return;
        }
        
        if (!self.selectedBundleID || ![self.selectedBundleID isKindOfClass:[NSString class]] || self.selectedBundleID.length == 0) {
            PXLog(@"[AppVersionSpoofing] No bundleID selected for version spoofing");
            [self showErrorAlert:@"No app selected. Please try again."];
            return;
        }
        
        [self setSpoofedVersion:ver build:build forBundleID:self.selectedBundleID reload:YES];
        [self closeVersionsPopup];
    } else {
        PXLog(@"[AppVersionSpoofing] Selected row index out of bounds: %ld", (long)indexPath.row);
    }
}

#pragma mark - UISearchBarDelegate
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredVersions = self.appVersions;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *ver, NSDictionary *bindings) {
            return [ver[@"version"] containsString:searchText] || [ver[@"releaseDate"] containsString:searchText];
        }];
        self.filteredVersions = [self.appVersions filteredArrayUsingPredicate:predicate];
    }
    [self.versionsTableView reloadData];
}


// Helper to set spoofed version/build and persist
- (void)setSpoofedVersion:(NSString *)version build:(NSString *)build forBundleID:(NSString *)bundleID reload:(BOOL)reload {
    if (!bundleID || ![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
        PXLog(@"[AppVersionSpoofing] Attempted to set spoofed version with invalid bundleID");
        [self showErrorAlert:@"Invalid app identifier. Please try again."];
        return;
    }
    
    // Get existing app info or create new dictionary
    id existingAppInfo = self.appsData[bundleID];
    NSMutableDictionary *appInfo = nil;
    
    if ([existingAppInfo isKindOfClass:[NSDictionary class]]) {
        appInfo = [existingAppInfo mutableCopy];
    } else {
        PXLog(@"[AppVersionSpoofing] Creating new app info dictionary for %@", bundleID);
        appInfo = [NSMutableDictionary dictionary];
    }
    
    // Update version and build if provided
    if (version && [version isKindOfClass:[NSString class]] && version.length > 0) {
        appInfo[@"spoofedVersion"] = version;
    }
    
    if (build && [build isKindOfClass:[NSString class]] && build.length > 0) {
        appInfo[@"spoofedBuild"] = build;
    }
    
    // Make sure spoofing is enabled when version is set - global setting only
    appInfo[@"spoofingEnabled"] = @YES;
    
    // Update apps data
    self.appsData[bundleID] = appInfo;
    
    // Save to profile-specific file directly - only store version data, not toggle state
    NSString *profileVersionFile = nil;
    
    // Get the active profile ID for direct profile storage
    NSString *profileId = nil;
    
    // Try to get from IdentifierManager if available
    Class idManagerClass = NSClassFromString(@"IdentifierManager");
    if (idManagerClass && [idManagerClass respondsToSelector:@selector(sharedManager)]) {
        id idManager = [idManagerClass performSelector:@selector(sharedManager)];
        if ([idManager respondsToSelector:@selector(getActiveProfileId)]) {
            profileId = [idManager performSelector:@selector(getActiveProfileId)];
        }
    }
    
    if (profileId) {
        // Build the path to this profile's app versions directory
        NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
        NSString *appVersionsDir = [profileDir stringByAppendingPathComponent:@"app_versions"];
        
        // Create the directory if it doesn't exist
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:appVersionsDir]) {
            NSDictionary *attributes = @{NSFilePosixPermissions: @0755,
                                      NSFileOwnerAccountName: @"mobile"};
            
            NSError *dirError = nil;
            if ([fileManager createDirectoryAtPath:appVersionsDir 
                        withIntermediateDirectories:YES 
                                         attributes:attributes
                                              error:&dirError]) {
                // Directory created successfully
                profileVersionFile = [appVersionsDir stringByAppendingPathComponent:
                                     [[bundleID stringByReplacingOccurrencesOfString:@"." withString:@"_"] 
                                      stringByAppendingString:@"_version.plist"]];
            } else {
                PXLog(@"[AppVersionSpoofing] Error creating app versions directory: %@", dirError);
            }
        } else {
            // Directory already exists
            profileVersionFile = [appVersionsDir stringByAppendingPathComponent:
                                 [[bundleID stringByReplacingOccurrencesOfString:@"." withString:@"_"] 
                                  stringByAppendingString:@"_version.plist"]];
        }
        
        if (profileVersionFile) {
            // Create the app version data dictionary for profile file - version data only
            NSMutableDictionary *appVersionData = [NSMutableDictionary dictionary];
            appVersionData[@"bundleID"] = bundleID;
            appVersionData[@"name"] = appInfo[@"name"] ?: bundleID;
            
            if (version && [version isKindOfClass:[NSString class]] && version.length > 0) {
                appVersionData[@"spoofedVersion"] = version;
            }
            
            if (build && [build isKindOfClass:[NSString class]] && build.length > 0) {
                appVersionData[@"spoofedBuild"] = build;
            }
            
            // NEVER save spoofingEnabled to profile file - that belongs in global plist only
            
            if (appInfo[@"activeVersionIndex"]) {
                appVersionData[@"activeVersionIndex"] = appInfo[@"activeVersionIndex"];
            }
            appVersionData[@"lastUpdated"] = [NSDate date];
            
            // Save to profile-specific file
            BOOL success = [appVersionData writeToFile:profileVersionFile atomically:YES];
            if (success) {
                PXLog(@"[AppVersionSpoofing] Successfully saved version data to profile-specific file for %@", bundleID);
            } else {
                PXLog(@"[AppVersionSpoofing] Failed to save to profile-specific file for %@", bundleID);
            }
        }
    }
    
    // We should also update the toggle state in the global plist
    [self persistSpoofingToggleForBundleID:bundleID enabled:YES];
    
    // Also update any global settings if needed
    [self performSelector:@selector(saveAppsData) withObject:nil afterDelay:0.1];
    
    // Post notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.appVersionDataChanged" object:nil];
    
    // Reload UI if requested
    if (reload) {
        [self.collectionView reloadData];
    }
}

// Manual spoof entry prompt
- (void)promptManualSpoofForBundleID:(NSString *)bundleID {
    if (!bundleID || ![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
        PXLog(@"[AppVersionSpoofing] Attempted manual spoof with nil bundleID");
        [self showErrorAlert:@"No app selected. Please try again." ];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Manual Spoof" message:@"Enter version and build to spoof." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Version";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Build (optional)";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *version = alert.textFields[0].text;
        NSString *build = alert.textFields[1].text;
        [self setSpoofedVersion:version build:build forBundleID:bundleID reload:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Handle toggle switch
- (void)toggleSpoofingSwitch:(UISwitch *)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger idx = sender.tag;
        if (idx < 0 || idx >= self.appsData.allKeys.count) {
            PXLog(@"[AppVersionSpoofing] Invalid index for toggle: %ld", (long)idx);
            return;
        }
        NSString *bundleID = self.appsData.allKeys[idx];
        if (!bundleID || ![bundleID isKindOfClass:[NSString class]]) {
            PXLog(@"[AppVersionSpoofing] Invalid bundleID for toggle");
            return;
        }
        id appInfoObj = self.appsData[bundleID];
        NSMutableDictionary *appInfo = nil;
        if ([appInfoObj isKindOfClass:[NSDictionary class]]) {
            appInfo = [[appInfoObj mutableCopy] ?: [NSMutableDictionary dictionary] mutableCopy];
        } else {
            PXLog(@"[AppVersionSpoofing] appInfo for %@ is not NSDictionary, resetting.", bundleID);
            appInfo = [NSMutableDictionary dictionary];
        }
        appInfo[@"spoofingEnabled"] = @(sender.isOn);
        self.appsData[bundleID] = appInfo;
        PXLog(@"[AppVersionSpoofing] Toggle spoofing for %@: %d", bundleID, sender.isOn);
        [self saveAppsData];
        // Also update in version spoofing plist immediately for persistence
        [self persistSpoofingToggleForBundleID:bundleID enabled:sender.isOn];
    });
}



- (void)editAppButtonTapped:(UIButton *)sender {
    PXLog(@"[AppVersionSpoofing] Edit button tapped for index: %ld", (long)sender.tag);
    
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.appsData.allKeys.count) {
        PXLog(@"[AppVersionSpoofing] Invalid index for edit: %ld", (long)index);
        return;
    }
    
    NSString *bundleID = self.appsData.allKeys[index];
    NSDictionary *appInfo = self.appsData[bundleID];
    
    // Create and navigate to version management view controller
    VersionManagementViewController *versionVC = [[VersionManagementViewController alloc] initWithBundleID:bundleID appInfo:appInfo];
    versionVC.delegate = self;
    versionVC.title = [NSString stringWithFormat:@"%@ Versions", appInfo[@"name"] ?: @"App"];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:versionVC];
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    // Remove the automatic edit action on cell tap
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

// Persist spoofing toggle state to version spoofing plist for a single app
- (void)persistSpoofingToggleForBundleID:(NSString *)bundleID enabled:(BOOL)enabled {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Only use global storage for toggle state, never profile-specific
        
        // Try rootless path first
        NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
        NSString *versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:prefsPath]) {
            prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
            versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
            if (![fileManager fileExistsAtPath:prefsPath]) {
                prefsPath = @"/var/mobile/Library/Preferences";
                versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
            }
        }
        
        NSMutableDictionary *versionSpoofDict = [NSMutableDictionary dictionaryWithContentsOfFile:versionSpoofFile];
        if (!versionSpoofDict || ![versionSpoofDict isKindOfClass:[NSDictionary class]]) {
            PXLog(@"[AppVersionSpoofing] versionSpoofDict is nil or invalid, starting new dictionary");
            versionSpoofDict = [NSMutableDictionary dictionary];
        }
        
        NSMutableDictionary *spoofedVersions = [versionSpoofDict[@"SpoofedVersions"] mutableCopy];
        if (!spoofedVersions || ![spoofedVersions isKindOfClass:[NSDictionary class]]) {
            PXLog(@"[AppVersionSpoofing] spoofedVersions is nil or invalid, starting new dictionary");
            spoofedVersions = [NSMutableDictionary dictionary];
        }
        
        NSMutableDictionary *spoofInfo = [spoofedVersions[bundleID] mutableCopy];
        if (!spoofInfo || ![spoofInfo isKindOfClass:[NSDictionary class]]) {
            spoofInfo = [NSMutableDictionary dictionary];
        }
        
        // Update toggle state
        spoofInfo[@"spoofingEnabled"] = @(enabled);
        
        // If we have additional information in memory, add it
        NSDictionary *appInfo = self.appsData[bundleID];
        if (appInfo) {
            spoofInfo[@"name"] = appInfo[@"name"] ?: bundleID;
            if (appInfo[@"version"]) {
                spoofInfo[@"version"] = appInfo[@"version"];
            }
            if (appInfo[@"spoofedVersion"]) {
                spoofInfo[@"spoofedVersion"] = appInfo[@"spoofedVersion"];
            }
            if (appInfo[@"spoofedBuild"]) {
                spoofInfo[@"spoofedBuild"] = appInfo[@"spoofedBuild"];
            }
        }
        
        spoofedVersions[bundleID] = spoofInfo;
        versionSpoofDict[@"SpoofedVersions"] = spoofedVersions;
        versionSpoofDict[@"LastUpdated"] = [NSDate date];
        
        // Save to global file
        BOOL success = [versionSpoofDict writeToFile:versionSpoofFile atomically:YES];
        if (success) {
            PXLog(@"[AppVersionSpoofing] Successfully saved toggle state to global file for %@", bundleID);
        } else {
            PXLog(@"[AppVersionSpoofing] Failed to save toggle state to global file for %@", bundleID);
        }
        
        // Post notification
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.appVersionDataChanged" object:nil];
    });
}

- (void)dealloc {
    // Cancel any ongoing network requests
    [self.currentVersionTask cancel];
    self.currentVersionTask = nil;
}

// Add this method to handle App Store Connect API authentication
- (NSString *)generateJWTToken {
    // These values should be stored securely and retrieved from your secure storage
    NSString *keyId = self.appStoreConnectKeyId;
    NSString *issuerId = self.appStoreConnectIssuerId;
    NSString *privateKey = self.appStoreConnectKey;
    
    if (!keyId || !issuerId || !privateKey) {
        PXLog(@"[AppVersionSpoofing] Missing App Store Connect API credentials");
        return nil;
    }
    
    // Create JWT header
    NSDictionary *header = @{
        @"alg": @"ES256",
        @"kid": keyId,
        @"typ": @"JWT"
    };
    
    // Create JWT payload
    NSDate *now = [NSDate date];
    NSDate *expirationDate = [now dateByAddingTimeInterval:1200]; // 20 minutes expiration
    
    NSDictionary *payload = @{
        @"iss": issuerId,
        @"exp": @([expirationDate timeIntervalSince1970]),
        @"aud": @"appstoreconnect-v1"
    };
    
    // Encode header and payload
    NSString *headerBase64 = [[NSJSONSerialization dataWithJSONObject:header options:0 error:nil] base64EncodedStringWithOptions:0];
    NSString *payloadBase64 = [[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil] base64EncodedStringWithOptions:0];
    
    // Create JWT string
    NSString *jwtString = [NSString stringWithFormat:@"%@.%@", headerBase64, payloadBase64];
    
    // Sign JWT with private key
    // Note: This is a placeholder. You'll need to implement proper ES256 signing
    // using your private key
    
    return jwtString;
}

// Add new method to fetch build information
- (void)fetchBuildInfoForVersion:(NSString *)version appId:(NSString *)appId completion:(void (^)(NSString *buildNumber))completion {
    if (!version || !appId) {
        if (completion) completion(nil);
        return;
    }
    
    NSString *buildInfoUrlString = [NSString stringWithFormat:@"https://apis.bilin.eu.org/build/%@/%@", appId, version];
    NSURL *buildInfoUrl = [NSURL URLWithString:buildInfoUrlString];
    
    if (!buildInfoUrl) {
        if (completion) completion(nil);
        return;
    }
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:buildInfoUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil);
            });
            return;
        }
        
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil);
            });
        return;
    }
    
        NSString *buildNumber = json[@"build"];
        if (!buildNumber || buildNumber.length == 0) {
            buildNumber = json[@"build_number"];
    }
    
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(buildNumber);
        });
    }];
    [task resume];
}

#pragma mark - VersionManagementViewControllerDelegate

- (void)versionManagementDidUpdateVersions {
    PXLog(@"[AppVersionSpoofing] Versions were updated from version management screen");
    // Reload the app data and refresh the UI
    [self loadAppsData];
    [self.collectionView reloadData];
}

// Add back these essential methods that are still needed
- (void)saveMultiVersionData {
    dispatch_async(dispatch_get_main_queue(), ^{
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
                PXLog(@"[AppVersionSpoofing] Failed to create preferences directory: %@", error.localizedDescription);
                return;
            }
        }
        
        // Create multi-version dictionary
        NSDictionary *multiVersionDict = @{
            @"MultiVersions": self.multiVersionData,
            @"LastUpdated": [NSDate date]
        };
        
        // Save to file
        BOOL success = [multiVersionDict writeToFile:multiVersionFile atomically:YES];
        
        if (success) {
            PXLog(@"[AppVersionSpoofing] Successfully saved multi-version data to: %@", multiVersionFile);
            // Post notification about the setting change
            [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.appVersionDataChanged" 
                                                                object:nil];
        } else {
            PXLog(@"[AppVersionSpoofing] Failed to save multi-version data");
        }
    });
}

- (void)saveAppsData {
    dispatch_async(dispatch_get_main_queue(), ^{
        // First save version/build data to profile-specific files (but NOT toggle state)
        NSMutableArray *bundlesWithProfileStorage = [NSMutableArray array];
        
        // For each app in appsData, try to save version/build to a profile-specific file
        for (NSString *bundleID in self.appsData) {
            id appInfoObj = self.appsData[bundleID];
            NSDictionary *appInfo = ([appInfoObj isKindOfClass:[NSDictionary class]]) ? appInfoObj : nil;
            if (!appInfo) {
                PXLog(@"[AppVersionSpoofing] Skipping invalid appInfo for %@", bundleID);
                continue;
            }
            
            // Extract version data for this app
            NSString *spoofedVersion = appInfo[@"spoofedVersion"];
            NSString *spoofedBuild = appInfo[@"spoofedBuild"];
            NSNumber *activeVersionIndex = appInfo[@"activeVersionIndex"];
            
            // Only proceed if there's actual version data to save (not toggle state)
            if ((spoofedVersion.length > 0) || (spoofedBuild.length > 0) || (activeVersionIndex != nil)) {
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
                
                // If we have a profile ID, proceed with profile-specific storage
                if (profileId) {
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
                            PXLog(@"[AppVersionSpoofing] Error creating app versions directory: %@", dirError);
                            continue;
                        }
                    }
                    
                    // Create a safe filename from the bundle ID
                    NSString *safeFilename = [bundleID stringByReplacingOccurrencesOfString:@"." withString:@"_"];
                    safeFilename = [safeFilename stringByAppendingString:@"_version.plist"];
                    
                    NSString *appVersionFile = [appVersionsDir stringByAppendingPathComponent:safeFilename];
                    
                    // Get existing data from file or create new dictionary
                    NSMutableDictionary *appVersionData = [[NSDictionary dictionaryWithContentsOfFile:appVersionFile] mutableCopy];
                    if (!appVersionData) {
                        appVersionData = [NSMutableDictionary dictionary];
                    }
                    
                    // Update version data (but not toggle state)
                    appVersionData[@"bundleID"] = bundleID;
                    appVersionData[@"name"] = appInfo[@"name"] ?: bundleID;
                    
                    if (spoofedVersion.length > 0) {
                        appVersionData[@"spoofedVersion"] = spoofedVersion;
                    }
                    if (spoofedBuild.length > 0) {
                        appVersionData[@"spoofedBuild"] = spoofedBuild;
                    }
                    
                    // IMPORTANT: NEVER save spoofingEnabled to profile file
                    // Remove it if it exists from previous versions
                    [appVersionData removeObjectForKey:@"spoofingEnabled"];
                    
                    if (activeVersionIndex != nil) {
                        appVersionData[@"activeVersionIndex"] = activeVersionIndex;
                    }
                    appVersionData[@"lastUpdated"] = [NSDate date];
                    
                    // Save to profile-specific file
                    BOOL success = [appVersionData writeToFile:appVersionFile atomically:YES];
                    if (success) {
                        PXLog(@"[AppVersionSpoofing] Successfully saved version data to profile-specific file for %@", bundleID);
                        [bundlesWithProfileStorage addObject:bundleID];
                    } else {
                        PXLog(@"[AppVersionSpoofing] Failed to save to profile-specific file for %@", bundleID);
                    }
                }
            }
        }
        
        // Now handle the global storage for all apps' toggle state
        // Try rootless path first
        NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
        NSString *versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
        
        // Fallback to standard path if rootless path doesn't exist
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:prefsPath]) {
            // Try Dopamine 2 path
            prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
            versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
            
            // Fallback to standard path if needed
            if (![fileManager fileExistsAtPath:prefsPath]) {
                prefsPath = @"/var/mobile/Library/Preferences";
                versionSpoofFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.version_spoof.plist"];
            }
        }
        
        // Create directory if it doesn't exist
        if (![fileManager fileExistsAtPath:prefsPath]) {
            NSError *error = nil;
            [fileManager createDirectoryAtPath:prefsPath withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                PXLog(@"[AppVersionSpoofing] Failed to create preferences directory: %@", error.localizedDescription);
                return;
            }
        }
        
        // Load existing global file
        NSMutableDictionary *versionSpoofDict = [[NSDictionary dictionaryWithContentsOfFile:versionSpoofFile] mutableCopy];
        if (!versionSpoofDict) {
            versionSpoofDict = [NSMutableDictionary dictionary];
        }
        
        NSMutableDictionary *spoofedVersions = [versionSpoofDict[@"SpoofedVersions"] mutableCopy];
        if (!spoofedVersions) {
            spoofedVersions = [NSMutableDictionary dictionary];
        }
        
        // Update global dictionary with all apps' data, focusing on toggle state
        for (NSString *bundleID in self.appsData) {
            id appInfoObj = self.appsData[bundleID];
            NSDictionary *appInfo = ([appInfoObj isKindOfClass:[NSDictionary class]]) ? appInfoObj : nil;
            if (!appInfo) {
                PXLog(@"[AppVersionSpoofing] Skipping invalid appInfo for %@", bundleID);
                continue;
            }
            
            // Get or create the spoof info dictionary
            NSMutableDictionary *spoofInfo = [spoofedVersions[bundleID] mutableCopy];
            if (!spoofInfo) {
                spoofInfo = [NSMutableDictionary dictionary];
            }
            
            // Always save the toggle state
            spoofInfo[@"spoofingEnabled"] = appInfo[@"spoofingEnabled"] ?: @NO;
            
            // Also include other metadata for completeness
            spoofInfo[@"name"] = appInfo[@"name"] ?: bundleID;
            spoofInfo[@"bundleID"] = bundleID;
            spoofInfo[@"version"] = appInfo[@"version"] ?: @"Unknown";
            
            // Include version/build info as reference (but primary storage is profile files)
            if (appInfo[@"spoofedVersion"]) {
                spoofInfo[@"spoofedVersion"] = appInfo[@"spoofedVersion"];
            }
            if (appInfo[@"spoofedBuild"]) {
                spoofInfo[@"spoofedBuild"] = appInfo[@"spoofedBuild"];
            }
            if (appInfo[@"activeVersionIndex"]) {
                spoofInfo[@"activeVersionIndex"] = appInfo[@"activeVersionIndex"];
            }
            
            // Include multi-version reference
            NSArray *multiVersions = self.multiVersionData[bundleID];
            if (multiVersions && multiVersions.count > 0) {
                spoofInfo[@"hasMultipleVersions"] = @YES;
                spoofInfo[@"versionCount"] = @(multiVersions.count);
            }
            
            spoofedVersions[bundleID] = spoofInfo;
        }
        
        // Update and save the global dictionary
        versionSpoofDict[@"SpoofedVersions"] = spoofedVersions;
        versionSpoofDict[@"LastUpdated"] = [NSDate date];
        
        // Save to global file
        BOOL success = [versionSpoofDict writeToFile:versionSpoofFile atomically:YES];
        
        if (success || bundlesWithProfileStorage.count > 0) {
            PXLog(@"[AppVersionSpoofing] Successfully saved app version data. Toggle states in global file, version info in %lu profile-specific files", 
                  (unsigned long)bundlesWithProfileStorage.count);
            
            // Post notification about the setting change
            [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.appVersionDataChanged" 
                                                                object:nil];
        } else {
            PXLog(@"[AppVersionSpoofing] Failed to save app version spoofing data");
            // Show error alert
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:@"Failed to save settings. Please check permissions."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

@end