#import "MethodSwizzler.h"

@implementation MethodSwizzler

+ (void)swizzleClass:(Class)cls originalSelector:(SEL)originalSelector swizzledSelector:(SEL)swizzledSelector {
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSelector);
    
    BOOL didAddMethod = class_addMethod(cls,
                                       originalSelector,
                                       method_getImplementation(swizzledMethod),
                                       method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(cls,
                           swizzledSelector,
                           method_getImplementation(originalMethod),
                           method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

+ (void)swizzleClassMethod:(Class)cls originalSelector:(SEL)originalSelector swizzledSelector:(SEL)swizzledSelector {
    Class metaClass = object_getClass(cls);
    Method originalMethod = class_getClassMethod(cls, originalSelector);
    Method swizzledMethod = class_getClassMethod(cls, swizzledSelector);
    
    BOOL didAddMethod = class_addMethod(metaClass,
                                       originalSelector,
                                       method_getImplementation(swizzledMethod),
                                       method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(metaClass,
                           swizzledSelector,
                           method_getImplementation(originalMethod),
                           method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

@end