#import <UIKit/UIKit.h>
#import "APIManager.h"
#import <objc/runtime.h>

@interface UIViewController (DynamicMethodAddition)
- (void)addAction:(SEL)selector withImplementation:(void (^)(id target, SEL cmd, id sender))implementation;
@end

@implementation UIViewController (DynamicMethodAddition)
- (void)addAction:(SEL)selector withImplementation:(void (^)(id target, SEL cmd, id sender))implementation {
    IMP imp = imp_implementationWithBlock(implementation);
    class_addMethod([self class], selector, imp, "v@:@");
}
@end

@interface ReplyTableViewCell : UITableViewCell <UIScrollViewDelegate>
@property (nonatomic, strong) UITextView *contentTextView;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UIImageView *attachmentImageView;
- (void)configureCellWithReply:(NSDictionary *)reply;
@end

@interface TicketDetailViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) NSNumber *ticketId;
@property (nonatomic, copy) void (^ticketUpdatedHandler)(void);

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *replyView;
@property (nonatomic, strong) UITextView *replyTextView;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *closeTicketButton;
@property (nonatomic, strong) UIButton *reopenTicketButton;
@property (nonatomic, strong) UIButton *attachmentButton;
@property (nonatomic, strong) UIImageView *attachmentPreview;
@property (nonatomic, strong) UIButton *removeAttachmentButton;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

@property (nonatomic, strong) NSDictionary *ticket;
@property (nonatomic, strong) NSArray *replies;
@property (nonatomic, strong) UIImage *imageAttachment;
@property (nonatomic, assign) BOOL isKeyboardVisible;
@property (nonatomic, assign) CGFloat keyboardHeight;

@end

@implementation TicketDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Ticket Details";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Initialize properties
    self.replies = @[];
    self.isKeyboardVisible = NO;
    self.keyboardHeight = 0;
    
    [self setupUI];
    [self loadTicketDetails];
    
    // Add keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    // Add tap gesture to dismiss keyboard
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    // Table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 100;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    
    // Set initial content inset to account for reply view
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 80, 0);
    self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 80, 0);
    
    [self.tableView registerClass:[ReplyTableViewCell class] forCellReuseIdentifier:@"ReplyCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ContentCell"];
    [self.view addSubview:self.tableView];
    
    // Setup reply view with modern design - improved to eliminate any gaps
    self.replyView = [[UIView alloc] init];
    self.replyView.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyView.backgroundColor = [UIColor systemBackgroundColor];
    self.replyView.clipsToBounds = NO; // Allow shadow to exceed bounds
    self.replyView.layer.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.15].CGColor;
    self.replyView.layer.shadowOffset = CGSizeMake(0, -2);
    self.replyView.layer.shadowRadius = 3;
    self.replyView.layer.shadowOpacity = 1.0;
    [self.view addSubview:self.replyView];
    
    // Add a separator line
    UIView *separatorLine = [[UIView alloc] init];
    separatorLine.translatesAutoresizingMaskIntoConstraints = NO;
    separatorLine.backgroundColor = [UIColor separatorColor];
    [self.replyView addSubview:separatorLine];
    
    // Create a container for the input elements with rounded corners
    UIView *inputContainer = [[UIView alloc] init];
    inputContainer.translatesAutoresizingMaskIntoConstraints = NO;
    inputContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
    inputContainer.layer.cornerRadius = 18;
    inputContainer.layer.borderWidth = 0.5;
    inputContainer.layer.borderColor = [UIColor separatorColor].CGColor;
    [self.replyView addSubview:inputContainer];
    
    // Setup reply text view
    self.replyTextView = [[UITextView alloc] init];
    self.replyTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.replyTextView.font = [UIFont systemFontOfSize:15.0];
    self.replyTextView.backgroundColor = [UIColor clearColor];
    self.replyTextView.textColor = [UIColor labelColor];
    self.replyTextView.returnKeyType = UIReturnKeyDefault;
    self.replyTextView.delegate = self;
    self.replyTextView.textContainerInset = UIEdgeInsetsMake(8, 0, 8, 0);
    [inputContainer addSubview:self.replyTextView];
    
    // Add placeholder to text view
    UILabel *placeholderLabel = [[UILabel alloc] init];
    placeholderLabel.text = @"Write a reply...";
    placeholderLabel.font = [UIFont systemFontOfSize:15.0];
    placeholderLabel.textColor = [UIColor placeholderTextColor];
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    placeholderLabel.tag = 999;
    [self.replyTextView addSubview:placeholderLabel];
    
    // Setup attachment button
    self.attachmentButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.attachmentButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *paperclipImage = [UIImage systemImageNamed:@"paperclip"];
    UIImageConfiguration *attachmentConfig = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImage *configuredAttachmentIcon = [paperclipImage imageWithConfiguration:attachmentConfig];
    [self.attachmentButton setImage:configuredAttachmentIcon forState:UIControlStateNormal];
    self.attachmentButton.tintColor = [UIColor systemBlueColor];
    [self.attachmentButton addTarget:self action:@selector(addAttachment) forControlEvents:UIControlEventTouchUpInside];
    [inputContainer addSubview:self.attachmentButton];
    
    // Setup attachment preview view (hidden by default)
    self.attachmentPreview = [[UIImageView alloc] init];
    self.attachmentPreview.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentPreview.contentMode = UIViewContentModeScaleAspectFill;
    self.attachmentPreview.clipsToBounds = YES;
    self.attachmentPreview.layer.cornerRadius = 10.0;
    self.attachmentPreview.layer.borderWidth = 1.0;
    self.attachmentPreview.layer.borderColor = [UIColor separatorColor].CGColor;
    self.attachmentPreview.hidden = YES;
    [self.replyView addSubview:self.attachmentPreview];
    
    // Setup remove attachment button (hidden by default)
    self.removeAttachmentButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.removeAttachmentButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *removeImage = [UIImage systemImageNamed:@"xmark.circle.fill"];
    UIImageConfiguration *removeConfig = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium];
    UIImage *configuredRemoveIcon = [removeImage imageWithConfiguration:removeConfig];
    [self.removeAttachmentButton setImage:configuredRemoveIcon forState:UIControlStateNormal];
    self.removeAttachmentButton.tintColor = [UIColor systemRedColor];
    [self.removeAttachmentButton addTarget:self action:@selector(removeAttachment) forControlEvents:UIControlEventTouchUpInside];
    self.removeAttachmentButton.hidden = YES;
    [self.replyView addSubview:self.removeAttachmentButton];
    
    // Setup send button
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *sendImage = [UIImage systemImageNamed:@"paperplane.fill"];
    UIImageConfiguration *sendConfig = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    UIImage *configuredSendIcon = [sendImage imageWithConfiguration:sendConfig];
    [self.sendButton setImage:configuredSendIcon forState:UIControlStateNormal];
    self.sendButton.tintColor = [UIColor systemBlueColor];
    [self.sendButton addTarget:self action:@selector(sendReply) forControlEvents:UIControlEventTouchUpInside];
    [inputContainer addSubview:self.sendButton];
    
    // Loading indicator
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];
    
    // Setup layout constraints - updated replyView constraint to bottom of view (not safe area)
    NSLayoutConstraint *replyViewHeightConstraint = [self.replyView.heightAnchor constraintEqualToConstant:80];
    
    [NSLayoutConstraint activateConstraints:@[
        // Table view
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.replyView.topAnchor],
        
        // Reply view - now constrained to bottom of view, not safe area
        [self.replyView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.replyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.replyView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], // Changed from safeAreaLayoutGuide.bottomAnchor
        replyViewHeightConstraint,
        
        // Separator line
        [separatorLine.topAnchor constraintEqualToAnchor:self.replyView.topAnchor],
        [separatorLine.leadingAnchor constraintEqualToAnchor:self.replyView.leadingAnchor],
        [separatorLine.trailingAnchor constraintEqualToAnchor:self.replyView.trailingAnchor],
        [separatorLine.heightAnchor constraintEqualToConstant:0.5],
        
        // Input container
        [inputContainer.leadingAnchor constraintEqualToAnchor:self.replyView.leadingAnchor constant:10],
        [inputContainer.trailingAnchor constraintEqualToAnchor:self.replyView.trailingAnchor constant:-10],
        [inputContainer.topAnchor constraintEqualToAnchor:self.replyView.topAnchor constant:12],
        [inputContainer.bottomAnchor constraintEqualToAnchor:self.replyView.bottomAnchor constant:-12],
        
        // Attachment button
        [self.attachmentButton.leadingAnchor constraintEqualToAnchor:inputContainer.leadingAnchor constant:8],
        [self.attachmentButton.centerYAnchor constraintEqualToAnchor:inputContainer.centerYAnchor],
        [self.attachmentButton.widthAnchor constraintEqualToConstant:36],
        [self.attachmentButton.heightAnchor constraintEqualToConstant:36],
        
        // Reply text view
        [self.replyTextView.topAnchor constraintEqualToAnchor:inputContainer.topAnchor constant:4],
        [self.replyTextView.leadingAnchor constraintEqualToAnchor:self.attachmentButton.trailingAnchor constant:4],
        [self.replyTextView.bottomAnchor constraintEqualToAnchor:inputContainer.bottomAnchor constant:-4],
        [self.replyTextView.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-4],
        
        // Placeholder
        [placeholderLabel.leadingAnchor constraintEqualToAnchor:self.replyTextView.leadingAnchor constant:4],
        [placeholderLabel.topAnchor constraintEqualToAnchor:self.replyTextView.topAnchor constant:8],
        
        // Send button
        [self.sendButton.trailingAnchor constraintEqualToAnchor:inputContainer.trailingAnchor constant:-8],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:inputContainer.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:36],
        [self.sendButton.heightAnchor constraintEqualToConstant:36],
        
        // Loading indicator
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        
        // Attachment preview
        [self.attachmentPreview.topAnchor constraintEqualToAnchor:self.replyView.topAnchor constant:10],
        [self.attachmentPreview.leadingAnchor constraintEqualToAnchor:self.replyView.leadingAnchor constant:10],
        [self.attachmentPreview.widthAnchor constraintEqualToConstant:60],
        [self.attachmentPreview.heightAnchor constraintEqualToConstant:60],
        
        // Remove attachment button
        [self.removeAttachmentButton.topAnchor constraintEqualToAnchor:self.attachmentPreview.topAnchor constant:-10],
        [self.removeAttachmentButton.leadingAnchor constraintEqualToAnchor:self.attachmentPreview.trailingAnchor constant:-10],
        [self.removeAttachmentButton.widthAnchor constraintEqualToConstant:24],
        [self.removeAttachmentButton.heightAnchor constraintEqualToConstant:24]
    ]];
}

#pragma mark - API calls

- (void)loadTicketDetails {
    [self.loadingIndicator startAnimating];
    
    [[APIManager sharedManager] getTicketDetails:self.ticketId completion:^(NSDictionary *ticket, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:@"Failed to load ticket details. Please try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            self.ticket = ticket;
            self.replies = ticket[@"replies"] ?: @[];
            
            // Update navigation bar title
            self.title = [NSString stringWithFormat:@"Ticket #%@", self.ticketId];
            
            // Check if ticket is closed
            BOOL isClosed = [ticket[@"is_closed"] boolValue];
            
            // Remove any existing right bar button item
            self.navigationItem.rightBarButtonItem = nil;
            
            if (isClosed) {
                // Add reopen button if ticket is closed
                UIBarButtonItem *reopenButton = [[UIBarButtonItem alloc] initWithTitle:@"Reopen" 
                                                                                 style:UIBarButtonItemStylePlain 
                                                                                target:self 
                                                                                action:@selector(reopenTicket)];
                self.navigationItem.rightBarButtonItem = reopenButton;
                
                // Hide reply view for closed tickets
                self.replyView.hidden = YES;
                
                // Update table view bottom constraint
                for (NSLayoutConstraint *constraint in self.view.constraints) {
                    if (constraint.firstItem == self.tableView && constraint.firstAttribute == NSLayoutAttributeBottom) {
                        constraint.constant = 0;
                        break;
                    }
                }
            } else {
                // Add close button if ticket is open
                UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithTitle:@"Close" 
                                                                                style:UIBarButtonItemStylePlain 
                                                                               target:self 
                                                                               action:@selector(closeTicket)];
                self.navigationItem.rightBarButtonItem = closeButton;
                
                // Show reply view for open tickets
                self.replyView.hidden = NO;
                
                // Update table view bottom constraint to make room for reply view
                for (NSLayoutConstraint *constraint in self.view.constraints) {
                    if (constraint.firstItem == self.tableView && constraint.firstAttribute == NSLayoutAttributeBottom) {
                        constraint.constant = 80; // Adjust this value based on your reply view height
                        break;
                    }
                }
            }
            
            [self.tableView reloadData];
            
            // Scroll to bottom
            if (self.replies.count > 0) {
                [self scrollToBottomAnimated:NO];
            }
        });
    }];
}

- (void)sendReply {
    // Validate input
    if (self.replyTextView.text.length == 0 || [self.replyTextView.text isEqualToString:@"Write a reply..."]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:@"Please enter a reply."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // Disable send button and attachment button
    self.sendButton.enabled = NO;
    self.attachmentButton.enabled = NO;
    
    // Clear text view
    NSString *replyContent = self.replyTextView.text;
    self.replyTextView.text = @"";
    UILabel *placeholderLabel = [self.replyTextView viewWithTag:999];
    placeholderLabel.hidden = NO;
    
    // Dismiss keyboard
    [self dismissKeyboard];
    
    // Show loading
    [self.loadingIndicator startAnimating];
    
    // Send reply with optional attachment
    [[APIManager sharedManager] replyToTicket:self.ticketId content:replyContent attachment:self.imageAttachment completion:^(BOOL success, NSString *message, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            self.sendButton.enabled = YES;
            self.attachmentButton.enabled = YES;
            
            if (error || !success) {
                NSString *errorMessage = message ?: @"Failed to send reply. Please try again.";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:errorMessage
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
                // Restore reply text and attachment
                self.replyTextView.text = replyContent;
                placeholderLabel.hidden = YES;
                return;
            }
            
            // Clear attachment if successful
            [self removeAttachment];
            
            // Reload ticket details
            [self loadTicketDetails];
        });
    }];
}

- (void)reopenTicket {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reopen Ticket"
                                                                   message:@"Are you sure you want to reopen this ticket?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reopen" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.loadingIndicator startAnimating];
        
        [[APIManager sharedManager] reopenTicket:self.ticketId completion:^(BOOL success, NSString *message, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                
                if (error || !success) {
                    NSString *errorMessage = message ?: @"Failed to reopen ticket. Please try again.";
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                   message:errorMessage
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                    return;
                }
                
                // Reload ticket details and notify parent view
                [self loadTicketDetails];
                
                if (self.ticketUpdatedHandler) {
                    self.ticketUpdatedHandler();
                }
            });
        }];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeTicket {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Close Ticket"
                                                                   message:@"Are you sure you want to close this ticket?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self.loadingIndicator startAnimating];
        
        [[APIManager sharedManager] closeTicket:self.ticketId completion:^(BOOL success, NSString *message, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                
                if (error || !success) {
                    NSString *errorMessage = message ?: @"Failed to close ticket. Please try again.";
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                   message:errorMessage
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                    return;
                }
                
                // Reload ticket details and notify parent view
                [self loadTicketDetails];
                
                if (self.ticketUpdatedHandler) {
                    self.ticketUpdatedHandler();
                }
            });
        }];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// Methods for handling image attachments
- (void)addAttachment {
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePicker.allowsEditing = YES;
    [self presentViewController:imagePicker animated:YES completion:nil];
}

- (void)removeAttachment {
    self.imageAttachment = nil;
    self.attachmentPreview.hidden = YES;
    self.removeAttachmentButton.hidden = YES;
    
    // Adjust constraints to remove space for attachment preview
    // ...
}

#pragma mark - UIImagePickerControllerDelegate Methods

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    UIImage *selectedImage = info[UIImagePickerControllerEditedImage];
    if (!selectedImage) {
        selectedImage = info[UIImagePickerControllerOriginalImage];
    }
    
    if (selectedImage) {
        // Resize and compress image if needed (max 2MB)
        UIImage *processedImage = [self resizeImage:selectedImage toMaxFileSize:2 * 1024 * 1024];
        
        self.imageAttachment = processedImage;
        self.attachmentPreview.image = processedImage;
        self.attachmentPreview.hidden = NO;
        self.removeAttachmentButton.hidden = NO;
        
        // Adjust constraints to make space for attachment preview
        // ...
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (UIImage *)resizeImage:(UIImage *)image toMaxFileSize:(NSUInteger)maxFileSize {
    // Check if image has an alpha channel (transparency)
    BOOL hasAlpha = NO;
    if (image.CGImage) {
        CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(image.CGImage);
        hasAlpha = (alphaInfo == kCGImageAlphaFirst || 
                   alphaInfo == kCGImageAlphaLast || 
                   alphaInfo == kCGImageAlphaPremultipliedFirst || 
                   alphaInfo == kCGImageAlphaPremultipliedLast);
    }
    
    // Start with high quality compression
    CGFloat compression = 0.9;
    CGFloat maxCompression = 0.1;
    NSData *imageData;
    
    if (hasAlpha) {
        // Use PNG for images with transparency
        imageData = UIImagePNGRepresentation(image);
        
        // If PNG is too large, we need to resize the image dimensions
        if (imageData.length > maxFileSize) {
            UIImage *resizedImage = image;
            CGFloat scaleFactor = 0.9; // Start with 90% of original size
            
            while (imageData.length > maxFileSize && scaleFactor > 0.1) {
                CGFloat width = image.size.width * scaleFactor;
                CGFloat height = image.size.height * scaleFactor;
                
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, image.scale);
                [image drawInRect:CGRectMake(0, 0, width, height)];
                resizedImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                
                imageData = UIImagePNGRepresentation(resizedImage);
                scaleFactor -= 0.1;
            }
            
            return resizedImage;
        }
    } else {
        // Use JPEG for photos and images without transparency
        imageData = UIImageJPEGRepresentation(image, compression);
    
    // Reduce image size if needed
    UIImage *resizedImage = image;
    if (imageData.length > maxFileSize) {
        CGFloat width = image.size.width;
        CGFloat height = image.size.height;
        
        // Reduce size by 50% and check again
        CGFloat targetWidth = width * 0.5;
        CGFloat targetHeight = height * 0.5;
        
        UIGraphicsBeginImageContext(CGSizeMake(targetWidth, targetHeight));
        [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
        resizedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        imageData = UIImageJPEGRepresentation(resizedImage, compression);
    }
    
    // Further compress if still too large
    while (imageData.length > maxFileSize && compression > maxCompression) {
        compression -= 0.1;
        imageData = UIImageJPEGRepresentation(resizedImage, compression);
    }
    
    return resizedImage;
    }
    
    return image;
}

#pragma mark - Helper methods

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    NSInteger sections = [self.tableView numberOfSections];
    if (sections > 0) {
        NSInteger rows = [self.tableView numberOfRowsInSection:sections - 1];
        if (rows > 0) {
            NSIndexPath *lastRow = [NSIndexPath indexPathForRow:rows - 1 inSection:sections - 1];
            
            // Ensure the last row is fully visible above the keyboard and reply bar
            [self.tableView scrollToRowAtIndexPath:lastRow atScrollPosition:UITableViewScrollPositionBottom animated:animated];
            
            // Add a small delay to ensure the scroll completes properly
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Get the rect of the cell in the table view
                CGRect cellRect = [self.tableView rectForRowAtIndexPath:lastRow];
                // Convert to view coordinates
                CGRect cellRectInView = [self.tableView convertRect:cellRect toView:self.view];
                
                // If cell is partially hidden by the reply bar or keyboard, adjust scroll position
                CGFloat replyViewTopY = self.view.bounds.size.height - self.keyboardHeight - self.replyView.bounds.size.height;
                if (CGRectGetMaxY(cellRectInView) > replyViewTopY) {
                    CGFloat additionalOffset = CGRectGetMaxY(cellRectInView) - replyViewTopY + 10; // 10pt extra padding
                    CGPoint contentOffset = self.tableView.contentOffset;
                    contentOffset.y += additionalOffset;
                    [self.tableView setContentOffset:contentOffset animated:YES];
                }
            });
        }
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Adjust the reply view position for the safe area when keyboard is not showing
    if (!self.isKeyboardVisible) {
        for (NSLayoutConstraint *constraint in self.view.constraints) {
            if (constraint.firstItem == self.replyView && constraint.firstAttribute == NSLayoutAttributeBottom) {
                // Use the safe area inset to position the reply view properly
                constraint.constant = -self.view.safeAreaInsets.bottom;
                break;
            }
        }
    }
    
    // Set initial content inset to account for reply view even when keyboard is not showing
    UIEdgeInsets contentInset = self.tableView.contentInset;
    
    if (self.isKeyboardVisible) {
        contentInset.bottom = self.replyView.bounds.size.height + self.keyboardHeight;
    } else {
        // Account for safe area when setting content inset
        contentInset.bottom = self.replyView.bounds.size.height + self.view.safeAreaInsets.bottom;
    }
    
    self.tableView.contentInset = contentInset;
    self.tableView.scrollIndicatorInsets = contentInset;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // After the view appears, scroll to bottom to ensure the latest messages are visible
    [self scrollToBottomAnimated:NO];
}

#pragma mark - UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Original ticket content + all replies
    return 1 + self.replies.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 0) {
        // Content cell for original ticket
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ContentCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        // Clear any existing subviews
        for (UIView *subview in cell.contentView.subviews) {
            [subview removeFromSuperview];
        }
        
        // Create modern header view
        UIView *headerView = [[UIView alloc] init];
        headerView.translatesAutoresizingMaskIntoConstraints = NO;
        headerView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        headerView.layer.cornerRadius = 12;
        [cell.contentView addSubview:headerView];
        
        // Add shadow to header view for depth
        headerView.layer.shadowColor = [UIColor blackColor].CGColor;
        headerView.layer.shadowOffset = CGSizeMake(0, 2);
        headerView.layer.shadowRadius = 4;
        headerView.layer.shadowOpacity = 0.1;
        
        // Subject label with larger font size
        UILabel *subjectLabel = [[UILabel alloc] init];
        subjectLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subjectLabel.text = self.ticket[@"subject"] ?: @"No Subject";
        subjectLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        subjectLabel.textColor = [UIColor labelColor];
        subjectLabel.numberOfLines = 0;
        [headerView addSubview:subjectLabel];
        
        // Status badge with modern style
        UIView *statusBadge = [[UIView alloc] init];
        statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
        statusBadge.layer.cornerRadius = 14;
        
        // Set badge color based on status
        NSString *status = self.ticket[@"status"];
        if ([status isEqualToString:@"open"]) {
            statusBadge.backgroundColor = [UIColor systemGreenColor];
        } else if ([status isEqualToString:@"in_progress"]) {
            statusBadge.backgroundColor = [UIColor systemBlueColor];
        } else if ([status isEqualToString:@"closed"]) {
            statusBadge.backgroundColor = [UIColor systemRedColor];
        } else if ([status isEqualToString:@"resolved"]) {
            statusBadge.backgroundColor = [UIColor systemPurpleColor];
        } else {
            statusBadge.backgroundColor = [UIColor systemGrayColor];
        }
        [headerView addSubview:statusBadge];
        
        // Status label
        UILabel *statusLabel = [[UILabel alloc] init];
        statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        statusLabel.text = [status capitalizedString];
        statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        statusLabel.textColor = [UIColor whiteColor];
        [statusBadge addSubview:statusLabel];
        
        // Divider
        UIView *divider = [[UIView alloc] init];
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        divider.backgroundColor = [UIColor separatorColor];
        [headerView addSubview:divider];
        
        // Category container
        UIView *categoryContainer = [[UIView alloc] init];
        categoryContainer.translatesAutoresizingMaskIntoConstraints = NO;
        categoryContainer.backgroundColor = [UIColor tertiarySystemBackgroundColor];
        categoryContainer.layer.cornerRadius = 8;
        [headerView addSubview:categoryContainer];
        
        // Category label title
        UILabel *categoryTitle = [[UILabel alloc] init];
        categoryTitle.translatesAutoresizingMaskIntoConstraints = NO;
        categoryTitle.text = @"Category:";
        categoryTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        categoryTitle.textColor = [UIColor secondaryLabelColor];
        [categoryContainer addSubview:categoryTitle];
        
        // Category label value
        UILabel *categoryLabel = [[UILabel alloc] init];
        categoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Extract category value from ticket dictionary
        NSString *categoryName = [self.ticket[@"category"] isKindOfClass:[NSDictionary class]] ? 
                              self.ticket[@"category"][@"name"] : 
                              ([self.ticket[@"category"] isKindOfClass:[NSString class]] ? self.ticket[@"category"] : @"None");
        categoryLabel.text = categoryName;
        categoryLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        categoryLabel.textColor = [UIColor labelColor];
        [categoryContainer addSubview:categoryLabel];
        
        // Subcategory label - new addition
        UILabel *subcategoryTitle = [[UILabel alloc] init];
        subcategoryTitle.translatesAutoresizingMaskIntoConstraints = NO;
        subcategoryTitle.text = @"Subcategory:";
        subcategoryTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        subcategoryTitle.textColor = [UIColor secondaryLabelColor];
        [categoryContainer addSubview:subcategoryTitle];
        
        UILabel *subcategoryLabel = [[UILabel alloc] init];
        subcategoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Extract subcategory value from the ticket dictionary
        NSString *subcategoryName = @"None";
        if ([self.ticket[@"subcategory"] isKindOfClass:[NSDictionary class]]) {
            subcategoryName = self.ticket[@"subcategory"][@"name"] ?: @"None";
        } else if ([self.ticket[@"subcategory_id"] isKindOfClass:[NSNumber class]] && [self.ticket[@"subcategory_id"] intValue] > 0) {
            subcategoryName = @"Available"; // Fallback if we only have ID but not the name
        }
        
        subcategoryLabel.text = subcategoryName;
        subcategoryLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        subcategoryLabel.textColor = [UIColor labelColor];
        [categoryContainer addSubview:subcategoryLabel];
        
        // Date label with improved formatting
        UILabel *dateLabel = [[UILabel alloc] init];
        dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Format date
        NSString *createdAtString = self.ticket[@"created_at"];
        NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
        [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        NSDate *createdDate = [inputFormatter dateFromString:createdAtString];
        
        NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
        [outputFormatter setDateStyle:NSDateFormatterMediumStyle];
        [outputFormatter setTimeStyle:NSDateFormatterShortStyle];
        
        if (createdDate) {
            dateLabel.text = [outputFormatter stringFromDate:createdDate];
        } else {
            dateLabel.text = @"";
        }
        
        dateLabel.font = [UIFont systemFontOfSize:14];
        dateLabel.textColor = [UIColor systemGrayColor];
        [headerView addSubview:dateLabel];
        
        // Description label title
        UILabel *descriptionTitle = [[UILabel alloc] init];
        descriptionTitle.translatesAutoresizingMaskIntoConstraints = NO;
        descriptionTitle.text = @"Description";
        descriptionTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        descriptionTitle.textColor = [UIColor labelColor];
        [headerView addSubview:descriptionTitle];
        
        // Content container - styled container for the ticket content
        UIView *contentContainer = [[UIView alloc] init];
        contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
        contentContainer.backgroundColor = [UIColor tertiarySystemBackgroundColor];
        contentContainer.layer.cornerRadius = 8;
        [cell.contentView addSubview:contentContainer];
        
        // Content label - the ticket description
        UILabel *contentLabel = [[UILabel alloc] init];
        contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
        contentLabel.text = self.ticket[@"content"];
        contentLabel.font = [UIFont systemFontOfSize:16];
        contentLabel.textColor = [UIColor labelColor];
        contentLabel.numberOfLines = 0;
        [contentContainer addSubview:contentLabel];
        
        // Check for attachments in the original ticket
        NSArray *attachments = self.ticket[@"attachments"];
        BOOL hasAttachments = (attachments && [attachments isKindOfClass:[NSArray class]] && attachments.count > 0);
        
        // Add attachments as small thumbnails under the content
        if (hasAttachments) {
            // Attachments label title
            UILabel *attachmentsTitle = [[UILabel alloc] init];
            attachmentsTitle.translatesAutoresizingMaskIntoConstraints = NO;
            attachmentsTitle.text = @"Attachments";
            attachmentsTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            attachmentsTitle.textColor = [UIColor secondaryLabelColor];
            [contentContainer addSubview:attachmentsTitle];
            
            // Horizontal stack view for thumbnails
            UIStackView *thumbnailsStackView = [[UIStackView alloc] init];
            thumbnailsStackView.translatesAutoresizingMaskIntoConstraints = NO;
            thumbnailsStackView.axis = UILayoutConstraintAxisHorizontal;
            thumbnailsStackView.spacing = 8;
            thumbnailsStackView.alignment = UIStackViewAlignmentCenter;
            thumbnailsStackView.distribution = UIStackViewDistributionFillEqually;
            [contentContainer addSubview:thumbnailsStackView];
            
            // Set constraints for the attachments title and stack view
            [NSLayoutConstraint activateConstraints:@[
                [attachmentsTitle.topAnchor constraintEqualToAnchor:contentLabel.bottomAnchor constant:12],
                [attachmentsTitle.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:12],
                [attachmentsTitle.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-12],
                
                [thumbnailsStackView.topAnchor constraintEqualToAnchor:attachmentsTitle.bottomAnchor constant:8],
                [thumbnailsStackView.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:12],
                [thumbnailsStackView.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-12],
                [thumbnailsStackView.bottomAnchor constraintEqualToAnchor:contentContainer.bottomAnchor constant:-12],
                [thumbnailsStackView.heightAnchor constraintEqualToConstant:60]
            ]];
            
            // Add thumbnail image views
            for (NSInteger i = 0; i < MIN(attachments.count, 3); i++) { // Limit to 3 attachments
                NSDictionary *attachment = attachments[i];
                NSString *fileUrl = attachment[@"file_url"];
                
                if (!fileUrl) {
                    // Try alternative keys that might be used
                    fileUrl = attachment[@"url"];
                    if (!fileUrl) {
                        // One more fallback
                        NSString *filePath = attachment[@"file_path"];
                        if (filePath) {
                            // Use dynamic URL construction based on API base URL instead of hardcoded domain
                            NSString *baseURL = [[APIManager sharedManager] baseURL] ?: @"https://hydra.weaponx.us";
                            
                            // Ensure proper formatting of path and URL construction
                            if ([filePath hasPrefix:@"storage/"]) {
                                // If path starts with storage/, ensure we point to the public directory
                                fileUrl = [NSString stringWithFormat:@"%@/%@", baseURL, filePath];
                            } else if ([filePath hasPrefix:@"/storage/"]) {
                                // If path starts with /storage/, ensure we don't double slash
                                fileUrl = [NSString stringWithFormat:@"%@%@", baseURL, filePath];
                            } else {
                                // Otherwise, assume it's a path that needs to go into storage
                                fileUrl = [NSString stringWithFormat:@"%@/storage/%@", baseURL, filePath];
                            }
                        }
                    }
                }
                
                if (fileUrl) {
                    // Create thumbnail container
                    UIView *thumbnailContainer = [[UIView alloc] init];
                    thumbnailContainer.translatesAutoresizingMaskIntoConstraints = NO;
                    thumbnailContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
                    thumbnailContainer.layer.cornerRadius = 6;
                    thumbnailContainer.clipsToBounds = YES;
                    thumbnailContainer.layer.borderWidth = 1;
                    thumbnailContainer.layer.borderColor = [UIColor separatorColor].CGColor;
                    [thumbnailsStackView addSubview:thumbnailContainer];
                    
                    // Set fixed height and width for thumbnail container
                    [NSLayoutConstraint activateConstraints:@[
                        [thumbnailContainer.heightAnchor constraintEqualToConstant:50],
                        [thumbnailContainer.widthAnchor constraintEqualToConstant:50]
                    ]];
                    
                    // Create image view
                    UIImageView *imageView = [[UIImageView alloc] init];
                    imageView.translatesAutoresizingMaskIntoConstraints = NO;
                    imageView.contentMode = UIViewContentModeScaleAspectFill;
                    imageView.clipsToBounds = YES;
                    imageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
                    imageView.tag = i + 5000; // Use a different tag range
                    [thumbnailContainer addSubview:imageView];
                    
                    // Add constraints for image view
                    [NSLayoutConstraint activateConstraints:@[
                        [imageView.topAnchor constraintEqualToAnchor:thumbnailContainer.topAnchor],
                        [imageView.leadingAnchor constraintEqualToAnchor:thumbnailContainer.leadingAnchor],
                        [imageView.trailingAnchor constraintEqualToAnchor:thumbnailContainer.trailingAnchor],
                        [imageView.bottomAnchor constraintEqualToAnchor:thumbnailContainer.bottomAnchor]
                    ]];
                    
                    // Add a loading indicator
                    UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                    loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
                    loadingIndicator.tag = i + 6000;
                    [loadingIndicator startAnimating];
                    [thumbnailContainer addSubview:loadingIndicator];
                    
                    [NSLayoutConstraint activateConstraints:@[
                        [loadingIndicator.centerXAnchor constraintEqualToAnchor:thumbnailContainer.centerXAnchor],
                        [loadingIndicator.centerYAnchor constraintEqualToAnchor:thumbnailContainer.centerYAnchor]
                    ]];
                    
                    // Add the thumbnail container to the stack view
                    [thumbnailsStackView addArrangedSubview:thumbnailContainer];
                    
                    // Load image asynchronously
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        NSData *imageData = nil;
                        
                        // Try to download the image
                        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:fileUrl]];
                        NSURLSession *session = [NSURLSession sharedSession];
                        
                        __block NSData *downloadedData = nil;
                        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                        
                        NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *downloadError) {
                            if (!downloadError && data) {
                                downloadedData = data;
                            }
                            dispatch_semaphore_signal(semaphore);
                        }];
                        [dataTask resume];
                        
                        // Wait for the download to complete (with a timeout)
                        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
                        
                        imageData = downloadedData;
                        
                        // If we have image data, try to create an image
                        UIImage *image = nil;
                        if (imageData) {
                            image = [UIImage imageWithData:imageData];
                        }
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // Remove the loading indicator
                            UIActivityIndicatorView *indicator = [thumbnailsStackView viewWithTag:i + 6000];
                            [indicator stopAnimating];
                            [indicator removeFromSuperview];
                            
                            // Update the image
                            UIImageView *imgView = [thumbnailsStackView viewWithTag:i + 5000];
                            if (imgView && image) {
                                imgView.image = image;
                                
                                // Add tap gesture to view full image
                                imgView.userInteractionEnabled = YES;
                                UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleOriginalAttachmentTap:)];
                                [imgView addGestureRecognizer:tapGesture];
                                // Store the image URL for later use
                                objc_setAssociatedObject(imgView, "imageURL", fileUrl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            }
                        });
                    });
                }
            }
        } else {
            // If no attachments, just add appropriate bottom constraint to content label
            [NSLayoutConstraint activateConstraints:@[
                [contentLabel.bottomAnchor constraintEqualToAnchor:contentContainer.bottomAnchor constant:-12]
            ]];
        }
        
        // Don't create a separate attachments container anymore - thumbnails are in content container
        
        // Update constraints for the various views
        [NSLayoutConstraint activateConstraints:@[
            // Header view
            [headerView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:15],
            [headerView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:15],
            [headerView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
            
            // Subject label
            [subjectLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor constant:15],
            [subjectLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:15],
            [subjectLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-15],
            
            // Status badge
            [statusBadge.topAnchor constraintEqualToAnchor:subjectLabel.bottomAnchor constant:10],
            [statusBadge.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:15],
            [statusBadge.heightAnchor constraintEqualToConstant:28],
            
            // Status label
            [statusLabel.topAnchor constraintEqualToAnchor:statusBadge.topAnchor constant:4],
            [statusLabel.leadingAnchor constraintEqualToAnchor:statusBadge.leadingAnchor constant:8],
            [statusLabel.trailingAnchor constraintEqualToAnchor:statusBadge.trailingAnchor constant:-8],
            [statusLabel.bottomAnchor constraintEqualToAnchor:statusBadge.bottomAnchor constant:-4],
            
            // Date label
            [dateLabel.centerYAnchor constraintEqualToAnchor:statusBadge.centerYAnchor],
            [dateLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-15],
            
            // Divider
            [divider.topAnchor constraintEqualToAnchor:statusBadge.bottomAnchor constant:15],
            [divider.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:15],
            [divider.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-15],
            [divider.heightAnchor constraintEqualToConstant:1],
            
            // Category container
            [categoryContainer.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:15],
            [categoryContainer.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:15],
            [categoryContainer.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-15],
            
            // Category title
            [categoryTitle.topAnchor constraintEqualToAnchor:categoryContainer.topAnchor constant:12],
            [categoryTitle.leadingAnchor constraintEqualToAnchor:categoryContainer.leadingAnchor constant:12],
            
            // Category label
            [categoryLabel.topAnchor constraintEqualToAnchor:categoryTitle.topAnchor],
            [categoryLabel.leadingAnchor constraintEqualToAnchor:categoryTitle.trailingAnchor constant:8],
            [categoryLabel.trailingAnchor constraintEqualToAnchor:categoryContainer.trailingAnchor constant:-12],
            
            // Subcategory title
            [subcategoryTitle.topAnchor constraintEqualToAnchor:categoryTitle.bottomAnchor constant:12],
            [subcategoryTitle.leadingAnchor constraintEqualToAnchor:categoryContainer.leadingAnchor constant:12],
            [subcategoryTitle.bottomAnchor constraintEqualToAnchor:categoryContainer.bottomAnchor constant:-12],
            
            // Subcategory label
            [subcategoryLabel.topAnchor constraintEqualToAnchor:subcategoryTitle.topAnchor],
            [subcategoryLabel.leadingAnchor constraintEqualToAnchor:subcategoryTitle.trailingAnchor constant:8],
            [subcategoryLabel.trailingAnchor constraintEqualToAnchor:categoryContainer.trailingAnchor constant:-12],
            
            // Description title
            [descriptionTitle.topAnchor constraintEqualToAnchor:categoryContainer.bottomAnchor constant:15],
            [descriptionTitle.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:15],
            [descriptionTitle.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-15],
            [descriptionTitle.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-15],
            
            // Content container
            [contentContainer.topAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:10],
            [contentContainer.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:15],
            [contentContainer.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-15],
            [contentContainer.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-15],
            
            // Content label
            [contentLabel.topAnchor constraintEqualToAnchor:contentContainer.topAnchor constant:12],
            [contentLabel.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:12],
            [contentLabel.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-12]
        ]];
        
        return cell;
    } else {
        // Reply cell
        ReplyTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ReplyCell" forIndexPath:indexPath];
        
        NSDictionary *reply = self.replies[indexPath.row - 1]; // -1 because row 0 is the original post
        [cell configureCellWithReply:reply];
        
        return cell;
    }
}

#pragma mark - UITextViewDelegate methods

- (void)textViewDidBeginEditing:(UITextView *)textView {
    UILabel *placeholderLabel = [textView viewWithTag:999];
    placeholderLabel.hidden = YES;
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    UILabel *placeholderLabel = [textView viewWithTag:999];
    placeholderLabel.hidden = textView.text.length > 0;
}

- (void)textViewDidChange:(UITextView *)textView {
    // Show/hide placeholder
    UILabel *placeholderLabel = [textView viewWithTag:999];
    placeholderLabel.hidden = textView.text.length > 0;
    
    // Calculate optimal height based on content
    CGFloat maxHeight = 120; // Maximum height for text view
    CGSize contentSize = [textView sizeThatFits:CGSizeMake(textView.frame.size.width, MAXFLOAT)];
    CGFloat newHeight = MIN(contentSize.height, maxHeight);
    
    // Ensure minimum height of 36
    newHeight = MAX(newHeight, 36);
    
    // Calculate reply view height
    CGFloat replyViewHeight = newHeight + 24; // Add padding
    
    // Update reply view height constraint
    for (NSLayoutConstraint *constraint in self.view.constraints) {
        if (constraint.firstItem == self.replyView && constraint.firstAttribute == NSLayoutAttributeHeight) {
            if (constraint.constant != replyViewHeight) {
            constraint.constant = replyViewHeight;
                
                // If keyboard is showing, adjust bottom constraint to maintain no gap
                if (self.isKeyboardVisible) {
                    for (NSLayoutConstraint *bottomConstraint in self.view.constraints) {
                        if (bottomConstraint.firstItem == self.replyView && 
                            bottomConstraint.firstAttribute == NSLayoutAttributeBottom) {
                            bottomConstraint.constant = -self.keyboardHeight;
            break;
                        }
                    }
                }
                
                // Update table view content inset to account for new reply view height
                UIEdgeInsets contentInset = self.tableView.contentInset;
                contentInset.bottom = replyViewHeight + (self.isKeyboardVisible ? self.keyboardHeight : 0);
                self.tableView.contentInset = contentInset;
                self.tableView.scrollIndicatorInsets = contentInset;
                
                [UIView animateWithDuration:0.2 animations:^{
    [self.view layoutIfNeeded];
                }];
            }
            break;
        }
    }
    
    // Scroll to bottom to keep newest messages visible
    if (self.isKeyboardVisible) {
        [self scrollToBottomAnimated:YES];
    }
}

#pragma mark - Keyboard handling

- (void)keyboardWillShow:(NSNotification *)notification {
    self.isKeyboardVisible = YES;
    
    NSDictionary *keyboardInfo = [notification userInfo];
    CGRect keyboardFrame = [[keyboardInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval animationDuration = [[keyboardInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    // Calculate keyboard height - simplest approach that works on all iOS versions
    self.keyboardHeight = keyboardFrame.size.height;
    
    // Use basic animation method compatible with all iOS versions
    [UIView animateWithDuration:animationDuration animations:^{
        // Update reply view bottom constraint to exactly match keyboard with absolutely no gap
        for (NSLayoutConstraint *constraint in self.view.constraints) {
            if (constraint.firstItem == self.replyView && constraint.firstAttribute == NSLayoutAttributeBottom) {
                constraint.constant = -self.keyboardHeight;
                break;
            }
        }
        
        // Adjust table view content inset to ensure content isn't hidden behind keyboard and reply view
        CGFloat replyViewHeight = self.replyView.bounds.size.height;
        UIEdgeInsets contentInset = self.tableView.contentInset;
        contentInset.bottom = replyViewHeight + self.keyboardHeight;
        self.tableView.contentInset = contentInset;
        self.tableView.scrollIndicatorInsets = contentInset;
        
        [self.view layoutIfNeeded];
    }];
    
    // Scroll to bottom for better UX - slight delay ensures layout completes
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self scrollToBottomAnimated:YES];
    });
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.isKeyboardVisible = NO;
    
    NSDictionary *keyboardInfo = [notification userInfo];
    NSTimeInterval animationDuration = [[keyboardInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    [UIView animateWithDuration:animationDuration animations:^{
        // Update reply view bottom constraint to account for safe area when keyboard hides
        for (NSLayoutConstraint *constraint in self.view.constraints) {
            if (constraint.firstItem == self.replyView && constraint.firstAttribute == NSLayoutAttributeBottom) {
                constraint.constant = -self.view.safeAreaInsets.bottom;
                break;
            }
        }
        
        // Reset table view content inset when keyboard hides
        UIEdgeInsets contentInset = self.tableView.contentInset;
        contentInset.bottom = self.replyView.bounds.size.height + self.view.safeAreaInsets.bottom;
        self.tableView.contentInset = contentInset;
        self.tableView.scrollIndicatorInsets = contentInset;
        
        [self.view layoutIfNeeded];
    }];
}

- (NSString *)capitalizedStatus:(NSString *)status {
    if ([status isEqualToString:@"in_progress"]) {
        return @"In Progress";
    }
    return [status capitalizedString];
}

#pragma mark - Attachment handling methods

- (void)attachmentTapped:(UITapGestureRecognizer *)gesture {
    // Get the tapped view
    UIView *tappedView = gesture.view;
    
    // Find the image view inside the tapped container
    UIImageView *imageView = nil;
    for (UIView *subview in tappedView.subviews) {
        if ([subview isKindOfClass:[UIImageView class]]) {
            imageView = (UIImageView *)subview;
            break;
        }
    }
    
    if (!imageView || !imageView.image) return;
    
    // Create a full-screen image viewer
    UIViewController *fullScreenVC = [[UIViewController alloc] init];
    fullScreenVC.view.backgroundColor = [UIColor systemBackgroundColor];
    fullScreenVC.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // Add method for closing
    [fullScreenVC addAction:@selector(closeButtonTapped:) withImplementation:^(id target, SEL _cmd, id sender) {
        [target dismissViewControllerAnimated:YES completion:nil];
    }];
    
    // Create a scrollView for zooming
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.delegate = self;
    scrollView.minimumZoomScale = 1.0;
    scrollView.maximumZoomScale = 4.0; // Increased max zoom
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.bounces = YES;
    scrollView.bouncesZoom = YES;
    scrollView.decelerationRate = UIScrollViewDecelerationRateNormal;
    [fullScreenVC.view addSubview:scrollView];
    
    // Create a full-size image view
    UIImageView *fullImageView = [[UIImageView alloc] init];
    fullImageView.translatesAutoresizingMaskIntoConstraints = NO;
    fullImageView.contentMode = UIViewContentModeScaleAspectFit;
    fullImageView.image = imageView.image;
    fullImageView.tag = 100; // Tag for zooming
    [scrollView addSubview:fullImageView];
    
    // Add constraints
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:fullScreenVC.view.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:fullScreenVC.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:fullScreenVC.view.bottomAnchor],
        
        [fullImageView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [fullImageView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [fullImageView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [fullImageView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [fullImageView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
        [fullImageView.heightAnchor constraintEqualToAnchor:scrollView.heightAnchor]
    ]];
    
    // Add a close button with improved style
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.7];
    closeButton.tintColor = [UIColor whiteColor];
    closeButton.layer.cornerRadius = 20;
    [closeButton addTarget:fullScreenVC action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [fullScreenVC.view addSubview:closeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.topAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.topAnchor constant:16],
        [closeButton.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor constant:-16],
        [closeButton.widthAnchor constraintEqualToConstant:40],
        [closeButton.heightAnchor constraintEqualToConstant:40]
    ]];
    
    // Add double tap gesture to zoom in/out
    UITapGestureRecognizer *doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTapGesture.numberOfTapsRequired = 2;
    [scrollView addGestureRecognizer:doubleTapGesture];
    
    // Store scrollView in a property of fullScreenVC for the double tap handler
    objc_setAssociatedObject(fullScreenVC, "scrollView", scrollView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Add method for handling double tap
    [self addAction:@selector(handleDoubleTap:) withImplementation:^(id target, SEL _cmd, UITapGestureRecognizer *gesture) {
        UIScrollView *sv = objc_getAssociatedObject(fullScreenVC, "scrollView");
        if (sv.zoomScale > sv.minimumZoomScale) {
            [sv setZoomScale:sv.minimumZoomScale animated:YES];
        } else {
            // Zoom in to where the user tapped
            CGPoint touchPoint = [gesture locationInView:sv];
            CGSize targetSize = CGSizeMake(sv.bounds.size.width / 2.0, sv.bounds.size.height / 2.0);
            CGRect targetRect = CGRectMake(touchPoint.x - targetSize.width/2, touchPoint.y - targetSize.height/2, targetSize.width, targetSize.height);
            [sv zoomToRect:targetRect animated:YES];
        }
    }];
    
    // Present the full-screen view
    [self presentViewController:fullScreenVC animated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return [scrollView viewWithTag:100];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    UIView *zoomView = [scrollView viewWithTag:100];
    
    CGFloat offsetX = MAX((scrollView.bounds.size.width - zoomView.frame.size.width) * 0.5, 0.0);
    CGFloat offsetY = MAX((scrollView.bounds.size.height - zoomView.frame.size.height) * 0.5, 0.0);
    
    zoomView.center = CGPointMake(scrollView.bounds.size.width * 0.5 + offsetX,
                                 scrollView.bounds.size.height * 0.5 + offsetY);
}

// Method to handle taps on original ticket attachment thumbnails
- (void)handleOriginalAttachmentTap:(UITapGestureRecognizer *)gesture {
    UIImageView *imageView = (UIImageView *)gesture.view;
    if (!imageView.image) return;
    
    // Create a full-screen image viewer
    UIViewController *fullScreenVC = [[UIViewController alloc] init];
    fullScreenVC.view.backgroundColor = [UIColor systemBackgroundColor];
    fullScreenVC.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // Add method for closing
    [fullScreenVC addAction:@selector(closeButtonTapped:) withImplementation:^(id target, SEL _cmd, id sender) {
        [target dismissViewControllerAnimated:YES completion:nil];
    }];
    
    // Create a scrollView for zooming
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.delegate = self;
    scrollView.minimumZoomScale = 1.0;
    scrollView.maximumZoomScale = 3.0;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    [fullScreenVC.view addSubview:scrollView];
    
    // Create a full-size image view
    UIImageView *fullImageView = [[UIImageView alloc] init];
    fullImageView.translatesAutoresizingMaskIntoConstraints = NO;
    fullImageView.contentMode = UIViewContentModeScaleAspectFit;
    fullImageView.image = imageView.image;
    fullImageView.tag = 100; // Tag for zooming
    [scrollView addSubview:fullImageView];
    
    // Add constraints
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:fullScreenVC.view.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:fullScreenVC.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:fullScreenVC.view.bottomAnchor],
        
        [fullImageView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [fullImageView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [fullImageView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [fullImageView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [fullImageView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
        [fullImageView.heightAnchor constraintEqualToAnchor:scrollView.heightAnchor]
    ]];
    
    // Add a close button with system styling
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    closeButton.backgroundColor = [UIColor systemFillColor];
    closeButton.layer.cornerRadius = 8;
    closeButton.tintColor = [UIColor labelColor];
    [closeButton addTarget:fullScreenVC action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [fullScreenVC.view addSubview:closeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.topAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.topAnchor constant:20],
        [closeButton.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor constant:-20],
        [closeButton.widthAnchor constraintEqualToConstant:80],
        [closeButton.heightAnchor constraintEqualToConstant:40]
    ]];
    
    // Present the full-screen view
    [self presentViewController:fullScreenVC animated:YES completion:nil];
}

@end

#pragma mark - ReplyTableViewCell Implementation

@implementation ReplyTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        
        // Bubble view with improved design
        self.bubbleView = [[UIView alloc] init];
        self.bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
        self.bubbleView.layer.cornerRadius = 18;  // More rounded corners
        self.bubbleView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.bubbleView.layer.shadowOffset = CGSizeMake(0, 1);
        self.bubbleView.layer.shadowRadius = 2;
        self.bubbleView.layer.shadowOpacity = 0.1;
        [self.contentView addSubview:self.bubbleView];
        
        // Time label (outside the bubble)
        self.timeLabel = [[UILabel alloc] init];
        self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.timeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
        self.timeLabel.textColor = [UIColor secondaryLabelColor];
        self.timeLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.timeLabel];
        
        // Author label with improved font
        self.authorLabel = [[UILabel alloc] init];
        self.authorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.authorLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [self.bubbleView addSubview:self.authorLabel];
        
        // Date label with improved font
        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.dateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        self.dateLabel.textColor = [UIColor systemGrayColor];
        [self.bubbleView addSubview:self.dateLabel];
        
        // Content text view with improved font - replaced UILabel with UITextView
        self.contentTextView = [[UITextView alloc] init];
        self.contentTextView.translatesAutoresizingMaskIntoConstraints = NO;
        self.contentTextView.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        self.contentTextView.editable = NO;
        self.contentTextView.scrollEnabled = NO;
        self.contentTextView.backgroundColor = [UIColor clearColor];
        self.contentTextView.textContainerInset = UIEdgeInsetsZero;
        self.contentTextView.textContainer.lineFragmentPadding = 0;
        self.contentTextView.dataDetectorTypes = UIDataDetectorTypeLink;
        [self.bubbleView addSubview:self.contentTextView];
        
        // Attachment image view with improved design
        self.attachmentImageView = [[UIImageView alloc] init];
        self.attachmentImageView.translatesAutoresizingMaskIntoConstraints = NO;
        self.attachmentImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.attachmentImageView.clipsToBounds = YES;
        self.attachmentImageView.layer.cornerRadius = 12.0;  // More rounded corners
        self.attachmentImageView.layer.borderWidth = 1.0;
        self.attachmentImageView.layer.borderColor = [UIColor separatorColor].CGColor;
        self.attachmentImageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.attachmentImageView.hidden = YES;
        [self.bubbleView addSubview:self.attachmentImageView];
        
        // Add tap gesture to image view
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleAttachmentTap:)];
        self.attachmentImageView.userInteractionEnabled = YES;
        [self.attachmentImageView addGestureRecognizer:tapGesture];
    }
    return self;
}

// Helper method to process formatted text (bold and links)
- (NSAttributedString *)processFormattedText:(NSString *)text isAdminReply:(BOOL)isAdminReply {
    // Only process formatting for admin replies
    if (!isAdminReply) {
        return [[NSAttributedString alloc] initWithString:text ?: @"" 
                                              attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightRegular]}];
    }
    
    // Create mutable attributed string
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:text ?: @""];
    
    // Set default attributes
    [attributedText addAttribute:NSFontAttributeName 
                           value:[UIFont systemFontOfSize:16 weight:UIFontWeightRegular] 
                           range:NSMakeRange(0, attributedText.length)];
    
    // Process bold text (**text**)
    NSError *error = nil;
    NSRegularExpression *boldRegex = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*(.*?)\\*\\*" 
                                                                               options:0 
                                                                                 error:&error];
    if (!error) {
        NSArray *matches = [boldRegex matchesInString:text 
                                              options:0 
                                                range:NSMakeRange(0, text.length)];
        
        // Process matches in reverse order to not mess up ranges
        for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
            NSRange boldTextRange = [match rangeAtIndex:1]; // The text between ** and **
            NSRange fullRange = [match rangeAtIndex:0];     // The full match including **
            
            // Get the text to make bold
            NSString *boldText = [text substringWithRange:boldTextRange];
            
            // Replace the full match with just the text (removing **)
            [attributedText replaceCharactersInRange:fullRange withString:boldText];
            
            // Apply bold attribute
            [attributedText addAttribute:NSFontAttributeName 
                                   value:[UIFont systemFontOfSize:16 weight:UIFontWeightBold] 
                                   range:NSMakeRange(fullRange.location, boldText.length)];
        }
    }
    
    // Process links ([text](url))
    error = nil;
    NSRegularExpression *linkRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[(.*?)\\]\\((.*?)\\)" 
                                                                               options:0 
                                                                                 error:&error];
    if (!error) {
        NSArray *matches = [linkRegex matchesInString:attributedText.string 
                                              options:0 
                                                range:NSMakeRange(0, attributedText.length)];
        
        // Process matches in reverse order to not mess up ranges
        for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
            NSRange linkTextRange = [match rangeAtIndex:1]; // The text between [ and ]
            NSRange linkURLRange = [match rangeAtIndex:2];  // The URL between ( and )
            NSRange fullRange = [match rangeAtIndex:0];     // The full match
            
            // Get the link text and URL
            NSString *linkText = [attributedText.string substringWithRange:linkTextRange];
            NSString *linkURL = [attributedText.string substringWithRange:linkURLRange];
            
            // Prefix link text with link icon if not already prefixed
            if (![linkText hasPrefix:@"🔗 "]) {
                linkText = [NSString stringWithFormat:@"🔗 %@", linkText];
            }
            
            // Replace the full match with just the link text (now with icon)
            [attributedText replaceCharactersInRange:fullRange withString:linkText];
            
            // Apply link attribute
            [attributedText addAttribute:NSLinkAttributeName 
                                   value:linkURL 
                                   range:NSMakeRange(fullRange.location, linkText.length)];
            
            // Add underline to indicate it's a link
            [attributedText addAttribute:NSUnderlineStyleAttributeName 
                                   value:@(NSUnderlineStyleSingle) 
                                   range:NSMakeRange(fullRange.location, linkText.length)];
                                   
            // Add background color to make the link stand out
            [attributedText addAttribute:NSBackgroundColorAttributeName
                                   value:[UIColor colorWithWhite:1.0 alpha:0.2]
                                   range:NSMakeRange(fullRange.location, linkText.length)];
                                   
            // Make the font slightly bolder
            [attributedText addAttribute:NSFontAttributeName 
                                   value:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] 
                                   range:NSMakeRange(fullRange.location, linkText.length)];
        }
    }
    
    return attributedText;
}

- (void)configureCellWithReply:(NSDictionary *)reply {
    // Set content
    NSString *content = reply[@"content"] ?: @"";
    
    // Set author
    NSDictionary *user = reply[@"user"];
    self.authorLabel.text = user[@"name"] ?: @"Unknown User";
    
    // Format date
    NSString *createdAtString = reply[@"created_at"];
    NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
    [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
    NSDate *createdDate = [inputFormatter dateFromString:createdAtString];
    
    NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
    [outputFormatter setDateStyle:NSDateFormatterShortStyle];
    [outputFormatter setTimeStyle:NSDateFormatterNoStyle]; // Don't include time in date label
    
    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    [timeFormatter setDateFormat:@"h:mm a"];
    
    if (createdDate) {
        self.dateLabel.text = [outputFormatter stringFromDate:createdDate];
        self.timeLabel.text = [timeFormatter stringFromDate:createdDate]; // Set the separate time label
    } else {
        self.dateLabel.text = @"";
        self.timeLabel.text = @"";
    }
    
    // Reset attachment view state
    self.attachmentImageView.hidden = YES;
    self.attachmentImageView.image = nil;
    
    // Check for attachments
    NSArray *attachments = reply[@"attachments"];
    BOOL hasAttachments = (attachments && [attachments isKindOfClass:[NSArray class]] && attachments.count > 0);
    
    // Set attachment image if available
    if (hasAttachments) {
        self.attachmentImageView.hidden = NO;
        
        NSDictionary *attachment = attachments[0]; // Use first attachment
        
        NSString *imageUrl = attachment[@"file_url"];
        if (!imageUrl) {
            // Try alternative keys that might be used
            imageUrl = attachment[@"url"];
            if (!imageUrl) {
                // One more fallback
                NSString *filePath = attachment[@"file_path"];
                if (filePath) {
                    // Use dynamic URL construction based on API base URL instead of hardcoded domain
                    NSString *baseURL = [[APIManager sharedManager] baseURL] ?: @"https://hydra.weaponx.us";
                    
                    // Ensure proper formatting of path and URL construction
                    if ([filePath hasPrefix:@"storage/"]) {
                        // If path starts with storage/, ensure we point to the public directory
                        imageUrl = [NSString stringWithFormat:@"%@/%@", baseURL, filePath];
                    } else if ([filePath hasPrefix:@"/storage/"]) {
                        // If path starts with /storage/, ensure we don't double slash
                        imageUrl = [NSString stringWithFormat:@"%@%@", baseURL, filePath];
                    } else {
                        // Otherwise, assume it's a path that needs to go into storage
                        imageUrl = [NSString stringWithFormat:@"%@/storage/%@", baseURL, filePath];
                    }
                }
            }
        }
        
        if (imageUrl) {
            // Show a loading placeholder
            self.attachmentImageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
            UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
            loadingIndicator.color = [UIColor labelColor];
            loadingIndicator.tag = 999;
            [self.attachmentImageView addSubview:loadingIndicator];
            
            [NSLayoutConstraint activateConstraints:@[
                [loadingIndicator.centerXAnchor constraintEqualToAnchor:self.attachmentImageView.centerXAnchor],
                [loadingIndicator.centerYAnchor constraintEqualToAnchor:self.attachmentImageView.centerYAnchor]
            ]];
            
            [loadingIndicator startAnimating];
            
            // Load image asynchronously with better error handling
            NSURLSession *session = [NSURLSession sharedSession];
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:imageUrl]];
            
            NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Remove the loading indicator
                    UIActivityIndicatorView *indicator = [self.attachmentImageView viewWithTag:999];
                    [indicator removeFromSuperview];
                    
                    if (error) {
                        self.attachmentImageView.hidden = YES;
                        return;
                    }
                    
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                    if (httpResponse.statusCode != 200) {
                        self.attachmentImageView.hidden = YES;
                        return;
                    }
                    
                    if (!data) {
                        self.attachmentImageView.hidden = YES;
                        return;
                    }
                    
                    UIImage *image = [UIImage imageWithData:data];
                    if (image) {
                        self.attachmentImageView.backgroundColor = [UIColor clearColor];
                        self.attachmentImageView.image = image;
                        self.attachmentImageView.hidden = NO;
                    } else {
                        self.attachmentImageView.hidden = YES;
                    }
                });
            }];
            
            [task resume];
        } else {
            self.attachmentImageView.hidden = YES;
        }
    }
    
    // Determine if this is an admin reply
    BOOL isAdminReply = [reply[@"is_admin_reply"] boolValue];
    
    // Process content with formatting (only for admin replies)
    NSAttributedString *processedContent = [self processFormattedText:content isAdminReply:isAdminReply];
    self.contentTextView.attributedText = processedContent;
    
    // Setup layout based on if admin or user
    if (isAdminReply) {
        self.bubbleView.backgroundColor = [UIColor systemBlueColor];
        self.contentTextView.textColor = [UIColor whiteColor];
        self.authorLabel.textColor = [UIColor whiteColor];
        self.dateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
        
        // Update link text color for admin bubbles
        self.contentTextView.linkTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
            NSBackgroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.2],
            NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]
        };
        
        // Remove any existing constraints
        [self.bubbleView removeConstraints:self.bubbleView.constraints];
        [self.contentView removeConstraints:self.contentView.constraints];
        
        // Base constraints for admin replies
        NSMutableArray *constraints = [NSMutableArray array];
        
        // Add bubble view constraints
        [constraints addObjectsFromArray:@[
            // Bubble view
            [self.bubbleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.bubbleView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
            [self.bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.75],
            [self.bubbleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            
            // Time label - positioned to the right of admin bubbles
            [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.bubbleView.centerYAnchor],
            [self.timeLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:8],
            [self.timeLabel.widthAnchor constraintEqualToConstant:60],
            
            // Author label
            [self.authorLabel.topAnchor constraintEqualToAnchor:self.bubbleView.topAnchor constant:8],
            [self.authorLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
            [self.authorLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
            
            // Date label
            [self.dateLabel.topAnchor constraintEqualToAnchor:self.authorLabel.bottomAnchor constant:2],
            [self.dateLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
            [self.dateLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
            
            // Content text view
            [self.contentTextView.topAnchor constraintEqualToAnchor:self.dateLabel.bottomAnchor constant:8],
            [self.contentTextView.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
            [self.contentTextView.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
        ]];
        
        if (hasAttachments) {
            // Add attachment-specific constraints
            [constraints addObjectsFromArray:@[
                // Attachment image - make it more prominent
                [self.attachmentImageView.topAnchor constraintEqualToAnchor:self.contentTextView.bottomAnchor constant:8],
                [self.attachmentImageView.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
                [self.attachmentImageView.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
                [self.attachmentImageView.heightAnchor constraintEqualToConstant:180],
                [self.attachmentImageView.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-8]
            ]];
        } else {
            // If no attachment, content label goes to bottom of bubble
            [constraints addObject:[self.contentTextView.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-8]];
        }
        
        // Activate all constraints
        [NSLayoutConstraint activateConstraints:constraints];
    } else {
        self.bubbleView.backgroundColor = [UIColor systemGrayColor];
        self.contentTextView.textColor = [UIColor whiteColor];
        self.authorLabel.textColor = [UIColor whiteColor];
        self.dateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
        
        // Update link text color for user bubbles
        self.contentTextView.linkTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
            NSBackgroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.2],
            NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]
        };
        
        // Remove any existing constraints
        [self.bubbleView removeConstraints:self.bubbleView.constraints];
        [self.contentView removeConstraints:self.contentView.constraints];
        
        // Base constraints for user replies
        NSMutableArray *constraints = [NSMutableArray array];
        
        // Add bubble view constraints
        [constraints addObjectsFromArray:@[
            // Bubble view
            [self.bubbleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.bubbleView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
            [self.bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.75],
            [self.bubbleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
            
            // Time label - positioned to the left of user bubbles
            [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.bubbleView.centerYAnchor],
            [self.timeLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:-8],
            [self.timeLabel.widthAnchor constraintEqualToConstant:60],
            
            // Author label
            [self.authorLabel.topAnchor constraintEqualToAnchor:self.bubbleView.topAnchor constant:8],
            [self.authorLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
            [self.authorLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
            
            // Date label
            [self.dateLabel.topAnchor constraintEqualToAnchor:self.authorLabel.bottomAnchor constant:2],
            [self.dateLabel.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
            [self.dateLabel.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
            
            // Content text view
            [self.contentTextView.topAnchor constraintEqualToAnchor:self.dateLabel.bottomAnchor constant:8],
            [self.contentTextView.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
            [self.contentTextView.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
        ]];
        
        if (hasAttachments) {
            // Add attachment-specific constraints
            [constraints addObjectsFromArray:@[
                // Attachment image - make it more prominent
                [self.attachmentImageView.topAnchor constraintEqualToAnchor:self.contentTextView.bottomAnchor constant:8],
                [self.attachmentImageView.leadingAnchor constraintEqualToAnchor:self.bubbleView.leadingAnchor constant:12],
                [self.attachmentImageView.trailingAnchor constraintEqualToAnchor:self.bubbleView.trailingAnchor constant:-12],
                [self.attachmentImageView.heightAnchor constraintEqualToConstant:180],
                [self.attachmentImageView.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-8]
            ]];
        } else {
            // If no attachment, content label goes to bottom of bubble
            [constraints addObject:[self.contentTextView.bottomAnchor constraintEqualToAnchor:self.bubbleView.bottomAnchor constant:-8]];
        }
        
        // Activate all constraints
        [NSLayoutConstraint activateConstraints:constraints];
    }
}

- (void)handleAttachmentTap:(UITapGestureRecognizer *)gesture {
    if (!self.attachmentImageView.image) return;
    
    // Get reference to the view controller (find the parent view controller)
    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *viewController = (UIViewController *)responder;
            
            // Create a full-screen image viewer
            UIViewController *fullScreenVC = [[UIViewController alloc] init];
            fullScreenVC.view.backgroundColor = [UIColor systemBackgroundColor];
            fullScreenVC.modalPresentationStyle = UIModalPresentationFullScreen;
            
            // Add method for closing
            [fullScreenVC addAction:@selector(closeButtonTapped:) withImplementation:^(id target, SEL _cmd, id sender) {
                [target dismissViewControllerAnimated:YES completion:nil];
            }];
            
            // Create a scrollView for zooming
            UIScrollView *scrollView = [[UIScrollView alloc] init];
            scrollView.translatesAutoresizingMaskIntoConstraints = NO;
            scrollView.delegate = self;
            scrollView.minimumZoomScale = 1.0;
            scrollView.maximumZoomScale = 3.0;
            scrollView.showsHorizontalScrollIndicator = NO;
            scrollView.showsVerticalScrollIndicator = NO;
            [fullScreenVC.view addSubview:scrollView];
            
            // Create a full-size image view
            UIImageView *fullImageView = [[UIImageView alloc] init];
            fullImageView.translatesAutoresizingMaskIntoConstraints = NO;
            fullImageView.contentMode = UIViewContentModeScaleAspectFit;
            fullImageView.image = self.attachmentImageView.image;
            fullImageView.tag = 100; // Tag for zooming
            [scrollView addSubview:fullImageView];
            
            // Add constraints
            [NSLayoutConstraint activateConstraints:@[
                [scrollView.topAnchor constraintEqualToAnchor:fullScreenVC.view.topAnchor],
                [scrollView.leadingAnchor constraintEqualToAnchor:fullScreenVC.view.leadingAnchor],
                [scrollView.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor],
                [scrollView.bottomAnchor constraintEqualToAnchor:fullScreenVC.view.bottomAnchor],
                
                [fullImageView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
                [fullImageView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
                [fullImageView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
                [fullImageView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
                [fullImageView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
                [fullImageView.heightAnchor constraintEqualToAnchor:scrollView.heightAnchor]
            ]];
            
            // Add a close button with system styling
            UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
            closeButton.translatesAutoresizingMaskIntoConstraints = NO;
            [closeButton setTitle:@"Close" forState:UIControlStateNormal];
            closeButton.backgroundColor = [UIColor systemFillColor];
            closeButton.layer.cornerRadius = 8;
            closeButton.tintColor = [UIColor labelColor];
            [closeButton addTarget:fullScreenVC action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [fullScreenVC.view addSubview:closeButton];
            
            [NSLayoutConstraint activateConstraints:@[
                [closeButton.topAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.topAnchor constant:20],
                [closeButton.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor constant:-20],
                [closeButton.widthAnchor constraintEqualToConstant:80],
                [closeButton.heightAnchor constraintEqualToConstant:40]
            ]];
            
            // Present the full-screen view
            [viewController presentViewController:fullScreenVC animated:YES completion:nil];
            break;
        }
    }
}

@end 