#import <UIKit/UIKit.h>

@protocol VersionManagementViewControllerDelegate <NSObject>
// Called when versions have been updated
- (void)versionManagementDidUpdateVersions;
@end

@interface VersionManagementViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

// Initialize with bundle ID and app info
- (instancetype)initWithBundleID:(NSString *)bundleID appInfo:(NSDictionary *)appInfo;

// Public method to trigger version fetching from App Store
- (void)fetchVersionsButtonTapped;

@property (nonatomic, weak) id<VersionManagementViewControllerDelegate> delegate;
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, strong) NSDictionary *appInfo;
@property (nonatomic, strong) NSMutableArray *versions;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) NSInteger activeVersionIndex;
@property (nonatomic, assign) NSInteger maxVersionsPerApp;

@end 