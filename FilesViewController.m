#import "FilesViewController.h"
#import "FileManagerViewController.h"
#import <objc/runtime.h>

@interface FilesViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation FilesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Files";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Add Done button
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                                target:self 
                                                                                action:@selector(dismissViewController)];
    self.navigationItem.leftBarButtonItem = doneButton;
    
    // Setup scroll view for content
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];
    
    // Add repo section
    [self setupRepoSection];
    
    // Add shadow section
    [self setupShadowSection];
    
    // Add AppStore++ section
    [self setupAppStorePPSection];
    
    // Add Crane section
    [self setupCraneSection];
    
    // Add AppDump3 section
    [self setupAppDump3Section];
    
    // Add Shadowrocket section
    [self setupShadowrocketSection];
    
    // Add Filza section
    [self setupFilzaSection];
    
    // Add TrollStore Helper section
    [self setupTrollStoreHelperSection];
    
    // Add more coming soon section
    [self setupComingSoonSection];
    
    // Add separator line
    [self setupSeparatorLine];
    
    // Add file browser section
    [self setupFileBrowserSection];
    
    // Set content size to ensure scrolling works - increased for new sections
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, 1900);
}

- (void)setupRepoSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 20, self.view.bounds.size.width - 40, 180)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"Add Repository";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Repo URL
    UILabel *repoLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 25)];
    repoLabel.text = @"https://repo.misty.moe/apt/";
    repoLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    repoLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:repoLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 75, cardView.bounds.size.width - 30, 40)];
    descLabel.text = @"Add this repository to your package manager to install Shadow and other tweaks.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Add package manager buttons
    NSArray *packageManagers = @[@"Sileo", @"Zebra", @"Cydia"];
    NSArray *icons = @[@"arrow.down.circle.fill", @"striped.bars.corner.forward", @"app.badge.checkmark.fill"];
    NSArray *colors = @[[UIColor systemBlueColor], [UIColor systemIndigoColor], [UIColor systemOrangeColor]];
    
    CGFloat buttonWidth = (cardView.bounds.size.width - 50) / 3;
    CGFloat buttonY = 125;
    
    for (NSInteger i = 0; i < packageManagers.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(15 + (buttonWidth + 10) * i, buttonY, buttonWidth, 40);
        button.backgroundColor = [colors[i] colorWithAlphaComponent:0.1];
        button.layer.cornerRadius = 10;
        button.tag = i;
        [button addTarget:self action:@selector(addRepoTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        // Set button configuration for iOS 15+
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
            config.baseBackgroundColor = [colors[i] colorWithAlphaComponent:0.1];
            config.baseForegroundColor = colors[i];
            config.title = packageManagers[i];
            config.image = [UIImage systemImageNamed:icons[i]];
            config.imagePlacement = NSDirectionalRectEdgeLeading;
            config.imagePadding = 5;
            config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
            button.configuration = config;
        } else {
            [button setTitle:packageManagers[i] forState:UIControlStateNormal];
            [button setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];
            button.tintColor = colors[i];
            
            // Handle button styling for older iOS
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            button.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
            button.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
            #pragma clang diagnostic pop
        }
        
        [cardView addSubview:button];
    }
}

- (void)setupShadowSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 220, self.view.bounds.size.width - 40, 180)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"Shadow Jailbreak Bypass";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Package ID
    UILabel *packageLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 25)];
    packageLabel.text = @"me.jjolano.shadow";
    packageLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    packageLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:packageLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 75, cardView.bounds.size.width - 30, 60)];
    descLabel.text = @"Shadow is a powerful jailbreak detection bypass tweak that helps hide your jailbreak from apps that implement jailbreak detection.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 3;
    [cardView addSubview:descLabel];
    
    // Add download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.frame = CGRectMake(15, 140, cardView.bounds.size.width - 30, 25);
    downloadButton.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.1];
    downloadButton.layer.cornerRadius = 10;
    [downloadButton addTarget:self action:@selector(downloadShadowTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Set button configuration for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.1];
        config.baseForegroundColor = [UIColor systemGreenColor];
        config.title = @"Download Shadow";
        config.image = [UIImage systemImageNamed:@"arrow.down.app.fill"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        downloadButton.configuration = config;
    } else {
        [downloadButton setTitle:@"Download Shadow" forState:UIControlStateNormal];
        [downloadButton setImage:[UIImage systemImageNamed:@"arrow.down.app.fill"] forState:UIControlStateNormal];
        downloadButton.tintColor = [UIColor systemGreenColor];
        
        // Handle button styling for older iOS
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        downloadButton.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
        #pragma clang diagnostic pop
    }
    
    [cardView addSubview:downloadButton];
}

- (void)setupAppStorePPSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 420, self.view.bounds.size.width - 40, 160)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"AppStore++";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 50)];
    descLabel.text = @"Allows you to downgrade or upgrade apps to specific versions. Supports TrollStore installation.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Source label
    UILabel *sourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 95, cardView.bounds.size.width - 30, 20)];
    sourceLabel.text = @"Source: github.com/DiziFire/JAILBREAKFILES";
    sourceLabel.font = [UIFont systemFontOfSize:12];
    sourceLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:sourceLabel];
    
    // Add download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.frame = CGRectMake(15, 120, cardView.bounds.size.width - 30, 25);
    downloadButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.1];
    downloadButton.layer.cornerRadius = 10;
    [downloadButton addTarget:self action:@selector(downloadAppStorePlusPlusTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Set button configuration for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.1];
        config.baseForegroundColor = [UIColor systemBlueColor];
        config.title = @"Download AppStore++ IPA";
        config.image = [UIImage systemImageNamed:@"arrow.down.app"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        downloadButton.configuration = config;
    } else {
        [downloadButton setTitle:@"Download AppStore++ IPA" forState:UIControlStateNormal];
        [downloadButton setImage:[UIImage systemImageNamed:@"arrow.down.app"] forState:UIControlStateNormal];
        downloadButton.tintColor = [UIColor systemBlueColor];
        
        // Handle button styling for older iOS
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        downloadButton.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
        #pragma clang diagnostic pop
    }
    
    [cardView addSubview:downloadButton];
}

- (void)setupCraneSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 600, self.view.bounds.size.width - 40, 160)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"Crane";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 50)];
    descLabel.text = @"Crane lets you create multiple containers for apps, allowing you to use multiple accounts simultaneously.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Source label
    UILabel *sourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 95, cardView.bounds.size.width - 30, 20)];
    sourceLabel.text = @"Source: github.com/DiziFire/JAILBREAKFILES";
    sourceLabel.font = [UIFont systemFontOfSize:12];
    sourceLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:sourceLabel];
    
    // Add download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.frame = CGRectMake(15, 120, cardView.bounds.size.width - 30, 25);
    downloadButton.backgroundColor = [[UIColor systemPurpleColor] colorWithAlphaComponent:0.1];
    downloadButton.layer.cornerRadius = 10;
    [downloadButton addTarget:self action:@selector(downloadCraneTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Set button configuration for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [[UIColor systemPurpleColor] colorWithAlphaComponent:0.1];
        config.baseForegroundColor = [UIColor systemPurpleColor];
        config.title = @"Download Crane DEB";
        config.image = [UIImage systemImageNamed:@"archivebox.fill"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        downloadButton.configuration = config;
    } else {
        [downloadButton setTitle:@"Download Crane DEB" forState:UIControlStateNormal];
        [downloadButton setImage:[UIImage systemImageNamed:@"archivebox.fill"] forState:UIControlStateNormal];
        downloadButton.tintColor = [UIColor systemPurpleColor];
        
        // Handle button styling for older iOS
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        downloadButton.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
        #pragma clang diagnostic pop
    }
    
    [cardView addSubview:downloadButton];
}

- (void)setupAppDump3Section {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 780, self.view.bounds.size.width - 40, 160)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"AppsDump3";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 50)];
    descLabel.text = @"Tool to dump and extract iOS apps from your device. Useful for creating TrollStore compatible IPAs.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Source label
    UILabel *sourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 95, cardView.bounds.size.width - 30, 20)];
    sourceLabel.text = @"Source: github.com/DiziFire/JAILBREAKFILES";
    sourceLabel.font = [UIFont systemFontOfSize:12];
    sourceLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:sourceLabel];
    
    // Add download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.frame = CGRectMake(15, 120, cardView.bounds.size.width - 30, 25);
    downloadButton.backgroundColor = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.1];
    downloadButton.layer.cornerRadius = 10;
    [downloadButton addTarget:self action:@selector(downloadAppDump3Tapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Set button configuration for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [[UIColor systemOrangeColor] colorWithAlphaComponent:0.1];
        config.baseForegroundColor = [UIColor systemOrangeColor];
        config.title = @"Download AppsDump3 TIPA";
        config.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        downloadButton.configuration = config;
    } else {
        [downloadButton setTitle:@"Download AppsDump3 TIPA" forState:UIControlStateNormal];
        [downloadButton setImage:[UIImage systemImageNamed:@"square.and.arrow.down"] forState:UIControlStateNormal];
        downloadButton.tintColor = [UIColor systemOrangeColor];
        
        // Handle button styling for older iOS
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        downloadButton.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
        #pragma clang diagnostic pop
    }
    
    [cardView addSubview:downloadButton];
}

- (void)setupShadowrocketSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 960, self.view.bounds.size.width - 40, 160)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"Shadowrocket";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 50)];
    descLabel.text = @"Network tool for iOS that provides web debugging proxy and custom proxy/socks capabilities.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Source label
    UILabel *sourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 95, cardView.bounds.size.width - 30, 20)];
    sourceLabel.text = @"Source: github.com/DiziFire/JAILBREAKFILES";
    sourceLabel.font = [UIFont systemFontOfSize:12];
    sourceLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:sourceLabel];
    
    // Add download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.frame = CGRectMake(15, 120, cardView.bounds.size.width - 30, 25);
    downloadButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
    downloadButton.layer.cornerRadius = 10;
    [downloadButton addTarget:self action:@selector(downloadShadowrocketTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Set button configuration for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
        config.baseForegroundColor = [UIColor systemRedColor];
        config.title = @"Download Shadowrocket IPA";
        config.image = [UIImage systemImageNamed:@"network"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        downloadButton.configuration = config;
    } else {
        [downloadButton setTitle:@"Download Shadowrocket IPA" forState:UIControlStateNormal];
        [downloadButton setImage:[UIImage systemImageNamed:@"network"] forState:UIControlStateNormal];
        downloadButton.tintColor = [UIColor systemRedColor];
        
        // Handle button styling for older iOS
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        downloadButton.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
        #pragma clang diagnostic pop
    }
    
    [cardView addSubview:downloadButton];
}

- (void)setupFilzaSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 1140, self.view.bounds.size.width - 40, 160)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"Filza File Manager";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 50)];
    descLabel.text = @"The most advanced file manager for iOS with full filesystem access. Custom ClayUI version.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Source label
    UILabel *sourceLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 95, cardView.bounds.size.width - 30, 20)];
    sourceLabel.text = @"Source: github.com/DiziFire/JAILBREAKFILES";
    sourceLabel.font = [UIFont systemFontOfSize:12];
    sourceLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:sourceLabel];
    
    // Add download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.frame = CGRectMake(15, 120, cardView.bounds.size.width - 30, 25);
    downloadButton.backgroundColor = [[UIColor systemTealColor] colorWithAlphaComponent:0.1];
    downloadButton.layer.cornerRadius = 10;
    [downloadButton addTarget:self action:@selector(downloadFilzaTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // Set button configuration for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [[UIColor systemTealColor] colorWithAlphaComponent:0.1];
        config.baseForegroundColor = [UIColor systemTealColor];
        config.title = @"Download Filza TIPA";
        config.image = [UIImage systemImageNamed:@"folder.fill"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        downloadButton.configuration = config;
    } else {
        [downloadButton setTitle:@"Download Filza TIPA" forState:UIControlStateNormal];
        [downloadButton setImage:[UIImage systemImageNamed:@"folder.fill"] forState:UIControlStateNormal];
        downloadButton.tintColor = [UIColor systemTealColor];
        
        // Handle button styling for older iOS
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        downloadButton.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
        #pragma clang diagnostic pop
    }
    
    [cardView addSubview:downloadButton];
}

- (void)setupTrollStoreHelperSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 1320, self.view.bounds.size.width - 40, 140)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"TrollStore Helper";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 40)];
    descLabel.text = @"Helper utility to install or update TrollStore on supported iOS versions.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Package ID
    UILabel *packageLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 90, cardView.bounds.size.width - 30, 20)];
    packageLabel.text = @"com.opa334.trollstorehelper";
    packageLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    packageLabel.textColor = [UIColor secondaryLabelColor];
    [cardView addSubview:packageLabel];
    
    // Add download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.frame = CGRectMake(15, 110, cardView.bounds.size.width - 30, 25);
    downloadButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
    downloadButton.layer.cornerRadius = 10;
    [downloadButton addTarget:self action:@selector(openTrollStoreHelperInSileo) forControlEvents:UIControlEventTouchUpInside];
    
    // Set button configuration for iOS 15+
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
        config.baseForegroundColor = [UIColor systemRedColor];
        config.title = @"Open in Sileo";
        config.image = [UIImage systemImageNamed:@"arrowshape.turn.up.right.fill"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        downloadButton.configuration = config;
    } else {
        [downloadButton setTitle:@"Open in Sileo" forState:UIControlStateNormal];
        [downloadButton setImage:[UIImage systemImageNamed:@"arrowshape.turn.up.right.fill"] forState:UIControlStateNormal];
        downloadButton.tintColor = [UIColor systemRedColor];
        
        // Handle button styling for older iOS
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        downloadButton.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
        downloadButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 5);
        #pragma clang diagnostic pop
    }
    
    [cardView addSubview:downloadButton];
}

- (void)setupComingSoonSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 1480, self.view.bounds.size.width - 40, 140)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"More Options Coming Soon";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 75)];
    descLabel.text = @"We're working on additional features for this section including more tweaks, utilities for rootless jailbreak, and file management tools.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 4;
    [cardView addSubview:descLabel];
}

- (void)setupSeparatorLine {
    // Create a separator line
    UIView *separatorLine = [[UIView alloc] initWithFrame:CGRectMake(40, 1640, self.view.bounds.size.width - 80, 2)];
    separatorLine.backgroundColor = [UIColor separatorColor];
    [self.scrollView addSubview:separatorLine];
    
    // Add text label on top of the line
    UILabel *separatorLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 1630, self.view.bounds.size.width, 20)];
    separatorLabel.text = @"ADVANCED FEATURES";
    separatorLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    separatorLabel.textColor = [UIColor secondaryLabelColor];
    separatorLabel.textAlignment = NSTextAlignmentCenter;
    separatorLabel.backgroundColor = [UIColor systemBackgroundColor];
    [self.scrollView addSubview:separatorLabel];
    
    // Create a background view to properly show the label over the line
    UIView *labelBackgroundView = [[UIView alloc] initWithFrame:CGRectMake(separatorLabel.center.x - 80, 1630, 160, 20)];
    labelBackgroundView.backgroundColor = [UIColor systemBackgroundColor];
    [self.scrollView insertSubview:labelBackgroundView belowSubview:separatorLabel];
}

- (void)setupFileBrowserSection {
    // Create card container
    UIView *cardView = [self createCardWithFrame:CGRectMake(20, 1660, self.view.bounds.size.width - 40, 220)];
    [self.scrollView addSubview:cardView];
    
    // Header
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, cardView.bounds.size.width - 30, 30)];
    headerLabel.text = @"System File Browser";
    headerLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    headerLabel.textColor = [UIColor labelColor];
    [cardView addSubview:headerLabel];
    
    // Description
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, cardView.bounds.size.width - 30, 40)];
    descLabel.text = @"Browse and manage files on your jailbroken iOS device. Quickly access important directories.";
    descLabel.font = [UIFont systemFontOfSize:14];
    descLabel.textColor = [UIColor labelColor];
    descLabel.numberOfLines = 2;
    [cardView addSubview:descLabel];
    
    // Create shortcut buttons container
    UIView *shortcutsContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 100, cardView.bounds.size.width - 30, 80)];
    shortcutsContainer.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    shortcutsContainer.layer.cornerRadius = 10;
    [cardView addSubview:shortcutsContainer];
    
    // Directory shortcuts
    NSArray *directories = @[
        @{@"title": @"Library", @"path": @"/var/jb/var/mobile/Library", @"icon": @"folder.fill.badge.person.crop"},
        @{@"title": @"Documents", @"path": @"/var/jb/var/mobile/Documents", @"icon": @"doc.fill"},
        @{@"title": @"Root", @"path": @"/var/jb", @"icon": @"terminal.fill"},
        @{@"title": @"Applications", @"path": @"/var/jb/Applications", @"icon": @"app.fill"}
    ];
    
    CGFloat buttonWidth = (shortcutsContainer.bounds.size.width - 30) / 4;
    
    for (NSInteger i = 0; i < directories.count; i++) {
        NSDictionary *dirInfo = directories[i];
        
        UIButton *dirButton = [UIButton buttonWithType:UIButtonTypeSystem];
        dirButton.frame = CGRectMake(10 + (buttonWidth * i), 10, buttonWidth, 60);
        
        // Different styling approach for iOS 15+ vs older iOS
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.imagePlacement = NSDirectionalRectEdgeTop;
            config.imagePadding = 5;
            config.title = dirInfo[@"title"];
            config.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
            config.baseForegroundColor = [UIColor labelColor];
            config.image = [UIImage systemImageNamed:dirInfo[@"icon"]];
            
            // Create a smaller font
            UIFont *smallFont = [UIFont systemFontOfSize:9];
            config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
                NSMutableDictionary *newAttributes = [attributes mutableCopy];
                newAttributes[NSFontAttributeName] = smallFont;
                return newAttributes;
            };
            
            dirButton.configuration = config;
        } else {
            [dirButton setImage:[UIImage systemImageNamed:dirInfo[@"icon"]] forState:UIControlStateNormal];
            [dirButton setTitle:dirInfo[@"title"] forState:UIControlStateNormal];
            dirButton.titleLabel.font = [UIFont systemFontOfSize:9];
            dirButton.tintColor = [UIColor labelColor];
            
            // Center image and put title below
            dirButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
            
            // Handle vertical alignment for iOS 14 and below
            [dirButton setContentVerticalAlignment:UIControlContentVerticalAlignmentTop];
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            dirButton.imageEdgeInsets = UIEdgeInsetsMake(5, 0, 0, 0);
            dirButton.titleEdgeInsets = UIEdgeInsetsMake(40, -30, 0, 0);
            #pragma clang diagnostic pop
        }
        
        // Store path in tag for access in action method
        dirButton.tag = i;
        [dirButton addTarget:self action:@selector(openDirectoryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [shortcutsContainer addSubview:dirButton];
    }
    
    // Add browse button
    UIButton *browseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    browseButton.frame = CGRectMake(15, 190, cardView.bounds.size.width - 30, 15);
    [browseButton setTitle:@"Open Full File Browser" forState:UIControlStateNormal];
    [browseButton addTarget:self action:@selector(openFullFileBrowserTapped) forControlEvents:UIControlEventTouchUpInside];
    [cardView addSubview:browseButton];
}

- (void)openDirectoryButtonTapped:(UIButton *)sender {
    NSArray *directories = @[
        @"/var/jb/var/mobile/Library",
        @"/var/jb/var/mobile/Documents",
        @"/var/jb",
        @"/var/jb/Applications"
    ];
    
    NSString *path = directories[sender.tag];
    
    // Use our own file browser
    FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:path];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)openFullFileBrowserTapped {
    // Present our own file browser
    FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:@"/var/jb"];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navController animated:YES completion:nil];
}

- (UIView *)createCardWithFrame:(CGRect)frame {
    UIView *cardView = [[UIView alloc] initWithFrame:frame];
    cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    cardView.layer.cornerRadius = 15;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOpacity = 0.1;
    cardView.layer.shadowOffset = CGSizeMake(0, 2);
    cardView.layer.shadowRadius = 5;
    return cardView;
}

- (void)addRepoTapped:(UIButton *)sender {
    NSString *repoURL = @"https://repo.misty.moe/apt/";
    NSString *packageManager = @"";
    NSString *urlScheme = @"";
    
    switch (sender.tag) {
        case 0: // Sileo
            packageManager = @"Sileo";
            urlScheme = [NSString stringWithFormat:@"sileo://source/%@", [self encodeURLString:repoURL]];
            break;
        case 1: // Zebra
            packageManager = @"Zebra";
            urlScheme = [NSString stringWithFormat:@"zbra://sources/%@", [self encodeURLString:repoURL]];
            break;
        case 2: // Cydia
            packageManager = @"Cydia";
            urlScheme = [NSString stringWithFormat:@"cydia://url/https://cydia.saurik.com/api/share#?source=%@", [self encodeURLString:repoURL]];
            break;
        default:
            break;
    }
    
    NSURL *url = [NSURL URLWithString:urlScheme];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [self showAlertWithTitle:@"Cannot Open Package Manager" 
                         message:[NSString stringWithFormat:@"%@ is not installed on this device.", packageManager]];
    }
}

- (void)downloadShadowTapped {
    NSString *urlScheme = @"";
    NSString *packageID = @"me.jjolano.shadow";
    
    // Try Sileo first
    urlScheme = [NSString stringWithFormat:@"sileo://package/%@", packageID];
    NSURL *url = [NSURL URLWithString:urlScheme];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    // Try Zebra
    urlScheme = [NSString stringWithFormat:@"zbra://packages/search?q=%@", packageID];
    url = [NSURL URLWithString:urlScheme];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    // Try Cydia
    urlScheme = [NSString stringWithFormat:@"cydia://package/%@", packageID];
    url = [NSURL URLWithString:urlScheme];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    // If no package manager is found
    [self showAlertWithTitle:@"No Package Manager Found" 
                     message:@"Please install a package manager like Sileo, Zebra, or Cydia first."];
}

- (void)downloadAppStorePlusPlusTapped {
    // Open Safari to download the file
    NSURL *url = [NSURL URLWithString:@"https://github.com/DiziFire/JAILBREAKFILES/raw/main/AppStore%2B%2B_TrollStore_v1.0.3-2.ipa"];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [self showAlertWithTitle:@"Download Error" 
                         message:@"Unable to open download URL. Please check your internet connection."];
    }
}

- (void)downloadCraneTapped {
    // Open Safari to download the file
    NSURL *url = [NSURL URLWithString:@"https://github.com/DiziFire/JAILBREAKFILES/raw/main/com.opa334.crane_1.3.16-4_iphoneos-arm64e-1.deb"];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [self showAlertWithTitle:@"Download Error" 
                         message:@"Unable to open download URL. Please check your internet connection."];
    }
}

- (void)downloadAppDump3Tapped {
    // Open Safari to download the file
    NSURL *url = [NSURL URLWithString:@"https://github.com/DiziFire/JAILBREAKFILES/raw/main/AppsDump3.tipa"];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [self showAlertWithTitle:@"Download Error" 
                         message:@"Unable to open download URL. Please check your internet connection."];
    }
}

- (void)downloadShadowrocketTapped {
    // Open Safari to download the file
    NSURL *url = [NSURL URLWithString:@"https://github.com/DiziFire/JAILBREAKFILES/raw/main/Shadowrocket_2.2.54.ipa"];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [self showAlertWithTitle:@"Download Error" 
                         message:@"Unable to open download URL. Please check your internet connection."];
    }
}

- (void)downloadFilzaTapped {
    // Open Safari to download the file
    NSURL *url = [NSURL URLWithString:@"https://github.com/DiziFire/JAILBREAKFILES/raw/main/Filza%20-%20No%20URL%20-%20MOD%20ClayUI.tipa"];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [self showAlertWithTitle:@"Download Error" 
                         message:@"Unable to open download URL. Please check your internet connection."];
    }
}

- (void)openTrollStoreHelperInSileo {
    // Open TrollStore Helper in Sileo
    NSURL *url = [NSURL URLWithString:@"sileo://package/com.opa334.trollstorehelper"];
    
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [self showAlertWithTitle:@"Cannot Open Sileo" 
                         message:@"Sileo is not installed on this device. Please install Sileo first."];
    }
}

- (NSString *)encodeURLString:(NSString *)string {
    return [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end 