#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import "PickupDropManager.h"

@interface MapTabViewController : UIViewController <WKNavigationDelegate, WKScriptMessageHandler, UITextFieldDelegate, CLLocationManagerDelegate, UIPopoverPresentationControllerDelegate, UITableViewDataSource, UITableViewDelegate, UIContextMenuInteractionDelegate, MKLocalSearchCompleterDelegate, UISearchBarDelegate>

@property (nonatomic, readonly, strong) UIButton *favoritesButton;
@property (nonatomic, readonly, strong) UIView *favoritesContainer;
@property (nonatomic, readonly, strong) UIButton *unpinButton;
@property (nonatomic, readonly, strong) UIButton *pinButton;
@property (nonatomic, readonly, strong) UIView *unpinContainer;

// GPS Spoofing Properties
@property (nonatomic, readonly, strong) UIView *gpsSpoofingBar;
@property (nonatomic, readonly, strong) UISwitch *gpsSpoofingSwitch;

// Advanced GPS Spoofing Properties
@property (nonatomic, readonly, strong) UIButton *gpsAdvancedButton;
@property (nonatomic, readonly, strong) UIView *gpsAdvancedPanel;
@property (nonatomic, readonly, strong) UISegmentedControl *transportationModeControl;
@property (nonatomic, readonly, strong) UISlider *accuracySlider;
@property (nonatomic, readonly, strong) UISwitch *jitterSwitch;
@property (nonatomic, readonly, strong) UILabel *speedCourseLabel;
@property (nonatomic, readonly, strong) NSTimer *speedUpdateTimer;

// Path Movement Properties 
@property (nonatomic, readonly, strong) UISlider *movementSpeedSlider;
@property (nonatomic, readonly, strong) UILabel *movementSpeedLabel;
@property (nonatomic, readonly, strong) UILabel *pathStatusLabel;

// New properties for pickup/drop functionality
@property (nonatomic, strong) UIButton *pickupDropButton;
@property (nonatomic, strong) UIView *pickupDropMenuView;
@property (nonatomic, strong) NSDictionary *pickupLocation;
@property (nonatomic, strong) NSDictionary *dropLocation;
@property (nonatomic, strong) PickupDropManager *pickupDropManager;

// Map views
@property (nonatomic, strong) UIView *mapContainerView;
@property (nonatomic, strong) WKWebView *mapWebView;

// UI elements
@property (nonatomic, strong) UIButton *uberFareButton;

@end