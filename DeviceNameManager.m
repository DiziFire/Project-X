#import "DeviceNameManager.h"
#import <Security/Security.h>
#import <time.h>

@interface DeviceNameManager ()
@property (nonatomic, strong) NSString *currentIdentifier;
@property (nonatomic, strong) NSError *error;
@end

@implementation DeviceNameManager

+ (instancetype)sharedManager {
    static DeviceNameManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSString *)generateDeviceName {
    self.error = nil;
    
    // List of iPhone models from 8 Plus to 15 Pro Max
    NSArray *iPhoneModels = @[
        @"iPhone 8 Plus",
        @"iPhone X",
        @"iPhone XR",
        @"iPhone XS",
        @"iPhone XS Max",
        @"iPhone 11",
        @"iPhone 11 Pro",
        @"iPhone 11 Pro Max",
        @"iPhone 12",
        @"iPhone 12 mini",
        @"iPhone 12 Pro",
        @"iPhone 12 Pro Max",
        @"iPhone 13",
        @"iPhone 13 mini",
        @"iPhone 13 Pro",
        @"iPhone 13 Pro Max",
        @"iPhone 14",
        @"iPhone 14 Plus",
        @"iPhone 14 Pro",
        @"iPhone 14 Pro Max",
        @"iPhone 15",
        @"iPhone 15 Plus",
        @"iPhone 15 Pro",
        @"iPhone 15 Pro Max"
    ];
    
    // Common first names in the USA
    NSArray *usaFirstNames = @[
        @"Michael", @"Christopher", @"Jessica", @"Matthew", @"Ashley", @"Jennifer", 
        @"Joshua", @"Amanda", @"Daniel", @"David", @"James", @"Robert", @"John", 
        @"Joseph", @"Andrew", @"Ryan", @"Brandon", @"Jason", @"Justin", @"Sarah", 
        @"William", @"Jonathan", @"Stephanie", @"Brian", @"Nicole", @"Nicholas", 
        @"Anthony", @"Heather", @"Eric", @"Elizabeth", @"Adam", @"Megan", @"Melissa", 
        @"Kevin", @"Steven", @"Thomas", @"Timothy", @"Christina", @"Kyle", @"Rachel", 
        @"Laura", @"Lauren", @"Amber", @"Brittany", @"Danielle", @"Richard", @"Kimberly", 
        @"Jeffrey", @"Amy", @"Crystal", @"Michelle", @"Tiffany", @"Jeremy", @"Benjamin", 
        @"Mark", @"Emily", @"Aaron", @"Charles", @"Rebecca", @"Jacob", @"Stephen", 
        @"Patrick", @"Sean", @"Erin", @"Zachary", @"Jamie", @"Kelly", @"Samantha", 
        @"Nathan", @"Sara", @"Dustin", @"Paul", @"Angela", @"Tyler", @"Scott", 
        @"Katherine", @"Andrea", @"Gregory", @"Erica", @"Mary", @"Travis", @"Lisa", 
        @"Kenneth", @"Bryan", @"Lindsey", @"Kristen", @"Jose", @"Alexander", @"Jesse", 
        @"Katie", @"Lindsay", @"Shannon", @"Vanessa", @"Courtney", @"Christine", 
        @"Alicia", @"Cody", @"Allison", @"Bradley", @"Samuel", @"Emma", @"Noah", 
        @"Olivia", @"Liam", @"Ava", @"Ethan", @"Sophia", @"Isabella", @"Mason", 
        @"Mia", @"Lucas", @"Charlotte", @"Aiden", @"Harper", @"Elijah", @"Amelia", 
        @"Oliver", @"Abigail", @"Ella", @"Logan", @"Madison", @"Jackson", @"Lily", 
        @"Avery", @"Carter", @"Chloe", @"Grayson", @"Evelyn", @"Leo", @"Sofia", 
        @"Lincoln", @"Hannah", @"Henry", @"Aria", @"Gabriel", @"Grace", @"Owen",
        @"Victoria", @"Zoey", @"Isaac", @"Brooklyn", @"Levi", @"Zoe", @"Julian",
        @"Natalie", @"Caleb", @"Addison", @"Luke", @"Leah", @"Nathan", @"Aubrey", 
        @"Jack", @"Aurora", @"Isaiah", @"Savannah", @"Eli", @"Audrey", @"Dylan"
    ];
    
    // Common last names in the USA
    NSArray *usaLastNames = @[
        @"Smith", @"Johnson", @"Williams", @"Jones", @"Brown", @"Davis", @"Miller", 
        @"Wilson", @"Moore", @"Taylor", @"Anderson", @"Thomas", @"Jackson", @"White", 
        @"Harris", @"Martin", @"Thompson", @"Garcia", @"Martinez", @"Robinson", @"Clark", 
        @"Rodriguez", @"Lewis", @"Lee", @"Walker", @"Hall", @"Allen", @"Young", @"Hernandez", 
        @"King", @"Wright", @"Lopez", @"Hill", @"Scott", @"Green", @"Adams", @"Baker", 
        @"Gonzalez", @"Nelson", @"Carter", @"Mitchell", @"Perez", @"Roberts", @"Turner", 
        @"Phillips", @"Campbell", @"Parker", @"Evans", @"Edwards", @"Collins", @"Stewart", 
        @"Sanchez", @"Morris", @"Rogers", @"Reed", @"Cook", @"Morgan", @"Bell", @"Murphy", 
        @"Bailey", @"Rivera", @"Cooper", @"Richardson", @"Cox", @"Howard", @"Ward", @"Torres", 
        @"Peterson", @"Gray", @"Ramirez", @"James", @"Watson", @"Brooks", @"Kelly", @"Sanders", 
        @"Price", @"Bennett", @"Wood", @"Barnes", @"Ross", @"Henderson", @"Coleman", @"Jenkins", 
        @"Perry", @"Powell", @"Long", @"Patterson", @"Hughes", @"Flores", @"Washington", @"Butler", 
        @"Simmons", @"Foster", @"Gonzales", @"Bryant", @"Alexander", @"Russell", @"Griffin", 
        @"Diaz", @"Hayes"
    ];
    
    // Common US locations/states/cities for naming patterns
    NSArray *usaLocations = @[
        @"NYC", @"LA", @"Chicago", @"Houston", @"Phoenix", @"Philly", @"San Antonio", 
        @"San Diego", @"Dallas", @"Austin", @"Seattle", @"Denver", @"Boston", @"Vegas", 
        @"Miami", @"Oakland", @"Jersey", @"Portland", @"ATL", @"SF", @"NOLA", @"DC", 
        @"Nashville", @"SLC", @"Detroit", @"Columbus", @"Indy", @"Charlotte", @"Memphis", 
        @"AZ", @"CA", @"TX", @"FL", @"NY", @"PA", @"IL", @"OH", @"GA", @"NC", @"MI", 
        @"NJ", @"VA", @"WA", @"MN", @"CO", @"AL", @"SC", @"LA", @"KY", @"OR", @"OK", 
        @"CT", @"UT", @"IA", @"NV", @"AR", @"MS", @"KS", @"NE", @"WV", @"ID", @"HI", 
        @"NH", @"ME", @"MT", @"DE", @"SD", @"ND", @"AK", @"VT", @"WY", @"Home", @"Work", 
        @"Office"
    ];
    
    // Personalized descriptors
    NSArray *personalDescriptors = @[
        @"Personal", @"Pro", @"Work", @"Home", @"Main", @"Family", @"Mobile", @"Primary",
        @"New", @"Travel", @"Gaming", @"Backup", @"Private", @"", @"", @"", @"", @""
    ];
    
    // Generate a random device name
    NSMutableString *deviceName = [NSMutableString string];
    
    // Determine which naming pattern to use
    uint32_t patternSelector;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(patternSelector), (uint8_t *)&patternSelector) != errSecSuccess) {
        self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                       code:3001 
                                   userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate secure random number"}];
        return nil;
    }
    
    switch (patternSelector % 5) {
        case 0: { 
            // Pattern: "[First Name]'s iPhone"
            uint32_t nameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nameIndex), (uint8_t *)&nameIndex) != errSecSuccess) {
                // Fall back to a simpler deterministic behavior on error
                nameIndex = (uint32_t)time(NULL);
            }
            NSString *firstName = usaFirstNames[nameIndex % usaFirstNames.count];
            [deviceName appendFormat:@"%@'s iPhone", firstName];
            break;
        }
        case 1: { 
            // Pattern: "iPhone [First Name]" or "iPhone-[First Name]"
            uint32_t nameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nameIndex), (uint8_t *)&nameIndex) != errSecSuccess) {
                nameIndex = (uint32_t)time(NULL);
            }
            NSString *firstName = usaFirstNames[nameIndex % usaFirstNames.count];
            
            uint32_t dashOrSpace;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(dashOrSpace), (uint8_t *)&dashOrSpace) != errSecSuccess) {
                dashOrSpace = (uint32_t)time(NULL);
            }
            
            if (dashOrSpace % 2 == 0) {
                [deviceName appendFormat:@"iPhone %@", firstName];
            } else {
                [deviceName appendFormat:@"iPhone-%@", firstName];
            }
            break;
        }
        case 2: { 
            // Pattern: "[First Name] [Last Name]'s iPhone"
            uint32_t firstNameIndex, lastNameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(firstNameIndex), (uint8_t *)&firstNameIndex) != errSecSuccess) {
                firstNameIndex = (uint32_t)time(NULL);
            }
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(lastNameIndex), (uint8_t *)&lastNameIndex) != errSecSuccess) {
                lastNameIndex = (uint32_t)(time(NULL) + 1);
            }
            
            NSString *firstName = usaFirstNames[firstNameIndex % usaFirstNames.count];
            NSString *lastName = usaLastNames[lastNameIndex % usaLastNames.count];
            
            [deviceName appendFormat:@"%@ %@'s iPhone", firstName, lastName];
            break;
        }
        case 3: { 
            // Pattern: "iPhone [Location/State]"
            uint32_t locationIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(locationIndex), (uint8_t *)&locationIndex) != errSecSuccess) {
                locationIndex = (uint32_t)time(NULL);
            }
            NSString *location = usaLocations[locationIndex % usaLocations.count];
            
            [deviceName appendFormat:@"iPhone %@", location];
            break;
        }
        case 4: { 
            // Pattern: "[Specific iPhone Model] [Descriptor]"
            uint32_t modelIndex, descriptorIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(modelIndex), (uint8_t *)&modelIndex) != errSecSuccess) {
                modelIndex = (uint32_t)time(NULL);
            }
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(descriptorIndex), (uint8_t *)&descriptorIndex) != errSecSuccess) {
                descriptorIndex = (uint32_t)(time(NULL) + 1);
            }
            
            NSString *model = iPhoneModels[modelIndex % iPhoneModels.count];
            NSString *descriptor = personalDescriptors[descriptorIndex % personalDescriptors.count];
            
            if ([descriptor length] > 0) {
                [deviceName appendFormat:@"%@ %@", model, descriptor];
            } else {
                // If we got an empty descriptor, just use the model
                [deviceName appendString:model];
            }
            break;
        }
    }
    
    if ([self isValidDeviceName:deviceName]) {
        self.currentIdentifier = [deviceName copy];
        return self.currentIdentifier;
    }
    
    self.error = [NSError errorWithDomain:@"com.hydra.projectx" 
                                   code:3002 
                               userInfo:@{NSLocalizedDescriptionKey: @"Generated device name failed validation"}];
    return nil;
}

- (NSString *)currentDeviceName {
    return self.currentIdentifier;
}

- (void)setCurrentDeviceName:(NSString *)deviceName {
    if ([self isValidDeviceName:deviceName]) {
        self.currentIdentifier = [deviceName copy];
    }
}

- (BOOL)isValidDeviceName:(NSString *)deviceName {
    if (!deviceName) return NO;
    
    // Basic validation - ensure it's not empty and not too long
    if (deviceName.length == 0 || deviceName.length > 50) {
        return NO;
    }
    
    // Ensure it doesn't contain any invalid characters
    NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"<>:\"/\\|?*"];
    if ([deviceName rangeOfCharacterFromSet:invalidChars].location != NSNotFound) {
        return NO;
    }
    
    return YES;
}

- (NSError *)lastError {
    return self.error;
}

@end 