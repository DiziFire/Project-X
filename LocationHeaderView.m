#import "LocationHeaderView.h"
#import "LocationSpoofingManager.h"
#import "ProjectXLogging.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import "IPMonitorService.h"
#import "IPStatusCacheManager.h"

// Category to add timeZoneId property to UILabel
@interface UILabel (TimeZone)
@property (nonatomic, strong) NSString *timeZoneId;
// Add properties for IP details
@property (nonatomic, strong) NSString *ipCity;
@property (nonatomic, strong) NSString *ipISP;
@property (nonatomic, strong) NSString *ipTimezoneName;
@end

@implementation UILabel (TimeZone)
- (void)setTimeZoneId:(NSString *)timeZoneId {
    objc_setAssociatedObject(self, @selector(timeZoneId), timeZoneId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)timeZoneId {
    return objc_getAssociatedObject(self, @selector(timeZoneId));
}

// Implement getters and setters for new properties
- (void)setIpCity:(NSString *)ipCity {
    objc_setAssociatedObject(self, @selector(ipCity), ipCity, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)ipCity {
    return objc_getAssociatedObject(self, @selector(ipCity));
}

- (void)setIpISP:(NSString *)ipISP {
    objc_setAssociatedObject(self, @selector(ipISP), ipISP, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)ipISP {
    return objc_getAssociatedObject(self, @selector(ipISP));
}

- (void)setIpTimezoneName:(NSString *)ipTimezoneName {
    objc_setAssociatedObject(self, @selector(ipTimezoneName), ipTimezoneName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)ipTimezoneName {
    return objc_getAssociatedObject(self, @selector(ipTimezoneName));
}
@end

@interface LocationHeaderView ()
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NSString *currentTimeZoneId;
@property (nonatomic, strong) NSCache *countryCache;
@end

@implementation LocationHeaderView

+ (UIView *)createHeaderViewWithTitle:(NSString *)title 
                     navigationItem:(UINavigationItem *)navigationItem 
                      updateHandler:(void (^)(void))updateHandler {
    // Set the main title directly
    navigationItem.title = title;
    
    // Remove any existing barButtonItems to prevent duplication
    navigationItem.rightBarButtonItems = nil;
    navigationItem.leftBarButtonItems = nil;
    
    // Create a custom view for the right bar button item
    UIView *rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 44)];
    
    // Create coordinates label
    UILabel *coordsLabel = [[UILabel alloc] init];
    coordsLabel.textColor = [UIColor secondaryLabelColor];
    coordsLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    coordsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    coordsLabel.adjustsFontSizeToFitWidth = YES;
    coordsLabel.minimumScaleFactor = 0.8;
    coordsLabel.textAlignment = NSTextAlignmentRight;
    [rightView addSubview:coordsLabel];
    
    // Create time label
    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.textColor = [UIColor secondaryLabelColor];
    timeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
    timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    timeLabel.textAlignment = NSTextAlignmentRight;
    timeLabel.userInteractionEnabled = YES;
    [rightView addSubview:timeLabel];
    
    // Set up constraints for right view
    [NSLayoutConstraint activateConstraints:@[
        // Position coordinates label
        [coordsLabel.topAnchor constraintEqualToAnchor:rightView.topAnchor constant:-2],
        [coordsLabel.trailingAnchor constraintEqualToAnchor:rightView.trailingAnchor],
        [coordsLabel.leadingAnchor constraintEqualToAnchor:rightView.leadingAnchor],
        
        // Position time label
        [timeLabel.topAnchor constraintEqualToAnchor:coordsLabel.bottomAnchor constant:2],
        [timeLabel.trailingAnchor constraintEqualToAnchor:coordsLabel.trailingAnchor],
        [timeLabel.leadingAnchor constraintEqualToAnchor:coordsLabel.leadingAnchor]
    ]];
    
    // Create a custom view for the left bar button item (IP address)
    UIView *leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 44)];
    
    // Create IP label
    UILabel *ipLabel = [[UILabel alloc] init];
    ipLabel.textColor = [UIColor secondaryLabelColor];
    ipLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    ipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    ipLabel.adjustsFontSizeToFitWidth = YES;
    ipLabel.minimumScaleFactor = 0.8;
    ipLabel.textAlignment = NSTextAlignmentLeft;
    ipLabel.tag = 1001; // Tag for easy reference to update later
    ipLabel.text = @"Fetching IP...";
    
    [leftView addSubview:ipLabel];
    
    // Set up constraints for left view
    [NSLayoutConstraint activateConstraints:@[
        [ipLabel.centerYAnchor constraintEqualToAnchor:leftView.centerYAnchor],
        [ipLabel.leadingAnchor constraintEqualToAnchor:leftView.leadingAnchor],
        [ipLabel.trailingAnchor constraintEqualToAnchor:leftView.trailingAnchor]
    ]];
    
    // Get pinned location
    NSDictionary *pinnedLocation = [[LocationSpoofingManager sharedManager] loadSpoofingLocation];
    if (pinnedLocation && pinnedLocation[@"latitude"] && pinnedLocation[@"longitude"]) {
        double lat = [pinnedLocation[@"latitude"] doubleValue];
        double lon = [pinnedLocation[@"longitude"] doubleValue];
        
        // Initially set coordinates without flag
        coordsLabel.text = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];
        coordsLabel.hidden = NO;
        timeLabel.hidden = NO;
        
        // Get timezone and update time
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(lat, lon);
        [self getTimeZoneForLocation:coordinate completion:^(NSTimeZone *timeZone, NSString *timeZoneId) {
            if (timeZone) {
                // Store timeZoneId in the label
                timeLabel.timeZoneId = timeZoneId;
                
                // Update time immediately
                [self updateTimeLabel:timeLabel withTimeZone:timeZone];
                
                // Add tap gesture to time label
                UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showTimeZoneOptions:)];
                tapGesture.cancelsTouchesInView = NO;
                timeLabel.userInteractionEnabled = YES;
                [timeLabel addGestureRecognizer:tapGesture];
            }
        }];
        
        // Fetch country info and update label
        [self fetchCountryForCoordinates:lat longitude:lon completion:^(NSString *countryCode, NSString *flag) {
            if (flag) {
                NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:
                    [NSString stringWithFormat:@"%@ %.4f, %.4f", flag, lat, lon]
                    attributes:@{
                        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightRegular],
                        NSForegroundColorAttributeName: [UIColor secondaryLabelColor]
                    }];
                coordsLabel.attributedText = attributedText;
                
                // Save pinned location data to iplocationtime.plist
                Class cacheManagerClass = NSClassFromString(@"IPStatusCacheManager");
                if (cacheManagerClass && 
                    [cacheManagerClass respondsToSelector:@selector(savePinnedLocation:countryCode:flagEmoji:timestamp:)]) {
                    
                    CLLocationCoordinate2D coords;
                    coords.latitude = lat;
                    coords.longitude = lon;
                    
                    [cacheManagerClass savePinnedLocation:coords
                                             countryCode:countryCode
                                              flagEmoji:flag
                                              timestamp:[NSDate date]];
                    PXLog(@"[LocationHeaderView] Saved pinned location to iplocationtime.plist: %.4f, %.4f", coords.latitude, coords.longitude);
                }
            }
        }];
        
        // Create bar button items with the custom views
        UIBarButtonItem *rightBarItem = [[UIBarButtonItem alloc] initWithCustomView:rightView];
        UIBarButtonItem *leftBarItem = [[UIBarButtonItem alloc] initWithCustomView:leftView];
        
        navigationItem.rightBarButtonItem = rightBarItem;
        navigationItem.leftBarButtonItem = leftBarItem;
    } else {
        // If no pinned location, still show the IP on the left
        UIBarButtonItem *leftBarItem = [[UIBarButtonItem alloc] initWithCustomView:leftView];
        navigationItem.leftBarButtonItem = leftBarItem;
    }
    
    // Fetch current IP
    [self fetchCurrentIPWithNavigationItem:navigationItem];
    
    return rightView;
}

+ (void)fetchCurrentIPWithNavigationItem:(UINavigationItem *)navigationItem {
    // Create a URL session with timeout
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 8.0;
    config.timeoutIntervalForResource = 15.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // Use ipwhois.app to get additional country info
    NSString *ipwhoisURL = @"https://ipwhois.app/json/";
    NSURL *url = [NSURL URLWithString:ipwhoisURL];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"WeaponX iOS App" forHTTPHeaderField:@"User-Agent"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            // Fallback to simpler IP services if ipwhois fails
            PXLog(@"[IPDisplay] ipwhois.app request failed: %@", error);
            [self fetchSimpleIPWithNavigationItem:navigationItem];
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            PXLog(@"[IPDisplay] JSON parsing failed: %@", jsonError);
            [self fetchSimpleIPWithNavigationItem:navigationItem];
            return;
        }
        
        // Debug to see all fields
        PXLog(@"[IPDisplay] ipwhois response: %@", json);
        
        NSString *ip = json[@"ip"];
        NSString *countryCode = json[@"country_code"];
        NSString *city = json[@"city"];
        NSString *isp = json[@"isp"];
        NSString *timezoneName = json[@"timezone"];
        
        // Get timezone info and format current time
        NSString *currentTime = nil;
        
        if (timezoneName) {
            // Create timezone from name (e.g., "America/New_York")
            NSTimeZone *tz = [NSTimeZone timeZoneWithName:timezoneName];
            if (tz) {
                // Format current time in the IP's timezone
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.timeZone = tz;
                formatter.dateFormat = @"h:mm a"; // 12-hour format with AM/PM
                currentTime = [formatter stringFromDate:[NSDate date]];
                PXLog(@"[IPDisplay] Formatted current time for %@: %@", timezoneName, currentTime);
            }
        }
        
        // If we couldn't format the time, fall back to timezone_gmt
        if (!currentTime) {
            currentTime = json[@"timezone_gmt"];
        }
        
        PXLog(@"[IPDisplay] IP: %@, Country: %@, Time: %@", ip, countryCode, currentTime);
        
        if (ip) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Get the IP label to store details
                UIView *leftView = navigationItem.leftBarButtonItem.customView;
                UILabel *ipLabel = [leftView viewWithTag:1001];
                
                // Store IP details for display when tapped
                if (ipLabel) {
                    ipLabel.ipCity = city;
                    ipLabel.ipISP = isp;
                    ipLabel.ipTimezoneName = timezoneName;
                }
                
                [self updateIPLabelWithIP:ip countryCode:countryCode currentTime:currentTime navigationItem:navigationItem];
            });
        } else {
            [self fetchSimpleIPWithNavigationItem:navigationItem];
        }
    }];
    
    [task resume];
}

+ (void)fetchSimpleIPWithNavigationItem:(UINavigationItem *)navigationItem {
    // Fallback to simpler IP service without country info
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 5.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURL *url = [NSURL URLWithString:@"https://api.ipify.org"];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:[NSURLRequest requestWithURL:url] 
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            return;
        }
        
        NSString *ip = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        ip = [ip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (ip && ip.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateIPLabelWithIP:ip countryCode:nil currentTime:nil navigationItem:navigationItem];
            });
        }
    }];
    
    [task resume];
}

+ (void)updateIPLabelWithIP:(NSString *)ip countryCode:(NSString *)countryCode currentTime:(NSString *)currentTime navigationItem:(UINavigationItem *)navigationItem {
    // Get the views
    UIView *leftView = navigationItem.leftBarButtonItem.customView;
    UILabel *ipLabel = [leftView viewWithTag:1001];
    UILabel *ipTimeLabel = [leftView viewWithTag:1002];
    
    if (!ipTimeLabel && leftView) {
        // Create time label if it doesn't exist
        ipTimeLabel = [[UILabel alloc] init];
        ipTimeLabel.textColor = [UIColor secondaryLabelColor];
        ipTimeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightRegular];
        ipTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        ipTimeLabel.adjustsFontSizeToFitWidth = YES;
        ipTimeLabel.minimumScaleFactor = 0.8;
        ipTimeLabel.textAlignment = NSTextAlignmentLeft;
        ipTimeLabel.tag = 1002;
        [leftView addSubview:ipTimeLabel];
        
        // Position time label below IP label
        [NSLayoutConstraint activateConstraints:@[
            [ipTimeLabel.topAnchor constraintEqualToAnchor:ipLabel.bottomAnchor constant:2],
            [ipTimeLabel.leadingAnchor constraintEqualToAnchor:ipLabel.leadingAnchor],
            [ipTimeLabel.trailingAnchor constraintEqualToAnchor:ipLabel.trailingAnchor]
        ]];
    }
    
    if (ipLabel) {
        // Format the IP address (abbreviate IPv6)
        NSString *formattedIP = [self formatIPAddress:ip];
        NSString *flagEmoji = nil;
        
        if (countryCode) {
            // Get flag emoji for country code
            flagEmoji = [self flagEmojiForCountryCode:countryCode];
            if (flagEmoji) {
                // Show flag + IP
                ipLabel.text = [NSString stringWithFormat:@"%@ %@", flagEmoji, formattedIP];
            } else {
                // Fallback to just IP
                ipLabel.text = formattedIP;
            }
            
            // Add tap gesture if not already added
            if (![ipLabel.gestureRecognizers count]) {
                UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showIPDetails:)];
                ipLabel.userInteractionEnabled = YES;
                [ipLabel addGestureRecognizer:tapGesture];
            }
        } else {
            // No country info, just show IP
            ipLabel.text = formattedIP;
        }
        
        // Update time label if we have time info
        if (ipTimeLabel && currentTime) {
            ipTimeLabel.text = currentTime;
            ipTimeLabel.hidden = NO;
        } else if (ipTimeLabel) {
            ipTimeLabel.hidden = YES;
        }
        
        // Save IP data to iplocationtime.plist
        if (ip) {
            // Import IPStatusCacheManager if needed
            Class cacheManagerClass = NSClassFromString(@"IPStatusCacheManager");
            if (cacheManagerClass && 
                [cacheManagerClass respondsToSelector:@selector(savePublicIP:countryCode:flagEmoji:timestamp:)]) {
                [cacheManagerClass savePublicIP:ip 
                                   countryCode:countryCode 
                                    flagEmoji:flagEmoji 
                                    timestamp:[NSDate date]];
                PXLog(@"[LocationHeaderView] Saved IP data to iplocationtime.plist: %@", ip);
            }
        }
    }
}

+ (NSString *)formatIPAddress:(NSString *)ipAddress {
    if (!ipAddress) return @"";
    
    // If IP length exceeds 17 characters, truncate it
    if (ipAddress.length > 17) {
        // If it's IPv6 (contains colons)
    if ([ipAddress containsString:@":"]) {
            NSString *start = [ipAddress substringToIndex:8];
            NSString *end = [ipAddress substringFromIndex:ipAddress.length - 4];
            return [NSString stringWithFormat:@"%@...%@", start, end];
        } else {
            // For any other long address, simply truncate with ellipsis
            return [NSString stringWithFormat:@"%@...", [ipAddress substringToIndex:14]];
        }
    }
    
    // Return full IP for addresses 17 chars or shorter
    return ipAddress;
}

#pragma mark - Helper Methods

+ (void)getTimeZoneForLocation:(CLLocationCoordinate2D)coordinate completion:(void (^)(NSTimeZone *timeZone, NSString *timeZoneId))completion {
    CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> * _Nullable placemarks, NSError * _Nullable error) {
        if (error || placemarks.count == 0) {
            completion(nil, nil);
            return;
        }
        
        CLPlacemark *placemark = placemarks.firstObject;
        NSTimeZone *timeZone = placemark.timeZone;
        NSString *timeZoneId = timeZone.name;
        completion(timeZone, timeZoneId);
    }];
}

+ (void)showTimeZoneOptions:(UITapGestureRecognizer *)gesture {
    UILabel *timeLabel = (UILabel *)gesture.view;
    if (!timeLabel) return;
    
    UIViewController *viewController = [self findViewController:timeLabel];
    if (!viewController) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Time Zone Info"
                                                                 message:[NSString stringWithFormat:@"Time Zone ID: %@", timeLabel.timeZoneId ?: @"Unknown"]
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add action to open iOS Time Settings
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Time Settings"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction * _Nonnull action) {
        NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if ([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
            [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    // For iPad
    alert.popoverPresentationController.sourceView = timeLabel;
    alert.popoverPresentationController.sourceRect = timeLabel.bounds;
    
    [viewController presentViewController:alert animated:YES completion:nil];
}

+ (UIViewController *)findViewController:(UIView *)view {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}

+ (void)updateTimeLabel:(UILabel *)timeLabel withTimeZone:(NSTimeZone *)timeZone {
    if (!timeZone || !timeLabel) return;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.timeZone = timeZone;
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    formatter.dateFormat = @"h:mm a";
    
    NSString *currentTime = [formatter stringFromDate:[NSDate date]];
    timeLabel.text = currentTime;
}

+ (void)fetchCountryForCoordinates:(double)lat longitude:(double)lon completion:(void (^)(NSString *countryCode, NSString *flag))completion {
    // Create URL for OpenStreetMap Nominatim reverse geocoding
    NSString *urlString = [NSString stringWithFormat:@"https://nominatim.openstreetmap.org/reverse?format=json&lat=%.6f&lon=%.6f&zoom=18&addressdetails=1", lat, lon];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"WeaponX iOS App" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:10.0];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
            return;
        }
        
        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError || !json || ![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
            return;
        }
        
        NSDictionary *address = json[@"address"];
        NSString *countryCode = address[@"country_code"];
        
        if (!countryCode) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
            return;
        }
        
        NSString *flag = [self flagEmojiForCountryCode:countryCode];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(countryCode, flag);
        });
    }];
    
    [task resume];
}

+ (NSString *)flagEmojiForCountryCode:(NSString *)countryCode {
    if (!countryCode || countryCode.length != 2) {
        return nil;
    }
    
    countryCode = [countryCode uppercaseString];
    
    // Create array of country codes and corresponding emojis
    NSDictionary *flagEmojis = @{
        @"US": @"🇺🇸", @"GB": @"🇬🇧", @"CA": @"🇨🇦", @"AU": @"🇦🇺",
        @"IN": @"🇮🇳", @"JP": @"🇯🇵", @"DE": @"🇩🇪", @"FR": @"🇫🇷",
        @"IT": @"🇮🇹", @"ES": @"🇪🇸", @"BR": @"🇧🇷", @"RU": @"🇷🇺",
        @"CN": @"🇨🇳", @"KR": @"🇰🇷", @"ID": @"🇮🇩", @"MX": @"🇲🇽",
        @"NL": @"🇳🇱", @"TR": @"🇹🇷", @"SA": @"🇸🇦", @"CH": @"🇨🇭",
        @"SE": @"🇸🇪", @"PL": @"🇵🇱", @"BE": @"🇧🇪", @"IR": @"🇮🇷",
        @"NO": @"🇳🇴", @"AT": @"🇦🇹", @"IL": @"🇮🇱", @"DK": @"🇩🇰",
        @"SG": @"🇸🇬", @"FI": @"🇫🇮", @"NZ": @"🇳🇿", @"MY": @"🇲🇾",
        @"TH": @"🇹🇭", @"AE": @"🇦🇪", @"PH": @"🇵🇭", @"IE": @"🇮🇪",
        @"PT": @"🇵🇹", @"GR": @"🇬🇷", @"CZ": @"🇨🇿", @"VN": @"🇻🇳",
        @"RO": @"🇷🇴", @"ZA": @"🇿🇦", @"UA": @"🇺🇦", @"HK": @"🇭🇰",
        @"HU": @"🇭🇺", @"BG": @"🇧🇬", @"HR": @"🇭🇷", @"LT": @"🇱🇹",
        @"EE": @"🇪🇪", @"SK": @"🇸🇰"
    };
    
    NSString *flag = flagEmojis[countryCode];
    if (!flag) {
        flag = [[NSString alloc] initWithFormat:@"%C%C",
                (unichar)(0x1F1E6 + [countryCode characterAtIndex:0] - 'A'),
                (unichar)(0x1F1E6 + [countryCode characterAtIndex:1] - 'A')];
    }
    
    return flag;
}

// Add method to show IP details when IP label is tapped
+ (void)showIPDetails:(UITapGestureRecognizer *)gesture {
    UILabel *ipLabel = (UILabel *)gesture.view;
    if (!ipLabel) return;
    
    UIViewController *viewController = [self findViewController:ipLabel];
    if (!viewController) return;
    
    // Get IP details from the label
    NSString *city = ipLabel.ipCity ?: @"Unknown";
    NSString *isp = ipLabel.ipISP ?: @"Unknown";
    NSString *timezoneName = ipLabel.ipTimezoneName ?: @"Unknown";
    
    // Format the message
    NSString *message = [NSString stringWithFormat:@"City: %@\nISP: %@\nTimezone: %@", 
                          city, isp, timezoneName];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IP Information"
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy IP Info"
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction * _Nonnull action) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = message;
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    // For iPad
    alert.popoverPresentationController.sourceView = ipLabel;
    alert.popoverPresentationController.sourceRect = ipLabel.bounds;
    
    [viewController presentViewController:alert animated:YES completion:nil];
}

@end 