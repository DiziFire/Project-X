#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface MethodSwizzler : NSObject

+ (void)swizzleClass:(Class)cls originalSelector:(SEL)originalSelector swizzledSelector:(SEL)swizzledSelector;
+ (void)swizzleClassMethod:(Class)cls originalSelector:(SEL)originalSelector swizzledSelector:(SEL)swizzledSelector;

@end