#import <UIKit/UIKit.h>
#import "APIManager.h"

// Disable deprecation warnings for this file
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface CreateTicketViewController : UIViewController <UIPickerViewDataSource, UIPickerViewDelegate, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, copy) void (^ticketCreatedHandler)(void);
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *subjectField;
@property (nonatomic, strong) UITextView *contentTextView;
@property (nonatomic, strong) UILabel *categoryLabel;
@property (nonatomic, strong) UIButton *categoryButton;
@property (nonatomic, strong) UIPickerView *categoryPicker;
@property (nonatomic, strong) UIPickerView *subcategoryPicker;
@property (nonatomic, strong) UIView *pickerContainerView;
@property (nonatomic, strong) UISegmentedControl *prioritySegment;
@property (nonatomic, strong) UILabel *priorityLabel;
@property (nonatomic, strong) UIButton *submitButton;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) NSArray *categories;
@property (nonatomic, strong) NSArray *subcategories;
@property (nonatomic, strong) NSNumber *selectedCategoryId;
@property (nonatomic, strong) NSNumber *selectedSubcategoryId;
@property (nonatomic, strong) NSString *selectedCategoryName;
@property (nonatomic, strong) NSString *selectedSubcategoryName;
@property (nonatomic, assign) BOOL isPickerVisible;
@property (nonatomic, assign) BOOL isSubcategoryPickerVisible;

// Subcategory properties
@property (nonatomic, strong) UILabel *subcategoryLabel;
@property (nonatomic, strong) UIButton *subcategoryButton;
@property (nonatomic, strong) UIView *subcategoryPickerContainerView;

// Attachment related properties
@property (nonatomic, strong) UIButton *attachmentButton;
@property (nonatomic, strong) UIView *attachmentsContainer;
@property (nonatomic, strong) NSMutableArray<UIImage *> *attachments;
@property (nonatomic, strong) NSMutableArray<UIView *> *attachmentViews;

@end

@implementation CreateTicketViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Create Support Ticket";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Initialize properties
    self.categories = @[];
    self.subcategories = @[];
    self.isPickerVisible = NO;
    self.isSubcategoryPickerVisible = NO;
    
    // Initialize attachment arrays
    self.attachments = [NSMutableArray array];
    self.attachmentViews = [NSMutableArray array];
    
    // Navigation bar buttons
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
    
    [self setupUI];
    [self loadCategories];
    
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
    // Scroll view
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:self.scrollView];
    
    // Content container
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.backgroundColor = [UIColor systemBackgroundColor];
    [self.scrollView addSubview:contentView];
    
    // Create section title style
    UIFont *sectionFont = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    UIColor *sectionColor = [UIColor secondaryLabelColor];
    
    // Subject field with floating label style
    UIView *subjectContainer = [[UIView alloc] init];
    subjectContainer.translatesAutoresizingMaskIntoConstraints = NO;
    subjectContainer.layer.cornerRadius = 10;
    subjectContainer.layer.borderWidth = 1;
    subjectContainer.layer.borderColor = [UIColor systemGray5Color].CGColor;
    subjectContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [contentView addSubview:subjectContainer];
    
    UILabel *subjectLabel = [[UILabel alloc] init];
    subjectLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subjectLabel.text = @"Subject";
    subjectLabel.font = sectionFont;
    subjectLabel.textColor = sectionColor;
    [contentView addSubview:subjectLabel];
    
    self.subjectField = [[UITextField alloc] init];
    self.subjectField.translatesAutoresizingMaskIntoConstraints = NO;
    self.subjectField.placeholder = @"Enter ticket subject";
    self.subjectField.borderStyle = UITextBorderStyleNone;
    self.subjectField.returnKeyType = UIReturnKeyNext;
    self.subjectField.textColor = [UIColor labelColor];
    self.subjectField.font = [UIFont systemFontOfSize:16];
    self.subjectField.backgroundColor = [UIColor clearColor];
    [self.subjectField addTarget:self action:@selector(subjectFieldDidEndOnExit:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [subjectContainer addSubview:self.subjectField];
    
    // Category section
    self.categoryLabel = [[UILabel alloc] init];
    self.categoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.categoryLabel.text = @"Category";
    self.categoryLabel.font = sectionFont;
    self.categoryLabel.textColor = sectionColor;
    [contentView addSubview:self.categoryLabel];
    
    // Category button
    self.categoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.categoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.categoryButton setTitle:@"Select Category" forState:UIControlStateNormal];
    self.categoryButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.categoryButton.layer.cornerRadius = 10;
    self.categoryButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.categoryButton.tintColor = [UIColor labelColor];
    
    // Add dropdown icon
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium];
    UIImage *chevronImage = [UIImage systemImageNamed:@"chevron.down" withConfiguration:config];
    [self.categoryButton setImage:chevronImage forState:UIControlStateNormal];
    self.categoryButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.categoryButton.imageEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
    
    // Set button insets using the helper method
    [self setButtonInsets:self.categoryButton];
    
    [self.categoryButton addTarget:self action:@selector(categoryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.categoryButton];
    
    // Subcategory section
    self.subcategoryLabel = [[UILabel alloc] init];
    self.subcategoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subcategoryLabel.text = @"Subcategory";
    self.subcategoryLabel.font = sectionFont;
    self.subcategoryLabel.textColor = sectionColor;
    [contentView addSubview:self.subcategoryLabel];
    
    // Subcategory button
    self.subcategoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.subcategoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.subcategoryButton setTitle:@"Select Subcategory" forState:UIControlStateNormal];
    self.subcategoryButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.subcategoryButton.layer.cornerRadius = 10;
    self.subcategoryButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.subcategoryButton.tintColor = [UIColor labelColor];
    
    // Add dropdown icon
    [self.subcategoryButton setImage:chevronImage forState:UIControlStateNormal];
    self.subcategoryButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.subcategoryButton.imageEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 0);
    
    // Set button insets using the helper method
    [self setButtonInsets:self.subcategoryButton];
    
    // Initially disable subcategory button until a category is selected
    self.subcategoryButton.enabled = NO;
    self.subcategoryButton.alpha = 0.5;
    
    [self.subcategoryButton addTarget:self action:@selector(subcategoryButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.subcategoryButton];
    
    // Priority section
    self.priorityLabel = [[UILabel alloc] init];
    self.priorityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.priorityLabel.text = @"Priority";
    self.priorityLabel.font = sectionFont;
    self.priorityLabel.textColor = sectionColor;
    [contentView addSubview:self.priorityLabel];
    
    // Priority segment with modern styling
    self.prioritySegment = [[UISegmentedControl alloc] initWithItems:@[@"Low", @"Medium", @"High"]];
    self.prioritySegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.prioritySegment.selectedSegmentIndex = 1; // Medium by default
    self.prioritySegment.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [contentView addSubview:self.prioritySegment];
    
    // Description section
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descriptionLabel.text = @"Description";
    descriptionLabel.font = sectionFont;
    descriptionLabel.textColor = sectionColor;
    [contentView addSubview:descriptionLabel];
    
    // Content text view container
    UIView *textViewContainer = [[UIView alloc] init];
    textViewContainer.translatesAutoresizingMaskIntoConstraints = NO;
    textViewContainer.layer.cornerRadius = 10;
    textViewContainer.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [contentView addSubview:textViewContainer];
    
    // Content text view
    self.contentTextView = [[UITextView alloc] init];
    self.contentTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentTextView.layer.cornerRadius = 10;
    self.contentTextView.delegate = self;
    self.contentTextView.font = [UIFont systemFontOfSize:16];
    self.contentTextView.backgroundColor = [UIColor clearColor];
    self.contentTextView.textColor = [UIColor labelColor];
    self.contentTextView.textContainerInset = UIEdgeInsetsMake(12, 8, 12, 8);
    [textViewContainer addSubview:self.contentTextView];
    
    // Placeholder for text view
    UILabel *placeholderLabel = [[UILabel alloc] init];
    placeholderLabel.text = @"Describe your issue";
    placeholderLabel.font = [UIFont systemFontOfSize:16];
    placeholderLabel.textColor = [UIColor placeholderTextColor];
    [placeholderLabel sizeToFit];
    placeholderLabel.frame = CGRectMake(12, 12, placeholderLabel.frame.size.width, placeholderLabel.frame.size.height);
    placeholderLabel.tag = 999;
    [self.contentTextView addSubview:placeholderLabel];
    
    // Attachments section
    UILabel *attachmentsLabel = [[UILabel alloc] init];
    attachmentsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    attachmentsLabel.text = @"Attachments (Optional, Max 3)";
    attachmentsLabel.font = sectionFont;
    attachmentsLabel.textColor = sectionColor;
    [contentView addSubview:attachmentsLabel];
    
    // Attachment button
    self.attachmentButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.attachmentButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.attachmentButton setTitle:@" Add Image" forState:UIControlStateNormal];
    UIImage *photoImage = [UIImage systemImageNamed:@"photo.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium]];
    [self.attachmentButton setImage:photoImage forState:UIControlStateNormal];
    self.attachmentButton.layer.cornerRadius = 10;
    self.attachmentButton.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    [self.attachmentButton addTarget:self action:@selector(addAttachment) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.attachmentButton];
    
    // Attachments container
    self.attachmentsContainer = [[UIView alloc] init];
    self.attachmentsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentsContainer.backgroundColor = [UIColor clearColor];
    [contentView addSubview:self.attachmentsContainer];
    
    // Submit button
    self.submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.submitButton setTitle:@"Submit Ticket" forState:UIControlStateNormal];
    self.submitButton.backgroundColor = [UIColor systemBlueColor];
    self.submitButton.tintColor = [UIColor whiteColor];
    self.submitButton.layer.cornerRadius = 12;
    self.submitButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    
    // Add shadow to button
    self.submitButton.layer.shadowColor = [UIColor systemBlueColor].CGColor;
    self.submitButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.submitButton.layer.shadowRadius = 4;
    self.submitButton.layer.shadowOpacity = 0.3;
    
    [self.submitButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:self.submitButton];
    
    // Loading indicator
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.color = [UIColor whiteColor];
    [contentView addSubview:self.loadingIndicator];
    
    // Picker container view with rounded corners and blur effect
    self.pickerContainerView = [[UIView alloc] init];
    self.pickerContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add blur effect for a modern look
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pickerContainerView addSubview:blurView];
    
    // Set corner radius with mask
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, self.view.frame.size.width, 260) 
                                          byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight 
                                                cornerRadii:CGSizeMake(15, 15)].CGPath;
    self.pickerContainerView.layer.mask = maskLayer;
    self.pickerContainerView.hidden = YES;
    
    // Add toolbar with modern style
    UIToolbar *toolbar = [[UIToolbar alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.barTintColor = nil; // Let system handle the color
    toolbar.backgroundColor = nil; // Let system handle the color
    toolbar.clipsToBounds = YES;
    [self.pickerContainerView addSubview:toolbar];
    
    // Add picker view
    self.categoryPicker = [[UIPickerView alloc] init];
    self.categoryPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.categoryPicker.dataSource = self;
    self.categoryPicker.delegate = self;
    [self.pickerContainerView addSubview:self.categoryPicker];
    
    [self.view addSubview:self.pickerContainerView];
    
    // Setup layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Scroll view
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        
        // Content view
        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
        
        // Subject label
        [subjectLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:24],
        [subjectLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        [subjectLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24],
        
        // Subject container
        [subjectContainer.topAnchor constraintEqualToAnchor:subjectLabel.bottomAnchor constant:8],
        [subjectContainer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [subjectContainer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [subjectContainer.heightAnchor constraintEqualToConstant:48],
        
        // Subject field
        [self.subjectField.leadingAnchor constraintEqualToAnchor:subjectContainer.leadingAnchor constant:15],
        [self.subjectField.trailingAnchor constraintEqualToAnchor:subjectContainer.trailingAnchor constant:-15],
        [self.subjectField.topAnchor constraintEqualToAnchor:subjectContainer.topAnchor],
        [self.subjectField.bottomAnchor constraintEqualToAnchor:subjectContainer.bottomAnchor],
        
        // Category label
        [self.categoryLabel.topAnchor constraintEqualToAnchor:subjectContainer.bottomAnchor constant:24],
        [self.categoryLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        
        // Category button
        [self.categoryButton.topAnchor constraintEqualToAnchor:self.categoryLabel.bottomAnchor constant:8],
        [self.categoryButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.categoryButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.categoryButton.heightAnchor constraintEqualToConstant:48],
        
        // Subcategory label
        [self.subcategoryLabel.topAnchor constraintEqualToAnchor:self.categoryButton.bottomAnchor constant:24],
        [self.subcategoryLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        
        // Subcategory button
        [self.subcategoryButton.topAnchor constraintEqualToAnchor:self.subcategoryLabel.bottomAnchor constant:8],
        [self.subcategoryButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.subcategoryButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.subcategoryButton.heightAnchor constraintEqualToConstant:48],
        
        // Priority label
        [self.priorityLabel.topAnchor constraintEqualToAnchor:self.subcategoryButton.bottomAnchor constant:24],
        [self.priorityLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        
        // Priority segment
        [self.prioritySegment.topAnchor constraintEqualToAnchor:self.priorityLabel.bottomAnchor constant:8],
        [self.prioritySegment.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.prioritySegment.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.prioritySegment.heightAnchor constraintEqualToConstant:40],
        
        // Description label
        [descriptionLabel.topAnchor constraintEqualToAnchor:self.prioritySegment.bottomAnchor constant:24],
        [descriptionLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        
        // Text view container
        [textViewContainer.topAnchor constraintEqualToAnchor:descriptionLabel.bottomAnchor constant:8],
        [textViewContainer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [textViewContainer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [textViewContainer.heightAnchor constraintEqualToConstant:180],
        
        // Content text view
        [self.contentTextView.topAnchor constraintEqualToAnchor:textViewContainer.topAnchor],
        [self.contentTextView.leadingAnchor constraintEqualToAnchor:textViewContainer.leadingAnchor],
        [self.contentTextView.trailingAnchor constraintEqualToAnchor:textViewContainer.trailingAnchor],
        [self.contentTextView.bottomAnchor constraintEqualToAnchor:textViewContainer.bottomAnchor],
        
        // Attachments label
        [attachmentsLabel.topAnchor constraintEqualToAnchor:textViewContainer.bottomAnchor constant:24],
        [attachmentsLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        [attachmentsLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // Attachment button
        [self.attachmentButton.topAnchor constraintEqualToAnchor:attachmentsLabel.bottomAnchor constant:12],
        [self.attachmentButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.attachmentButton.heightAnchor constraintEqualToConstant:40],
        [self.attachmentButton.widthAnchor constraintEqualToConstant:130],
        
        // Attachments container
        [self.attachmentsContainer.topAnchor constraintEqualToAnchor:self.attachmentButton.bottomAnchor constant:12],
        [self.attachmentsContainer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [self.attachmentsContainer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [self.attachmentsContainer.heightAnchor constraintEqualToConstant:100],
        
        // Submit button
        [self.submitButton.topAnchor constraintEqualToAnchor:self.attachmentsContainer.bottomAnchor constant:30],
        [self.submitButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.submitButton.widthAnchor constraintEqualToConstant:200],
        [self.submitButton.heightAnchor constraintEqualToConstant:50],
        [self.submitButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-30],
        
        // Loading indicator
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.submitButton.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.submitButton.centerYAnchor],
        
        // Blur effect view
        [blurView.topAnchor constraintEqualToAnchor:self.pickerContainerView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:self.pickerContainerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:self.pickerContainerView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:self.pickerContainerView.bottomAnchor],
        
        // Picker container view
        [self.pickerContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pickerContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pickerContainerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.pickerContainerView.heightAnchor constraintEqualToConstant:260],
        
        // Toolbar
        [toolbar.topAnchor constraintEqualToAnchor:self.pickerContainerView.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.pickerContainerView.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.pickerContainerView.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:44],
        
        // Picker view
        [self.categoryPicker.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.categoryPicker.leadingAnchor constraintEqualToAnchor:self.pickerContainerView.leadingAnchor],
        [self.categoryPicker.trailingAnchor constraintEqualToAnchor:self.pickerContainerView.trailingAnchor],
        [self.categoryPicker.bottomAnchor constraintEqualToAnchor:self.pickerContainerView.bottomAnchor],
    ]];
}

#pragma mark - API calls

- (void)loadCategories {
    [self.loadingIndicator startAnimating];
    
    [[APIManager sharedManager] getTicketCategories:^(NSArray *categories, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                               message:@"Failed to load ticket categories. Please try again."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }
            
            self.categories = categories;
            [self.categoryPicker reloadAllComponents];
            
            // Select first category if available
            if (self.categories.count > 0) {
                NSDictionary *firstCategory = self.categories[0];
                self.selectedCategoryId = firstCategory[@"id"];
                self.selectedCategoryName = firstCategory[@"name"];
                [self.categoryButton setTitle:self.selectedCategoryName forState:UIControlStateNormal];
                
                // Load subcategories for the first category
                [self loadSubcategoriesForCategory:self.selectedCategoryId];
            }
        });
    }];
}

- (void)loadSubcategoriesForCategory:(NSNumber *)categoryId {
    [self.loadingIndicator startAnimating];
    
    [[APIManager sharedManager] getSubcategoriesForCategory:categoryId completion:^(NSArray *subcategories, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            
            if (error) {
                // If there's a server error, display a more detailed message in debug builds
                NSString *errorMessage = nil;
                #ifdef DEBUG
                errorMessage = [NSString stringWithFormat:@"Failed to load subcategories. Error: %@", error.localizedDescription];
                #else
                errorMessage = @"Failed to load subcategories. Please try again.";
                #endif
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                              message:errorMessage
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
                // Even with an error, update the UI
                self.subcategories = @[];
                self.selectedSubcategoryId = nil;
                self.selectedSubcategoryName = nil;
                [self.subcategoryButton setTitle:@"No subcategories available" forState:UIControlStateNormal];
                self.subcategoryButton.enabled = NO;
                self.subcategoryButton.alpha = 0.5;
                
                return;
            }
            
            self.subcategories = subcategories ?: @[];
            
            // Enable subcategory button if there are subcategories available
            BOOL hasSubcategories = (subcategories && subcategories.count > 0);
            
            self.subcategoryButton.enabled = hasSubcategories;
            self.subcategoryButton.alpha = hasSubcategories ? 1.0 : 0.5;
            
            // Update button text
            if (!hasSubcategories) {
                [self.subcategoryButton setTitle:@"No subcategories available" forState:UIControlStateNormal];
                self.selectedSubcategoryId = nil;
                self.selectedSubcategoryName = nil;
            } else {
                [self.subcategoryButton setTitle:@"Select Subcategory" forState:UIControlStateNormal];
                [self.subcategoryPicker reloadAllComponents];
                
                // Select the first subcategory by default
                if (self.subcategories.count > 0) {
                    NSDictionary *firstSubcategory = self.subcategories[0];
                    self.selectedSubcategoryId = firstSubcategory[@"id"];
                    self.selectedSubcategoryName = firstSubcategory[@"name"];
                    [self.subcategoryButton setTitle:self.selectedSubcategoryName forState:UIControlStateNormal];
                }
            }
        });
    }];
}

- (void)submitTicket {
    // Validate input
    if (self.subjectField.text.length == 0) {
        [self showErrorAlert:@"Please enter a subject for your ticket."];
        return;
    }
    
    if (self.contentTextView.text.length == 0 || [self.contentTextView.text isEqualToString:@"Describe your issue"]) {
        [self showErrorAlert:@"Please describe your issue."];
        return;
    }
    
    if (!self.selectedCategoryId) {
        [self showErrorAlert:@"Please select a category."];
        return;
    }
    
    // Get priority
    NSArray *priorities = @[@"low", @"medium", @"high"];
    NSString *priority = priorities[self.prioritySegment.selectedSegmentIndex];
    
    // Show loading
    [self.loadingIndicator startAnimating];
    self.submitButton.hidden = YES;
    
    // Submit ticket with attachments and subcategory
    [[APIManager sharedManager] createTicketWithSubcategory:self.subjectField.text 
                                                   content:self.contentTextView.text 
                                                categoryId:self.selectedCategoryId 
                                             subcategoryId:self.selectedSubcategoryId
                                                  priority:priority 
                                               attachments:self.attachments.count > 0 ? self.attachments : nil
                                                completion:^(BOOL success, NSString *message, NSNumber *ticketId, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            self.submitButton.hidden = NO;
            
            if (error || !success) {
                NSString *errorMessage = message ?: @"Failed to create ticket. Please try again.";
                [self showErrorAlert:errorMessage];
                return;
            }
            
            // Show success and dismiss
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success"
                                                                           message:@"Your support ticket has been submitted successfully."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                if (self.ticketCreatedHandler) {
                    self.ticketCreatedHandler();
                }
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

#pragma mark - Actions

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)subjectFieldDidEndOnExit:(UITextField *)textField {
    [self.contentTextView becomeFirstResponder];
}

- (void)categoryButtonTapped {
    [self dismissKeyboard];
    
    // Show category picker
    self.pickerContainerView.hidden = NO;
    self.isPickerVisible = YES;
    
    // Animate picker appearance
    CGRect pickerFrame = self.pickerContainerView.frame;
    pickerFrame.origin.y = self.view.frame.size.height;
    self.pickerContainerView.frame = pickerFrame;
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect newFrame = self.pickerContainerView.frame;
        newFrame.origin.y = self.view.frame.size.height - newFrame.size.height;
        self.pickerContainerView.frame = newFrame;
    }];
}

- (void)doneButtonTapped {
    // Hide picker
    [UIView animateWithDuration:0.3 animations:^{
        CGRect pickerFrame = self.pickerContainerView.frame;
        pickerFrame.origin.y = self.view.frame.size.height;
        self.pickerContainerView.frame = pickerFrame;
    } completion:^(BOOL finished) {
        self.pickerContainerView.hidden = YES;
        self.isPickerVisible = NO;
    }];
    
    // Update selected category
    if (self.categories.count > 0) {
        NSInteger selectedRow = [self.categoryPicker selectedRowInComponent:0];
        NSDictionary *selectedCategory = self.categories[selectedRow];
        self.selectedCategoryId = selectedCategory[@"id"];
        self.selectedCategoryName = selectedCategory[@"name"];
        [self.categoryButton setTitle:self.selectedCategoryName forState:UIControlStateNormal];
        
        // Reset subcategory selection
        self.selectedSubcategoryId = nil;
        self.selectedSubcategoryName = nil;
        [self.subcategoryButton setTitle:@"Select Subcategory" forState:UIControlStateNormal];
        
        // Load subcategories for the selected category
        [self loadSubcategoriesForCategory:self.selectedCategoryId];
    }
}

- (void)subcategoryButtonTapped {
    if (self.isPickerVisible) {
        // Hide category picker first
        [self doneButtonTapped];
    }
    
    // Setup subcategory picker if not already done
    if (!self.subcategoryPickerContainerView) {
        [self setupSubcategoryPickerView];
    }
    
    [self toggleSubcategoryPicker];
}

- (void)toggleSubcategoryPicker {
    self.isSubcategoryPickerVisible = !self.isSubcategoryPickerVisible;
    
    if (self.isSubcategoryPickerVisible) {
        // Show the picker
        self.subcategoryPickerContainerView.hidden = NO;
        
        CGRect frame = self.subcategoryPickerContainerView.frame;
        frame.origin.y = self.view.frame.size.height;
        self.subcategoryPickerContainerView.frame = frame;
        
        [UIView animateWithDuration:0.3 animations:^{
            CGRect frame = self.subcategoryPickerContainerView.frame;
            frame.origin.y = self.view.frame.size.height - frame.size.height;
            self.subcategoryPickerContainerView.frame = frame;
        }];
    } else {
        // Hide the picker
        [UIView animateWithDuration:0.3 animations:^{
            CGRect frame = self.subcategoryPickerContainerView.frame;
            frame.origin.y = self.view.frame.size.height;
            self.subcategoryPickerContainerView.frame = frame;
        } completion:^(BOOL finished) {
            self.subcategoryPickerContainerView.hidden = YES;
        }];
    }
}

- (void)doneSubcategoryPickerTapped {
    // Get selected subcategory
    if (self.subcategories.count > 0) {
        NSInteger selectedRow = [self.subcategoryPicker selectedRowInComponent:0];
        NSDictionary *selectedSubcategory = self.subcategories[selectedRow];
        self.selectedSubcategoryId = selectedSubcategory[@"id"];
        self.selectedSubcategoryName = selectedSubcategory[@"name"];
        [self.subcategoryButton setTitle:self.selectedSubcategoryName forState:UIControlStateNormal];
    }
    
    [self toggleSubcategoryPicker];
}

- (void)submitTapped {
    [self dismissKeyboard];
    [self submitTicket];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
    
    if (self.isPickerVisible) {
        [self doneButtonTapped];
    }
    
    if (self.isSubcategoryPickerVisible) {
        [self toggleSubcategoryPicker];
    }
}

- (void)toggleCategoryPicker {
    self.isPickerVisible = !self.isPickerVisible;
    
    if (self.isPickerVisible) {
        // Show the picker
        self.pickerContainerView.hidden = NO;
        [UIView animateWithDuration:0.3 animations:^{
            CGRect frame = self.pickerContainerView.frame;
            frame.origin.y = self.view.frame.size.height - frame.size.height;
            self.pickerContainerView.frame = frame;
        }];
    } else {
        // Hide the picker
        [UIView animateWithDuration:0.3 animations:^{
            CGRect frame = self.pickerContainerView.frame;
            frame.origin.y = self.view.frame.size.height;
            self.pickerContainerView.frame = frame;
        } completion:^(BOOL finished) {
            self.pickerContainerView.hidden = YES;
        }];
    }
}

#pragma mark - Helper methods

- (void)showErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setButtonInsets:(UIButton *)button {
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.contentInsets = NSDirectionalEdgeInsetsMake(10, 15, 10, 15);
        button.configuration = config;
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        button.contentEdgeInsets = UIEdgeInsetsMake(10, 15, 10, 15);
        #pragma clang diagnostic pop
    }
}

#pragma mark - UIPickerViewDataSource methods

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    if (pickerView == self.subcategoryPicker) {
        return self.subcategories.count;
    }
    return self.categories.count;
}

#pragma mark - UIPickerViewDelegate methods

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    if (pickerView == self.subcategoryPicker) {
        if (row < self.subcategories.count) {
            NSDictionary *subcategory = self.subcategories[row];
            return subcategory[@"name"];
        }
        return @"";
    } else {
        if (row < self.categories.count) {
            NSDictionary *category = self.categories[row];
            return category[@"name"];
        }
        return @"";
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

#pragma mark - Keyboard handling

- (void)keyboardWillShow:(NSNotification *)notification {
    if (self.isPickerVisible) {
        return;
    }
    
    NSDictionary *keyboardInfo = [notification userInfo];
    CGRect keyboardFrame = [[keyboardInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval animationDuration = [[keyboardInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardFrame.size.height, 0.0);
    
    [UIView animateWithDuration:animationDuration animations:^{
        self.scrollView.contentInset = contentInsets;
        self.scrollView.scrollIndicatorInsets = contentInsets;
        
        // Scroll to active text field
        UIView *activeField = nil;
        if ([self.subjectField isFirstResponder]) {
            activeField = self.subjectField;
        } else if ([self.contentTextView isFirstResponder]) {
            activeField = self.contentTextView;
        }
        
        if (activeField) {
            CGRect activeRect = [self.scrollView convertRect:activeField.frame fromView:activeField.superview];
            activeRect.size.height += 20; // Add some padding
            [self.scrollView scrollRectToVisible:activeRect animated:YES];
        }
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    if (self.isPickerVisible) {
        return;
    }
    
    NSDictionary *keyboardInfo = [notification userInfo];
    NSTimeInterval animationDuration = [[keyboardInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    [UIView animateWithDuration:animationDuration animations:^{
        self.scrollView.contentInset = UIEdgeInsetsZero;
        self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }];
}

#pragma mark - Attachment methods

- (void)addAttachment {
    // Check if we already have 3 attachments
    if (self.attachments.count >= 3) {
        [self showErrorAlert:@"You can only add up to 3 images."];
        return;
    }
    
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePicker.allowsEditing = YES;
    [self presentViewController:imagePicker animated:YES completion:nil];
}

- (void)removeAttachment:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < self.attachments.count && index < self.attachmentViews.count) {
        [self.attachments removeObjectAtIndex:index];
        
        // Remove the view from container
        UIView *viewToRemove = self.attachmentViews[index];
        [viewToRemove removeFromSuperview];
        [self.attachmentViews removeObjectAtIndex:index];
        
        // Refresh attachment views to update layout
        [self refreshAttachmentViews];
    }
}

- (void)refreshAttachmentViews {
    // Clear all views
    for (UIView *view in self.attachmentViews) {
        [view removeFromSuperview];
    }
    [self.attachmentViews removeAllObjects];
    
    // Rebuild views
    CGFloat spacing = 10;
    CGFloat size = 80;
    
    for (NSInteger i = 0; i < self.attachments.count; i++) {
        UIView *attachmentView = [[UIView alloc] init];
        attachmentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.attachmentsContainer addSubview:attachmentView];
        [self.attachmentViews addObject:attachmentView];
        
        // Create image view
        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        imageView.layer.cornerRadius = 5;
        imageView.image = self.attachments[i];
        [attachmentView addSubview:imageView];
        
        // Create remove button
        UIButton *removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        removeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [removeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        removeButton.tintColor = [UIColor systemRedColor];
        removeButton.tag = i;
        [removeButton addTarget:self action:@selector(removeAttachment:) forControlEvents:UIControlEventTouchUpInside];
        [attachmentView addSubview:removeButton];
        
        // Set constraints
        [NSLayoutConstraint activateConstraints:@[
            [attachmentView.leadingAnchor constraintEqualToAnchor:self.attachmentsContainer.leadingAnchor constant:i * (size + spacing)],
            [attachmentView.topAnchor constraintEqualToAnchor:self.attachmentsContainer.topAnchor],
            [attachmentView.widthAnchor constraintEqualToConstant:size],
            [attachmentView.heightAnchor constraintEqualToConstant:size],
            
            [imageView.leadingAnchor constraintEqualToAnchor:attachmentView.leadingAnchor],
            [imageView.topAnchor constraintEqualToAnchor:attachmentView.topAnchor],
            [imageView.trailingAnchor constraintEqualToAnchor:attachmentView.trailingAnchor],
            [imageView.bottomAnchor constraintEqualToAnchor:attachmentView.bottomAnchor],
            
            [removeButton.topAnchor constraintEqualToAnchor:attachmentView.topAnchor constant:-5],
            [removeButton.trailingAnchor constraintEqualToAnchor:attachmentView.trailingAnchor constant:5],
            [removeButton.widthAnchor constraintEqualToConstant:25],
            [removeButton.heightAnchor constraintEqualToConstant:25],
        ]];
    }
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
        
        // Add to attachments array
        [self.attachments addObject:processedImage];
        
        // Update UI
        [self refreshAttachmentViews];
        
        // Disable add button if we have 3 attachments
        self.attachmentButton.enabled = (self.attachments.count < 3);
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

- (void)setupSubcategoryPickerView {
    // Create picker container view with blur effect
    self.subcategoryPickerContainerView = [[UIView alloc] init];
    self.subcategoryPickerContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Add blur effect for a modern look
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.subcategoryPickerContainerView addSubview:blurView];
    
    // Set corner radius with mask
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, self.view.frame.size.width, 260) 
                                          byRoundingCorners:UIRectCornerTopLeft | UIRectCornerTopRight 
                                                cornerRadii:CGSizeMake(15, 15)].CGPath;
    self.subcategoryPickerContainerView.layer.mask = maskLayer;
    self.subcategoryPickerContainerView.hidden = YES;
    
    [self.view addSubview:self.subcategoryPickerContainerView];
    
    // Add toolbar with modern style
    UIToolbar *toolbar = [[UIToolbar alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.barTintColor = nil; // Let system handle the color
    toolbar.backgroundColor = nil; // Let system handle the color
    toolbar.clipsToBounds = YES;
    [self.subcategoryPickerContainerView addSubview:toolbar];
    
    UIBarButtonItem *titleItem = [[UIBarButtonItem alloc] initWithTitle:@"Select Subcategory" style:UIBarButtonItemStylePlain target:nil action:nil];
    titleItem.tintColor = [UIColor labelColor];
    
    UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(doneSubcategoryPickerTapped)];
    doneButton.tintColor = [UIColor systemBlueColor];
    
    toolbar.items = @[flexSpace, titleItem, flexSpace, doneButton];
    
    // Create picker view
    self.subcategoryPicker = [[UIPickerView alloc] init];
    self.subcategoryPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.subcategoryPicker.dataSource = self;
    self.subcategoryPicker.delegate = self;
    [self.subcategoryPickerContainerView addSubview:self.subcategoryPicker];
    
    // Constraints for blur view
    [NSLayoutConstraint activateConstraints:@[
        [blurView.topAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.topAnchor],
        [blurView.leadingAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.trailingAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.bottomAnchor],
    ]];
    
    // Constraints for toolbar
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:44]
    ]];
    
    // Constraints for picker view
    [NSLayoutConstraint activateConstraints:@[
        [self.subcategoryPicker.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.subcategoryPicker.leadingAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.leadingAnchor],
        [self.subcategoryPicker.trailingAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.trailingAnchor],
        [self.subcategoryPicker.bottomAnchor constraintEqualToAnchor:self.subcategoryPickerContainerView.bottomAnchor],
        [self.subcategoryPicker.heightAnchor constraintEqualToConstant:216]
    ]];
    
    // Constraints for picker container view
    [NSLayoutConstraint activateConstraints:@[
        [self.subcategoryPickerContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.subcategoryPickerContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.subcategoryPickerContainerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.subcategoryPickerContainerView.heightAnchor constraintEqualToConstant:260]
    ]];
}

@end

// Restore deprecation warnings
#pragma clang diagnostic pop