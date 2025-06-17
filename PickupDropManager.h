#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <WebKit/WebKit.h>

// Keys for NSUserDefaults persistence
extern NSString * const kPickupLocationKey;
extern NSString * const kDropLocationKey;

@interface PickupDropManager : NSObject

@property (nonatomic, strong) WKWebView *mapWebView;
@property (nonatomic, strong) NSDictionary *pickupLocation;
@property (nonatomic, strong) NSDictionary *dropLocation;

+ (instancetype)sharedManager;

// Initialize with the map webview
- (void)initWithMapWebView:(WKWebView *)webView;

// Save locations
- (void)savePickupLocation:(NSDictionary *)location;
- (void)saveDropLocation:(NSDictionary *)location;

// Load locations
- (void)loadSavedLocations;

// Update map markers
- (void)updatePickupDropMarkersOnMap;

// Create path between pickup and drop
- (NSArray *)createPathFromPickupToDrop;

// Check if locations are set
- (BOOL)hasPickupLocation;
- (BOOL)hasDropLocation;
- (BOOL)hasPickupAndDropLocations;

// Uber fare estimation
- (void)configureUberWithAppId:(NSString *)appId clientSecret:(NSString *)clientSecret;
- (void)calculateUberFareWithCompletion:(void (^)(NSDictionary *fareEstimate, NSError *error))completion;
- (CLLocationCoordinate2D)pickupCoordinate;
- (CLLocationCoordinate2D)dropCoordinate;

// Remove locations
- (void)removePickupLocation;
- (void)removeDropLocation;

@end 