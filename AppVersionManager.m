#import "AppVersionManager.h"
#import <Foundation/Foundation.h>

@implementation AppVersionManager {
    NSString *_appStoreApiUrl;
    NSString *_versionHistoryApiUrl;
    BOOL _isFetching;
}

+ (instancetype)sharedManager {
    static AppVersionManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _appStoreApiUrl = @"https://itunes.apple.com/lookup";
        _versionHistoryApiUrl = @"https://apis.bilin.eu.org/history/";
        _isFetching = NO;
    }
    return self;
}

- (void)fetchVersionsForBundleID:(NSString *)bundleID 
                     completion:(void (^)(NSArray<NSDictionary *> *versions, NSError *error))completion {
    if (!bundleID) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"com.appversionmanager"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Bundle ID is required"}]);
        });
        return;
    }
    
    if (_isFetching) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"com.appversionmanager"
                                             code:429
                                         userInfo:@{NSLocalizedDescriptionKey: @"Already fetching versions"}]);
        });
        return;
    }
    
    _isFetching = YES;
    
    NSURLComponents *components = [[NSURLComponents alloc] initWithString:_appStoreApiUrl];
    NSArray *queryItems = @[
        [[NSURLQueryItem alloc] initWithName:@"bundleId" value:bundleID],
        [[NSURLQueryItem alloc] initWithName:@"entity" value:@"software"],
        [[NSURLQueryItem alloc] initWithName:@"limit" value:@"1"],
        [[NSURLQueryItem alloc] initWithName:@"country" value:@"us"],
        [[NSURLQueryItem alloc] initWithName:@"lang" value:@"en_us"]
    ];
    components.queryItems = queryItems;
    
    NSURL *url = components.URL;
    if (!url) {
        _isFetching = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"com.appversionmanager"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        });
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                     timeoutInterval:30.0];
    [request setValue:@"iTunes/12.6.8 (Macintosh; OS X 10.15.7)" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept-Encoding"];
    [request setValue:@"en-us" forHTTPHeaderField:@"Accept-Language"];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30.0;
    config.timeoutIntervalForResource = 300.0;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        if (error) {
            strongSelf->_isFetching = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
            strongSelf->_isFetching = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, jsonError ?: [NSError errorWithDomain:@"com.appversionmanager"
                                                              code:500
                                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON response"}]);
            });
            return;
        }
        
        NSArray *results = json[@"results"];
        if (![results isKindOfClass:[NSArray class]] || results.count == 0) {
            strongSelf->_isFetching = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"com.appversionmanager"
                                                 code:404
                                             userInfo:@{NSLocalizedDescriptionKey: @"App not found"}]);
            });
            return;
        }
        
        NSDictionary *appInfo = results.firstObject;
        NSNumber *trackId = appInfo[@"trackId"];
        
        if (!trackId) {
            strongSelf->_isFetching = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"com.appversionmanager"
                                                 code:404
                                             userInfo:@{NSLocalizedDescriptionKey: @"Track ID not found"}]);
            });
            return;
        }
        
        NSURL *historyURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", strongSelf->_versionHistoryApiUrl, trackId]];
        NSMutableURLRequest *historyRequest = [NSMutableURLRequest requestWithURL:historyURL];
        [historyRequest setValue:@"*/*" forHTTPHeaderField:@"Accept"];
        [historyRequest setValue:@"en-us" forHTTPHeaderField:@"Accept-Language"];
        
        NSURLSessionDataTask *historyTask = [[NSURLSession sharedSession] dataTaskWithRequest:historyRequest 
                                                                          completionHandler:^(NSData *historyData, NSURLResponse *historyResponse, NSError *historyError) {
            strongSelf->_isFetching = NO;
            
            if (historyError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, historyError);
                });
                return;
            }
            
            NSError *historyJsonError;
            NSDictionary *historyJson = [NSJSONSerialization JSONObjectWithData:historyData options:0 error:&historyJsonError];
            
            if (historyJsonError || ![historyJson isKindOfClass:[NSDictionary class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, historyJsonError ?: [NSError errorWithDomain:@"com.appversionmanager"
                                                                      code:500
                                                                  userInfo:@{NSLocalizedDescriptionKey: @"Invalid version history response"}]);
                });
                return;
            }
            
            NSArray *versions = historyJson[@"data"];
            if (![versions isKindOfClass:[NSArray class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [NSError errorWithDomain:@"com.appversionmanager"
                                                     code:500
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid version data"}]);
                });
                return;
            }
            
            NSMutableArray *processedVersions = [NSMutableArray array];
            
            // Add current version first
            NSMutableDictionary *currentVersion = [NSMutableDictionary dictionary];
            currentVersion[@"version"] = appInfo[@"version"];
            currentVersion[@"bundleId"] = bundleID;
            currentVersion[@"trackId"] = trackId;
            currentVersion[@"external_identifier"] = @0;
            currentVersion[@"appName"] = appInfo[@"trackName"];
            currentVersion[@"sellerName"] = appInfo[@"sellerName"];
            currentVersion[@"minimumOsVersion"] = appInfo[@"minimumOsVersion"];
            currentVersion[@"releaseDate"] = appInfo[@"currentVersionReleaseDate"];
            currentVersion[@"releaseNotes"] = appInfo[@"releaseNotes"];
            currentVersion[@"isCurrent"] = @YES;
            currentVersion[@"price"] = appInfo[@"price"] ?: @0;
            currentVersion[@"currency"] = appInfo[@"currency"] ?: @"USD";
            currentVersion[@"isFirstParty"] = @YES;
            [processedVersions addObject:currentVersion];
            
            // Process version history
            for (NSDictionary *version in versions) {
                if (![version isKindOfClass:[NSDictionary class]]) continue;
                
                NSMutableDictionary *versionInfo = [NSMutableDictionary dictionary];
                versionInfo[@"version"] = version[@"bundle_version"];
                versionInfo[@"bundleId"] = bundleID;
                versionInfo[@"trackId"] = trackId;
                versionInfo[@"external_identifier"] = version[@"external_identifier"];
                versionInfo[@"appName"] = appInfo[@"trackName"];
                versionInfo[@"sellerName"] = appInfo[@"sellerName"];
                
                // Get minimum OS version from version history API
                NSString *minOSVersion = version[@"minimum_os_version"];
                if (!minOSVersion || [minOSVersion isEqualToString:@""]) {
                    // If not available in version history, try to get from app info
                    minOSVersion = appInfo[@"minimumOsVersion"];
                }
                versionInfo[@"minimumOsVersion"] = minOSVersion ?: @"Unknown";
                
                versionInfo[@"releaseDate"] = version[@"created_at"] ?: @"Unknown";
                versionInfo[@"isCurrent"] = @NO;
                versionInfo[@"price"] = appInfo[@"price"] ?: @0;
                versionInfo[@"currency"] = appInfo[@"currency"] ?: @"USD";
                versionInfo[@"isFirstParty"] = @YES;
                [processedVersions addObject:versionInfo];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(processedVersions, nil);
            });
        }];
        
        [historyTask resume];
    }];
    
    [task resume];
}

- (void)installVersion:(NSString *)version 
           forBundleID:(NSString *)bundleID 
            completion:(void (^)(BOOL success, NSError *error))completion {
    
    [self fetchVersionsForBundleID:bundleID completion:^(NSArray<NSDictionary *> *versions, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSDictionary *versionInfo = nil;
        for (NSDictionary *ver in versions) {
            if ([ver[@"version"] isEqualToString:version]) {
                versionInfo = ver;
                break;
            }
        }
        
        if (!versionInfo) {
            completion(NO, [NSError errorWithDomain:@"com.appversionmanager"
                                            code:404
                                        userInfo:@{NSLocalizedDescriptionKey: @"Version not found"}]);
            return;
        }
        
        NSNumber *trackId = versionInfo[@"trackId"];
        NSNumber *externalId = versionInfo[@"external_identifier"];
        
        if (!trackId || !externalId) {
            completion(NO, [NSError errorWithDomain:@"com.appversionmanager"
                                            code:500
                                        userInfo:@{NSLocalizedDescriptionKey: @"Invalid version info"}]);
            return;
        }

        Class SKUIItemOfferClass = NSClassFromString(@"SKUIItemOffer");
        Class SKUIItemClass = NSClassFromString(@"SKUIItem");
        Class SKUIItemStateCenterClass = NSClassFromString(@"SKUIItemStateCenter");
        Class SKUIClientContextClass = NSClassFromString(@"SKUIClientContext");
        
        if (!SKUIItemOfferClass || !SKUIItemClass || !SKUIItemStateCenterClass || !SKUIClientContextClass) {
            completion(NO, [NSError errorWithDomain:@"com.appversionmanager"
                                            code:500
                                        userInfo:@{NSLocalizedDescriptionKey: @"Required StoreKit classes not found"}]);
            return;
        }

        // Create item first
        NSDictionary *itemDict = @{@"_itemOffer": trackId};
        id item = [[SKUIItemClass alloc] initWithLookupDictionary:itemDict];
        [item setValue:@"iosSoftware" forKey:@"_itemKindString"];
        
        if (![externalId isEqual:@0]) {
            [item setValue:externalId forKey:@"_versionIdentifier"];
        }

        // Then create and set offer
        NSString *offerString;
        if ([externalId isEqual:@0]) {
            offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=pricingParameter&clientBuyId=1&installed=0&trolled=1", trackId];
        } else {
            offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=pricingParameter&appExtVrsId=%@&clientBuyId=1&installed=0&trolled=1", trackId, externalId];
        }

        NSDictionary *offerDict = @{@"buyParams": offerString};
        id offer = [[SKUIItemOfferClass alloc] initWithLookupDictionary:offerDict];
        [item setValue:offer forKey:@"_itemOffer"];

        // Create center and perform purchase
        id center = [SKUIItemStateCenterClass defaultCenter];
        id purchases = [center _newPurchasesWithItems:@[item]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [center _performPurchases:purchases hasBundlePurchase:NO withClientContext:[SKUIClientContextClass defaultContext] completionBlock:^(id result) {
                if (result) {
                    completion(YES, nil);
                } else {
                    completion(NO, [NSError errorWithDomain:@"com.appversionmanager"
                                                    code:500
                                                userInfo:@{NSLocalizedDescriptionKey: @"Installation failed"}]);
                }
            }];
        });
    }];
}

@end 