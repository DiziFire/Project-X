#import <Foundation/Foundation.h>
#import "BottomButtons.h"

@interface SKUIItemStateCenter : NSObject
+ (id)defaultCenter;
- (id)_newPurchasesWithItems:(id)items;
- (void)_performPurchases:(id)purchases hasBundlePurchase:(_Bool)purchase withClientContext:(id)context completionBlock:(id /* block */)block;
@end

@interface SKUIItem : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIItemOffer : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIClientContext : NSObject
+ (id)defaultContext;
@end

// Add missing method to LSApplicationWorkspace
@interface LSApplicationWorkspace (AppVersionManager)
- (BOOL)installApplication:(NSURL *)application withOptions:(NSDictionary *)options error:(NSError **)error;
@end

@interface AppVersionManager : NSObject

+ (instancetype)sharedManager;

// Fetch all available versions for an app
- (void)fetchVersionsForBundleID:(NSString *)bundleID 
                     completion:(void (^)(NSArray<NSDictionary *> *versions, NSError *error))completion;

// Install specific version of an app
- (void)installVersion:(NSString *)version 
           forBundleID:(NSString *)bundleID 
            completion:(void (^)(BOOL success, NSError *error))completion;

@end 