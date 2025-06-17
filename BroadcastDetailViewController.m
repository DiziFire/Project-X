#import <UIKit/UIKit.h>
#import "APIManager.h"
#import <objc/runtime.h>
#import <WebKit/WebKit.h>

@interface BroadcastDetailViewController : UIViewController <WKNavigationDelegate>

@property (nonatomic, strong) NSNumber *broadcastId;
@property (nonatomic, strong) NSDictionary *broadcast;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) WKWebView *contentWebView;
@property (nonatomic, strong) UILabel *contentLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *expiryLabel;
@property (nonatomic, strong) UIImageView *featuredImageView;
@property (nonatomic, strong) UIStackView *attachmentsStackView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UIView *separatorView;

@end

@implementation BroadcastDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Announcement";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Add a custom back button for iOS 15 compatibility
    if (@available(iOS 15.0, *)) {
        UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back" 
                                                                       style:UIBarButtonItemStylePlain 
                                                                      target:self 
                                                                      action:@selector(safelyDismissView)];
        self.navigationItem.leftBarButtonItem = backButton;
    }
    
    [self setupUI];
    [self loadBroadcastDetails];
}

// Safe method to dismiss the view
- (void)safelyDismissView {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)setupUI {
    // Scroll view
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];
    
    // Content container
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:contentView];
    
    // Title label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.textColor = [UIColor labelColor];
    [contentView addSubview:self.titleLabel];
    
    // Date label
    self.dateLabel = [[UILabel alloc] init];
    self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dateLabel.font = [UIFont systemFontOfSize:14];
    self.dateLabel.textColor = [UIColor secondaryLabelColor];
    [contentView addSubview:self.dateLabel];
    
    // Expiry label
    self.expiryLabel = [[UILabel alloc] init];
    self.expiryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.expiryLabel.font = [UIFont systemFontOfSize:14];
    self.expiryLabel.textColor = [UIColor secondaryLabelColor];
    [contentView addSubview:self.expiryLabel];
    
    // Featured image view
    self.featuredImageView = [[UIImageView alloc] init];
    self.featuredImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.featuredImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.featuredImageView.layer.cornerRadius = 8.0;
    self.featuredImageView.clipsToBounds = YES;
    self.featuredImageView.hidden = YES;
    self.featuredImageView.userInteractionEnabled = YES;
    
    // Add tap gesture to featured image
    UITapGestureRecognizer *imageTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageTap:)];
    [self.featuredImageView addGestureRecognizer:imageTapGesture];
    
    [contentView addSubview:self.featuredImageView];
    
    // Content web view for HTML content
    WKWebViewConfiguration *webConfig = [[WKWebViewConfiguration alloc] init];
    self.contentWebView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:webConfig];
    self.contentWebView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentWebView.navigationDelegate = self;
    // Disable scrolling in WebView since we're using the main scrollView
    self.contentWebView.scrollView.scrollEnabled = NO;
    self.contentWebView.hidden = YES;
    self.contentWebView.backgroundColor = [UIColor clearColor];
    self.contentWebView.opaque = NO;
    [contentView addSubview:self.contentWebView];
    
    // Separator
    self.separatorView = [[UIView alloc] init];
    self.separatorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.separatorView.backgroundColor = [UIColor separatorColor];
    [contentView addSubview:self.separatorView];
    
    // Regular content label for plain text
    self.contentLabel = [[UILabel alloc] init];
    self.contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentLabel.font = [UIFont systemFontOfSize:16];
    self.contentLabel.numberOfLines = 0;
    self.contentLabel.textColor = [UIColor labelColor];
    [contentView addSubview:self.contentLabel];
    
    // Attachments stack view
    self.attachmentsStackView = [[UIStackView alloc] init];
    self.attachmentsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentsStackView.axis = UILayoutConstraintAxisVertical;
    self.attachmentsStackView.spacing = 10;
    self.attachmentsStackView.distribution = UIStackViewDistributionFill;
    self.attachmentsStackView.alignment = UIStackViewAlignmentFill;
    self.attachmentsStackView.hidden = YES;
    [contentView addSubview:self.attachmentsStackView];
    
    // Loading indicator
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];
    
    // Setup constraints
    [NSLayoutConstraint activateConstraints:@[
        // Scroll view
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        
        // Content view
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        
        // Title label
        [self.titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // Date label
        [self.dateLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:10],
        [self.dateLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.dateLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // Expiry label
        [self.expiryLabel.topAnchor constraintEqualToAnchor:self.dateLabel.bottomAnchor constant:4],
        [self.expiryLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.expiryLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // Featured image view
        [self.featuredImageView.topAnchor constraintEqualToAnchor:self.expiryLabel.bottomAnchor constant:15],
        [self.featuredImageView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.featuredImageView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.featuredImageView.heightAnchor constraintLessThanOrEqualToConstant:200],
        
        // Separator
        [self.separatorView.topAnchor constraintEqualToAnchor:self.expiryLabel.bottomAnchor constant:15],
        [self.separatorView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.separatorView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.separatorView.heightAnchor constraintEqualToConstant:1],
        
        // Attachments stack view - moved to be directly after separator
        [self.attachmentsStackView.topAnchor constraintEqualToAnchor:self.separatorView.bottomAnchor constant:15],
        [self.attachmentsStackView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.attachmentsStackView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // Content webview (for HTML content) - moved to be after attachments
        [self.contentWebView.topAnchor constraintEqualToAnchor:self.attachmentsStackView.bottomAnchor constant:15],
        [self.contentWebView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.contentWebView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.contentWebView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-30],
        
        // Content label (for plain text) - moved to be after attachments
        [self.contentLabel.topAnchor constraintEqualToAnchor:self.attachmentsStackView.bottomAnchor constant:15],
        [self.contentLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.contentLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.contentLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-30],
        
        // Loading indicator
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    
    // Additional constraint for web view to content web view height
    [self.contentWebView.heightAnchor constraintGreaterThanOrEqualToConstant:10].active = YES;
}

// WKWebView Navigation Delegate Methods
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // Adjust web view height to fit content
    [webView evaluateJavaScript:@"document.documentElement.scrollHeight" completionHandler:^(id height, NSError *error) {
        if (!error) {
            CGFloat contentHeight = [height floatValue];
            NSLog(@"WebView content height: %@", height);
            
            // Remove any existing height constraints
            for (NSLayoutConstraint *constraint in self.contentWebView.constraints) {
                if (constraint.firstAttribute == NSLayoutAttributeHeight) {
                    [self.contentWebView removeConstraint:constraint];
                    break;
                }
            }
            
            // Set the exact height needed for the content with some padding
            NSLayoutConstraint *heightConstraint = [self.contentWebView.heightAnchor constraintEqualToConstant:contentHeight + 20];
            heightConstraint.priority = UILayoutPriorityDefaultHigh;
            heightConstraint.active = YES;
            
            // If we're using the web view, make sure content label is hidden and doesn't take up space
            self.contentLabel.hidden = YES;
            
            // Force layout update
            [self.view layoutIfNeeded];
            
            // Ensure the scrollView content size is updated
            [self.scrollView layoutIfNeeded];
        }
    }];
}

- (void)loadBroadcastDetails {
    [self.loadingIndicator startAnimating];
    
    // Use weak self to prevent retain cycles
    __weak typeof(self) weakSelf = self;
    
    [[APIManager sharedManager] getBroadcastDetails:self.broadcastId completion:^(NSDictionary *broadcast, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Check if self is still around
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            [strongSelf.loadingIndicator stopAnimating];
            
            if (error) {
                NSLog(@"Error loading broadcast details: %@", error);
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:@"Failed to load announcement details. Please try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            strongSelf.broadcast = broadcast;
            [strongSelf updateUI];
            
            // Mark as read - Use weak self again for the inner completion block
            [[APIManager sharedManager] markBroadcastAsRead:strongSelf.broadcastId completion:^(BOOL success, NSError *error) {
                if (error) {
                    NSLog(@"Error marking broadcast as read: %@", error);
                }
            }];
        });
    }];
}

- (void)updateUI {
    // Safety check
    if (!self.broadcast) {
        NSLog(@"Error: No broadcast data to display");
        return;
    }
    
    // Ensure we're on the main thread for UI updates
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateUI];
        });
        return;
    }
    
    // Set title with fallback
    self.titleLabel.text = self.broadcast[@"title"] ?: @"Untitled Announcement";
    
    // Check for content type - HTML or plain text
    NSString *contentType = self.broadcast[@"content_type"];
    NSString *content = self.broadcast[@"content"] ?: @"No content available";
    
    // Clear previous attachments
    for (UIView *view in self.attachmentsStackView.arrangedSubviews) {
        [view removeFromSuperview];
    }
    
    // Handle attachments if available - process this BEFORE content to ensure proper layout
    id attachments = self.broadcast[@"attachments"];
    if (attachments && [attachments isKindOfClass:[NSArray class]] && [(NSArray *)attachments count] > 0) {
        self.attachmentsStackView.hidden = NO;
        self.attachmentsStackView.alpha = 1.0;
        [self setupAttachments:(NSArray *)attachments];
    } else {
        self.attachmentsStackView.hidden = YES;
        self.attachmentsStackView.alpha = 0;
        
        // When attachments are hidden, adjust content top anchor
        if ([contentType isEqualToString:@"html"] || [content containsString:@"<html>"] || [content containsString:@"<body>"]) {
            // Adjust webView top anchor
            for (NSLayoutConstraint *constraint in self.view.constraints) {
                if (constraint.firstItem == self.contentWebView && constraint.firstAttribute == NSLayoutAttributeTop) {
                    constraint.active = NO;
                    break;
                }
            }
            [self.contentWebView.topAnchor constraintEqualToAnchor:self.separatorView.bottomAnchor constant:15].active = YES;
        } else {
            // Adjust content label top anchor
            for (NSLayoutConstraint *constraint in self.view.constraints) {
                if (constraint.firstItem == self.contentLabel && constraint.firstAttribute == NSLayoutAttributeTop) {
                    constraint.active = NO;
                    break;
                }
            }
            [self.contentLabel.topAnchor constraintEqualToAnchor:self.separatorView.bottomAnchor constant:15].active = YES;
        }
    }
    
    // Handle HTML content if specified
    if ([contentType isEqualToString:@"html"] || [content containsString:@"<html>"] || [content containsString:@"<body>"]) {
        // Configure web view for HTML content
        self.contentWebView.hidden = NO;
        self.contentLabel.hidden = YES;
        
        // Create HTML string with proper styling that adapts to light/dark mode
        NSString *htmlTemplate = [self createHtmlTemplateWithContent:content];
        [self.contentWebView loadHTMLString:htmlTemplate baseURL:nil];
    } else {
        // Use regular text display
        self.contentWebView.hidden = YES;
        self.contentLabel.hidden = NO;
        self.contentLabel.text = content;
    }
    
    // Format created date
    NSString *createdAtString = self.broadcast[@"created_at"];
    if (createdAtString) {
    NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
    [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
    NSDate *createdDate = [inputFormatter dateFromString:createdAtString];
    
        if (!createdDate) {
            // Try alternative format without milliseconds
            [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
            createdDate = [inputFormatter dateFromString:createdAtString];
        }
        
        if (createdDate) {
    NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
    [outputFormatter setDateStyle:NSDateFormatterMediumStyle];
    [outputFormatter setTimeStyle:NSDateFormatterShortStyle];
        self.dateLabel.text = [NSString stringWithFormat:@"Posted: %@", [outputFormatter stringFromDate:createdDate]];
        } else {
            self.dateLabel.text = @"Posted: Unknown date";
        }
    } else {
        self.dateLabel.text = @"Posted: Unknown date";
    }
    
    // Format expiry date if available
    NSString *expiryDateString = self.broadcast[@"expiry_date"];
    if (expiryDateString) {
        NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
        [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        NSDate *expiryDate = [inputFormatter dateFromString:expiryDateString];
        
        if (!expiryDate) {
            // Try alternative format without milliseconds
            [inputFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
            expiryDate = [inputFormatter dateFromString:expiryDateString];
        }
        
        if (expiryDate) {
            NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
            [outputFormatter setDateStyle:NSDateFormatterMediumStyle];
            [outputFormatter setTimeStyle:NSDateFormatterShortStyle];
            self.expiryLabel.text = [NSString stringWithFormat:@"Valid until: %@", [outputFormatter stringFromDate:expiryDate]];
            self.expiryLabel.hidden = NO;
        } else {
            self.expiryLabel.hidden = YES;
        }
    } else {
        // No expiry date, so it's valid indefinitely
        self.expiryLabel.text = @"Valid indefinitely";
        self.expiryLabel.hidden = NO;
    }
    
    // Handle featured image if available
    id imageUrl = self.broadcast[@"image_url"];
    if (imageUrl && [imageUrl isKindOfClass:[NSString class]] && [(NSString *)imageUrl length] > 0) {
        // Only show and attempt to load if we have a non-empty image URL
        self.featuredImageView.hidden = NO;
        [self loadImageFromURL:[NSURL URLWithString:imageUrl] forImageView:self.featuredImageView];
    } else {
        // Always hide the featuredImageView if no valid image URL
        self.featuredImageView.hidden = YES;
    }
}

- (NSString *)createHtmlTemplateWithContent:(NSString *)content {
    // Create HTML template that adapts to system light/dark mode
    NSString *htmlTemplate = @"<!DOCTYPE html>\
    <html>\
    <head>\
        <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=5.0'>\
        <style>\
            :root {\
                color-scheme: light dark;\
            }\
            body {\
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;\
                font-size: 16px;\
                line-height: 1.6;\
                margin: 0;\
                padding: 0;\
                color: #000;\
                background-color: transparent;\
                overflow-wrap: break-word;\
                word-wrap: break-word;\
            }\
            @media (prefers-color-scheme: dark) {\
                body {\
                    color: #fff;\
                }\
                a {\
                    color: #0a84ff;\
                }\
            }\
            img {\
                max-width: 100%%;\
                height: auto;\
                border-radius: 8px;\
                display: block;\
                margin: 12px 0;\
            }\
            a {\
                color: #007aff;\
                text-decoration: none;\
            }\
            ul, ol {\
                padding-left: 20px;\
                margin-bottom: 16px;\
            }\
            p {\
                margin-bottom: 16px;\
            }\
            h1, h2, h3, h4, h5, h6 {\
                margin-top: 24px;\
                margin-bottom: 16px;\
                line-height: 1.4;\
            }\
            /* More styles can be added here */\
        </style>\
    </head>\
    <body>%@</body>\
    </html>";
    
    // Check if content already has HTML structure
    if ([content containsString:@"<html>"] || [content containsString:@"<body>"]) {
        return content; // Already has full HTML structure
    }
    
    // If it has some HTML tags but not full structure
    if ([content containsString:@"<"] && [content containsString:@">"]) {
        return [NSString stringWithFormat:htmlTemplate, content];
    }
    
    // If it's plain text, wrap it in paragraph tags
    return [NSString stringWithFormat:htmlTemplate, [NSString stringWithFormat:@"<p>%@</p>", content]];
}

- (void)loadImageFromURL:(NSURL *)url forImageView:(UIImageView *)imageView {
    if (!url) {
        if (imageView == self.featuredImageView) {
            imageView.hidden = YES;
        }
        return;
    }
    
    // Log URL for debugging
    NSLog(@"Loading featured image from URL: %@", url);
    
    // Create a loading indicator
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    [imageView addSubview:indicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [indicator.centerXAnchor constraintEqualToAnchor:imageView.centerXAnchor],
        [indicator.centerYAnchor constraintEqualToAnchor:imageView.centerYAnchor]
    ]];
    
    [indicator startAnimating];
    
    // Load image asynchronously with improved request
    NSURLSession *session = [NSURLSession sharedSession];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setCachePolicy:NSURLRequestUseProtocolCachePolicy];
    [request setTimeoutInterval:30.0];
    
    // Add custom headers if needed for authentication
    // [request setValue:@"Bearer TOKEN" forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [indicator stopAnimating];
            [indicator removeFromSuperview];
            
            if (error) {
                NSLog(@"Error loading image: %@", error);
                // Show error indicator in imageView
                [self showErrorImageInImageView:imageView];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (!httpResponse || httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
                NSLog(@"HTTP error: %ld", (long)httpResponse.statusCode);
                [self showErrorImageInImageView:imageView];
                return;
            }
            
            if (!data || data.length == 0) {
                NSLog(@"No data received");
                [self showErrorImageInImageView:imageView];
                return;
            }
            
            UIImage *image = [UIImage imageWithData:data];
            if (image) {
                imageView.image = image;
                
                // Only add tap gesture for featured image
                if (imageView == self.featuredImageView) {
                    // Add tap gesture to view full image
                    imageView.userInteractionEnabled = YES;
                    
                    // Remove any existing gestures first
                    for (UIGestureRecognizer *recognizer in imageView.gestureRecognizers) {
                        [imageView removeGestureRecognizer:recognizer];
                    }
                    
                    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageTap:)];
                    [imageView addGestureRecognizer:tapGesture];
                }
            } else {
                NSLog(@"Failed to create image from data. Data length: %lu", (unsigned long)data.length);
                [self showErrorImageInImageView:imageView];
            }
        });
    }];
    
    [task resume];
}

- (void)showErrorImageInImageView:(UIImageView *)imageView {
    // Don't show placeholder icons for failed images in broadcast details
    if (imageView == self.featuredImageView) {
        imageView.image = nil;
        imageView.hidden = YES;
        return;
    }
    
    // For other image views, create an error image/indicator
    UIImage *errorImage = [UIImage systemImageNamed:@"photo.fill"];
    if (errorImage) {
        imageView.image = errorImage;
        imageView.tintColor = [UIColor systemGrayColor];
        imageView.contentMode = UIViewContentModeCenter;
    } else {
        // Fallback if system image isn't available
        imageView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.1];
        
        // Add label for error message
        for (UIView *subview in imageView.subviews) {
            if ([subview isKindOfClass:[UILabel class]]) {
                [subview removeFromSuperview];
            }
        }
        
        UILabel *errorLabel = [[UILabel alloc] init];
        errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        errorLabel.text = @"Image not available";
        errorLabel.textColor = [UIColor systemGrayColor];
        errorLabel.font = [UIFont systemFontOfSize:14];
        [imageView addSubview:errorLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [errorLabel.centerXAnchor constraintEqualToAnchor:imageView.centerXAnchor],
            [errorLabel.centerYAnchor constraintEqualToAnchor:imageView.centerYAnchor]
        ]];
    }
}

- (void)setupAttachments:(NSArray *)attachments {
    // Process each attachment directly without the header or separator
    for (NSDictionary *attachment in attachments) {
        NSString *name = attachment[@"name"] ?: @"Attachment";
        NSString *type = attachment[@"type"] ?: @"file";
        NSString *url = attachment[@"url"];
        
        if (url) {
            // For images, display them directly
            if ([type isEqualToString:@"image"]) {
                // Create image container
                UIView *imageContainer = [[UIView alloc] init];
                imageContainer.translatesAutoresizingMaskIntoConstraints = NO;
                imageContainer.layer.cornerRadius = 8.0;
                imageContainer.clipsToBounds = YES;
                imageContainer.backgroundColor = [UIColor systemGray6Color];
                
                // Create image view
                UIImageView *attachmentImageView = [[UIImageView alloc] init];
                attachmentImageView.translatesAutoresizingMaskIntoConstraints = NO;
                attachmentImageView.contentMode = UIViewContentModeScaleAspectFit;
                attachmentImageView.clipsToBounds = YES;
                [imageContainer addSubview:attachmentImageView];
                
                // Add constraints for image view
                [NSLayoutConstraint activateConstraints:@[
                    [attachmentImageView.topAnchor constraintEqualToAnchor:imageContainer.topAnchor],
                    [attachmentImageView.leadingAnchor constraintEqualToAnchor:imageContainer.leadingAnchor],
                    [attachmentImageView.trailingAnchor constraintEqualToAnchor:imageContainer.trailingAnchor],
                    [attachmentImageView.bottomAnchor constraintEqualToAnchor:imageContainer.bottomAnchor]
                ]];
                
                // Store URL in image container
                objc_setAssociatedObject(imageContainer, @"attachment_url", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(imageContainer, @"attachment_type", type, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                
                // Add tap gesture to open full screen
                UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageContainerTap:)];
                [imageContainer addGestureRecognizer:tapGesture];
                imageContainer.userInteractionEnabled = YES;
                
                // Add to stack view
                [self.attachmentsStackView addArrangedSubview:imageContainer];
                
                // Set height constraint - use a reasonable height for images
                [imageContainer.heightAnchor constraintEqualToConstant:200].active = YES;
                
                // Start loading the image
                NSURL *imageURL = [NSURL URLWithString:url];
                if (imageURL) {
                    [self loadAttachmentImageFromURL:imageURL forImageView:attachmentImageView];
                }
            } else {
                // For non-image files, keep the button approach
                if (@available(iOS 15.0, *)) {
                    // Use UIButtonConfiguration for iOS 15+
                    UIButton *attachmentButton = [UIButton buttonWithType:UIButtonTypeSystem];
                    attachmentButton.translatesAutoresizingMaskIntoConstraints = NO;
                    
                    // Set icon based on type
                    UIImage *icon;
                    if ([type isEqualToString:@"video"]) {
                        icon = [UIImage systemImageNamed:@"video"];
                    } else if ([type isEqualToString:@"pdf"]) {
                        icon = [UIImage systemImageNamed:@"doc.text"];
                    } else {
                        icon = [UIImage systemImageNamed:@"doc"];
                    }
                    
                    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
                    config.imagePadding = 10;
                    config.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);
                    config.image = icon;
                    config.title = name;
                    config.imagePlacement = NSDirectionalRectEdgeLeading;
                    config.baseForegroundColor = [UIColor systemBlueColor];
                    [attachmentButton setConfiguration:config];
                    
                    // Store URL in button
                    objc_setAssociatedObject(attachmentButton, @"attachment_url", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(attachmentButton, @"attachment_type", type, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    
                    [attachmentButton addTarget:self action:@selector(handleAttachmentTap:) forControlEvents:UIControlEventTouchUpInside];
                    
                    [self.attachmentsStackView addArrangedSubview:attachmentButton];
                    [attachmentButton.heightAnchor constraintEqualToConstant:44].active = YES;
                } else {
                    // Create a custom view that simulates a button for iOS 14 and below
                    UIView *customButtonView = [[UIView alloc] init];
                    customButtonView.translatesAutoresizingMaskIntoConstraints = NO;
                    
                    // Create icon image view
                    UIImage *icon;
                    if ([type isEqualToString:@"video"]) {
                        icon = [UIImage systemImageNamed:@"video"];
                    } else if ([type isEqualToString:@"pdf"]) {
                        icon = [UIImage systemImageNamed:@"doc.text"];
                    } else {
                        icon = [UIImage systemImageNamed:@"doc"];
                    }
                    
                    UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
                    iconView.translatesAutoresizingMaskIntoConstraints = NO;
                    iconView.tintColor = [UIColor systemBlueColor];
                    [customButtonView addSubview:iconView];
                    
                    // Create label
                    UILabel *nameLabel = [[UILabel alloc] init];
                    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
                    nameLabel.text = name;
                    nameLabel.textColor = [UIColor systemBlueColor];
                    nameLabel.font = [UIFont systemFontOfSize:16];
                    [customButtonView addSubview:nameLabel];
                    
                    // Setup constraints
                    [NSLayoutConstraint activateConstraints:@[
                        [iconView.leadingAnchor constraintEqualToAnchor:customButtonView.leadingAnchor constant:8],
                        [iconView.centerYAnchor constraintEqualToAnchor:customButtonView.centerYAnchor],
                        [iconView.widthAnchor constraintEqualToConstant:20],
                        [iconView.heightAnchor constraintEqualToConstant:20],
                        
                        [nameLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10],
                        [nameLabel.trailingAnchor constraintEqualToAnchor:customButtonView.trailingAnchor constant:-8],
                        [nameLabel.centerYAnchor constraintEqualToAnchor:customButtonView.centerYAnchor]
                    ]];
                    
                    // Add tap gesture
                    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCustomButtonTap:)];
                    [customButtonView addGestureRecognizer:tapGesture];
                    customButtonView.userInteractionEnabled = YES;
                    
                    // Store URL in view
                    objc_setAssociatedObject(customButtonView, @"attachment_url", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(customButtonView, @"attachment_type", type, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    
                    [self.attachmentsStackView addArrangedSubview:customButtonView];
                    [customButtonView.heightAnchor constraintEqualToConstant:44].active = YES;
                }
            }
        }
    }
}

// Special loading method for attachment images
- (void)loadAttachmentImageFromURL:(NSURL *)url forImageView:(UIImageView *)imageView {
    if (!url) return;
    
    // Log URL for debugging
    NSLog(@"Loading attachment image from URL: %@", url);
    
    // Create a loading indicator
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    [imageView addSubview:indicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [indicator.centerXAnchor constraintEqualToAnchor:imageView.centerXAnchor],
        [indicator.centerYAnchor constraintEqualToAnchor:imageView.centerYAnchor]
    ]];
    
    [indicator startAnimating];
    
    // Check if URL is relative and convert to absolute if needed
    if (![url.absoluteString hasPrefix:@"http"]) {
        // Get base URL from API manager
        NSString *baseURL = [[APIManager sharedManager] baseURL] ?: @"https://hydra.weaponx.us";
        
        // Ensure proper formatting of path and URL construction
        NSString *path = url.absoluteString;
        NSString *absoluteURLString = nil;
        
        if ([path hasPrefix:@"storage/"]) {
            // If path starts with storage/, ensure we point to the public directory
            absoluteURLString = [NSString stringWithFormat:@"%@/%@", baseURL, path];
        } else if ([path hasPrefix:@"/storage/"]) {
            // If path starts with /storage/, ensure we don't double slash
            absoluteURLString = [NSString stringWithFormat:@"%@%@", baseURL, path];
        } else {
            // Otherwise, assume it's a relative path that needs to be appended
            absoluteURLString = [NSString stringWithFormat:@"%@/%@", 
                                baseURL, 
                                [path hasPrefix:@"/"] ? [path substringFromIndex:1] : path];
        }
        
        url = [NSURL URLWithString:absoluteURLString];
        NSLog(@"Converted to absolute URL: %@", url);
    }
    
    // Load image asynchronously
    NSURLSession *session = [NSURLSession sharedSession];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setCachePolicy:NSURLRequestUseProtocolCachePolicy];
    [request setTimeoutInterval:30.0];
    
    // Add authorization if needed
    NSString *token = [[APIManager sharedManager] getAuthToken];
    if (token) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [indicator stopAnimating];
            [indicator removeFromSuperview];
            
            if (error) {
                NSLog(@"Error loading attachment image: %@", error);
                [self showErrorImageInImageView:imageView];
                return;
            }
            
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (!httpResponse || httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
                NSLog(@"HTTP error: %ld", (long)httpResponse.statusCode);
                [self showErrorImageInImageView:imageView];
                return;
            }
            
            if (!data || data.length == 0) {
                NSLog(@"No data received for attachment image");
                [self showErrorImageInImageView:imageView];
                return;
            }
            
            UIImage *image = [UIImage imageWithData:data];
            if (image) {
                imageView.image = image;
        } else {
                NSLog(@"Failed to create image from attachment data. Data length: %lu", (unsigned long)data.length);
                [self showErrorImageInImageView:imageView];
            }
        });
    }];
    
    [task resume];
}

// Handler for tapping on an image container
- (void)handleImageContainerTap:(UITapGestureRecognizer *)gesture {
    UIView *container = gesture.view;
    NSString *urlString = objc_getAssociatedObject(container, @"attachment_url");
    NSString *type = objc_getAssociatedObject(container, @"attachment_type");
    
    // Reuse the same handler logic
    if (urlString) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [self openAttachmentWithURL:url type:type];
        }
    }
}

// Handler for custom button taps in iOS 14 and below
- (void)handleCustomButtonTap:(UITapGestureRecognizer *)gesture {
    UIView *customButtonView = gesture.view;
    NSString *urlString = objc_getAssociatedObject(customButtonView, @"attachment_url");
    NSString *type = objc_getAssociatedObject(customButtonView, @"attachment_type");
    
    // Reuse the same handler logic
    if (urlString) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [self openAttachmentWithURL:url type:type];
        }
    }
}

- (void)handleAttachmentTap:(UIButton *)button {
    NSString *urlString = objc_getAssociatedObject(button, @"attachment_url");
    NSString *type = objc_getAssociatedObject(button, @"attachment_type");
    
    if (urlString) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [self openAttachmentWithURL:url type:type];
        }
    }
}

- (void)openAttachmentWithURL:(NSURL *)url type:(NSString *)type {
    // For images, we can preview them
    if ([type isEqualToString:@"image"]) {
        [self.loadingIndicator startAnimating];
        
        // Log the URL to help with debugging
        NSLog(@"Loading attachment image from URL: %@", url);
        
        // Check if URL is relative and convert to absolute if needed
        if (![url.absoluteString hasPrefix:@"http"]) {
            // Get base URL from API manager
            NSString *baseURL = [[APIManager sharedManager] baseURL] ?: @"https://hydra.weaponx.us";
            
            // Ensure proper formatting of path and URL construction
            NSString *path = url.absoluteString;
            NSString *absoluteURLString = nil;
            
            if ([path hasPrefix:@"storage/"]) {
                // If path starts with storage/, ensure we point to the public directory
                absoluteURLString = [NSString stringWithFormat:@"%@/%@", baseURL, path];
            } else if ([path hasPrefix:@"/storage/"]) {
                // If path starts with /storage/, ensure we don't double slash
                absoluteURLString = [NSString stringWithFormat:@"%@%@", baseURL, path];
            } else {
                // Otherwise, assume it's a relative path that needs to be appended
                absoluteURLString = [NSString stringWithFormat:@"%@/%@", 
                                    baseURL, 
                                    [path hasPrefix:@"/"] ? [path substringFromIndex:1] : path];
            }
            
            url = [NSURL URLWithString:absoluteURLString];
            NSLog(@"Converted to absolute URL: %@", url);
        }
        
        // Create a proper URL request with cache policy and timeout
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setCachePolicy:NSURLRequestUseProtocolCachePolicy];
        [request setTimeoutInterval:30.0];
        
        // Add authorization if needed - sometimes images require authentication
        NSString *token = [[APIManager sharedManager] getAuthToken];
        if (token) {
            [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
        }
        
        // Load image asynchronously
        NSURLSession *session = [NSURLSession sharedSession];
        
        NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.loadingIndicator stopAnimating];
                
                if (error) {
                    NSLog(@"Error loading image: %@", error);
                    [self showErrorAlertWithMessage:[NSString stringWithFormat:@"Failed to load image attachment: %@", error.localizedDescription]];
                    return;
                }
                
                // Check HTTP response
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (httpResponse && (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300)) {
                    NSLog(@"HTTP error: %ld", (long)httpResponse.statusCode);
                    [self showErrorAlertWithMessage:[NSString stringWithFormat:@"Server returned error: %ld", (long)httpResponse.statusCode]];
                    return;
                }
                
                if (!data || data.length == 0) {
                    NSLog(@"Empty data received");
                    [self showErrorAlertWithMessage:@"Empty image data received"];
                    return;
                }
                
                // Try to create image from data
                UIImage *image = [UIImage imageWithData:data];
                if (image) {
                    // Create fullscreen view controller with zooming
                    UIViewController *fullScreenVC = [[UIViewController alloc] init];
                    fullScreenVC.view.backgroundColor = [UIColor systemBackgroundColor];
                    fullScreenVC.modalPresentationStyle = UIModalPresentationFullScreen;
                    
                    // Create a scroll view for zooming
                    UIScrollView *scrollView = [[UIScrollView alloc] init];
                    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
                    scrollView.minimumZoomScale = 1.0;
                    scrollView.maximumZoomScale = 3.0;
                    scrollView.delegate = (id<UIScrollViewDelegate>)fullScreenVC;
                    [fullScreenVC.view addSubview:scrollView];
                    
                    // Add image view to scroll view
                    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
                    imageView.translatesAutoresizingMaskIntoConstraints = NO;
                    imageView.contentMode = UIViewContentModeScaleAspectFit;
                    [scrollView addSubview:imageView];
                    
                    // Set up constraints for scroll view
                    [NSLayoutConstraint activateConstraints:@[
                        [scrollView.topAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.topAnchor],
                        [scrollView.leadingAnchor constraintEqualToAnchor:fullScreenVC.view.leadingAnchor],
                        [scrollView.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor],
                        [scrollView.bottomAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.bottomAnchor]
                    ]];
                    
                    // Set up constraints for image view
                    [NSLayoutConstraint activateConstraints:@[
                        [imageView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
                        [imageView.heightAnchor constraintEqualToAnchor:scrollView.heightAnchor],
                        [imageView.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor],
                        [imageView.centerYAnchor constraintEqualToAnchor:scrollView.centerYAnchor]
                    ]];
                    
                    // Add close button
                    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
                    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
                    
                    if (@available(iOS 15.0, *)) {
                        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
                        config.baseBackgroundColor = [UIColor secondarySystemBackgroundColor];
                        config.baseForegroundColor = [UIColor labelColor];
                        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
                        [config setImage:[UIImage systemImageNamed:@"xmark"]];
                        closeButton.configuration = config;
                    } else {
                        [closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
                        closeButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
                        closeButton.tintColor = [UIColor labelColor];
                        closeButton.layer.cornerRadius = 20;
                    }
                    
                    [fullScreenVC.view addSubview:closeButton];
                    
                    // Use objc_runtime to add the close button action
                    IMP implementation = imp_implementationWithBlock(^(id sender) {
                        [fullScreenVC dismissViewControllerAnimated:YES completion:nil];
                    });
                    
                    class_addMethod([fullScreenVC class], @selector(closeButtonTapped:), implementation, "v@:@");
                    [closeButton addTarget:fullScreenVC action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
                    
                    // Set up constraints for close button
                    [NSLayoutConstraint activateConstraints:@[
                        [closeButton.widthAnchor constraintEqualToConstant:40],
                        [closeButton.heightAnchor constraintEqualToConstant:40],
                        [closeButton.topAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.topAnchor constant:16],
                        [closeButton.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor constant:-16]
                    ]];
                    
                    // Add view for zooming method
                    objc_setAssociatedObject(fullScreenVC, "imageViewForZooming", imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    
                    // Add viewForZooming method
                    IMP zoomImplementation = imp_implementationWithBlock(^UIView *(id self, UIScrollView *scrollView) {
                        return objc_getAssociatedObject(self, "imageViewForZooming");
                    });
                    
                    class_addMethod([fullScreenVC class], @selector(viewForZoomingInScrollView:), zoomImplementation, "@@:@");
                    
                    // Present the view controller
                    [self presentViewController:fullScreenVC animated:YES completion:nil];
                } else {
                    NSLog(@"Failed to create image from data. Data length: %lu", (unsigned long)data.length);
                    [self showErrorAlertWithMessage:@"Failed to process image attachment"];
                }
            });
        }];
        
        [task resume];
    } else {
        // For other types, try to open them in Safari or a system viewer
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showErrorAlertWithMessage:@"Could not open this attachment type"];
                });
            }
        }];
    }
}

- (void)showErrorAlertWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Helper method to add a method to a class at runtime
+ (BOOL)addAction:(SEL)selector withImplementation:(id)implementationBlock toClass:(Class)targetClass {
    if (!implementationBlock) return NO;
    
    Method oldMethod = class_getInstanceMethod(targetClass, selector);
    IMP newImp = imp_implementationWithBlock(implementationBlock);
    
    if (!oldMethod) {
        // Method doesn't exist yet - add it
        class_addMethod(targetClass, selector, newImp, "v@:@");
        return YES;
    }
    
    return NO;
}

- (void)handleImageTap:(UITapGestureRecognizer *)sender {
    if (self.featuredImageView.image == nil) return;
    
    NSLog(@"Image tapped, showing full screen view");
    
    // Create a full screen view controller
    UIViewController *fullScreenVC = [[UIViewController alloc] init];
    fullScreenVC.view.backgroundColor = [UIColor systemBackgroundColor];
    fullScreenVC.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // Create a scroll view for zooming
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.minimumZoomScale = 1.0;
    scrollView.maximumZoomScale = 3.0;
    scrollView.delegate = (id<UIScrollViewDelegate>)fullScreenVC;
    [fullScreenVC.view addSubview:scrollView];
    
    // Add an image view to the scroll view
    UIImageView *imageView = [[UIImageView alloc] init];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.image = self.featuredImageView.image;
    [scrollView addSubview:imageView];
    
    // Add close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [UIColor secondarySystemBackgroundColor];
        config.baseForegroundColor = [UIColor labelColor];
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        [config setImage:[UIImage systemImageNamed:@"xmark"]];
        closeButton.configuration = config;
    } else {
        [closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        closeButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
        closeButton.tintColor = [UIColor labelColor];
        closeButton.layer.cornerRadius = 20;
    }
    
    [fullScreenVC.view addSubview:closeButton];
    
    // Use objc_runtime to add the close button action
    IMP implementation = imp_implementationWithBlock(^(id sender) {
        [fullScreenVC dismissViewControllerAnimated:YES completion:nil];
    });
    
    class_addMethod([fullScreenVC class], @selector(closeButtonTapped:), implementation, "v@:@");
    [closeButton addTarget:fullScreenVC action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    // Set up constraints
    [NSLayoutConstraint activateConstraints:@[
        // Scroll view constraints
        [scrollView.topAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:fullScreenVC.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.bottomAnchor],
        
        // Image view constraints - size to scroll view
        [imageView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
        [imageView.heightAnchor constraintEqualToAnchor:scrollView.heightAnchor],
        [imageView.centerXAnchor constraintEqualToAnchor:scrollView.centerXAnchor],
        [imageView.centerYAnchor constraintEqualToAnchor:scrollView.centerYAnchor],
        
        // Close button constraints
        [closeButton.widthAnchor constraintEqualToConstant:40],
        [closeButton.heightAnchor constraintEqualToConstant:40],
        [closeButton.topAnchor constraintEqualToAnchor:fullScreenVC.view.safeAreaLayoutGuide.topAnchor constant:16],
        [closeButton.trailingAnchor constraintEqualToAnchor:fullScreenVC.view.trailingAnchor constant:-16]
    ]];
    
    // Add view for zooming method
    objc_setAssociatedObject(fullScreenVC, "imageViewForZooming", imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Add viewForZooming method
    IMP zoomImplementation = imp_implementationWithBlock(^UIView *(id self, UIScrollView *scrollView) {
        return objc_getAssociatedObject(self, "imageViewForZooming");
    });
    
    class_addMethod([fullScreenVC class], @selector(viewForZoomingInScrollView:), zoomImplementation, "@@:@");
    
    // Present the view controller
    [self presentViewController:fullScreenVC animated:YES completion:nil];
}

@end 