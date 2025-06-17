#import "MapTabViewController.h"

@interface MapTabViewController (PickupDrop)

// Setup methods
- (void)setupPickupDropButton;
- (void)setupPickupDropManager;

// Action handlers
- (void)pickupDropButtonTapped:(UIButton *)sender;
- (void)pickupDropOptionSelected:(UIButton *)sender;
- (void)ellipsisButtonTapped:(UIButton *)sender;

// Load saved locations
- (void)loadSavedPickupDropLocations;

// Map methods
- (void)centerMapAndPlacePinAtLatitude:(double)latitude longitude:(double)longitude shouldTogglePinButton:(BOOL)shouldToggle;

// Path creation
- (void)createPathFromPickupToDrop;

// Uber fare estimation
- (void)setupUberAPIWithAppId:(NSString *)appId clientSecret:(NSString *)clientSecret;
- (void)showUberFareEstimate;

@end 