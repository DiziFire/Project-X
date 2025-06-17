#import "SerialNumberManager.h"
#import <Security/Security.h>
#import <sys/sysctl.h>
#import <mach-o/dyld.h>

@interface SerialNumberManager ()
@property (nonatomic, strong) NSString *currentIdentifier;
@property (nonatomic, strong) NSError *error;
@end

@implementation SerialNumberManager

+ (instancetype)sharedManager {
    static SerialNumberManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

+ (void)initialize {
    if (self == [SerialNumberManager class]) {
        atexit_b(^{
            [[SerialNumberManager sharedManager] clearSensitiveData];
        });
    }
}

- (BOOL)isBeingDebugged {
    int name[4];
    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    
    name[0] = CTL_KERN;
    name[1] = KERN_PROC;
    name[2] = KERN_PROC_PID;
    name[3] = getpid();
    
    if (sysctl(name, 4, &info, &info_size, NULL, 0) == -1) {
        return NO;
    }
    
    return ((info.kp_proc.p_flag & P_TRACED) != 0);
}

- (BOOL)isEnvironmentSecure {
    // Check for debugging
    if ([self isBeingDebugged]) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                       code:4003 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Debug environment detected"}];
        return NO;
    }
    
    // Basic integrity check
    if (![self verifyCodeIntegrity]) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                       code:4004 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Code integrity check failed"}];
        return NO;
    }
    
    return YES;
}

- (BOOL)verifyCodeIntegrity {
    // Basic dyld image count check
    uint32_t count = _dyld_image_count();
    if (count < 1) return NO;
    
    // You can add more integrity checks here
    return YES;
}

- (void)clearSensitiveData {
    if (self.currentIdentifier) {
        char *ptr = (char *)[self.currentIdentifier UTF8String];
        size_t len = [self.currentIdentifier length];
        if (ptr && len > 0) {
            memset(ptr, 0, len);
        }
        self.currentIdentifier = nil;
    }
}

- (NSString *)generateSerialNumber {
    // Add security checks
    if (![self isEnvironmentSecure]) {
        return nil;
    }
    
    self.error = nil;
    
    // Add random delay to avoid pattern detection
    usleep(arc4random_uniform(50000));  // 0-50ms delay
    
    // Define valid prefixes for USA-based Apple devices
    NSArray *prefixes = @[@"C02", @"FVF", @"DLXJ", @"GG78", @"HC79"];
    
    // Use pattern variation
    static int patternIndex = 0;
    patternIndex = (patternIndex + 1) % prefixes.count;
    NSString *prefix = prefixes[patternIndex];
    
    // Create a mutable string with the prefix
    NSMutableString *serialNumber = [NSMutableString stringWithString:prefix];
    
    // Generate random alphanumeric characters for the rest
    // Skip I, O, 1, 0 to avoid confusion (common in Apple serial numbers)
    const char *chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    NSInteger remainingLength = (prefix.length == 3) ? 8 : 7;
    
    for (int i = 0; i < remainingLength; i++) {
        uint32_t randomValue;
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomValue), (uint8_t *)&randomValue) == errSecSuccess) {
            [serialNumber appendFormat:@"%c", chars[randomValue % strlen(chars)]];
        } else {
            self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                           code:4001 
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate secure random number for serial"}];
            return nil;
        }
    }
    
    // Validate the generated serial number
    if ([self isValidSerialNumber:serialNumber]) {
        [self clearSensitiveData];  // Clear any previous value securely
        self.currentIdentifier = [serialNumber copy];
        return self.currentIdentifier;
    }
    
    self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                   code:4002 
                               userInfo:@{NSLocalizedDescriptionKey: @"Generated serial number failed validation"}];
    return nil;
}

- (NSString *)currentSerialNumber {
    if (![self isEnvironmentSecure]) {
        return nil;
    }
    return self.currentIdentifier;
}

- (void)setCurrentSerialNumber:(NSString *)serialNumber {
    if (![self isEnvironmentSecure]) {
        return;
    }
    
    if ([self isValidSerialNumber:serialNumber]) {
        [self clearSensitiveData];  // Clear any previous value securely
        self.currentIdentifier = [serialNumber copy];
    }
}

- (BOOL)isValidSerialNumber:(NSString *)serialNumber {
    if (!serialNumber) return NO;
    
    if (![self isEnvironmentSecure]) {
        return NO;
    }
    
    // Check format using regex for various Apple device serial number formats
    // Pattern matches common prefixes followed by 7-8 alphanumeric characters
    NSString *pattern = @"^(C02|FVF|DLXJ|GG78|HC79)[0-9A-Z]{7,8}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:0
                                                                           error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:serialNumber
                                               options:0
                                                 range:NSMakeRange(0, serialNumber.length)];
    
    return matches == 1;
}

- (NSError *)lastError {
    return self.error;
}

- (void)dealloc {
    [self clearSensitiveData];
}

@end 