#import <Foundation/Foundation.h>

@interface NetworkManager : NSObject

// Shared instance
+ (instancetype)sharedManager;

// Carrier information methods
+ (NSArray *)getCarriersForCountry:(NSString *)countryCode;
+ (NSDictionary *)getRandomCarrierForCountry:(NSString *)countryCode;
+ (BOOL)saveCarrierDetails:(NSString *)carrierName mcc:(NSString *)mcc mnc:(NSString *)mnc;
+ (NSDictionary *)getSavedCarrierDetails;
+ (NSDictionary *)getSavedCarrierDetailsWithForcedRefresh:(BOOL)forceRefresh;

// US Carriers
+ (NSArray *)getUSCarriers;
// India Carriers
+ (NSArray *)getIndiaCarriers;
// Canada Carriers
+ (NSArray *)getCanadaCarriers;

// Local IP address methods
+ (NSString *)getCurrentLocalIPAddress;
+ (BOOL)saveLocalIPAddress:(NSString *)ipAddress;
+ (NSString *)getSavedLocalIPAddress;
+ (NSString *)getSavedLocalIPAddressWithForcedRefresh:(BOOL)forceRefresh;

+ (NSString *)generateSpoofedLocalIPAddressFromCurrent;
+ (NSString *)generateSpoofedLocalIPv6AddressFromCurrent;
+ (NSString *)getSavedLocalIPv6Address;

@end
