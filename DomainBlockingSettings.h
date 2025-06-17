#import <Foundation/Foundation.h>

@interface DomainBlockingSettings : NSObject

@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, strong) NSMutableArray<NSString *> *blockedDomains;

+ (instancetype)sharedSettings;
- (void)saveSettings;
- (void)loadSettings;
- (void)addDomain:(NSString *)domain;
- (void)removeDomain:(NSString *)domain;
- (BOOL)isDomainBlocked:(NSString *)domain;

// Custom domain management methods (everything is now custom)
- (void)setCustomDomainEnabled:(NSString *)domain enabled:(BOOL)enabled;
- (BOOL)isCustomDomainEnabled:(NSString *)domain;
- (void)removeCustomDomain:(NSString *)domain;
- (NSArray<NSDictionary *> *)getCustomDomains; // Returns array of {domain, enabled} dictionaries
- (BOOL)isCustomDomain:(NSString *)domain;
- (NSArray<NSDictionary *> *)getAllDomains; // Returns custom domains for UI

@end
