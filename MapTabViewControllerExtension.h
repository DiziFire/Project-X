#import "MapTabViewController.h"

@interface MapTabViewController (PathExtension)

// This category enhances the path creation options
// by adding a "Pickup to Drop Location" option
- (void)enhancedCreatePathButtonTapped:(UIButton *)sender;

@end

// Forward declarations for methods that are not in the main header
@interface MapTabViewController (InternalMethods)
- (void)startPathCreationByMapTap;
- (void)promptForStraightLinePath;
- (void)showPredefinedPathOptions;
@end 