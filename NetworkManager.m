#import "NetworkManager.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import "ProjectXLogging.h"

@implementation NetworkManager

+ (instancetype)sharedManager {
    static NetworkManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Carrier Methods

+ (NSArray *)getCarriersForCountry:(NSString *)countryCode {
    if ([countryCode.lowercaseString isEqualToString:@"us"]) {
        return [self getUSCarriers];
    } else if ([countryCode.lowercaseString isEqualToString:@"in"]) {
        return [self getIndiaCarriers];
    } else if ([countryCode.lowercaseString isEqualToString:@"ca"]) {
        return [self getCanadaCarriers];
    }
    
    // Return US carriers as default
    return [self getUSCarriers];
}

+ (NSDictionary *)getRandomCarrierForCountry:(NSString *)countryCode {
    NSArray *carriers = [self getCarriersForCountry:countryCode];
    if (carriers.count == 0) {
        return @{
            @"name": @"Unknown Carrier",
            @"mcc": @"000",
            @"mnc": @"00"
        };
    }
    
    NSUInteger randomIndex = arc4random_uniform((uint32_t)carriers.count);
    return carriers[randomIndex];
}

+ (NSArray *)getUSCarriers {
    return @[
        // Major Carriers
        @{@"name": @"Verizon", @"mcc": @"310", @"mnc": @"004"},
        @{@"name": @"Verizon", @"mcc": @"310", @"mnc": @"010"},
        @{@"name": @"Verizon", @"mcc": @"311", @"mnc": @"480"},
        
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"170"},
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"410"},
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"150"},
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"680"},
        
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"260"},
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"160"},
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"240"},
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"800"},
        
        @{@"name": @"Sprint", @"mcc": @"310", @"mnc": @"120"},
        @{@"name": @"Sprint", @"mcc": @"311", @"mnc": @"870"},
        @{@"name": @"Sprint", @"mcc": @"312", @"mnc": @"530"},
        
        // Regional Carriers without spaces
        @{@"name": @"Cellcom", @"mcc": @"311", @"mnc": @"210"}
    ];
}

+ (NSArray *)getIndiaCarriers {
    return @[
        @{@"name": @"Jio", @"mcc": @"405", @"mnc": @"840"},
        @{@"name": @"Jio", @"mcc": @"405", @"mnc": @"854"},
        @{@"name": @"Jio", @"mcc": @"405", @"mnc": @"855"},
        @{@"name": @"Jio", @"mcc": @"405", @"mnc": @"856"},
        @{@"name": @"Jio", @"mcc": @"405", @"mnc": @"857"},
        @{@"name": @"Airtel", @"mcc": @"404", @"mnc": @"45"},
        @{@"name": @"Airtel", @"mcc": @"404", @"mnc": @"49"},
        @{@"name": @"Airtel", @"mcc": @"404", @"mnc": @"70"},
        @{@"name": @"Airtel", @"mcc": @"404", @"mnc": @"90"},
        @{@"name": @"Airtel", @"mcc": @"404", @"mnc": @"92"},
        @{@"name": @"BSNL", @"mcc": @"404", @"mnc": @"34"},
        @{@"name": @"BSNL", @"mcc": @"404", @"mnc": @"38"},
        @{@"name": @"BSNL", @"mcc": @"404", @"mnc": @"51"},
        @{@"name": @"BSNL", @"mcc": @"404", @"mnc": @"53"},
        @{@"name": @"MTNL", @"mcc": @"404", @"mnc": @"68"},
        @{@"name": @"MTNL", @"mcc": @"404", @"mnc": @"69"}
    ];
}

+ (NSArray *)getCanadaCarriers {
    return @[
        @{@"name": @"Rogers", @"mcc": @"302", @"mnc": @"720"},
        @{@"name": @"Rogers", @"mcc": @"302", @"mnc": @"370"},
        @{@"name": @"Bell", @"mcc": @"302", @"mnc": @"610"},
        @{@"name": @"Bell", @"mcc": @"302", @"mnc": @"640"},
        @{@"name": @"Bell", @"mcc": @"302", @"mnc": @"651"},
        @{@"name": @"Telus", @"mcc": @"302", @"mnc": @"220"},
        @{@"name": @"Telus", @"mcc": @"302", @"mnc": @"221"},
        @{@"name": @"Freedom Mobile", @"mcc": @"302", @"mnc": @"490"},
        @{@"name": @"Videotron", @"mcc": @"302", @"mnc": @"500"},
        @{@"name": @"Videotron", @"mcc": @"302", @"mnc": @"510"},
        @{@"name": @"SaskTel", @"mcc": @"302", @"mnc": @"780"},
        @{@"name": @"Fido", @"mcc": @"302", @"mnc": @"370"},
        @{@"name": @"Koodo", @"mcc": @"302", @"mnc": @"220"},
        @{@"name": @"Chatr", @"mcc": @"302", @"mnc": @"720"},
        @{@"name": @"Cityfone", @"mcc": @"302", @"mnc": @"720"},
        @{@"name": @"7-Eleven Speak Out", @"mcc": @"302", @"mnc": @"720"}
    ];
}

#pragma mark - IP Address Methods

+ (NSString *)getCurrentLocalIPAddress {
    NSString *address = @"192.168.1.1"; // Default fallback
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    // Retrieve the current interfaces - returns 0 on success
    if (getifaddrs(&interfaces) == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on iOS
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}

+ (NSString *)generateSpoofedLocalIPAddressFromCurrent {
    NSString *currentIP = [self getCurrentLocalIPAddress];
    NSArray<NSString *> *parts = [currentIP componentsSeparatedByString:@"."];
    if (parts.count == 4) {
        // Change the last octet to a random value (2-253), not the original
        int lastOctet = [parts[3] intValue];
        int newLastOctet = lastOctet;
        int attempts = 0;
        while (newLastOctet == lastOctet && attempts < 10) {
            newLastOctet = 2 + arc4random_uniform(252); // 2-253
            attempts++;
        }
        NSString *spoofedIP = [NSString stringWithFormat:@"%@.%@.%@.%d", parts[0], parts[1], parts[2], newLastOctet];
        return spoofedIP;
    }
    // Fallback to random if parsing fails
    return [self getCurrentLocalIPAddress];
}

+ (NSString *)generateSpoofedLocalIPv6AddressFromCurrent {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET6) {
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    char ip6[INET6_ADDRSTRLEN];
                    struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)temp_addr->ifa_addr;
                    inet_ntop(AF_INET6, &sin6->sin6_addr, ip6, sizeof(ip6));
                    address = [NSString stringWithUTF8String:ip6];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    if (!address) {
        address = @"fe80::1234:abcd:5678:9abc";
    }
    // Spoof last segment
    NSArray *parts = [address componentsSeparatedByString:@":"];
    if (parts.count >= 2) {
        NSMutableArray *mutableParts = [parts mutableCopy];
        NSString *last = parts.lastObject;
        NSString *spoofedLast = [NSString stringWithFormat:@"%x", arc4random_uniform(0xFFFF)];
        if ([last length] > 0) {
            mutableParts[mutableParts.count-1] = spoofedLast;
        } else if (mutableParts.count > 1) {
            mutableParts[mutableParts.count-2] = spoofedLast;
        }
        return [mutableParts componentsJoinedByString:@":"];
    }
    return address;
}

#pragma mark - Profile-based IP Storage

// Helper method to get the path to the current profile's identity directory
+ (NSString *)profileIdentityPath {
    // Get current profile ID
    NSString *profileId = nil;
    NSString *centralInfoPath = @"/var/jb/var/mobile/Library/WeaponX/Profiles/current_profile_info.plist";
    NSDictionary *centralInfo = [NSDictionary dictionaryWithContentsOfFile:centralInfoPath];
    
    profileId = centralInfo[@"ProfileId"];
    if (!profileId) {
        // If not found, check the legacy active_profile_info.plist
        NSString *activeInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
        NSDictionary *activeInfo = [NSDictionary dictionaryWithContentsOfFile:activeInfoPath];
        profileId = activeInfo[@"ProfileId"];
        
        PXLog(@"[WeaponX] 🔍 NetworkManager - Primary profile info not found, checked backup: %@", profileId ? @"✅ found" : @"❌ not found");
    }
    
    if (!profileId) {
        PXLog(@"[WeaponX] Warning: No active profile ID found for NetworkManager");
        // Fallback approach: try to find any profile directory
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *profilesDir = @"/var/jb/var/mobile/Library/WeaponX/Profiles";
        NSError *error = nil;
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:profilesDir error:&error];
        
        if (!error && contents.count > 0) {
            // Use the first directory found as a fallback
            for (NSString *item in contents) {
                BOOL isDir = NO;
                NSString *fullPath = [profilesDir stringByAppendingPathComponent:item];
                [fileManager fileExistsAtPath:fullPath isDirectory:&isDir];
                
                if (isDir) {
                    profileId = item;
                    PXLog(@"[WeaponX] NetworkManager using fallback profile ID: %@", profileId);
                    break;
                }
            }
        }
        
        // If we still don't have a profile ID, give up
        if (!profileId) {
            PXLog(@"[WeaponX] Error: NetworkManager could not find any profile");
            return nil;
        }
    }
    
    // Build the path to this profile's identity directory
    NSString *profileDir = [NSString stringWithFormat:@"/var/jb/var/mobile/Library/WeaponX/Profiles/%@", profileId];
    NSString *identityDir = [profileDir stringByAppendingPathComponent:@"identity"];
    
    // Create the directory if it doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:identityDir]) {
        NSDictionary *attributes = @{
            NSFilePosixPermissions: @0755,
            NSFileOwnerAccountName: @"mobile"
        };
        
        NSError *dirError = nil;
        if (![fileManager createDirectoryAtPath:identityDir 
                    withIntermediateDirectories:YES 
                                     attributes:attributes
                                          error:&dirError]) {
            PXLog(@"[WeaponX] Error creating identity directory for NetworkManager: %@", dirError);
            return nil;
        }
    }
    
    return identityDir;
}

+ (BOOL)saveLocalIPAddress:(NSString *)ipAddress {
    NSString *identityDir = [self profileIdentityPath];
    if (!identityDir) {
        PXLog(@"[WeaponX] Error: Could not get profile identity path for NetworkManager");
        return NO;
    }
    // Generate spoofed IPv6
    NSString *ipv6 = [self generateSpoofedLocalIPv6AddressFromCurrent];
    NSDictionary *networkDict = @{
        @"localIPAddress": ipAddress ?: @"",
        @"localIPv6Address": ipv6 ?: @"",
        @"lastUpdated": [NSDate date]
    };
    NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
    BOOL success = [networkDict writeToFile:networkPath atomically:YES];
    if (success) {
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: [NSMutableDictionary dictionary];
        deviceIds[@"LocalIPAddress"] = ipAddress;
        deviceIds[@"LocalIPv6Address"] = ipv6;
        success = [deviceIds writeToFile:deviceIdsPath atomically:YES];
    }
    PXLog(@"[WeaponX] %@ Local IP Address (IPv4/IPv6) saved to profile: %@ / %@", success ? @"✅" : @"❌", ipAddress, ipv6);
    return success;
}

+ (NSString *)getSavedLocalIPAddress {
    return [self getSavedLocalIPAddressWithForcedRefresh:NO];
}

+ (NSString *)getSavedLocalIPAddressWithForcedRefresh:(BOOL)forceRefresh {
    // Get path to current profile's identity directory
    NSString *identityDir = [self profileIdentityPath];
    if (!identityDir) {
        PXLog(@"[WeaponX] Error: Could not get profile identity path for NetworkManager");
        return nil;
    }
    
    // If forced refresh is requested, always generate a new local IP
    if (forceRefresh) {
        NSString *localIP = [self generateSpoofedLocalIPAddressFromCurrent];
        
        // Save it for future use
        [self saveLocalIPAddress:localIP];
        
        PXLog(@"[WeaponX] Forced refresh of local IP address: %@", localIP);
        return localIP;
    }
    
    // Try to read from network_settings.plist
    NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
    NSDictionary *networkDict = [NSDictionary dictionaryWithContentsOfFile:networkPath];
    
    NSString *localIP = networkDict[@"localIPAddress"];
    
    // If not found in dedicated file, try the combined device_ids.plist
    if (!localIP) {
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
        localIP = deviceIds[@"LocalIPAddress"];
    }
    
    // If still not found, get current IP or generate a random one
    if (!localIP) {
        localIP = [self getCurrentLocalIPAddress];
        // Save it for future use
        [self saveLocalIPAddress:localIP];
        PXLog(@"[WeaponX] No saved Local IP found, using current: %@", localIP);
    }
    
    return localIP;
}

+ (NSString *)getSavedLocalIPv6Address {
    NSString *identityDir = [self profileIdentityPath];
    if (!identityDir) return nil;
    NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
    NSDictionary *networkDict = [NSDictionary dictionaryWithContentsOfFile:networkPath];
    NSString *ipv6 = networkDict[@"localIPv6Address"];
    if (!ipv6) {
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
        ipv6 = deviceIds[@"LocalIPv6Address"];
    }
    if (!ipv6) {
        ipv6 = [self generateSpoofedLocalIPv6AddressFromCurrent];
        [self saveLocalIPAddress:[self getCurrentLocalIPAddress]];
    }
    return ipv6;
}

#pragma mark - Profile-based Carrier Storage

+ (BOOL)saveCarrierDetails:(NSString *)carrierName mcc:(NSString *)mcc mnc:(NSString *)mnc {
    // Get path to current profile's identity directory
    NSString *identityDir = [self profileIdentityPath];
    if (!identityDir) {
        PXLog(@"[WeaponX] Error: Could not get profile identity path for carrier details");
        return NO;
    }
    
    // Create carrier details dictionary
    NSDictionary *carrierDict = @{
        @"carrierName": carrierName ?: @"",
        @"mcc": mcc ?: @"",
        @"mnc": mnc ?: @"",
        @"lastUpdated": [NSDate date]
    };
    
    // Save to carrier_details.plist
    NSString *carrierPath = [identityDir stringByAppendingPathComponent:@"carrier_details.plist"];
    BOOL success = [carrierDict writeToFile:carrierPath atomically:YES];
    
    // Also update the network_settings.plist to keep all network data together
    if (success) {
        NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
        NSMutableDictionary *networkDict = [NSMutableDictionary dictionaryWithContentsOfFile:networkPath] ?: [NSMutableDictionary dictionary];
        
        networkDict[@"carrierName"] = carrierName ?: @"";
        networkDict[@"mcc"] = mcc ?: @"";
        networkDict[@"mnc"] = mnc ?: @"";
        [networkDict setObject:[NSDate date] forKey:@"lastUpdated"];
        
        success = [networkDict writeToFile:networkPath atomically:YES];
    }
    
    // Also update the combined device_ids.plist
    if (success) {
        NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
        NSMutableDictionary *deviceIds = [NSMutableDictionary dictionaryWithContentsOfFile:deviceIdsPath] ?: [NSMutableDictionary dictionary];
        
        deviceIds[@"CarrierName"] = carrierName ?: @"";
        deviceIds[@"CarrierMCC"] = mcc ?: @"";
        deviceIds[@"CarrierMNC"] = mnc ?: @"";
        
        success = [deviceIds writeToFile:deviceIdsPath atomically:YES];
    }
    
    PXLog(@"[WeaponX] %@ Carrier details saved to profile: %@ (%@-%@)", 
           success ? @"✅" : @"❌", carrierName ?: @"Unknown", mcc ?: @"", mnc ?: @"");
    
    return success;
}

+ (NSDictionary *)getSavedCarrierDetails {
    return [self getSavedCarrierDetailsWithForcedRefresh:NO];
}

+ (NSDictionary *)getSavedCarrierDetailsWithForcedRefresh:(BOOL)forceRefresh {
    // Get path to current profile's identity directory
    NSString *identityDir = [self profileIdentityPath];
    if (!identityDir) {
        PXLog(@"[WeaponX] Error: Could not get profile identity path for carrier details");
        return nil;
    }
    
    // If forced refresh is requested, always generate new carrier details
    if (forceRefresh) {
        NSString *countryCode = [self getCurrentCountryCode] ?: @"us";
        NSDictionary *carrierInfo = [self getRandomCarrierForCountry:countryCode];
        
        // Save the generated carrier info
        [self saveCarrierDetails:carrierInfo[@"name"] mcc:carrierInfo[@"mcc"] mnc:carrierInfo[@"mnc"]];
        
        PXLog(@"[WeaponX] Forced refresh of carrier details: %@ (%@-%@)", 
              carrierInfo[@"name"], carrierInfo[@"mcc"], carrierInfo[@"mnc"]);
        
        return carrierInfo;
    }
    
    // Try to read from carrier_details.plist first
    NSString *carrierPath = [identityDir stringByAppendingPathComponent:@"carrier_details.plist"];
    NSDictionary *carrierDict = [NSDictionary dictionaryWithContentsOfFile:carrierPath];
    
    if (carrierDict && carrierDict[@"carrierName"] && carrierDict[@"mcc"] && carrierDict[@"mnc"]) {
        return @{
            @"name": carrierDict[@"carrierName"],
            @"mcc": carrierDict[@"mcc"],
            @"mnc": carrierDict[@"mnc"]
        };
    }
    
    // If not found, try reading from network_settings.plist
    NSString *networkPath = [identityDir stringByAppendingPathComponent:@"network_settings.plist"];
    NSDictionary *networkDict = [NSDictionary dictionaryWithContentsOfFile:networkPath];
    
    if (networkDict && networkDict[@"carrierName"] && networkDict[@"mcc"] && networkDict[@"mnc"]) {
        return @{
            @"name": networkDict[@"carrierName"],
            @"mcc": networkDict[@"mcc"],
            @"mnc": networkDict[@"mnc"]
        };
    }
    
    // If not found, try the combined device_ids.plist
    NSString *deviceIdsPath = [identityDir stringByAppendingPathComponent:@"device_ids.plist"];
    NSDictionary *deviceIds = [NSDictionary dictionaryWithContentsOfFile:deviceIdsPath];
    
    if (deviceIds && deviceIds[@"CarrierName"] && deviceIds[@"CarrierMCC"] && deviceIds[@"CarrierMNC"]) {
        return @{
            @"name": deviceIds[@"CarrierName"],
            @"mcc": deviceIds[@"CarrierMCC"],
            @"mnc": deviceIds[@"CarrierMNC"]
        };
    }
    
    // If still not found, generate default values based on country code (US as fallback)
    NSString *countryCode = [self getCurrentCountryCode] ?: @"us";
    NSDictionary *carrierInfo = [self getRandomCarrierForCountry:countryCode];
    
    // Save the generated carrier info for future use
    [self saveCarrierDetails:carrierInfo[@"name"] mcc:carrierInfo[@"mcc"] mnc:carrierInfo[@"mnc"]];
    
    PXLog(@"[WeaponX] No saved carrier details found, generated: %@ (%@-%@)", 
          carrierInfo[@"name"], carrierInfo[@"mcc"], carrierInfo[@"mnc"]);
    
    return carrierInfo;
}

// Helper method to get current country code (can be extended in the future)
+ (NSString *)getCurrentCountryCode {
    // For now, we'll return nil which will default to "us" in the caller
    // In the future, this could be enhanced to detect the actual country
    return nil;
}

@end
