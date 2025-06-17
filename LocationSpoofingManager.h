#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

// Define transportation modes
typedef NS_ENUM(NSInteger, TransportationMode) {
    TransportationModeStationary = 0,
    TransportationModeWalking = 1,
    TransportationModeDriving = 2
};

@interface LocationSpoofingManager : NSObject

@property (nonatomic, strong) NSMutableDictionary *cachedScopedApps;

// Advanced spoofing properties
@property (nonatomic, readonly, assign) TransportationMode transportationMode;
@property (nonatomic, readonly, assign) double maxMovementSpeed;
@property (nonatomic, readonly, assign) double jitterAmount;
@property (nonatomic, readonly, assign) double accuracyValue;
@property (nonatomic, readonly, assign) BOOL jitterEnabled;
@property (nonatomic, readonly, assign) double lastReportedSpeed;
@property (nonatomic, readonly, assign) double lastReportedCourse;
@property (nonatomic, readwrite, assign) BOOL positionVariationsEnabled;

// Path-based movement properties
@property (nonatomic, readonly, assign) BOOL isMovingAlongPath;
@property (nonatomic, readwrite, strong) NSArray *currentPath;
@property (nonatomic, readwrite, assign) NSInteger currentPathIndex;

+ (instancetype)sharedManager;

// Core functionality
- (BOOL)isSpoofingEnabled;
- (void)enableSpoofingWithLatitude:(double)latitude longitude:(double)longitude;
- (void)disableSpoofing;

// Toggle state controls
- (BOOL)isSpoofingToggleEnabled;
- (void)enableSpoofingToggle;
- (void)disableSpoofingToggle;

// Settings
- (void)saveSpoofingLocation:(NSDictionary *)location;
- (NSDictionary *)loadSpoofingLocation;
- (NSDictionary *)directReadPinnedLocationFromFile;  // Direct access to pinned location from plist

// GPS data modification
- (CLLocation *)modifySpoofedLocation:(CLLocation *)originalLocation;
- (double)getSpoofedLatitude;
- (double)getSpoofedLongitude;
- (BOOL)shouldSpoofApp:(NSString *)bundleID;

// Advanced spoofing methods
- (void)setTransportationMode:(TransportationMode)mode;
- (void)setAccuracyValue:(double)accuracy;
- (void)setJitterEnabled:(BOOL)enabled;
- (CLLocation *)createRealisticSpoofedLocation:(CLLocationCoordinate2D)baseCoordinate;

// Movement simulation method
- (NSArray<CLLocation *> *)calculateSimpleMovement:(CLLocationCoordinate2D)start
                                               end:(CLLocationCoordinate2D)end
                               speedMetersPerSecond:(double)speed;

// Apply transportation mode settings to location
- (void)applyTransportationMode:(TransportationMode)mode toLocation:(CLLocation *)location;

// Path-based movement methods
- (void)startMovementAlongPath:(NSArray *)waypoints
                     withSpeed:(double)metersPerSecond
                    completion:(void(^)(BOOL completed))completion;
- (void)startMovementAlongPath:(NSArray *)waypoints
                     withSpeed:(double)metersPerSecond
                    startIndex:(NSInteger)startIndex
                    completion:(void(^)(BOOL completed))completion;
- (void)stopMovementAlongPath;
- (BOOL)isCurrentlyMoving;
- (double)estimatedTimeToCompleteCurrentPath; // Returns time in seconds

@end 