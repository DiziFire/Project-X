#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DeviceModelManager : NSObject

// Returns the user-friendly name for a given device string (e.g., iPhone15,2 -> iPhone 14 Pro)
- (NSString *)deviceModelNameForString:(NSString *)deviceString;

// Device Specifications for a given device model
- (NSDictionary *)deviceSpecificationsForModel:(NSString *)deviceString;
- (NSString *)screenResolutionForModel:(NSString *)deviceString;
- (NSString *)viewportResolutionForModel:(NSString *)deviceString;
- (CGFloat)devicePixelRatioForModel:(NSString *)deviceString;
- (NSInteger)screenDensityForModel:(NSString *)deviceString;
- (NSString *)cpuArchitectureForModel:(NSString *)deviceString;
- (NSInteger)deviceMemoryForModel:(NSString *)deviceString;
- (NSDictionary *)webGLInfoForModel:(NSString *)deviceString;
- (NSString *)gpuFamilyForModel:(NSString *)deviceString;
- (NSInteger)cpuCoreCountForModel:(NSString *)deviceString;
- (NSString *)metalFeatureSetForModel:(NSString *)deviceString;

// Board ID and Hardware Model
- (NSString *)boardIDForModel:(NSString *)deviceString;
- (NSString *)hwModelForModel:(NSString *)deviceString;

// Processor name (e.g., "Apple A11 Bionic")
- (NSString *)processorNameForModel:(NSString *)deviceString;

// CPU information dictionary
- (NSDictionary *)cpuInfoForModel:(NSString *)deviceString;

+ (instancetype)sharedManager;

// Device Model Generation
- (NSString *)generateDeviceModel;
- (NSString *)currentDeviceModel;
- (void)setCurrentDeviceModel:(NSString *)deviceModel;

// Validation
- (BOOL)isValidDeviceModel:(NSString *)deviceModel;

// Error Handling
- (NSError *)lastError;

@end
