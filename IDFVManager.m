#import "IDFVManager.h"
#import <Security/Security.h>

@interface IDFVManager ()
@property (nonatomic, strong) NSString *currentIdentifier;
@property (nonatomic, strong) NSError *error;
@end

@implementation IDFVManager

+ (instancetype)sharedManager {
    static IDFVManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSString *)generateIDFV {
    self.error = nil;
    
    // Generate a valid IDFV format (8-4-4-4-12)
    NSMutableString *idfv = [NSMutableString string];
    const char *chars = "0123456789ABCDEF";
    
    for (int i = 0; i < 32; i++) {
        if (i == 8 || i == 12 || i == 16 || i == 20) {
            [idfv appendString:@"-"];
        }
        uint32_t randomValue;
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomValue), (uint8_t *)&randomValue) == errSecSuccess) {
            [idfv appendFormat:@"%c", chars[randomValue % 16]];
        } else {
            self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                           code:2001 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate secure random number"}];
            return nil;
        }
    }
    
    if ([self isValidIDFV:idfv]) {
        self.currentIdentifier = [idfv copy];
        return self.currentIdentifier;
    }
    
    self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                   code:2002 
                               userInfo:@{NSLocalizedDescriptionKey: @"Generated IDFV failed validation"}];
    return nil;
}

- (NSString *)currentIDFV {
    return self.currentIdentifier;
}

- (void)setCurrentIDFV:(NSString *)idfv {
    if ([self isValidIDFV:idfv]) {
        self.currentIdentifier = [idfv copy];
    }
}

- (BOOL)isValidIDFV:(NSString *)idfv {
    if (!idfv) return NO;
    
    // Check format using regex
    NSString *pattern = @"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:0
                                                                           error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:idfv
                                               options:0
                                                 range:NSMakeRange(0, idfv.length)];
    
    return matches == 1;
}

- (NSError *)lastError {
    return self.error;
}

@end