#import "PlistViewerViewController.h"

@interface PlistViewerViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *plistPath;
@property (nonatomic, strong) id plistContent;
@property (nonatomic, strong) NSArray *allKeys;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, assign) BOOL isEditing;
@property (nonatomic, strong) NSMutableDictionary *editedValues;

@end

@implementation PlistViewerViewController

- (instancetype)initWithPlistPath:(NSString *)path {
    self = [super init];
    if (self) {
        _plistPath = path;
        _editedValues = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [self.plistPath lastPathComponent];
    
    // Add edit and share buttons
    UIBarButtonItem *editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                               target:self
                                                                               action:@selector(toggleEditMode)];
    
    UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                target:self
                                                                                action:@selector(sharePlist)];
    
    self.navigationItem.rightBarButtonItems = @[editButton, shareButton];
    
    // Setup table view
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.hidden = YES;
    [self.view addSubview:self.tableView];
    
    // Error label (will be displayed if the plist can't be read)
    self.errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, self.view.bounds.size.width - 40, 80)];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.textColor = [UIColor secondaryLabelColor];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];
    
    // Add swipe gesture recognizer for navigation
    UISwipeGestureRecognizer *swipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
    swipeGesture.direction = UISwipeGestureRecognizerDirectionRight; // Right swipe to go back
    [self.view addGestureRecognizer:swipeGesture];
    
    // Load plist content
    [self loadPlistContent];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Center error label
    self.errorLabel.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2 - 40);
}

#pragma mark - Plist Loading

- (void)loadPlistContent {
    NSError *error = nil;
    NSData *plistData = [NSData dataWithContentsOfFile:self.plistPath options:0 error:&error];
    
    if (!plistData || error) {
        [self showErrorMessage:[NSString stringWithFormat:@"Error loading plist: %@", error.localizedDescription]];
        return;
    }
    
    // Try to read as XML plist
    NSPropertyListFormat format;
    self.plistContent = [NSPropertyListSerialization propertyListWithData:plistData
                                                                 options:NSPropertyListMutableContainersAndLeaves
                                                                  format:&format
                                                                   error:&error];
    
    if (!self.plistContent || error) {
        [self showErrorMessage:[NSString stringWithFormat:@"Error parsing plist: %@", error.localizedDescription]];
        return;
    }
    
    // Successfully loaded
    if ([self.plistContent isKindOfClass:[NSDictionary class]]) {
        // Dictionary plist
        self.allKeys = [(NSDictionary *)self.plistContent allKeys];
        
        // Sort keys alphabetically
        self.allKeys = [self.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        
    } else if ([self.plistContent isKindOfClass:[NSArray class]]) {
        // Array plist - use indices as keys
        NSMutableArray *indices = [NSMutableArray array];
        for (NSInteger i = 0; i < [(NSArray *)self.plistContent count]; i++) {
            [indices addObject:@(i)];
        }
        self.allKeys = indices;
    } else {
        // Single value plist (rare)
        self.allKeys = @[@"Value"];
    }
    
    self.tableView.hidden = NO;
    [self.tableView reloadData];
}

- (void)showErrorMessage:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = NO;
    self.tableView.hidden = YES;
}

#pragma mark - Edit Mode

- (void)toggleEditMode {
    self.isEditing = !self.isEditing;
    
    if (self.isEditing) {
        // Switch to edit mode
        UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                   target:self
                                                                                   action:@selector(toggleEditMode)];
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                     target:self
                                                                                     action:@selector(cancelEditing)];
        self.navigationItem.rightBarButtonItems = @[doneButton, cancelButton];
        
        // Clear edited values
        [self.editedValues removeAllObjects];
    } else {
        // Save changes and exit edit mode
        [self saveChanges];
        
        UIBarButtonItem *editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                                   target:self
                                                                                   action:@selector(toggleEditMode)];
        UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                    target:self
                                                                                    action:@selector(sharePlist)];
        self.navigationItem.rightBarButtonItems = @[editButton, shareButton];
    }
    
    [self.tableView reloadData];
}

- (void)cancelEditing {
    self.isEditing = NO;
    [self.editedValues removeAllObjects];
    
    UIBarButtonItem *editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
                                                                               target:self
                                                                               action:@selector(toggleEditMode)];
    UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                target:self
                                                                                action:@selector(sharePlist)];
    self.navigationItem.rightBarButtonItems = @[editButton, shareButton];
    
    [self.tableView reloadData];
}

- (void)saveChanges {
    // Apply changes to plist content
    for (id key in self.editedValues.allKeys) {
        id newValue = self.editedValues[key];
        
        if ([self.plistContent isKindOfClass:[NSMutableDictionary class]]) {
            [(NSMutableDictionary *)self.plistContent setObject:newValue forKey:key];
        } else if ([self.plistContent isKindOfClass:[NSMutableArray class]]) {
            NSInteger index = [key integerValue];
            if (index < [(NSMutableArray *)self.plistContent count]) {
                [(NSMutableArray *)self.plistContent replaceObjectAtIndex:index withObject:newValue];
            }
        } else {
            // Single value plist
            self.plistContent = newValue;
        }
    }
    
    // Write back to file
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.plistContent
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    
    if (error || !data) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:[NSString stringWithFormat:@"Failed to save changes: %@", error.localizedDescription]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    [data writeToFile:self.plistPath atomically:YES];
    
    // Clear edited values
    [self.editedValues removeAllObjects];
    
    // Show success message
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                   message:@"Changes saved successfully"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.allKeys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"PlistCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }
    
    id key = self.allKeys[indexPath.row];
    id value = nil;
    
    // Check if we have an edited value for this key
    if (self.editedValues[key]) {
        value = self.editedValues[key];
    } else {
        if ([self.plistContent isKindOfClass:[NSDictionary class]]) {
            value = [(NSDictionary *)self.plistContent objectForKey:key];
        } else if ([self.plistContent isKindOfClass:[NSArray class]]) {
            value = [(NSArray *)self.plistContent objectAtIndex:[key integerValue]];
        } else {
            value = self.plistContent;
        }
    }
    
    // Display key and type of value
    cell.textLabel.text = [key description];
    
    if ([value isKindOfClass:[NSDictionary class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Dictionary (%lu keys)", (unsigned long)[(NSDictionary *)value count]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Array (%lu items)", (unsigned long)[(NSArray *)value count]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([value isKindOfClass:[NSString class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"String: %@", value];
        cell.accessoryType = self.isEditing ? UITableViewCellAccessoryDetailButton : UITableViewCellAccessoryNone;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        // Determine if number is boolean
        if (strcmp([value objCType], @encode(BOOL)) == 0) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Boolean: %@", [value boolValue] ? @"YES" : @"NO"];
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Number: %@", value];
        }
        cell.accessoryType = self.isEditing ? UITableViewCellAccessoryDetailButton : UITableViewCellAccessoryNone;
    } else if ([value isKindOfClass:[NSData class]]) {
        NSUInteger length = [(NSData *)value length];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Data (%lu bytes)", (unsigned long)length];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([value isKindOfClass:[NSDate class]]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterMediumStyle];
        [formatter setTimeStyle:NSDateFormatterMediumStyle];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Date: %@", [formatter stringFromDate:(NSDate *)value]];
        cell.accessoryType = self.isEditing ? UITableViewCellAccessoryDetailButton : UITableViewCellAccessoryNone;
    } else if (value == nil || value == [NSNull null]) {
        cell.detailTextLabel.text = @"<null>";
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %@", [value class], value];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    return cell;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    id key = self.allKeys[indexPath.row];
    id value = nil;
    
    // Check if we have an edited value
    if (self.editedValues[key]) {
        value = self.editedValues[key];
    } else {
        if ([self.plistContent isKindOfClass:[NSDictionary class]]) {
            value = [(NSDictionary *)self.plistContent objectForKey:key];
        } else if ([self.plistContent isKindOfClass:[NSArray class]]) {
            value = [(NSArray *)self.plistContent objectAtIndex:[key integerValue]];
        } else {
            value = self.plistContent;
        }
    }
    
    if (self.isEditing) {
        // In edit mode, show edit UI for simple values
        if ([value isKindOfClass:[NSString class]] || 
            [value isKindOfClass:[NSNumber class]] ||
            [value isKindOfClass:[NSDate class]]) {
            [self showEditDialogForKey:key value:value];
            return;
        }
    }
    
    // Handle dictionary and array values by opening a new plist viewer
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        // Create a temporary file for the sub-plist
        NSString *tempDir = NSTemporaryDirectory();
        NSString *filename = [NSString stringWithFormat:@"%@_%@.plist", 
                              [[self.plistPath lastPathComponent] stringByDeletingPathExtension], 
                              [key description]];
        NSString *tempPath = [tempDir stringByAppendingPathComponent:filename];
        
        // Write the sub-plist to the temp file
        NSError *error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:value
                                                                  format:NSPropertyListXMLFormat_v1_0
                                                                 options:0
                                                                   error:&error];
        if (!error && data) {
            [data writeToFile:tempPath atomically:YES];
            
            // Open new PlistViewerViewController with the temp file
            PlistViewerViewController *subPlistVC = [[PlistViewerViewController alloc] initWithPlistPath:tempPath];
            if ([key isKindOfClass:[NSString class]]) {
                subPlistVC.title = key;
            } else {
                subPlistVC.title = [NSString stringWithFormat:@"Item %@", [key description]];
            }
            [self.navigationController pushViewController:subPlistVC animated:YES];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                          message:[NSString stringWithFormat:@"Could not create sub-plist: %@", error.localizedDescription]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if ([value isKindOfClass:[NSData class]]) {
        // For data objects, show a hex and ASCII representation
        NSData *data = (NSData *)value;
        NSString *hexString = [self hexStringFromData:data];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Data Contents"
                                                                      message:hexString
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if (!self.isEditing) return;
    
    id key = self.allKeys[indexPath.row];
    id value = nil;
    
    // Check if we have an edited value
    if (self.editedValues[key]) {
        value = self.editedValues[key];
    } else {
        if ([self.plistContent isKindOfClass:[NSDictionary class]]) {
            value = [(NSDictionary *)self.plistContent objectForKey:key];
        } else if ([self.plistContent isKindOfClass:[NSArray class]]) {
            value = [(NSArray *)self.plistContent objectAtIndex:[key integerValue]];
        } else {
            value = self.plistContent;
        }
    }
    
    [self showEditDialogForKey:key value:value];
}

#pragma mark - Editing UI

- (void)showEditDialogForKey:(id)key value:(id)value {
    NSString *title = [NSString stringWithFormat:@"Edit %@", [key description]];
    UIAlertController *alert = nil;
    
    if ([value isKindOfClass:[NSString class]]) {
        // String editing
        alert = [UIAlertController alertControllerWithTitle:title
                                                   message:@"Enter new string value"
                                            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = value;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        }];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UITextField *textField = alert.textFields.firstObject;
            NSString *newValue = textField.text;
            [self updateValue:newValue forKey:key];
        }]];
        
    } else if ([value isKindOfClass:[NSNumber class]]) {
        // Determine if number is boolean
        if (strcmp([value objCType], @encode(BOOL)) == 0) {
            // Boolean editing
            alert = [UIAlertController alertControllerWithTitle:title
                                                       message:@"Select boolean value"
                                                preferredStyle:UIAlertControllerStyleActionSheet];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"YES" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self updateValue:@YES forKey:key];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"NO" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self updateValue:@NO forKey:key];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            
        } else {
            // Number editing
            alert = [UIAlertController alertControllerWithTitle:title
                                                       message:@"Enter new numeric value"
                                                preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.text = [value stringValue];
                textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
                textField.clearButtonMode = UITextFieldViewModeWhileEditing;
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                UITextField *textField = alert.textFields.firstObject;
                NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
                formatter.numberStyle = NSNumberFormatterDecimalStyle;
                NSNumber *newValue = [formatter numberFromString:textField.text];
                
                if (newValue) {
                    [self updateValue:newValue forKey:key];
                } else {
                    // Try to convert to integer or float
                    if ([textField.text containsString:@"."]) {
                        float floatValue = [textField.text floatValue];
                        [self updateValue:@(floatValue) forKey:key];
                    } else {
                        int intValue = [textField.text intValue];
                        [self updateValue:@(intValue) forKey:key];
                    }
                }
            }]];
        }
    } else if ([value isKindOfClass:[NSDate class]]) {
        // Date editing not directly supported in alert controllers
        // Instead show an informative message
        alert = [UIAlertController alertControllerWithTitle:@"Date Editing"
                                                   message:@"Date editing is not supported in this version."
                                            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    }
    
    if (alert) {
        // For iPad, we need to set the source view for action sheets
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad &&
            alert.preferredStyle == UIAlertControllerStyleActionSheet) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[self.tableView indexPathForSelectedRow]];
            alert.popoverPresentationController.sourceView = cell;
            alert.popoverPresentationController.sourceRect = cell.bounds;
        }
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)updateValue:(id)newValue forKey:(id)key {
    self.editedValues[key] = newValue;
    [self.tableView reloadData];
}

#pragma mark - Helper Methods

- (NSString *)hexStringFromData:(NSData *)data {
    // Limit the amount of data displayed to prevent huge alerts
    NSUInteger bytesToShow = MIN(data.length, 256);
    NSMutableString *hexString = [NSMutableString stringWithCapacity:bytesToShow * 3 + 50];
    
    [hexString appendFormat:@"Showing first %lu bytes of %lu total bytes\n\n", (unsigned long)bytesToShow, (unsigned long)data.length];
    
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < bytesToShow; i++) {
        [hexString appendFormat:@"%02X ", bytes[i]];
        if ((i + 1) % 8 == 0 || i == bytesToShow - 1) {
            [hexString appendString:@"\n"];
        }
    }
    
    return hexString;
}

#pragma mark - Actions

- (void)sharePlist {
    NSURL *fileURL = [NSURL fileURLWithPath:self.plistPath];
    NSArray *activityItems = @[fileURL];
    
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:nil];
    
    // For iPad
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
        activityVC.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems[1];
    }
    
    [self presentViewController:activityVC animated:YES completion:nil];
}

// Handle swipe gesture for navigation
- (void)handleSwipeGesture:(UISwipeGestureRecognizer *)gesture {
    if (gesture.direction == UISwipeGestureRecognizerDirectionRight) {
        // For modal presentation, dismiss if it's the root view of the navigation stack
        if (self.navigationController.viewControllers.count <= 1) {
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            // Otherwise, pop from navigation stack
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
}

@end 