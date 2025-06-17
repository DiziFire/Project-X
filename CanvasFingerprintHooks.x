#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "ProjectXLogging.h"
#import <objc/runtime.h>
#import <ellekit/ellekit.h>

// Cache for bundle decisions
static NSMutableDictionary *cachedBundleDecisions = nil;
static NSDate *cacheTimestamp = nil;
static NSTimeInterval kCacheValidityDuration = 300.0; // 5 minutes in seconds

// Configuration for fingerprint noise
static CGFloat kNoiseIntensity = 0.02;  // Default noise intensity (2% variation)
static BOOL kConsistentNoise = YES;     // Whether to use consistent noise per session

// Cache for noise seed values (to keep consistent noise per app session)
static NSMutableDictionary *noiseSeedCache = nil;

#pragma mark - Helper Functions

// Helper: Always read enablement from profile/plist, not IdentifierManager
static BOOL isCanvasFingerprintProtectionEnabledForCurrentApp(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID) return NO;
    NSArray *possiblePaths = @[@"/var/jb/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist",
                               @"/var/jb/private/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist",
                               @"/var/mobile/Library/Preferences/com.weaponx.securitySettings.plist"];
    NSDictionary *settingsDict = nil;
    for (NSString *path in possiblePaths) {
        settingsDict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (settingsDict) break;
    }
    if (!settingsDict) return NO;
    NSNumber *enabled = settingsDict[@"canvasFingerprintingEnabled"];
    if (!enabled) enabled = settingsDict[@"CanvasFingerprint"];
    return enabled ? [enabled boolValue] : NO;
}

// Update shouldProtectBundle to use only the new function
static BOOL shouldProtectBundle(NSString *bundleID) {
    if (!bundleID) return NO;
    // Check cache first
    if (!cachedBundleDecisions) {
        cachedBundleDecisions = [NSMutableDictionary dictionary];
    } else {
        NSNumber *cachedDecision = cachedBundleDecisions[bundleID];
        NSDate *decisionTimestamp = cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]];
        if (cachedDecision && decisionTimestamp && 
            [[NSDate date] timeIntervalSinceDate:decisionTimestamp] < kCacheValidityDuration) {
            return [cachedDecision boolValue];
        }
    }
    BOOL shouldProtect = isCanvasFingerprintProtectionEnabledForCurrentApp();
    cachedBundleDecisions[bundleID] = @(shouldProtect);
    cachedBundleDecisions[[bundleID stringByAppendingString:@"_timestamp"]] = [NSDate date];
    return shouldProtect;
}

// Get or create a noise seed for consistent variations
static NSInteger getNoiseSeedForBundle(NSString *bundleID) {
    if (!noiseSeedCache) {
        noiseSeedCache = [NSMutableDictionary dictionary];
    }
    
    NSNumber *cachedSeed = noiseSeedCache[bundleID];
    if (cachedSeed) {
        return [cachedSeed integerValue];
    }
    
    // Create a new random seed
    NSInteger seed = arc4random_uniform(1000000);
    noiseSeedCache[bundleID] = @(seed);
    
    return seed;
}

// Add subtle noise to image data based on seed
static void addNoiseToImageData(NSMutableData *imageData, NSString *bundleID) {
    if (!imageData || imageData.length == 0) return;
    
    NSInteger seed = kConsistentNoise ? getNoiseSeedForBundle(bundleID) : arc4random_uniform(1000000);
    srand((unsigned int)seed);
    
    UInt8 *bytes = (UInt8 *)imageData.mutableBytes;
    NSUInteger length = imageData.length;
    
    // Skip the first 8 bytes (header data) to preserve PNG/JPEG validity
    NSUInteger startOffset = 8;
    
    // Add subtle noise to pixel values
    for (NSUInteger i = startOffset; i < length; i++) {
        // Apply noise with probability based on intensity
        if ((CGFloat)rand() / RAND_MAX < kNoiseIntensity) {
            // Add -1, 0, or +1 variation to byte value
            int variation = (rand() % 3) - 1;
            
            // Apply variation ensuring value stays within 0-255 range
            int newValue = bytes[i] + variation;
            bytes[i] = (UInt8)MAX(0, MIN(255, newValue));
        }
    }
}

// Helper: Check if current app is in the scoped apps list (copied from WiFiHook.x)
static BOOL isInScopedAppsList(void) {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID || [bundleID length] == 0) {
            return NO;
        }
        NSArray *possiblePaths = @[@"/var/jb/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist",
                                   @"/var/jb/private/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist",
                                   @"/var/mobile/Library/Preferences/com.hydra.projectx.global_scope.plist"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *validPath = nil;
        for (NSString *path in possiblePaths) {
            if ([fileManager fileExistsAtPath:path]) {
                validPath = path;
                break;
            }
        }
        if (!validPath) return NO;
        NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:validPath];
        NSDictionary *scopedApps = plistDict[@"ScopedApps"];
        if (!scopedApps || ![scopedApps isKindOfClass:[NSDictionary class]]) return NO;
        id appEntry = scopedApps[bundleID];
        if (!appEntry || ![appEntry isKindOfClass:[NSDictionary class]]) return NO;
        BOOL isEnabled = [appEntry[@"enabled"] boolValue];
        return isEnabled;
    } @catch (NSException *e) {
        return NO;
    }
}

// Helper: Re-inject JS into all live WKWebViews
static void reinjectFingerprintProtectionScriptToAllWKWebViews() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || !shouldProtectBundle(bundleID)) return;
    // The JS string must match the one injected in WKWebView hook
    NSString *canvasProtectionScript =
        @"(function() {"
        // --- Canvas 2D & WebGL Pixel Noise (existing) ---
        "    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;"
        "    const origToBlob = HTMLCanvasElement.prototype.toBlob;"
        "    const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;"
        "    function addNoise(canvas) {"
        "        try {"
        "            const ctx = canvas.getContext('2d');"
        "            if (!ctx) return;"
        "            const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);"
        "            const pixels = imageData.data;"
        "            for (let i = 0; i < pixels.length; i += 4) {"
        "                if (Math.random() < 0.02) {"
        "                    pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "                }"
        "            }"
        "            ctx.putImageData(imageData, 0, 0);"
        "        } catch (e) {}"
        "    }"
        "    HTMLCanvasElement.prototype.toDataURL = function() { addNoise(this); return origToDataURL.apply(this, arguments); };"
        "    HTMLCanvasElement.prototype.toBlob = function(callback) { addNoise(this); return origToBlob.apply(this, arguments); };"
        "    CanvasRenderingContext2D.prototype.getImageData = function() {"
        "        const imageData = origGetImageData.apply(this, arguments);"
        "        const pixels = imageData.data;"
        "        for (let i = 0; i < pixels.length; i += 4) {"
        "            if (Math.random() < 0.02) {"
        "                pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "            }"
        "        }"
        "        return imageData;"
        "    };"
        "    const origReadPixels = WebGLRenderingContext.prototype.readPixels;"
        "    WebGLRenderingContext.prototype.readPixels = function(x, y, width, height, format, type, pixels) {"
        "        origReadPixels.apply(this, arguments);"
        "        if (pixels instanceof Uint8Array) {"
        "            for (let i = 0; i < pixels.length; i += 4) {"
        "                if (Math.random() < 0.02) {"
        "                    pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "                }"
        "            }"
        "        }"
        "    };"
        // --- Audio Fingerprinting Protection ---
        "    if (window.AnalyserNode) {"
        "        const origGetFloatFrequencyData = AnalyserNode.prototype.getFloatFrequencyData;"
        "        AnalyserNode.prototype.getFloatFrequencyData = function(array) {"
        "            origGetFloatFrequencyData.call(this, array);"
        "            for (let i = 0; i < array.length; i++) {"
        "                array[i] += (Math.random() - 0.5) * 0.1;"
        "            }"
        "        };"
        "    }"
        "    if (window.AudioBuffer) {"
        "        const origGetChannelData = AudioBuffer.prototype.getChannelData;"
        "        AudioBuffer.prototype.getChannelData = function() {"
        "            const data = origGetChannelData.apply(this, arguments);"
        "            for (let i = 0; i < data.length; i += 100) {"
        "                data[i] += (Math.random() - 0.5) * 0.0001;"
        "            }"
        "            return data;"
        "        };"
        "    }"
        // --- WebGL Advanced Fingerprinting Protection ---
        "    const spoofedVendor = 'Apple Inc.';"
        "    const spoofedRenderer = 'Apple GPU';"
        "    const origGetParameter = WebGLRenderingContext.prototype.getParameter;"
        "    WebGLRenderingContext.prototype.getParameter = function(param) {"
        "        if (param === 37445) return spoofedVendor;"
        "        if (param === 37446) return spoofedRenderer;"
        "        if (param === this.MAX_TEXTURE_SIZE) return 4096 + Math.floor(Math.random() * 10);"
        "        return origGetParameter.call(this, param);"
        "    };"
        "    const origGetSupportedExtensions = WebGLRenderingContext.prototype.getSupportedExtensions;"
        "    WebGLRenderingContext.prototype.getSupportedExtensions = function() {"
        "        const exts = origGetSupportedExtensions.call(this) || [];"
        "        return exts.slice().sort(() => Math.random() - 0.5);"
        "    };"
        "    const origGetShaderPrecisionFormat = WebGLRenderingContext.prototype.getShaderPrecisionFormat;"
        "    WebGLRenderingContext.prototype.getShaderPrecisionFormat = function() {"
        "        const res = origGetShaderPrecisionFormat.apply(this, arguments);"
        "        if (res && typeof res === 'object') { res.precision += Math.floor(Math.random() * 2); }"
        "        return res;"
        "    };"
        // --- Font Fingerprinting Protection ---
        "    if (window.CanvasRenderingContext2D) {"
        "        const origMeasureText = CanvasRenderingContext2D.prototype.measureText;"
        "        CanvasRenderingContext2D.prototype.measureText = function(text) {"
        "            const result = origMeasureText.apply(this, arguments);"
        "            Object.defineProperty(result, 'width', { value: result.width * (1 + (Math.random() - 0.5) * 0.01) });"
        "            return result;"
        "        };"
        "    }"
        "    if (window.navigator && window.navigator.fonts && window.navigator.fonts.query) {"
        "        const origAvailableFonts = window.navigator.fonts.query;"
        "        window.navigator.fonts.query = function() {"
        "            return origAvailableFonts.apply(this, arguments).then(fonts => {"
        "                return fonts.slice().sort(() => Math.random() - 0.5);"
        "            });"
        "        };"
        "    }"
        "    console.log('[WeaponX] Canvas, Audio, WebGL, and Font fingerprinting protection enabled');"
        "})();";
    // Modern iOS 15+ way: enumerate all UIWindowScene windows
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            for (UIView *view in window.subviews) {
                if ([view isKindOfClass:[WKWebView class]]) {
                    WKWebView *webView = (WKWebView *)view;
                    [webView evaluateJavaScript:canvasProtectionScript completionHandler:nil];
                }
                // Recursively search subviews
                NSMutableArray *stack = [NSMutableArray arrayWithArray:view.subviews];
                while (stack.count > 0) {
                    UIView *subview = [stack lastObject];
                    [stack removeLastObject];
                    if ([subview isKindOfClass:[WKWebView class]]) {
                        WKWebView *webView = (WKWebView *)subview;
                        [webView evaluateJavaScript:canvasProtectionScript completionHandler:nil];
                    }
                    [stack addObjectsFromArray:subview.subviews];
                }
            }
        }
    }
}

#pragma mark - WKWebView Configuration Hooks

// Inject JS at document start for all WKWebViews
%hook WKWebViewConfiguration

- (void)setUserContentController:(WKUserContentController *)userContentController {
    %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || !shouldProtectBundle(bundleID)) return;
    // Only inject if not already present
    BOOL alreadyInjected = NO;
    for (WKUserScript *script in userContentController.userScripts) {
        if ([script.source containsString:@"[WeaponX] Canvas, Audio, WebGL, and Font fingerprinting protection enabled"]) {
            alreadyInjected = YES;
            break;
        }
    }
    if (alreadyInjected) return;
    // JS with MutationObserver for iframes
    NSString *canvasProtectionScript =
        @"(function() {"
        "console.log('[WeaponX] Canvas, Audio, WebGL, and Font fingerprinting protection enabled');"
        // --- Canvas 2D & WebGL Pixel Noise (existing) ---
        "    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;"
        "    const origToBlob = HTMLCanvasElement.prototype.toBlob;"
        "    const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;"
        "    function addNoise(canvas) {"
        "        try {"
        "            const ctx = canvas.getContext('2d');"
        "            if (!ctx) return;"
        "            const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);"
        "            const pixels = imageData.data;"
        "            for (let i = 0; i < pixels.length; i += 4) {"
        "                if (Math.random() < 0.02) {"
        "                    pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "                }"
        "            }"
        "            ctx.putImageData(imageData, 0, 0);"
        "        } catch (e) {}"
        "    }"
        "    HTMLCanvasElement.prototype.toDataURL = function() { addNoise(this); return origToDataURL.apply(this, arguments); };"
        "    HTMLCanvasElement.prototype.toBlob = function(callback) { addNoise(this); return origToBlob.apply(this, arguments); };"
        "    CanvasRenderingContext2D.prototype.getImageData = function() {"
        "        const imageData = origGetImageData.apply(this, arguments);"
        "        const pixels = imageData.data;"
        "        for (let i = 0; i < pixels.length; i += 4) {"
        "            if (Math.random() < 0.02) {"
        "                pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "            }"
        "        }"
        "        return imageData;"
        "    };"
        // --- Audio Fingerprinting Protection ---
        "    if (window.AnalyserNode) {"
        "        const origGetFloatFrequencyData = AnalyserNode.prototype.getFloatFrequencyData;"
        "        AnalyserNode.prototype.getFloatFrequencyData = function(array) {"
        "            origGetFloatFrequencyData.call(this, array);"
        "            for (let i = 0; i < array.length; i++) {"
        "                array[i] += (Math.random() - 0.5) * 0.1;"
        "            }"
        "        };"
        "    }"
        "    if (window.AudioBuffer) {"
        "        const origGetChannelData = AudioBuffer.prototype.getChannelData;"
        "        AudioBuffer.prototype.getChannelData = function() {"
        "            const data = origGetChannelData.apply(this, arguments);"
        "            for (let i = 0; i < data.length; i += 100) {"
        "                data[i] += (Math.random() - 0.5) * 0.0001;"
        "            }"
        "            return data;"
        "        };"
        "    }"
        // --- WebGL Advanced Fingerprinting Protection ---
        "    const spoofedVendor = 'Apple Inc.';"
        "    const spoofedRenderer = 'Apple GPU';"
        "    const origGetParameter = WebGLRenderingContext.prototype.getParameter;"
        "    WebGLRenderingContext.prototype.getParameter = function(param) {"
        "        if (param === 37445) return spoofedVendor;"
        "        if (param === 37446) return spoofedRenderer;"
        "        if (param === this.MAX_TEXTURE_SIZE) return 4096 + Math.floor(Math.random() * 10);"
        "        return origGetParameter.call(this, param);"
        "    };"
        "    const origGetSupportedExtensions = WebGLRenderingContext.prototype.getSupportedExtensions;"
        "    WebGLRenderingContext.prototype.getSupportedExtensions = function() {"
        "        const exts = origGetSupportedExtensions.call(this) || [];"
        "        return exts.slice().sort(() => Math.random() - 0.5);"
        "    };"
        "    const origGetShaderPrecisionFormat = WebGLRenderingContext.prototype.getShaderPrecisionFormat;"
        "    WebGLRenderingContext.prototype.getShaderPrecisionFormat = function() {"
        "        const res = origGetShaderPrecisionFormat.apply(this, arguments);"
        "        if (res && typeof res === 'object') { res.precision += Math.floor(Math.random() * 2); }"
        "        return res;"
        "    };"
        // --- Font Fingerprinting Protection ---
        "    if (window.CanvasRenderingContext2D) {"
        "        const origMeasureText = CanvasRenderingContext2D.prototype.measureText;"
        "        CanvasRenderingContext2D.prototype.measureText = function(text) {"
        "            const result = origMeasureText.apply(this, arguments);"
        "            Object.defineProperty(result, 'width', { value: result.width * (1 + (Math.random() - 0.5) * 0.01) });"
        "            return result;"
        "        };"
        "    }"
        "    if (window.navigator && window.navigator.fonts && window.navigator.fonts.query) {"
        "        const origAvailableFonts = window.navigator.fonts.query;"
        "        window.navigator.fonts.query = function() {"
        "            return origAvailableFonts.apply(this, arguments).then(fonts => {"
        "                return fonts.slice().sort(() => Math.random() - 0.5);"
        "            });"
        "        };"
        "    }"
        // MutationObserver for iframes
        "    function injectAllFrames(win) {"
        "        try {"
        "            win.eval('(' + arguments.callee.toString() + ')(window)');"
        "        } catch (e) {}"
        "        for (let i = 0; i < win.frames.length; i++) {"
        "            try { injectAllFrames(win.frames[i]); } catch (e) {}"
        "        }"
        "    }"
        "    injectAllFrames(window);"
        "    const observer = new MutationObserver(function(mutations) {"
        "        mutations.forEach(function(mutation) {"
        "            mutation.addedNodes.forEach(function(node) {"
        "                if (node.tagName === 'IFRAME') {"
        "                    try { injectAllFrames(node.contentWindow); } catch (e) {}"
        "                }"
        "            });"
        "        });"
        "    });"
        "    observer.observe(document, { childList: true, subtree: true });"
        "})();";
    WKUserScript *script = [[NSClassFromString(@"WKUserScript") alloc] initWithSource:canvasProtectionScript injectionTime:1 forMainFrameOnly:NO];
    [userContentController addUserScript:script];
}

%end

#pragma mark - WKWebView Hooks

// Hook WKWebView to inject JavaScript that adds subtle noise to canvas operations
%hook WKWebView

- (void)_didFinishLoadForFrame:(WKFrameInfo *)frame {
    %orig;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || !shouldProtectBundle(bundleID)) {
        return;
    }
    
    // JavaScript to protect against canvas, audio, WebGL, and font fingerprinting
    NSString *canvasProtectionScript = 
        @"(function() {"
        // --- Canvas 2D & WebGL Pixel Noise (existing) ---
        "    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;"
        "    const origToBlob = HTMLCanvasElement.prototype.toBlob;"
        "    const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;"
        "    function addNoise(canvas) {"
        "        try {"
        "            const ctx = canvas.getContext('2d');"
        "            if (!ctx) return;"
        "            const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);"
        "            const pixels = imageData.data;"
        "            for (let i = 0; i < pixels.length; i += 4) {"
        "                if (Math.random() < 0.02) {"
        "                    pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "                }"
        "            }"
        "            ctx.putImageData(imageData, 0, 0);"
        "        } catch (e) {}"
        "    }"
        "    HTMLCanvasElement.prototype.toDataURL = function() { addNoise(this); return origToDataURL.apply(this, arguments); };"
        "    HTMLCanvasElement.prototype.toBlob = function(callback) { addNoise(this); return origToBlob.apply(this, arguments); };"
        "    CanvasRenderingContext2D.prototype.getImageData = function() {"
        "        const imageData = origGetImageData.apply(this, arguments);"
        "        const pixels = imageData.data;"
        "        for (let i = 0; i < pixels.length; i += 4) {"
        "            if (Math.random() < 0.02) {"
        "                pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "            }"
        "        }"
        "        return imageData;"
        "    };"
        "    const origReadPixels = WebGLRenderingContext.prototype.readPixels;"
        "    WebGLRenderingContext.prototype.readPixels = function(x, y, width, height, format, type, pixels) {"
        "        origReadPixels.apply(this, arguments);"
        "        if (pixels instanceof Uint8Array) {"
        "            for (let i = 0; i < pixels.length; i += 4) {"
        "                if (Math.random() < 0.02) {"
        "                    pixels[i] = Math.max(0, Math.min(255, pixels[i] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+1] = Math.max(0, Math.min(255, pixels[i+1] + (Math.random() < 0.5 ? -1 : 1)));"
        "                    pixels[i+2] = Math.max(0, Math.min(255, pixels[i+2] + (Math.random() < 0.5 ? -1 : 1)));"
        "                }"
        "            }"
        "        }"
        "    };"
        // --- Audio Fingerprinting Protection ---
        "    if (window.AnalyserNode) {"
        "        const origGetFloatFrequencyData = AnalyserNode.prototype.getFloatFrequencyData;"
        "        AnalyserNode.prototype.getFloatFrequencyData = function(array) {"
        "            origGetFloatFrequencyData.call(this, array);"
        "            for (let i = 0; i < array.length; i++) {"
        "                array[i] += (Math.random() - 0.5) * 0.1;"
        "            }"
        "        };"
        "    }"
        "    if (window.AudioBuffer) {"
        "        const origGetChannelData = AudioBuffer.prototype.getChannelData;"
        "        AudioBuffer.prototype.getChannelData = function() {"
        "            const data = origGetChannelData.apply(this, arguments);"
        "            for (let i = 0; i < data.length; i += 100) {"
        "                data[i] += (Math.random() - 0.5) * 0.0001;"
        "            }"
        "            return data;"
        "        };"
        "    }"
        // --- WebGL Advanced Fingerprinting Protection ---
        "    const spoofedVendor = 'Apple Inc.';"
        "    const spoofedRenderer = 'Apple GPU';"
        "    const origGetParameter = WebGLRenderingContext.prototype.getParameter;"
        "    WebGLRenderingContext.prototype.getParameter = function(param) {"
        "        if (param === 37445) return spoofedVendor;"
        "        if (param === 37446) return spoofedRenderer;"
        "        if (param === this.MAX_TEXTURE_SIZE) return 4096 + Math.floor(Math.random() * 10);"
        "        return origGetParameter.call(this, param);"
        "    };"
        "    const origGetSupportedExtensions = WebGLRenderingContext.prototype.getSupportedExtensions;"
        "    WebGLRenderingContext.prototype.getSupportedExtensions = function() {"
        "        const exts = origGetSupportedExtensions.call(this) || [];"
        "        return exts.slice().sort(() => Math.random() - 0.5);"
        "    };"
        "    const origGetShaderPrecisionFormat = WebGLRenderingContext.prototype.getShaderPrecisionFormat;"
        "    WebGLRenderingContext.prototype.getShaderPrecisionFormat = function() {"
        "        const res = origGetShaderPrecisionFormat.apply(this, arguments);"
        "        if (res && typeof res === 'object') { res.precision += Math.floor(Math.random() * 2); }"
        "        return res;"
        "    };"
        // --- Font Fingerprinting Protection ---
        "    if (window.CanvasRenderingContext2D) {"
        "        const origMeasureText = CanvasRenderingContext2D.prototype.measureText;"
        "        CanvasRenderingContext2D.prototype.measureText = function(text) {"
        "            const result = origMeasureText.apply(this, arguments);"
        "            Object.defineProperty(result, 'width', { value: result.width * (1 + (Math.random() - 0.5) * 0.01) });"
        "            return result;"
        "        };"
        "    }"
        "    if (window.navigator && window.navigator.fonts && window.navigator.fonts.query) {"
        "        const origAvailableFonts = window.navigator.fonts.query;"
        "        window.navigator.fonts.query = function() {"
        "            return origAvailableFonts.apply(this, arguments).then(fonts => {"
        "                return fonts.slice().sort(() => Math.random() - 0.5);"
        "            });"
        "        };"
        "    }"
        "    console.log('[WeaponX] Canvas, Audio, WebGL, and Font fingerprinting protection enabled');"
        "})();";
    
    [self evaluateJavaScript:canvasProtectionScript completionHandler:^(id result, NSError *error) {
        if (error) {
            PXLog(@"[CanvasFingerprint] Error injecting canvas/audio/webgl/font protection script: %@", error);
        } else {
            static BOOL loggedInjection = NO;
            if (!loggedInjection) {
                PXLog(@"[CanvasFingerprint] Successfully injected canvas/audio/webgl/font fingerprinting protection for %@", bundleID);
                loggedInjection = YES;
            }
        }
    }];
}

%end

#pragma mark - UIImage+ImageIO Hooks

// Hook UIImage imageWithData method to protect screenshots and image generation
%hook UIImage

+ (UIImage *)imageWithData:(NSData *)data {
    UIImage *originalImage = %orig;
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || !shouldProtectBundle(bundleID) || !data) {
        return originalImage;
    }
    // Always add noise for protected apps
    @try {
        UIGraphicsBeginImageContextWithOptions(originalImage.size, NO, originalImage.scale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        [originalImage drawInRect:CGRectMake(0, 0, originalImage.size.width, originalImage.size.height)];
        CGContextSetBlendMode(context, kCGBlendModeLighten);
        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.01].CGColor);
        for (int i = 0; i < 20; i++) {
            CGFloat x = arc4random_uniform((uint32_t)originalImage.size.width);
            CGFloat y = arc4random_uniform((uint32_t)originalImage.size.height);
            CGContextFillRect(context, CGRectMake(x, y, 1, 1));
        }
        UIImage *modifiedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        if (modifiedImage) {
            PXLog(@"[CanvasFingerprint] Noise added to image for %@", bundleID);
            return modifiedImage;
        }
    } @catch (NSException *exception) {
        PXLog(@"[CanvasFingerprint] Exception adding noise to image: %@", exception);
    }
    return originalImage;
}

%end

#pragma mark - WKNativeCanvas Hooks

// Hook WKNativeCanvas data access methods if they exist
%hook WKNativeCanvas

// Method for getting pixel data
- (NSData *)drawingData {
    NSData *originalData = %orig;
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || !shouldProtectBundle(bundleID) || !originalData) {
        return originalData;
    }
    
    // Create a mutable copy to modify
    NSMutableData *modifiedData = [originalData mutableCopy];
    
    // Add noise to the image data
    addNoiseToImageData(modifiedData, bundleID);
    
    return modifiedData;
}

%end

#pragma mark - Notification Handlers

// Refresh settings when profile or settings change
static void refreshSettings(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *notificationName = (__bridge NSString *)name;
    PXLog(@"[CanvasFingerprint] Received settings notification: %@", notificationName);
    [cachedBundleDecisions removeAllObjects];
    cacheTimestamp = [NSDate date];
        [noiseSeedCache removeAllObjects];
    reinjectFingerprintProtectionScriptToAllWKWebViews();
}

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        PXLog(@"[CanvasFingerprint] Initializing Canvas Fingerprint Protection hooks");
        if (!isInScopedAppsList()) {
            PXLog(@"[CanvasFingerprint] App is not scoped, skipping hook installation");
            return;
        }
        // Initialize caches
        cachedBundleDecisions = [NSMutableDictionary dictionary];
        noiseSeedCache = [NSMutableDictionary dictionary];
        cacheTimestamp = [NSDate date];
        // Register for notifications about profile or settings changes
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.settings.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.profileChanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.toggleCanvasFingerprint"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.canvasFingerprintToggleChanged"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.enableCanvasFingerprintProtection"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.disableCanvasFingerprintProtection"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            refreshSettings,
            CFSTR("com.hydra.projectx.resetCanvasNoise"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        // Initialize hooks
        %init();
    }
} 