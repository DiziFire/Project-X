#import "ProjectX.h"
#import "IdentifierManager.h"
#import "UptimeManager.h"
#import "CopyHelper.h"
#import "BottomButtons.h"
#import "AccountViewController.h"
#import "FreezeManager.h"
#import "AppDataCleaner.h"
#import "AppVersionManager.h"
#import "APIManager.h"
#import "TokenManager.h"
#import "APIManagerPlanExtensions.h"
#import "ProfileButtonsView.h"
#import "ProfileManagerViewController.h"
#import "ProfileCreationViewController.h"
#import "ProfileManager.h"
#import "StorageManager.h"
#import "BatteryManager.h"
#import "AppDataBackupRestoreViewController.h"
#import "ToolViewController.h"
#import "FilesViewController.h"
#import <UIKit/UIKit.h>
#import "ProgressHUDView.h"
#import <spawn.h>
#import <sys/wait.h>
#import <dlfcn.h>
#import <objc/runtime.h>

// Add missing methods via category
@interface LSApplicationWorkspace (ProjectX)
- (NSArray *)allInstalledApplications;
@end

// Add missing properties via category
@interface LSApplicationProxy (ProjectX)
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSString *buildVersionString;  // Add this line to get build number
@end

@interface ProjectXViewController () <UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIScrollViewDelegate, ProfileCreationViewControllerDelegate>
@property (nonatomic, strong) ProgressHUDView *progressHUD;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStackView;
@property (nonatomic, strong) UIStackView *appsStackView;
@property (nonatomic, strong) UITextField *bundleIDTextField;
@property (nonatomic, strong) FreezeManager *freezeManager;
@property (nonatomic, strong) NSMutableDictionary *appSwitches;
@property (nonatomic, strong) NSMutableDictionary *identifierSwitches;
@property (nonatomic, strong) UITableView *appsTableView;
@property (nonatomic, strong) UIViewController *installedAppsPopupVC;
@property (nonatomic, strong) UITableView *installedAppsTableView;
@property (nonatomic, strong) UISearchBar *appSearchBar;
@property (nonatomic, strong) NSArray *installedApps;
@property (nonatomic, strong) NSArray *filteredApps;
@property (nonatomic, strong) UIViewController *versionsPopupVC;
@property (nonatomic, strong) UITableView *versionsTableView;
@property (nonatomic, strong) NSArray *appVersions;
@property (nonatomic, strong) NSString *selectedBundleID;
@property (nonatomic, strong) UISearchBar *versionSearchBar;
@property (nonatomic, strong) NSArray *filteredVersions;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSCache *iconCache;
@property (nonatomic, strong) NSArray *scopedApps;
@property (nonatomic, strong) UIButton *scrollToBottomButton;

// Trial offer banner properties
@property (nonatomic, strong) UIView *trialOfferBannerView;
@property (nonatomic, strong) UIButton *getTrialButton;
@property (nonatomic, assign) BOOL hasShownTrialOffer;
@property (nonatomic, assign) BOOL hasPlan;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

// Method declarations
- (void)showError:(NSError *)error;
- (void)killEnabledAppsAndRespring;
- (void)loadSettings;
- (void)setupUI;
- (void)addIdentifierSection:(NSString *)type title:(NSString *)title;
- (void)addAppManagementSection;
- (UIView *)createSectionHeaderWithTitle:(NSString *)title;
- (void)updateAppsList;
- (instancetype)init;
- (void)fetchAppIconForBundleID:(NSString *)bundleID completion:(void (^)(UIImage *icon))completion;
- (UIImage *)createNotInAppStoreImage;
- (void)installAppWithAdamId:(NSString *)adamId appExtVrsId:(NSString *)appExtVrsId bundleID:(NSString *)bundleID appName:(NSString *)appName version:(NSString *)version;

// Add this new method to directly update identifier values
- (void)directUpdateIdentifierValue:(NSString *)identifierType withValue:(NSString *)value;

// Trial offer banner methods
- (void)setupTrialOfferBanner;
- (BOOL)checkTrialOfferEligibility;
- (void)getTrialButtonTapped;
- (BOOL)shouldShowTrialOffer;
- (void)hideTrialOfferBanner;

// Helper methods for finding view controllers
- (UIViewController *)findTopViewController;
- (UITabBarController *)findTabBarController;

@property (nonatomic, strong) ProfileButtonsView *profileButtonsView;
@property (nonatomic, strong) NSMutableArray *profiles;

// Profile Management Methods
- (void)setupProfileButtons;
- (void)setupProfileManagement;
- (void)showProfileCreation;
- (void)showProfileManager;

// Profile Indicator
@property (nonatomic, strong) UIView *profileIndicatorView;

// Add helper methods for finding buttons by tag
- (UIButton *)buttonWithTag:(NSInteger)tag;
- (NSArray *)findSubviewsOfClass:(Class)cls inView:(UIView *)view;

- (void)addApplicationWithExtensionsToScope:(NSString *)bundleID;

// Add loadScopedApps method
- (void)loadScopedApps;

// Add property to track advanced identifiers visibility in the @interface section
@property (nonatomic, assign) BOOL showAdvancedIdentifiers;
@property (nonatomic, strong) UIButton *showAdvancedButton;
@property (nonatomic, strong) NSMutableArray *advancedIdentifierViews;

// Modify setupUI method to add a "Show Advanced" button and initially hide the advanced identifier sections
- (void)setupUI;

// Add methods for the show advanced button and advanced identifier sections
- (void)addShowAdvancedButton;

// Add a version of addIdentifierSection that adds to our tracking array and hides them initially
- (void)addAdvancedIdentifierSection:(NSString *)type title:(NSString *)title;

// Handle toggle of advanced identifiers
- (void)toggleAdvancedIdentifiers:(UIButton *)sender;
@end

@implementation ProjectXViewController

- (void)floatingScrollButtonTapped:(UIButton *)sender {
    CGFloat y = self.scrollView.contentOffset.y;
    CGFloat maxY = self.scrollView.contentSize.height - self.scrollView.bounds.size.height;
    if (maxY <= 0) return;
    if (y <= maxY * 0.20) {
        // Scroll to bottom
        CGFloat bottomOffset = self.scrollView.contentSize.height - self.scrollView.bounds.size.height + self.scrollView.contentInset.bottom;
        if (bottomOffset > 0) {
            [self.scrollView setContentOffset:CGPointMake(0, bottomOffset) animated:YES];
        }
    } else if (y >= maxY * 0.80) {
        // Scroll to top
        [self.scrollView setContentOffset:CGPointZero animated:YES];
    }
    // Hide the button after tap
    [UIView animateWithDuration:0.2 animations:^{
        self.scrollToBottomButton.alpha = 0.0;
    }];
}

// Show/hide scrollToBottomButton based on scroll position
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat y = scrollView.contentOffset.y;
    CGFloat maxY = scrollView.contentSize.height - scrollView.bounds.size.height;
    if (maxY <= 0) {
        self.scrollToBottomButton.alpha = 0.0;
        return;
    }
    UIImage *downArrow = [[UIImage systemImageNamed:@"arrow.down"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage *upArrow = [[UIImage systemImageNamed:@"arrow.up"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (y <= maxY * 0.20) {
        // Top 20%: show button to scroll to bottom
        [self.scrollToBottomButton setImage:downArrow forState:UIControlStateNormal];
        self.scrollToBottomButton.accessibilityLabel = @"Scroll to bottom";
        [self.scrollToBottomButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.scrollToBottomButton addTarget:self action:@selector(floatingScrollButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 1.0;
        }];
    } else if (y >= maxY * 0.80) {
        // Bottom 20%: show button to scroll to top
        [self.scrollToBottomButton setImage:upArrow forState:UIControlStateNormal];
        self.scrollToBottomButton.accessibilityLabel = @"Scroll to top";
        [self.scrollToBottomButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [self.scrollToBottomButton addTarget:self action:@selector(floatingScrollButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 1.0;
        }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.scrollToBottomButton.alpha = 0.0;
        }];
    }
}

#pragma mark - Helper Methods

// Helper method to find top view controller without using keyWindow
- (UIViewController *)findTopViewController {
    UIViewController *rootVC = nil;
    
    // Get the key window using the modern approach for iOS 13+
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        rootVC = window.rootViewController;
                        break;
                    }
                }
                if (rootVC) break;
            }
        }
        
        // Fallback if we couldn't find the key window
        if (!rootVC) {
            UIWindowScene *windowScene = (UIWindowScene *)[connectedScenes anyObject];
            rootVC = windowScene.windows.firstObject.rootViewController;
        }
    } else {
        // Fallback for iOS 12 and below (though this is less likely to be used in iOS 15)
        rootVC = [UIApplication sharedApplication].delegate.window.rootViewController;
    }
    
    // Navigate through presented view controllers to find the topmost one
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    return rootVC;
}

- (UIViewController *)findTopViewControllerFromViewController:(UIViewController *)viewController {
    if (viewController.presentedViewController) {
        return [self findTopViewControllerFromViewController:viewController.presentedViewController];
    } else if ([viewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)viewController;
        return [self findTopViewControllerFromViewController:navigationController.topViewController];
    } else if ([viewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)viewController;
        return [self findTopViewControllerFromViewController:tabController.selectedViewController];
    } else {
        return viewController;
    }
}

- (UITabBarController *)findTabBarController {
    UIViewController *rootViewController = [self findTopViewController];
    
    // Check if root is a tab bar controller
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        return (UITabBarController *)rootViewController;
    }
    
    // Check if root is a navigation controller with a tab bar controller
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)rootViewController;
        if ([navController.viewControllers.firstObject isKindOfClass:[UITabBarController class]]) {
            return (UITabBarController *)navController.viewControllers.firstObject;
        }
    }
    
    // Check if tab bar controller is presented
    if ([rootViewController.presentedViewController isKindOfClass:[UITabBarController class]]) {
        return (UITabBarController *)rootViewController.presentedViewController;
    }
    
    return nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.installedAppsTableView) {
        return self.filteredApps.count;
    } else if (tableView == self.versionsTableView) {
        return self.filteredVersions.count;
    }
    return self.appSwitches.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.installedAppsTableView) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InstalledAppCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"InstalledAppCell"];
        }
        
        NSDictionary *app = self.filteredApps[indexPath.row];
        cell.textLabel.text = app[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (v%@)", app[@"bundleID"], app[@"version"]];
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        
        return cell;
    } else if (tableView == self.versionsTableView) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"VersionCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"VersionCell"];
        }
        
        // Clear existing content
        for (UIView *view in cell.contentView.subviews) {
            [view removeFromSuperview];
        }
        
        NSDictionary *version = self.filteredVersions[indexPath.row];
        NSString *releaseDate = version[@"releaseDate"];
        NSString *appName = version[@"appName"];
        
        // Truncate app name to 15 characters
        if (appName.length > 15) {
            appName = [[appName substringToIndex:15] stringByAppendingString:@"..."];
        }
        
        // Format the date for display
        NSString *formattedDate = @"Unknown";
        if (![releaseDate isEqualToString:@"Unknown"]) {
            // Try parsing as ISO 8601 date string first
            NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
            isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
            NSDate *date = [isoFormatter dateFromString:releaseDate];
            
            // If that fails, try parsing as "yyyy-MM-dd HH:mm:ss" format
            if (!date) {
                NSDateFormatter *altFormatter = [[NSDateFormatter alloc] init];
                altFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
                date = [altFormatter dateFromString:releaseDate];
            }
            
            // If that fails, try parsing as timestamp
            if (!date && releaseDate.length > 0) {
                NSTimeInterval timestamp = [releaseDate doubleValue];
                if (timestamp > 0) {
                    date = [NSDate dateWithTimeIntervalSince1970:timestamp];
                }
            }
            
            if (date) {
                if (!self.dateFormatter) {
                    self.dateFormatter = [[NSDateFormatter alloc] init];
                    self.dateFormatter.dateFormat = @"MMM d, yyyy";
                }
                formattedDate = [self.dateFormatter stringFromDate:date];
            }
        }
        
        // Create main content view
        UIView *contentContainer = [[UIView alloc] init];
        contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:contentContainer];
        
        // Version label
        UILabel *versionLabel = [[UILabel alloc] init];
        versionLabel.text = version[@"version"];
        versionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [contentContainer addSubview:versionLabel];
        
        // Date label
        UILabel *dateLabel = [[UILabel alloc] init];
        dateLabel.text = formattedDate;
        dateLabel.font = [UIFont systemFontOfSize:12];
        dateLabel.textColor = [UIColor secondaryLabelColor];
        dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [contentContainer addSubview:dateLabel];
        
        // Install button
        UIButton *installButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [installButton setTitle:[NSString stringWithFormat:@"Install %@", appName] forState:UIControlStateNormal];
        installButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        installButton.tag = indexPath.row;
        [installButton addTarget:self action:@selector(installButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        installButton.translatesAutoresizingMaskIntoConstraints = NO;
        [contentContainer addSubview:installButton];
        
        // Highlight installed version by comparing to installed version from plist
        // --- Begin: Robust installed version fetch (rootless/jailbreak aware, same as AppVersionSpoofingViewController) ---
        NSString *installedVersion = nil;
        NSString *prefsPath = @"/var/jb/var/mobile/Library/Preferences";
        NSString *scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:prefsPath]) {
            // Try Dopamine 2 path
            prefsPath = @"/var/jb/private/var/mobile/Library/Preferences";
            scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
            if (![fileManager fileExistsAtPath:prefsPath]) {
                prefsPath = @"/var/mobile/Library/Preferences";
                scopedAppsFile = [prefsPath stringByAppendingPathComponent:@"com.hydra.projectx.global_scope.plist"];
            }
        }
        NSDictionary *scopedAppsDict = [NSDictionary dictionaryWithContentsOfFile:scopedAppsFile];
        NSDictionary *savedApps = scopedAppsDict[@"ScopedApps"];
        if (savedApps && self.selectedBundleID) {
            NSDictionary *appInfo = savedApps[self.selectedBundleID];
            if ([appInfo isKindOfClass:[NSDictionary class]]) {
                installedVersion = appInfo[@"version"];
            }
        }
        // --- End: Robust installed version fetch ---
        BOOL isHighlighted = (installedVersion && [version[@"version"] isEqualToString:installedVersion]);
        if (isHighlighted) {
            contentContainer.backgroundColor = [UIColor colorWithRed:0.90 green:0.97 blue:1.0 alpha:1.0];
            contentContainer.layer.cornerRadius = 10;
            contentContainer.layer.borderWidth = 1.5;
            contentContainer.layer.borderColor = [UIColor colorWithRed:0.20 green:0.60 blue:1.0 alpha:0.35].CGColor;
            versionLabel.textColor = [UIColor systemBlueColor];
            dateLabel.textColor = [UIColor systemBlueColor];
        } else {
            contentContainer.backgroundColor = [UIColor clearColor];
            contentContainer.layer.cornerRadius = 0;
            contentContainer.layer.borderWidth = 0;
            versionLabel.textColor = [UIColor labelColor];
            dateLabel.textColor = [UIColor secondaryLabelColor];
        }
        
        // Setup constraints
        CGFloat topPad = isHighlighted ? 0 : 8;
        CGFloat leftPad = isHighlighted ? 0 : 16;
        CGFloat rightPad = isHighlighted ? 0 : -16;
        CGFloat bottomPad = isHighlighted ? 0 : -8;
        [NSLayoutConstraint activateConstraints:@[
            // Container constraints
            [contentContainer.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:topPad],
            [contentContainer.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:leftPad],
            [contentContainer.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:rightPad],
            [contentContainer.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:bottomPad],
            
            // Version label constraints
            [versionLabel.topAnchor constraintEqualToAnchor:contentContainer.topAnchor],
            [versionLabel.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor],
            
            // Date label constraints
            [dateLabel.topAnchor constraintEqualToAnchor:versionLabel.bottomAnchor constant:2],
            [dateLabel.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor],
            [dateLabel.bottomAnchor constraintEqualToAnchor:contentContainer.bottomAnchor],
            
            // Install button constraints
            [installButton.centerYAnchor constraintEqualToAnchor:contentContainer.centerYAnchor],
            [installButton.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor],
            [installButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:versionLabel.trailingAnchor constant:8]
        ]];
        
        return cell;
    }
    
    // Return cell for app switches table
    static NSString *cellIdentifier = @"AppCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
        cell.backgroundColor = [UIColor systemBackgroundColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    // Clear existing subviews to prevent stacking
    for (UIView *view in cell.contentView.subviews) {
        [view removeFromSuperview];
    }
    
    NSString *bundleID = self.appSwitches.allKeys[indexPath.row];
    // Use original bundle ID from app info to preserve case
    NSDictionary *appInfo = [self.manager getApplicationInfo:bundleID];
    NSString *displayBundleID = appInfo[@"bundleID"] ?: bundleID;
    
    // Create app view container
    UIView *appView = [[UIView alloc] init];
    appView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    appView.layer.cornerRadius = 8;
    appView.clipsToBounds = YES;
    
    // Create background icon view with blur
    UIImageView *iconBackgroundView = [[UIImageView alloc] init];
    iconBackgroundView.contentMode = UIViewContentModeScaleAspectFit;
    iconBackgroundView.alpha = 0.3; // 30% opacity
    iconBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    [appView addSubview:iconBackgroundView];
    
    // Add blur effect
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.alpha = 0.7; // Adjust blur intensity
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [appView addSubview:blurView];
    
    // Create stack view for app content
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 8;
    contentStack.layoutMargins = UIEdgeInsetsMake(12, 12, 12, 12);
    contentStack.layoutMarginsRelativeArrangement = YES;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [appView addSubview:contentStack];
    
    // Setup constraints for background icon and blur
    [NSLayoutConstraint activateConstraints:@[
        [iconBackgroundView.centerXAnchor constraintEqualToAnchor:appView.centerXAnchor],
        [iconBackgroundView.centerYAnchor constraintEqualToAnchor:appView.centerYAnchor],
        [iconBackgroundView.widthAnchor constraintEqualToAnchor:appView.widthAnchor multiplier:0.3], // Reduced to 30%
        [iconBackgroundView.heightAnchor constraintEqualToAnchor:iconBackgroundView.widthAnchor],
        
        [blurView.topAnchor constraintEqualToAnchor:appView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:appView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:appView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:appView.bottomAnchor],
        
        [contentStack.topAnchor constraintEqualToAnchor:appView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:appView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:appView.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:appView.bottomAnchor]
    ]];
    
    // Fetch and set app icon
    [self fetchAppIconForBundleID:bundleID completion:^(UIImage *icon) {
        iconBackgroundView.image = icon;
    }];
    
    // Create bundle ID with copy button
    UIStackView *bundleStack = [[UIStackView alloc] init];
    bundleStack.axis = UILayoutConstraintAxisHorizontal;
    bundleStack.spacing = 4;  // Reduced spacing
    bundleStack.alignment = UIStackViewAlignmentCenter;
    
    // Add extension button with smaller size
    UIButton *extensionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *plusImage = [[UIImage systemImageNamed:@"plus.circle.fill"] imageWithConfiguration:
                         [UIImageSymbolConfiguration configurationWithPointSize:14.0]];  // Reduced size
    [extensionButton setImage:plusImage forState:UIControlStateNormal];
    extensionButton.tintColor = [UIColor systemBlueColor];
    extensionButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
    [extensionButton addTarget:self action:@selector(extensionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Set fixed size for extension button
    [extensionButton.heightAnchor constraintEqualToConstant:16].active = YES;  // Fixed height
    [extensionButton.widthAnchor constraintEqualToConstant:16].active = YES;   // Fixed width
    extensionButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    
    // Add to stack with no extra padding
    [bundleStack setCustomSpacing:2 afterView:extensionButton];  // Minimal spacing after button
    [bundleStack addArrangedSubview:extensionButton];
    
    UILabel *bundleLabel = [[UILabel alloc] init];
    bundleLabel.text = displayBundleID;
    bundleLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    bundleLabel.numberOfLines = 1;
    bundleLabel.adjustsFontSizeToFitWidth = YES;
    bundleLabel.minimumScaleFactor = 0.75;
    [bundleStack addArrangedSubview:bundleLabel];
    
    UIButton *copyButton = [CopyHelper createCopyButtonWithText:displayBundleID];
    [copyButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [bundleStack addArrangedSubview:copyButton];
    
    [contentStack addArrangedSubview:bundleStack];
    
    // Add app info
    UILabel *infoLabel = [[UILabel alloc] init];
    if ([appInfo[@"installed"] boolValue]) {
        NSString *frozenStatus = [self.freezeManager isApplicationFrozen:bundleID] ? @" [FROZEN]" : @"";
        NSString *infoText = [NSString stringWithFormat:@"%@ - v%@%@", appInfo[@"name"], appInfo[@"version"], frozenStatus];
        
        NSMutableAttributedString *attributedInfoText = [[NSMutableAttributedString alloc] initWithString:infoText];
        if ([self.freezeManager isApplicationFrozen:bundleID]) {
            NSRange frozenRange = [infoText rangeOfString:@"[FROZEN]"];
            [attributedInfoText addAttribute:NSForegroundColorAttributeName value:[UIColor systemBlueColor] range:frozenRange];
        }
        
        infoLabel.attributedText = attributedInfoText;
        infoLabel.textColor = [UIColor labelColor];
    } else {
        infoLabel.text = @"Removed From Scope";
        infoLabel.textColor = [UIColor systemOrangeColor];
    }
    infoLabel.font = [UIFont systemFontOfSize:12];
    [contentStack addArrangedSubview:infoLabel];
    
    // Add delete button with trash icon
    UIStackView *controlStack = [[UIStackView alloc] init];
    controlStack.axis = UILayoutConstraintAxisHorizontal;
    controlStack.alignment = UIStackViewAlignmentCenter;
    controlStack.distribution = UIStackViewDistributionEqualSpacing;
    controlStack.spacing = 8;
    
    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [deleteButton setImage:[UIImage systemImageNamed:@"trash.slash.circle.fill"] forState:UIControlStateNormal];
    [deleteButton setTintColor:[UIColor systemRedColor]];
    deleteButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
    [deleteButton addTarget:self action:@selector(deleteAppButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [controlStack addArrangedSubview:deleteButton];
    
    // Replace freeze button with more options button (ellipsis)
    UIButton *moreOptionsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [moreOptionsButton setImage:[UIImage systemImageNamed:@"ellipsis.circle.fill"] forState:UIControlStateNormal];
    [moreOptionsButton setTintColor:[UIColor systemBlueColor]];
    moreOptionsButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
    [moreOptionsButton addTarget:self action:@selector(moreOptionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [controlStack addArrangedSubview:moreOptionsButton];
    
    // Add clear data button
    UIButton *clearDataButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearDataButton setImage:[UIImage systemImageNamed:@"externaldrive.fill.badge.minus"] forState:UIControlStateNormal];
    [clearDataButton setTintColor:[UIColor systemRedColor]];
    clearDataButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
    [clearDataButton addTarget:self action:@selector(clearDataButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [controlStack addArrangedSubview:clearDataButton];
    
    // Add versions button
    UIButton *versionsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [versionsButton setImage:[UIImage systemImageNamed:@"arrow.up.and.down.circle.fill"] forState:UIControlStateNormal];
    [versionsButton setTintColor:[UIColor systemBlueColor]];
    versionsButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
    [versionsButton addTarget:self action:@selector(versionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [controlStack addArrangedSubview:versionsButton];
    
    // Add switch
    UISwitch *appSwitch = self.appSwitches[bundleID];
    [controlStack addArrangedSubview:appSwitch];
    
    [contentStack addArrangedSubview:controlStack];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:appView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:appView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:appView.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:appView.bottomAnchor]
    ]];
    
    [cell.contentView addSubview:appView];
    
    // Setup constraints for appView
    appView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [appView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [appView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [appView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [appView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor]
    ]];
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (tableView == self.installedAppsTableView) {
        // Restrict adding if user has no plan
        if (![[APIManager sharedManager] userHasPlan]) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Plan Required"
                                                                           message:@"You need an active plan to add apps to scope."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        // Handle installed apps selection
        NSDictionary *selectedApp = self.filteredApps[indexPath.row];
        NSString *bundleID = selectedApp[@"bundleID"];
        
        if (bundleID) {
            // Add the app to scope
            [self.manager addApplicationToScope:bundleID];
            
            // Check for errors
            if ([self.manager lastError]) {
                [self showError:[self.manager lastError]];
                return;
            }
            
            // Refresh UI
            [self loadSettings];
            
            // Dismiss the popup
            [self dismissViewControllerAnimated:YES completion:^{
                // Show success message
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                             message:[NSString stringWithFormat:@"Added %@ to scope", selectedApp[@"name"]]
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleDefault
                                                      handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            }];
        }
    }
    else if (indexPath.section == 0) { // Scoped Apps section
        NSDictionary *appInfo = self.scopedApps[indexPath.row];
        NSString *bundleID = appInfo[@"bundleID"];
        if (bundleID) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Options"
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
            
            UIAlertAction *addWithExtensionsAction = [UIAlertAction actionWithTitle:@"Add with Extensions"
                                                                            style:UIAlertActionStyleDefault
                                                                          handler:^(UIAlertAction * _Nonnull action) {
                if (![[APIManager sharedManager] userHasPlan]) {
                    UIAlertController *planAlert = [UIAlertController alertControllerWithTitle:@"Plan Required"
                                                                                      message:@"You need an active plan to add apps with extensions to scope."
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                    [planAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:planAlert animated:YES completion:nil];
                    return;
                }
                [self addApplicationWithExtensionsToScope:bundleID];
            }];
            
            UIAlertAction *removeAction = [UIAlertAction actionWithTitle:@"Remove from Scope"
                                                                 style:UIAlertActionStyleDestructive
                                                               handler:^(UIAlertAction * _Nonnull action) {
                [[IdentifierManager sharedManager] removeApplicationFromScope:bundleID];
                [self loadScopedApps];
            }];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                                 style:UIAlertActionStyleCancel
                                                               handler:nil];
            
            [alert addAction:addWithExtensionsAction];
            [alert addAction:removeAction];
            [alert addAction:cancelAction];
            
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        self.iconCache = [[NSCache alloc] init];
        self.iconCache.countLimit = 50; // Cache up to 50 icons
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Add iPad-specific layout adaptations
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        // Use regular width size class layout for iPad
        self.view.backgroundColor = [UIColor systemBackgroundColor];
        
        // Create container view for iPad layout
        UIView *containerView = [[UIView alloc] init];
        containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:containerView];
        
        // Center container with max width for iPad
        [NSLayoutConstraint activateConstraints:@[
            [containerView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [containerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [containerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            [containerView.widthAnchor constraintLessThanOrEqualToConstant:768], // iPad-appropriate max width
            [containerView.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-40],
            [containerView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:20],
            [containerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-20]
        ]];
        
        // Move existing content to container
        for (UIView *subview in self.view.subviews) {
            if (subview != containerView) {
                [containerView addSubview:subview];
            }
        }
    }
    
    self.title = @"Project X";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Add Files button to left side of navigation bar
    UIButton *filesButton = [UIButton buttonWithType:UIButtonTypeSystem];
    
    if (@available(iOS 15.0, *)) {
        // Modern button style for iOS 15+
        UIButtonConfiguration *filesConfig = [UIButtonConfiguration plainButtonConfiguration];
        filesConfig.title = @"Files";
        filesConfig.image = [UIImage systemImageNamed:@"arrow.down.circle"];
        filesConfig.imagePlacement = NSDirectionalRectEdgeLeading;
        filesConfig.imagePadding = 4;
        filesConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        filesConfig.baseForegroundColor = [UIColor systemBlueColor];
        filesButton.configuration = filesConfig;
    } else {
        // Fallback for iOS 14 and below without using deprecated properties
        // Create a container view to hold the image and text
        UIView *buttonContentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 30)];
        
        // Add icon image view
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle"]];
        iconImageView.tintColor = [UIColor systemBlueColor];
        iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [buttonContentView addSubview:iconImageView];
        
        // Add text label
        UILabel *textLabel = [[UILabel alloc] init];
        textLabel.text = @"Files";
        textLabel.font = [UIFont systemFontOfSize:16];
        textLabel.textColor = [UIColor systemBlueColor];
        textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [buttonContentView addSubview:textLabel];
        
        // Set up constraints
        [NSLayoutConstraint activateConstraints:@[
            [iconImageView.leadingAnchor constraintEqualToAnchor:buttonContentView.leadingAnchor],
            [iconImageView.centerYAnchor constraintEqualToAnchor:buttonContentView.centerYAnchor],
            [iconImageView.widthAnchor constraintEqualToConstant:20],
            [iconImageView.heightAnchor constraintEqualToConstant:20],
            
            [textLabel.leadingAnchor constraintEqualToAnchor:iconImageView.trailingAnchor constant:4],
            [textLabel.trailingAnchor constraintEqualToAnchor:buttonContentView.trailingAnchor],
            [textLabel.centerYAnchor constraintEqualToAnchor:buttonContentView.centerYAnchor]
        ]];
        
        // Create button with the custom content view
        filesButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [filesButton addTarget:self action:@selector(filesButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        filesButton.frame = buttonContentView.bounds;
        [filesButton addSubview:buttonContentView];
    }
    
    [filesButton addTarget:self action:@selector(filesButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *filesBarButton = [[UIBarButtonItem alloc] initWithCustomView:filesButton];
    self.navigationItem.leftBarButtonItem = filesBarButton;
    
    // Add Tools button to navigation bar (right side)
    UIButton *toolsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [toolsButton setTitle:@"Tools" forState:UIControlStateNormal];
    toolsButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [toolsButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    
    if (@available(iOS 15.0, *)) {
        // Use modern button configuration for iOS 15+
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = @"Tools";
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
            NSMutableDictionary *newAttributes = [attributes mutableCopy];
            newAttributes[NSFontAttributeName] = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
            newAttributes[NSForegroundColorAttributeName] = [UIColor systemBlueColor];
            return newAttributes;
        };
        config.contentInsets = NSDirectionalEdgeInsetsMake(4, 10, 4, 10);
        toolsButton.configuration = config;
    } else {
        // Fall back to older style for iOS 14 and below
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        toolsButton.contentEdgeInsets = UIEdgeInsetsMake(4, 10, 4, 10);
        #pragma clang diagnostic pop
    }
    
    toolsButton.layer.cornerRadius = 10;
    toolsButton.layer.borderWidth = 1;
    toolsButton.layer.borderColor = [UIColor systemBlueColor].CGColor;
    [toolsButton addTarget:self action:@selector(toolsButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *toolsBarButton = [[UIBarButtonItem alloc] initWithCustomView:toolsButton];
    self.navigationItem.rightBarButtonItem = toolsBarButton;
    
    // Initialize managers
    self.manager = [IdentifierManager sharedManager];
    self.freezeManager = [FreezeManager sharedManager];
    self.appSwitches = [NSMutableDictionary dictionary];
    self.identifierSwitches = [NSMutableDictionary dictionary];
    
    // Add tap gesture recognizer to dismiss keyboard
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    // Add long press gesture to show debug info for trial banner
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showTrialBannerDebugInfo:)];
    longPressGesture.minimumPressDuration = 2.0; // 2 seconds
    [self.view addGestureRecognizer:longPressGesture];
    
    // Register for keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    // Register for frozen state changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleFrozenStateChanged:)
                                                 name:@"AppFrozenStateChanged"
                                               object:nil];
    
    // Register for network status changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNetworkStatusChanged:)
                                                 name:@"WeaponXNetworkStatusChanged"
                                               object:nil];
    
    // Register for profile changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(handleProfileChanged:)
                                                name:@"com.hydra.projectx.profileChanged"
                                              object:nil];
    
    [self setupUI];
    [self loadSettings];
    // Remove duplicate call to setupProfileButtons since it's already called in setupUI
    [self setupProfileManagement];
    
    // Setup the trial offer banner for new users
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setupTrialOfferBanner];
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Ensure the gradient layer in the trial banner is properly sized
    if (self.trialOfferBannerView) {
        for (CALayer *layer in self.trialOfferBannerView.layer.sublayers) {
            if ([layer isKindOfClass:[CAGradientLayer class]]) {
                CAGradientLayer *gradientLayer = (CAGradientLayer *)layer;
                gradientLayer.frame = self.trialOfferBannerView.bounds;
            }
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Check network status for trial banner display
    if (![self isNetworkAvailable] && self.trialOfferBannerView) {
        // Hide the banner when offline
        [self hideTrialOfferBanner];
    }
    
    // Check user plan status for trial banner display using the tab restriction system flags
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasActivePlan = [defaults boolForKey:@"WeaponXHasActivePlan"];
    BOOL isRestricted = [defaults boolForKey:@"WeaponXRestrictedAccess"];
    BOOL hasPlan = hasActivePlan || !isRestricted;
    
    if (hasPlan && self.trialOfferBannerView) {
        // Hide the banner when user has a plan
        [self hideTrialOfferBanner];
    }
    
    // Make sure we have our main stack view fully loaded before attempting to add the banner
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!self.trialOfferBannerView) {
            [self setupTrialOfferBanner];
        }
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // ... existing code ...
    
    // Check if we should refresh the trial offer banner
    NSDate *lastShownDate = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXTrialOfferShownDate"];
    BOOL bannerExists = (self.trialOfferBannerView != nil);
    
    // If banner doesn't exist and we haven't shown it in the last hour, check eligibility again
    if (!bannerExists && lastShownDate) {
        NSTimeInterval timeSinceShown = [[NSDate date] timeIntervalSinceDate:lastShownDate];
        if (timeSinceShown > 3600) { // 1 hour = 3600 seconds
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupTrialOfferBanner];
            });
        }
    } else if (!bannerExists && !lastShownDate) {
        // Never shown before, initialize it
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setupTrialOfferBanner];
        });
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Remember if we had a banner
    self.hasShownTrialOffer = (self.trialOfferBannerView != nil);
    
    // Clean up trial banner when view disappears to avoid memory issues
    if (self.trialOfferBannerView) {
        [self hideTrialOfferBanner];
    }
}

#pragma mark - UI Setup

- (void)setupUI {
    // Setup scroll view with refresh control
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    
    // Hide vertical scroll indicator (removes the scrollbar line when scrolling)
    self.scrollView.showsVerticalScrollIndicator = NO;
    
    // Set delegate to self to implement scroll restriction
    self.scrollView.delegate = self;
    
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    self.scrollView.refreshControl = refreshControl;
    [self.view addSubview:self.scrollView];
    
    // Setup main stack view with improved spacing
    self.mainStackView = [[UIStackView alloc] init];
    self.mainStackView.axis = UILayoutConstraintAxisVertical;
    self.mainStackView.spacing = 24;
    self.mainStackView.alignment = UIStackViewAlignmentFill;
    self.mainStackView.layoutMargins = UIEdgeInsetsMake(0, 0, 100, 0);
    self.mainStackView.layoutMarginsRelativeArrangement = YES;
    self.mainStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStackView];
    
    // Initialize the advanced identifiers tracking array and flag
    self.advancedIdentifierViews = [NSMutableArray array];
    self.showAdvancedIdentifiers = NO;
    
    // Setup constraints with safe area
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [self.mainStackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.mainStackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.mainStackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.mainStackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.mainStackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32]
    ]];
    
    // Add sections with visual separation
    UIView *identifiersSection = [self createSectionHeaderWithTitle:@"Device IDs"];
    
    // Create header stack view for title and generate button
    UIStackView *headerStack = [[UIStackView alloc] init];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.spacing = 8;
    headerStack.alignment = UIStackViewAlignmentCenter;
    headerStack.distribution = UIStackViewDistributionEqualSpacing;
    
    [headerStack addArrangedSubview:identifiersSection];
    
    // Add Account button
    UIButton *accountButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [accountButton setImage:[UIImage systemImageNamed:@"person.crop.circle.fill"] forState:UIControlStateNormal];
    [accountButton addTarget:self action:@selector(accountButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    accountButton.tintColor = [UIColor systemBlueColor];
    [headerStack addArrangedSubview:accountButton];
    
    // Add Generate All button with minimalistic style
    UIButton *generateAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *generateAllConfig = [UIButtonConfiguration plainButtonConfiguration];
    generateAllConfig.title = @"Generate All";
    generateAllConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    generateAllConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.15];
    generateAllConfig.baseForegroundColor = [UIColor systemBlueColor];
    generateAllConfig.contentInsets = NSDirectionalEdgeInsetsMake(2, 4, 2, 4);
    
    // Create a smaller icon that matches the text size
    UIImage *smallIcon = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10]];
    generateAllConfig.image = smallIcon;
    
    generateAllConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    generateAllConfig.imagePadding = 2;
    generateAllButton.configuration = generateAllConfig;
    generateAllButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    generateAllButton.layer.cornerRadius = 8;
    generateAllButton.clipsToBounds = YES;
    [generateAllButton addTarget:self action:@selector(generateAllButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [headerStack addArrangedSubview:generateAllButton];
    
    [self.mainStackView addArrangedSubview:headerStack];
    
    // Add basic identifier sections
    [self addIdentifierSection:@"IDFA" title:@"Advertising Identifier"];
    [self addIdentifierSection:@"IDFV" title:@"Vendor Identifier"];
    [self addIdentifierSection:@"DeviceName" title:@"Device Name"];
    [self addIdentifierSection:@"IOSVersion" title:@"iOS Version & Build"];
    [self addIdentifierSection:@"WiFi" title:@"WiFi Information"];
    [self addIdentifierSection:@"StorageSystem" title:@"Storage Information"];
    [self addIdentifierSection:@"Battery" title:@"Battery Information"];
    
    // Add basic UUID sections - moved System Uptime and Boot Time from advanced to basic
    [self addIdentifierSection:@"SystemUptime" title:@"System Uptime"];
    [self addIdentifierSection:@"BootTime" title:@"Boot Time"];
    
    // Add "Show Advanced" button
    [self addShowAdvancedButton];
    
    // Add advanced identifier sections (will be initially hidden)
    [self addAdvancedIdentifierSection:@"KeychainUUID" title:@"Keychain UUID"];
    [self addAdvancedIdentifierSection:@"UserDefaultsUUID" title:@"UserDefaults UUID"];
    [self addAdvancedIdentifierSection:@"AppGroupUUID" title:@"App Group UUID"];
    [self addAdvancedIdentifierSection:@"CoreDataUUID" title:@"Core Data UUID"];
    [self addAdvancedIdentifierSection:@"AppInstallUUID" title:@"App Install UUID"];
    [self addAdvancedIdentifierSection:@"AppContainerUUID" title:@"App Container UUID"];
    // Moved Serial Number and Pasteboard UUID from basic to advanced
    [self addAdvancedIdentifierSection:@"SerialNumber" title:@"Serial Number"];
    [self addAdvancedIdentifierSection:@"PasteboardUUID" title:@"Pasteboard UUID"];
    // Moved System Boot UUID and Dyld Cache UUID from basic to advanced
    [self addAdvancedIdentifierSection:@"SystemBootUUID" title:@"System Boot UUID"];
    [self addAdvancedIdentifierSection:@"DyldCacheUUID" title:@"Dyld Cache UUID"];
    
    UIView *appsSection = [self createSectionHeaderWithTitle:@"Scoped Apps"];
    [self.mainStackView addArrangedSubview:appsSection];
    
    [self addAppManagementSection];
    
    // Add bottom buttons view
    UIView *bottomButtonsView = [[BottomButtons sharedInstance] createBottomButtonsView];
    [self.view addSubview:bottomButtonsView];
    
    // Setup constraints for bottom buttons view
    [NSLayoutConstraint activateConstraints:@[
        [bottomButtonsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bottomButtonsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bottomButtonsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    
    // Add profile buttons view
    self.profileButtonsView = [[ProfileButtonsView alloc] initWithFrame:CGRectZero];
    self.profileButtonsView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.profileButtonsView];
    
    // Setup profile button actions
    __weak typeof(self) weakSelf = self;
    
    // Set the block for new profile button
    self.profileButtonsView.onNewProfileTapped = ^{
        [weakSelf showProfileCreation];
    };
    self.profileButtonsView.onManageProfilesTapped = ^{
        [weakSelf showProfileManager];
    };
    
    // Add profile buttons constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.profileButtonsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:11],
        [self.profileButtonsView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.profileButtonsView.widthAnchor constraintEqualToConstant:60],
        [self.profileButtonsView.heightAnchor constraintEqualToConstant:136] // 2 buttons * 60 + 16 spacing
    ]];

    // --- Floating scroll-to-bottom button ---
    UIButton *scrollToBottomButton = [UIButton buttonWithType:UIButtonTypeCustom];
    scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = NO;
    // Use system background color that adapts to light/dark mode
    if (@available(iOS 13.0, *)) {
        scrollToBottomButton.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        scrollToBottomButton.backgroundColor = [UIColor whiteColor];
    }
    scrollToBottomButton.layer.cornerRadius = 18;
    scrollToBottomButton.clipsToBounds = YES;
    [scrollToBottomButton setImage:[[UIImage systemImageNamed:@"arrow.down"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    // Use system label color for the icon (adapts to theme)
    if (@available(iOS 13.0, *)) {
        scrollToBottomButton.tintColor = [UIColor labelColor];
    } else {
        scrollToBottomButton.tintColor = [UIColor blackColor];
    }
    scrollToBottomButton.alpha = 0.0; // Initially hidden
    scrollToBottomButton.layer.shadowColor = [UIColor blackColor].CGColor;
    scrollToBottomButton.layer.shadowOpacity = 0.2;
    scrollToBottomButton.layer.shadowOffset = CGSizeMake(0,2);
    scrollToBottomButton.layer.shadowRadius = 4;
    [self.view addSubview:scrollToBottomButton];

    // Constraints: right below profile buttons, horizontally aligned
    [NSLayoutConstraint activateConstraints:@[
        [scrollToBottomButton.centerXAnchor constraintEqualToAnchor:self.profileButtonsView.centerXAnchor],
        [scrollToBottomButton.topAnchor constraintEqualToAnchor:self.profileButtonsView.bottomAnchor constant:18],
        [scrollToBottomButton.widthAnchor constraintEqualToConstant:36],
        [scrollToBottomButton.heightAnchor constraintEqualToConstant:36]
    ]];

    // Action: scroll to bottom
    [scrollToBottomButton addTarget:self action:@selector(scrollToBottomButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.scrollToBottomButton = scrollToBottomButton;

    // Observe scroll events to show/hide button
    self.scrollView.delegate = self;

    
    // Initialize profiles array
    self.profiles = [[ProfileManager sharedManager].profiles mutableCopy];
    
    // Setup profile indicator
    [self setupProfileIndicator];
}

#pragma mark - Settings Management

- (void)loadSettings {
    // Load identifier states
    UISwitch *idfaSwitch = self.identifierSwitches[@"IDFA"];
    UISwitch *idfvSwitch = self.identifierSwitches[@"IDFV"];
    
    if (idfaSwitch) {
        idfaSwitch.on = [self.manager isIdentifierEnabled:@"IDFA"];
    }
    
    if (idfvSwitch) {
        idfvSwitch.on = [self.manager isIdentifierEnabled:@"IDFV"];
    }
    
    // Clear existing app switches
    [self.appSwitches removeAllObjects];
    
    // Load app states
    NSDictionary *appInfo = [self.manager getApplicationInfo:nil];
    for (NSString *bundleID in appInfo) {
        UISwitch *appSwitch = [[UISwitch alloc] init];
        [appSwitch addTarget:self action:@selector(appSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        appSwitch.on = [self.manager isApplicationEnabled:bundleID];
        self.appSwitches[bundleID] = appSwitch;
    }
    
    // Update UI to reflect current state
    [self updateAppsList];
}

#pragma mark - UI Updates

- (void)updateAppsList {
    // Remove all existing app views
    for (UIView *view in self.appsStackView.arrangedSubviews) {
        [view removeFromSuperview];
    }
    
    // Add app views for each app in appSwitches
    for (NSString *bundleID in self.appSwitches) {
        NSDictionary *appInfo = [self.manager getApplicationInfo:bundleID];
        NSString *displayBundleID = appInfo[@"bundleID"] ?: bundleID;
        
        // Create app view container
        UIView *appView = [[UIView alloc] init];
        appView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        appView.layer.cornerRadius = 8;
        appView.clipsToBounds = YES;
        
        // Create background icon view with blur
        UIImageView *iconBackgroundView = [[UIImageView alloc] init];
        iconBackgroundView.contentMode = UIViewContentModeScaleAspectFit;
        iconBackgroundView.alpha = 0.3; // 30% opacity
        iconBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
        [appView addSubview:iconBackgroundView];
        
        // Add blur effect
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        blurView.alpha = 0.7; // Adjust blur intensity
        blurView.translatesAutoresizingMaskIntoConstraints = NO;
        [appView addSubview:blurView];
        
        // Create stack view for app content
        UIStackView *contentStack = [[UIStackView alloc] init];
        contentStack.axis = UILayoutConstraintAxisVertical;
        contentStack.spacing = 8;
        contentStack.layoutMargins = UIEdgeInsetsMake(12, 12, 12, 12);
        contentStack.layoutMarginsRelativeArrangement = YES;
        contentStack.translatesAutoresizingMaskIntoConstraints = NO;
        [appView addSubview:contentStack];
        
        // Setup constraints for background icon and blur
        [NSLayoutConstraint activateConstraints:@[
            [iconBackgroundView.centerXAnchor constraintEqualToAnchor:appView.centerXAnchor],
            [iconBackgroundView.centerYAnchor constraintEqualToAnchor:appView.centerYAnchor],
            [iconBackgroundView.widthAnchor constraintEqualToAnchor:appView.widthAnchor multiplier:0.3], // Reduced to 30%
            [iconBackgroundView.heightAnchor constraintEqualToAnchor:iconBackgroundView.widthAnchor],
            
            [blurView.topAnchor constraintEqualToAnchor:appView.topAnchor],
            [blurView.leadingAnchor constraintEqualToAnchor:appView.leadingAnchor],
            [blurView.trailingAnchor constraintEqualToAnchor:appView.trailingAnchor],
            [blurView.bottomAnchor constraintEqualToAnchor:appView.bottomAnchor],
            
            [contentStack.topAnchor constraintEqualToAnchor:appView.topAnchor],
            [contentStack.leadingAnchor constraintEqualToAnchor:appView.leadingAnchor],
            [contentStack.trailingAnchor constraintEqualToAnchor:appView.trailingAnchor],
            [contentStack.bottomAnchor constraintEqualToAnchor:appView.bottomAnchor]
        ]];
        
        // Fetch and set app icon
        [self fetchAppIconForBundleID:bundleID completion:^(UIImage *icon) {
            iconBackgroundView.image = icon;
        }];
        
        // Create bundle ID with copy button
        UIStackView *bundleStack = [[UIStackView alloc] init];
        bundleStack.axis = UILayoutConstraintAxisHorizontal;
        bundleStack.spacing = 4;  // Reduced spacing
        bundleStack.alignment = UIStackViewAlignmentCenter;
        
        // Add extension button with smaller size
        UIButton *extensionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *plusImage = [[UIImage systemImageNamed:@"plus.circle.fill"] imageWithConfiguration:
                             [UIImageSymbolConfiguration configurationWithPointSize:14.0]];  // Reduced size
        [extensionButton setImage:plusImage forState:UIControlStateNormal];
        extensionButton.tintColor = [UIColor systemBlueColor];
        extensionButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
        [extensionButton addTarget:self action:@selector(extensionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        // Set fixed size for extension button
        [extensionButton.heightAnchor constraintEqualToConstant:16].active = YES;  // Fixed height
        [extensionButton.widthAnchor constraintEqualToConstant:16].active = YES;   // Fixed width
        extensionButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        
        // Add to stack with no extra padding
        [bundleStack setCustomSpacing:2 afterView:extensionButton];  // Minimal spacing after button
        [bundleStack addArrangedSubview:extensionButton];
        
        UILabel *bundleLabel = [[UILabel alloc] init];
        bundleLabel.text = displayBundleID;
        bundleLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        bundleLabel.numberOfLines = 1;
        bundleLabel.adjustsFontSizeToFitWidth = YES;
        bundleLabel.minimumScaleFactor = 0.75;
        [bundleStack addArrangedSubview:bundleLabel];
        
        UIButton *copyButton = [CopyHelper createCopyButtonWithText:displayBundleID];
        [copyButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [bundleStack addArrangedSubview:copyButton];
        
        [contentStack addArrangedSubview:bundleStack];
        
        // Add app info
        UILabel *infoLabel = [[UILabel alloc] init];
        if ([appInfo[@"installed"] boolValue]) {
            NSString *frozenStatus = [self.freezeManager isApplicationFrozen:bundleID] ? @" [FROZEN]" : @"";
            NSString *infoText = [NSString stringWithFormat:@"%@ - v%@%@", appInfo[@"name"], appInfo[@"version"], frozenStatus];
            
            NSMutableAttributedString *attributedInfoText = [[NSMutableAttributedString alloc] initWithString:infoText];
            if ([self.freezeManager isApplicationFrozen:bundleID]) {
                NSRange frozenRange = [infoText rangeOfString:@"[FROZEN]"];
                [attributedInfoText addAttribute:NSForegroundColorAttributeName value:[UIColor systemBlueColor] range:frozenRange];
            }
            
            infoLabel.attributedText = attributedInfoText;
            infoLabel.textColor = [UIColor labelColor];
        } else {
            infoLabel.text = @"Removed From Scope";
            infoLabel.textColor = [UIColor systemOrangeColor];
        }
        infoLabel.font = [UIFont systemFontOfSize:12];
        [contentStack addArrangedSubview:infoLabel];
        
        // Add delete button with trash icon
        UIStackView *controlStack = [[UIStackView alloc] init];
        controlStack.axis = UILayoutConstraintAxisHorizontal;
        controlStack.alignment = UIStackViewAlignmentCenter;
        controlStack.distribution = UIStackViewDistributionEqualSpacing;
        controlStack.spacing = 8;
        
        UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [deleteButton setImage:[UIImage systemImageNamed:@"trash.slash.circle.fill"] forState:UIControlStateNormal];
        [deleteButton setTintColor:[UIColor systemRedColor]];
        deleteButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
        [deleteButton addTarget:self action:@selector(deleteAppButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [controlStack addArrangedSubview:deleteButton];
        
        // Replace freeze button with more options button (ellipsis)
        UIButton *moreOptionsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [moreOptionsButton setImage:[UIImage systemImageNamed:@"ellipsis.circle.fill"] forState:UIControlStateNormal];
        [moreOptionsButton setTintColor:[UIColor systemBlueColor]];
        moreOptionsButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
        [moreOptionsButton addTarget:self action:@selector(moreOptionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [controlStack addArrangedSubview:moreOptionsButton];
        
        // Add clear data button
        UIButton *clearDataButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [clearDataButton setImage:[UIImage systemImageNamed:@"externaldrive.fill.badge.minus"] forState:UIControlStateNormal];
        [clearDataButton setTintColor:[UIColor systemRedColor]];
        clearDataButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
        [clearDataButton addTarget:self action:@selector(clearDataButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [controlStack addArrangedSubview:clearDataButton];
        
        // Add versions button
        UIButton *versionsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [versionsButton setImage:[UIImage systemImageNamed:@"arrow.up.and.down.circle.fill"] forState:UIControlStateNormal];
        [versionsButton setTintColor:[UIColor systemBlueColor]];
        versionsButton.tag = [self.appSwitches.allKeys indexOfObject:bundleID];
        [versionsButton addTarget:self action:@selector(versionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [controlStack addArrangedSubview:versionsButton];
        
        // Add switch
        UISwitch *appSwitch = self.appSwitches[bundleID];
        [controlStack addArrangedSubview:appSwitch];
        
        [contentStack addArrangedSubview:controlStack];
        
        // Setup constraints
        [NSLayoutConstraint activateConstraints:@[
            [contentStack.topAnchor constraintEqualToAnchor:appView.topAnchor],
            [contentStack.leadingAnchor constraintEqualToAnchor:appView.leadingAnchor],
            [contentStack.trailingAnchor constraintEqualToAnchor:appView.trailingAnchor],
            [contentStack.bottomAnchor constraintEqualToAnchor:appView.bottomAnchor]
        ]];
        
        [self.appsStackView addArrangedSubview:appView];
    }
}

#pragma mark - Button Actions

- (void)backupRestoreButtonTapped:(UIButton *)sender {
    // Open the AppDataBackupRestoreViewController when the new icon is tapped
    AppDataBackupRestoreViewController *vc = [[AppDataBackupRestoreViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:vc animated:YES completion:nil];
}

// (Freeze logic remains for now, but is not connected to any UI)
- (void)freezeAppButtonTapped:(UIButton *)sender {
    NSString *bundleID = self.appSwitches.allKeys[sender.tag];
    if (!bundleID) {
        return;
    }
    
    // Disable the button temporarily to prevent multiple taps
    sender.enabled = NO;
    
    BOOL isFrozen = [self.freezeManager isApplicationFrozen:bundleID];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (isFrozen) {
            [self.freezeManager unfreezeApplication:bundleID];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [sender setTintColor:[UIColor systemGrayColor]];
                sender.enabled = YES;
                [self.appsTableView reloadData];
            });
        } else {
            [self.freezeManager freezeApplication:bundleID];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [sender setTintColor:[UIColor systemBlueColor]];
                sender.enabled = YES;
                [self.appsTableView reloadData];
            });
        }
    });
}

#pragma mark - Process Management

- (void)killEnabledAppsAndRespring {
    // Get all enabled apps
    NSDictionary *allApps = [self.manager getApplicationInfo:nil];
    for (NSString *bundleID in allApps) {
        if ([self.manager isApplicationEnabled:bundleID]) {
            // Use posix_spawn to kill apps
            pid_t pid;
            const char *killall = "/usr/bin/killall";
            const char *bundleIDStr = [bundleID UTF8String];
            char *const argv[] = {(char *)"killall", (char *)bundleIDStr, NULL};
            posix_spawn(&pid, killall, NULL, NULL, argv, NULL);
            int status;
            waitpid(pid, &status, WEXITED);
        }
    }
    
    // Respring using sbreload
    pid_t pid;
    const char *sbreload = "/usr/bin/sbreload";
    char *const argv[] = {(char *)"sbreload", NULL};
    posix_spawn(&pid, sbreload, NULL, NULL, argv, NULL);
    waitpid(pid, NULL, WEXITED);
}

#pragma mark - Error Handling

- (void)showError:(NSError *)error {
    if (!error) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                 message:error.localizedDescription
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil];
    
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Keyboard Handling

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardFrame.size.height, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.scrollView.contentInset = UIEdgeInsetsZero;
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
    [self.versionSearchBar resignFirstResponder];
    [self.appSearchBar resignFirstResponder];
}

#pragma mark - UI Components

- (void)addIdentifierSection:(NSString *)type title:(NSString *)title {
    // Create section title
    NSArray *shippingboxTypes = @[ @"KeychainUUID", @"UserDefaultsUUID", @"AppGroupUUID", @"CoreDataUUID", @"AppInstallUUID", @"AppContainerUUID" ];
    if (@available(iOS 15.0, *)) {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor labelColor];
        
        // Determine which icon to use based on type
        NSString *iconName = [shippingboxTypes containsObject:type] ? @"shippingbox" : @"pencil";
        UIImage *iconImage = [UIImage systemImageNamed:iconName];
        
        if (iconImage) {
            // Tint the icon to match text
            iconImage = [iconImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            NSTextAttachment *iconAttachment = [[NSTextAttachment alloc] init];
            iconAttachment.image = iconImage;
            CGFloat iconSize = 18;
            iconAttachment.bounds = CGRectMake(0, -3, iconSize, iconSize);
            
            NSAttributedString *space = [[NSAttributedString alloc] initWithString:@"  "];
            NSAttributedString *titleString = [[NSAttributedString alloc] initWithString:title attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:18 weight:UIFontWeightBold],
                NSForegroundColorAttributeName: [UIColor labelColor]
            }];
            
            NSMutableAttributedString *full = [[NSMutableAttributedString alloc] initWithAttributedString:titleString];
            [full appendAttributedString:space];
            [full appendAttributedString:[NSAttributedString attributedStringWithAttachment:iconAttachment]];
            titleLabel.attributedText = full;
            titleLabel.tintColor = [UIColor labelColor];
            
            // Add tap gesture for the label to show edit dialog
            UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(titleIconTapped:)];
            titleLabel.userInteractionEnabled = YES;
            [titleLabel addGestureRecognizer:titleTap];
            objc_setAssociatedObject(titleTap, "identifierType", type, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            // Unicode fallback
            titleLabel.text = [NSString stringWithFormat:@"%@ \U0001F4E6", title];
        }
        [self.mainStackView addArrangedSubview:titleLabel];
    } else {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = title;
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor labelColor];
        [self.mainStackView addArrangedSubview:titleLabel];
    }
    
    // Reduce spacing between title and container by 50%
    UIView *lastTitleView = nil;
    if (@available(iOS 15.0, *)) {
        if ([shippingboxTypes containsObject:type]) {
            lastTitleView = self.mainStackView.arrangedSubviews.lastObject; // titleStack
        } else {
            lastTitleView = self.mainStackView.arrangedSubviews.lastObject; // titleLabel
        }
    } else {
        lastTitleView = self.mainStackView.arrangedSubviews.lastObject; // titleLabel
    }
    if (lastTitleView) {
        [self.mainStackView setCustomSpacing:4 afterView:lastTitleView];
    }
    
    // Create container view with glassmorphism effect
    UIView *containerView = [[UIView alloc] init];
    
    // Set up glassmorphism effect - works in both light and dark mode
    containerView.backgroundColor = [UIColor clearColor];
    
    // Create blur effect - adapts to light/dark mode automatically
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:blurView];
    
    // Add vibrancy effect for content
    UIVibrancyEffect *vibrancyEffect = [UIVibrancyEffect effectForBlurEffect:blurEffect];
    UIVisualEffectView *vibrancyView = [[UIVisualEffectView alloc] initWithEffect:vibrancyEffect];
    vibrancyView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Setup blur view constraints to fill container
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];
    
    // Add subtle border
    containerView.layer.borderWidth = 0.5;
    containerView.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.2].CGColor;
    containerView.layer.cornerRadius = 20;
    containerView.clipsToBounds = YES;
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add subtle shadow
    containerView.layer.shadowColor = [UIColor blackColor].CGColor;
    containerView.layer.shadowOffset = CGSizeMake(0, 4);
    containerView.layer.shadowRadius = 8;
    containerView.layer.shadowOpacity = 0.1;
    
    // Create vertical stack for identifier and controls
    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 10;
    contentStack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
    contentStack.layoutMarginsRelativeArrangement = YES;
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:contentStack];
    
    // Setup content stack constraints
    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:containerView.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor]
    ]];
    
    // Create identifier container with background
    UIView *identifierContainer = [[UIView alloc] init];
    identifierContainer.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.1];
    identifierContainer.layer.cornerRadius = 12;
    identifierContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Create identifier label
    UILabel *identifierLabel = [[UILabel alloc] init];
    NSString *currentValue = [self.manager currentValueForIdentifier:type];
    identifierLabel.text = currentValue ?: @"Not Set";
    identifierLabel.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightRegular];
    identifierLabel.textColor = [UIColor labelColor];
    identifierLabel.numberOfLines = 1;
    identifierLabel.adjustsFontSizeToFitWidth = YES;
    identifierLabel.minimumScaleFactor = 0.5;
    identifierLabel.textAlignment = NSTextAlignmentCenter;
    identifierLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add padding to identifier label
    [identifierContainer addSubview:identifierLabel];
    [NSLayoutConstraint activateConstraints:@[
        [identifierLabel.topAnchor constraintEqualToAnchor:identifierContainer.topAnchor constant:12],
        [identifierLabel.leadingAnchor constraintEqualToAnchor:identifierContainer.leadingAnchor constant:12],
        [identifierLabel.trailingAnchor constraintEqualToAnchor:identifierContainer.trailingAnchor constant:-12],
        [identifierLabel.bottomAnchor constraintEqualToAnchor:identifierContainer.bottomAnchor constant:-12]
    ]];
    
    [contentStack addArrangedSubview:identifierContainer];
    
    // Create horizontal stack for controls
    UIStackView *controlsStack = [[UIStackView alloc] init];
    controlsStack.axis = UILayoutConstraintAxisHorizontal;
    controlsStack.distribution = UIStackViewDistributionEqualSpacing;
    controlsStack.alignment = UIStackViewAlignmentCenter;
    
    // Create copy button with enhanced style
    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *copyConfig = [UIButtonConfiguration plainButtonConfiguration];
    copyConfig.image = [UIImage systemImageNamed:@"doc.on.doc"];
    copyConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    copyConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    copyConfig.baseForegroundColor = [UIColor systemBlueColor];
    copyConfig.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
    copyButton.configuration = copyConfig;
    
    copyButton.tag = [self tagForIdentifierType:type];
    copyButton.accessibilityValue = currentValue;
    [copyButton addTarget:self action:@selector(copyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Create switch and status container
    UIStackView *switchStatusStack = [[UIStackView alloc] init];
    switchStatusStack.axis = UILayoutConstraintAxisHorizontal;
    switchStatusStack.spacing = 8;
    switchStatusStack.alignment = UIStackViewAlignmentCenter;
    
    // Create status label
    UILabel *stateLabel = [[UILabel alloc] init];
    stateLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    stateLabel.textColor = [UIColor labelColor];
    stateLabel.text = [self.manager isIdentifierEnabled:type] ? @"Enabled" : @"Disabled";
    stateLabel.tag = 100; // Tag to find this label later
    
    // Create switch with modern style
    UISwitch *identifierSwitch = [[UISwitch alloc] init];
    [identifierSwitch setOn:[self.manager isIdentifierEnabled:type] animated:NO];
    identifierSwitch.onTintColor = [UIColor systemBlueColor];
    [identifierSwitch addTarget:self action:@selector(identifierSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    identifierSwitch.tag = [self tagForIdentifierType:type];
    
    [switchStatusStack addArrangedSubview:stateLabel];
    [switchStatusStack addArrangedSubview:identifierSwitch];
    
    // Create generate button with minimalistic style
    UIButton *generateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *generateConfig = [UIButtonConfiguration plainButtonConfiguration];
    generateConfig.image = [UIImage systemImageNamed:@"arrow.clockwise"];
    generateConfig.title = @"Generate";
    generateConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    generateConfig.imagePadding = 4;
    generateConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    generateConfig.background.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.15];
    generateConfig.baseForegroundColor = [UIColor systemBlueColor];
    generateConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 6, 4, 6);
    generateButton.configuration = generateConfig;
    generateButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    generateButton.layer.cornerRadius = 10;
    generateButton.clipsToBounds = YES;
    
    generateButton.tag = [self tagForIdentifierType:type];
    [generateButton addTarget:self action:@selector(generateButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Add all elements to controls stack
    [controlsStack addArrangedSubview:copyButton];
    [controlsStack addArrangedSubview:switchStatusStack];
    [controlsStack addArrangedSubview:generateButton];
    
    // Add controls stack to content stack
    [contentStack addArrangedSubview:controlsStack];
    
    // Add container to main stack
    [self.mainStackView addArrangedSubview:containerView];
    
    // Add spacing after the container - reduce by 50% from default spacing
    [self.mainStackView setCustomSpacing:12 afterView:containerView]; // 50% of the default 24 spacing
    
    // Store switch reference
    if (!self.identifierSwitches) {
        self.identifierSwitches = [NSMutableDictionary dictionary];
    }
    self.identifierSwitches[type] = identifierSwitch;
}

- (void)addAppManagementSection {
    // Create apps stack view
    self.appsStackView = [[UIStackView alloc] init];
    self.appsStackView.axis = UILayoutConstraintAxisVertical;
    self.appsStackView.spacing = 12;
    self.appsStackView.alignment = UIStackViewAlignmentFill;
    
    // Add bundle ID input field and buttons container
    UIStackView *inputStack = [[UIStackView alloc] init];
    inputStack.axis = UILayoutConstraintAxisHorizontal;
    inputStack.spacing = 8;
    inputStack.alignment = UIStackViewAlignmentCenter;
    inputStack.layoutMargins = UIEdgeInsetsMake(0, 8, 0, 8);
    inputStack.layoutMarginsRelativeArrangement = YES;
    
    // Create container view for text field to control its size
    UIView *textFieldContainer = [[UIView alloc] init];
    textFieldContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.bundleIDTextField = [[UITextField alloc] init];
    self.bundleIDTextField.placeholder = @"Enter Bundle ID";
    self.bundleIDTextField.font = [UIFont systemFontOfSize:16];
    self.bundleIDTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.bundleIDTextField.delegate = self;
    self.bundleIDTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [textFieldContainer addSubview:self.bundleIDTextField];
    
    // Set fixed height and width for text field container
    [NSLayoutConstraint activateConstraints:@[
        [textFieldContainer.heightAnchor constraintEqualToConstant:36],
        [textFieldContainer.widthAnchor constraintEqualToConstant:200],  // Fixed width
        [self.bundleIDTextField.topAnchor constraintEqualToAnchor:textFieldContainer.topAnchor],
        [self.bundleIDTextField.bottomAnchor constraintEqualToAnchor:textFieldContainer.bottomAnchor],
        [self.bundleIDTextField.leadingAnchor constraintEqualToAnchor:textFieldContainer.leadingAnchor],
        [self.bundleIDTextField.trailingAnchor constraintEqualToAnchor:textFieldContainer.trailingAnchor]
    ]];
    
    [inputStack addArrangedSubview:textFieldContainer];
    
    // Create buttons stack
    UIStackView *buttonsStack = [[UIStackView alloc] init];
    buttonsStack.axis = UILayoutConstraintAxisHorizontal;
    buttonsStack.spacing = 12;  // Increased spacing between buttons
    buttonsStack.alignment = UIStackViewAlignmentCenter;
    
    // Add installed apps button (plus button)
    UIButton *installedAppsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [installedAppsButton setImage:[UIImage systemImageNamed:@"plus.diamond.fill"] forState:UIControlStateNormal];
    [installedAppsButton addTarget:self action:@selector(addAppButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [installedAppsButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [buttonsStack addArrangedSubview:installedAppsButton];
    
    // Add App button
    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *addButtonConfig = [UIButtonConfiguration plainButtonConfiguration];
    addButtonConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 6, 4, 6);
    addButtonConfig.title = @"Add App";
    addButtonConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    addButtonConfig.background.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.15];
    addButtonConfig.baseForegroundColor = [UIColor systemGreenColor];
    addButton.configuration = addButtonConfig;
    addButton.layer.cornerRadius = 10;
    addButton.clipsToBounds = YES;
    addButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [addButton addTarget:self action:@selector(showInstalledAppsPopup:) forControlEvents:UIControlEventTouchUpInside];
    [addButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [buttonsStack addArrangedSubview:addButton];
    
    [inputStack addArrangedSubview:buttonsStack];
    
    // Set content hugging and compression resistance for the container
    [textFieldContainer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [textFieldContainer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    
    // Set content hugging and compression resistance for buttons stack
    [buttonsStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [buttonsStack setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    
    [self.mainStackView addArrangedSubview:inputStack];
    [self.mainStackView addArrangedSubview:self.appsStackView];
}

- (UIView *)createSectionHeaderWithTitle:(NSString *)title {
    UIView *headerView = [[UIView alloc] init];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [headerView addSubview:titleLabel];
    
    UIView *separatorView = [[UIView alloc] init];
    separatorView.backgroundColor = [UIColor separatorColor];
    separatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [headerView addSubview:separatorView];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
        
        [separatorView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [separatorView.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor],
        [separatorView.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
        [separatorView.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor],
        [separatorView.heightAnchor constraintEqualToConstant:1]
    ]];
    
    return headerView;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Get the new text that would result from this change
    NSString *newText = [textField.text stringByReplacingCharactersInRange:range withString:string];
    
    // Limit text field to 50 characters (increased from 26)
    if (newText.length > 50) {
        return NO;
    }
    
    // Only allow alphanumeric characters, dots, and hyphens
    NSCharacterSet *allowedCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    NSCharacterSet *characterSet = [NSCharacterSet characterSetWithCharactersInString:string];
    return [allowedCharacters isSupersetOfSet:characterSet] || [string isEqualToString:@""];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    
    // If there's text, automatically try to add the app
    if (textField.text.length > 0) {
        [self addAppButtonTapped:nil];
    }
    
    return YES;
}

#pragma mark - UITableViewDelegate


#pragma mark - Switch Actions

- (void)identifierSwitchChanged:(UISwitch *)sender {
    // Find which identifier type this switch belongs to
    NSString *identifierType = nil;
    for (NSString *type in self.identifierSwitches) {
        if (self.identifierSwitches[type] == sender) {
            identifierType = type;
            break;
        }
    }
    
    if (!identifierType) return;
    
    // Update the identifier state in manager
    [self.manager setIdentifierEnabled:sender.isOn forType:identifierType];
    
    // Find and update state label
    UIStackView *switchStatusStack = (UIStackView *)sender.superview;
    if ([switchStatusStack isKindOfClass:[UIStackView class]]) {
        UILabel *stateLabel = [switchStatusStack.arrangedSubviews filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                return [object isKindOfClass:[UILabel class]] && ((UILabel *)object).tag == 100;
            }]].firstObject;
        
        if (stateLabel) {
            stateLabel.text = sender.isOn ? @"Enabled" : @"Disabled";
        }
    }
    
    // If enabled, just update the UI with the existing value from plist
    if (sender.isOn) {
        NSString *existingValue = [self.manager currentValueForIdentifier:identifierType];
        if (existingValue) {
            [self directUpdateIdentifierValue:identifierType withValue:existingValue];
        }
    }
    
    // Save settings to persist the enabled state
    [self.manager saveSettings];
}

- (void)appSwitchChanged:(UISwitch *)sender {
    // Find which app this switch belongs to
    NSString *bundleID = nil;
    for (NSString *appBundleID in self.appSwitches) {
        if (self.appSwitches[appBundleID] == sender) {
            bundleID = appBundleID;
            break;
        }
    }
    
    if (!bundleID) return;
    
    // Update app state in manager
    [self.manager setApplication:bundleID enabled:sender.isOn];
}

- (void)addAppButtonTapped:(UIButton *)sender {
    if (![[APIManager sharedManager] userHasPlan]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Plan Required"
                                                                       message:@"You need an active plan to add apps to scope."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *bundleID = self.bundleIDTextField.text;
    if (!bundleID.length) {
        [self showError:[NSError errorWithDomain:@"com.hydra.projectx" 
                                           code:3001 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Please enter a bundle ID"}]];
        return;
    }
    
    // Add app to manager
    [self.manager addApplicationToScope:bundleID];
    
    // Check for errors
    if ([self.manager lastError]) {
        [self showError:[self.manager lastError]];
        return;
    }
    
    // Clear text field
    self.bundleIDTextField.text = @"";
    [self.bundleIDTextField resignFirstResponder];
    
    // Refresh UI
    [self loadSettings];
}

- (void)handleFrozenStateChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update the table view to reflect frozen state changes
        [self.appsTableView reloadData];
        
        // If specific app info was provided, update just that row
        NSString *bundleID = notification.userInfo[@"bundleID"];
        if (bundleID) {
            NSInteger index = [self.appSwitches.allKeys indexOfObject:bundleID];
            if (index != NSNotFound) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                [self.appsTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            }
        }
    });
}

- (void)refreshData {
    [self loadSettings];
    [self.scrollView.refreshControl endRefreshing];
}

- (void)generateButtonTapped:(UIButton *)sender {
    // Check if user has an active plan
    BOOL isRestricted = [[NSUserDefaults standardUserDefaults] boolForKey:@"WeaponXRestrictedAccess"];
    
    // Also check associated object as a backup
    if (!isRestricted) {
        UIViewController *topVC = [self findTopViewController];
        NSNumber *restrictedAccess = objc_getAssociatedObject(topVC, "WeaponXRestrictedAccess");
        isRestricted = restrictedAccess ? [restrictedAccess boolValue] : NO;
    }
    
    // If user doesn't have an active plan, show alert and prevent action
    if (isRestricted) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Access Restricted" 
            message:@"Please subscribe to a plan to use the generate feature." 
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"View Plans" 
            style:UIAlertActionStyleDefault 
            handler:^(UIAlertAction * _Nonnull action) {
                // Switch to account tab to view plans
                UITabBarController *tabController = [self findTabBarController];
                if ([tabController respondsToSelector:@selector(switchToAccountTab)]) {
                    [tabController performSelector:@selector(switchToAccountTab)];
                }
            }]];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"Cancel" 
            style:UIAlertActionStyleCancel 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Determine which identifier type based on the button's tag
    NSString *identifierType;
    if (sender.tag == 1) {
        identifierType = @"IDFA";
    } else if (sender.tag == 2) {
        identifierType = @"IDFV";
    } else if (sender.tag == 3) {
        identifierType = @"DeviceName";
    } else if (sender.tag == 4) {
        identifierType = @"SerialNumber";
    } else if (sender.tag == 5) {
        identifierType = @"IOSVersion";
    } else if (sender.tag == 6) {
        identifierType = @"WiFi";
    } else if (sender.tag == 7) {
        identifierType = @"StorageSystem";
    } else if (sender.tag == 8) {
        identifierType = @"Battery";
    } else if (sender.tag == 9) {
        identifierType = @"SystemBootUUID";
    } else if (sender.tag == 10) {
        identifierType = @"DyldCacheUUID";
    } else if (sender.tag == 11) {
        identifierType = @"PasteboardUUID";
    } else if (sender.tag == 12) {
        identifierType = @"KeychainUUID";
    } else if (sender.tag == 13) {
        identifierType = @"UserDefaultsUUID";
    } else if (sender.tag == 14) {
        identifierType = @"AppGroupUUID";
    } else if (sender.tag == 15) {
        identifierType = @"SystemUptime";
    } else if (sender.tag == 16) {
        identifierType = @"BootTime";
    } else if (sender.tag == 17) {
        identifierType = @"CoreDataUUID";
    } else if (sender.tag == 18) {
        identifierType = @"AppInstallUUID";
    } else if (sender.tag == 19) {
        identifierType = @"AppContainerUUID";
    } else {
        return;
    }
    
    // Disable button temporarily
    sender.enabled = NO;
    
    // Show loading state
    UIColor *originalColor = sender.tintColor;
    [sender setTitle:@"Generating..." forState:UIControlStateNormal];
    [sender setTintColor:[UIColor systemGrayColor]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Generate only the specific identifier that was tapped
        NSString *newValue = nil;
        if ([identifierType isEqualToString:@"IDFA"]) {
            newValue = [self.manager generateIDFA];
        } else if ([identifierType isEqualToString:@"IDFV"]) {
            newValue = [self.manager generateIDFV];
        } else if ([identifierType isEqualToString:@"DeviceName"]) {
            newValue = [self.manager generateDeviceName];
        } else if ([identifierType isEqualToString:@"SerialNumber"]) {
            newValue = [self.manager generateSerialNumber];
        } else if ([identifierType isEqualToString:@"IOSVersion"]) {
            // Generate iOS Version and then get the string representation
            [self.manager generateIOSVersion];
            newValue = [self.manager currentValueForIdentifier:@"IOSVersion"];
        } else if ([identifierType isEqualToString:@"WiFi"]) {
            newValue = [self.manager generateWiFiInformation];
        } else if ([identifierType isEqualToString:@"SystemBootUUID"]) {
            newValue = [self.manager generateSystemBootUUID];
        } else if ([identifierType isEqualToString:@"DyldCacheUUID"]) {
            newValue = [self.manager generateDyldCacheUUID];
        } else if ([identifierType isEqualToString:@"PasteboardUUID"]) {
            newValue = [self.manager generatePasteboardUUID];
        } else if ([identifierType isEqualToString:@"KeychainUUID"]) {
            newValue = [self.manager generateKeychainUUID];
        } else if ([identifierType isEqualToString:@"UserDefaultsUUID"]) {
            newValue = [self.manager generateUserDefaultsUUID];
        } else if ([identifierType isEqualToString:@"AppGroupUUID"]) {
            newValue = [self.manager generateAppGroupUUID];
        } else if ([identifierType isEqualToString:@"StorageSystem"]) {
            // Get StorageManager class
            Class storageManagerClass = NSClassFromString(@"StorageManager");
            if (storageManagerClass && [storageManagerClass respondsToSelector:@selector(sharedManager)]) {
                id storageManager = [storageManagerClass sharedManager];
                if (storageManager) {
                    // Generate a random storage capacity (either 64GB or 128GB)
                    NSString *capacity = [storageManager respondsToSelector:@selector(randomizeStorageCapacity)] ? 
                                       [storageManager randomizeStorageCapacity] : @"64";
                    
                    // Generate the storage information based on the capacity
                    if ([storageManager respondsToSelector:@selector(generateStorageForCapacity:)]) {
                        NSDictionary *storageInfo = [storageManager generateStorageForCapacity:capacity];
                        if (storageInfo) {
                            // Update the StorageManager with the generated values
                            [storageManager setTotalStorageCapacity:storageInfo[@"TotalStorage"]];
                            [storageManager setFreeStorageSpace:storageInfo[@"FreeStorage"]];
                            [storageManager setFilesystemType:storageInfo[@"FilesystemType"]];
                            
                            // Format the value for display
                            newValue = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                      storageInfo[@"TotalStorage"], 
                                      storageInfo[@"FreeStorage"]];
                        }
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                BOOL use128GB = (arc4random_uniform(100) < 60);
                newValue = use128GB ? @"Total: 128 GB, Free: 38.4 GB" : @"Total: 64 GB, Free: 19.8 GB";
            }
        } else if ([identifierType isEqualToString:@"Battery"]) {
            // Get BatteryManager class
            Class batteryManagerClass = NSClassFromString(@"BatteryManager");
            if (batteryManagerClass && [batteryManagerClass respondsToSelector:@selector(sharedManager)]) {
                id batteryManager = [batteryManagerClass sharedManager];
                if (batteryManager && [batteryManager respondsToSelector:@selector(generateBatteryInfo)]) {
                    NSDictionary *batteryInfo = [batteryManager generateBatteryInfo];
                    if (batteryInfo) {
                        // Update display value - just show battery percentage now
                        NSString *level = batteryInfo[@"BatteryLevel"];
                        float levelFloat = [level floatValue];
                        int percentage = (int)(levelFloat * 100);
                        
                        newValue = [NSString stringWithFormat:@"%d%%", percentage];
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                int randomPercentage = 20 + arc4random_uniform(81); // 20-100%
                newValue = [NSString stringWithFormat:@"%d%%", randomPercentage];
            }
        } else if ([identifierType isEqualToString:@"SystemUptime"]) {
            NSString *profilePath = [self.manager profileIdentityPath];
            [[UptimeManager sharedManager] generateUptimeForProfile:profilePath];
            newValue = [self.manager currentValueForIdentifier:@"SystemUptime"];
        } else if ([identifierType isEqualToString:@"BootTime"]) {
            NSString *profilePath = [self.manager profileIdentityPath];
            [[UptimeManager sharedManager] generateBootTimeForProfile:profilePath];
            newValue = [self.manager currentValueForIdentifier:@"BootTime"];
        } else if ([identifierType isEqualToString:@"CoreDataUUID"]) {
            newValue = [self.manager generateCoreDataUUID];
        } else if ([identifierType isEqualToString:@"AppInstallUUID"]) {
            newValue = [self.manager generateAppInstallUUID];
        } else if ([identifierType isEqualToString:@"AppContainerUUID"]) {
            newValue = [self.manager generateAppContainerUUID];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Re-enable button
            sender.enabled = YES;
            [sender setTitle:@"Generate" forState:UIControlStateNormal];
            [sender setTintColor:originalColor];
            
            if ([self.manager lastError]) {
                [self showError:[self.manager lastError]];
                return;
            }
            
            // Save settings after generating new value
            [self.manager saveSettings];
            
            // Use our direct update method for immediate UI update
            [self directUpdateIdentifierValue:identifierType withValue:newValue];
            
            // Enable this identifier's switch if it's not already enabled
            UISwitch *identifierSwitch = self.identifierSwitches[identifierType];
            if (identifierSwitch && !identifierSwitch.isOn) {
                identifierSwitch.on = YES;
                [self.manager setIdentifierEnabled:YES forType:identifierType];
                [self.manager saveSettings];
                
                // Update the status label
                UIStackView *switchStatusStack = (UIStackView *)identifierSwitch.superview;
                if ([switchStatusStack isKindOfClass:[UIStackView class]]) {
                    UILabel *stateLabel = [switchStatusStack.arrangedSubviews filteredArrayUsingPredicate:
                        [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                            return [object isKindOfClass:[UILabel class]] && ((UILabel *)object).tag == 100;
                        }]].firstObject;
                    
                    if (stateLabel) {
                        stateLabel.text = @"Enabled";
                    }
                }
            }
            
            // Show success feedback
            [sender setTintColor:[UIColor systemGreenColor]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{
                    [sender setTintColor:originalColor];
                }];
            });
        });
    });
}

- (void)updateValueLabel:(NSString *)identifierType withValue:(NSString *)value {
    // Find the container view for this specific identifier type
    for (UIView *view in self.mainStackView.arrangedSubviews) {
        // Skip non-container views (like labels and spacers)
        if (![view isKindOfClass:[UIView class]] || 
            ![view.subviews.firstObject isKindOfClass:[UIVisualEffectView class]]) {
            continue;
        }
        
        // Get the content stack view
        UIStackView *contentStack = nil;
        for (UIView *subview in view.subviews) {
            if ([subview isKindOfClass:[UIStackView class]]) {
                contentStack = (UIStackView *)subview;
                break;
            }
        }
        
        if (!contentStack) continue;
        
        // Get the controls stack to find which identifier this is
        if (contentStack.arrangedSubviews.count < 2) continue;
        
        UIStackView *controlsStack = contentStack.arrangedSubviews.lastObject;
        if (![controlsStack isKindOfClass:[UIStackView class]]) continue;
        
        // Find the generate button to check its tag
        UIButton *generateButton = nil;
        for (UIView *control in controlsStack.arrangedSubviews) {
            if ([control isKindOfClass:[UIButton class]] && 
                [[(UIButton *)control currentTitle] isEqualToString:@"Generate"]) {
                generateButton = (UIButton *)control;
                break;
            }
        }
        
        if (!generateButton) continue;
        
        // Check if this is the container we want based on the tag
        BOOL isTargetContainer = (generateButton.tag == [self tagForIdentifierType:identifierType]);
        
        if (isTargetContainer) {
            // Get the identifier container
            if (contentStack.arrangedSubviews.count < 1) continue;
            
            UIView *identifierContainer = contentStack.arrangedSubviews.firstObject;
            if (![identifierContainer isKindOfClass:[UIView class]]) continue;
            
            // Get the identifier label
            UILabel *identifierLabel = nil;
            for (UIView *subview in identifierContainer.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    identifierLabel = (UILabel *)subview;
                    break;
                }
            }
            
            if (!identifierLabel) continue;
            
            // Update the label text with animation
            [UIView transitionWithView:identifierLabel
                              duration:0.3
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{
                                identifierLabel.text = value ?: @"Not Set";
                            }
                            completion:nil];
            
            // Also update the copy button's accessibility value
            UIButton *copyButton = controlsStack.arrangedSubviews.firstObject;
            if ([copyButton isKindOfClass:[UIButton class]]) {
                copyButton.accessibilityValue = value;
            }
            
            // Found and updated the target container, no need to continue
            break;
        }
    }
}

- (void)copyButtonTapped:(UIButton *)sender {
    NSString *value = sender.accessibilityValue;
    if (value && ![value isEqualToString:@"Not Set"]) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:value];
        
        // Enhanced visual feedback for copy action
        UIColor *originalColor = sender.tintColor;
        
        // Create a checkmark configuration for success feedback
        UIButtonConfiguration *originalConfig = sender.configuration;
        UIButtonConfiguration *successConfig = [originalConfig copy];
        successConfig.image = [UIImage systemImageNamed:@"checkmark"];
        successConfig.baseForegroundColor = [UIColor systemGreenColor];
        
        // Animate the change
        [UIView animateWithDuration:0.2 animations:^{
            sender.configuration = successConfig;
        } completion:^(BOOL finished) {
            // Show success state for a moment
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Animate back to original state
                [UIView animateWithDuration:0.2 animations:^{
                    UIButtonConfiguration *revertConfig = [originalConfig copy];
                    revertConfig.baseForegroundColor = originalColor;
                    sender.configuration = revertConfig;
                }];
            });
        }];
    }
}

#pragma mark - Button Actions

- (void)accountButtonTapped:(UIButton *)sender {
    // Access the tab bar controller and switch to the account tab
    UITabBarController *tabBarController = self.tabBarController;
    if ([tabBarController respondsToSelector:@selector(switchToAccountTab)]) {
        [tabBarController performSelector:@selector(switchToAccountTab)];
    } else {
        // Fallback to old method if for some reason the tabBarController doesn't have the method
        AccountViewController *accountVC = [[AccountViewController alloc] init];
        [self.navigationController pushViewController:accountVC animated:YES];
    }
}

#pragma mark - Installed Apps Popup

- (void)showInstalledAppsPopup:(UIButton *)sender {
    // Create popup view controller if not exists
    if (!self.installedAppsPopupVC) {
        self.installedAppsPopupVC = [[UIViewController alloc] init];
        self.installedAppsPopupVC.view.backgroundColor = [UIColor systemBackgroundColor];
        self.installedAppsPopupVC.modalPresentationStyle = UIModalPresentationFormSheet;
        self.installedAppsPopupVC.preferredContentSize = CGSizeMake(350, 500);
        
        // Add search bar
        self.appSearchBar = [[UISearchBar alloc] init];
        self.appSearchBar.placeholder = @"Search Apps";
        self.appSearchBar.delegate = self;
        self.appSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self.installedAppsPopupVC.view addSubview:self.appSearchBar];
        
        // Add close button
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        [closeButton addTarget:self action:@selector(closeInstalledAppsPopup:) forControlEvents:UIControlEventTouchUpInside];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.installedAppsPopupVC.view addSubview:closeButton];
        
        // Add table view
        self.installedAppsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        self.installedAppsTableView.delegate = self;
        self.installedAppsTableView.dataSource = self;
        self.installedAppsTableView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.installedAppsPopupVC.view addSubview:self.installedAppsTableView];
        
        // Setup constraints
        [NSLayoutConstraint activateConstraints:@[
            [closeButton.topAnchor constraintEqualToAnchor:self.installedAppsPopupVC.view.topAnchor constant:16],
            [closeButton.trailingAnchor constraintEqualToAnchor:self.installedAppsPopupVC.view.trailingAnchor constant:-16],
            
            [self.appSearchBar.topAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:8],
            [self.appSearchBar.leadingAnchor constraintEqualToAnchor:self.installedAppsPopupVC.view.leadingAnchor],
            [self.appSearchBar.trailingAnchor constraintEqualToAnchor:self.installedAppsPopupVC.view.trailingAnchor],
            
            [self.installedAppsTableView.topAnchor constraintEqualToAnchor:self.appSearchBar.bottomAnchor],
            [self.installedAppsTableView.leadingAnchor constraintEqualToAnchor:self.installedAppsPopupVC.view.leadingAnchor],
            [self.installedAppsTableView.trailingAnchor constraintEqualToAnchor:self.installedAppsPopupVC.view.trailingAnchor],
            [self.installedAppsTableView.bottomAnchor constraintEqualToAnchor:self.installedAppsPopupVC.view.bottomAnchor]
        ]];
        
        // Register cell
        [self.installedAppsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"InstalledAppCell"];
    }
    
    // Load installed apps
    [self loadInstalledApps];
    
    // Present popup
    [self presentViewController:self.installedAppsPopupVC animated:YES completion:nil];
}

- (void)loadInstalledApps {
    // Get all installed apps from LSApplicationWorkspace
    LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
    NSArray *installedApps = [workspace allInstalledApplications];
    NSMutableArray *apps = [NSMutableArray array];
    
    for (LSApplicationProxy *app in installedApps) {
        NSMutableDictionary *appInfo = [NSMutableDictionary dictionary];
        appInfo[@"name"] = app.localizedName ?: @"Unknown";
        appInfo[@"bundleID"] = app.bundleIdentifier ?: app.applicationIdentifier;
        appInfo[@"version"] = app.shortVersionString ?: @"1.0";
        [apps addObject:appInfo];
    }
    
    // Sort apps by name
    self.installedApps = [apps sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *app1, NSDictionary *app2) {
        return [app1[@"name"] compare:app2[@"name"]];
    }];
    self.filteredApps = self.installedApps;
    [self.installedAppsTableView reloadData];
}

- (void)closeInstalledAppsPopup:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchBar == self.versionSearchBar) {
        // Handle version search
        if (searchText.length == 0) {
            self.filteredVersions = self.appVersions;
        } else {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *version, NSDictionary *bindings) {
                NSString *versionString = version[@"version"];
                NSString *releaseDate = version[@"releaseDate"];
                
                // Format the date for display
                NSString *formattedDate = @"Unknown";
                if (![releaseDate isEqualToString:@"Unknown"]) {
                    // Try parsing as ISO 8601 date string first
                    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
                    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
                    NSDate *date = [isoFormatter dateFromString:releaseDate];
                    
                    // If that fails, try parsing as "yyyy-MM-dd HH:mm:ss" format
                    if (!date) {
                        NSDateFormatter *altFormatter = [[NSDateFormatter alloc] init];
                        altFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
                        date = [altFormatter dateFromString:releaseDate];
                    }
                    
                    // If that fails, try parsing as timestamp
                    if (!date && releaseDate.length > 0) {
                        NSTimeInterval timestamp = [releaseDate doubleValue];
                        if (timestamp > 0) {
                            date = [NSDate dateWithTimeIntervalSince1970:timestamp];
                        }
                    }
                    
                    if (date) {
                        formattedDate = [self.dateFormatter stringFromDate:date];
                    }
                }
                
                return [versionString localizedCaseInsensitiveContainsString:searchText] ||
                       [formattedDate localizedCaseInsensitiveContainsString:searchText];
            }];
            
            self.filteredVersions = [self.appVersions filteredArrayUsingPredicate:predicate];
        }
        [self.versionsTableView reloadData];
    } else if (searchBar == self.appSearchBar) {
        // Handle app search
        if (searchText.length == 0) {
            self.filteredApps = self.installedApps;
        } else {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR bundleID CONTAINS[cd] %@", searchText, searchText];
            self.filteredApps = [self.installedApps filteredArrayUsingPredicate:predicate];
        }
        [self.installedAppsTableView reloadData];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - App Versions Management

- (void)versionsButtonTapped:(UIButton *)sender {
    NSString *bundleID = self.appSwitches.allKeys[sender.tag];
    self.selectedBundleID = bundleID;
    
    // Create versions popup if not exists
    if (!self.versionsPopupVC) {
        self.versionsPopupVC = [[UIViewController alloc] init];
        self.versionsPopupVC.view.backgroundColor = [UIColor systemBackgroundColor];
        self.versionsPopupVC.modalPresentationStyle = UIModalPresentationFormSheet;
        self.versionsPopupVC.preferredContentSize = CGSizeMake(350, 500);
        
        // Add tap gesture recognizer to dismiss keyboard
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
        tapGesture.cancelsTouchesInView = NO;
        [self.versionsPopupVC.view addGestureRecognizer:tapGesture];
        
        // Title label
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"TAP ON APPNAME TO INSTALL";
        titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        titleLabel.textColor = [UIColor secondaryLabelColor];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.versionsPopupVC.view addSubview:titleLabel];
        
        // Add close button
        UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        [closeButton addTarget:self action:@selector(closeVersionsPopup:) forControlEvents:UIControlEventTouchUpInside];
        closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.versionsPopupVC.view addSubview:closeButton];
        
        // Add search bar
        self.versionSearchBar = [[UISearchBar alloc] init];
        self.versionSearchBar.placeholder = @"Search versions or dates";
        self.versionSearchBar.delegate = self;
        self.versionSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self.versionsPopupVC.view addSubview:self.versionSearchBar];
        
        // Add loading indicator
        UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        [self.versionsPopupVC.view addSubview:loadingIndicator];
        
        // Add table view
        self.versionsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        self.versionsTableView.delegate = self;
        self.versionsTableView.dataSource = self;
        self.versionsTableView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.versionsPopupVC.view addSubview:self.versionsTableView];
        
        // Setup constraints
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.versionsPopupVC.view.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-8],
            
            [closeButton.topAnchor constraintEqualToAnchor:self.versionsPopupVC.view.topAnchor constant:16],
            [closeButton.trailingAnchor constraintEqualToAnchor:self.versionsPopupVC.view.trailingAnchor constant:-16],
            
            [self.versionSearchBar.topAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:8],
            [self.versionSearchBar.leadingAnchor constraintEqualToAnchor:self.versionsPopupVC.view.leadingAnchor],
            [self.versionSearchBar.trailingAnchor constraintEqualToAnchor:self.versionsPopupVC.view.trailingAnchor],
            
            [loadingIndicator.centerXAnchor constraintEqualToAnchor:self.versionsPopupVC.view.centerXAnchor],
            [loadingIndicator.centerYAnchor constraintEqualToAnchor:self.versionsPopupVC.view.centerYAnchor],
            
            [self.versionsTableView.topAnchor constraintEqualToAnchor:self.versionSearchBar.bottomAnchor],
            [self.versionsTableView.leadingAnchor constraintEqualToAnchor:self.versionsPopupVC.view.leadingAnchor],
            [self.versionsTableView.trailingAnchor constraintEqualToAnchor:self.versionsPopupVC.view.trailingAnchor],
            [self.versionsTableView.bottomAnchor constraintEqualToAnchor:self.versionsPopupVC.view.bottomAnchor]
        ]];
        
        // Register cell
        [self.versionsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"VersionCell"];
        
        // Initialize date formatter
        self.dateFormatter = [[NSDateFormatter alloc] init];
        self.dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        self.dateFormatter.timeStyle = NSDateFormatterNoStyle;
    }
    
    // Show loading indicator
    UIActivityIndicatorView *loadingIndicator = [self.versionsPopupVC.view.subviews filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [object isKindOfClass:[UIActivityIndicatorView class]];
    }]].firstObject;
    [loadingIndicator startAnimating];
    self.versionsTableView.hidden = YES;
    
    // Present popup
    [self presentViewController:self.versionsPopupVC animated:YES completion:^{
        // Fetch versions
        [[AppVersionManager sharedManager] fetchVersionsForBundleID:bundleID completion:^(NSArray<NSDictionary *> *versions, NSError *error) {
            [loadingIndicator stopAnimating];
            self.versionsTableView.hidden = NO;
            
            if (error) {
                [self showError:error];
                return;
            }
            
            self.appVersions = versions;
            self.filteredVersions = versions;
            [self.versionsTableView reloadData];
        }];
    }];
}

- (void)closeVersionsPopup:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Clear Data Button

- (void)showProgressHUDWithTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressHUD) [self.progressHUD removeFromSuperview];
        self.progressHUD = [ProgressHUDView showHUDAddedTo:self.view title:title];
    });
}

- (void)updateProgress:(float)progress detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressHUD) {
            [self.progressHUD setProgress:progress animated:YES];
            [self.progressHUD setDetailText:detail];
        }
    });
}

- (void)hideProgressHUD {
    dispatch_async(dispatch_get_main_queue(), ^{
        [ProgressHUDView hideHUDForView:self.view];
        self.progressHUD = nil;
    });
}

- (void)clearDataButtonTapped:(UIButton *)sender {
    NSString *bundleID = self.appSwitches.allKeys[sender.tag];
    if (!bundleID) {
        return;
    }
    
    // --- Show progress HUD for data search ---
    [self showProgressHUDWithTitle:@"Fetching data..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block BOOL foundData = NO;
        // Simulate progress for data search (replace with real progress if possible)
        for (int i = 0; i <= 100; i += 10) {
            [self updateProgress:i/100.0 detail:[NSString stringWithFormat:@"Scanning... %d%%", i]];
            [NSThread sleepForTimeInterval:0.01];
        }
        foundData = [[AppDataCleaner sharedManager] hasDataToClear:bundleID];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideProgressHUD];
            // --- End progress HUD for data search ---

            // Check if there's data to clear
            if (!foundData) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Data"
                                                                             message:@"No app data found to clear."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:nil];
                [alert addAction:okAction];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }

            // Get data usage information from UserDefaults where AppDataCleaner stores it
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSDictionary *dataUsage = [defaults objectForKey:[NSString stringWithFormat:@"DataUsage_%@", bundleID]];
            // Format the data size for display
            NSString *dataSizeStr = @"Unknown size";
            if (dataUsage && dataUsage[@"totalSize"]) {
                long long totalSize = [dataUsage[@"totalSize"] longLongValue];
                NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
                formatter.countStyle = NSByteCountFormatterCountStyleFile;
                dataSizeStr = [formatter stringFromByteCount:totalSize];
            }
            NSString *dataDetailsStr = @"";
            if (dataUsage) {
                NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
                formatter.countStyle = NSByteCountFormatterCountStyleFile;
                if (dataUsage[@"dataSize"])
                    dataDetailsStr = [dataDetailsStr stringByAppendingFormat:@"\n• App Data: %@",
                                      [formatter stringFromByteCount:[dataUsage[@"dataSize"] longLongValue]]];
                if (dataUsage[@"sharedSize"])
                    dataDetailsStr = [dataDetailsStr stringByAppendingFormat:@"\n• Shared Data: %@",
                                     [formatter stringFromByteCount:[dataUsage[@"sharedSize"] longLongValue]]];
            }
            // Show confirmation alert with size info
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear App Data"
                                                                           message:[NSString stringWithFormat:@"Are you sure you want to clear all data for this app? This will remove %@.%@\n\nThis action cannot be undone.", dataSizeStr, dataDetailsStr]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                                 style:UIAlertActionStyleCancel
                                                               handler:nil];
            
            UIAlertAction *clearAction = [UIAlertAction actionWithTitle:@"Clear Data"
                                                                 style:UIAlertActionStyleDestructive
                                                               handler:^(UIAlertAction * _Nonnull action) {
                // Disable the button temporarily
                sender.enabled = NO;
                [sender setTintColor:[UIColor systemGrayColor]];
                // --- Show progress HUD for data clearing ---
                [self showProgressHUDWithTitle:@"Clearing data..."];
                // Simulate progress for cleaning (replace with real progress if possible)
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    for (int i = 0; i <= 100; i += 10) {
                        [self updateProgress:i/100.0 detail:[NSString stringWithFormat:@"Deleting... %d%%", i]];
                        [NSThread sleepForTimeInterval:0.01];
                    }
                    // Clear the data
                    [[AppDataCleaner sharedManager] clearDataForBundleID:bundleID completion:^(BOOL success, NSError *error) {
                        [self hideProgressHUD];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // Re-enable the button
                            sender.enabled = YES;
                            [sender setTintColor:[UIColor systemRedColor]];
                            if (!success) {
                                [self showError:error];
                                return;
                            }
                            // Get results of the cleaning operation from UserDefaults
                            NSDictionary *cleaningResult = [defaults objectForKey:[NSString stringWithFormat:@"DataCleaningResult_%@", bundleID]];
                            NSString *resultMessage = @"App data has been cleared successfully.";
                            if (cleaningResult) {
                                NSDictionary *beforeSize = cleaningResult[@"beforeSize"];
                                NSDictionary *afterSize = cleaningResult[@"afterSize"];
                                if (beforeSize && afterSize && beforeSize[@"totalSize"] && afterSize[@"totalSize"]) {
                                    long long clearedBytes = [beforeSize[@"totalSize"] longLongValue] - [afterSize[@"totalSize"] longLongValue];
                                    if (clearedBytes > 0) {
                                        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
                                        formatter.countStyle = NSByteCountFormatterCountStyleFile;
                                        NSString *clearedSizeStr = [formatter stringFromByteCount:clearedBytes];
                                        resultMessage = [NSString stringWithFormat:@"Successfully cleared %@ of app data.", clearedSizeStr];
                                    }
                                }
                            }
                            // Show success message
                            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                                                   message:resultMessage
                                                                                            preferredStyle:UIAlertControllerStyleAlert];
                            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
                            [successAlert addAction:okAction];
                            [self presentViewController:successAlert animated:YES completion:nil];
                        });
                    }];
                });
            }];
            [alert addAction:cancelAction];
            [alert addAction:clearAction];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)deleteAppButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.appSwitches.allKeys.count) {
        return;
    }
    
    NSString *bundleID = self.appSwitches.allKeys[index];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove App"
                                                                   message:[NSString stringWithFormat:@"Are you sure you want to remove %@ from the scoped apps list?", bundleID]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self.manager removeApplicationFromScope:bundleID];
        [self updateAppsList];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)installAppWithAdamId:(NSString *)adamId appExtVrsId:(NSString *)appExtVrsId bundleID:(NSString *)bundleID appName:(NSString *)appName version:(NSString *)version {
    // This is the exact method MuffinStore uses
    NSString *urlString = [NSString stringWithFormat:@"itms-apps://buy.itunes.apple.com/WebObjects/MZBuy.woa/wa/buyProduct?id=%@&mt=8&appExtVrsId=%@", 
                          adamId, appExtVrsId];
    NSURL *url = [NSURL URLWithString:urlString];
    
    // MuffinStore uses this exact method to open the URL
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) {
            // Show success alert
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *truncatedAppName = appName;
                if (appName.length > 15) {
                    truncatedAppName = [NSString stringWithFormat:@"%@...", [appName substringToIndex:15]];
                }
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Installation Started"
                                                                              message:[NSString stringWithFormat:@"%@ version %@ is being installed.", truncatedAppName, version]
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            });
        } else {
            // Show error alert
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Installation Failed"
                                                                              message:@"Failed to initiate installation. Please try again."
                                                                       preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            });
        }
    }];
}

- (void)installButtonTapped:(UIButton *)sender {
    // Check if the sender tag is valid
    if (sender.tag < 0 || sender.tag >= self.filteredVersions.count) {
        return;
    }
    
    // Get the selected version
    NSDictionary *selectedVersion = self.filteredVersions[sender.tag];
    
    // Extract required information
    NSString *bundleID = selectedVersion[@"bundleId"];
    NSNumber *trackIdNum = selectedVersion[@"trackId"];
    NSNumber *externalIdNum = selectedVersion[@"external_identifier"];
    NSString *appName = selectedVersion[@"appName"];
    NSString *versionString = selectedVersion[@"version"];
    
    // Check if we have all required information
    if (!bundleID || !trackIdNum || !externalIdNum || !appName || !versionString) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" 
                                                                       message:@"Missing required app information" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Convert track ID and external ID to strings
    NSString *trackId = [trackIdNum stringValue];
    NSString *externalId = [externalIdNum stringValue];
    
    // Temporarily disable the button and update its title
    sender.enabled = NO;
    NSString *originalButtonTitle = [sender titleForState:UIControlStateNormal];
    [sender setTitle:@"Installing..." forState:UIControlStateNormal];
    
    // Use the MuffinStore-style installation method
    [self installAppWithAdamId:trackId appExtVrsId:externalId bundleID:bundleID appName:appName version:versionString];
    
    // Re-enable the button after a short delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sender.enabled = YES;
        [sender setTitle:originalButtonTitle forState:UIControlStateNormal];
    });
}

- (UIImage *)createNotInAppStoreImage {
    // Create a context with a transparent background
    CGSize size = CGSizeMake(200, 200);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    
    // Setup text attributes
    NSString *text = @"App Not In AppStore";
    UIFont *font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor.labelColor colorWithAlphaComponent:3],
        NSParagraphStyleAttributeName: paragraphStyle
    };
    
    // Calculate text size and position
    CGRect textRect = [text boundingRectWithSize:size
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:attributes
                                         context:nil];
    
    CGRect drawRect = CGRectMake((size.width - textRect.size.width) / 2,
                                 (size.height - textRect.size.height) / 2,
                                 textRect.size.width,
                                 textRect.size.height);
    
    // Draw the text
    [text drawInRect:drawRect withAttributes:attributes];
    
    // Get the image and end the context
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

- (void)fetchAppIconForBundleID:(NSString *)bundleID completion:(void (^)(UIImage *icon))completion {
    // Check cache first
    UIImage *cachedIcon = [self.iconCache objectForKey:bundleID];
    if (cachedIcon) {
        completion(cachedIcon);
        return;
    }
    
    // Construct iTunes lookup URL
    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@", bundleID];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImage *notFoundImage = [self createNotInAppStoreImage];
                [self.iconCache setObject:notFoundImage forKey:bundleID];
                completion(notFoundImage);
            });
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImage *notFoundImage = [self createNotInAppStoreImage];
                [self.iconCache setObject:notFoundImage forKey:bundleID];
                completion(notFoundImage);
            });
            return;
        }
        
        NSArray *results = json[@"results"];
        if (![results isKindOfClass:[NSArray class]] || results.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImage *notFoundImage = [self createNotInAppStoreImage];
                [self.iconCache setObject:notFoundImage forKey:bundleID];
                completion(notFoundImage);
            });
            return;
        }
        
        NSDictionary *appInfo = results.firstObject;
        NSString *iconURLString = appInfo[@"artworkUrl512"];
        if (!iconURLString) {
            iconURLString = appInfo[@"artworkUrl100"];
        }
        
        if (!iconURLString) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImage *notFoundImage = [self createNotInAppStoreImage];
                [self.iconCache setObject:notFoundImage forKey:bundleID];
                completion(notFoundImage);
            });
            return;
        }
        
        NSURL *iconURL = [NSURL URLWithString:iconURLString];
        [[session dataTaskWithURL:iconURL completionHandler:^(NSData *iconData, NSURLResponse *iconResponse, NSError *iconError) {
            UIImage *icon = nil;
            if (!iconError && iconData) {
                icon = [UIImage imageWithData:iconData];
                if (icon) {
                    [self.iconCache setObject:icon forKey:bundleID];
                } else {
                    icon = [self createNotInAppStoreImage];
                    [self.iconCache setObject:icon forKey:bundleID];
                }
            } else {
                icon = [self createNotInAppStoreImage];
                [self.iconCache setObject:icon forKey:bundleID];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(icon);
            });
        }] resume];
    }] resume];
}

- (void)directUpdateIdentifierValue:(NSString *)identifierType withValue:(NSString *)value {
    // Find all identifier cells
    BOOL foundContainer = NO;
    
    for (UIView *view in self.mainStackView.arrangedSubviews) {
        // Skip if not a view or doesn't have subviews
        if (![view isKindOfClass:[UIView class]] || view.subviews.count == 0) {
            continue;
        }
        
        // Find the content stack view
        UIStackView *contentStack = nil;
        for (UIView *subview in view.subviews) {
            if ([subview isKindOfClass:[UIStackView class]]) {
                contentStack = (UIStackView *)subview;
                break;
            }
        }
        
        if (!contentStack || contentStack.arrangedSubviews.count < 2) {
            continue;
        }
        
        // Get the controls stack
        UIStackView *controlsStack = contentStack.arrangedSubviews.lastObject;
        if (![controlsStack isKindOfClass:[UIStackView class]]) continue;
        
        // Find the generate button to check its tag
        UIButton *generateButton = nil;
        for (UIView *control in controlsStack.arrangedSubviews) {
            if ([control isKindOfClass:[UIButton class]]) {
                UIButton *button = (UIButton *)control;
                NSString *buttonTitle = [button titleForState:UIControlStateNormal];
                if ([buttonTitle isEqualToString:@"Generate"] || 
                    [button.configuration.title isEqualToString:@"Generate"]) {
                    generateButton = button;
                    break;
                }
            }
        }
        
        if (!generateButton) {
            continue;
        }
        
        // Check if this is the container we want based on the tag
        BOOL isTargetContainer = (generateButton.tag == [self tagForIdentifierType:identifierType]);
        
        if (isTargetContainer) {
            NSLog(@"[WeaponX] ✅ Found container for %@ (tag: %ld)", identifierType, (long)generateButton.tag);
            foundContainer = YES;
            
            // Get the identifier container (first subview in content stack)
            UIView *identifierContainer = contentStack.arrangedSubviews.firstObject;
            if (![identifierContainer isKindOfClass:[UIView class]]) {
                NSLog(@"[WeaponX] ❌ Identifier container is not a UIView");
                continue;
            }
            
            // Find the label within the container
            UILabel *identifierLabel = nil;
            for (UIView *subview in identifierContainer.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    identifierLabel = (UILabel *)subview;
                    break;
                }
            }
            
            if (identifierLabel) {
                NSLog(@"[WeaponX] 🔄 Updating label from '%@' to '%@'", identifierLabel.text, value);
                
                // Ensure the update happens on the main thread
                if ([NSThread isMainThread]) {
                    identifierLabel.text = value ?: @"Not Set";
                    NSLog(@"[WeaponX] ✅ Label updated directly on main thread");
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        identifierLabel.text = value ?: @"Not Set";
                        NSLog(@"[WeaponX] ✅ Label updated via dispatch to main thread");
                    });
                }
                
                // Update the copy button's accessibility value
                UIButton *copyButton = controlsStack.arrangedSubviews.firstObject;
                if ([copyButton isKindOfClass:[UIButton class]]) {
                    copyButton.accessibilityValue = value;
                }
                
                return;
            } else {
                NSLog(@"[WeaponX] ❌ Could not find label in container");
            }
        }
    }
    
    if (!foundContainer) {
        NSLog(@"[WeaponX] ❌ Could not find container for %@", identifierType);
    }
}

- (void)generateAllButtonTapped:(UIButton *)sender {
    // Check if user has an active plan
    BOOL isRestricted = [[NSUserDefaults standardUserDefaults] boolForKey:@"WeaponXRestrictedAccess"];
    
    // Also check associated object as a backup
    if (!isRestricted) {
        UIViewController *topVC = [self findTopViewController];
        NSNumber *restrictedAccess = objc_getAssociatedObject(topVC, "WeaponXRestrictedAccess");
        isRestricted = restrictedAccess ? [restrictedAccess boolValue] : NO;
    }
    
    // If user doesn't have an active plan, show alert and prevent action
    if (isRestricted) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Access Restricted" 
            message:@"Please subscribe to a plan to use the generate feature." 
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"View Plans" 
            style:UIAlertActionStyleDefault 
            handler:^(UIAlertAction * _Nonnull action) {
                // Switch to account tab to view plans
                UITabBarController *tabController = [self findTabBarController];
                if ([tabController respondsToSelector:@selector(switchToAccountTab)]) {
                    [tabController performSelector:@selector(switchToAccountTab)];
                }
            }]];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"Cancel" 
            style:UIAlertActionStyleCancel 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Disable button temporarily
    sender.enabled = NO;
    
    // Show loading state
    UIColor *originalColor = sender.tintColor;
    [sender setTintColor:[UIColor systemGrayColor]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Regenerate all enabled identifiers
        [self.manager regenerateAllEnabledIdentifiers];
        
        // Get the new values for UI update
        NSString *newIDFA = [self.manager currentValueForIdentifier:@"IDFA"];
        NSString *newIDFV = [self.manager currentValueForIdentifier:@"IDFV"];
        NSString *newDeviceName = [self.manager currentValueForIdentifier:@"DeviceName"];
        NSString *newSerialNumber = [self.manager currentValueForIdentifier:@"SerialNumber"];
        NSString *newIOSVersion = [self.manager currentValueForIdentifier:@"IOSVersion"];
        NSString *newWiFiInfo = [self.manager currentValueForIdentifier:@"WiFi"];
        NSString *newStorageInfo = [self.manager currentValueForIdentifier:@"StorageSystem"];
        NSString *newBatteryInfo = [self.manager currentValueForIdentifier:@"Battery"];
        NSString *newSystemBootUUID = [self.manager currentValueForIdentifier:@"SystemBootUUID"];
        NSString *newDyldCacheUUID = [self.manager currentValueForIdentifier:@"DyldCacheUUID"];
        NSString *newPasteboardUUID = [self.manager currentValueForIdentifier:@"PasteboardUUID"];
        NSString *newKeychainUUID = [self.manager currentValueForIdentifier:@"KeychainUUID"];
        NSString *newUserDefaultsUUID = [self.manager currentValueForIdentifier:@"UserDefaultsUUID"];
        NSString *newAppGroupUUID = [self.manager currentValueForIdentifier:@"AppGroupUUID"];
        NSString *newDeviceModel = [self.manager currentValueForIdentifier:@"DeviceModel"];
        [self.manager generateSystemUptime];
        [self.manager generateBootTime];
        NSString *newSystemUptime = [self.manager currentValueForIdentifier:@"SystemUptime"];
        NSString *newBootTime = [self.manager currentValueForIdentifier:@"BootTime"];
        NSString *newCoreDataUUID = [self.manager generateCoreDataUUID];
        NSString *newAppInstallUUID = [self.manager currentValueForIdentifier:@"AppInstallUUID"];
        NSString *newAppContainerUUID = [self.manager currentValueForIdentifier:@"AppContainerUUID"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Re-enable button
            sender.enabled = YES;
            [sender setTintColor:originalColor];
            
            // Update UI with new values
            if ([self.manager isIdentifierEnabled:@"IDFA"]) {
                [self directUpdateIdentifierValue:@"IDFA" withValue:newIDFA];
            }
            
            if ([self.manager isIdentifierEnabled:@"IDFV"]) {
                [self directUpdateIdentifierValue:@"IDFV" withValue:newIDFV];
            }
            
            if ([self.manager isIdentifierEnabled:@"DeviceName"]) {
                [self directUpdateIdentifierValue:@"DeviceName" withValue:newDeviceName];
            }
            
            if ([self.manager isIdentifierEnabled:@"SerialNumber"]) {
                [self directUpdateIdentifierValue:@"SerialNumber" withValue:newSerialNumber];
            }
            
            if ([self.manager isIdentifierEnabled:@"IOSVersion"]) {
                [self directUpdateIdentifierValue:@"IOSVersion" withValue:newIOSVersion];
            }
            
            if ([self.manager isIdentifierEnabled:@"WiFi"]) {
                [self directUpdateIdentifierValue:@"WiFi" withValue:newWiFiInfo];
            }
            
            if ([self.manager isIdentifierEnabled:@"StorageSystem"]) {
                [self directUpdateIdentifierValue:@"StorageSystem" withValue:newStorageInfo];
            }
            
            if ([self.manager isIdentifierEnabled:@"Battery"]) {
                [self directUpdateIdentifierValue:@"Battery" withValue:newBatteryInfo];
            }
            
            if ([self.manager isIdentifierEnabled:@"SystemBootUUID"]) {
                [self directUpdateIdentifierValue:@"SystemBootUUID" withValue:newSystemBootUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"DyldCacheUUID"]) {
                [self directUpdateIdentifierValue:@"DyldCacheUUID" withValue:newDyldCacheUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"PasteboardUUID"]) {
                [self directUpdateIdentifierValue:@"PasteboardUUID" withValue:newPasteboardUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"KeychainUUID"]) {
                [self directUpdateIdentifierValue:@"KeychainUUID" withValue:newKeychainUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"UserDefaultsUUID"]) {
                [self directUpdateIdentifierValue:@"UserDefaultsUUID" withValue:newUserDefaultsUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"AppGroupUUID"]) {
                [self directUpdateIdentifierValue:@"AppGroupUUID" withValue:newAppGroupUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"SystemUptime"]) {
                [self directUpdateIdentifierValue:@"SystemUptime" withValue:newSystemUptime];
            }
            
            if ([self.manager isIdentifierEnabled:@"BootTime"]) {
                [self directUpdateIdentifierValue:@"BootTime" withValue:newBootTime];
            }
            
            if ([self.manager isIdentifierEnabled:@"CoreDataUUID"]) {
                [self directUpdateIdentifierValue:@"CoreDataUUID" withValue:newCoreDataUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"AppInstallUUID"]) {
                [self directUpdateIdentifierValue:@"AppInstallUUID" withValue:newAppInstallUUID];
            }
            
            if ([self.manager isIdentifierEnabled:@"AppContainerUUID"]) {
                [self directUpdateIdentifierValue:@"AppContainerUUID" withValue:newAppContainerUUID];
            }
            
            // Always update the device model
            [self directUpdateIdentifierValue:@"DeviceModel" withValue:newDeviceModel];
            
            if ([self.manager isIdentifierEnabled:@"SystemUptime"]) {
                [self directUpdateIdentifierValue:@"SystemUptime" withValue:newSystemUptime];
            }
            
            // Show success feedback
            UIAlertController *alert = [UIAlertController 
                alertControllerWithTitle:@"Success" 
                message:@"All enabled identifiers have been regenerated" 
                preferredStyle:UIAlertControllerStyleAlert];
            
            [self presentViewController:alert animated:YES completion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [alert dismissViewControllerAnimated:YES completion:nil];
                });
            }];
        });
    });
}

#pragma mark - UIScrollViewDelegate

// Trial offer banner methods
- (void)setupTrialOfferBanner {
    // Check if we should show the offer
    BOOL shouldShow = [self shouldShowTrialOffer];
    
    if (!shouldShow) {
        return;
    }
    
    // Check if banner already exists - don't create duplicates
    if (self.trialOfferBannerView) {
        return;
    }
    
    // Create the banner view with futuristic design
    self.trialOfferBannerView = [[UIView alloc] init];
    self.trialOfferBannerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.trialOfferBannerView.layer.cornerRadius = 16.0;
    self.trialOfferBannerView.clipsToBounds = YES;
    
    // Create gradient background
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = CGRectMake(0, 0, self.view.bounds.size.width - 40, 120);
    gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    
    // Use system colors that adapt to light/dark mode
    if (@available(iOS 13.0, *)) {
        UIColor *startColor = [UIColor systemBlueColor];
        UIColor *endColor = [UIColor systemIndigoColor];
        gradientLayer.colors = @[
            (id)[startColor colorWithAlphaComponent:0.9].CGColor,
            (id)[endColor colorWithAlphaComponent:0.9].CGColor
        ];
    } else {
        gradientLayer.colors = @[
            (id)[[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9] CGColor],
            (id)[[UIColor colorWithRed:0.3 green:0.2 blue:0.8 alpha:0.9] CGColor]
        ];
    }
    
    [self.trialOfferBannerView.layer insertSublayer:gradientLayer atIndex:0];
    
    // Create content container
    UIView *contentContainer = [[UIView alloc] init];
    contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    contentContainer.backgroundColor = [UIColor clearColor];
    [self.trialOfferBannerView addSubview:contentContainer];
    
    // Create title label with glow effect
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"SPECIAL OFFER";
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    
    // Add subtle shadow for glow effect
    titleLabel.layer.shadowColor = [UIColor whiteColor].CGColor;
    titleLabel.layer.shadowOffset = CGSizeZero;
    titleLabel.layer.shadowRadius = 10.0;
    titleLabel.layer.shadowOpacity = 0.4;
    [contentContainer addSubview:titleLabel];
    
    // Create subtitle label
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"Experience all features with our free trial plan!";
    subtitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    subtitleLabel.textColor = [UIColor whiteColor];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.numberOfLines = 0;
    [contentContainer addSubview:subtitleLabel];
    
    // Create get trial button with modern style
    self.getTrialButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.getTrialButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.getTrialButton setTitle:@"GET TRIAL" forState:UIControlStateNormal];
    [self.getTrialButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.getTrialButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    
    // Create pillbox shape with glassy background
    self.getTrialButton.layer.cornerRadius = 18.0;
    self.getTrialButton.clipsToBounds = YES;
    
    // Glassy background
    self.getTrialButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    
    // Add highlight effect
    UIView *highlightView = [[UIView alloc] init];
    highlightView.translatesAutoresizingMaskIntoConstraints = NO;
    highlightView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    highlightView.layer.cornerRadius = 18.0;
    highlightView.clipsToBounds = YES;
    highlightView.userInteractionEnabled = NO;
    
    // Create inner shadow for button
    CALayer *innerShadow = [CALayer layer];
    innerShadow.frame = CGRectMake(0, 0, 140, 36);
    innerShadow.shadowColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    innerShadow.shadowOffset = CGSizeMake(0, 1);
    innerShadow.shadowOpacity = 0.5;
    innerShadow.shadowRadius = 3;
    
    // Set action for button
    [self.getTrialButton addTarget:self action:@selector(getTrialButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    [contentContainer addSubview:self.getTrialButton];
    [self.getTrialButton addSubview:highlightView];
    
    // Add the banner to the view hierarchy at the top
    if (self.mainStackView && self.mainStackView.arrangedSubviews.count > 0) {
        [self.mainStackView insertArrangedSubview:self.trialOfferBannerView atIndex:0];
    } else {
        return;
    }
    
    // Set up constraints
    [NSLayoutConstraint activateConstraints:@[
        // Content container constraints
        [contentContainer.topAnchor constraintEqualToAnchor:self.trialOfferBannerView.topAnchor],
        [contentContainer.leadingAnchor constraintEqualToAnchor:self.trialOfferBannerView.leadingAnchor],
        [contentContainer.trailingAnchor constraintEqualToAnchor:self.trialOfferBannerView.trailingAnchor],
        [contentContainer.bottomAnchor constraintEqualToAnchor:self.trialOfferBannerView.bottomAnchor],
        
        // Title label constraints
        [titleLabel.topAnchor constraintEqualToAnchor:contentContainer.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-16],
        
        // Subtitle label constraints
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:16],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-16],
        
        // Get trial button constraints
        [self.getTrialButton.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:12],
        [self.getTrialButton.centerXAnchor constraintEqualToAnchor:contentContainer.centerXAnchor],
        [self.getTrialButton.widthAnchor constraintEqualToConstant:140],
        [self.getTrialButton.heightAnchor constraintEqualToConstant:36],
        [self.getTrialButton.bottomAnchor constraintEqualToAnchor:contentContainer.bottomAnchor constant:-16],
        
        // Highlight view constraints (partial overlay for glass effect)
        [highlightView.topAnchor constraintEqualToAnchor:self.getTrialButton.topAnchor],
        [highlightView.leadingAnchor constraintEqualToAnchor:self.getTrialButton.leadingAnchor],
        [highlightView.trailingAnchor constraintEqualToAnchor:self.getTrialButton.trailingAnchor],
        [highlightView.heightAnchor constraintEqualToConstant:18], // Half height for highlight
    ]];
}

// Method to reset trial offer status for testing
- (void)resetTrialOfferStatus {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"WeaponXHasShownTrialOffer"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"WeaponXTrialOfferShownDate"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Force banner to show again
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.trialOfferBannerView) {
            [self hideTrialOfferBanner];
        }
        [self setupTrialOfferBanner];
    });
}

- (BOOL)shouldShowTrialOffer {
    // 1. Only show in online mode - use offline banner indicator logic for consistency
    if (![self isNetworkAvailable]) {
        return NO;
    }
    
    // 2. Never show for users with active plans - use existing plan flags
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasActivePlan = [defaults boolForKey:@"WeaponXHasActivePlan"];
    BOOL isRestricted = [defaults boolForKey:@"WeaponXRestrictedAccess"];
    BOOL hasPlan = hasActivePlan || !isRestricted;
    
    if (hasPlan) {
        return NO;
    }
    
    // Check if banner has been permanently hidden after 12 hours total display
    BOOL permanentlyHidden = [defaults boolForKey:@"WeaponXTrialOfferPermanentlyHidden"];
    if (permanentlyHidden) {
        return NO;
    }
    
    // 3. Check if already shown for 12 hours total using accumulated display time
    NSNumber *totalDisplayTime = [defaults objectForKey:@"WeaponXTrialTotalDisplayTime"];
    if (totalDisplayTime && [totalDisplayTime doubleValue] > 43200) { // 12 hours = 43200 seconds
        // Mark as permanently hidden
        [defaults setBool:YES forKey:@"WeaponXTrialOfferPermanentlyHidden"];
        [defaults synchronize];
        return NO;
    }
    
    // 4. Only show to users registered max 2 days ago
    NSDate *userRegistrationDate = [[APIManager sharedManager] userRegistrationDate];
    if (!userRegistrationDate) {
        // Check if user is new based on plan_id = 0
        NSDictionary *userData = [defaults dictionaryForKey:@"WeaponXUserData"];
        if (!(userData && [userData[@"plan_id"] intValue] == 0)) {
            return NO;
        }
    } else {
        // Get the server time if available, otherwise use device time
        NSDate *serverTime = [defaults objectForKey:@"WeaponXServerTime"];
        NSDate *comparisonTime = serverTime ? serverTime : [NSDate date];
        
        // Calculate how long the user has been registered (2 days = 172800 seconds)
        NSTimeInterval timeRegistered = [comparisonTime timeIntervalSinceDate:userRegistrationDate];
        
        if (timeRegistered > 172800) { // 2 days
            return NO;
        }
    }
    
    // If this is the first time showing the banner, record the timestamp
    NSDate *firstShownDate = [defaults objectForKey:@"WeaponXTrialOfferFirstShownDate"];
    if (!firstShownDate) {
        // Use server time if available for recording first shown time
        NSDate *serverTime = [defaults objectForKey:@"WeaponXServerTime"];
        NSDate *currentTime = serverTime ? serverTime : [NSDate date];
        
        [defaults setObject:currentTime forKey:@"WeaponXTrialOfferFirstShownDate"];
        [defaults synchronize];
    }
    
    // Check with server for eligibility
    [self performServerEligibilityCheck];
    
    return YES;
}

- (BOOL)isNetworkAvailable {
    // Use the APIManager's network availability check for consistency with offline banner
    return [[APIManager sharedManager] isNetworkAvailable];
}

- (BOOL)checkTrialOfferEligibility {
    // First, check if user has an active plan
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hasActivePlan = [defaults boolForKey:@"WeaponXHasActivePlan"];
    BOOL isRestricted = [defaults boolForKey:@"WeaponXRestrictedAccess"];
    BOOL hasPlan = hasActivePlan || !isRestricted;
    
    if (hasPlan) {
        return NO;
    }
    
    // Get the user's registration date
    NSDate *userRegistrationDate = [[APIManager sharedManager] userRegistrationDate];
    if (!userRegistrationDate) {
        return NO;
    }
    
    // Calculate how long the user has been registered
    NSTimeInterval timeRegistered = [[NSDate date] timeIntervalSinceDate:userRegistrationDate];
    
    // Only show to users who registered within the last 3 days (259200 seconds)
    if (timeRegistered > 259200) {
        return NO;
    }
    
    // Check with server if this user is eligible for a trial
    [self performServerEligibilityCheck];
    
    // For now, assume eligible until server responds
    return YES;
}

- (void)performServerEligibilityCheck {
    // TEMPORARY FIX: For testing, always assume server says user is eligible
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"WeaponXTrialEligible"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
    
    // Original implementation commented out for testing
    /*
    // Get user ID and token for authentication
    NSString *userId = [[TokenManager sharedInstance] getServerUserId];
    NSString *token = [[TokenManager sharedInstance] token];
    
    if (!userId || !token) {
        // Handle error - hide banner if already showing
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.trialOfferBannerView) {
                [self hideTrialOfferBanner];
            }
        });
        return;
    }
    
    // Create request to check eligibility
    NSString *url = [NSString stringWithFormat:@"%@/api/trial/eligibility/%@", 
                    [[APIManager sharedManager] baseURL], userId];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"GET"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    
    // Create a URL session for this request
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            // On network error, if banner is already showing, keep it
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        BOOL isEligible = NO;
        
        if (httpResponse.statusCode == 200 && data) {
            // Parse response
            NSError *jsonError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (!jsonError && responseDict) {
                // Update UI on main thread based on response
                isEligible = [responseDict[@"eligible"] boolValue];
                
                // Store eligibility result for future reference
                [[NSUserDefaults standardUserDefaults] setBool:isEligible forKey:@"WeaponXTrialEligible"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            } else {
                // If we can't parse the response but banner is already showing, keep it
                return;
            }
        } else {
            // If server error but banner is already showing, keep it
            return;
        }
        
        // Update UI based on eligibility
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!isEligible && self.trialOfferBannerView) {
                // User is not eligible, hide the banner
                [self hideTrialOfferBanner];
            } else if (isEligible) {
                // User is eligible, ensure banner is shown
                if (!self.trialOfferBannerView) {
                    [self setupTrialOfferBanner];
                }
            }
        });
    }];
    
    [task resume];
    */
}

- (void)getTrialButtonTapped {
    // Show loading state on button
    [self.getTrialButton setTitle:@"PROCESSING..." forState:UIControlStateNormal];
    self.getTrialButton.enabled = NO;
    
    // Create a simple CSRF token (in a production app, this would be securely obtained from the server)
    NSString *csrfToken = [NSUUID UUID].UUIDString;
    
    // Proceed with purchase using the token
    [self purchaseTrialPlanWithCSRFToken:csrfToken];
}

- (void)purchaseTrialPlanWithCSRFToken:(NSString *)csrfToken {
    // Get user ID and token for authentication
    // Use TokenManager instead of direct NSUserDefaults access
    NSString *userId = [[TokenManager sharedInstance] getServerUserId];
    NSString *token = [[TokenManager sharedInstance] token];
    
    if (!userId || !token) {
        NSLog(@"[WeaponX] Missing userId or token for trial purchase");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showPurchaseError:@"Authentication error. Please log in again."];
            [self.getTrialButton setTitle:@"GET TRIAL" forState:UIControlStateNormal];
            self.getTrialButton.enabled = YES;
        });
        return;
    }
    
    NSLog(@"[WeaponX] Purchasing trial plan for user ID: %@", userId);
    
    // Use the APIManager to purchase the plan instead of implementing the logic again
    [[APIManager sharedManager] purchasePlanWithToken:token planId:@"1" completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                // Purchase successful, hide banner and show success message
                [self showPurchaseSuccess:@"Trial plan activated successfully!"];
                
                // Save user plan status
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"WeaponXUserHasPlan"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                
                // Hide the banner with animation
                [self hideTrialOfferBanner];
            } else {
                // Purchase failed
                NSString *errorMessage = error ? error.localizedDescription : @"Error processing purchase.";
                [self showPurchaseError:errorMessage];
                [self.getTrialButton setTitle:@"GET TRIAL" forState:UIControlStateNormal];
                self.getTrialButton.enabled = YES;
            }
        });
    }];
}

- (void)showPurchaseSuccess:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showPurchaseError:(NSString *)errorMessage {
    // Always append contact support for plan purchase failures
    NSString *fullMessage = [NSString stringWithFormat:@"%@\n\nPlease contact support.", errorMessage];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Purchase Error" 
                                                                   message:fullMessage
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)hideTrialOfferBanner {
    if (!self.trialOfferBannerView) {
        return;
    }
    
    // Track when the banner was hidden for accurate 12-hour total display time
    NSDate *lastShownDate = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXTrialOfferShownDate"];
    if (lastShownDate) {
        // Calculate time displayed in this session
        NSTimeInterval displayTime = [[NSDate date] timeIntervalSinceDate:lastShownDate];
        
        // Get existing total display time or initialize to zero
        NSNumber *totalDisplayTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXTrialTotalDisplayTime"];
        NSTimeInterval newTotalTime = (totalDisplayTime ? [totalDisplayTime doubleValue] : 0) + displayTime;
        
        // Store updated total display time
        [[NSUserDefaults standardUserDefaults] setObject:@(newTotalTime) forKey:@"WeaponXTrialTotalDisplayTime"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // If total display time exceeds 12 hours (43200 seconds), never show again
        if (newTotalTime > 43200) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"WeaponXTrialOfferPermanentlyHidden"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    
    // Animate the banner removal
    [UIView animateWithDuration:0.3 animations:^{
        self.trialOfferBannerView.alpha = 0.0;
        self.trialOfferBannerView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self.trialOfferBannerView removeFromSuperview];
        self.trialOfferBannerView = nil;
        self.getTrialButton = nil;
    }];
}

- (void)showTrialBannerDebugInfo:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        NSString *bannerStatus = self.trialOfferBannerView ? @"Banner is SHOWING" : @"Banner is NOT showing";
        
        // Get status values
        BOOL hasShownBefore = [[NSUserDefaults standardUserDefaults] boolForKey:@"WeaponXHasShownTrialOffer"];
        NSDate *lastShownDate = [[NSUserDefaults standardUserDefaults] objectForKey:@"WeaponXTrialOfferShownDate"];
        NSString *lastShownStr = lastShownDate ? [lastShownDate description] : @"Never shown";
        
        NSDate *userRegistrationDate = [[APIManager sharedManager] userRegistrationDate];
        NSString *regDateStr = userRegistrationDate ? [userRegistrationDate description] : @"Unknown";
        
        BOOL hasActivePlan = [[APIManager sharedManager] userHasPlan];
        
        NSString *message = [NSString stringWithFormat:
                            @"Trial Banner Debug Info:\n"
                            @"-------------------\n"
                            @"%@\n"
                            @"Has shown before: %@\n"
                            @"Last shown: %@\n"
                            @"Reg date: %@\n"
                            @"Has plan: %@\n"
                            @"-------------------\n"
                            @"Tap 'Reset' to force banner to show",
                            bannerStatus,
                            hasShownBefore ? @"YES" : @"NO",
                            lastShownStr,
                            regDateStr,
                            hasActivePlan ? @"YES" : @"NO"];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Trial Banner Debug"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *resetAction = [UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction * _Nonnull action) {
            [self resetTrialOfferStatus];
        }];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
                                                           handler:nil];
        
        [alert addAction:resetAction];
        [alert addAction:cancelAction];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)handleNetworkStatusChanged:(NSNotification *)notification {
    // Extract isOnline status from notification user info
    NSDictionary *userInfo = notification.userInfo;
    BOOL isOnline = [[userInfo objectForKey:@"isOnline"] boolValue];
    
    // Update the trial banner based on network status
    if (isOnline) {
        // Network came back online, check if we should show the banner
        if (!self.trialOfferBannerView && [self shouldShowTrialOffer]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupTrialOfferBanner];
            });
        }
    } else {
        // Network went offline, hide the banner if it's showing
        if (self.trialOfferBannerView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideTrialOfferBanner];
            });
        }
    }
}

- (void)showProfileCreation {
    // Create alert controller
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Create New Profile"
                                                                             message:@"Enter a name and optional description for the new profile."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    // Add text fields for profile name and description
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Profile Name";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Short Description (optional)";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    // Generate a sample profile ID
    NSString *sampleProfileID = [[ProfileManager sharedManager] generateProfileID];
    
    // Set the message to include the profile ID
    alertController.message = [NSString stringWithFormat:@"NEW Profile ID: %@", sampleProfileID];
    
    // Add cancel action
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];
    
    // Add create action
    UIAlertAction *createAction = [UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *nameField = alertController.textFields.firstObject;
        UITextField *descriptionField = alertController.textFields.lastObject;
        
        NSString *profileName = [nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *profileDescription = [descriptionField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (profileName.length == 0) {
            [self showError:[NSError errorWithDomain:@"WeaponXError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Profile name cannot be empty"}]];
            return;
        }
        
        // Create profile
        Profile *newProfile = [[Profile alloc] initWithName:profileName 
                                            shortDescription:profileDescription 
                                                iconName:@"default_profile"];
        
        // Show loading indicator
        [self showLoadingIndicator];
        
        // Save profile
        [[ProfileManager sharedManager] createProfile:newProfile completion:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                // Update profiles array
                self.profiles = [[ProfileManager sharedManager].profiles mutableCopy];
                
                // Auto-switch to the newly created profile
                [[ProfileManager sharedManager] switchToProfile:newProfile completion:^(BOOL switchSuccess, NSError * _Nullable switchError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // First update the profile indicator
                        [self updateProfileIndicator];
                        
                        // Then force regenerate all identifiers
                        [self.manager regenerateAllEnabledIdentifiers];
                        
                        // Explicitly generate device model if it's not already set
                        if (![self.manager currentValueForIdentifier:@"DeviceModel"]) {
                            NSString *deviceModel = [self.manager generateDeviceModel];
                            if (deviceModel) [self.manager setCustomDeviceModel:deviceModel];
                        }
                        
                        // Explicitly generate device theme if it's not already set
                        if (![self.manager currentValueForIdentifier:@"DeviceTheme"] && 
                            [self.manager respondsToSelector:@selector(generateDeviceTheme)]) {
                            NSString *deviceTheme = [self.manager generateDeviceTheme];
                            if (deviceTheme && [self.manager respondsToSelector:@selector(setCustomDeviceTheme:)]) {
                                [self.manager setCustomDeviceTheme:deviceTheme];
                                NSLog(@"[ProjectXViewController] Generated device theme for new profile: %@", deviceTheme);
                            }
                        }
                        
                        // Add a delay to ensure all values are generated and stored
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            // Update UI with new identifiers
                            Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
                            if (identifierManagerClass) {
                                id identifierManager = [identifierManagerClass sharedManager];
                                if ([identifierManager respondsToSelector:@selector(currentValueForIdentifier:)] &&
                                    [identifierManager respondsToSelector:@selector(isIdentifierEnabled:)]) {
                                    // Refresh UI with generated identifiers
                                    [self refreshIdentifierValuesInUI];
                                }
                            }
                            
                            [self hideLoadingIndicator];
                            
                            if (switchSuccess) {
                                // Show success message with the profile ID and mention that the profile is now active
                                NSString *profileID = newProfile.profileId;
                                NSString *successMessage = [NSString stringWithFormat:@"Profile created successfully.\nID: %@\n\nProfile is now active.", profileID];
                                [self showSuccessMessage:successMessage];
                            } else {
                                // Profile created but switch failed
                                NSString *profileID = newProfile.profileId;
                                NSString *successMessage = [NSString stringWithFormat:@"Profile created successfully.\nID: %@\n\nFailed to switch to profile: %@", profileID, switchError.localizedDescription];
                                [self showSuccessMessage:successMessage];
                            }
                        });
                    });
                }];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self hideLoadingIndicator];
                    [self showError:error];
                });
            }
        }];
    }];
    [alertController addAction:createAction];
    
    // Present the alert controller
    [self presentViewController:alertController animated:YES completion:nil];
}

// Helper methods for the profile creation popup
- (void)showLoadingIndicator {
    if (!self.loadingIndicator) {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        self.loadingIndicator.center = self.view.center;
        self.loadingIndicator.hidesWhenStopped = YES;
        [self.view addSubview:self.loadingIndicator];
    }
    
    [self.loadingIndicator startAnimating];
}

- (void)hideLoadingIndicator {
    [self.loadingIndicator stopAnimating];
}

- (void)showSuccessMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showProfileManager {
    // Create profile manager controller with nil profiles since it will load them directly
    ProfileManagerViewController *profileVC = [[ProfileManagerViewController alloc] initWithProfiles:nil];
    profileVC.delegate = (id<ProfileManagerViewControllerDelegate>)self;
    
    // Create navigation controller
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:profileVC];
    
    // Show modal
    [self presentViewController:navController animated:YES completion:nil];
}

#pragma mark - ProfileCreationViewControllerDelegate

- (void)profileCreationViewController:(UIViewController *)controller didCreateProfile:(NSString *)profileName {
    // Update profiles array since the profile was already created by ProfileCreationViewController
    self.profiles = [[ProfileManager sharedManager].profiles mutableCopy];
    
    // Update the profile indicator to reflect the newly created profile
    [self updateProfileIndicator];
    
    // NOTE: We no longer need to send additional notifications here
    // The profile update is already handled by ProfileManager.createProfile
    // These extra notifications were causing duplicate indicators to appear
}

#pragma mark - ProfileManagerViewControllerDelegate

- (void)profileManagerViewController:(UIViewController *)viewController didUpdateProfiles:(NSArray<Profile *> *)profiles {
    self.profiles = [profiles mutableCopy];
    [self updateProfileIndicator];
}

- (void)profileManagerViewController:(UIViewController *)viewController didSelectProfile:(Profile *)profile {
    // Update the local profiles array
    self.profiles = [[ProfileManager sharedManager].profiles mutableCopy];
    
    // Update UI if needed based on the newly selected profile
    // For example, refresh any profile-dependent UI elements
    
    // Update the profile indicator
    [self updateProfileIndicator];
    
    // Explicitly notify floating profile indicator to refresh
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ProfileManagerCurrentProfileChanged" 
                                                        object:nil 
                                                      userInfo:nil];
    
    // Also post a Darwin notification for the floating indicator
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, 
                                         CFSTR("com.hydra.projectx.profileChanged"), 
                                         NULL, 
                                         NULL, 
                                         YES);
}

// Profile Management Methods
- (void)setupProfileButtons {
    // Add profile buttons view
    self.profileButtonsView = [[ProfileButtonsView alloc] initWithFrame:CGRectZero];
    self.profileButtonsView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.profileButtonsView];
    
    // Setup profile button actions
    __weak typeof(self) weakSelf = self;
    self.profileButtonsView.onNewProfileTapped = ^{
        [weakSelf showProfileCreation];
    };
    self.profileButtonsView.onManageProfilesTapped = ^{
        [weakSelf showProfileManager];
    };
    
    // Add profile buttons constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.profileButtonsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:11],
        [self.profileButtonsView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.profileButtonsView.widthAnchor constraintEqualToConstant:60],
        [self.profileButtonsView.heightAnchor constraintEqualToConstant:136] // 2 buttons * 60 + 16 spacing
    ]];
}

- (void)setupProfileManagement {
    // Initialize profiles array
    self.profiles = [[ProfileManager sharedManager].profiles mutableCopy];
}

#pragma mark - Profile Indicator

- (void)setupProfileIndicator {
    // Remove existing indicator if any
    if (self.profileIndicatorView) {
        [self.profileIndicatorView removeFromSuperview];
    }
    
    // Create profile indicator view with no styling
    self.profileIndicatorView = [[UIView alloc] init];
    self.profileIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileIndicatorView.backgroundColor = [UIColor clearColor]; // Make completely transparent
    [self.view addSubview:self.profileIndicatorView];
    
    // Position at the left edge of the screen - move further left with negative constant
    [NSLayoutConstraint activateConstraints:@[
        [self.profileIndicatorView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:-8],
        [self.profileIndicatorView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.profileIndicatorView.widthAnchor constraintEqualToConstant:30],
        [self.profileIndicatorView.heightAnchor constraintEqualToConstant:260]
    ]];
    
    // Update the profile indicator content
    [self updateProfileIndicator];
}

- (void)updateProfileIndicator {
    // Clear existing content
    for (UIView *subview in self.profileIndicatorView.subviews) {
        [subview removeFromSuperview];
    }
    
    // Read from central profile info using ProfileManager
    ProfileManager *profileManager = [ProfileManager sharedManager];
    NSString *centralProfileInfoPath = [profileManager centralProfileInfoPath];
    NSDictionary *profileInfo = [NSDictionary dictionaryWithContentsOfFile:centralProfileInfoPath];
    NSString *profileId = profileInfo[@"ProfileId"];
    
    if (!profileId) {
        NSLog(@"[WeaponX] ProjectX: ❌ Failed to read profile ID from current_profile_info.plist");
        return;
    }
    
    NSLog(@"[WeaponX] ProjectX: Using profile ID %@ from central store", profileId);
    
    // Update UI with profile info
    NSString *profileName = profileInfo[@"ProfileName"] ?: [NSString stringWithFormat:@"Profile %@", profileId];
    NSString *iconName = profileInfo[@"IconName"] ?: @"default_profile";
    
    // Update the indicator view
    [self updateIndicatorWithName:profileName iconName:iconName profileId:profileId];
    
    // Also refresh the identifier values in the UI
    [self refreshIdentifierValuesInUI];
}

- (void)updateIndicatorWithName:(NSString *)name iconName:(NSString *)iconName profileId:(NSString *)profileId {
    // Create a single label that combines all elements with the exact format requested
    UILabel *profileIndicatorLabel = [[UILabel alloc] init];
    profileIndicatorLabel.text = [NSString stringWithFormat:@"←------------------ Profile Num: %@ -----------------→", profileId];
    profileIndicatorLabel.textColor = [UIColor systemBlueColor];
    profileIndicatorLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    profileIndicatorLabel.textAlignment = NSTextAlignmentCenter;
    profileIndicatorLabel.numberOfLines = 0;
    
    // Rotate the label to make text vertical, going from bottom to top
    profileIndicatorLabel.transform = CGAffineTransformMakeRotation(-M_PI_2);
    profileIndicatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.profileIndicatorView addSubview:profileIndicatorLabel];
    
    // Center the rotated label in the indicator view
    [NSLayoutConstraint activateConstraints:@[
        [profileIndicatorLabel.centerXAnchor constraintEqualToAnchor:self.profileIndicatorView.centerXAnchor],
        [profileIndicatorLabel.centerYAnchor constraintEqualToAnchor:self.profileIndicatorView.centerYAnchor]
    ]];
}

- (void)copyIdentifierValue:(UIButton *)sender {
    // Determine which identifier type this is for
    NSString *identifierType = nil;
    NSUInteger tag = sender.tag;
    
    // Find the identifier type based on the tag
    for (NSString *type in self.identifierSwitches.allKeys) {
        if ([self.identifierSwitches[type] tag] == tag) {
            identifierType = type;
            break;
        }
    }
    
    if (!identifierType) return;
    
    // Get the current value of the identifier
    NSString *value = [self.manager currentValueForIdentifier:identifierType];
    if (value) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:value];
        
        // Show a success message
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Copied!" 
            message:[NSString stringWithFormat:@"%@ copied to clipboard", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [self presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    }
}

- (void)regenerateIdentifier:(UIButton *)sender {
    // Determine which identifier type this is for
    NSString *identifierType = nil;
    NSUInteger tag = sender.tag;
    
    // Find the identifier type based on the tag
    for (NSString *type in self.identifierSwitches.allKeys) {
        if ([self.identifierSwitches[type] tag] == tag) {
            identifierType = type;
            break;
        }
    }
    
    if (!identifierType) return;
    
    // Check if the identifier is enabled first
    if (![self.manager isIdentifierEnabled:identifierType]) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Identifier Disabled" 
            message:[NSString stringWithFormat:@"Enable %@ spoofing first", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Generate new value based on identifier type
    if ([identifierType isEqualToString:@"IDFA"]) {
        [self.manager generateIDFA];
    } else if ([identifierType isEqualToString:@"IDFV"]) {
        [self.manager generateIDFV];
    } else if ([identifierType isEqualToString:@"DeviceName"]) {
        [self.manager generateDeviceName];
    } else if ([identifierType isEqualToString:@"SerialNumber"]) {
        [self.manager generateSerialNumber];
    } else if ([identifierType isEqualToString:@"IOSVersion"]) {
        [self.manager generateIOSVersion];
    } else if ([identifierType isEqualToString:@"WiFi"]) {
        [self.manager generateWiFiInformation];
    } else if ([identifierType isEqualToString:@"StorageSystem"]) {
        // ... existing StorageSystem code ...
    } else if ([identifierType isEqualToString:@"Battery"]) {
        // ... existing Battery code ...
    } else if ([identifierType isEqualToString:@"SystemBootUUID"]) {
        [self.manager generateSystemBootUUID];
    } else if ([identifierType isEqualToString:@"DyldCacheUUID"]) {
        [self.manager generateDyldCacheUUID];
    } else if ([identifierType isEqualToString:@"PasteboardUUID"]) {
        [self.manager generatePasteboardUUID];
    } else if ([identifierType isEqualToString:@"KeychainUUID"]) {
        [self.manager generateKeychainUUID];
    } else if ([identifierType isEqualToString:@"UserDefaultsUUID"]) {
        [self.manager generateUserDefaultsUUID];
    } else if ([identifierType isEqualToString:@"AppGroupUUID"]) {
        [self.manager generateAppGroupUUID];
    } else if ([identifierType isEqualToString:@"SystemUptime"]) {
        [self.manager generateSystemUptime];
    } else if ([identifierType isEqualToString:@"BootTime"]) {
        [self.manager generateBootTime];
    } else if ([identifierType isEqualToString:@"CoreDataUUID"]) {
        [self.manager generateCoreDataUUID];
    } else if ([identifierType isEqualToString:@"AppInstallUUID"]) {
        [self.manager generateAppInstallUUID];
} else if ([identifierType isEqualToString:@"AppContainerUUID"]) {
        [self.manager generateAppContainerUUID];
    } else {
        return;
    }
    
    // Check for errors
    if ([self.manager lastError]) {
        [self showError:[self.manager lastError]];
        return;
    }
    
    // Refresh UI to show new value
    [self loadSettings];
    
    // Show a success message
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"Regenerated" 
        message:[NSString stringWithFormat:@"%@ has been regenerated", identifierType]
        preferredStyle:UIAlertControllerStyleAlert];
    
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

// New method to refresh identifier values
- (void)refreshIdentifierValuesInUI {
    // Get the IdentifierManager
    Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
    if (!identifierManagerClass) {
        NSLog(@"[WeaponX] ❌ Could not find IdentifierManager class for refresh");
        return;
    }
    
    id identifierManager = [identifierManagerClass sharedManager];
    if (!identifierManager) {
        NSLog(@"[WeaponX] ❌ Could not get IdentifierManager instance for refresh");
        return;
    }
    
    // Log the current profile path for debugging
    if ([identifierManager respondsToSelector:@selector(profileIdentityPath)]) {
        NSString *profilePath = [identifierManager performSelector:@selector(profileIdentityPath)];
        NSLog(@"[WeaponX] 🔍 Current profile path: %@", profilePath);
    }
    
    // Check if identifiers are enabled and get current values
    SEL isEnabledSel = NSSelectorFromString(@"isIdentifierEnabled:");
    SEL currentValueSel = NSSelectorFromString(@"currentValueForIdentifier:");
    
    if ([identifierManager respondsToSelector:isEnabledSel] && [identifierManager respondsToSelector:currentValueSel]) {
        // Helper method to safely perform selector
        BOOL (^performBoolSelector)(id, SEL, id) = ^(id target, SEL selector, id object) {
            NSMethodSignature *signature = [target methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:target];
            [invocation setSelector:selector];
            if (object) {
                [invocation setArgument:&object atIndex:2];
            }
            [invocation invoke];
            BOOL result = NO;
            [invocation getReturnValue:&result];
            return result;
        };
        
        NSString* (^performStringSelector)(id, SEL, id) = ^(id target, SEL selector, id object) {
            NSMethodSignature *signature = [target methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:target];
            [invocation setSelector:selector];
            if (object) {
                [invocation setArgument:&object atIndex:2];
            }
            [invocation invoke];
            __unsafe_unretained NSString *result = nil;
            [invocation getReturnValue:&result];
            return result;
        };
        
        NSArray *identifierTypes = @[@"IDFA", @"IDFV", @"DeviceName", @"SerialNumber", @"IOSVersion", @"WiFi", @"StorageSystem", @"Battery", @"SystemBootUUID", @"DyldCacheUUID", @"PasteboardUUID", @"KeychainUUID", @"UserDefaultsUUID", @"AppGroupUUID", @"CoreDataUUID", @"SystemUptime", @"BootTime", @"AppInstallUUID", @"AppContainerUUID"];
        
        for (NSString *type in identifierTypes) {
            BOOL isEnabled = performBoolSelector(identifierManager, isEnabledSel, type);
            NSLog(@"[WeaponX] 🔍 Checking %@ - Enabled: %@", type, isEnabled ? @"YES" : @"NO");
            
            if (isEnabled) {
                NSString *value = performStringSelector(identifierManager, currentValueSel, type);
                NSLog(@"[WeaponX] 🔍 %@ current value: %@", type, value ?: @"nil");
                
                if (value) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self directUpdateIdentifierValue:type withValue:value];
                    });
                } else {
                    NSLog(@"[WeaponX] ⚠️ No value found for enabled identifier: %@", type);
                }
            }
        }
    } else {
        NSLog(@"[WeaponX] ❌ IdentifierManager missing required methods");
    }
}

- (void)createProfileTapped:(id)sender {
    NSLog(@"[WeaponX] Create profile tapped");
    
    // Create alert controller for profile creation
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Create New Profile"
                                                                             message:@"Enter a name and optional description for the new profile."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    // Add text fields for name and description
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Profile Name";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Description (optional)";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    
    // Add cancel action
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];
    
    // Add create action
    UIAlertAction *createAction = [UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *nameField = alertController.textFields.firstObject;
        UITextField *descriptionField = alertController.textFields.lastObject;
        
        NSString *profileName = [nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *profileDescription = [descriptionField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (profileName.length == 0) {
            [self showError:[NSError errorWithDomain:@"WeaponXError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Profile name cannot be empty"}]];
            return;
        }
        
        // Create profile
        Profile *newProfile = [[Profile alloc] initWithName:profileName 
                                            shortDescription:profileDescription 
                                                iconName:@"default_profile"];
        
        // Show loading indicator
        [self showLoadingIndicator];
        
        // Save profile
        [[ProfileManager sharedManager] createProfile:newProfile completion:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                // Update profiles array
                self.profiles = [[ProfileManager sharedManager].profiles mutableCopy];
                
                // Auto-switch to the newly created profile
                [[ProfileManager sharedManager] switchToProfile:newProfile completion:^(BOOL switchSuccess, NSError * _Nullable switchError) {
                    // Add a small delay to ensure identifier generation completes
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        // Update UI with new identifiers
                        Class identifierManagerClass = NSClassFromString(@"IdentifierManager");
                        if (identifierManagerClass) {
                            id identifierManager = [identifierManagerClass sharedManager];
                            if ([identifierManager respondsToSelector:@selector(currentValueForIdentifier:)] &&
                                [identifierManager respondsToSelector:@selector(isIdentifierEnabled:)]) {
                                // Refresh UI with generated identifiers
                                [self refreshIdentifierValuesInUI];
                                
                                // Also generate Device Theme if missing for the new profile
                                if ([identifierManager respondsToSelector:@selector(currentValueForIdentifier:)] &&
                                    ![identifierManager currentValueForIdentifier:@"DeviceTheme"]) {
                                    if ([identifierManager respondsToSelector:@selector(generateDeviceTheme)]) {
                                        NSString *deviceTheme = [identifierManager generateDeviceTheme];
                                        if (deviceTheme && [identifierManager respondsToSelector:@selector(setCustomDeviceTheme:)]) {
                                            [identifierManager setCustomDeviceTheme:deviceTheme];
                                            NSLog(@"[ProjectXViewController] Generated device theme for new profile: %@", deviceTheme);
                                        }
                                    }
                                }
                            }
                        }
                        
                        [self hideLoadingIndicator];
                        
                        // Update the profile indicator
                        [self updateProfileIndicator];
                        
                        if (switchSuccess) {
                            // Show success message with the profile ID and mention that the profile is now active
                            NSString *profileID = newProfile.profileId;
                            NSString *successMessage = [NSString stringWithFormat:@"Profile created successfully.\nID: %@\n\nProfile is now active.", profileID];
                            [self showSuccessMessage:successMessage];
                        } else {
                            // Profile created but switch failed
                            NSString *profileID = newProfile.profileId;
                            NSString *successMessage = [NSString stringWithFormat:@"Profile created successfully.\nID: %@\n\nFailed to switch to profile: %@", profileID, switchError.localizedDescription];
                            [self showSuccessMessage:successMessage];
                        }
                    });
                }];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self hideLoadingIndicator];
                    [self showError:error];
                });
            }
        }];
    }];
    [alertController addAction:createAction];
    
    // Present the alert controller
    [self presentViewController:alertController animated:YES completion:nil];
}

// Replace the identifierDidTap method to handle Battery like other simple identifiers
- (void)identifierDidTap:(UITapGestureRecognizer *)gesture {
    // Get the identifier type from the associated object
    NSString *identifierType = objc_getAssociatedObject(gesture, "identifierType");
    if (!identifierType) {
        return;
    }
    
    // Check if spoofing is enabled for this identifier
    if (![self.manager isIdentifierEnabled:identifierType]) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Spoofing Disabled" 
            message:[NSString stringWithFormat:@"Please enable %@ spoofing first.", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // For all identifiers, simply click the generate button
    int tag = 0;
    if ([identifierType isEqualToString:@"IDFA"])
        tag = 1;
    else if ([identifierType isEqualToString:@"IDFV"])
        tag = 2;
    else if ([identifierType isEqualToString:@"DeviceName"])
        tag = 3;
    else if ([identifierType isEqualToString:@"SerialNumber"])
        tag = 4;
    else if ([identifierType isEqualToString:@"IOSVersion"])
        tag = 5;
    else if ([identifierType isEqualToString:@"WiFi"])
        tag = 6;
    else if ([identifierType isEqualToString:@"StorageSystem"])
        tag = 7;
    else if ([identifierType isEqualToString:@"Battery"])
        tag = 8;
    else if ([identifierType isEqualToString:@"SystemBootUUID"])
        tag = 9;
    else if ([identifierType isEqualToString:@"DyldCacheUUID"])
        tag = 10;
    else if ([identifierType isEqualToString:@"PasteboardUUID"])
        tag = 11;
    else if ([identifierType isEqualToString:@"KeychainUUID"])
        tag = 12;
    else if ([identifierType isEqualToString:@"UserDefaultsUUID"])
        tag = 13;
    else if ([identifierType isEqualToString:@"AppGroupUUID"])
        tag = 14;
    else if ([identifierType isEqualToString:@"SystemUptime"])
        tag = 15;
    else if ([identifierType isEqualToString:@"BootTime"])
        tag = 16;
    else if ([identifierType isEqualToString:@"CoreDataUUID"])
        tag = 17;
    else if ([identifierType isEqualToString:@"AppInstallUUID"])
        tag = 18;
else if ([identifierType isEqualToString:@"AppContainerUUID"])
        tag = 19;
    if (tag > 0) {
        [self generateButtonTapped:[self buttonWithTag:tag]];
    }
}

// Remove unused battery configuration methods
// Delete these methods:
// showBatteryConfigurationUI
// setBatteryLevel:lowPowerMode:
// toggleLowPowerMode
// showCustomBatteryInput
// randomizeBattery

// Add helper methods for finding buttons by tag
- (UIButton *)buttonWithTag:(NSInteger)tag {
    for (UIView *view in self.mainStackView.arrangedSubviews) {
        // Find buttons with matching tag
        if ([view isKindOfClass:[UIView class]]) {
            NSArray *buttons = [self findSubviewsOfClass:[UIButton class] inView:view];
            for (UIButton *button in buttons) {
                if (button.tag == tag) {
                    return button;
                }
            }
        }
    }
    return nil;
}

- (NSArray *)findSubviewsOfClass:(Class)cls inView:(UIView *)view {
    NSMutableArray *result = [NSMutableArray array];
    
    if ([view isKindOfClass:cls]) {
        [result addObject:view];
    }
    
    for (UIView *subview in view.subviews) {
        [result addObjectsFromArray:[self findSubviewsOfClass:cls inView:subview]];
    }
    
    return result;
}

// Add this helper method at the end of the @implementation
- (NSInteger)tagForIdentifierType:(NSString *)type {
    if ([type isEqualToString:@"IDFA"]) return 1;
    if ([type isEqualToString:@"IDFV"]) return 2;
    if ([type isEqualToString:@"DeviceName"]) return 3;
    if ([type isEqualToString:@"SerialNumber"]) return 4;
    if ([type isEqualToString:@"IOSVersion"]) return 5;
    if ([type isEqualToString:@"WiFi"]) return 6;
    if ([type isEqualToString:@"StorageSystem"]) return 7;
    if ([type isEqualToString:@"Battery"]) return 8;
    if ([type isEqualToString:@"SystemBootUUID"]) return 9;
    if ([type isEqualToString:@"DyldCacheUUID"]) return 10;
    if ([type isEqualToString:@"PasteboardUUID"]) return 11;
    if ([type isEqualToString:@"KeychainUUID"]) return 12;
    if ([type isEqualToString:@"UserDefaultsUUID"]) return 13;
    if ([type isEqualToString:@"AppGroupUUID"]) return 14;
    if ([type isEqualToString:@"SystemUptime"]) return 15;
    if ([type isEqualToString:@"BootTime"]) return 16;
    if ([type isEqualToString:@"CoreDataUUID"]) return 17;
    if ([type isEqualToString:@"AppInstallUUID"]) return 18;
    if ([type isEqualToString:@"AppContainerUUID"]) return 19;
    return 0;
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

- (void)addApplicationWithExtensionsToScope:(NSString *)bundleID {
    if (![[APIManager sharedManager] userHasPlan]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Plan Required"
                                                                       message:@"You need an active plan to add apps with extensions to scope."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (!bundleID) return;
    
    // Get the app proxy
    LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!appProxy) return;
    
    // Add the app with extensions to scope
    [[IdentifierManager sharedManager] addApplicationWithExtensionsToScope:bundleID];
    
    // Show success message
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                 message:@"Application and its extensions have been added to scope"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
    // Refresh the app list
    [self loadScopedApps];
}

// Add loadScopedApps method
- (void)loadScopedApps {
    // Get all scoped apps from IdentifierManager
    NSDictionary *appInfo = [self.manager getApplicationInfo:nil];
    NSMutableArray *apps = [NSMutableArray array];
    
    for (NSString *bundleID in appInfo) {
        NSMutableDictionary *app = [NSMutableDictionary dictionaryWithDictionary:appInfo[bundleID]];
        if (!app[@"bundleID"]) {
            app[@"bundleID"] = bundleID;
        }
        [apps addObject:app];
    }
    
    // Sort apps by name
    self.scopedApps = [apps sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *app1, NSDictionary *app2) {
        return [app1[@"name"] compare:app2[@"name"]];
    }];
    
    // Refresh the table view if it exists
    if (self.appsTableView) {
        [self.appsTableView reloadData];
    }
}

// Add the extension button handler method
- (void)extensionButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.appSwitches.allKeys.count) {
        return;
    }
    
    NSString *bundleID = self.appSwitches.allKeys[index];
    if (!bundleID) return;
    
    // Add the app with extensions
    [self.manager addApplicationWithExtensionsToScope:bundleID];
    
    // Check for errors
    if ([self.manager lastError]) {
        [self showError:[self.manager lastError]];
        return;
    }
    
    // Show success message
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                 message:@"App extensions have been added to scope"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
    
    // Update UI
    [self loadSettings];
}

- (void)titleIconTapped:(UITapGestureRecognizer *)gesture {
    // Get the identifier type from the associated object
    NSString *identifierType = objc_getAssociatedObject(gesture, "identifierType");
    if (!identifierType) {
        return;
    }
    
    // Check if spoofing is enabled for this identifier
    if (![self.manager isIdentifierEnabled:identifierType]) {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Spoofing Disabled" 
            message:[NSString stringWithFormat:@"Please enable %@ spoofing first.", identifierType]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction 
            actionWithTitle:@"OK" 
            style:UIAlertActionStyleDefault 
            handler:nil]];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Get current value
    NSString *currentValue = [self.manager currentValueForIdentifier:identifierType];
    
    // Create alert with text field to edit value
    UIAlertController *editAlert = [UIAlertController 
        alertControllerWithTitle:[NSString stringWithFormat:@"Edit %@", identifierType]
        message:@"Enter a new value or leave blank to auto-generate"
        preferredStyle:UIAlertControllerStyleAlert];
    
    [editAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"New Value";
        textField.text = currentValue;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        
        // For UUID types, add validation
        if ([identifierType containsString:@"UUID"]) {
            textField.keyboardType = UIKeyboardTypeDefault;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }
    }];
    
    // Add cancel action
    [editAlert addAction:[UIAlertAction 
        actionWithTitle:@"Cancel" 
        style:UIAlertActionStyleCancel 
        handler:nil]];
    
    // Add save action
    [editAlert addAction:[UIAlertAction 
        actionWithTitle:@"Save" 
        style:UIAlertActionStyleDefault 
        handler:^(UIAlertAction *action) {
            UITextField *textField = editAlert.textFields.firstObject;
            NSString *newValue = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            // If empty, generate a new value
            if (newValue.length == 0) {
                [self generateValueForIdentifier:identifierType];
                return;
            }
            
            // For UUID values, validate format
            if ([identifierType containsString:@"UUID"]) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" 
                                                                            options:NSRegularExpressionCaseInsensitive 
                                                                            error:nil];
                
                NSUInteger matches = [regex numberOfMatchesInString:newValue 
                                                          options:0 
                                                            range:NSMakeRange(0, newValue.length)];
                
                if (matches != 1) {
                    // Invalid UUID format
                    UIAlertController *errorAlert = [UIAlertController 
                        alertControllerWithTitle:@"Invalid Format" 
                        message:@"Please enter a valid UUID in the format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" 
                        preferredStyle:UIAlertControllerStyleAlert];
                    
                    [errorAlert addAction:[UIAlertAction 
                        actionWithTitle:@"OK" 
                        style:UIAlertActionStyleDefault 
                        handler:nil]];
                    
                    [self presentViewController:errorAlert animated:YES completion:nil];
                    return;
                }
            }
            
            // Update value in manager
            [self setCustomValue:newValue forIdentifier:identifierType];
        }]];
    
    [self presentViewController:editAlert animated:YES completion:nil];
}

- (void)setCustomValue:(NSString *)value forIdentifier:(NSString *)type {
    // This implementation depends on how values can be set in your manager
    // We need to forward it to the appropriate manager
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = NO;
        
        // Save the custom value depending on identifier type
        if ([type isEqualToString:@"IDFA"]) {
            success = [self.manager setCustomIDFA:value];
        } else if ([type isEqualToString:@"IDFV"]) {
            success = [self.manager setCustomIDFV:value];
        } else if ([type isEqualToString:@"DeviceName"]) {
            success = [self.manager setCustomDeviceName:value];
        } else if ([type isEqualToString:@"SerialNumber"]) {
            success = [self.manager setCustomSerialNumber:value];
        } else if ([type isEqualToString:@"SystemBootUUID"]) {
            success = [self.manager setCustomSystemBootUUID:value];
        } else if ([type isEqualToString:@"DyldCacheUUID"]) {
            success = [self.manager setCustomDyldCacheUUID:value];
        } else if ([type isEqualToString:@"PasteboardUUID"]) {
            success = [self.manager setCustomPasteboardUUID:value];
        } else if ([type isEqualToString:@"KeychainUUID"]) {
            success = [self.manager setCustomKeychainUUID:value];
        } else if ([type isEqualToString:@"UserDefaultsUUID"]) {
            success = [self.manager setCustomUserDefaultsUUID:value];
        } else if ([type isEqualToString:@"AppGroupUUID"]) {
            success = [self.manager setCustomAppGroupUUID:value];
        } else if ([type isEqualToString:@"CoreDataUUID"]) {
            success = [self.manager setCustomCoreDataUUID:value];
        } else if ([type isEqualToString:@"AppInstallUUID"]) {
            success = [self.manager setCustomAppInstallUUID:value];
        } else if ([type isEqualToString:@"AppContainerUUID"]) {
            success = [self.manager setCustomAppContainerUUID:value];
        }
        
        // Update UI
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                // Refresh the value in UI
                NSString *updatedValue = [self.manager currentValueForIdentifier:type];
                [self directUpdateIdentifierValue:type withValue:updatedValue];
                
                // Show success message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Value Updated" 
                    message:[NSString stringWithFormat:@"%@ has been updated.", type]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [self presentViewController:alert animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    });
                }];
            } else {
                // Show error message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Update Failed" 
                    message:[NSString stringWithFormat:@"Failed to update %@. Please try again.", type]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                    actionWithTitle:@"OK" 
                    style:UIAlertActionStyleDefault 
                    handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

- (void)generateValueForIdentifier:(NSString *)identifierType {
    // Show loading indicator
    [self showLoadingIndicator];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Generate a new value for the specified identifier
        NSString *newValue = nil;
        if ([identifierType isEqualToString:@"IDFA"]) {
            newValue = [self.manager generateIDFA];
        } else if ([identifierType isEqualToString:@"IDFV"]) {
            newValue = [self.manager generateIDFV];
        } else if ([identifierType isEqualToString:@"DeviceName"]) {
            newValue = [self.manager generateDeviceName];
        } else if ([identifierType isEqualToString:@"SerialNumber"]) {
            newValue = [self.manager generateSerialNumber];
        } else if ([identifierType isEqualToString:@"IOSVersion"]) {
            // Generate iOS Version and then get the string representation
            [self.manager generateIOSVersion];
            newValue = [self.manager currentValueForIdentifier:@"IOSVersion"];
        } else if ([identifierType isEqualToString:@"WiFi"]) {
            newValue = [self.manager generateWiFiInformation];
        } else if ([identifierType isEqualToString:@"SystemBootUUID"]) {
            newValue = [self.manager generateSystemBootUUID];
        } else if ([identifierType isEqualToString:@"DyldCacheUUID"]) {
            newValue = [self.manager generateDyldCacheUUID];
        } else if ([identifierType isEqualToString:@"PasteboardUUID"]) {
            newValue = [self.manager generatePasteboardUUID];
        } else if ([identifierType isEqualToString:@"KeychainUUID"]) {
            newValue = [self.manager generateKeychainUUID];
        } else if ([identifierType isEqualToString:@"UserDefaultsUUID"]) {
            newValue = [self.manager generateUserDefaultsUUID];
        } else if ([identifierType isEqualToString:@"AppGroupUUID"]) {
            newValue = [self.manager generateAppGroupUUID];
        } else if ([identifierType isEqualToString:@"CoreDataUUID"]) {
            newValue = [self.manager generateCoreDataUUID];
        } else if ([identifierType isEqualToString:@"AppInstallUUID"]) {
            newValue = [self.manager generateAppInstallUUID];
        } else if ([identifierType isEqualToString:@"AppContainerUUID"]) {
            newValue = [self.manager generateAppContainerUUID];
        } else if ([identifierType isEqualToString:@"StorageSystem"]) {
            // Get StorageManager class
            Class storageManagerClass = NSClassFromString(@"StorageManager");
            if (storageManagerClass && [storageManagerClass respondsToSelector:@selector(sharedManager)]) {
                id storageManager = [storageManagerClass sharedManager];
                if (storageManager) {
                    // Generate a random storage capacity (either 64GB or 128GB)
                    NSString *capacity = [storageManager respondsToSelector:@selector(randomizeStorageCapacity)] ? 
                                       [storageManager randomizeStorageCapacity] : @"64";
                    
                    // Generate the storage information based on the capacity
                    if ([storageManager respondsToSelector:@selector(generateStorageForCapacity:)]) {
                        NSDictionary *storageInfo = [storageManager generateStorageForCapacity:capacity];
                        if (storageInfo) {
                            // Update the StorageManager with the generated values
                            [storageManager setTotalStorageCapacity:storageInfo[@"TotalStorage"]];
                            [storageManager setFreeStorageSpace:storageInfo[@"FreeStorage"]];
                            [storageManager setFilesystemType:storageInfo[@"FilesystemType"]];
                            
                            // Format the value for display
                            newValue = [NSString stringWithFormat:@"Total: %@ GB, Free: %@ GB", 
                                      storageInfo[@"TotalStorage"], 
                                      storageInfo[@"FreeStorage"]];
                        }
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                BOOL use128GB = (arc4random_uniform(100) < 60);
                newValue = use128GB ? @"Total: 128 GB, Free: 38.4 GB" : @"Total: 64 GB, Free: 19.8 GB";
            }
        } else if ([identifierType isEqualToString:@"Battery"]) {
            // Get BatteryManager class
            Class batteryManagerClass = NSClassFromString(@"BatteryManager");
            if (batteryManagerClass && [batteryManagerClass respondsToSelector:@selector(sharedManager)]) {
                id batteryManager = [batteryManagerClass sharedManager];
                if (batteryManager && [batteryManager respondsToSelector:@selector(generateBatteryInfo)]) {
                    NSDictionary *batteryInfo = [batteryManager generateBatteryInfo];
                    if (batteryInfo) {
                        // Update display value - just show battery percentage now
                        NSString *level = batteryInfo[@"BatteryLevel"];
                        float levelFloat = [level floatValue];
                        int percentage = (int)(levelFloat * 100);
                        
                        newValue = [NSString stringWithFormat:@"%d%%", percentage];
                    }
                }
            }
            
            // If we couldn't generate a value, use a fallback
            if (!newValue) {
                int randomPercentage = 20 + arc4random_uniform(81); // 20-100%
                newValue = [NSString stringWithFormat:@"%d%%", randomPercentage];
            }
        } else if ([identifierType isEqualToString:@"SystemUptime"]) {
            NSString *profilePath = [self.manager profileIdentityPath];
            [[UptimeManager sharedManager] generateUptimeForProfile:profilePath];
            newValue = [self.manager currentValueForIdentifier:@"SystemUptime"];
        } else if ([identifierType isEqualToString:@"BootTime"]) {
            NSString *profilePath = [self.manager profileIdentityPath];
            [[UptimeManager sharedManager] generateBootTimeForProfile:profilePath];
            newValue = [self.manager currentValueForIdentifier:@"BootTime"];
        }
        
        // Update UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideLoadingIndicator];
            
            if ([self.manager lastError]) {
                [self showError:[self.manager lastError]];
                return;
            }
            
            // Save settings
            [self.manager saveSettings];
            
            // Update the UI with the new value
            if (newValue) {
                [self directUpdateIdentifierValue:identifierType withValue:newValue];
                
                // Show success message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Generated" 
                    message:[NSString stringWithFormat:@"New %@ generated", identifierType]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [self presentViewController:alert animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    });
                }];
            } else {
                // Show error message
                UIAlertController *alert = [UIAlertController 
                    alertControllerWithTitle:@"Generation Failed" 
                    message:[NSString stringWithFormat:@"Failed to generate %@. Please try again.", identifierType]
                    preferredStyle:UIAlertControllerStyleAlert];
                
                [alert addAction:[UIAlertAction 
                    actionWithTitle:@"OK" 
                    style:UIAlertActionStyleDefault 
                    handler:nil]];
                
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

// Add methods for the show advanced button and advanced identifier sections
- (void)addShowAdvancedButton {
    // Create a container for the button with padding
    UIView *buttonContainer = [[UIView alloc] init];
    buttonContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mainStackView addArrangedSubview:buttonContainer];
    
    // Create the "Show Advanced" button
    self.showAdvancedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.showAdvancedButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Configure button with modern appearance
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        config.baseBackgroundColor = [UIColor systemBlueColor];
        config.baseForegroundColor = [UIColor whiteColor];
        config.title = @"Show Advanced Identifiers";
        config.image = [UIImage systemImageNamed:@"chevron.down"];
        config.imagePlacement = NSDirectionalRectEdgeTrailing;
        config.imagePadding = 8;
        config.contentInsets = NSDirectionalEdgeInsetsMake(8, 16, 8, 16);
        self.showAdvancedButton.configuration = config;
    } else {
        // Fallback for older iOS versions - create a tinted button without using deprecated properties
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = @"Show Advanced Identifiers";
        config.background.backgroundColor = [UIColor systemBlueColor];
        config.baseForegroundColor = [UIColor whiteColor];
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        
        // Set content insets equivalent to UIEdgeInsetsMake(8, 16, 8, 16)
        config.contentInsets = NSDirectionalEdgeInsetsMake(8, 16, 8, 16);
        self.showAdvancedButton.configuration = config;
        
        // Add chevron icon manually for older iOS
        UIImageView *chevronIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
        chevronIcon.tintColor = [UIColor whiteColor];
        chevronIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [self.showAdvancedButton addSubview:chevronIcon];
        
        [NSLayoutConstraint activateConstraints:@[
            [chevronIcon.trailingAnchor constraintEqualToAnchor:self.showAdvancedButton.trailingAnchor constant:-8],
            [chevronIcon.centerYAnchor constraintEqualToAnchor:self.showAdvancedButton.centerYAnchor],
            [chevronIcon.widthAnchor constraintEqualToConstant:12],
            [chevronIcon.heightAnchor constraintEqualToConstant:12]
        ]];
    }
    
    [self.showAdvancedButton addTarget:self action:@selector(toggleAdvancedIdentifiers:) forControlEvents:UIControlEventTouchUpInside];
    [buttonContainer addSubview:self.showAdvancedButton];
    
    // Center the button in its container
    [NSLayoutConstraint activateConstraints:@[
        [self.showAdvancedButton.centerXAnchor constraintEqualToAnchor:buttonContainer.centerXAnchor],
        [self.showAdvancedButton.topAnchor constraintEqualToAnchor:buttonContainer.topAnchor constant:8],
        [self.showAdvancedButton.bottomAnchor constraintEqualToAnchor:buttonContainer.bottomAnchor constant:-8],
        [self.showAdvancedButton.widthAnchor constraintLessThanOrEqualToAnchor:buttonContainer.widthAnchor constant:-32]
    ]];
    
    // Add some spacing after the button
    [self.mainStackView setCustomSpacing:16 afterView:buttonContainer];
}

// Add a version of addIdentifierSection that adds to our tracking array and hides them initially
- (void)addAdvancedIdentifierSection:(NSString *)type title:(NSString *)title {
    // Get the current count of views in main stack before adding
    NSUInteger beforeCount = self.mainStackView.arrangedSubviews.count;
    
    // Call the original method to create the section (adds title label and container)
    [self addIdentifierSection:type title:title];
    
    // Get both the title label and container view that were just added
    if (self.mainStackView.arrangedSubviews.count >= beforeCount + 2) {
        // The title label is typically added first, then the container
        UIView *titleLabel = self.mainStackView.arrangedSubviews[beforeCount];
        UIView *containerView = self.mainStackView.arrangedSubviews[beforeCount + 1];
        
        // Initially hide both views
        titleLabel.hidden = YES;
        containerView.hidden = YES;
        
        // Add both views to our tracking array
        [self.advancedIdentifierViews addObject:titleLabel];
        [self.advancedIdentifierViews addObject:containerView];
    } else {
        // Fallback in case we couldn't identify both views properly
        // Just hide the last view added (likely the container)
        UIView *lastView = self.mainStackView.arrangedSubviews.lastObject;
        lastView.hidden = YES;
        [self.advancedIdentifierViews addObject:lastView];
    }
}

// Handle toggle of advanced identifiers
- (void)toggleAdvancedIdentifiers:(UIButton *)sender {
    // Toggle the state
    self.showAdvancedIdentifiers = !self.showAdvancedIdentifiers;
    
    // Update button appearance
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = self.showAdvancedButton.configuration;
        if (self.showAdvancedIdentifiers) {
            config.title = @"Hide Advanced Identifiers";
            config.image = [UIImage systemImageNamed:@"chevron.up"];
        } else {
            config.title = @"Show Advanced Identifiers";
            config.image = [UIImage systemImageNamed:@"chevron.down"];
        }
        self.showAdvancedButton.configuration = config;
    } else {
        // Update for older iOS versions
        if (self.showAdvancedIdentifiers) {
            [self.showAdvancedButton setTitle:@"Hide Advanced Identifiers" forState:UIControlStateNormal];
            
            // Update chevron icon
            for (UIView *subview in self.showAdvancedButton.subviews) {
                if ([subview isKindOfClass:[UIImageView class]]) {
                    UIImageView *imageView = (UIImageView *)subview;
                    imageView.image = [UIImage systemImageNamed:@"chevron.up"];
                    break;
                }
            }
        } else {
            [self.showAdvancedButton setTitle:@"Show Advanced Identifiers" forState:UIControlStateNormal];
            
            // Update chevron icon
            for (UIView *subview in self.showAdvancedButton.subviews) {
                if ([subview isKindOfClass:[UIImageView class]]) {
                    UIImageView *imageView = (UIImageView *)subview;
                    imageView.image = [UIImage systemImageNamed:@"chevron.down"];
                    break;
                }
            }
        }
    }
    
    // Toggle visibility of advanced identifiers with animation
    if (self.showAdvancedIdentifiers) {
        // Show the advanced identifier views with a sequential animation
        [UIView animateWithDuration:0.3 animations:^{
            for (NSInteger i = 0; i < self.advancedIdentifierViews.count; i++) {
                UIView *view = self.advancedIdentifierViews[i];
                view.hidden = NO;
                view.alpha = 0;
                
                // Add a slight delay between each view appearing
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.3 animations:^{
                        view.alpha = 1.0;
                    }];
                });
            }
        }];
        
        // Scroll to show the first advanced identifier
        if (self.advancedIdentifierViews.count > 0) {
            UIView *firstView = self.advancedIdentifierViews.firstObject;
            [self.scrollView scrollRectToVisible:firstView.frame animated:YES];
        }
    } else {
        // Hide the advanced identifier views
        [UIView animateWithDuration:0.2 animations:^{
            for (UIView *view in self.advancedIdentifierViews) {
                view.alpha = 0;
            }
        } completion:^(BOOL finished) {
            for (UIView *view in self.advancedIdentifierViews) {
                view.hidden = YES;
            }
        }];
    }
}

#pragma mark - More Options Button Action

- (void)moreOptionsButtonTapped:(UIButton *)sender {
    // Add safety check for the tag value
    if (sender.tag < 0 || !self.appSwitches || sender.tag >= self.appSwitches.allKeys.count) {
        NSLog(@"[WeaponX] ⚠️ Invalid button tag or appSwitches state");
        return;
    }
    
    NSString *bundleID = self.appSwitches.allKeys[sender.tag];
    if (!bundleID) {
        NSLog(@"[WeaponX] ⚠️ Could not find bundleID for tag: %ld", (long)sender.tag);
        return;
    }
    
    // Verify manager instances exist
    if (!self.manager || !self.freezeManager) {
        NSLog(@"[WeaponX] ⚠️ Manager instances are nil");
        return;
    }
    
    // Get app info with error handling
    NSDictionary *appInfo = [self.manager getApplicationInfo:bundleID];
    
    // Use safe values for app info
    NSString *appName = bundleID;
    BOOL isFrozen = NO;
    
    // Only if we have valid appInfo, extract information
    if (appInfo) {
        appName = appInfo[@"name"] ?: bundleID;
        isFrozen = [self.freezeManager isApplicationFrozen:bundleID];
    } else {
        NSLog(@"[WeaponX] ⚠️ Could not get app info for %@", bundleID);
    }
    
    // Create action sheet with app name as title
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:appName
                                                                        message:nil
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add freeze/unfreeze option with appropriate styling based on current state
    NSString *freezeTitle = isFrozen ? @"Unfreeze App" : @"Freeze App";
    UIImage *freezeImage = [UIImage systemImageNamed:@"snowflake.circle.fill"];
    
    UIAlertAction *freezeAction = [UIAlertAction actionWithTitle:freezeTitle
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        @try {
            // Use the manager directly instead of calling freezeAppButtonTapped
            if (isFrozen) {
                [self.freezeManager unfreezeApplication:bundleID];
            } else {
                [self.freezeManager freezeApplication:bundleID];
            }
            
            // Update the UI for the specific cell that changed - with safety checks
            NSInteger index = [self.appSwitches.allKeys indexOfObject:bundleID];
            if (index != NSNotFound && self.appsTableView) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
                [self.appsTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            }
            
            // Also update the app list to reflect changes
            [self updateAppsList];
            
            // Show confirmation of the action
            NSString *confirmMessage = isFrozen ? 
                [NSString stringWithFormat:@"%@ has been unfrozen", appName] : 
                [NSString stringWithFormat:@"%@ has been frozen", appName];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Status Changed"
                                                                                 message:confirmMessage
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                [confirmAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                
                // Present after a short delay to let the action complete
                [self presentViewController:confirmAlert animated:YES completion:nil];
            });
        } @catch (NSException *exception) {
            NSLog(@"[WeaponX] ⚠️ Exception during freeze/unfreeze: %@", exception);
            
            // Show error message
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                             message:[NSString stringWithFormat:@"Could not perform action: %@", exception.reason]
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            });
        }
    }];
    
    // Add visual indicator of freeze state to the action title - with error handling
    if (isFrozen && freezeImage) {
        @try {
            // Create attributed string with freeze icon for frozen apps
            NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:freezeTitle];
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.image = [freezeImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            
            // Set the bounds to control image size
            CGFloat imageSize = 20.0;
            attachment.bounds = CGRectMake(0, -4, imageSize, imageSize);
            
            NSAttributedString *imageString = [NSAttributedString attributedStringWithAttachment:attachment];
            [attributedTitle insertAttributedString:imageString atIndex:0];
            [attributedTitle insertAttributedString:[[NSAttributedString alloc] initWithString:@" "] atIndex:1];
            
            [freezeAction setValue:attributedTitle forKey:@"attributedTitle"];
            [freezeAction setValue:[UIColor systemBlueColor] forKey:@"titleTextColor"];
        } @catch (NSException *exception) {
            NSLog(@"[WeaponX] ⚠️ Exception during attributed text creation: %@", exception);
            // Continue without styled text if there's an error
        }
    }
    
    // Add app info option
    UIAlertAction *infoAction = [UIAlertAction actionWithTitle:@"App Info"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull action) {
        @try {
            // Display app info in an alert
            NSString *version = appInfo[@"version"] ?: @"Unknown";
            
            // Fix: Use buildVersionString instead of buildNumber (per LSApplicationProxy category properties)
            NSString *buildNumber = appInfo[@"buildVersionString"] ?: appInfo[@"build"] ?: @"Unknown";
            
            // Log available keys to debug
            NSLog(@"[WeaponX] 📱 App Info keys: %@", [appInfo allKeys]);
            
            NSString *infoMessage = [NSString stringWithFormat:
                                   @"Bundle ID: %@\nVersion: %@\nBuild: %@\nFrozen: %@",
                                   bundleID, 
                                   version,
                                   buildNumber,
                                   isFrozen ? @"Yes" : @"No"];
            
            UIAlertController *infoAlert = [UIAlertController alertControllerWithTitle:appName
                                                                             message:infoMessage
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            
            // Add copy action to copy bundle ID
            UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"Copy Bundle ID"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction * _Nonnull action) {
                UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                [pasteboard setString:bundleID];
            }];
            
            // Add close action
            UIAlertAction *closeAction = [UIAlertAction actionWithTitle:@"Close"
                                                               style:UIAlertActionStyleCancel
                                                             handler:nil];
            
            [infoAlert addAction:copyAction];
            [infoAlert addAction:closeAction];
            [self presentViewController:infoAlert animated:YES completion:nil];
        } @catch (NSException *exception) {
            NSLog(@"[WeaponX] ⚠️ Exception during info view: %@", exception);
        }
    }];
    
    // Add backup/restore option
    UIAlertAction *backupRestoreAction = [UIAlertAction actionWithTitle:@"BACKUP/RESTORE"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
        @try {
            // Create and configure the backup/restore view controller
            AppDataBackupRestoreViewController *backupRestoreVC = [[AppDataBackupRestoreViewController alloc] init];
            
            // Configure it with the current app info if needed
            // We could store the bundleID and app name as properties if the VC needs them
            if ([backupRestoreVC respondsToSelector:@selector(setBundleID:)]) {
                [backupRestoreVC performSelector:@selector(setBundleID:) withObject:bundleID];
            }
            
            if ([backupRestoreVC respondsToSelector:@selector(setAppName:)]) {
                [backupRestoreVC performSelector:@selector(setAppName:) withObject:appName];
            }
            
            // Present the view controller with a navigation controller for better UX
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:backupRestoreVC];
            navController.modalPresentationStyle = UIModalPresentationFormSheet;
            [self presentViewController:navController animated:YES completion:nil];
        } @catch (NSException *exception) {
            NSLog(@"[WeaponX] ⚠️ Exception during backup/restore view: %@", exception);
        }
    }];
    
    // Add "Open in Settings" option with correct URL format for iOS Settings app
    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"Open in Settings"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * _Nonnull action) {
        @try {
            // Try multiple methods to open app settings
            [self openAppSettings:bundleID];
        } @catch (NSException *exception) {
            NSLog(@"[WeaponX] ⚠️ Exception opening settings: %@", exception);
            
            // Fallback to general settings as a last resort
            NSURL *generalSettingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            [[UIApplication sharedApplication] openURL:generalSettingsURL options:@{} completionHandler:nil];
        }
    }];
    
    // Add actions in logical order
    [actionSheet addAction:freezeAction];
    [actionSheet addAction:infoAction];
    [actionSheet addAction:backupRestoreAction]; // Add the new action
    [actionSheet addAction:settingsAction];
    
    // Add cancel option
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                         style:UIAlertActionStyleCancel
                                                       handler:nil];
    [actionSheet addAction:cancelAction];
    
    // For iPad support - set source view for popover
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = sender;
        actionSheet.popoverPresentationController.sourceRect = sender.bounds;
    }
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

// Keeping only one openAppSettings implementation - the more comprehensive one that calls tryAppPrefsFormat
// Remove the helper method for opening general settings as a fallback
- (void)openGeneralSettings {
    NSLog(@"[WeaponX] ⚠️ Falling back to general settings");
    NSURL *generalSettingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    [[UIApplication sharedApplication] openURL:generalSettingsURL options:@{} completionHandler:nil];
}

// Implementation of openAppSettings method
- (void)openAppSettings:(NSString *)bundleID {
    NSLog(@"[WeaponX] 🔍 Attempting to open settings for %@", bundleID);
    
    // Try all possible URL schemes with proper URL encoding
    NSString *encodedBundleID = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    // Priority 1: prefs:root=Privacy&path=APPLEID/[bundle-id] - as explicitly requested
    NSString *privacyPathUrlString = [NSString stringWithFormat:@"prefs:root=Privacy&path=APPLEID/%@", encodedBundleID];
    NSURL *privacyPathUrl = [NSURL URLWithString:privacyPathUrlString];
    
    NSLog(@"[WeaponX] 🔍 Trying URL: %@", privacyPathUrlString);
    
    // Check if the URL can be opened
    if ([[UIApplication sharedApplication] canOpenURL:privacyPathUrl]) {
        [[UIApplication sharedApplication] openURL:privacyPathUrl options:@{} completionHandler:^(BOOL success) {
            NSLog(@"[WeaponX] %@ Opening prefs:root=Privacy&path=APPLEID/%@", success ? @"✅" : @"❌", bundleID);
            
            if (!success) {
                // Continue with next method if this fails
                [self tryAppPrefsFormat:bundleID];
            }
        }];
        return;
    } else {
        NSLog(@"[WeaponX] ❌ Cannot open URL: %@", privacyPathUrlString);
        [self tryAppPrefsFormat:bundleID];
    }
}

// Try App-Prefs format - second priority as requested
- (void)tryAppPrefsFormat:(NSString *)bundleID {
    NSString *encodedBundleID = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    // Format variations to try
    NSArray *appPrefsFormats = @[
        [NSString stringWithFormat:@"App-Prefs:%@", encodedBundleID],
        [NSString stringWithFormat:@"App-prefs:root=%@", encodedBundleID],
        [NSString stringWithFormat:@"app-prefs:root=%@", encodedBundleID]
    ];
    
    // Try each format in order
    for (NSString *urlString in appPrefsFormats) {
        NSURL *url = [NSURL URLWithString:urlString];
        NSLog(@"[WeaponX] 🔍 Trying URL: %@", urlString);
        
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                NSLog(@"[WeaponX] %@ Opening %@", success ? @"✅" : @"❌", urlString);
                
                if (!success && [urlString isEqualToString:[appPrefsFormats lastObject]]) {
                    // If this was the last App-Prefs format and it failed, try other approaches
                    [self tryOtherApproaches:bundleID];
                }
            }];
            return;
        } else {
            NSLog(@"[WeaponX] ❌ Cannot open URL: %@", urlString);
        }
    }
    
    // If we get here, none of the App-Prefs formats worked
    [self tryOtherApproaches:bundleID];
}

// Try other approaches as fallbacks
- (void)tryOtherApproaches:(NSString *)bundleID {
    NSString *encodedBundleID = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    // Additional formats to try
    NSArray *otherFormats = @[
        [NSString stringWithFormat:@"prefs:root=General&path=ManagedConfigurationList/%@", encodedBundleID],
        [NSString stringWithFormat:@"app-settings:%@", encodedBundleID],
        [NSString stringWithFormat:@"prefs:root=SettingsForApp-%@", encodedBundleID]
    ];
    
    // Try each format in order
    for (NSString *urlString in otherFormats) {
        NSURL *url = [NSURL URLWithString:urlString];
        NSLog(@"[WeaponX] 🔍 Trying URL: %@", urlString);
        
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                NSLog(@"[WeaponX] %@ Opening %@", success ? @"✅" : @"❌", urlString);
                
                if (!success && [urlString isEqualToString:[otherFormats lastObject]]) {
                    // If this was the last format and it failed, try the universal method
                    [self tryUniversalSettingsMethod:bundleID];
                }
            }];
            return;
        } else {
            NSLog(@"[WeaponX] ❌ Cannot open URL: %@", urlString);
        }
    }
    
    // If we get here, none of the other formats worked
    [self tryUniversalSettingsMethod:bundleID];
}

// Try the universal settings method as last resort
- (void)tryUniversalSettingsMethod:(NSString *)bundleID {
    // Use UIApplicationOpenSettingsURLString with query parameter as a "universal" approach
    NSString *encodedBundleID = [bundleID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *settingsString = [NSString stringWithFormat:@"%@?app=%@", 
                             UIApplicationOpenSettingsURLString, 
                             encodedBundleID];
    NSURL *url = [NSURL URLWithString:settingsString];
    
    NSLog(@"[WeaponX] 🔍 Trying universal settings URL: %@", settingsString);
    
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        NSLog(@"[WeaponX] %@ Opening universal settings URL", success ? @"✅" : @"❌");
        
        if (!success) {
            // Last resort - open general settings
            NSLog(@"[WeaponX] ⚠️ All methods failed, falling back to general settings");
            NSURL *generalSettingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            [[UIApplication sharedApplication] openURL:generalSettingsURL options:@{} completionHandler:nil];
        }
    }];
}

// Remove the openGeneralSettings method since it's now included in the tryUniversalSettingsMethod

#pragma mark - Tools Button

- (void)toolsButtonTapped {
    ToolViewController *toolsVC = [[ToolViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:toolsVC];
    if (@available(iOS 15.0, *)) {
        // Modern styling for iOS 15+
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithDefaultBackground];
        navController.navigationBar.standardAppearance = appearance;
        navController.navigationBar.scrollEdgeAppearance = appearance;
    }
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)filesButtonTapped {
    FilesViewController *filesVC = [[FilesViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:filesVC];
    if (@available(iOS 15.0, *)) {
        // Modern styling for iOS 15+
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithDefaultBackground];
        navController.navigationBar.standardAppearance = appearance;
        navController.navigationBar.scrollEdgeAppearance = appearance;
    }
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)handleProfileChanged:(NSNotification *)notification {
    // This method is called when the profile changes
    NSLog(@"[WeaponX] Profile changed notification received");
    
    // Update the profile indicator to show the new profile
    [self updateProfileIndicator];
    
    // Refresh all identifier values in the UI
    [self refreshIdentifierValuesInUI];
    
    // Also refresh the apps list in case app scoping has changed
    [self loadSettings];
}

#pragma mark - Memory Management

- (void)dealloc {
    // Remove all notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end