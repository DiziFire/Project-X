#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UberFareCalculator : NSObject

// Uber API credentials
@property (nonatomic, strong, readonly) NSString *applicationId;
@property (nonatomic, strong, readonly) NSString *clientSecret;

// Singleton instance
+ (instancetype)sharedCalculator;

// Initialize with API credentials
- (void)initWithApplicationId:(NSString *)applicationId 
                clientSecret:(NSString *)clientSecret;

// Calculate fare between two coordinate points
- (void)calculateFareBetweenPickup:(CLLocationCoordinate2D)pickup
                           andDrop:(CLLocationCoordinate2D)drop
                        completion:(void (^)(NSDictionary * _Nullable fareEstimate, 
                                           NSError * _Nullable error))completion;

// Get available products at a location
- (void)getAvailableProductsAtLocation:(CLLocationCoordinate2D)location
                            completion:(void (^)(NSArray * _Nullable products, 
                                              NSError * _Nullable error))completion;

// Calculate fare with specified product ID
- (void)calculateFareForProduct:(NSString *)productId
                    fromPickup:(CLLocationCoordinate2D)pickup
                       toDrop:(CLLocationCoordinate2D)drop
                    completion:(void (^)(NSDictionary * _Nullable fareEstimate, 
                                       NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END 