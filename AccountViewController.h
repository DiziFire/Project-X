#import <UIKit/UIKit.h>

#import "TelegramUI.h"
#import "PlanSliderView.h"

@interface AccountViewController : UIViewController <UITextFieldDelegate, PlanSliderViewDelegate>

// Core properties
@property (nonatomic, assign, getter=isLoggedIn, setter=setLoggedIn:) BOOL loggedIn;
@property (nonatomic, strong) NSString *authToken;
@property (nonatomic, strong) NSDictionary *userData;

// Connectivity properties
@property (nonatomic, strong) UILabel *connectionStatusLabel;
@property (nonatomic, strong) NSURLSessionDataTask *connectivityTask;
@property (nonatomic, strong) NSTimer *connectivityTimer;
@property (nonatomic, assign) NSTimeInterval lastPingTime;

// UI Elements
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *loginView;
@property (nonatomic, strong) UIView *userInfoCard;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *signupButton;
@property (nonatomic, strong) UIButton *logoutButton;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

// User info elements
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UILabel *userIdLabel;
@property (nonatomic, strong) UILabel *emailValueLabel;
@property (nonatomic, strong) UILabel *planValueLabel;
@property (nonatomic, strong) UILabel *systemValueLabel;
@property (nonatomic, strong) UILabel *planTitleLabel;
@property (nonatomic, strong) UILabel *planNameLabel;
@property (nonatomic, strong) UILabel *planExpiryLabel;
@property (nonatomic, strong) UILabel *appVersionValueLabel;
@property (nonatomic, strong) UILabel *deviceLimitTitleLabel;
@property (nonatomic, strong) UILabel *deviceLimitValueLabel;
@property (nonatomic, strong) UILabel *deviceUuidLabel;
@property (nonatomic, strong) UIImageView *deviceIconImageView;
@property (nonatomic, strong) UILabel *telegramTitleLabel;
@property (nonatomic, strong) UILabel *telegramValueLabel;

// Telegram UI component
@property (nonatomic, strong) TelegramUI *telegramUI;

// Plan slider
@property (nonatomic, strong) PlanSliderView *planSliderView;

// State management
@property (nonatomic, assign) BOOL isLoggingIn;
@property (nonatomic, strong) NSTimer *loadingTimeoutTimer;

// App update UI
@property (nonatomic, strong) UIView *updateView;
@property (nonatomic, strong) UILabel *updateTitleLabel;
@property (nonatomic, strong) UILabel *updateDescriptionLabel;
@property (nonatomic, strong) UIButton *updateButton;
@property (nonatomic, strong) NSDictionary *availableUpdate;
@property (nonatomic, assign) BOOL isCheckingForUpdates;
@property (nonatomic, assign) BOOL isDownloadingUpdate;
@property (nonatomic, strong) UIProgressView *downloadProgressView;
@property (nonatomic, strong) NSTimer *updateCheckTimer;

// Manage devices button
@property (nonatomic, strong) UIButton *manageDevicesButton;

// Loading indicator
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

// Method declarations
- (void)refreshUserData;
- (void)refreshUserDataForceRefresh:(BOOL)forceRefresh;
- (void)manageDevicesButtonTapped;

@end