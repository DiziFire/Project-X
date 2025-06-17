#import <Foundation/Foundation.h>

@class Profile;

NS_ASSUME_NONNULL_BEGIN

@interface Profile : NSObject <NSSecureCoding>

@property (nonatomic, strong, readonly) NSString *profileId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *shortDescription;
@property (nonatomic, strong) NSString *iconName;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *lastUsed;
@property (nonatomic, strong) NSDictionary *settings;

- (instancetype)initWithName:(NSString *)name iconName:(NSString *)iconName;
- (instancetype)initWithName:(NSString *)name shortDescription:(NSString *)shortDescription iconName:(NSString *)iconName;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)toDictionary;

@end

@interface ProfileManager : NSObject

@property (nonatomic, strong, readonly) NSArray<Profile *> *profiles;
@property (nonatomic, strong, readonly) Profile *currentProfile;

+ (instancetype)sharedManager;

- (void)createProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)updateProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)deleteProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)switchToProfile:(Profile *)profile completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)loadProfilesWithCompletion:(void (^)(BOOL success, NSError * _Nullable error))completion;

// New methods to manage central profile information
- (void)updateCurrentProfileInfoWithProfile:(Profile *)profile;
- (Profile *)loadCurrentProfileInfoFromCentralStore;
- (BOOL)saveCentralProfileInfo:(NSDictionary *)infoDict;
- (NSDictionary *)loadCentralProfileInfo;
- (NSString *)centralProfileInfoPath;

// Convenience methods for ProfileManagerViewController
- (void)removeProfile:(NSString *)profileName;
- (void)renameProfile:(NSString *)oldName to:(NSString *)newName;
- (void)addProfile:(NSString *)profileName;
- (void)addProfileWithName:(NSString *)profileName shortDescription:(NSString *)shortDescription;

// Profile ID generation
- (NSString *)generateProfileID;

@end

NS_ASSUME_NONNULL_END 