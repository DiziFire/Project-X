#import "FileManagerViewController.h"
#import "PlistViewerViewController.h"
#import <objc/runtime.h>

// Constants for operation types
typedef NS_ENUM(NSInteger, FileOperationType) {
    FileOperationTypeNone = 0,
    FileOperationTypeCopy = 1,
    FileOperationTypeMove = 2
};

@interface FileManagerViewController () <UITableViewDelegate, UITableViewDataSource, UIDocumentInteractionControllerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSArray *directoryContents;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) UIBarButtonItem *navigationBackButton;
@property (nonatomic, strong) UIDocumentInteractionController *documentController;
@property (nonatomic, strong) UILabel *emptyDirectoryLabel;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

// Properties for file operations
@property (nonatomic, strong) NSString *sourceFilePath;
@property (nonatomic, strong) NSArray<NSString *> *sourceFilePaths;
@property (nonatomic, assign) FileOperationType operationType;
@property (nonatomic, strong) UIBarButtonItem *pasteButton;

// Properties for multiple selection
@property (nonatomic, assign) BOOL isMultipleSelectionMode;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedFilePaths;
@property (nonatomic, strong) UIBarButtonItem *selectButton;
@property (nonatomic, strong) UIBarButtonItem *cancelSelectButton;
@property (nonatomic, strong) UIBarButtonItem *actionButton;
@property (nonatomic, strong) UIBarButtonItem *selectAllButton;

@end

@implementation FileManagerViewController

- (instancetype)initWithPath:(NSString *)path {
    return [self initWithPath:path sourceFilePath:nil operationType:FileOperationTypeNone];
}

- (instancetype)initWithPath:(NSString *)path sourceFilePath:(NSString *)sourceFilePath operationType:(NSInteger)operationType {
    self = [super init];
    if (self) {
        _currentPath = path ? path : @"/var/jb";
        _fileManager = [NSFileManager defaultManager];
        _sourceFilePath = sourceFilePath;
        _operationType = operationType;
        _selectedFilePaths = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithPath:(NSString *)path sourceFilePaths:(NSArray<NSString *> *)sourceFilePaths operationType:(NSInteger)operationType {
    self = [super init];
    if (self) {
        _currentPath = path ? path : @"/var/jb";
        _fileManager = [NSFileManager defaultManager];
        _sourceFilePaths = sourceFilePaths;
        _operationType = operationType;
        _selectedFilePaths = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Configure navigation bar
    self.title = [self displayNameForPath:self.currentPath];
    
    // Add close button
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone 
                                                                                 target:self 
                                                                                 action:@selector(closeButtonTapped)];
    self.navigationItem.leftBarButtonItem = closeButton;
    
    // Add navigation back button if not at root
    if (![self.currentPath isEqualToString:@"/var/jb"]) {
        self.navigationBackButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.doc"]
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(navigateToParentDirectory)];
        
        UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                       target:self
                                                                                       action:@selector(refreshDirectory)];
        
        self.navigationItem.rightBarButtonItems = @[refreshButton, self.navigationBackButton];
    } else {
        UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                       target:self
                                                                                       action:@selector(refreshDirectory)];
        self.navigationItem.rightBarButtonItem = refreshButton;
    }
    
    // Add selection button if not in copy/move mode
    if (self.operationType == FileOperationTypeNone) {
        // Create select button
        self.selectButton = [[UIBarButtonItem alloc] initWithTitle:@"Select"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(toggleSelectionMode)];
        
        NSMutableArray *rightBarItems = [NSMutableArray arrayWithArray:self.navigationItem.rightBarButtonItems ?: @[]];
        [rightBarItems addObject:self.selectButton];
        self.navigationItem.rightBarButtonItems = rightBarItems;
    }
    
    // Add paste button if we're in copy/move mode
    if ((self.sourceFilePath || self.sourceFilePaths.count > 0) && 
        (self.operationType == FileOperationTypeCopy || self.operationType == FileOperationTypeMove)) {
        
        // Update the title based on operation type
        NSString *operationTitle = (self.operationType == FileOperationTypeCopy) ? @"Copy Here" : @"Move Here";
        UIBarButtonItem *operationButton = [[UIBarButtonItem alloc] initWithTitle:operationTitle
                                                                           style:UIBarButtonItemStylePlain
                                                                          target:self
                                                                          action:@selector(pasteFile)];
        
        NSMutableArray *rightBarItems = [NSMutableArray arrayWithArray:self.navigationItem.rightBarButtonItems ?: @[]];
        [rightBarItems addObject:operationButton];
        self.navigationItem.rightBarButtonItems = rightBarItems;
        
        // Set title to indicate operation
        NSString *promptText;
        if (self.sourceFilePath) {
            NSString *fileName = [self.sourceFilePath lastPathComponent];
            promptText = [NSString stringWithFormat:@"%@ %@", 
                           (self.operationType == FileOperationTypeCopy) ? @"Copy" : @"Move", 
                           fileName];
        } else {
            promptText = [NSString stringWithFormat:@"%@ %lu files", 
                           (self.operationType == FileOperationTypeCopy) ? @"Copy" : @"Move", 
                           (unsigned long)self.sourceFilePaths.count];
        }
        self.navigationItem.prompt = promptText;
    }
    
    // Configure table view
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.allowsMultipleSelection = NO; // Will be toggled in selection mode
    [self.view addSubview:self.tableView];
    
    // Add refresh control
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshDirectory) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;
    
    // Empty directory label
    self.emptyDirectoryLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 80)];
    self.emptyDirectoryLabel.text = @"This directory is empty";
    self.emptyDirectoryLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyDirectoryLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyDirectoryLabel.font = [UIFont systemFontOfSize:16];
    self.emptyDirectoryLabel.hidden = YES;
    [self.view addSubview:self.emptyDirectoryLabel];
    
    // Add swipe gesture recognizer for navigation
    UISwipeGestureRecognizer *swipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
    swipeGesture.direction = UISwipeGestureRecognizerDirectionRight; // Right swipe to go back
    [self.view addGestureRecognizer:swipeGesture];
    
    // Load directory contents
    [self loadDirectoryContents];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Center empty directory label
    self.emptyDirectoryLabel.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2 - 40);
}

#pragma mark - Directory Management

- (void)loadDirectoryContents {
    NSError *error = nil;
    NSArray *contents = [self.fileManager contentsOfDirectoryAtPath:self.currentPath error:&error];
    
    if (error) {
        NSLog(@"Error loading directory contents: %@", error.localizedDescription);
        [self showAlertWithTitle:@"Error" message:[NSString stringWithFormat:@"Could not load contents of directory: %@", error.localizedDescription]];
        self.directoryContents = @[];
    } else {
        // Sort contents: directories first, then files alphabetically
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES];
        contents = [contents sortedArrayUsingDescriptors:@[sortDescriptor]];
        
        NSMutableArray *sortedContents = [NSMutableArray array];
        NSMutableArray *directories = [NSMutableArray array];
        NSMutableArray *files = [NSMutableArray array];
        
        for (NSString *item in contents) {
            if ([item hasPrefix:@"."]) continue; // Skip hidden files
            
            NSString *fullPath = [self.currentPath stringByAppendingPathComponent:item];
            BOOL isDirectory = NO;
            
            if ([self.fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
                if (isDirectory) {
                    [directories addObject:item];
                } else {
                    [files addObject:item];
                }
            }
        }
        
        [sortedContents addObjectsFromArray:directories];
        [sortedContents addObjectsFromArray:files];
        
        self.directoryContents = [sortedContents copy];
    }
    
    [self.tableView reloadData];
    self.emptyDirectoryLabel.hidden = self.directoryContents.count > 0;
}

- (void)navigateToDirectory:(NSString *)directoryName {
    NSString *newPath = [self.currentPath stringByAppendingPathComponent:directoryName];
    
    // Create new view controller, preserving operation state
    FileManagerViewController *fileManagerVC;
    if (self.sourceFilePaths.count > 0) {
        fileManagerVC = [[FileManagerViewController alloc] initWithPath:newPath 
                                                        sourceFilePaths:self.sourceFilePaths
                                                         operationType:self.operationType];
    } else {
        fileManagerVC = [[FileManagerViewController alloc] initWithPath:newPath 
                                                         sourceFilePath:self.sourceFilePath 
                                                         operationType:self.operationType];
    }
    
    [self.navigationController pushViewController:fileManagerVC animated:YES];
}

- (void)navigateToParentDirectory {
    NSString *parentPath = [self.currentPath stringByDeletingLastPathComponent];
    if ([parentPath hasPrefix:@"/var/jb"]) {
        // Create new view controller, preserving operation state
        FileManagerViewController *fileManagerVC;
        if (self.sourceFilePaths.count > 0) {
            fileManagerVC = [[FileManagerViewController alloc] initWithPath:parentPath 
                                                           sourceFilePaths:self.sourceFilePaths 
                                                            operationType:self.operationType];
        } else {
            fileManagerVC = [[FileManagerViewController alloc] initWithPath:parentPath 
                                                             sourceFilePath:self.sourceFilePath 
                                                             operationType:self.operationType];
        }
        
        NSMutableArray *viewControllers = [NSMutableArray arrayWithArray:self.navigationController.viewControllers];
        if (viewControllers.count > 1) {
            [viewControllers removeLastObject];
        }
        [viewControllers addObject:fileManagerVC];
        [self.navigationController setViewControllers:viewControllers animated:YES];
    }
}

- (void)refreshDirectory {
    [self loadDirectoryContents];
    [self.refreshControl endRefreshing];
}

#pragma mark - Table View Delegate/DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.directoryContents.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"FileCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }
    
    NSString *itemName = self.directoryContents[indexPath.row];
    NSString *fullPath = [self.currentPath stringByAppendingPathComponent:itemName];
    BOOL isDirectory = NO;
    [self.fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory];
    
    // Configure cell
    cell.textLabel.text = itemName;
    
    // Get file attributes
    NSError *error = nil;
    NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:fullPath error:&error];
    NSString *fileSize = @"";
    
    if (!error) {
        if (!isDirectory) {
            fileSize = [self formattedFileSize:[attributes fileSize]];
        }
        
        NSDate *modDate = [attributes fileModificationDate];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
        
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", 
                                     fileSize, 
                                     [dateFormatter stringFromDate:modDate]];
    } else {
        cell.detailTextLabel.text = @"";
    }
    
    // Set icon
    NSString *fileExtension = @"";
    if (isDirectory) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        fileExtension = [itemName pathExtension];
        NSString *iconName = [self iconNameForFileExtension:fileExtension];
        cell.imageView.image = [UIImage systemImageNamed:iconName];
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
    }
    
    // Set tint color based on file type
    if (isDirectory) {
        cell.imageView.tintColor = [UIColor systemBlueColor];
    } else {
        UIColor *tintColor = [self colorForFileExtension:fileExtension];
        cell.imageView.tintColor = tintColor;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *selectedItem = self.directoryContents[indexPath.row];
    NSString *fullPath = [self.currentPath stringByAppendingPathComponent:selectedItem];
    BOOL isDirectory = NO;
    
    if ([self.fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
        if (isDirectory) {
            [self navigateToDirectory:selectedItem];
        } else {
            // Preview file
            [self previewFileAtPath:fullPath];
        }
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    NSString *selectedItem = self.directoryContents[indexPath.row];
    NSString *fullPath = [self.currentPath stringByAppendingPathComponent:selectedItem];
    
    [self showFileActionsForPath:fullPath];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    NSString *selectedItem = self.directoryContents[indexPath.row];
    NSString *fullPath = [self.currentPath stringByAppendingPathComponent:selectedItem];
    
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        
        // Get file attributes
        BOOL isDirectory = NO;
        [self.fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory];
        
        NSMutableArray *actions = [NSMutableArray array];
        
        if (isDirectory) {
            [actions addObject:[UIAction actionWithTitle:@"Open" 
                                                   image:[UIImage systemImageNamed:@"folder"] 
                                              identifier:nil 
                                                 handler:^(__kindof UIAction * _Nonnull action) {
                [self navigateToDirectory:selectedItem];
            }]];
        } else {
            [actions addObject:[UIAction actionWithTitle:@"Preview" 
                                                   image:[UIImage systemImageNamed:@"eye"] 
                                              identifier:nil 
                                                 handler:^(__kindof UIAction * _Nonnull action) {
                [self previewFileAtPath:fullPath];
            }]];
        }
        
        [actions addObject:[UIAction actionWithTitle:@"Info" 
                                               image:[UIImage systemImageNamed:@"info.circle"] 
                                          identifier:nil 
                                             handler:^(__kindof UIAction * _Nonnull action) {
            [self showFileInfoForPath:fullPath];
        }]];
        
        // Copy action
        [actions addObject:[UIAction actionWithTitle:@"Copy" 
                                               image:[UIImage systemImageNamed:@"doc.on.doc"] 
                                          identifier:nil 
                                             handler:^(__kindof UIAction * _Nonnull action) {
            FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:self.currentPath 
                                                                                       sourceFilePath:fullPath 
                                                                                       operationType:FileOperationTypeCopy];
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
            navController.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:navController animated:YES completion:nil];
        }]];
        
        // Move action
        [actions addObject:[UIAction actionWithTitle:@"Move" 
                                               image:[UIImage systemImageNamed:@"folder.badge.plus"] 
                                          identifier:nil 
                                             handler:^(__kindof UIAction * _Nonnull action) {
            FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:self.currentPath 
                                                                                       sourceFilePath:fullPath 
                                                                                       operationType:FileOperationTypeMove];
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
            navController.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:navController animated:YES completion:nil];
        }]];
        
        // Rename action
        [actions addObject:[UIAction actionWithTitle:@"Rename" 
                                               image:[UIImage systemImageNamed:@"pencil"] 
                                          identifier:nil 
                                             handler:^(__kindof UIAction * _Nonnull action) {
            [self renameItemAtPath:fullPath];
        }]];
        
        [actions addObject:[UIAction actionWithTitle:@"Share" 
                                               image:[UIImage systemImageNamed:@"square.and.arrow.up"] 
                                          identifier:nil 
                                             handler:^(__kindof UIAction * _Nonnull action) {
            [self shareItemAtPath:fullPath];
        }]];
        
        // Add delete action
        UIAction *deleteAction = [UIAction actionWithTitle:@"Delete" 
                                                     image:[UIImage systemImageNamed:@"trash"] 
                                                identifier:nil 
                                                   handler:^(__kindof UIAction * _Nonnull action) {
            [self confirmDeleteItemAtPath:fullPath];
        }];
        deleteAction.attributes = UIMenuElementAttributesDestructive;
        [actions addObject:deleteAction];
        
        return [UIMenu menuWithTitle:@"" children:actions];
    }];
}

#pragma mark - Helper Methods

- (NSString *)iconNameForFileExtension:(NSString *)extension {
    // Default icon
    NSString *iconName = @"doc.fill";
    
    // Define icons for common file types
    NSDictionary *extensionToIcon = @{
        @"jpg": @"photo.fill",
        @"jpeg": @"photo.fill",
        @"png": @"photo.fill",
        @"gif": @"photo.fill",
        @"heic": @"photo.fill",
        @"mp4": @"video.fill",
        @"mov": @"video.fill",
        @"mp3": @"music.note",
        @"m4a": @"music.note",
        @"wav": @"music.note",
        @"pdf": @"doc.text.fill",
        @"txt": @"doc.text.fill",
        @"rtf": @"doc.text.fill",
        @"html": @"doc.text.fill",
        @"plist": @"list.bullet",
        @"zip": @"archivebox.fill",
        @"tar": @"archivebox.fill",
        @"gz": @"archivebox.fill",
        @"deb": @"shippingbox.fill",
        @"ipa": @"app.badge.fill",
        @"app": @"app.fill",
        @"dylib": @"puzzlepiece.fill",
        @"bundle": @"cube.box.fill",
    };
    
    NSString *matchedIcon = extensionToIcon[extension.lowercaseString];
    if (matchedIcon) {
        iconName = matchedIcon;
    }
    
    return iconName;
}

- (UIColor *)colorForFileExtension:(NSString *)extension {
    // Default color
    UIColor *color = [UIColor systemGrayColor];
    
    // Define colors for common file types
    NSDictionary *extensionToColor = @{
        @"jpg": [UIColor systemPinkColor],
        @"jpeg": [UIColor systemPinkColor],
        @"png": [UIColor systemPinkColor],
        @"gif": [UIColor systemPinkColor],
        @"heic": [UIColor systemPinkColor],
        @"mp4": [UIColor systemPurpleColor],
        @"mov": [UIColor systemPurpleColor],
        @"mp3": [UIColor systemRedColor],
        @"m4a": [UIColor systemRedColor],
        @"wav": [UIColor systemRedColor],
        @"pdf": [UIColor systemOrangeColor],
        @"txt": [UIColor systemGreenColor],
        @"rtf": [UIColor systemGreenColor],
        @"html": [UIColor systemGreenColor],
        @"plist": [UIColor systemTealColor],
        @"zip": [UIColor systemIndigoColor],
        @"tar": [UIColor systemIndigoColor],
        @"gz": [UIColor systemIndigoColor],
        @"deb": [UIColor systemOrangeColor],
        @"ipa": [UIColor systemBlueColor],
        @"app": [UIColor systemBlueColor],
        @"dylib": [UIColor systemYellowColor],
        @"bundle": [UIColor systemBlueColor],
    };
    
    UIColor *matchedColor = extensionToColor[extension.lowercaseString];
    if (matchedColor) {
        color = matchedColor;
    }
    
    return color;
}

- (NSString *)displayNameForPath:(NSString *)path {
    if ([path isEqualToString:@"/var/jb"]) {
        return @"Root";
    }
    
    return [path lastPathComponent];
}

- (NSString *)formattedFileSize:(unsigned long long)size {
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    NSString *formattedSize = [formatter stringFromByteCount:size];
    return [NSString stringWithFormat:@"%@ • ", formattedSize];
}

#pragma mark - File Actions

- (void)previewFileAtPath:(NSString *)path {
    // If it's a plist file, use our custom plist viewer
    if ([[path pathExtension].lowercaseString isEqualToString:@"plist"]) {
        PlistViewerViewController *plistVC = [[PlistViewerViewController alloc] initWithPlistPath:path];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:plistVC];
        navController.modalPresentationStyle = UIModalPresentationPageSheet;
        [self presentViewController:navController animated:YES completion:nil];
        return;
    }
    
    // Check if file is too large
    NSError *error = nil;
    NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:path error:&error];
    
    if (!error && attributes) {
        unsigned long long fileSize = [attributes fileSize];
        
        // Don't try to preview files larger than 10MB
        if (fileSize > 10 * 1024 * 1024) {
            [self showAlertWithTitle:@"File Too Large" 
                             message:@"This file is too large to preview directly. You can share it or view its information."];
            return;
        }
    }
    
    self.documentController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:path]];
    self.documentController.delegate = self;
    
    BOOL success = [self.documentController presentPreviewAnimated:YES];
    
    if (!success) {
        [self showAlertWithTitle:@"Cannot Preview"
                         message:@"This file type cannot be previewed."];
    }
}

- (void)showFileActionsForPath:(NSString *)path {
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:nil
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    BOOL isDirectory = NO;
    [self.fileManager fileExistsAtPath:path isDirectory:&isDirectory];
    
    // Preview action (for files only)
    if (!isDirectory) {
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"Preview"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull action) {
            [self previewFileAtPath:path];
        }]];
    }
    
    // Info action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Info"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        [self showFileInfoForPath:path];
    }]];
    
    // Copy action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Copy"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        // Create new file manager to browse for destination
        FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:self.currentPath 
                                                                                   sourceFilePath:path 
                                                                                   operationType:FileOperationTypeCopy];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navController animated:YES completion:nil];
    }]];
    
    // Move action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Move"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        // Create new file manager to browse for destination
        FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:self.currentPath 
                                                                                   sourceFilePath:path 
                                                                                   operationType:FileOperationTypeMove];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navController animated:YES completion:nil];
    }]];
    
    // Rename action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Rename"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        [self renameItemAtPath:path];
    }]];
    
    // Share action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Share"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        [self shareItemAtPath:path];
    }]];
    
    // Delete action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Delete"
                                                    style:UIAlertActionStyleDestructive
                                                  handler:^(UIAlertAction * _Nonnull action) {
        [self confirmDeleteItemAtPath:path];
    }]];
    
    // Cancel action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];
    
    // For iPad compatibility
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[self.tableView indexPathForSelectedRow]];
        actionSheet.popoverPresentationController.sourceView = cell;
        actionSheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    
    // Present action sheet
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)showFileInfoForPath:(NSString *)path {
    NSError *error = nil;
    NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:path error:&error];
    
    if (error) {
        [self showAlertWithTitle:@"Error" message:[NSString stringWithFormat:@"Could not get file information: %@", error.localizedDescription]];
        return;
    }
    
    BOOL isDirectory = NO;
    [self.fileManager fileExistsAtPath:path isDirectory:&isDirectory];
    
    NSString *name = [path lastPathComponent];
    NSString *type = isDirectory ? @"Directory" : @"File";
    NSString *extension = [path pathExtension];
    
    NSDate *creationDate = [attributes fileCreationDate];
    NSDate *modificationDate = [attributes fileModificationDate];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    
    NSString *creationDateStr = [dateFormatter stringFromDate:creationDate];
    NSString *modificationDateStr = [dateFormatter stringFromDate:modificationDate];
    
    NSString *size = @"--";
    if (!isDirectory) {
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleFile;
        size = [formatter stringFromByteCount:[attributes fileSize]];
    }
    
    NSString *permissions = [NSString stringWithFormat:@"%@ (%lo)", 
                            [attributes fileType], 
                            (unsigned long)[attributes filePosixPermissions]];
    
    NSString *message = [NSString stringWithFormat:
                         @"Name: %@\n"
                         @"Type: %@\n"
                         @"%@"
                         @"Size: %@\n"
                         @"Created: %@\n"
                         @"Modified: %@\n"
                         @"Permissions: %@\n"
                         @"Path: %@",
                         name,
                         type,
                         extension.length > 0 ? [NSString stringWithFormat:@"Extension: %@\n", extension] : @"",
                         size,
                         creationDateStr,
                         modificationDateStr,
                         permissions,
                         path];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"File Information"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareItemAtPath:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    NSArray *activityItems = @[fileURL];
    
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:nil];
    
    // For iPad
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)confirmDeleteItemAtPath:(NSString *)path {
    NSString *message = [NSString stringWithFormat:@"Are you sure you want to delete '%@'? This action cannot be undone.", [path lastPathComponent]];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Delete"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteItemAtPath:path];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteItemAtPath:(NSString *)path {
    NSError *error = nil;
    BOOL success = [self.fileManager removeItemAtPath:path error:&error];
    
    if (!success) {
        [self showAlertWithTitle:@"Delete Failed" message:[NSString stringWithFormat:@"Could not delete item: %@", error.localizedDescription]];
    } else {
        [self loadDirectoryContents];
    }
}

#pragma mark - Document Interaction Controller Delegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self;
}

#pragma mark - Navigation

- (void)closeButtonTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Alerts

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Handle swipe gesture for navigation
- (void)handleSwipeGesture:(UISwipeGestureRecognizer *)gesture {
    if (gesture.direction == UISwipeGestureRecognizerDirectionRight) {
        // Only navigate back if not at root
        if (![self.currentPath isEqualToString:@"/var/jb"]) {
            [self navigateToParentDirectory];
        }
    }
}

- (void)pasteFile {
    if (!self.sourceFilePath && self.sourceFilePaths.count == 0) {
        return;
    }
    
    // Handle single file operation
    if (self.sourceFilePath) {
        NSString *sourceFileName = [self.sourceFilePath lastPathComponent];
        NSString *destinationPath = [self.currentPath stringByAppendingPathComponent:sourceFileName];
        
        // Check if destination file already exists
        if ([self.fileManager fileExistsAtPath:destinationPath]) {
            // Ask for confirmation to overwrite
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"File Already Exists"
                                                                          message:[NSString stringWithFormat:@"'%@' already exists at this location. Do you want to replace it?", sourceFileName]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [self performFileOperation];
            }]];
            
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            [self performFileOperation];
        }
    } 
    // Handle multiple files operation
    else if (self.sourceFilePaths.count > 0) {
        // Check if any destination files already exist
        BOOL filesExist = NO;
        NSMutableArray *existingFiles = [NSMutableArray array];
        
        for (NSString *sourcePath in self.sourceFilePaths) {
            NSString *sourceFileName = [sourcePath lastPathComponent];
            NSString *destinationPath = [self.currentPath stringByAppendingPathComponent:sourceFileName];
            
            if ([self.fileManager fileExistsAtPath:destinationPath]) {
                filesExist = YES;
                [existingFiles addObject:sourceFileName];
            }
        }
        
        if (filesExist) {
            // Ask for confirmation to overwrite
            NSString *existingFilesList = [existingFiles componentsJoinedByString:@", "];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Files Already Exist"
                                                                          message:[NSString stringWithFormat:@"The following files already exist: %@. Do you want to replace them?", existingFilesList]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Replace All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [self performFileOperation];
            }]];
            
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            [self performFileOperation];
        }
    }
}

- (void)performFileOperation {
    NSError *error = nil;
    BOOL success = YES;
    NSString *destinationPath;
    
    // Handle single file operation
    if (self.sourceFilePath) {
        NSString *sourceFileName = [self.sourceFilePath lastPathComponent];
        destinationPath = [self.currentPath stringByAppendingPathComponent:sourceFileName];
        
        if (self.operationType == FileOperationTypeCopy) {
            // Perform copy operation
            success = [self.fileManager copyItemAtPath:self.sourceFilePath toPath:destinationPath error:&error];
        } else if (self.operationType == FileOperationTypeMove) {
            // Perform move operation
            success = [self.fileManager moveItemAtPath:self.sourceFilePath toPath:destinationPath error:&error];
        }
    } 
    // Handle multiple files operation
    else if (self.sourceFilePaths.count > 0) {
        for (NSString *sourcePath in self.sourceFilePaths) {
            NSString *sourceFileName = [sourcePath lastPathComponent];
            destinationPath = [self.currentPath stringByAppendingPathComponent:sourceFileName];
            
            NSError *singleError = nil;
            BOOL singleSuccess = YES;
            
            if (self.operationType == FileOperationTypeCopy) {
                // Perform copy operation
                singleSuccess = [self.fileManager copyItemAtPath:sourcePath toPath:destinationPath error:&singleError];
            } else if (self.operationType == FileOperationTypeMove) {
                // Perform move operation
                singleSuccess = [self.fileManager moveItemAtPath:sourcePath toPath:destinationPath error:&singleError];
            }
            
            if (!singleSuccess) {
                success = NO;
                error = singleError;
                break;
            }
        }
    }
    
    if (success) {
        // Operation was successful
        NSString *message = (self.operationType == FileOperationTypeCopy) ? @"Files copied successfully." : @"Files moved successfully.";
        [self showAlertWithTitle:@"Success" message:message];
        
        // Reset operation state and reload directory
        self.sourceFilePath = nil;
        self.sourceFilePaths = nil;
        self.operationType = FileOperationTypeNone;
        self.navigationItem.prompt = nil;
        
        // Update paste button
        NSMutableArray *rightBarItems = [NSMutableArray arrayWithArray:self.navigationItem.rightBarButtonItems];
        if (rightBarItems.count > 0) {
            [rightBarItems removeLastObject];
            self.navigationItem.rightBarButtonItems = rightBarItems;
        }
        
        [self loadDirectoryContents];
    } else {
        // Operation failed
        [self showAlertWithTitle:@"Operation Failed" message:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
    }
}

- (void)renameItemAtPath:(NSString *)path {
    NSString *fileName = [path lastPathComponent];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename"
                                                                   message:[NSString stringWithFormat:@"Enter new name for '%@'", fileName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = fileName;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *newName = textField.text;
        
        if (newName.length == 0 || [newName isEqualToString:fileName]) {
            return;
        }
        
        NSString *newPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        
        NSError *error = nil;
        BOOL success = [self.fileManager moveItemAtPath:path toPath:newPath error:&error];
        
        if (success) {
            [self loadDirectoryContents];
        } else {
            [self showAlertWithTitle:@"Rename Failed" message:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
        }
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleSelectionMode {
    self.isMultipleSelectionMode = !self.isMultipleSelectionMode;
    
    if (self.isMultipleSelectionMode) {
        // Clear selection
        [self.selectedFilePaths removeAllObjects];
        
        // Create cancel button
        self.cancelSelectButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                               target:self
                                                                               action:@selector(toggleSelectionMode)];
        
        // Create action button
        self.actionButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                         target:self
                                                                         action:@selector(showMultiSelectionActions)];
        self.actionButton.enabled = NO;
        
        // Create select all button
        self.selectAllButton = [[UIBarButtonItem alloc] initWithTitle:@"Select All"
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(selectAllItems)];
        
        // Update navigation bar
        self.navigationItem.rightBarButtonItems = @[self.cancelSelectButton, self.actionButton, self.selectAllButton];
        self.tableView.allowsMultipleSelection = YES;
        
        // Update navigation title
        self.navigationItem.prompt = @"Select items";
    } else {
        // Restore normal state
        [self.selectedFilePaths removeAllObjects];
        
        // Update navigation bar
        NSMutableArray *rightBarItems = [NSMutableArray array];
        
        UIBarButtonItem *refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                      target:self
                                                                                      action:@selector(refreshDirectory)];
        [rightBarItems addObject:refreshButton];
        
        if (![self.currentPath isEqualToString:@"/var/jb"]) {
            [rightBarItems addObject:self.navigationBackButton];
        }
        
        [rightBarItems addObject:self.selectButton];
        
        self.navigationItem.rightBarButtonItems = rightBarItems;
        self.tableView.allowsMultipleSelection = NO;
        
        // Clear selection UI
        self.navigationItem.prompt = nil;
        
        // Deselect all rows
        for (NSIndexPath *indexPath in [self.tableView indexPathsForSelectedRows] ?: @[]) {
            [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        }
        
        [self.tableView reloadData];
    }
}

- (void)selectAllItems {
    [self.selectedFilePaths removeAllObjects];
    
    // Select all rows
    for (NSInteger i = 0; i < self.directoryContents.count; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
        [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        
        NSString *itemName = self.directoryContents[i];
        NSString *fullPath = [self.currentPath stringByAppendingPathComponent:itemName];
        [self.selectedFilePaths addObject:fullPath];
    }
    
    // Update the action button state
    self.actionButton.enabled = (self.selectedFilePaths.count > 0);
    
    // Update the prompt
    self.navigationItem.prompt = [NSString stringWithFormat:@"%lu items selected", (unsigned long)self.selectedFilePaths.count];
}

- (void)showMultiSelectionActions {
    if (self.selectedFilePaths.count == 0) {
        return;
    }
    
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:nil
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add copy action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Copy Items"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        // Create new file manager for destination selection
        FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:self.currentPath
                                                                                  sourceFilePaths:[self.selectedFilePaths copy]
                                                                                   operationType:FileOperationTypeCopy];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navController animated:YES completion:nil];
    }]];
    
    // Add move action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Move Items"
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
        // Create new file manager for destination selection
        FileManagerViewController *fileManagerVC = [[FileManagerViewController alloc] initWithPath:self.currentPath
                                                                                  sourceFilePaths:[self.selectedFilePaths copy]
                                                                                   operationType:FileOperationTypeMove];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:fileManagerVC];
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navController animated:YES completion:nil];
    }]];
    
    // Add delete action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Delete Items"
                                                    style:UIAlertActionStyleDestructive
                                                  handler:^(UIAlertAction * _Nonnull action) {
        [self confirmDeleteMultipleItemsAtPaths:self.selectedFilePaths];
    }]];
    
    // Cancel action
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];
    
    // For iPad
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.barButtonItem = self.actionButton;
    }
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)confirmDeleteMultipleItemsAtPaths:(NSArray<NSString *> *)paths {
    NSString *message = [NSString stringWithFormat:@"Are you sure you want to delete %lu items? This action cannot be undone.", 
                         (unsigned long)paths.count];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Confirm Delete"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteMultipleItemsAtPaths:paths];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteMultipleItemsAtPaths:(NSArray<NSString *> *)paths {
    NSInteger successCount = 0;
    NSInteger failCount = 0;
    
    for (NSString *path in paths) {
        NSError *error = nil;
        BOOL success = [self.fileManager removeItemAtPath:path error:&error];
        
        if (success) {
            successCount++;
        } else {
            failCount++;
            NSLog(@"Failed to delete %@: %@", path, error.localizedDescription);
        }
    }
    
    // Exit selection mode
    self.isMultipleSelectionMode = NO;
    [self toggleSelectionMode];
    
    // Show results
    NSString *message;
    if (failCount == 0) {
        message = [NSString stringWithFormat:@"Successfully deleted %ld items.", (long)successCount];
    } else {
        message = [NSString stringWithFormat:@"Deleted %ld items. Failed to delete %ld items.", (long)successCount, (long)failCount];
    }
    
    [self showAlertWithTitle:@"Delete Complete" message:message];
    
    // Refresh directory contents
    [self loadDirectoryContents];
}

@end 