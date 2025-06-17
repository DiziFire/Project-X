#import "AppInstallUUIDManager.h"
#import "ProjectXLogging.h"

@interface AppInstallUUIDManager ()
@property (nonatomic, strong) NSString *currentIdentifier;
@property (nonatomic, strong) NSError *error;
@end

@implementation AppInstallUUIDManager

+ (instancetype)sharedManager {
    static AppInstallUUIDManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSString *)generateAppInstallUUID {
    // Generate a valid UUID format (8-4-4-4-12)
    NSMutableString *uuid = [NSMutableString string];
    
    // Characters for hex values
    const char chars[] = "0123456789abcdef";
    
    // First section (8 chars)
    for (int i = 0; i < 8; i++) {
        int randomValue = arc4random() % 16;
        [uuid appendFormat:@"%c", chars[randomValue]];
    }
    
    [uuid appendString:@"-"];
    
    // Second section (4 chars)
    for (int i = 0; i < 4; i++) {
        int randomValue = arc4random() % 16;
        [uuid appendFormat:@"%c", chars[randomValue]];
    }
    
    [uuid appendString:@"-"];
    
    // Third section (4 chars) - version 4 UUID
    [uuid appendString:@"4"];
    for (int i = 0; i < 3; i++) {
        int randomValue = arc4random() % 16;
        [uuid appendFormat:@"%c", chars[randomValue]];
    }
    
    [uuid appendString:@"-"];
    
    // Fourth section (4 chars) - variant
    int randomValue = arc4random() % 4 + 8; // 8, 9, A, or B
    [uuid appendFormat:@"%c", chars[randomValue]];
    for (int i = 0; i < 3; i++) {
        randomValue = arc4random() % 16;
        [uuid appendFormat:@"%c", chars[randomValue]];
    }
    
    [uuid appendString:@"-"];
    
    // Fifth section (12 chars)
    for (int i = 0; i < 12; i++) {
        randomValue = arc4random() % 16;
        [uuid appendFormat:@"%c", chars[randomValue]];
    }
    
    // Validate and return
    if ([self isValidUUID:uuid]) {
        self.currentIdentifier = [uuid copy];
        PXLog(@"[WeaponX] 📱 Generated App Install UUID: %@", uuid);
        return uuid;
    }
    
    // If validation failed, return error
    self.error = [NSError errorWithDomain:@"com.weaponx.AppInstallUUIDManager" 
                                     code:1001 
                                 userInfo:@{NSLocalizedDescriptionKey: @"Generated App Install UUID failed validation"}];
    return nil;
}

- (NSString *)currentAppInstallUUID {
    return self.currentIdentifier;
}

- (void)setCurrentAppInstallUUID:(NSString *)uuid {
    if ([self isValidUUID:uuid]) {
        self.currentIdentifier = [uuid copy];
    }
}

- (BOOL)isValidUUID:(NSString *)uuid {
    if (!uuid) return NO;
    
    // Verify format: 8-4-4-4-12 hexadecimal characters
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" 
                                                                           options:NSRegularExpressionCaseInsensitive 
                                                                             error:nil];
    
    NSUInteger matches = [regex numberOfMatchesInString:uuid 
                                                options:0 
                                                  range:NSMakeRange(0, uuid.length)];
    
    return matches == 1;
}

- (NSError *)lastError {
    return self.error;
}

@end 