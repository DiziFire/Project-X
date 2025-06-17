#import <UIKit/UIKit.h>
#import "VersionManagementViewController.h"

@interface AppVersionSpoofingViewController : UIViewController <UICollectionViewDelegate, UICollectionViewDataSource, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, VersionManagementViewControllerDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableDictionary *appsData;
@property (nonatomic, copy) NSString *toastMessageToShow;

// New property to store multiple versions per app
@property (nonatomic, strong) NSMutableDictionary *multiVersionData;
@property (nonatomic, readonly) NSInteger maxVersionsPerApp;

@end 