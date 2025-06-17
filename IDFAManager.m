#import "IDFAManager.h"
#import <AdSupport/AdSupport.h>
#import <Security/Security.h>

@interface IDFAManager ()
@property (nonatomic, strong) NSString *currentIdentifier;
@property (nonatomic, strong) NSError *error;
@end

@implementation IDFAManager

+ (instancetype)sharedManager {
    static IDFAManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSString *)generateIDFA {
    self.error = nil;
    
    // Generate a valid IDFA format (8-4-4-4-12)
    NSMutableString *idfa = [NSMutableString string];
    const char *chars = "0123456789ABCDEF";
    
    for (int i = 0; i < 32; i++) {
        if (i == 8 || i == 12 || i == 16 || i == 20) {
            [idfa appendString:@"-"];
        }
        uint32_t randomValue;
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomValue), (uint8_t *)&randomValue) == errSecSuccess) {
            [idfa appendFormat:@"%c", chars[randomValue % 16]];
        } else {
            self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                           code:1001 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate secure random number"}];
            return nil;
        }
    }
    
    if ([self isValidIDFA:idfa]) {
        self.currentIdentifier = [idfa copy];
        return self.currentIdentifier;
    }
    
    self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                   code:1002 
                               userInfo:@{NSLocalizedDescriptionKey: @"Generated IDFA failed validation"}];
    return nil;
}

- (NSString *)currentIDFA {
    return self.currentIdentifier;
}

- (void)setCurrentIDFA:(NSString *)idfa {
    if ([self isValidIDFA:idfa]) {
        self.currentIdentifier = [idfa copy];
    }
}

- (BOOL)isValidIDFA:(NSString *)idfa {
    if (!idfa) return NO;
    
    // Check format using regex
    NSString *pattern = @"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:0
                                                                           error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:idfa
                                               options:0
                                                 range:NSMakeRange(0, idfa.length)];
    
    return matches == 1;
}

- (NSError *)lastError {
    return self.error;
}

@end