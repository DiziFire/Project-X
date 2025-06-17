#import "ProfileCreationViewController.h"
#import "ProfileManager.h"

@interface ProfileCreationViewController ()

@property (nonatomic, strong) UITextField *nameTextField;
@property (nonatomic, strong) UIButton *createButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

@end

@implementation ProfileCreationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self setupConstraints];
}

- (void)setupUI {
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"Create Profile";
    
    // Name Text Field
    self.nameTextField = [[UITextField alloc] init];
    self.nameTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameTextField.placeholder = @"Profile Name";
    self.nameTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.nameTextField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.nameTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.nameTextField.returnKeyType = UIReturnKeyDone;
    self.nameTextField.delegate = self;
    [self.view addSubview:self.nameTextField];
    
    // Create Button
    self.createButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.createButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.createButton setTitle:@"Create" forState:UIControlStateNormal];
    [self.createButton addTarget:self action:@selector(createButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.createButton.enabled = NO;
    [self.view addSubview:self.createButton];
    
    // Cancel Button
    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.cancelButton addTarget:self action:@selector(cancelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cancelButton];
    
    // Activity Indicator
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.activityIndicator];
    
    // Add tap gesture to dismiss keyboard
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    [self.view addGestureRecognizer:tapGesture];
}

- (void)setupConstraints {
    NSLayoutConstraint *nameTextFieldTop = [self.nameTextField.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20];
    NSLayoutConstraint *nameTextFieldLeading = [self.nameTextField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20];
    NSLayoutConstraint *nameTextFieldTrailing = [self.nameTextField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20];
    
    NSLayoutConstraint *createButtonTop = [self.createButton.topAnchor constraintEqualToAnchor:self.nameTextField.bottomAnchor constant:20];
    NSLayoutConstraint *createButtonLeading = [self.createButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20];
    NSLayoutConstraint *createButtonTrailing = [self.createButton.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-10];
    
    NSLayoutConstraint *cancelButtonTop = [self.cancelButton.topAnchor constraintEqualToAnchor:self.nameTextField.bottomAnchor constant:20];
    NSLayoutConstraint *cancelButtonLeading = [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:10];
    NSLayoutConstraint *cancelButtonTrailing = [self.cancelButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20];
    
    NSLayoutConstraint *activityIndicatorCenterX = [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor];
    NSLayoutConstraint *activityIndicatorCenterY = [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor];
    
    [NSLayoutConstraint activateConstraints:@[
        nameTextFieldTop,
        nameTextFieldLeading,
        nameTextFieldTrailing,
        createButtonTop,
        createButtonLeading,
        createButtonTrailing,
        cancelButtonTop,
        cancelButtonLeading,
        cancelButtonTrailing,
        activityIndicatorCenterX,
        activityIndicatorCenterY
    ]];
}

#pragma mark - Actions

- (void)createButtonTapped {
    NSString *profileName = [self.nameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (profileName.length == 0) {
        [self showAlertWithTitle:@"Invalid Name" message:@"Please enter a valid profile name."];
        return;
    }
    
    [self.activityIndicator startAnimating];
    self.createButton.enabled = NO;
    self.cancelButton.enabled = NO;
    
    // Create profile using ProfileManager
    Profile *newProfile = [[Profile alloc] initWithName:profileName iconName:@"default_profile"];
    [[ProfileManager sharedManager] createProfile:newProfile completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.activityIndicator stopAnimating];
            self.createButton.enabled = YES;
            self.cancelButton.enabled = YES;
            
            if (success) {
                if ([self.delegate respondsToSelector:@selector(profileCreationViewController:didCreateProfile:)]) {
                    [self.delegate profileCreationViewController:self didCreateProfile:profileName];
                }
                [self dismissViewControllerAnimated:YES completion:nil];
            } else {
                [self showAlertWithTitle:@"Error" message:error.localizedDescription ?: @"Failed to create profile."];
            }
        });
    }];
}

- (void)cancelButtonTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidChangeSelection:(UITextField *)textField {
    NSString *trimmedText = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.createButton.enabled = trimmedText.length > 0;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (self.createButton.enabled) {
        [self createButtonTapped];
    }
    return YES;
}

#pragma mark - Helper Methods

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end 