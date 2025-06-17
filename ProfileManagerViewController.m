#import "ProfileManagerViewController.h"
#import "ProfileManager.h"

// Custom ProfileTableViewCell class
@interface ProfileTableViewCell : UITableViewCell

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *innerCard;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *idLabel;
@property (nonatomic, strong) UIButton *renameButton;
@property (nonatomic, strong) UIButton *infoButton;
@property (nonatomic, strong) UIButton *timeButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UIButton *switchButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, assign) BOOL isCurrentProfile;

- (void)configureWithProfile:(Profile *)profile isCurrentProfile:(BOOL)isCurrentProfile tableWidth:(CGFloat)tableWidth;

@end

@interface ProfileManagerViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIDocumentInteractionControllerDelegate>

@property (nonatomic, strong) UIBarButtonItem *editButton;
@property (nonatomic, strong) UIBarButtonItem *doneButton;
@property (nonatomic, strong) NSDictionary *storageInfo;
@property (nonatomic, strong) UILabel *profileCountLabel;
@property (nonatomic, strong) UILabel *currentProfileIdLabel;
@property (nonatomic, strong) NSMutableArray<Profile *> *filteredProfiles;
@property (nonatomic, strong) NSMutableArray<Profile *> *allProfiles;
@property (nonatomic, assign) NSInteger displayedProfilesCount;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, assign) BOOL isSearchActive;
@property (nonatomic, strong) UIImageView *searchIcon;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIDocumentInteractionController *documentInteractionController;

@end

@implementation ProfileManagerViewController

- (instancetype)initWithProfiles:(NSMutableArray<Profile *> *)profiles {
    self = [super init];
    if (self) {
        if (profiles) {
            _profiles = profiles;
        } else {
            _profiles = [NSMutableArray array];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.filteredProfiles = [NSMutableArray array];
    self.isSearchActive = NO;
    [self setupUI];
    [self updateStorageInfo];
    
    // Setup tap gesture to dismiss keyboard
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    // Optimize tableview for smoother scrolling
    self.tableView.estimatedRowHeight = 0;
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.estimatedSectionFooterHeight = 0;
    self.tableView.showsVerticalScrollIndicator = NO;
    
    // Register custom profile cell class
    [self.tableView registerClass:[ProfileTableViewCell class] forCellReuseIdentifier:@"ProfileCell"];
    
    // Pre-layout cells to avoid resize delays
    [self.tableView prefetchDataSource];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // First check central profile info to ensure we have the latest active profile ID
    ProfileManager *manager = [ProfileManager sharedManager];
    NSDictionary *centralInfo = [manager loadCentralProfileInfo];
    
    if (centralInfo && centralInfo[@"ProfileId"]) {
        NSString *activeProfileId = centralInfo[@"ProfileId"];
        
        // Check if manager's currentProfile is aligned with central store
        if (manager.currentProfile && ![manager.currentProfile.profileId isEqualToString:activeProfileId]) {
            // Find profile with ID from central store
            for (Profile *profile in self.allProfiles) {
                if ([profile.profileId isEqualToString:activeProfileId]) {
                    // Update manager's currentProfile
                    [manager updateCurrentProfileInfoWithProfile:profile];
                    break;
                }
            }
        }
    }
    
    // Load profiles directly from disk
    [self loadProfilesFromDisk];
    
    // Update storage info
    [self updateStorageInfo];
}

- (void)updateStorageInfo {
    NSError *error = nil;
    NSURL *documentURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    
    if (error) {
        return;
    }
    
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:documentURL.path error:&error];
    
    if (error) {
        return;
    }
    
    NSNumber *totalSpace = attributes[NSFileSystemSize];
    NSNumber *freeSpace = attributes[NSFileSystemFreeSize];
    
    if (totalSpace && freeSpace) {
        self.storageInfo = @{
            @"totalSpace": totalSpace,
            @"freeSpace": freeSpace
        };
        
        [self.tableView reloadData];
    }
}

- (void)loadProfilesFromDisk {
    // Get active profile ID directly from central info store first
    ProfileManager *manager = [ProfileManager sharedManager];
    NSDictionary *centralInfo = [manager loadCentralProfileInfo];
    NSString *activeProfileId = nil;
    
    if (centralInfo && centralInfo[@"ProfileId"]) {
        activeProfileId = centralInfo[@"ProfileId"];
    } else if (manager.currentProfile) {
        activeProfileId = manager.currentProfile.profileId;
    }
    
    // Get profiles directory path
    NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
    
    // Get file manager
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Check if directory exists
    if (![fileManager fileExistsAtPath:profilesDirectory]) {
        self.profiles = [NSMutableArray array];
        self.allProfiles = [NSMutableArray array];
        self.displayedProfilesCount = 0;
        [self.tableView reloadData];
        [self updateProfileCount];
        return;
    }
    
    // First try to load from profiles.plist
    NSString *profilesPath = [profilesDirectory stringByAppendingPathComponent:@"profiles.plist"];
    if ([fileManager fileExistsAtPath:profilesPath]) {
        NSData *data = [NSData dataWithContentsOfFile:profilesPath];
        if (data) {
            NSError *error = nil;
            
            // Use the modern non-deprecated API for iOS 15+
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
            if (error) {
                // Handle error silently
            } else {
                unarchiver.requiresSecureCoding = YES;
                NSArray *loadedProfiles = [unarchiver decodeObjectOfClass:[NSArray class] forKey:NSKeyedArchiveRootObjectKey];
                
                if (loadedProfiles) {
                    // Filter out profiles with ID 0
                    NSMutableArray *filteredProfiles = [NSMutableArray array];
                    for (Profile *profile in loadedProfiles) {
                        // Skip profiles with ID 0, "0", "profile_0", or missing profileId
                        if (!profile.profileId || 
                            [profile.profileId isEqualToString:@"0"] || 
                            [profile.profileId isEqualToString:@"profile_0"] ||
                            [profile.profileId intValue] == 0) {
                            NSLog(@"[WeaponX] Filtering out profile with ID 0: %@", profile.name);
                            continue;
                        }
                        [filteredProfiles addObject:profile];
                    }
                    
                    self.allProfiles = filteredProfiles;
                    
                    // Get first 10 profiles or all if less than 10
                    NSInteger initialCount = MIN(10, self.allProfiles.count);
                    NSRange initialRange = NSMakeRange(0, initialCount);
                    self.profiles = [[self.allProfiles subarrayWithRange:initialRange] mutableCopy];
                    self.displayedProfilesCount = initialCount;
                    
                    self.filteredProfiles = [self.profiles mutableCopy];
                    
                    // Make sure each profile has a proper display name and ensure shortDescription is set
                    [self enrichProfilesWithAdditionalInfo];
                    
                    [self.tableView reloadData];
                    [self updateProfileCount];
                    return;
                } else {
                    // Failed to decode profiles: nil result
                }
            }
        }
    }
    
    // If profiles.plist couldn't be loaded, scan directory for profile folders
    NSError *error = nil;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:profilesDirectory error:&error];
    
    if (error) {
        self.profiles = [NSMutableArray array];
        self.allProfiles = [NSMutableArray array];
        self.displayedProfilesCount = 0;
        [self.tableView reloadData];
        [self updateProfileCount];
        return;
    }
    
    NSMutableArray *allProfilesFound = [NSMutableArray array];
    for (NSString *item in contents) {
        NSString *itemPath = [profilesDirectory stringByAppendingPathComponent:item];
        BOOL isDirectory = NO;
        
        // Skip non-directories, the profiles.plist file, profiles with ID 0 or profile_0
        if (![fileManager fileExistsAtPath:itemPath isDirectory:&isDirectory] || 
            !isDirectory || 
            [item isEqualToString:@"profiles.plist"] ||
            [item isEqualToString:@"0"] ||
            [item isEqualToString:@"profile_0"] ||
            [item intValue] == 0) {
            continue;
        }
        
        // Extract additional profile info from plists within the profile directory
        NSString *displayName = [self extractProfileDisplayNameFromDirectory:itemPath withFolderName:item];
        NSString *shortDesc = [self extractProfileShortDescriptionFromDirectory:itemPath withFolderName:item];
        
        // Create a profile object with the discovered information
        Profile *profile = [[Profile alloc] initWithName:displayName ? displayName : item 
                                        shortDescription:shortDesc ? shortDesc : @""
                                               iconName:@"default_profile"];
        
        // Make sure the profileId is set to the folder name for accuracy
        [profile setValue:item forKey:@"profileId"];
        
        // Set timestamps
        NSDate *creationDate = nil;
        NSDate *modificationDate = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:itemPath error:nil];
        if (attributes) {
            creationDate = attributes[NSFileCreationDate];
            modificationDate = attributes[NSFileModificationDate];
        }
        
        if (creationDate) {
            [profile setValue:creationDate forKey:@"createdAt"];
        }
        
        if (modificationDate) {
            [profile setValue:modificationDate forKey:@"lastUsed"];
        }
        
        [allProfilesFound addObject:profile];
    }
    
    self.allProfiles = allProfilesFound;
    
    // Get first 10 profiles or all if less than 10
    NSInteger initialCount = MIN(10, self.allProfiles.count);
    if (initialCount > 0) {
        NSRange initialRange = NSMakeRange(0, initialCount);
        self.profiles = [[self.allProfiles subarrayWithRange:initialRange] mutableCopy];
    } else {
        self.profiles = [NSMutableArray array];
    }
    self.displayedProfilesCount = initialCount;
    
    self.filteredProfiles = [self.profiles mutableCopy];
    
    // If we have an active profile ID, ensure it's correctly updated
    if (activeProfileId) {
        for (Profile *profile in self.allProfiles) {
            if ([profile.profileId isEqualToString:activeProfileId]) {
                [manager updateCurrentProfileInfoWithProfile:profile];
                
                // If active profile isn't in the first set of displayed profiles,
                // make sure it's included by adding it to the beginning
                if (![self.profiles containsObject:profile]) {
                    [self.profiles insertObject:profile atIndex:0];
                    self.displayedProfilesCount = MIN(self.allProfiles.count, self.displayedProfilesCount + 1);
                }
                break;
            }
        }
    }
    
    [self.tableView reloadData];
    [self updateProfileCount];
}

// New method to extract the display name from profile directory plists
- (NSString *)extractProfileDisplayNameFromDirectory:(NSString *)directoryPath withFolderName:(NSString *)folderName {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // First check for identifiers.plist as it might contain display information
    NSString *identifiersPath = [directoryPath stringByAppendingPathComponent:@"identifiers.plist"];
    if ([fileManager fileExistsAtPath:identifiersPath]) {
        NSDictionary *identifiers = [NSDictionary dictionaryWithContentsOfFile:identifiersPath];
        if (identifiers && identifiers[@"DisplayName"]) {
            return identifiers[@"DisplayName"];
        }
    }
    
    // Check for scoped-apps.plist which might have a friendly name
    NSString *scopedAppsPath = [directoryPath stringByAppendingPathComponent:@"scoped-apps.plist"];
    if ([fileManager fileExistsAtPath:scopedAppsPath]) {
        NSDictionary *scopedApps = [NSDictionary dictionaryWithContentsOfFile:scopedAppsPath];
        if (scopedApps && scopedApps[@"ProfileName"]) {
            return scopedApps[@"ProfileName"];
        }
    }
    
    // Check for Info.plist which might have a profile name
    NSString *infoPath = [directoryPath stringByAppendingPathComponent:@"Info.plist"];
    if ([fileManager fileExistsAtPath:infoPath]) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        if (info && info[@"Name"]) {
            return info[@"Name"];
        }
    }
    
    // Check for appdata/Info.plist 
    NSString *appDataPath = [directoryPath stringByAppendingPathComponent:@"appdata/Info.plist"];
    if ([fileManager fileExistsAtPath:appDataPath]) {
        NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:appDataPath];
        if (appInfo && appInfo[@"ProfileName"]) {
            return appInfo[@"ProfileName"];
        }
    }
    
    // If nothing is found, just return the folder name with proper formatting
    // Convert profile_123 to "Profile 123"
    if ([folderName hasPrefix:@"profile_"]) {
        NSString *numberPart = [folderName substringFromIndex:8]; // Skip "profile_"
        return [NSString stringWithFormat:@"Profile %@", numberPart];
    }
    
    return folderName; // Default fallback
}

// New method to extract the short description from profile directory plists
- (NSString *)extractProfileShortDescriptionFromDirectory:(NSString *)directoryPath withFolderName:(NSString *)folderName {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Check various plists for description information
    NSArray *potentialPaths = @[
        [directoryPath stringByAppendingPathComponent:@"identifiers.plist"],
        [directoryPath stringByAppendingPathComponent:@"scoped-apps.plist"],
        [directoryPath stringByAppendingPathComponent:@"Info.plist"],
        [directoryPath stringByAppendingPathComponent:@"appdata/Info.plist"]
    ];
    
    NSArray *potentialKeys = @[@"Description", @"ShortDescription", @"ProfileDescription"];
    
    for (NSString *path in potentialPaths) {
        if ([fileManager fileExistsAtPath:path]) {
            NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:path];
            
            if (plistDict) {
                for (NSString *key in potentialKeys) {
                    if (plistDict[key] && [plistDict[key] isKindOfClass:[NSString class]]) {
                        return plistDict[key];
                    }
                }
            }
        }
    }
    
    // If we couldn't find a description, use a default based on ID
    return [NSString stringWithFormat:@"Profile ID: %@", folderName];
}

- (void)updateProfileCount {
    if (self.profileCountLabel) {
        // Use the count from all profiles array 
        NSInteger profileCount = self.allProfiles.count;
        
        NSString *countText = [NSString stringWithFormat:@"%ld", (long)profileCount];
        self.profileCountLabel.text = countText;
    }
    
    // Update the current profile ID label
    [self updateCurrentProfileIdLabel];
}

- (void)updateCurrentProfileIdLabel {
    if (self.currentProfileIdLabel) {
        // Get the active profile from central info store
        NSString *currentProfileId = @"—";
        
        // Get the current profile info from ProfileManager
        ProfileManager *manager = [ProfileManager sharedManager];
        NSDictionary *centralInfo = [manager loadCentralProfileInfo];
        
        if (centralInfo && centralInfo[@"ProfileId"]) {
            // Use the profile ID from central store (most reliable source)
            currentProfileId = centralInfo[@"ProfileId"];
        } else {
            // Fallback: check if manager has a current profile
            Profile *currentProfile = manager.currentProfile;
            if (currentProfile) {
                currentProfileId = currentProfile.profileId;
                
                // Since we found a profile but the central store didn't have it,
                // update the central store for future use
                [manager updateCurrentProfileInfoWithProfile:currentProfile];
            }
        }
        
        // Update the label with current profile ID
        self.currentProfileIdLabel.text = currentProfileId;
    }
}

- (void)setupUI {
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Setup custom title view with centered title and count
    UIView *titleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width - 100, 44)];
    
    // Profile count pill - on the left side
    UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 44, 24)];
    countLabel.text = @"0"; // Start with 0, will update after profiles are loaded
    countLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    countLabel.textColor = [UIColor systemBlueColor];
    countLabel.textAlignment = NSTextAlignmentCenter;
    countLabel.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.15];
    countLabel.layer.cornerRadius = 12;
    countLabel.layer.masksToBounds = YES;
    [titleView addSubview:countLabel];
    self.profileCountLabel = countLabel; // Save reference to update later
    
    // "Profiles" text - centered in the title view
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 0, 100, 44)];
    titleLabel.text = @"Profiles";
    titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleView addSubview:titleLabel];
    
    // Current profile ID pill - positioned on the right side
    UIView *rightContainer = [[UIView alloc] initWithFrame:CGRectMake(titleView.bounds.size.width - 70, 6, 70, 32)];
    rightContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
    rightContainer.layer.cornerRadius = 16;
    rightContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [titleView addSubview:rightContainer];
    
    // "Current" and "Profile" text as a two-line label to the left of the profile ID pill
    UIView *labelContainer = [[UIView alloc] initWithFrame:CGRectMake(rightContainer.frame.origin.x - 45, 6, 40, 32)];
    labelContainer.backgroundColor = [UIColor clearColor];
    [titleView addSubview:labelContainer];
    
    // "Current" text (top line)
    UILabel *currentLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, 40, 14)];
    currentLabel.text = @"Current";
    currentLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    currentLabel.textColor = [UIColor secondaryLabelColor];
    currentLabel.textAlignment = NSTextAlignmentRight;
    currentLabel.adjustsFontSizeToFitWidth = YES;
    currentLabel.minimumScaleFactor = 0.8;
    [labelContainer addSubview:currentLabel];
    
    // "Profile" text (bottom line)
    UILabel *profileSubLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, 40, 14)];
    profileSubLabel.text = @"Profile";
    profileSubLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    profileSubLabel.textColor = [UIColor secondaryLabelColor];
    profileSubLabel.textAlignment = NSTextAlignmentRight;
    profileSubLabel.adjustsFontSizeToFitWidth = YES;
    profileSubLabel.minimumScaleFactor = 0.8;
    [labelContainer addSubview:profileSubLabel];
    
    UILabel *idLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 4, 60, 24)];
    idLabel.text = @"—"; // Will update after profiles are loaded
    idLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    idLabel.textColor = [UIColor systemGreenColor];
    idLabel.textAlignment = NSTextAlignmentCenter;
    idLabel.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
    idLabel.layer.cornerRadius = 12;
    idLabel.layer.masksToBounds = YES;
    idLabel.adjustsFontSizeToFitWidth = YES;
    idLabel.minimumScaleFactor = 0.7;
    [rightContainer addSubview:idLabel];
    self.currentProfileIdLabel = idLabel; // Save reference to update later
    
    self.navigationItem.titleView = titleView;
    
    // Setup table view
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    
    // Add close/dismiss button
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose 
                                                                               target:self 
                                                                               action:@selector(dismissProfileManager)];
    self.navigationItem.leftBarButtonItem = closeButton;
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    // Force refresh data
    [self.tableView reloadData];
}

- (void)dismissProfileManager {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)toggleEditMode {
    BOOL isEditing = self.tableView.isEditing;
    [self.tableView setEditing:!isEditing animated:YES];
    self.navigationItem.rightBarButtonItem = isEditing ? self.editButton : self.doneButton;
}

- (void)dismissKeyboard {
    [self.searchTextField resignFirstResponder];
}

#pragma mark - Search Functionality

- (void)performSearch {
    NSString *searchText = self.searchTextField.text;
    
    // Safety check - ensure filteredProfiles exists
    if (!self.filteredProfiles) {
        self.filteredProfiles = [NSMutableArray array];
    }
    
    if (searchText.length == 0) {
        self.isSearchActive = NO;
        self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
    } else {
        self.isSearchActive = YES;
        [self.filteredProfiles removeAllObjects];
        
        NSString *lowercaseSearchText = [searchText lowercaseString];
        
        // Search through ALL profiles, not just loaded ones
        for (Profile *profile in self.allProfiles) {
            // Skip profiles with ID 0 from search results
            if (!profile.profileId || 
                [profile.profileId isEqualToString:@"0"] || 
                [profile.profileId isEqualToString:@"profile_0"] ||
                [profile.profileId intValue] == 0) {
                NSLog(@"[WeaponX] Excluding profile with ID 0 from search results: %@", profile.name);
                continue;
            }
            
            // Search across all available profile information fields
            NSString *lowercaseName = profile.name ? [profile.name lowercaseString] : @"";
            NSString *lowercaseId = profile.profileId ? [profile.profileId lowercaseString] : @"";
            NSString *lowercaseDesc = profile.shortDescription ? [profile.shortDescription lowercaseString] : @"";
            
            // Extract just the number part of the profile ID for easier searching
            NSString *numberPart = @"";
            if ([lowercaseId hasPrefix:@"profile_"]) {
                numberPart = [lowercaseId substringFromIndex:8]; // Skip "profile_"
            }
            
            if ([lowercaseName containsString:lowercaseSearchText] || 
                [lowercaseId containsString:lowercaseSearchText] ||
                [lowercaseDesc containsString:lowercaseSearchText] ||
                [numberPart containsString:lowercaseSearchText]) {
                
                [self.filteredProfiles addObject:profile];
            }
        }
    }
    
    // Safety check - ensure we have a valid table view and the correct section exists
    if (self.tableView && self.tableView.numberOfSections > 3) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView reloadData];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self performSearch];
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    // When clear button is pressed, reset search immediately
    self.isSearchActive = NO;
    
    // Safety check - ensure profiles exists and make a safe copy
    if (!self.filteredProfiles) {
        self.filteredProfiles = [NSMutableArray array];
    }
    self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
    
    // Safety check - ensure table view exists and has the correct section
    if (self.tableView && self.tableView.numberOfSections > 3) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
    } else if (self.tableView) {
        [self.tableView reloadData];
    }
    
    // Show search icon, hide cancel button
    if (self.searchIcon) self.searchIcon.hidden = NO;
    if (self.cancelButton) self.cancelButton.hidden = YES;
    
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    // When ending editing, if the text is empty, ensure visible profiles are showing
    if (textField.text.length == 0 && self.isSearchActive) {
        self.isSearchActive = NO;
        
        // Safety check - ensure profiles exists and make a safe copy
        if (!self.filteredProfiles) {
            self.filteredProfiles = [NSMutableArray array];
        }
        self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
        
        // Safety check - ensure table view exists and has the correct section
        if (self.tableView && self.tableView.numberOfSections > 3) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
        } else if (self.tableView) {
            [self.tableView reloadData];
        }
        
        // Show search icon, hide cancel button
        if (self.searchIcon) self.searchIcon.hidden = NO;
        if (self.cancelButton) self.cancelButton.hidden = YES;
    }
}

- (void)textFieldDidChangeSelection:(UITextField *)textField {
    // Nil check for text
    NSString *text = textField.text ?: @"";
    
    // Show/hide cancel button based on text content
    if (text.length > 0) {
        if (self.searchIcon) self.searchIcon.hidden = YES;
        if (self.cancelButton) self.cancelButton.hidden = NO;
        
        // Perform search as user types for immediate feedback
        [self performSearch];
    } else {
        if (self.searchIcon) self.searchIcon.hidden = NO;
        if (self.cancelButton) self.cancelButton.hidden = YES;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4; // Storage section + Search section + Action Buttons section + Profiles section
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        // Storage section
        return 1;
    } else if (section == 1) {
        // Search section
        return 1;
    } else if (section == 2) {
        // Action buttons section
        return 1;
    } else {
        // Profiles section
        if (self.isSearchActive) {
            return self.filteredProfiles.count;
        } else {
            // Add one more row for "Show More" button if there are more profiles to show
            NSInteger showMoreButtonCount = (self.displayedProfilesCount < self.allProfiles.count) ? 1 : 0;
            return self.profiles.count + showMoreButtonCount;
        }
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Device Storage";
    } else if (section == 1) {
        return @"SEARCH PROFILES";
    } else if (section == 2) {
        return @"PROFILE ACTIONS";
    } else {
        return @"Available Profiles";
    }
}

// Add custom header view method to include the toggle
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 1) { // Search Profiles section
        // Create a container view for the header
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 44)];
        
        // Create the label
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, 150, 30)];
        titleLabel.text = @"SEARCH PROFILES";
        titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        titleLabel.textColor = [UIColor secondaryLabelColor];
        [headerView addSubview:titleLabel];
        
        // Create the toggle switch with a smaller size
        UISwitch *containerSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
        containerSwitch.onTintColor = [UIColor systemGreenColor];
        containerSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75); // Smaller switch size
        
        // Position the switch more to the left side
        CGFloat switchWidth = 51 * 0.75; // Scaled width
        CGFloat rightMargin = 25; // Reduced from 15 to move left
        containerSwitch.frame = CGRectMake(tableView.frame.size.width - switchWidth - rightMargin, 8, switchWidth, 31 * 0.75);
        
        // Set initial state from NSUserDefaults
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.containersystem"];
        BOOL isEnabled = [defaults boolForKey:@"containerSystemEnabled"];
        containerSwitch.on = isEnabled;
        
        // Add target action
        [containerSwitch addTarget:self action:@selector(containerSwitchToggled:) forControlEvents:UIControlEventValueChanged];
        [headerView addSubview:containerSwitch];
        
        // Create container icon with a smaller size
        UIImageView *containerIcon = [[UIImageView alloc] initWithFrame:CGRectMake(containerSwitch.frame.origin.x - 30, 10, 20, 20)];
        UIImage *boxImage = [UIImage systemImageNamed:@"shippingbox"];
        containerIcon.image = [boxImage imageWithTintColor:[UIColor systemGrayColor] renderingMode:UIImageRenderingModeAlwaysTemplate];
        containerIcon.tintColor = isEnabled ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
        containerIcon.contentMode = UIViewContentModeScaleAspectFit;
        [headerView addSubview:containerIcon];
        
        // Create label for container system - moved more to the left
        UILabel *containerLabel = [[UILabel alloc] initWithFrame:CGRectMake(containerIcon.frame.origin.x - 110, 10, 100, 20)];
        containerLabel.text = @"Container System";
        containerLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        containerLabel.textColor = [UIColor secondaryLabelColor];
        containerLabel.textAlignment = NSTextAlignmentRight;
        containerLabel.adjustsFontSizeToFitWidth = YES;
        containerLabel.minimumScaleFactor = 0.75;
        [headerView addSubview:containerLabel];
        
        return headerView;
    }
    
    // For other sections, use the default header
    return nil;
}

// Add the toggle handler method
- (void)containerSwitchToggled:(UISwitch *)sender {
    // Save to NSUserDefaults
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.containersystem"];
    [defaults setBool:sender.isOn forKey:@"containerSystemEnabled"];
    [defaults synchronize];
    
    // Update the tint color of the container icon
    UIImageView *containerIcon = nil;
    for (UIView *subview in sender.superview.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            containerIcon = (UIImageView *)subview;
            break;
        }
    }
    containerIcon.tintColor = sender.isOn ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
    
    // Post notification to update container system state
    [[NSNotificationCenter defaultCenter] postNotificationName:@"containerSystemToggled" object:nil userInfo:@{@"enabled": @(sender.isOn)}];
    
    // Also post Darwin notification for system-wide notification
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(darwinCenter, 
                                         CFSTR("com.weaponx.containersystem.toggled"), 
                                         NULL, 
                                         NULL, 
                                         YES);
    
    // Provide feedback 
    UIImpactFeedbackGenerator *feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedbackGenerator prepare];
    [feedbackGenerator impactOccurred];
}

// Override height for header in section
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 1) {
        return 44; // Taller header for the container toggle
    }
    return 30.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        // Storage info cell - enhanced futuristic design
        static NSString *storageIdentifier = @"StorageCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:storageIdentifier];
        
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:storageIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
            // Pre-set cell frame to avoid resize issues
            CGRect frame = cell.frame;
            frame.size.height = 100;
            frame.size.width = tableView.bounds.size.width;
            cell.frame = frame;
        }
        
        // Remove any existing subviews to prevent duplication
        for (UIView *subview in cell.contentView.subviews) {
            [subview removeFromSuperview];
        }
        
        if (self.storageInfo) {
            NSNumber *totalSpace = self.storageInfo[@"totalSpace"];
            NSNumber *freeSpace = self.storageInfo[@"freeSpace"];
            
            // Format bytes
            NSString *freeSpaceStr = [NSByteCountFormatter stringFromByteCount:freeSpace.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
            NSString *totalSpaceStr = [NSByteCountFormatter stringFromByteCount:totalSpace.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
            
            // Calculate used percentage (still needed for progress bar)
            double usedPercentage = 100.0 * (1.0 - ([freeSpace doubleValue] / [totalSpace doubleValue]));
            
            // Create color based on storage levels
            UIColor *primaryColor;
            UIColor *secondaryColor;
            if (usedPercentage > 90) {
                primaryColor = [UIColor systemRedColor];
                secondaryColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
            } else if (usedPercentage > 75) {
                primaryColor = [UIColor systemOrangeColor];
                secondaryColor = [UIColor colorWithRed:0.9 green:0.6 blue:0.0 alpha:1.0];
            } else {
                primaryColor = [UIColor systemGreenColor];
                secondaryColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:1.0];
            }
            
            // Container card view with shadow
            UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cell.contentView.bounds.size.width - 30, 80)];
            cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
            cardView.layer.cornerRadius = 15;
            cardView.layer.shadowColor = [UIColor blackColor].CGColor;
            cardView.layer.shadowOffset = CGSizeMake(0, 2);
            cardView.layer.shadowOpacity = 0.1;
            cardView.layer.shadowRadius = 4;
            cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:cardView];
            
            // Primary storage label with large font - increased width now that percentage is gone
            UILabel *storageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, cardView.bounds.size.width - 80, 30)];
            storageLabel.text = freeSpaceStr;
            storageLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
            storageLabel.textColor = primaryColor;
            storageLabel.adjustsFontSizeToFitWidth = YES;
            storageLabel.minimumScaleFactor = 0.7;
            [cardView addSubview:storageLabel];
            
            // "AVAILABLE" text positioned below the primary storage label
            UILabel *availableLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 45, 100, 16)];
            availableLabel.text = @"AVAILABLE";
            availableLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            availableLabel.textColor = [UIColor secondaryLabelColor];
            [cardView addSubview:availableLabel];
            
            // Total space label - now positioned at the right side
            UILabel *totalLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 120, 45, 100, 16)];
            totalLabel.text = [NSString stringWithFormat:@"of %@", totalSpaceStr];
            totalLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
            totalLabel.textColor = [UIColor tertiaryLabelColor];
            totalLabel.textAlignment = NSTextAlignmentRight;
            totalLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [cardView addSubview:totalLabel];
            
            // Create a custom progress track
            UIView *progressTrack = [[UIView alloc] initWithFrame:CGRectMake(20, 65, cardView.bounds.size.width - 40, 8)];
            progressTrack.backgroundColor = [UIColor systemFillColor];
            progressTrack.layer.cornerRadius = 4;
            progressTrack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cardView addSubview:progressTrack];
            
            // Create gradient progress fill
            CAGradientLayer *gradientLayer = [CAGradientLayer layer];
            gradientLayer.frame = CGRectMake(0, 0, progressTrack.bounds.size.width * (usedPercentage / 100.0), progressTrack.bounds.size.height);
            gradientLayer.colors = @[(id)primaryColor.CGColor, (id)secondaryColor.CGColor];
            gradientLayer.startPoint = CGPointMake(0.0, 0.5);
            gradientLayer.endPoint = CGPointMake(1.0, 0.5);
            gradientLayer.cornerRadius = progressTrack.layer.cornerRadius;
            
            UIView *progressFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, progressTrack.bounds.size.width * (usedPercentage / 100.0), progressTrack.bounds.size.height)];
            progressFill.layer.cornerRadius = progressTrack.layer.cornerRadius;
            progressFill.layer.masksToBounds = YES;
            progressFill.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [progressFill.layer addSublayer:gradientLayer];
            [progressTrack addSubview:progressFill];
            
            // Add shimmer effect to progress bar for futuristic look
            [self addShimmerToView:progressFill];
            
            // Add storage icon
            UIImageView *storageIcon = [[UIImageView alloc] initWithFrame:CGRectMake(cardView.bounds.size.width - 35, 15, 24, 24)];
            UIImage *diskImage = [UIImage systemImageNamed:@"internaldrive"];
            storageIcon.image = [diskImage imageWithTintColor:primaryColor renderingMode:UIImageRenderingModeAlwaysTemplate];
            storageIcon.tintColor = primaryColor;
            storageIcon.contentMode = UIViewContentModeScaleAspectFit;
            storageIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [cardView addSubview:storageIcon];
        } else {
            // Loading state
            UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            loadingIndicator.center = CGPointMake(cell.contentView.bounds.size.width / 2, cell.contentView.bounds.size.height / 2);
            loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            [loadingIndicator startAnimating];
            [cell.contentView addSubview:loadingIndicator];
            
            UILabel *loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, loadingIndicator.frame.origin.y + 30, cell.contentView.bounds.size.width, 20)];
            loadingLabel.text = @"Scanning storage...";
            loadingLabel.textAlignment = NSTextAlignmentCenter;
            loadingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            loadingLabel.textColor = [UIColor secondaryLabelColor];
            loadingLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:loadingLabel];
        }
        
        // Hide default labels since we're using custom views
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        
        return cell;
    } else if (indexPath.section == 1) {
        // Search cell - modern futuristic design
        static NSString *searchIdentifier = @"SearchCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:searchIdentifier];
        
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:searchIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
            // Pre-set cell frame to avoid resize issues
            CGRect frame = cell.frame;
            frame.size.height = 70;
            frame.size.width = tableView.bounds.size.width;
            cell.frame = frame;
        }
        
        // Remove any existing subviews to prevent duplication
        for (UIView *subview in cell.contentView.subviews) {
            [subview removeFromSuperview];
        }
        
        // Create a container for our search UI
        UIView *searchContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cell.contentView.bounds.size.width - 30, 60)];
        searchContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
        searchContainer.layer.cornerRadius = 15;
        searchContainer.layer.shadowColor = [UIColor blackColor].CGColor;
        searchContainer.layer.shadowOffset = CGSizeMake(0, 2);
        searchContainer.layer.shadowOpacity = 0.1;
        searchContainer.layer.shadowRadius = 4;
        searchContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:searchContainer];
        
        // Create a modern search text field
        UITextField *searchField = [[UITextField alloc] initWithFrame:CGRectMake(15, 10, searchContainer.bounds.size.width - 80, 40)];
        searchField.placeholder = @"Search by name or ID";
        searchField.font = [UIFont systemFontOfSize:16];
        searchField.backgroundColor = [UIColor tertiarySystemBackgroundColor];
        searchField.layer.cornerRadius = 10;
        searchField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 40)];
        searchField.leftViewMode = UITextFieldViewModeAlways;
        searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
        searchField.delegate = self;
        searchField.returnKeyType = UIReturnKeySearch;
        searchField.autocorrectionType = UITextAutocorrectionTypeNo;
        searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        searchField.layer.borderColor = [UIColor systemBlueColor].CGColor;
        searchField.layer.borderWidth = 1.0;
        searchField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [searchContainer addSubview:searchField];
        self.searchTextField = searchField;
        
        // Add search icon
        UIImageView *searchIcon = [[UIImageView alloc] initWithFrame:CGRectMake(searchContainer.bounds.size.width - 55, 15, 30, 30)];
        UIImage *icon = [UIImage systemImageNamed:@"magnifyingglass.circle.fill"];
        searchIcon.image = [icon imageWithTintColor:[UIColor systemBlueColor] renderingMode:UIImageRenderingModeAlwaysTemplate];
        searchIcon.tintColor = [UIColor systemBlueColor];
        searchIcon.contentMode = UIViewContentModeScaleAspectFit;
        searchIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        searchIcon.userInteractionEnabled = YES;
        [searchContainer addSubview:searchIcon];
        self.searchIcon = searchIcon;
        
        // Add a tap gesture to the search icon
        UITapGestureRecognizer *searchTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(searchIconTapped)];
        [searchIcon addGestureRecognizer:searchTap];
        
        // Add cancel button that appears when searching
        UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        cancelButton.frame = CGRectMake(searchContainer.bounds.size.width - 30, 10, 80, 40);
        [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
        cancelButton.titleLabel.font = [UIFont systemFontOfSize:14];
        cancelButton.tintColor = [UIColor systemBlueColor];
        cancelButton.alpha = 0.0; // Initially hidden
        cancelButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [cancelButton addTarget:self action:@selector(cancelSearch) forControlEvents:UIControlEventTouchUpInside];
        [searchContainer addSubview:cancelButton];
        self.cancelButton = cancelButton;
        
        return cell;
    } else if (indexPath.section == 2) {
        // Action buttons cell
        static NSString *actionsIdentifier = @"ActionsCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionsIdentifier];
        
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:actionsIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
            // Reduce cell frame height
            CGRect frame = cell.frame;
            frame.size.height = 60; // Reduced from 70
            frame.size.width = tableView.bounds.size.width;
            cell.frame = frame;
        }
        
        // Remove any existing subviews to prevent duplication
        for (UIView *subview in cell.contentView.subviews) {
            [subview removeFromSuperview];
        }
        
        // Create a container for the buttons - reduce height
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cell.contentView.bounds.size.width - 30, 50)]; // Reduced from 60
        container.backgroundColor = [UIColor secondarySystemBackgroundColor];
        container.layer.cornerRadius = 12; // Reduced from 15
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:container];
        
        // Add Import/Export button on the left side - reduce height and adjust position
        UIButton *importExportButton = [UIButton buttonWithType:UIButtonTypeSystem];
        importExportButton.frame = CGRectMake(15, 8, (container.bounds.size.width / 2) - 25, 34); // Reduced height from 40 to 34
        
        // Configure button with icon and text - smaller font
        UIImage *importExportIcon = [UIImage systemImageNamed:@"square.and.arrow.up.on.square"];
        NSString *importExportTitle = @"IMPORT/EXPORT";
        
        // Create configuration for button with smaller text
        UIButtonConfiguration *importExportConfig = [UIButtonConfiguration filledButtonConfiguration];
        importExportConfig.title = importExportTitle;
        importExportConfig.image = importExportIcon;
        importExportConfig.imagePlacement = NSDirectionalRectEdgeLeading;
        importExportConfig.imagePadding = 4; // Reduced from 8
        importExportConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        importExportConfig.baseBackgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.1];
        importExportConfig.baseForegroundColor = [UIColor systemBlueColor];
        
        // Set smaller font size
        UIFont *smallerFont = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium]; // Reduced font size
        importExportConfig.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *textAttributes) {
            NSMutableDictionary *newAttributes = [textAttributes mutableCopy];
            newAttributes[NSFontAttributeName] = smallerFont;
            return newAttributes;
        };
        
        // Reduce content insets to make button more compact
        importExportConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 8, 4, 8);
        
        importExportButton.configuration = importExportConfig;
        importExportButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
        [importExportButton addTarget:self action:@selector(importExportButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        // Add border
        importExportButton.layer.borderWidth = 1.0;
        importExportButton.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.3].CGColor;
        importExportButton.layer.cornerRadius = 10; // Reduced from 12
        
        [container addSubview:importExportButton];
        
        // Add Trash All Profiles button to the right side - reduce height and adjust position
        UIButton *trashAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
        trashAllButton.frame = CGRectMake(container.bounds.size.width/2 + 10, 8, (container.bounds.size.width / 2) - 25, 34); // Reduced height from 40 to 34
        
        // Configure button with icon and text - smaller text
        UIImage *trashIcon = [UIImage systemImageNamed:@"trash"];
        NSString *trashTitle = @"ALL PROFILES";
        
        // Create configuration for button with smaller text
        UIButtonConfiguration *trashConfig = [UIButtonConfiguration filledButtonConfiguration];
        trashConfig.title = trashTitle;
        trashConfig.image = trashIcon;
        trashConfig.imagePlacement = NSDirectionalRectEdgeLeading;
        trashConfig.imagePadding = 4; // Reduced from 8
        trashConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        trashConfig.baseBackgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
        trashConfig.baseForegroundColor = [UIColor systemRedColor];
        
        // Set smaller font size
        trashConfig.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *textAttributes) {
            NSMutableDictionary *newAttributes = [textAttributes mutableCopy];
            newAttributes[NSFontAttributeName] = smallerFont;
            return newAttributes;
        };
        
        // Reduce content insets to make button more compact
        trashConfig.contentInsets = NSDirectionalEdgeInsetsMake(4, 8, 4, 8);
        
        trashAllButton.configuration = trashConfig;
        trashAllButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
        [trashAllButton addTarget:self action:@selector(trashAllButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        // Add border
        trashAllButton.layer.borderWidth = 1.0;
        trashAllButton.layer.borderColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.3].CGColor;
        trashAllButton.layer.cornerRadius = 10; // Reduced from 12
        
        [container addSubview:trashAllButton];
        
        // Hide default labels
        cell.textLabel.text = nil;
        
        return cell;
    } else {
        // Profiles section - Show More button
        if (!self.isSearchActive && indexPath.row >= self.profiles.count) {
            // "Show More" button cell (only shown in main list mode)
            static NSString *moreIdentifier = @"MoreCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:moreIdentifier];
            
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:moreIdentifier];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.backgroundColor = [UIColor clearColor];
                // Pre-set cell frame to avoid resize issues
                CGRect frame = cell.frame;
                frame.size.height = 70;
                frame.size.width = tableView.bounds.size.width;
                cell.frame = frame;
            }
            
            // Remove any existing subviews to prevent duplication
            for (UIView *subview in cell.contentView.subviews) {
                [subview removeFromSuperview];
            }
            
            // Create a container for the "Show More" button
            UIView *container = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cell.contentView.bounds.size.width - 30, 60)];
            container.backgroundColor = [UIColor secondarySystemBackgroundColor];
            container.layer.cornerRadius = 15;
            container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:container];
            
            // Add "Show More" button on the left side
            UIButton *showMoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
            showMoreButton.frame = CGRectMake(15, 10, (container.bounds.size.width / 2) - 25, 40);
            
            // Configure button with icon and text properly spaced
            UIImage *addIcon = [UIImage systemImageNamed:@"plus.circle.fill"];
            NSString *title = @"Show More";
            
            // Create configuration for button
            UIButtonConfiguration *showMoreConfig = [UIButtonConfiguration filledButtonConfiguration];
            showMoreConfig.title = title;
            showMoreConfig.image = addIcon;
            showMoreConfig.imagePlacement = NSDirectionalRectEdgeLeading;
            showMoreConfig.imagePadding = 8;
            showMoreConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
            showMoreConfig.baseBackgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.1];
            showMoreConfig.baseForegroundColor = [UIColor systemBlueColor];
            
            showMoreButton.configuration = showMoreConfig;
            showMoreButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
            [showMoreButton addTarget:self action:@selector(loadMoreProfiles) forControlEvents:UIControlEventTouchUpInside];
            
            // Add border
            showMoreButton.layer.borderWidth = 1.0;
            showMoreButton.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.3].CGColor;
            showMoreButton.layer.cornerRadius = 12;
            
            [container addSubview:showMoreButton];
            
            // Add "Search Profiles" button to the right side
            UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
            searchButton.frame = CGRectMake(container.bounds.size.width/2 + 10, 10, (container.bounds.size.width / 2) - 25, 40);
            
            // Configure button with icon and text properly spaced
            UIImage *searchIcon = [UIImage systemImageNamed:@"magnifyingglass"];
            NSString *searchTitle = @"Search";
            
            // Create configuration for button
            UIButtonConfiguration *searchConfig = [UIButtonConfiguration filledButtonConfiguration];
            searchConfig.title = searchTitle;
            searchConfig.image = searchIcon;
            searchConfig.imagePlacement = NSDirectionalRectEdgeLeading;
            searchConfig.imagePadding = 8;
            searchConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
            searchConfig.baseBackgroundColor = [[UIColor systemPurpleColor] colorWithAlphaComponent:0.1];
            searchConfig.baseForegroundColor = [UIColor systemPurpleColor];
            
            searchButton.configuration = searchConfig;
            searchButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
            [searchButton addTarget:self action:@selector(scrollToSearchField) forControlEvents:UIControlEventTouchUpInside];
            
            // Add border
            searchButton.layer.borderWidth = 1.0;
            searchButton.layer.borderColor = [[UIColor systemPurpleColor] colorWithAlphaComponent:0.3].CGColor;
            searchButton.layer.cornerRadius = 12;
            
            [container addSubview:searchButton];
            
            // Hide default labels
            cell.textLabel.text = nil;
            
            return cell;
        }
        
        // Regular profile cells - Use custom ProfileTableViewCell
        static NSString *cellIdentifier = @"ProfileCell";
        ProfileTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
        
        if (!cell) {
            cell = [[ProfileTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
            
            // Set up button targets
            [cell.renameButton addTarget:self action:@selector(renameTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.infoButton addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.timeButton addTarget:self action:@selector(timeTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.exportButton addTarget:self action:@selector(exportTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.switchButton addTarget:self action:@selector(switchTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];
        }
        
        Profile *profile = self.isSearchActive ? self.filteredProfiles[indexPath.row] : self.profiles[indexPath.row];
        
        // Skip profiles with ID 0 to ensure they are never displayed
        if (!profile.profileId || 
            [profile.profileId isEqualToString:@"0"] || 
            [profile.profileId isEqualToString:@"profile_0"] ||
            [profile.profileId intValue] == 0) {
            
            // Create a blank cell instead
            UITableViewCell *blankCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BlankCell"];
            blankCell.hidden = YES;
            blankCell.userInteractionEnabled = NO;
            blankCell.contentView.hidden = YES;
            return blankCell;
        }
        
        // Check if this is the current profile using direct access to central profile info
        BOOL isCurrentProfile = NO;
        ProfileManager *manager = [ProfileManager sharedManager];
        
        // First check the central profile info store (most reliable source)
        NSDictionary *centralInfo = [manager loadCentralProfileInfo];
        if (centralInfo && centralInfo[@"ProfileId"] && 
            [centralInfo[@"ProfileId"] isEqualToString:profile.profileId]) {
            isCurrentProfile = YES;
        } 
        // Fallback to checking manager's currentProfile if central store doesn't match
        else if ([manager.currentProfile.profileId isEqualToString:profile.profileId]) {
            isCurrentProfile = YES;
            
            // If central store doesn't match but manager does, update central store
            if (centralInfo && centralInfo[@"ProfileId"] && 
                ![centralInfo[@"ProfileId"] isEqualToString:profile.profileId]) {
                // Detected mismatch between central store and manager, updating central store
                [manager updateCurrentProfileInfoWithProfile:profile];
            }
        }
        
        // Configure the cell with the profile
        [cell configureWithProfile:profile isCurrentProfile:isCurrentProfile tableWidth:tableView.bounds.size.width];
        
        // Set button tags and ensure targets are set up every time 
        // (not just during cell creation) to prevent issues with reused cells
        cell.renameButton.tag = indexPath.row;
        cell.infoButton.tag = indexPath.row;
        cell.timeButton.tag = indexPath.row;
        cell.exportButton.tag = indexPath.row;
        cell.switchButton.tag = indexPath.row;
        cell.deleteButton.tag = indexPath.row;
        
        // Remove existing targets first to avoid duplicate actions
        [cell.renameButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.infoButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.timeButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.exportButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.switchButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.deleteButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        
        // Re-add targets every time to ensure they work for reused cells
        [cell.renameButton addTarget:self action:@selector(renameTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.infoButton addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.timeButton addTarget:self action:@selector(timeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.exportButton addTarget:self action:@selector(exportTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.switchButton addTarget:self action:@selector(switchTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.deleteButton addTarget:self action:@selector(deleteTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        return cell;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return 100; // Height for storage cell
    } else if (indexPath.section == 1) {
        return 70; // Height for search cell
    } else if (indexPath.section == 2) {
        return 60; // Reduced from 70 for action buttons cell
    }
    
    // Use a fixed height for profile cards to avoid resize issues
    return 110; // Height for profile cards
}

// Override layoutSubviews to ensure cardView is sized correctly immediately
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // For profile cells, force immediate layout to ensure proper rendering
    if (indexPath.section == 2 && [cell isKindOfClass:[ProfileTableViewCell class]]) {
        [(ProfileTableViewCell *)cell layoutIfNeeded];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only allow editing profile cells, not storage or search
    return indexPath.section == 2;
}

// Leading swipe actions (swipe from left to right) - Switch profile action
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only add actions for profile cells
    if (indexPath.section != 2) {
        return nil;
    }
    
    // Get the profile at this row
    Profile *profile = self.isSearchActive ? self.filteredProfiles[indexPath.row] : self.profiles[indexPath.row];
    
    // Check if this is the current profile
    BOOL isCurrentProfile = NO;
    ProfileManager *manager = [ProfileManager sharedManager];
    if ([manager.currentProfile.profileId isEqualToString:profile.profileId]) {
        isCurrentProfile = YES;
    }
    
    // Don't add switch action if this is already the current profile
    if (isCurrentProfile) {
        return nil;
    }
    
    // Create switch action
    UIContextualAction *switchAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                               title:@"Switch"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        // Call the switch profile method
        [self switchToProfile:profile];
        completionHandler(YES);
    }];
    
    // Set switch action color and image
    switchAction.backgroundColor = [UIColor systemBlueColor];
    switchAction.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
    
    // Create swipe action configuration
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[switchAction]];
    configuration.performsFirstActionWithFullSwipe = YES;
    
    return configuration;
}

// Trailing swipe actions (swipe from right to left) - Delete action
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only add actions for profile cells
    if (indexPath.section != 2) {
        return nil;
    }
    
    // Get the profile at this row
    Profile *profile = self.isSearchActive ? self.filteredProfiles[indexPath.row] : self.profiles[indexPath.row];
    
    // Check if this is the current profile
    BOOL isCurrentProfile = NO;
    ProfileManager *manager = [ProfileManager sharedManager];
    if ([manager.currentProfile.profileId isEqualToString:profile.profileId]) {
        isCurrentProfile = YES;
    }
    
    // Create delete action
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        // Check if we can delete this profile (not the last one and not the current one)
        if (self.profiles.count <= 1) {
            // Show error - can't delete last profile
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                       message:@"You cannot delete the last profile. At least one profile must remain."
                                                                preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            completionHandler(NO);
            return;
        }
        
        // Check if this is the current active profile
        if (isCurrentProfile) {
            // Show error - can't delete current profile
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                           message:@"You cannot delete the currently active profile. Please switch to another profile first."
                                                                preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            completionHandler(NO);
            return;
        }
        
        // Confirm deletion
        UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"Delete Profile"
                                                                           message:@"Are you sure you want to delete this profile? This action cannot be undone."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        
        [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                    handler:^(UIAlertAction * _Nonnull action) {
            completionHandler(NO);
        }]];
        
        [confirmAlert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                    style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction * _Nonnull action) {
            // Direct approach: Delete the profile folder from the filesystem
            NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
            NSString *profilePath = [profilesDirectory stringByAppendingPathComponent:profile.profileId];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSError *error = nil;
            BOOL success = [fileManager removeItemAtPath:profilePath error:&error];
            
            if (success) {
                NSLog(@"[WeaponX] Successfully deleted profile folder: %@", profilePath);
                
                // Update local arrays and table view
                if (self.isSearchActive) {
                    [self.filteredProfiles removeObjectAtIndex:indexPath.row];
                    
                    // Also remove from main profiles array
                    NSInteger mainIndex = [self.profiles indexOfObject:profile];
                    if (mainIndex != NSNotFound) {
                        [self.profiles removeObjectAtIndex:mainIndex];
                    }
                } else {
                    [self.profiles removeObjectAtIndex:indexPath.row];
                }
                
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                [self updateProfileCount];
                
                // Notify delegate
                if ([self.delegate respondsToSelector:@selector(profileManagerViewController:didUpdateProfiles:)]) {
                    [self.delegate profileManagerViewController:self didUpdateProfiles:self.profiles];
                }
            } else {
                NSLog(@"[WeaponX] Failed to delete profile folder: %@, Error: %@", profilePath, error);
                
                // Show error alert
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:[NSString stringWithFormat:@"Failed to delete profile: %@", error.localizedDescription ?: @"Unknown error"]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
                
                // Reload profiles from disk to ensure UI is in sync
                [self loadProfilesFromDisk];
            }
            
            completionHandler(YES);
        }]];
        
        [self presentViewController:confirmAlert animated:YES completion:nil];
    }];
    
    // Set delete action image
    deleteAction.image = [UIImage systemImageNamed:@"trash"];
    
    // Create swipe action configuration
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = NO; // Require confirmation for delete
    
    return configuration;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // We're now using dedicated buttons for actions instead of row selection
    // This method is kept for future functionality if needed
}

- (void)switchToProfile:(Profile *)profile {
    // Show loading indicator
    UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    loadingIndicator.center = self.view.center;
    loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:loadingIndicator];
    [loadingIndicator startAnimating];
    
    // Switch to the selected profile
    [[ProfileManager sharedManager] switchToProfile:profile completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingIndicator stopAnimating];
            [loadingIndicator removeFromSuperview];
            
            if (success) {
                // Notify floating profile indicator that a change happened
                // This ensures the indicator updates promptly after the switch completes
                [[NSNotificationCenter defaultCenter] postNotificationName:@"ProfileManagerCurrentProfileChanged" 
                                                                    object:nil 
                                                                  userInfo:@{@"profile": profile}];
                
                // Also post a Darwin notification for the floating indicator
                CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
                CFNotificationCenterPostNotification(darwinCenter, 
                                                     CFSTR("com.hydra.projectx.profileChanged"), 
                                                     NULL, 
                                                     NULL, 
                                                     YES);
                
                // Show success message
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Profile Switched"
                                                                                 message:[NSString stringWithFormat:@"Successfully switched to profile: %@", profile.name]
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    // Notify delegate that a profile was selected
                    if ([self.delegate respondsToSelector:@selector(profileManagerViewController:didSelectProfile:)]) {
                        [self.delegate profileManagerViewController:self didSelectProfile:profile];
                    }
                    
                    // Dismiss the profile manager
                    [self dismissViewControllerAnimated:YES completion:nil];
                }]];
                [self presentViewController:successAlert animated:YES completion:nil];
            } else {
                // Show error message
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                message:[NSString stringWithFormat:@"Failed to switch profile: %@", error.localizedDescription ?: @"Unknown error"]
                                                                         preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
                
                // Reload profiles from disk to ensure UI is in sync
                [self loadProfilesFromDisk];
            }
        });
    }];
}

- (void)showRenameDialogForProfile:(Profile *)profile {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Profile"
                                                                 message:@"Enter new name for the profile"
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = profile.name;
        textField.placeholder = @"Profile Name";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction * _Nonnull action) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length > 0) {
            // Show loading indicator
            UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            loadingIndicator.center = self.view.center;
            loadingIndicator.hidesWhenStopped = YES;
            [self.view addSubview:loadingIndicator];
            [loadingIndicator startAnimating];
            
            // Get profile directory
            NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
            NSString *profilePath = [profilesDirectory stringByAppendingPathComponent:profile.profileId];
            
            // Update profile name in memory
            profile.name = newName;
            
            // Direct file updates - update name in all possible plist files
            BOOL didUpdateAnyFile = NO;
            NSFileManager *fileManager = [NSFileManager defaultManager];
            
            // 1. Update identifiers.plist if it exists
            NSString *identifiersPath = [profilePath stringByAppendingPathComponent:@"identifiers.plist"];
            if ([fileManager fileExistsAtPath:identifiersPath]) {
                NSMutableDictionary *identifiers = [NSMutableDictionary dictionaryWithContentsOfFile:identifiersPath];
                if (identifiers) {
                    identifiers[@"DisplayName"] = newName;
                    BOOL success = [identifiers writeToFile:identifiersPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated display name in identifiers.plist: %@", identifiersPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated identifiers.plist: %@", identifiersPath);
                    }
                }
            }
            
            // 2. Update scoped-apps.plist if it exists
            NSString *scopedAppsPath = [profilePath stringByAppendingPathComponent:@"scoped-apps.plist"];
            if ([fileManager fileExistsAtPath:scopedAppsPath]) {
                NSMutableDictionary *scopedApps = [NSMutableDictionary dictionaryWithContentsOfFile:scopedAppsPath];
                if (scopedApps) {
                    scopedApps[@"ProfileName"] = newName;
                    BOOL success = [scopedApps writeToFile:scopedAppsPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated profile name in scoped-apps.plist: %@", scopedAppsPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated scoped-apps.plist: %@", scopedAppsPath);
                    }
                }
            }
            
            // 3. Update Info.plist if it exists
            NSString *infoPath = [profilePath stringByAppendingPathComponent:@"Info.plist"];
            if ([fileManager fileExistsAtPath:infoPath]) {
                NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
                if (info) {
                    info[@"Name"] = newName;
                    BOOL success = [info writeToFile:infoPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated name in Info.plist: %@", infoPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated Info.plist: %@", infoPath);
                    }
                }
            }
            
            // 4. Update appdata/Info.plist if it exists
            NSString *appDataPath = [profilePath stringByAppendingPathComponent:@"appdata/Info.plist"];
            if ([fileManager fileExistsAtPath:appDataPath]) {
                NSMutableDictionary *appInfo = [NSMutableDictionary dictionaryWithContentsOfFile:appDataPath];
                if (appInfo) {
                    appInfo[@"ProfileName"] = newName;
                    BOOL success = [appInfo writeToFile:appDataPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated profile name in appdata/Info.plist: %@", appDataPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated appdata/Info.plist: %@", appDataPath);
                    }
                }
            }
            
            // 5. Update the current profile info if this is the current profile
            ProfileManager *manager = [ProfileManager sharedManager];
            if ([manager.currentProfile.profileId isEqualToString:profile.profileId]) {
                // Update central profile info
                [manager updateCurrentProfileInfoWithProfile:profile];
                NSLog(@"[WeaponX] Updated current profile info with new name");
                didUpdateAnyFile = YES;
            }
            
            // Use the ProfileManager to ensure any in-memory caches are updated
            [[ProfileManager sharedManager] renameProfile:profile.name to:newName];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingIndicator stopAnimating];
                [loadingIndicator removeFromSuperview];
                
                if (didUpdateAnyFile) {
                    // Show success message
                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Profile Renamed"
                                                                                      message:[NSString stringWithFormat:@"Profile successfully renamed to '%@'", newName]
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                    [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:successAlert animated:YES completion:nil];
                } else {
                    // Show warning message - changes may not persist
                    UIAlertController *warningAlert = [UIAlertController alertControllerWithTitle:@"Warning"
                                                                                      message:@"Profile was renamed in memory but changes may not persist between restarts. No profile files could be updated."
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                    [warningAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:warningAlert animated:YES completion:nil];
                }
                
                // Load profiles from disk to ensure UI is in sync
                [self loadProfilesFromDisk];
                
                // Notify delegate
                if ([self.delegate respondsToSelector:@selector(profileManagerViewController:didUpdateProfiles:)]) {
                    if (self.isSearchActive) {
                        [self.delegate profileManagerViewController:self didUpdateProfiles:self.filteredProfiles];
                    } else {
                        [self.delegate profileManagerViewController:self didUpdateProfiles:self.profiles];
                    }
                }
            });
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDeleteConfirmationForProfile:(Profile *)profile {
    // Verify we have more than one profile
    if (self.profiles.count <= 1) {
        // Show error - can't delete last profile
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                 message:@"You cannot delete the last profile. At least one profile must remain."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Check if this is the current active profile
    ProfileManager *manager = [ProfileManager sharedManager];
    if ([manager.currentProfile.profileId isEqualToString:profile.profileId]) {
        // Show error - can't delete current profile
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cannot Delete"
                                                                     message:@"You cannot delete the currently active profile. Please switch to another profile first."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Profile"
                                                                 message:@"Are you sure you want to delete this profile? This action cannot be undone."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction * _Nonnull action) {
        // Show loading indicator
        UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        loadingIndicator.center = self.view.center;
        loadingIndicator.hidesWhenStopped = YES;
        [self.view addSubview:loadingIndicator];
        [loadingIndicator startAnimating];
        
        // Direct approach: Delete the profile folder from the filesystem
        NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        NSString *profilePath = [profilesDirectory stringByAppendingPathComponent:profile.profileId];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        BOOL success = [fileManager removeItemAtPath:profilePath error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingIndicator stopAnimating];
            [loadingIndicator removeFromSuperview];
            
            if (success) {
                NSLog(@"[WeaponX] Successfully deleted profile folder: %@", profilePath);
                
                // Remove profile from local array
                NSInteger index = [self.profiles indexOfObject:profile];
                if (index != NSNotFound) {
                    [self.profiles removeObjectAtIndex:index];
                }
                
                if (self.isSearchActive) {
                    NSInteger searchIndex = [self.filteredProfiles indexOfObject:profile];
                    if (searchIndex != NSNotFound) {
                        [self.filteredProfiles removeObjectAtIndex:searchIndex];
                    }
                }
                
                // Reload the table view
                [self.tableView reloadData];
                [self updateProfileCount];
                
                // Notify delegate
                if ([self.delegate respondsToSelector:@selector(profileManagerViewController:didUpdateProfiles:)]) {
                    [self.delegate profileManagerViewController:self didUpdateProfiles:self.profiles];
                }
                
                // Show success alert
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                                    message:@"Profile deleted successfully"
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
            } else {
                NSLog(@"[WeaponX] Failed to delete profile folder: %@, Error: %@", profilePath, error);
                
                // Show error alert
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                   message:[NSString stringWithFormat:@"Failed to delete profile: %@", error.localizedDescription ?: @"Unknown error"]
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            }
            
            // Reload profiles from disk to ensure UI is in sync
            [self loadProfilesFromDisk];
        });
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)infoTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    
    // Show info/description dialog
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Profile Information"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Description";
        textField.text = profile.shortDescription;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                             style:UIAlertActionStyleCancel 
                                           handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Update" 
                                             style:UIAlertActionStyleDefault 
                                           handler:^(UIAlertAction * _Nonnull action) {
        NSString *newDescription = alert.textFields.firstObject.text;
        if (newDescription && ![newDescription isEqualToString:profile.shortDescription]) {
            // Show loading indicator
            UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            loadingIndicator.center = self.view.center;
            loadingIndicator.hidesWhenStopped = YES;
            [self.view addSubview:loadingIndicator];
            [loadingIndicator startAnimating];
            
            // Update profile description in memory
            profile.shortDescription = newDescription;
            
            // Get profile directory
            NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
            NSString *profilePath = [profilesDirectory stringByAppendingPathComponent:profile.profileId];
            
            // Direct file updates - update description in all possible plist files
            BOOL didUpdateAnyFile = NO;
            NSFileManager *fileManager = [NSFileManager defaultManager];
            
            // 1. Update identifiers.plist if it exists
            NSString *identifiersPath = [profilePath stringByAppendingPathComponent:@"identifiers.plist"];
            if ([fileManager fileExistsAtPath:identifiersPath]) {
                NSMutableDictionary *identifiers = [NSMutableDictionary dictionaryWithContentsOfFile:identifiersPath];
                if (identifiers) {
                    identifiers[@"Description"] = newDescription;
                    BOOL success = [identifiers writeToFile:identifiersPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated description in identifiers.plist: %@", identifiersPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated identifiers.plist: %@", identifiersPath);
                    }
                }
            }
            
            // 2. Update scoped-apps.plist if it exists
            NSString *scopedAppsPath = [profilePath stringByAppendingPathComponent:@"scoped-apps.plist"];
            if ([fileManager fileExistsAtPath:scopedAppsPath]) {
                NSMutableDictionary *scopedApps = [NSMutableDictionary dictionaryWithContentsOfFile:scopedAppsPath];
                if (scopedApps) {
                    scopedApps[@"Description"] = newDescription;
                    scopedApps[@"ProfileDescription"] = newDescription;
                    BOOL success = [scopedApps writeToFile:scopedAppsPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated description in scoped-apps.plist: %@", scopedAppsPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated scoped-apps.plist: %@", scopedAppsPath);
                    }
                }
            }
            
            // 3. Update Info.plist if it exists
            NSString *infoPath = [profilePath stringByAppendingPathComponent:@"Info.plist"];
            if ([fileManager fileExistsAtPath:infoPath]) {
                NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
                if (info) {
                    info[@"Description"] = newDescription;
                    info[@"ShortDescription"] = newDescription;
                    BOOL success = [info writeToFile:infoPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated description in Info.plist: %@", infoPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated Info.plist: %@", infoPath);
                    }
                }
            }
            
            // 4. Update appdata/Info.plist if it exists
            NSString *appDataPath = [profilePath stringByAppendingPathComponent:@"appdata/Info.plist"];
            if ([fileManager fileExistsAtPath:appDataPath]) {
                NSMutableDictionary *appInfo = [NSMutableDictionary dictionaryWithContentsOfFile:appDataPath];
                if (appInfo) {
                    appInfo[@"ProfileDescription"] = newDescription;
                    appInfo[@"Description"] = newDescription;
                    BOOL success = [appInfo writeToFile:appDataPath atomically:YES];
                    if (success) {
                        NSLog(@"[WeaponX] Updated description in appdata/Info.plist: %@", appDataPath);
                        didUpdateAnyFile = YES;
                    } else {
                        NSLog(@"[WeaponX] Failed to write updated appdata/Info.plist: %@", appDataPath);
                    }
                }
            }
            
            // 5. Update the current profile info if this is the current profile
            ProfileManager *manager = [ProfileManager sharedManager];
            if ([manager.currentProfile.profileId isEqualToString:profile.profileId]) {
                // Update central profile info
                [manager updateCurrentProfileInfoWithProfile:profile];
                NSLog(@"[WeaponX] Updated current profile info with new description");
                didUpdateAnyFile = YES;
            }
            
            // Use the ProfileManager to ensure any in-memory caches are updated
            [manager updateProfile:profile completion:^(BOOL success, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [loadingIndicator stopAnimating];
                    [loadingIndicator removeFromSuperview];
                    
                    if (didUpdateAnyFile) {
                        // Show success message
                        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Description Updated"
                                                                                          message:@"Profile description successfully updated"
                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                        [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:successAlert animated:YES completion:nil];
                    } else {
                        // Show warning message - changes may not persist
                        UIAlertController *warningAlert = [UIAlertController alertControllerWithTitle:@"Warning"
                                                                                          message:@"Description was updated in memory but changes may not persist between restarts. No profile files could be updated."
                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                        [warningAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:warningAlert animated:YES completion:nil];
                    }
                    
                    // Reload profiles to update UI
                    [self loadProfilesFromDisk];
                });
            }];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Add shimmer effect for futuristic look
- (void)addShimmerToView:(UIView *)view {
    CAGradientLayer *shimmerLayer = [CAGradientLayer layer];
    shimmerLayer.frame = CGRectMake(0, 0, view.bounds.size.width * 3, view.bounds.size.height);
    
    shimmerLayer.colors = @[
        (id)[UIColor colorWithWhite:1 alpha:0.1].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:0.2].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:0.1].CGColor
    ];
    
    shimmerLayer.locations = @[@0.0, @0.5, @1.0];
    shimmerLayer.startPoint = CGPointMake(0, 0.5);
    shimmerLayer.endPoint = CGPointMake(1, 0.5);
    
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position.x"];
    animation.fromValue = @(-view.bounds.size.width * 1.5);
    animation.toValue = @(view.bounds.size.width * 1.5);
    animation.repeatCount = HUGE_VALF;
    animation.duration = 3.0;
    
    [shimmerLayer addAnimation:animation forKey:@"shimmerAnimation"];
    view.layer.mask = nil;
    [view.layer addSublayer:shimmerLayer];
}

// Enrich existing profiles with additional information from plists if available
- (void)enrichProfilesWithAdditionalInfo {
    NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
    
    for (Profile *profile in self.profiles) {
        // If profile already has a proper name and description, skip it
        if (profile.name && profile.name.length > 0 && 
            ![profile.name isEqualToString:profile.profileId] &&
            profile.shortDescription && profile.shortDescription.length > 0) {
            continue;
        }
        
        NSString *profileDir = [profilesDirectory stringByAppendingPathComponent:profile.profileId];
        
        // Try to get a better display name if it's missing or same as ID
        if (!profile.name || [profile.name isEqualToString:profile.profileId]) {
            NSString *betterName = [self extractProfileDisplayNameFromDirectory:profileDir withFolderName:profile.profileId];
            if (betterName && betterName.length > 0) {
                profile.name = betterName;
            }
        }
        
        // Try to get a short description if it's missing
        if (!profile.shortDescription || profile.shortDescription.length == 0) {
            NSString *desc = [self extractProfileShortDescriptionFromDirectory:profileDir withFolderName:profile.profileId];
            if (desc && desc.length > 0) {
                profile.shortDescription = desc;
            }
        }
    }
}

- (void)cancelSearch {
    // Clear the search field
    if (self.searchTextField) {
        self.searchTextField.text = @"";
    }
    
    // Reset search state
    self.isSearchActive = NO;
    
    // Safety check for profiles property
    if (!self.filteredProfiles) {
        self.filteredProfiles = [NSMutableArray array];
    }
    self.filteredProfiles = [self.profiles mutableCopy] ?: [NSMutableArray array];
    
    // Safety check for table view
    if (self.tableView && self.tableView.numberOfSections > 3) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationFade];
    } else if (self.tableView) {
        [self.tableView reloadData];
    }
    
    // Show search icon, hide cancel button
    if (self.searchIcon) self.searchIcon.hidden = NO;
    if (self.cancelButton) self.cancelButton.hidden = YES;
    
    // Dismiss keyboard
    if (self.searchTextField) {
        [self.searchTextField resignFirstResponder];
    }
}

- (void)searchIconTapped {
    // Focus on the search text field when search icon is tapped
    if (self.searchTextField) {
        [self.searchTextField becomeFirstResponder];
    }
}

#pragma mark - Profile Card Button Actions

- (void)renameTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    [self showRenameDialogForProfile:profile];
}

- (void)timeTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    
    // Get file metadata directly from the filesystem for the most up-to-date information
    NSString *profileDirectory = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profile.profileId];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSDate *creationDate = nil;
    NSDate *lastAccessDate = nil;
    NSError *attributesError = nil;
    
    // Try to get actual file attributes first
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:profileDirectory error:&attributesError];
    if (!attributesError && attributes) {
        // Get creation date from file attributes
        creationDate = [attributes fileCreationDate];
        // Get last modification date as a proxy for last access
        lastAccessDate = [attributes fileModificationDate];
    }
    
    // Fall back to profile object dates if file attributes unavailable
    if (!creationDate) {
        creationDate = profile.createdAt;
    }
    
    if (!lastAccessDate) {
        lastAccessDate = profile.lastUsed;
    }
    
    // Current date for time ago calculations
    NSDate *now = [NSDate date];
    
    // Create date formatter for readable date display
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.timeStyle = NSDateFormatterMediumStyle;
    
    // Format date strings
    NSString *createdDateStr = @"Created: Unknown";
    NSString *createdTimeAgoStr = @"";
    if (creationDate) {
        createdDateStr = [NSString stringWithFormat:@"Created: %@", [dateFormatter stringFromDate:creationDate]];
        
        // Calculate "time ago" for creation date
        createdTimeAgoStr = [self timeAgoStringFromDate:creationDate toDate:now];
    }
    
    NSString *lastUsedStr = @"Last used: Never";
    NSString *lastUsedTimeAgoStr = @"";
    if (lastAccessDate) {
        lastUsedStr = [NSString stringWithFormat:@"Last used: %@", [dateFormatter stringFromDate:lastAccessDate]];
        
        // Calculate "time ago" for last used date
        lastUsedTimeAgoStr = [self timeAgoStringFromDate:lastAccessDate toDate:now];
    }
    
    // Combine the formatted strings with "time ago" information
    NSString *message;
    if (createdTimeAgoStr.length > 0) {
        createdDateStr = [NSString stringWithFormat:@"%@\n(%@)", createdDateStr, createdTimeAgoStr];
    }
    
    if (lastUsedTimeAgoStr.length > 0) {
        lastUsedStr = [NSString stringWithFormat:@"%@\n(%@)", lastUsedStr, lastUsedTimeAgoStr];
    }
    
    message = [NSString stringWithFormat:@"%@\n\n%@", createdDateStr, lastUsedStr];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Profile Timestamps"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" 
                                             style:UIAlertActionStyleDefault 
                                           handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Helper method to calculate "time ago" string
- (NSString *)timeAgoStringFromDate:(NSDate *)fromDate toDate:(NSDate *)toDate {
    if (!fromDate || !toDate) {
        return @"";
    }
    
    NSTimeInterval timeInterval = [toDate timeIntervalSinceDate:fromDate];
    
    // Convert to minutes, hours, days
    NSInteger minutes = (NSInteger)(timeInterval / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    
    if (minutes < 1) {
        return @"just now";
    } else if (minutes < 60) {
        return minutes == 1 ? @"1 minute ago" : [NSString stringWithFormat:@"%ld minutes ago", (long)minutes];
    } else if (hours < 24) {
        return hours == 1 ? @"1 hour ago" : [NSString stringWithFormat:@"%ld hours ago", (long)hours];
    } else if (days < 7) {
        return days == 1 ? @"1 day ago" : [NSString stringWithFormat:@"%ld days ago", (long)days];
    } else if (days < 30) {
        NSInteger weeks = days / 7;
        return weeks == 1 ? @"1 week ago" : [NSString stringWithFormat:@"%ld weeks ago", (long)weeks];
    } else if (days < 365) {
        NSInteger months = days / 30;
        return months == 1 ? @"1 month ago" : [NSString stringWithFormat:@"%ld months ago", (long)months];
    } else {
        NSInteger years = days / 365;
        return years == 1 ? @"1 year ago" : [NSString stringWithFormat:@"%ld years ago", (long)years];
    }
}

- (void)switchTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    
    // Show confirmation dialog for switching profiles
    NSString *message = [NSString stringWithFormat:@"Switch to profile '%@'?", profile.name];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Switch Profile"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" 
                                             style:UIAlertActionStyleCancel 
                                           handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Switch" 
                                             style:UIAlertActionStyleDefault 
                                           handler:^(UIAlertAction * _Nonnull action) {
        [self switchToProfile:profile];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    [self showDeleteConfirmationForProfile:profile];
}

- (void)loadMoreProfiles {
    // Check if we already loaded all profiles
    if (self.displayedProfilesCount >= self.allProfiles.count) {
        return;
    }
    
    // Calculate how many more to load (10 more or whatever is left)
    NSInteger remainingProfiles = self.allProfiles.count - self.displayedProfilesCount;
    NSInteger additionalCount = MIN(10, remainingProfiles);
    
    // Create range for additional profiles
    NSRange additionalRange = NSMakeRange(self.displayedProfilesCount, additionalCount);
    
    // Add profiles to displayed profiles array
    NSArray *additionalProfiles = [self.allProfiles subarrayWithRange:additionalRange];
    [self.profiles addObjectsFromArray:additionalProfiles];
    
    // Update displayed count
    self.displayedProfilesCount += additionalCount;
    
    // Reload table view
    [self.tableView reloadData];
}

- (void)scrollToSearchField {
    // Scroll to the search section
    NSIndexPath *searchIndexPath = [NSIndexPath indexPathForRow:0 inSection:1];
    [self.tableView scrollToRowAtIndexPath:searchIndexPath atScrollPosition:UITableViewScrollPositionTop animated:YES];
    
    // After scrolling, focus on the search field
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.searchTextField becomeFirstResponder];
    });
}

- (void)importExportButtonTapped:(UIButton *)sender {
    // To be implemented later
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import/Export"
                                                               message:@"Import/Export functionality will be configured later."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)trashAllButtonTapped:(UIButton *)sender {
    // Show confirmation alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete All Profiles"
                                                               message:@"Are you sure you want to delete all profiles? This action cannot be undone. The current active profile and profile '0' will be preserved."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteAllProfiles];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteAllProfiles {
    // Show loading indicator
    UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    loadingIndicator.center = self.view.center;
    loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:loadingIndicator];
    [loadingIndicator startAnimating];
    
    // Get the profiles directory
    NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Get current profile ID to preserve it - use the central profile info which is more reliable
    ProfileManager *manager = [ProfileManager sharedManager];
    NSDictionary *centralInfo = [manager loadCentralProfileInfo];
    NSString *currentProfileId = nil;
    
    // First try to get the profile ID from central info
    if (centralInfo && centralInfo[@"ProfileId"]) {
        currentProfileId = centralInfo[@"ProfileId"];
        NSLog(@"[WeaponX] Using central profile info ID for preservation: %@", currentProfileId);
    } 
    // Fallback to manager's currentProfile if central info doesn't exist
    else if (manager.currentProfile) {
        currentProfileId = manager.currentProfile.profileId;
        NSLog(@"[WeaponX] Using manager's current profile ID for preservation: %@", currentProfileId);
    }
    
    // If we still don't have a profile ID, log the issue
    if (!currentProfileId) {
        NSLog(@"[WeaponX] Warning: No current profile ID found for preservation");
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:profilesDirectory error:&error];
        
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingIndicator stopAnimating];
                [loadingIndicator removeFromSuperview];
                
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                   message:[NSString stringWithFormat:@"Failed to access profiles directory: %@", error.localizedDescription]
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            });
            return;
        }
        
        NSInteger deletedCount = 0;
        NSMutableArray *failedItems = [NSMutableArray array];
        NSMutableArray *skippedItems = [NSMutableArray array];
        
        for (NSString *item in contents) {
            // Skip profiles.plist file and folder named "0" or "profile_0"
            if ([item isEqualToString:@"profiles.plist"] || 
                [item isEqualToString:@"0"] || 
                [item isEqualToString:@"profile_0"]) {
                [skippedItems addObject:item];
                NSLog(@"[WeaponX] Skipping system profile: %@", item);
                continue;
            }
            
            // Skip the current profile
            if (currentProfileId && [item isEqualToString:currentProfileId]) {
                [skippedItems addObject:item];
                NSLog(@"[WeaponX] Skipping current profile: %@", item);
                continue;
            }
            
            NSString *itemPath = [profilesDirectory stringByAppendingPathComponent:item];
            BOOL isDirectory = NO;
            
            // Skip non-directories
            if (![fileManager fileExistsAtPath:itemPath isDirectory:&isDirectory] || !isDirectory) {
                NSLog(@"[WeaponX] Skipping non-directory: %@", item);
                continue;
            }
            
            // Try to delete the folder
            NSError *deleteError = nil;
            BOOL success = [fileManager removeItemAtPath:itemPath error:&deleteError];
            
            if (success) {
                deletedCount++;
                NSLog(@"[WeaponX] Successfully deleted profile: %@", item);
            } else {
                [failedItems addObject:item];
                NSLog(@"[WeaponX] Failed to delete profile %@: %@", item, deleteError.localizedDescription);
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingIndicator stopAnimating];
            [loadingIndicator removeFromSuperview];
            
            // Reload profiles from disk
            [self loadProfilesFromDisk];
            
            // Show results
            NSString *resultMessage;
            if (failedItems.count == 0) {
                resultMessage = [NSString stringWithFormat:@"Successfully deleted %ld profiles. Current active profile was preserved.", (long)deletedCount];
            } else {
                resultMessage = [NSString stringWithFormat:@"Deleted %ld profiles. Failed to delete %ld profiles. Current active profile was preserved.", (long)deletedCount, (long)failedItems.count];
            }
            
            // Log skipped profiles
            NSLog(@"[WeaponX] Profiles skipped during delete all: %@", skippedItems);
            
            UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:@"Delete Complete"
                                                                              message:resultMessage
                                                                       preferredStyle:UIAlertControllerStyleAlert];
            [resultAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:resultAlert animated:YES completion:nil];
        });
    });
}

- (void)exportTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    Profile *profile = self.isSearchActive ? self.filteredProfiles[index] : self.profiles[index];
    
    // Get the profile directory path
    NSString *profilesDirectory = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
    NSString *profilePath = [profilesDirectory stringByAppendingPathComponent:profile.profileId];
    
    // Check if the profile directory exists
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    
    if (![fileManager fileExistsAtPath:profilePath isDirectory:&isDirectory] || !isDirectory) {
        // Show error if directory doesn't exist
        UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"Export Error"
                                                                            message:@"The profile directory could not be found."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [errorAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:errorAlert animated:YES completion:nil];
        return;
    }
    
    // Show loading indicator
    UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    loadingIndicator.center = self.view.center;
    loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:loadingIndicator];
    [loadingIndicator startAnimating];
    
    // Perform file operation in background to avoid UI blocking
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Create a simple JSON file with profile information in the temp directory for sharing
        NSString *tempDir = NSTemporaryDirectory();
        NSString *infoFileName = [NSString stringWithFormat:@"%@_info.json", profile.profileId];
        NSString *infoFilePath = [tempDir stringByAppendingPathComponent:infoFileName];
        
        // Create a JSON file with profile details
        NSDictionary *profileInfo = @{
            @"profileId": profile.profileId ?: @"",
            @"name": profile.name ?: @"",
            @"description": profile.shortDescription ?: @"",
            @"exportDate": [NSDate date].description,
            @"path": profilePath
        };
        
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profileInfo options:NSJSONWritingPrettyPrinted error:&jsonError];
        
        if (jsonData) {
            [jsonData writeToFile:infoFilePath atomically:YES];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingIndicator stopAnimating];
            [loadingIndicator removeFromSuperview];
            
            // Get the cell or button that was tapped to use as source view
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:3]];
            UIView *sourceView = sender;
            if (!sourceView) {
                sourceView = cell;
            }
            
            // Create a URL for sharing (either directory or info file)
            NSURL *shareURL = [NSURL fileURLWithPath:profilePath isDirectory:YES];
            
            // Use UIDocumentInteractionController for sharing the directory
            self.documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:shareURL];
            self.documentInteractionController.delegate = self;
            
            // Present options
            BOOL presented = [self.documentInteractionController presentOptionsMenuFromRect:sourceView.bounds inView:sourceView animated:YES];
            
            if (!presented) {
                // Fallback to sharing the info file if directory sharing isn't supported
                NSURL *infoURL = [NSURL fileURLWithPath:infoFilePath];
                
                // Create activity view controller for sharing the info file
                UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[infoURL] applicationActivities:nil];
                
                // Configure for iPad
                if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                    activityVC.popoverPresentationController.sourceView = sourceView;
                    activityVC.popoverPresentationController.sourceRect = sourceView.bounds;
                }
                
                [self presentViewController:activityVC animated:YES completion:nil];
            }
        });
    });
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self;
}

- (UIView *)documentInteractionControllerViewForPreview:(UIDocumentInteractionController *)controller {
    return self.view;
}

- (CGRect)documentInteractionControllerRectForPreview:(UIDocumentInteractionController *)controller {
    return self.view.bounds;
}

@end

@implementation ProfileTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.backgroundColor = [UIColor clearColor];
        [self setupCell];
    }
    return self;
}

- (void)setupCell {
    // Create all views upfront
    CGFloat cardWidth = self.contentView.bounds.size.width - 30;
    
    // Main card container
    self.cardView = [[UIView alloc] initWithFrame:CGRectMake(15, 5, cardWidth, 100)];
    self.cardView.layer.cornerRadius = 18;
    self.cardView.clipsToBounds = NO;
    self.cardView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // Add shadow
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 3);
    self.cardView.layer.shadowOpacity = 0.12;
    self.cardView.layer.shadowRadius = 8;
    
    // Inner card
    self.innerCard = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cardWidth, 100)];
    self.innerCard.layer.cornerRadius = 18;
    self.innerCard.clipsToBounds = YES;
    self.innerCard.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    // Create gradient layer
    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.frame = self.innerCard.bounds;
    self.gradientLayer.cornerRadius = 18;
    self.gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    self.gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    
    // Default gradient colors (will update in configure method)
    self.gradientLayer.colors = @[
        (id)[UIColor secondarySystemBackgroundColor].CGColor,
        (id)[UIColor tertiarySystemBackgroundColor].CGColor
    ];
    
    [self.innerCard.layer insertSublayer:self.gradientLayer atIndex:0];
    [self.cardView addSubview:self.innerCard];
    
    // Profile ID Badge
    UIView *idBadge = [[UIView alloc] initWithFrame:CGRectMake(15, 15, 40, 40)];
    idBadge.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.15];
    idBadge.layer.cornerRadius = 20;
    [self.innerCard addSubview:idBadge];
    
    // ID Label
    self.idLabel = [[UILabel alloc] initWithFrame:idBadge.bounds];
    self.idLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    self.idLabel.textAlignment = NSTextAlignmentCenter;
    self.idLabel.adjustsFontSizeToFitWidth = YES;
    self.idLabel.minimumScaleFactor = 0.7;
    [idBadge addSubview:self.idLabel];
    
    // Profile Name Label
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(70, 22, self.innerCard.bounds.size.width - 130, 28)];
    self.nameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold]; // Reduced from 20 to 18
    self.nameLabel.textColor = [UIColor labelColor];
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.7;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail; // Add truncation for long names
    self.nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.innerCard addSubview:self.nameLabel];
    
    // Rename button - increase hit area and add proper background
    self.renameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.renameButton.frame = CGRectMake(200, 22, 30, 30);
    
    // Use modern UIButtonConfiguration API for iOS 15+
    UIButtonConfiguration *renameConfig = [UIButtonConfiguration plainButtonConfiguration];
    renameConfig.image = [UIImage systemImageNamed:@"pencil"];
    renameConfig.baseForegroundColor = [UIColor secondaryLabelColor];
    renameConfig.contentInsets = NSDirectionalEdgeInsetsMake(5, 5, 5, 5);
    self.renameButton.configuration = renameConfig;
    
    self.renameButton.userInteractionEnabled = YES;
    [self.innerCard addSubview:self.renameButton];
    
    // Info button - increase hit area
    self.infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.infoButton.frame = CGRectMake(self.innerCard.bounds.size.width - 44, 13, 32, 32);
    
    // Use modern UIButtonConfiguration API for iOS 15+
    UIButtonConfiguration *infoConfig = [UIButtonConfiguration plainButtonConfiguration];
    infoConfig.image = [UIImage systemImageNamed:@"info.circle"];
    infoConfig.baseForegroundColor = [UIColor systemBlueColor];
    infoConfig.contentInsets = NSDirectionalEdgeInsetsMake(5, 5, 5, 5);
    self.infoButton.configuration = infoConfig;
    
    self.infoButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.infoButton.userInteractionEnabled = YES;
    [self.innerCard addSubview:self.infoButton];
    
    // Create action container
    UIView *actionContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 60, self.innerCard.bounds.size.width, 40)];
    actionContainer.backgroundColor = [UIColor clearColor];
    actionContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.innerCard addSubview:actionContainer];
    
    // Add separator
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(15, 0, actionContainer.bounds.size.width - 30, 1)];
    separator.backgroundColor = [[UIColor separatorColor] colorWithAlphaComponent:0.3];
    separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [actionContainer addSubview:separator];
    
    // Enhance bottom action buttons with larger touch targets - adjust for 4 buttons
    CGFloat buttonSize = 30; // Slightly smaller for 4 buttons
    CGFloat availableWidth = actionContainer.bounds.size.width - 30; // Total width minus margins
    CGFloat buttonSpacing = (availableWidth - (4 * buttonSize)) / 3; // Space between 4 buttons
    
    // Time button - enhanced for better touch
    self.timeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.timeButton.frame = CGRectMake(15, 5, buttonSize, buttonSize);
    
    // Use modern UIButtonConfiguration API for iOS 15+
    UIButtonConfiguration *timeConfig = [UIButtonConfiguration plainButtonConfiguration];
    timeConfig.image = [UIImage systemImageNamed:@"clock"];
    timeConfig.baseForegroundColor = [UIColor systemGrayColor];
    timeConfig.contentInsets = NSDirectionalEdgeInsetsMake(5, 5, 5, 5);
    self.timeButton.configuration = timeConfig;
    
    self.timeButton.userInteractionEnabled = YES;
    [actionContainer addSubview:self.timeButton];
    
    // Export button (new) - add to the right of time button
    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat exportX = 15 + buttonSize + buttonSpacing;
    self.exportButton.frame = CGRectMake(exportX, 5, buttonSize, buttonSize);
    
    // Use modern UIButtonConfiguration API for iOS 15+
    UIButtonConfiguration *exportConfig = [UIButtonConfiguration plainButtonConfiguration];
    exportConfig.image = [UIImage systemImageNamed:@"square.and.arrow.up.on.square"];
    exportConfig.baseForegroundColor = [UIColor systemBlueColor];
    exportConfig.contentInsets = NSDirectionalEdgeInsetsMake(5, 5, 5, 5);
    self.exportButton.configuration = exportConfig;
    
    self.exportButton.userInteractionEnabled = YES;
    [actionContainer addSubview:self.exportButton];
    
    // Switch button - enhanced for better touch - position after export button
    self.switchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat switchX = exportX + buttonSize + buttonSpacing;
    self.switchButton.frame = CGRectMake(switchX, 5, buttonSize, buttonSize);
    
    // Use modern UIButtonConfiguration API for iOS 15+
    UIButtonConfiguration *switchConfig = [UIButtonConfiguration plainButtonConfiguration];
    // Use a simpler SF Symbol that's definitely available in iOS 15+
    switchConfig.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
    switchConfig.baseForegroundColor = [UIColor systemBlueColor];
    switchConfig.contentInsets = NSDirectionalEdgeInsetsMake(5, 5, 5, 5);
    self.switchButton.configuration = switchConfig;
    
    self.switchButton.userInteractionEnabled = YES;
    [actionContainer addSubview:self.switchButton];
    
    // Delete button - enhanced for better touch - move to rightmost position
    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat deleteX = switchX + buttonSize + buttonSpacing;
    self.deleteButton.frame = CGRectMake(deleteX, 5, buttonSize, buttonSize);
    
    // Use modern UIButtonConfiguration API for iOS 15+
    UIButtonConfiguration *deleteConfig = [UIButtonConfiguration plainButtonConfiguration];
    deleteConfig.image = [UIImage systemImageNamed:@"trash"];
    deleteConfig.baseForegroundColor = [UIColor systemRedColor];
    deleteConfig.contentInsets = NSDirectionalEdgeInsetsMake(5, 5, 5, 5);
    self.deleteButton.configuration = deleteConfig;
    
    self.deleteButton.userInteractionEnabled = YES;
    [actionContainer addSubview:self.deleteButton];
    
    // Add button highlights for visual feedback
    [self addButtonHighlightEffects:self.renameButton];
    [self addButtonHighlightEffects:self.infoButton];
    [self addButtonHighlightEffects:self.timeButton];
    [self addButtonHighlightEffects:self.exportButton]; // Add highlight effect to export button
    [self addButtonHighlightEffects:self.switchButton];
    [self addButtonHighlightEffects:self.deleteButton];
    
    [self.contentView addSubview:self.cardView];
    
    // Enable user interaction for the entire cell and its subviews
    self.userInteractionEnabled = YES;
    self.contentView.userInteractionEnabled = YES;
    self.cardView.userInteractionEnabled = YES;
    self.innerCard.userInteractionEnabled = YES;
    
    // Hide default labels
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
}

// Add visual feedback for button presses using iOS 15 compatible approach
- (void)addButtonHighlightEffects:(UIButton *)button {
    // For iOS 15+, we use the built-in UIButtonConfiguration highlighting
    // without trying to customize too much
    
    // Set up a simple handler that handles the pressed state
    button.configurationUpdateHandler = ^(__kindof UIButton *btn) {
        // Apply a simple background when pressed
        if (btn.isHighlighted) {
            btn.backgroundColor = [UIColor systemGray5Color];
        } else {
            btn.backgroundColor = nil;
        }
    };
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // Force all views to layout properly
    CGFloat cardWidth = self.contentView.bounds.size.width - 30;
    
    // Update frames to ensure proper layout
    self.cardView.frame = CGRectMake(15, 5, cardWidth, 100);
    self.innerCard.frame = CGRectMake(0, 0, cardWidth, 100);
    self.gradientLayer.frame = self.innerCard.bounds;
    
    // Update rename button position based on actual name width
    if (self.nameLabel.text) {
        CGSize nameSize = [self.nameLabel.text sizeWithAttributes:@{NSFontAttributeName: self.nameLabel.font}];
        
        // Set a maximum position for the pencil button to prevent overlap with info button
        CGFloat maxPencilX = self.innerCard.bounds.size.width - 90; // Keep at least 90px from right edge
        CGFloat calculatedPencilX = self.nameLabel.frame.origin.x + MIN(nameSize.width, self.nameLabel.frame.size.width) + 5;
        CGFloat pencilX = MIN(calculatedPencilX, maxPencilX); // Take the leftmost position
        
        self.renameButton.frame = CGRectMake(pencilX, 22, 30, 30); // Larger touch target
    }
    
    // Update info button position
    self.infoButton.frame = CGRectMake(self.innerCard.bounds.size.width - 44, 13, 32, 32);
    
    // Force immediate layout
    [self.cardView setNeedsLayout];
    [self.innerCard setNeedsLayout];
    [self.cardView layoutIfNeeded];
    [self.innerCard layoutIfNeeded];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    // Reset the cell state
    self.isCurrentProfile = NO;
    self.nameLabel.text = nil;
    self.idLabel.text = nil;
    
    // Reset border
    self.innerCard.layer.borderWidth = 0;
    
    // Reset button visual states
    self.renameButton.backgroundColor = nil;
    self.infoButton.backgroundColor = nil;
    self.timeButton.backgroundColor = nil;
    self.exportButton.backgroundColor = nil;
    self.switchButton.backgroundColor = nil;
    self.deleteButton.backgroundColor = nil;
    
    // Reset visibility of switchButton
    self.switchButton.hidden = NO;
}

- (void)configureWithProfile:(Profile *)profile isCurrentProfile:(BOOL)isCurrentProfile tableWidth:(CGFloat)tableWidth {
    self.isCurrentProfile = isCurrentProfile;
    
    // Apply color scheme based on current profile status
    if (isCurrentProfile) {
        // Active profile - green theme
        self.gradientLayer.colors = @[
            (id)[[UIColor systemGreenColor] colorWithAlphaComponent:0.2].CGColor,
            (id)[[UIColor systemGreenColor] colorWithAlphaComponent:0.08].CGColor
        ];
        self.innerCard.layer.borderWidth = 1.5;
        self.innerCard.layer.borderColor = [UIColor systemGreenColor].CGColor;
        
        // ID badge background and text
        UIView *idBadge = [self.innerCard.subviews objectAtIndex:0];
        idBadge.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.15];
        self.idLabel.textColor = [UIColor systemGreenColor];
        
        // Hide switch button for the current profile (no need to switch to current profile)
        self.switchButton.hidden = YES;
    } else {
        // Inactive profile - default theme
        self.gradientLayer.colors = @[
            (id)[UIColor secondarySystemBackgroundColor].CGColor,
            (id)[UIColor tertiarySystemBackgroundColor].CGColor
        ];
        self.innerCard.layer.borderWidth = 0;
        
        // ID badge background and text
        UIView *idBadge = [self.innerCard.subviews objectAtIndex:0];
        idBadge.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.15];
        self.idLabel.textColor = [UIColor labelColor];
        
        // Show switch button for inactive profiles
        self.switchButton.hidden = NO;
    }
    
    // Set ID label
    self.idLabel.text = profile.profileId;
    
    // Set name label with truncation if needed
    NSString *displayName = profile.name;
    // Limit display name to 15 characters to prevent overlap with info button
    if (displayName.length > 15) {
        displayName = [NSString stringWithFormat:@"%@...", [displayName substringToIndex:12]];
    }
    self.nameLabel.text = displayName;
    
    // Update layout to ensure proper positioning of elements
    [self setNeedsLayout];
    [self layoutIfNeeded];
    
    // Calculate pencil position based on visible name width, with a maximum position to prevent overlap
    CGSize nameSize = [displayName sizeWithAttributes:@{NSFontAttributeName: self.nameLabel.font}];
    CGFloat maxPencilX = self.innerCard.bounds.size.width - 90; // Keep at least 90px from right edge
    CGFloat calculatedPencilX = self.nameLabel.frame.origin.x + MIN(nameSize.width, self.nameLabel.frame.size.width) + 5;
    CGFloat pencilX = MIN(calculatedPencilX, maxPencilX); // Take the leftmost position
    
    self.renameButton.frame = CGRectMake(pencilX, 22, 30, 30);
}

@end 