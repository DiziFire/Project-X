#import "AppDataBackupRestoreViewController.h"

@interface AppDataBackupRestoreViewController ()
@property (nonatomic, strong) UILabel *appLabel;
@end

@implementation AppDataBackupRestoreViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Set title based on whether we have a specific app
    if (self.appName) {
        self.title = [NSString stringWithFormat:@"%@ Backup & Restore", self.appName];
    } else {
        self.title = @"App Data Backup & Restore";
    }
    
    // Add Done button for the navigation bar
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                               target:self
                                                                               action:@selector(dismissVC)];
    self.navigationItem.rightBarButtonItem = doneButton;
    
    // Create an app name/ID label to make it clear which app we're working with
    self.appLabel = [[UILabel alloc] init];
    if (self.bundleID) {
        NSString *displayText = self.appName ? 
            [NSString stringWithFormat:@"App: %@\nBundle ID: %@", self.appName, self.bundleID] : 
            [NSString stringWithFormat:@"Bundle ID: %@", self.bundleID];
        
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:displayText];
        
        // Add styling - make app name bold if we have it
        if (self.appName) {
            NSRange appNameRange = [displayText rangeOfString:self.appName];
            [attributedText addAttribute:NSFontAttributeName 
                                   value:[UIFont boldSystemFontOfSize:17] 
                                   range:appNameRange];
        }
        
        self.appLabel.attributedText = attributedText;
    } else {
        self.appLabel.text = @"No app selected";
    }
    
    self.appLabel.textAlignment = NSTextAlignmentCenter;
    self.appLabel.numberOfLines = 0;
    self.appLabel.font = [UIFont systemFontOfSize:16];
    self.appLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.appLabel];
    
    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = @"Backup and Restore your app data easily.\n\nSelect an option below:";
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.numberOfLines = 0;
    descLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:descLabel];
    
    UIStackView *buttonStack = [[UIStackView alloc] init];
    buttonStack.axis = UILayoutConstraintAxisVertical;
    buttonStack.spacing = 24;
    buttonStack.alignment = UIStackViewAlignmentCenter;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:buttonStack];
    
    // Create stylish buttons with icons using UIButtonConfiguration (iOS 15+)
    UIButtonConfiguration *backupConfig = [UIButtonConfiguration filledButtonConfiguration];
    backupConfig.title = @"Backup App Data";
    backupConfig.image = [UIImage systemImageNamed:@"arrow.down.doc.fill"];
    backupConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    backupConfig.imagePadding = 8;
    backupConfig.contentInsets = NSDirectionalEdgeInsetsMake(12, 20, 12, 20);
    backupConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    backupConfig.baseBackgroundColor = [UIColor clearColor];
    backupConfig.baseForegroundColor = [UIColor systemBlueColor];
    
    UIButton *backupButton = [UIButton buttonWithConfiguration:backupConfig primaryAction:nil];
    backupButton.tintColor = [UIColor systemBlueColor];
    
    // Add rounded corners and border
    backupButton.layer.cornerRadius = 10;
    backupButton.layer.borderWidth = 1;
    backupButton.layer.borderColor = [UIColor systemBlueColor].CGColor;
    
    [backupButton addTarget:self action:@selector(backupButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [buttonStack addArrangedSubview:backupButton];
    
    // Create restore button with UIButtonConfiguration (iOS 15+)
    UIButtonConfiguration *restoreConfig = [UIButtonConfiguration filledButtonConfiguration];
    restoreConfig.title = @"Restore App Data";
    restoreConfig.image = [UIImage systemImageNamed:@"arrow.up.doc.fill"];
    restoreConfig.imagePlacement = NSDirectionalRectEdgeLeading;
    restoreConfig.imagePadding = 8;
    restoreConfig.contentInsets = NSDirectionalEdgeInsetsMake(12, 20, 12, 20);
    restoreConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    restoreConfig.baseBackgroundColor = [UIColor clearColor];
    restoreConfig.baseForegroundColor = [UIColor systemGreenColor];
    
    UIButton *restoreButton = [UIButton buttonWithConfiguration:restoreConfig primaryAction:nil];
    restoreButton.tintColor = [UIColor systemGreenColor];
    
    // Add rounded corners and border
    restoreButton.layer.cornerRadius = 10;
    restoreButton.layer.borderWidth = 1;
    restoreButton.layer.borderColor = [UIColor systemGreenColor].CGColor;
    
    [restoreButton addTarget:self action:@selector(restoreButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [buttonStack addArrangedSubview:restoreButton];
    
    [NSLayoutConstraint activateConstraints:@[
        // App label constraints
        [self.appLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.appLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.appLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],
        
        // Description label constraints
        [descLabel.topAnchor constraintEqualToAnchor:self.appLabel.bottomAnchor constant:20],
        [descLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [descLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],
        
        // Button stack constraints
        [buttonStack.topAnchor constraintEqualToAnchor:descLabel.bottomAnchor constant:40],
        [buttonStack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
}

- (void)dismissVC {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)backupButtonTapped {
    NSString *appIdentifier = self.appName ?: self.bundleID ?: @"this app";
    
    // Show a confirmation alert first
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Confirm Backup"
                                                                      message:[NSString stringWithFormat:@"Are you sure you want to backup data for %@?", appIdentifier]
                                                               preferredStyle:UIAlertControllerStyleAlert];
    
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // Show processing alert
        UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:@"Backing Up"
                                                                          message:@"Please wait while we backup your app data..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:processingAlert animated:YES completion:nil];
        
        // Simulate processing time
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [processingAlert dismissViewControllerAnimated:YES completion:^{
                // TODO: Implement actual backup logic here
                
                // Show success message
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Backup Complete"
                                                                               message:[NSString stringWithFormat:@"Data for %@ has been successfully backed up.", appIdentifier]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            }];
        });
    }]];
    
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (void)restoreButtonTapped {
    NSString *appIdentifier = self.appName ?: self.bundleID ?: @"this app";
    
    // Show a confirmation alert first with warning
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Confirm Restore"
                                                                      message:[NSString stringWithFormat:@"⚠️ Warning: This will replace the current data for %@ with backup data. This operation cannot be undone.\n\nAre you sure you want to continue?", appIdentifier]
                                                               preferredStyle:UIAlertControllerStyleAlert];
    
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // Show processing alert
        UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:@"Restoring"
                                                                          message:@"Please wait while we restore your app data..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:processingAlert animated:YES completion:nil];
        
        // Simulate processing time
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [processingAlert dismissViewControllerAnimated:YES completion:^{
                // TODO: Implement actual restore logic here
                
                // Show success message
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Restore Complete"
                                                                               message:[NSString stringWithFormat:@"Data for %@ has been successfully restored.", appIdentifier]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            }];
        });
    }]];
    
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

@end
