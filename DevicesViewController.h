#import <UIKit/UIKit.h>

@interface DevicesViewController : UIViewController <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

// Core properties
@property (nonatomic, strong) NSString *authToken;
@property (nonatomic, strong) NSArray *devices;
@property (nonatomic, assign) NSInteger deviceLimit;
@property (nonatomic, strong) NSString *currentDeviceUUID;

// UI Elements
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *emptyStateLabel;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *deviceCountLabel;
@property (nonatomic, strong) UILabel *deviceSlashLabel;
@property (nonatomic, strong) UILabel *deviceLimitLabel;
@property (nonatomic, strong) UIProgressView *deviceLimitProgressView;

// Initialization with auth token
- (instancetype)initWithAuthToken:(NSString *)authToken;

// Refresh methods
- (void)refreshDevices;

// Device management
- (void)removeDeviceWithUUID:(NSString *)deviceUUID;

@end