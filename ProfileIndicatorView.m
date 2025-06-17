#import "ProfileIndicatorView.h"
#import "ProjectXLogging.h"
#import "PassThroughWindow.h"
#import "ProfileManager.h"
#import "IPStatusViewController.h"
#import "SecurityTabViewController.h"

// Forward declaration for static callbacks
static void toggleIndicatorCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void springboardLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void springboardLockStateCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void springboardBlankedScreenCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void springboardBeenUnlockedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

@interface ProfileIndicatorView ()

@property (nonatomic, strong) PassThroughWindow *floatingWindow;
@property (nonatomic, strong) UILabel *profileLabel;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, assign) CGPoint initialCenter;
@property (nonatomic, strong) NSUserDefaults *profileSettings;

@end

@interface ProfileIndicatorView ()
@property (nonatomic, assign) BOOL isDeviceLocked;
@end

@implementation ProfileIndicatorView

#pragma mark - Long Press Gesture for Options

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (self.isDeviceLocked) {
        PXLog(@"Indicator long press ignored: device is locked");
        return;
    }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        // Modern way to get the rootViewController for iOS 13+
        UIWindow *presentingWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        presentingWindow = window;
                        break;
                    }
                }
            }
            if (presentingWindow) break;
        }
        // Do NOT use [UIApplication sharedApplication].windows (deprecated in iOS 15+)
        // If no window found in any foreground scene, fallback to app delegate window only
        if (!presentingWindow && [UIApplication sharedApplication].delegate && [[UIApplication sharedApplication].delegate respondsToSelector:@selector(window)]) {
            UIWindow *delegateWindow = [[UIApplication sharedApplication].delegate window];
            if ([delegateWindow isKindOfClass:[UIWindow class]]) {
                presentingWindow = delegateWindow;
            }
        }
        UIViewController *rootVC = presentingWindow.rootViewController;
        // Fallback: try to get a rootViewController from the app delegate window
        if (!rootVC && [UIApplication sharedApplication].delegate && [[UIApplication sharedApplication].delegate respondsToSelector:@selector(window)]) {
            UIWindow *delegateWindow = [[UIApplication sharedApplication].delegate window];
            if ([delegateWindow isKindOfClass:[UIWindow class]]) {
                rootVC = delegateWindow.rootViewController;
            }
        }
        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"Profile Indicator"
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
        __weak typeof(self) weakSelf = self;
        // Option 1: Open ProjectX
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"Open ProjectX"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
            // Trigger the same logic as tap
            [weakSelf handleTap:nil];
        }]];
        // Option 2: Check IP (stub)
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"Check IP"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * _Nonnull action) {
            // Create and present IPStatusViewController
            IPStatusViewController *ipStatusVC = [[IPStatusViewController alloc] init];
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:ipStatusVC];
            navController.modalPresentationStyle = UIModalPresentationPageSheet;
            [rootVC presentViewController:navController animated:YES completion:nil];
        }]];
        // Cancel
        [actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
        // For iPad compatibility
        actionSheet.popoverPresentationController.sourceView = self;
        actionSheet.popoverPresentationController.sourceRect = self.bounds;
        [rootVC presentViewController:actionSheet animated:YES completion:nil];
    }
}

+ (instancetype)sharedInstance {
    static ProfileIndicatorView *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initPrivate];
    });
    return sharedInstance;
}

- (instancetype)initPrivate {
    self = [super initWithFrame:CGRectMake(0, 0, 40, 40)];
    if (self) {
        [self setup];
        [self registerForNotifications];
        self.isDeviceLocked = NO;
        // UIKit notifications for resign/become active (screen off/on, app background/foreground)
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDeviceLock)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDeviceUnlock)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDeviceLock)
                                                     name:UIApplicationProtectedDataWillBecomeUnavailable
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDeviceUnlock)
                                                     name:UIApplicationProtectedDataDidBecomeAvailable
                                                   object:nil];
        // Register for SpringBoard lock/unlock Darwin notifications (works even without passcode)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)(self),
                                        springboardLockCallback,
                                        CFSTR("com.apple.springboard.lockcomplete"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)(self),
                                        springboardLockStateCallback,
                                        CFSTR("com.apple.springboard.lockstate"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        // Screen blank/unblank notifications (for non-password devices)
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)(self),
                                        springboardBlankedScreenCallback,
                                        CFSTR("com.apple.springboard.hasBlankedScreen"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)(self),
                                        springboardBeenUnlockedCallback,
                                        CFSTR("com.apple.springboard.hasBeenUnlocked"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

// Override hitTest to only respond to touches on the circle itself
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint convertedPoint = [self convertPoint:point fromView:self.superview];
    
    // Check if the point is within the bounds of our circular indicator (using radius)
    CGFloat radius = self.bounds.size.width / 2.0;
    CGPoint center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
    CGFloat distance = sqrt(pow(convertedPoint.x - center.x, 2) + pow(convertedPoint.y - center.y, 2));
    
    // Only handle touches within our circular bounds
    if (distance <= radius) {
        return [super hitTest:point withEvent:event];
    }
    
    // Pass all other touches through to underlying views
    return nil;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [ProfileIndicatorView sharedInstance];
}

- (void)setup {
    self.profileSettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    
    // Configure floating view appearance with exact dimensions for a perfect circle
    self.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:0.8]; // Matrix green
    self.layer.cornerRadius = 20; // Make it a circle (half of width/height)
    self.layer.masksToBounds = NO; // Allow shadow to extend beyond bounds
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    self.layer.shadowOpacity = 0.5;
    self.layer.shadowRadius = 4;
    
    // Add glow effect
    self.layer.shadowColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0].CGColor;
    self.layer.shadowRadius = 8;
    
    // Create profile number label
    self.profileLabel = [[UILabel alloc] init];
    self.profileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileLabel.textAlignment = NSTextAlignmentCenter;
    self.profileLabel.textColor = [UIColor blackColor];
    self.profileLabel.font = [UIFont boldSystemFontOfSize:18];
    [self addSubview:self.profileLabel];
    
    // Center the label in the circle using constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.profileLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.profileLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    
    // Update profile number display
    [self updateProfileIndicator];
    
    // Enable dragging
    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:self.panGesture];

    // Add tap gesture to open app
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tapGesture.numberOfTapsRequired = 1;
    [self addGestureRecognizer:tapGesture];

    // Add long press gesture for options
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGesture.minimumPressDuration = 0.7;
    [self addGestureRecognizer:longPressGesture];
    
    [self createFloatingWindow];
}

- (void)createFloatingWindow {
    // Release old window if it exists
    if (self.floatingWindow) {
        [self removeFromSuperview];
        self.floatingWindow = nil;
        PXLog(@"Removing old floating window");
    }
    
    // Position in top-right corner initially or use saved position
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat initialX = screenBounds.size.width - 60;
    CGFloat initialY = 100;
    
    // Load saved position from both NSUserDefaults and file storage
    CGFloat savedX = 0;
    CGFloat savedY = 0;
    
    // First try dedicated file storage
    NSString *positionPath = [self getPositionFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:positionPath]) {
        NSDictionary *positionDict = [NSDictionary dictionaryWithContentsOfFile:positionPath];
        if (positionDict) {
            savedX = [(NSNumber *)[positionDict objectForKey:@"X"] floatValue];
            savedY = [(NSNumber *)[positionDict objectForKey:@"Y"] floatValue];
            PXLog(@"ProfileIndicator: Loaded position from file: (%.1f, %.1f)", savedX, savedY);
        }
    }
    
    // If file storage failed, try NSUserDefaults as fallback
    if (savedX == 0 && savedY == 0) {
        savedX = [self.profileSettings floatForKey:@"ProfileIndicatorX"];
        savedY = [self.profileSettings floatForKey:@"ProfileIndicatorY"];
        if (savedX > 0 && savedY > 0) {
            PXLog(@"ProfileIndicator: Loaded position from NSUserDefaults: (%.1f, %.1f)", savedX, savedY);
        }
    }
    
    // Use saved position if available, otherwise use initial values
    if (savedX > 0 && savedY > 0) {
        initialX = savedX;
        initialY = savedY;
    }
    
    // Use a fixed window size that's slightly larger than the circle to accommodate shadow
    CGRect windowFrame = CGRectMake(initialX, initialY, 60, 60);
    
    // For SpringBoard, use a simple window without UIScene
    if ([[[NSProcessInfo processInfo] processName] isEqualToString:@"SpringBoard"]) {
        PXLog(@"Creating window for SpringBoard");
        self.floatingWindow = [[PassThroughWindow alloc] initWithFrame:windowFrame];
    } 
    // For iOS 13+, use UIWindowScene
    else if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                self.floatingWindow = [[PassThroughWindow alloc] initWithWindowScene:windowScene];
                self.floatingWindow.frame = windowFrame;
                PXLog(@"Created floating window with scene: %@", windowScene);
                break;
            }
        }
        
        // Fallback if we couldn't find an active scene
        if (!self.floatingWindow && connectedScenes.count > 0) {
            UIScene *anyScene = [connectedScenes anyObject];
            if ([anyScene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)anyScene;
                self.floatingWindow = [[PassThroughWindow alloc] initWithWindowScene:windowScene];
                self.floatingWindow.frame = windowFrame;
                PXLog(@"Created floating window with fallback scene");
            }
        }
    }
    
    // If still no window, use basic initialization
    if (!self.floatingWindow) {
        self.floatingWindow = [[PassThroughWindow alloc] initWithFrame:windowFrame];
        PXLog(@"Created floating window with legacy method");
    }
    
    // Configure the window properties
    self.floatingWindow.backgroundColor = [UIColor clearColor];
    self.floatingWindow.windowLevel = UIWindowLevelAlert + 1; // Above alerts
    self.floatingWindow.clipsToBounds = YES; // Don't let content bleed outside bounds
    self.floatingWindow.userInteractionEnabled = YES;
    
    // Disable touch interception in SpringBoard
    if ([[[NSProcessInfo processInfo] processName] isEqualToString:@"SpringBoard"]) {
        SEL selector = NSSelectorFromString(@"setInterceptTouches:");
        if ([self.floatingWindow respondsToSelector:selector]) {
            NSMethodSignature *signature = [UIWindow instanceMethodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setSelector:selector];
            [invocation setTarget:self.floatingWindow];
            BOOL no = NO;
            [invocation setArgument:&no atIndex:2];
            [invocation invoke];
            PXLog(@"Set window to not intercept touches on SpringBoard");
        }
    }
    
    // Create a basic view controller for the window
    UIViewController *rootVC = [UIViewController new];
    rootVC.view.backgroundColor = [UIColor clearColor];
    self.floatingWindow.rootViewController = rootVC;
    
    // Add the indicator centered in the window
    [self.floatingWindow.rootViewController.view addSubview:self];
    
    // Set a perfect square frame for the circle with equal width and height
    // Position it centered within the window with 10px padding all around
    self.frame = CGRectMake(10, 10, 40, 40);
    
    PXLog(@"Floating window created at: %@", NSStringFromCGRect(self.floatingWindow.frame));
    PXLog(@"Indicator positioned at: %@", NSStringFromCGRect(self.frame));
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.initialCenter = self.floatingWindow.center;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.superview];
        CGPoint newCenter = CGPointMake(self.initialCenter.x + translation.x, 
                                       self.initialCenter.y + translation.y);
        self.floatingWindow.center = newCenter;
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        // Keep it on screen
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGRect frame = self.floatingWindow.frame;
        
        if (frame.origin.x < 0) {
            frame.origin.x = 0;
        } else if (frame.origin.x + frame.size.width > screenBounds.size.width) {
            frame.origin.x = screenBounds.size.width - frame.size.width;
        }
        
        if (frame.origin.y < 50) { // Allow for status bar
            frame.origin.y = 50;
        } else if (frame.origin.y + frame.size.height > screenBounds.size.height) {
            frame.origin.y = screenBounds.size.height - frame.size.height;
        }
        
        // Save position for persistence - save window position directly
        // 1. Save to NSUserDefaults
        [self.profileSettings setFloat:frame.origin.x forKey:@"ProfileIndicatorX"];
        [self.profileSettings setFloat:frame.origin.y forKey:@"ProfileIndicatorY"];
        [self.profileSettings synchronize];
        
        // 2. Save to dedicated file for extra persistence
        [self savePositionToFile:frame.origin.x y:frame.origin.y];
        
        PXLog(@"ProfileIndicator: Saved position to persistent storage: (%.1f, %.1f)", 
              frame.origin.x, frame.origin.y);
        
        // Animate to valid position if needed
        if (!CGRectEqualToRect(self.floatingWindow.frame, frame)) {
            [UIView animateWithDuration:0.3 animations:^{
                self.floatingWindow.frame = frame;
            }];
        }
    }
}

// Return path to dedicated position file
- (NSString *)getPositionFilePath {
    NSString *libraryDir = @"/var/jb/var/mobile/Library/WeaponX";
    // Create directory if it doesn't exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:libraryDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:libraryDir
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:nil];
    }
    return [libraryDir stringByAppendingPathComponent:@"indicator_position.plist"];
}

// Save position to dedicated file
- (void)savePositionToFile:(CGFloat)x y:(CGFloat)y {
    NSDictionary *positionDict = @{
        @"X": @(x),
        @"Y": @(y),
        @"Timestamp": [NSDate date]
    };
    
    NSString *positionPath = [self getPositionFilePath];
    BOOL success = [positionDict writeToFile:positionPath atomically:YES];
    
    if (success) {
        // Set proper file permissions
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644}
                                        ofItemAtPath:positionPath
                                               error:nil];
        PXLog(@"ProfileIndicator: Successfully saved position to file: %@", positionPath);
    } else {
        PXLog(@"ProfileIndicator: Failed to save position to file");
    }
}

- (void)updateProfileIndicator {
    // First force a synchronization to make sure we have the latest user defaults
    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
    [sharedDefaults synchronize];
    
    // Get profile path from ProfileManager instead of hardcoding
    ProfileManager *profileManager = [ProfileManager sharedManager];
    NSString *centralProfileInfoPath = [profileManager centralProfileInfoPath];
    
    PXLog(@"ProfileIndicator: 🔄 Attempting to read profile info from: %@", centralProfileInfoPath);
    
    // Read from central profile info
    NSDictionary *profileInfo = [NSDictionary dictionaryWithContentsOfFile:centralProfileInfoPath];
    
    if (!profileInfo) {
        PXLog(@"ProfileIndicator: ❌ Failed to read profile info dictionary from current_profile_info.plist");
        
        // Fallback to active profile info
        NSString *activeProfileInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
        PXLog(@"ProfileIndicator: 🔄 Trying fallback profile info from: %@", activeProfileInfoPath);
        
        profileInfo = [NSDictionary dictionaryWithContentsOfFile:activeProfileInfoPath];
        
        if (!profileInfo) {
            PXLog(@"ProfileIndicator: ❌ Failed to read from fallback profile info as well");
            
            // Fallback to NSUserDefaults
            NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
            [sharedDefaults synchronize];
            NSString *fallbackProfileId = [sharedDefaults stringForKey:@"CurrentProfileID"];
            
            if (fallbackProfileId) {
                PXLog(@"ProfileIndicator: ✅ Found profile ID from NSUserDefaults: %@", fallbackProfileId);
                
                // Create a minimal profile info dictionary
                profileInfo = @{
                    @"ProfileId": fallbackProfileId,
                    @"ProfileName": [NSString stringWithFormat:@"Profile %@", fallbackProfileId]
                };
            } else {
                PXLog(@"ProfileIndicator: ❌ All methods to find profile info failed, using default");
                
                // Use default as last resort
                profileInfo = @{
                    @"ProfileId": @"1",
                    @"ProfileName": @"Profile 1"
                };
            }
        }
    }
    
    NSString *profileId = profileInfo[@"ProfileId"];
    
    if (!profileId) {
        PXLog(@"ProfileIndicator: ❌ Failed to read profile ID from profile info");
        PXLog(@"ProfileIndicator: Available keys in profile info: %@", [profileInfo allKeys]);
        
        // Use a default profile ID as fallback
        profileId = @"1";
        PXLog(@"ProfileIndicator: Using default profile ID: %@", profileId);
    } else {
        PXLog(@"ProfileIndicator: ✅ Found profile ID: %@", profileId);
    }
    
    // Update UI with profile info
    NSString *profileName = profileInfo[@"ProfileName"] ?: [NSString stringWithFormat:@"Profile %@", profileId];
    NSString *iconName = profileInfo[@"IconName"] ?: @"default_profile";
    
    PXLog(@"ProfileIndicator: 🔄 Updating indicator with - ID: %@, Name: %@", profileId, profileName);
    
    // Verify label exists
    if (!self.profileLabel) {
        PXLog(@"ProfileIndicator: ❌ profileLabel is nil, recreating it");
        
        // Create profile number label
        self.profileLabel = [[UILabel alloc] init];
        self.profileLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.profileLabel.textAlignment = NSTextAlignmentCenter;
        self.profileLabel.textColor = [UIColor blackColor];
        self.profileLabel.font = [UIFont boldSystemFontOfSize:18];
        [self addSubview:self.profileLabel];
        
        // Center the label in the circle using constraints
        [NSLayoutConstraint activateConstraints:@[
            [self.profileLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.profileLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
        
        PXLog(@"ProfileIndicator: ✅ Created new profileLabel");
    }
    
    // Update the indicator view with an explicit text assignment
    self.profileLabel.text = profileId;
    PXLog(@"ProfileIndicator: 🔄 Directly set label text to: '%@'", profileId);
    
    // Update the indicator appearance
    [self updateIndicatorWithName:profileName iconName:iconName profileId:profileId];
    
    // Verify label was updated - extra check after updateIndicatorWithName
    if (self.profileLabel) {
        PXLog(@"ProfileIndicator: ✅ Label text after update: '%@'", self.profileLabel.text);
        
        // If label text is empty after update, force set it again
        if (!self.profileLabel.text || [self.profileLabel.text isEqualToString:@""]) {
            PXLog(@"ProfileIndicator: ⚠️ Label text was empty, setting text again");
            self.profileLabel.text = profileId;
        }
    } else {
        PXLog(@"ProfileIndicator: ❌ Label is still nil after update attempt - critical error");
    }
}

- (void)updateIndicatorWithName:(NSString *)name iconName:(NSString *)iconName profileId:(NSString *)profileId {
    // First check if our profileLabel exists
    if (!self.profileLabel) {
        PXLog(@"ProfileIndicator: ❌ Error - profileLabel is nil in updateIndicatorWithName");
        // Create it if missing
        self.profileLabel = [[UILabel alloc] init];
        self.profileLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.profileLabel.textAlignment = NSTextAlignmentCenter;
        self.profileLabel.textColor = [UIColor blackColor];
        self.profileLabel.font = [UIFont boldSystemFontOfSize:18];
        [self addSubview:self.profileLabel];
        
        // Center the label in the circle using constraints
        [NSLayoutConstraint activateConstraints:@[
            [self.profileLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [self.profileLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
        PXLog(@"ProfileIndicator: ✅ Created new profileLabel in updateIndicatorWithName");
    }
    
    // Always fully refresh to prevent any visual glitches
    // Remove any existing animation
    [self.layer removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES]; // Disable implicit animations
    
    PXLog(@"ProfileIndicator: 🔄 Setting label text to: '%@'", profileId);
    
    // Safety check profile ID before assigning
    if (profileId && profileId.length > 0) {
        // Update the label text - set it directly to avoid rendering issues
        self.profileLabel.text = profileId;
        
        // Extra check to make sure text was set properly
        if ([self.profileLabel.text isEqualToString:profileId]) {
            PXLog(@"ProfileIndicator: ✅ Label text set successfully to: '%@'", profileId);
        } else {
            PXLog(@"ProfileIndicator: ⚠️ Label text mismatch! Expected: '%@', Actual: '%@'", 
                  profileId, self.profileLabel.text);
            // Force it one more time with a slight delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.profileLabel.text = profileId;
                PXLog(@"ProfileIndicator: 🔄 Forced label text again to: '%@'", profileId);
            });
        }
    } else {
        PXLog(@"ProfileIndicator: ❌ Error - profileId is nil or empty");
        self.profileLabel.text = @"1"; // Default to profile 1 if none available
    }
    
    // Update appearance based on profile ID
    // Vary the color slightly for different profiles
    int profileNum = [profileId intValue];
    if (profileNum <= 0) profileNum = 1; // Ensure valid number
    
    CGFloat hue = 0.33; // Base green
    hue += (profileNum * 0.05) - 0.05; // Shift hue slightly for each profile
    if (hue > 1.0) hue -= 1.0;
    
    // Create a color with the adjusted hue
    UIColor *profileColor = [UIColor colorWithHue:hue saturation:0.8 brightness:0.8 alpha:0.8];
    self.backgroundColor = profileColor;
    
    // Set shadow color to match the indicator color but with higher brightness for glow effect
    UIColor *shadowColor = [UIColor colorWithHue:hue saturation:0.9 brightness:1.0 alpha:0.9];
    self.layer.shadowColor = shadowColor.CGColor;
    self.layer.shadowRadius = 8;
    self.layer.shadowOpacity = 0.7;
    
    [CATransaction commit];
    
    // Add a subtle pulse animation that preserves the center position
    CABasicAnimation *pulseAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulseAnimation.duration = 0.3;
    pulseAnimation.fromValue = @1.0;
    pulseAnimation.toValue = @1.3;
    pulseAnimation.autoreverses = YES;
    pulseAnimation.repeatCount = 1;
    pulseAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:pulseAnimation forKey:@"pulse"];
}

- (void)registerForNotifications {
    // Register for profile change notifications
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(profileChanged:) 
                                                 name:@"ProfileManagerCurrentProfileChanged" 
                                               object:nil];
    
    // Register for toggle notifications
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(toggleIndicator:) 
                                                 name:@"com.hydra.projectx.toggleProfileIndicator" 
                                               object:nil];
    
    // Also register for Darwin notifications directly
    CFNotificationCenterRef darwinCenter = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwinCenter,
                                   (__bridge const void *)(self),
                                   toggleIndicatorCallback,
                                   CFSTR("com.hydra.projectx.enableProfileIndicator"),
                                   NULL,
                                   CFNotificationSuspensionBehaviorDeliverImmediately);
                                   
    CFNotificationCenterAddObserver(darwinCenter,
                                   (__bridge const void *)(self),
                                   toggleIndicatorCallback,
                                   CFSTR("com.hydra.projectx.disableProfileIndicator"),
                                   NULL,
                                   CFNotificationSuspensionBehaviorDeliverImmediately);
                                   
    // Register for profile change Darwin notification
    CFNotificationCenterAddObserver(darwinCenter,
                                   (__bridge const void *)(self),
                                   toggleIndicatorCallback,
                                   CFSTR("com.hydra.projectx.profileChanged"),
                                   NULL,
                                   CFNotificationSuspensionBehaviorDeliverImmediately);
    
    // Start a timer to periodically check for profile changes (every 2 seconds)
    [NSTimer scheduledTimerWithTimeInterval:2.0
                                     target:self
                                   selector:@selector(checkForProfileChanges)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)profileChanged:(NSNotification *)notification {
    // Log the profile change event
    PXLog(@"ProfileIndicator: Profile changed notification received, refreshing indicator");
    
    // Add a delay to make sure the profile change is completed in ProfileManager
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // First check if we need to update the indicator
        NSString *currentProfileId = self.profileLabel.text;
        
        // Get the latest profile ID from central storage
        ProfileManager *profileManager = [ProfileManager sharedManager];
        NSString *centralProfileInfoPath = [profileManager centralProfileInfoPath];
        NSDictionary *profileInfo = [NSDictionary dictionaryWithContentsOfFile:centralProfileInfoPath];
        NSString *newProfileId = profileInfo[@"ProfileId"];
        
        if (!newProfileId) {
            // Fall back to shared defaults
            NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
            [sharedDefaults synchronize];
            newProfileId = [sharedDefaults stringForKey:@"CurrentProfileID"];
        }
        
        // If the profile ID has changed, or if our label doesn't match what we expect
        if (newProfileId && (![newProfileId isEqualToString:currentProfileId] || !currentProfileId)) {
            PXLog(@"ProfileIndicator: Profile ID changed from %@ to %@, refreshing", currentProfileId, newProfileId);
            
            // Force a complete refresh by hiding and showing the indicator again
            // This ensures any old content or labels are completely cleared
            [self hide];
            
            // Short delay to ensure the hiding completes before showing again
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Create a fresh instance and show it
                [self show];
            });
        } else {
            PXLog(@"ProfileIndicator: Profile ID remains %@, no update needed", currentProfileId);
        }
    });
}

- (void)toggleIndicator:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    BOOL shouldShow = [[userInfo objectForKey:@"enabled"] boolValue];
    
    if (shouldShow) {
        [self show];
    } else {
        [self hide];
    }
}

- (void)show {
    if (self.isDeviceLocked) {
        PXLog(@"ProfileIndicator: Show suppressed because device is locked");
        return;
    }
    // Check settings to make sure we should be showing
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    BOOL profileIndicatorEnabled = [securitySettings boolForKey:@"profileIndicatorEnabled"];
    
    if (!profileIndicatorEnabled) {
        PXLog(@"ProfileIndicator: Not showing because setting is disabled");
        [self hide]; // Make sure it's hidden
        return;
    }
    
    // If already visible, do nothing
    if (self.floatingWindow && !self.floatingWindow.hidden) {
        PXLog(@"ProfileIndicator: Show called but already visible");
        return;
    }
    
    PXLog(@"ProfileIndicator: Show requested by user or notification");
    
    // Always completely hide first to ensure clean state
    // This is critical to make sure any previous instances are fully cleaned up
    [self hide];
    
    // Force destroy any existing floating windows from other instances
    if (@available(iOS 13.0, *)) {
        // Use scene-based window enumeration for iOS 13+ (modern approach)
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                NSArray<UIWindow *> *sceneWindows = windowScene.windows;
                for (UIWindow *window in sceneWindows) {
                    if ([window isKindOfClass:NSClassFromString(@"PassThroughWindow")] && window != self.floatingWindow) {
                        PXLog(@"ProfileIndicator: ⚠️ Found another floating window in scene, destroying it");
                        window.hidden = YES;
                    }
                }
            }
        }
    } else {
        // Fallback for older iOS (shouldn't be needed since we target iOS 15+)
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if ([window isKindOfClass:NSClassFromString(@"PassThroughWindow")] && window != self.floatingWindow) {
                PXLog(@"ProfileIndicator: ⚠️ Found another floating window, destroying it");
                window.hidden = YES;
            }
        }
        #pragma clang diagnostic pop
    }
    
    PXLog(@"ProfileIndicator: 🔄 Show requested - performing full recreation");
    
    // Fully recreate the window and setup from scratch every time
    [self createFloatingWindow];
    
    // Read the profile ID before creating the label
    NSString *profileId = nil;
    
    // Try to read profile ID from the current_profile_info.plist
    ProfileManager *profileManager = [ProfileManager sharedManager];
    NSString *centralProfileInfoPath = [profileManager centralProfileInfoPath];
    NSDictionary *profileInfo = [NSDictionary dictionaryWithContentsOfFile:centralProfileInfoPath];
    
    if (profileInfo && profileInfo[@"ProfileId"]) {
        profileId = profileInfo[@"ProfileId"];
        PXLog(@"ProfileIndicator: ✅ Found profile ID '%@' for label", profileId);
    } else {
        // Fallback to a default value
        profileId = @"1";
        PXLog(@"ProfileIndicator: ⚠️ Using default profile ID '%@' for label", profileId);
    }
    
    // Recreate the profile label with explicit text
    self.profileLabel = [[UILabel alloc] init];
    self.profileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileLabel.textAlignment = NSTextAlignmentCenter;
    self.profileLabel.textColor = [UIColor blackColor];
    self.profileLabel.font = [UIFont boldSystemFontOfSize:18];
    self.profileLabel.text = profileId; // Set text explicitly
    PXLog(@"ProfileIndicator: ✅ Created new label with text: '%@'", profileId);
    
    // Add the label to the view
    [self addSubview:self.profileLabel];
    
    // Center the label in the circle using constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.profileLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.profileLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    
    // Ensure the label is visible
    self.profileLabel.alpha = 1.0;
    
    // IMPORTANT CHANGE: Don't call updateProfileIndicator here, as it will create a duplicate indicator
    // Instead, update the appearance directly based on the profile ID
    
    // Update appearance based on profile ID
    [self updateIndicatorWithName:nil iconName:nil profileId:profileId];
    
    // Make a direct final check on the label text
    if (!self.profileLabel.text || [self.profileLabel.text isEqualToString:@""]) {
        PXLog(@"ProfileIndicator: ⚠️ Label text still empty after updates, forcing direct value");
        self.profileLabel.text = profileId;
    }
    
    // Show immediately without animation
    self.alpha = 1.0;
    self.transform = CGAffineTransformIdentity;
    self.floatingWindow.hidden = NO;
    [self.floatingWindow makeKeyAndVisible];
    
    PXLog(@"ProfileIndicator: ✅ Show complete - Window visible: %d, Frame: %@, Label text: '%@'", 
          !self.floatingWindow.isHidden, 
          NSStringFromCGRect(self.floatingWindow.frame),
          self.profileLabel.text);
}

- (void)hide {
    PXLog(@"ProfileIndicator: Hide requested - thorough cleanup");
    
    // Cancel any pending animations
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    // Remove any ongoing animations
    [self.layer removeAllAnimations];
    
    // Clear the profile label text to prevent any caching of old values
    if (self.profileLabel) {
        self.profileLabel.text = @"";
        [self.profileLabel removeFromSuperview];
        self.profileLabel = nil;
    }
    
    // Properly release the window and all subviews to prevent memory leaks and duplicates
    for (UIView *subview in [self.subviews copy]) {
        [subview removeFromSuperview];
    }
    [self removeFromSuperview];
    
    // If we have a floating window, hide and release it
    if (self.floatingWindow) {
        UIWindow *windowToHide = self.floatingWindow;
        windowToHide.hidden = YES;
        
        // Remove any references to self from the window to prevent retain cycles
        windowToHide.rootViewController = nil;
        
        // Set to nil to break any retain cycles
        self.floatingWindow = nil;
    }
    
    // Clean up any retained properties to ensure complete reset
    self.profileLabel = nil;
    
    PXLog(@"ProfileIndicator: Hide complete with thorough cleanup");
}

// Checks for profile changes without relying solely on notifications
- (void)checkForProfileChanges {
    if (self.floatingWindow && !self.floatingWindow.hidden) {
        NSString *currentProfileId = self.profileLabel.text;
        NSString *newProfileId = nil;
        
        // Direct file approach: Read current_profile_info.plist or active_profile_info.plist
        ProfileManager *profileManager = [ProfileManager sharedManager];
        NSString *centralProfileInfoPath = [profileManager centralProfileInfoPath];
        NSString *activeProfileInfoPath = @"/var/jb/var/mobile/Library/WeaponX/active_profile_info.plist";
        
        // Try reading from central profile info first
        NSDictionary *profileInfo = [NSDictionary dictionaryWithContentsOfFile:centralProfileInfoPath];
        if (profileInfo && profileInfo[@"ProfileId"]) {
            newProfileId = profileInfo[@"ProfileId"];
        }
        
        // If not found, try active profile info
        if (!newProfileId) {
            profileInfo = [NSDictionary dictionaryWithContentsOfFile:activeProfileInfoPath];
            if (profileInfo && profileInfo[@"ProfileId"]) {
                newProfileId = profileInfo[@"ProfileId"];
            }
        }
        
        // If still not found, fallback to NSUserDefaults
        if (!newProfileId) {
            NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.hydra.projectx.shared"];
            [sharedDefaults synchronize];
            newProfileId = [sharedDefaults stringForKey:@"CurrentProfileID"];
        }
        
        if (newProfileId && ![newProfileId isEqualToString:currentProfileId]) {
            PXLog(@"Profile change detected by timer: %@ -> %@", currentProfileId, newProfileId);
            [self updateProfileIndicator];
        }
    }
}

// Static callback function for Darwin notifications
static void toggleIndicatorCallback(CFNotificationCenterRef center,
                                  void *observer,
                                  CFStringRef name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    @autoreleasepool {
        NSString *notificationName = (__bridge NSString *)name;
        ProfileIndicatorView *indicatorView = (__bridge ProfileIndicatorView *)observer;
        
        if (!indicatorView) {
            // If for some reason the observer is nil, get the shared instance
            indicatorView = [ProfileIndicatorView sharedInstance];
        }
        
        if ([notificationName isEqualToString:@"com.hydra.projectx.enableProfileIndicator"]) {
            // Use dispatch_async to ensure UI updates happen on the main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                // Update setting first to ensure show() doesn't reject the request
                NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
                [securitySettings setBool:YES forKey:@"profileIndicatorEnabled"];
                [securitySettings synchronize];
                
                [indicatorView show];
            });
        } else if ([notificationName isEqualToString:@"com.hydra.projectx.disableProfileIndicator"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Update setting first for consistency
                NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
                [securitySettings setBool:NO forKey:@"profileIndicatorEnabled"];
                [securitySettings synchronize];
                
                [indicatorView hide];
            });
        } else if ([notificationName isEqualToString:@"com.hydra.projectx.profileChanged"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLog(@"ProfileIndicator: Profile change Darwin notification received");
                
                // If the indicator is already visible, update it
                if (indicatorView.floatingWindow && !indicatorView.floatingWindow.hidden) {
                    NSString *currentProfileId = indicatorView.profileLabel.text;
                    
                    // Get current profile ID from central storage with simple delay to ensure profile change is complete
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        // Try to read directly from central storage
                        ProfileManager *profileManager = [ProfileManager sharedManager];
                        if (profileManager) {
                            Profile *currentProfile = [profileManager currentProfile];
                            NSString *newProfileId = currentProfile.profileId;
                            
                            if (newProfileId && currentProfileId && ![newProfileId isEqualToString:currentProfileId]) {
                                PXLog(@"ProfileIndicator: Profile ID changed from %@ to %@, refreshing via Darwin notification", 
                                      currentProfileId, newProfileId);
                                
                                // Hide and show to fully refresh
                                [indicatorView hide];
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    [indicatorView show];
                                });
                            } else {
                                PXLog(@"ProfileIndicator: Profile ID remains %@, no update needed from Darwin notification", 
                                      currentProfileId);
                            }
                        }
                    });
                }
            });
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleDeviceLock {
    self.isDeviceLocked = YES;
    [self hide]; // Hide the indicator when locked
}

- (void)handleDeviceUnlock {
    self.isDeviceLocked = NO;
    [self show]; // Show the indicator again when unlocked
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (self.isDeviceLocked) {
        PXLog(@"Indicator tap ignored: device is locked");
        return;
    }
    PXLog(@"Indicator tapped, attempting to open ProjectX app");
    
    // Visual feedback for the tap
    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = 0.5;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            self.alpha = 1.0;
        }];
    }];
    
    // URLs to try for opening the app
    NSArray *urlSchemes = @[
        @"weaponx://",                     // Primary app scheme
        @"projectx://",                    // Standard URL scheme
        @"hydraprojectx://",               // Alternative name
        @"com.hydra.projectx://",          // Bundle ID URL scheme
        @"com.hydra.weaponx://",           // Alternative bundle ID
        @"ProjectX://",                    // Capitalized variant
        @"WeaponX://"                      // Capitalized alternative
    ];
    
    // Dispatch to main thread to be safe
    dispatch_async(dispatch_get_main_queue(), ^{
        [self tryOpenURLSchemes:urlSchemes withIndex:0];
    });
}

- (void)tryOpenURLSchemes:(NSArray *)urlSchemes withIndex:(NSUInteger)index {
    // Base case: if we've tried all schemes, try direct launch as a last resort
    if (index >= urlSchemes.count) {
        PXLog(@"All URL schemes failed, attempting direct app launch");
        [self launchAppDirectly];
        return;
    }
    
    NSString *urlScheme = urlSchemes[index];
    NSURL *appURL = [NSURL URLWithString:urlScheme];
    
    PXLog(@"Attempting to open URL: %@", urlScheme);
    
    // Always use the modern API with options dictionary for iOS 15
    [[UIApplication sharedApplication] openURL:appURL options:@{} completionHandler:^(BOOL success) {
        if (success) {
            PXLog(@"Successfully opened app with URL scheme: %@", urlScheme);
        } else {
            PXLog(@"Failed to open URL: %@, trying next scheme", urlScheme);
            // Try the next scheme
            [self tryOpenURLSchemes:urlSchemes withIndex:index + 1];
        }
    }];
}

- (void)launchAppDirectly {
    NSArray *bundleIds = @[
        @"com.hydra.projectx",
        @"com.hydra.weaponx"
    ];
    
    PXLog(@"Attempting direct app launch via LSApplicationWorkspace");
    
    // Try to use LSApplicationWorkspace to launch the app directly
    Class LSApplicationWorkspace_class = NSClassFromString(@"LSApplicationWorkspace");
    if (LSApplicationWorkspace_class) {
        PXLog(@"LSApplicationWorkspace class found");
        
        SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
        if ([LSApplicationWorkspace_class respondsToSelector:defaultWorkspaceSelector]) {
            // Use NSInvocation to avoid ARC issues with performSelector:
            NSMethodSignature *classSignature = [LSApplicationWorkspace_class methodSignatureForSelector:defaultWorkspaceSelector];
            NSInvocation *classInvocation = [NSInvocation invocationWithMethodSignature:classSignature];
            [classInvocation setTarget:LSApplicationWorkspace_class];
            [classInvocation setSelector:defaultWorkspaceSelector];
            [classInvocation invoke];
            
            id workspace = nil;
            [classInvocation getReturnValue:&workspace];
            
            if (workspace) {
                PXLog(@"Got LSApplicationWorkspace default workspace");
                
                SEL openAppSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
                
                for (NSString *bundleId in bundleIds) {
                    PXLog(@"Attempting to launch app with bundle ID: %@", bundleId);
                    
                    if ([workspace respondsToSelector:openAppSelector]) {
                        // Use NSInvocation to avoid ARC issues with performSelector:withObject:
                        NSMethodSignature *signature = [workspace methodSignatureForSelector:openAppSelector];
                        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                        [invocation setTarget:workspace];
                        [invocation setSelector:openAppSelector];
                        
                        // Fix the type issue by using a local variable
                        NSString *localBundleId = bundleId;
                        [invocation setArgument:&localBundleId atIndex:2]; // first arg is at index 2
                        [invocation invoke];
                        
                        BOOL success = NO;
                        [invocation getReturnValue:&success];
                        
                        if (success) {
                            PXLog(@"Successfully launched app with bundle ID: %@", bundleId);
                            return;
                        } else {
                            PXLog(@"LSApplicationWorkspace failed to open app with bundle ID: %@", bundleId);
                        }
                    } else {
                        PXLog(@"openApplicationWithBundleID: selector not available");
                    }
                }
            } else {
                PXLog(@"Failed to get defaultWorkspace");
            }
        } else {
            PXLog(@"defaultWorkspace selector not available");
        }
    } else {
        PXLog(@"LSApplicationWorkspace class not found");
    }
    
    PXLog(@"Failed to open ProjectX app - all methods failed");
}

// Current mode: Display a + button that adds a temporary shortcut
- (void)longPressProfileButton:(UILongPressGestureRecognizer *)recognizer {
    // ... existing code ...
}

- (void)showProfileInfo {
    // ... existing code ...
}

// SpringBoard lock complete (device locked)
static void springboardLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ProfileIndicatorView *self = (__bridge ProfileIndicatorView *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleDeviceLock];
    });
}
// SpringBoard lockstate (device unlocked)
static void springboardLockStateCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ProfileIndicatorView *self = (__bridge ProfileIndicatorView *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleDeviceUnlock];
    });
}

// Screen blanked (screen off or lock)
static void springboardBlankedScreenCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ProfileIndicatorView *self = (__bridge ProfileIndicatorView *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleDeviceLock];
    });
}
// Screen unlocked/turned on
static void springboardBeenUnlockedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ProfileIndicatorView *self = (__bridge ProfileIndicatorView *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleDeviceUnlock];
    });
}

@end 