#import "MapTabViewController.h"
#import "MapTabViewController+PickupDrop.h"
#import "MapTabViewControllerExtension.h"
#import <objc/runtime.h>

@implementation MapTabViewController (PathExtension)

// Enhanced path creation button handler that includes pickup to drop option
- (void)enhancedCreatePathButtonTapped:(UIButton *)sender {
    // Create an alert for path creation options
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Create Path" 
                                                                             message:@"Choose path creation method:" 
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Add pickup to drop option
    UIAlertAction *pickupDropAction = [UIAlertAction actionWithTitle:@"Pickup to Drop Location" 
                                                               style:UIAlertActionStyleDefault 
                                                             handler:^(UIAlertAction * _Nonnull action) {
        [self createPathFromPickupToDrop];
    }];
    
    // Add predefined path option
    UIAlertAction *predefinedAction = [UIAlertAction actionWithTitle:@"Predefined Path" 
                                                               style:UIAlertActionStyleDefault 
                                                             handler:^(UIAlertAction * _Nonnull action) {
        [self showPredefinedPathOptions];
    }];
    
    // Add cancel option
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" 
                                                           style:UIAlertActionStyleCancel 
                                                             handler:nil];
    
    [alertController addAction:pickupDropAction];
    [alertController addAction:predefinedAction];
    [alertController addAction:cancelAction];
    
    // Present the alert
    [self presentViewController:alertController animated:YES completion:nil];
}

// Call this method from viewDidLoad to swizzle the original implementation
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(createPathButtonTapped:);
        SEL swizzledSelector = @selector(enhancedCreatePathButtonTapped:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        // First try to add the swizzled method implementation to the original selector
        BOOL didAddMethod = class_addMethod(class, 
                                          originalSelector, 
                                          method_getImplementation(swizzledMethod), 
                                          method_getTypeEncoding(swizzledMethod));
        
        if (didAddMethod) {
            // If we successfully added the method to the original selector, replace the swizzled selector with the original method
            class_replaceMethod(class, 
                               swizzledSelector, 
                               method_getImplementation(originalMethod), 
                               method_getTypeEncoding(originalMethod));
        } else {
            // If we couldn't add the method, just exchange their implementations
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

@end 