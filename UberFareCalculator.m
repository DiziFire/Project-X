#import "UberFareCalculator.h"

// Base Uber API URL
static NSString * const kUberBaseURL = @"https://api.uber.com/v1.2";

@interface UberFareCalculator ()

@property (nonatomic, strong, readwrite) NSString *applicationId;
@property (nonatomic, strong, readwrite) NSString *clientSecret;
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSDate *tokenExpirationDate;
@property (nonatomic, strong) NSURLSession *session;

@end

@implementation UberFareCalculator

#pragma mark - Singleton

+ (instancetype)sharedCalculator {
    static UberFareCalculator *sharedCalculator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedCalculator = [[self alloc] init];
    });
    return sharedCalculator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize URL session
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 30.0;
        self.session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

#pragma mark - API Configuration

- (void)initWithApplicationId:(NSString *)applicationId clientSecret:(NSString *)clientSecret {
    self.applicationId = applicationId;
    self.clientSecret = clientSecret;
    
    // Clear any existing tokens when re-initializing
    self.accessToken = nil;
    self.tokenExpirationDate = nil;
    
    NSLog(@"[WeaponX] UberFareCalculator initialized with application ID: %@", applicationId);
}

#pragma mark - Authentication

- (void)fetchAccessTokenWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    // Check if we already have a valid token
    if (self.accessToken && self.tokenExpirationDate && [self.tokenExpirationDate timeIntervalSinceNow] > 60) {
        if (completion) {
            completion(YES, nil);
        }
        return;
    }
    
    // Verify API credentials are set
    if (!self.applicationId || !self.clientSecret) {
        NSError *error = [NSError errorWithDomain:@"UberFareCalculatorErrorDomain" 
                                            code:1001 
                                        userInfo:@{NSLocalizedDescriptionKey: @"API credentials not set"}];
        if (completion) {
            completion(NO, error);
        }
        return;
    }
    
    // Create token request
    NSURL *tokenURL = [NSURL URLWithString:@"https://login.uber.com/oauth/v2/token"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tokenURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    // Prepare parameters with correct scopes for price estimates
    NSString *bodyString = [NSString stringWithFormat:@"client_id=%@&client_secret=%@&grant_type=client_credentials&scope=request pricing",
                          self.applicationId,
                          self.clientSecret];
    [request setHTTPBody:[bodyString dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSLog(@"[WeaponX] 🔑 Requesting Uber access token with scopes: request pricing");
    
    // Send request
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request 
                                            completionHandler:^(NSData * _Nullable data, 
                                                              NSURLResponse * _Nullable response, 
                                                              NSError * _Nullable error) {
        if (error) {
            NSLog(@"[WeaponX] ❌ Uber token request error: %@", error);
            if (completion) {
                completion(NO, error);
            }
            return;
        }
        
        // Parse response
        NSError *jsonError;
        NSDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:data 
                                                                       options:0 
                                                                         error:&jsonError];
        
        if (jsonError) {
            NSLog(@"[WeaponX] ❌ Failed to parse Uber token response: %@", jsonError);
            if (completion) {
                completion(NO, jsonError);
            }
            return;
        }
        
        // Log full response for debugging
        NSLog(@"[WeaponX] 📝 Uber token response: %@", responseObject);
        
        // Check for error in response
        if (responseObject[@"error"]) {
            NSString *errorMessage = responseObject[@"error_description"] ?: @"Unknown error";
            NSError *apiError = [NSError errorWithDomain:@"UberAPIErrorDomain" 
                                                   code:1002 
                                               userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            NSLog(@"[WeaponX] ❌ Uber API error: %@", errorMessage);
            if (completion) {
                completion(NO, apiError);
            }
            return;
        }
        
        // Extract token and expiration
        NSString *accessToken = responseObject[@"access_token"];
        NSNumber *expiresIn = responseObject[@"expires_in"];
        
        if (accessToken && expiresIn) {
            self.accessToken = accessToken;
            self.tokenExpirationDate = [NSDate dateWithTimeIntervalSinceNow:[expiresIn doubleValue]];
            NSLog(@"[WeaponX] ✅ Uber access token obtained, expires in %@ seconds", expiresIn);
            if (completion) {
                completion(YES, nil);
            }
        } else {
            NSError *parseError = [NSError errorWithDomain:@"UberFareCalculatorErrorDomain" 
                                                     code:1003 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid token response"}];
            if (completion) {
                completion(NO, parseError);
            }
        }
    }];
    
    [task resume];
}

#pragma mark - Fare Calculation

- (void)calculateFareBetweenPickup:(CLLocationCoordinate2D)pickup 
                          andDrop:(CLLocationCoordinate2D)drop 
                       completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    // First get available products at pickup location
    [self getAvailableProductsAtLocation:pickup completion:^(NSArray * _Nullable products, NSError * _Nullable error) {
        if (error) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        // Find the first available UberX product
        NSString *productId = nil;
        for (NSDictionary *product in products) {
            if ([product[@"display_name"] isEqualToString:@"UberX"]) {
                productId = product[@"product_id"];
                break;
            }
        }
        
        if (!productId) {
            // If no UberX product, use the first available product
            if (products.count > 0) {
                productId = products[0][@"product_id"];
            } else {
                NSError *noProductError = [NSError errorWithDomain:@"UberFareCalculatorErrorDomain" 
                                                            code:1004 
                                                        userInfo:@{NSLocalizedDescriptionKey: @"No Uber products available"}];
                if (completion) {
                    completion(nil, noProductError);
                }
                return;
            }
        }
        
        // Calculate fare for this product
        [self calculateFareForProduct:productId fromPickup:pickup toDrop:drop completion:completion];
    }];
}

- (void)getAvailableProductsAtLocation:(CLLocationCoordinate2D)location 
                           completion:(void (^)(NSArray * _Nullable, NSError * _Nullable))completion {
    // First ensure we have a valid token
    [self fetchAccessTokenWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        // Build products URL with location
        NSString *urlString = [NSString stringWithFormat:@"%@/products?latitude=%f&longitude=%f", 
                             kUberBaseURL, 
                             location.latitude, 
                             location.longitude];
        
        NSURL *url = [NSURL URLWithString:urlString];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setHTTPMethod:@"GET"];
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.accessToken] forHTTPHeaderField:@"Authorization"];
        
        // Send request
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request 
                                                  completionHandler:^(NSData * _Nullable data, 
                                                                    NSURLResponse * _Nullable response, 
                                                                    NSError * _Nullable error) {
            if (error) {
                NSLog(@"[WeaponX] ❌ Uber products request error: %@", error);
                if (completion) {
                    completion(nil, error);
                }
                return;
            }
            
            // Parse response
            NSError *jsonError;
            NSDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:data 
                                                                           options:0 
                                                                             error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Failed to parse Uber products response: %@", jsonError);
                if (completion) {
                    completion(nil, jsonError);
                }
                return;
            }
            
            // Check for error in response
            if (responseObject[@"error"]) {
                NSString *errorMessage = responseObject[@"message"] ?: @"Unknown error";
                NSError *apiError = [NSError errorWithDomain:@"UberAPIErrorDomain" 
                                                       code:1005 
                                                   userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
                NSLog(@"[WeaponX] ❌ Uber API error: %@", errorMessage);
                if (completion) {
                    completion(nil, apiError);
                }
                return;
            }
            
            // Extract products
            NSArray *products = responseObject[@"products"];
            
            if (completion) {
                completion(products, nil);
            }
        }];
        
        [task resume];
    }];
}

- (void)calculateFareForProduct:(NSString *)productId 
                   fromPickup:(CLLocationCoordinate2D)pickup 
                      toDrop:(CLLocationCoordinate2D)drop 
                   completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    // First ensure we have a valid token
    [self fetchAccessTokenWithCompletion:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }
        
        // Build estimate URL
        NSString *urlString = [NSString stringWithFormat:@"%@/estimates/price", kUberBaseURL];
        NSURL *url = [NSURL URLWithString:urlString];
        
        // Add query parameters
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSArray *queryItems = @[
            [NSURLQueryItem queryItemWithName:@"product_id" value:productId],
            [NSURLQueryItem queryItemWithName:@"start_latitude" value:[@(pickup.latitude) stringValue]],
            [NSURLQueryItem queryItemWithName:@"start_longitude" value:[@(pickup.longitude) stringValue]],
            [NSURLQueryItem queryItemWithName:@"end_latitude" value:[@(drop.latitude) stringValue]],
            [NSURLQueryItem queryItemWithName:@"end_longitude" value:[@(drop.longitude) stringValue]]
        ];
        components.queryItems = queryItems;
        
        // Create request
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
        [request setHTTPMethod:@"GET"];
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.accessToken] forHTTPHeaderField:@"Authorization"];
        
        // Send request
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request 
                                                  completionHandler:^(NSData * _Nullable data, 
                                                                    NSURLResponse * _Nullable response, 
                                                                    NSError * _Nullable error) {
            if (error) {
                NSLog(@"[WeaponX] ❌ Uber fare estimate request error: %@", error);
                if (completion) {
                    completion(nil, error);
                }
                return;
            }
            
            // Parse response
            NSError *jsonError;
            NSDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:data 
                                                                           options:0 
                                                                             error:&jsonError];
            
            if (jsonError) {
                NSLog(@"[WeaponX] ❌ Failed to parse Uber fare estimate response: %@", jsonError);
                if (completion) {
                    completion(nil, jsonError);
                }
                return;
            }
            
            // Check for error in response
            if (responseObject[@"error"]) {
                NSString *errorMessage = responseObject[@"message"] ?: @"Unknown error";
                NSError *apiError = [NSError errorWithDomain:@"UberAPIErrorDomain" 
                                                       code:1006 
                                                   userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
                NSLog(@"[WeaponX] ❌ Uber API error: %@", errorMessage);
                if (completion) {
                    completion(nil, apiError);
                }
                return;
            }
            
            // Extract fare estimate
            NSArray *estimates = responseObject[@"price"];
            
            if (estimates && estimates.count > 0) {
                // Return the first estimate
                if (completion) {
                    completion(estimates[0], nil);
                }
            } else {
                NSError *noEstimateError = [NSError errorWithDomain:@"UberFareCalculatorErrorDomain" 
                                                              code:1007 
                                                          userInfo:@{NSLocalizedDescriptionKey: @"No fare estimates available"}];
                if (completion) {
                    completion(nil, noEstimateError);
                }
            }
        }];
        
        [task resume];
    }];
}

@end 