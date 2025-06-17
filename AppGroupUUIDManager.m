#import "AppGroupUUIDManager.h"
#import "ProjectXLogging.h"

@interface AppGroupUUIDManager ()
@property (nonatomic, strong) NSString *currentIdentifier;
@property (nonatomic, strong) NSError *error;
@end

@implementation AppGroupUUIDManager

+ (instancetype)sharedManager {
    static AppGroupUUIDManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSString *)generateAppGroupUUID {
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
        return uuid;
    }
    
    // If validation failed, return error
    self.error = [NSError errorWithDomain:@"com.weaponx.AppGroupUUIDManager" 
                                     code:1001 
                                 userInfo:@{NSLocalizedDescriptionKey: @"Generated App Group UUID failed validation"}];
    return nil;
}

- (NSString *)currentAppGroupUUID {
    return self.currentIdentifier;
}

- (void)setCurrentAppGroupUUID:(NSString *)uuid {
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