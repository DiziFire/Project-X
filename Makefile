TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
ROOTLESS = 1
LOGOS_DEFAULT_GENERATOR = internal
INSTALL_TARGET_PROCESSES = SpringBoard ProjectX

# Ensure rootless paths
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_INSTALL_PREFIX = /var/jb

# Note: This project now includes a Notification Service Extension for rich push notifications
# The extension needs to be manually added in Xcode after installing this package
# See /NotificationServiceExtension/README.md for integration instructions

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ProjectXTweak
APPLICATION_NAME = ProjectX
TOOL_NAME = WeaponXDaemon

# Tweak files
ProjectXTweak_FILES = Tweak.x WiFiHook.x StorageHooks.x UUIDHooks.x PasteboardHooks.x DeviceModelHooks.x SpringBoardLaunchHook.x UberURLHooks.x IOSVersionHooks.x ThemeHooks.x DeviceSpecHooks.x NetworkConnectionTypeHooks.x CanvasFingerprintHooks.x BootTimeHooks.x DomainBlockingHooks.x IdentifierManager.m IDFAManager.m IDFVManager.m DeviceNameManager.m DeviceModelManager.m WiFiManager.m ProjectXLogging.m WeaponXGuardian.m SerialNumberManager.m ProfileIndicatorView.m IPStatusViewController.m IPStatusCacheManager.m ScoreMeterView.m PassThroughWindow.m ProfileManager.m InlineHook.m fishhook.c LocationSpoofingManager.m JailbreakDetectionBypass.m IOSVersionInfo.m MethodSwizzler.m StorageManager.m BatteryManager.m SystemUUIDManager.m DyldCacheUUIDManager.m PasteboardUUIDManager.m KeychainUUIDManager.m UserDefaultsUUIDManager.m AppGroupUUIDManager.m UptimeManager.m CoreDataUUIDManager.m AppInstallUUIDManager.m AppContainerUUIDManager.m IPMonitorService.m MapTabViewController.m PickupDropManager.m MapTabViewController+PickupDrop.m UberFareCalculator.m LocationHeaderView.m MapTabViewControllerExtension.m DomainBlockingSettings.m BatteryHooks.x NetworkManager.m VPNDetectionBypass.x AppVersionHooks.x
ProjectXTweak_CFLAGS = -fobjc-arc -Wno-error=unused-variable -Wno-error=unused-function -I$(THEOS_VENDOR_INCLUDE_PATH) -I./include -D USES_LIBUNDIRECT=1 -D SUPPORT_IPAD=1 -D ENABLE_STATE_RESTORATION=1
ProjectXTweak_FRAMEWORKS = UIKit Foundation AdSupport UserNotifications IOKit Security CoreLocation CoreFoundation Network CoreTelephony SystemConfiguration WebKit SafariServices
ProjectXTweak_PRIVATE_FRAMEWORKS = MobileCoreServices AppSupport SpringBoardServices
ProjectXTweak_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
ProjectXTweak_LDFLAGS = -F$(THEOS)/vendor/lib -framework CydiaSubstrate

# App files
ProjectX_FILES = $(filter-out Tweak.x WiFiHook.x StorageHooks.x UUIDHooks.x PasteboardHooks.x WeaponXDaemon.m JailbreakDetectionBypass.m, $(wildcard *.m)) JailbreakDetectionBypass_App.m fishhook.c IOSVersionInfo.m UptimeManager.m AppInstallUUIDManager.m AppContainerUUIDManager.m AppVersionSpoofingViewController.m IPStatusViewController.m IPStatusCacheManager.m IPMonitorService.m ProjectXSceneDelegate.m ProgressHUDView.m PickupDropManager.m MapTabViewController+PickupDrop.m UberFareCalculator.m LocationHeaderView.m MapTabViewControllerExtension.m DomainBlockingSettings.m DomainManagementViewController.m VarCleanViewController.m
ProjectX_RESOURCE_DIRS = Assets.xcassets
ProjectX_RESOURCE_FILES = Info.plist Icon.png LaunchScreen.storyboard VarCleanRules.json
ProjectX_PRIVATE_FRAMEWORKS = FrontBoardServices SpringBoardServices BackBoardServices StoreKitUI MobileCoreServices
ProjectX_LDFLAGS = -framework CoreData -F$(THEOS)/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks -framework UIKit -framework Foundation -rpath /var/jb/usr/lib
ProjectX_FRAMEWORKS = UIKit Foundation MobileCoreServices CoreServices StoreKit IOKit Security CoreLocation CoreLocationUI
ProjectX_CODESIGN_FLAGS = -Sent.plist
ProjectX_CFLAGS = -fobjc-arc -D SUPPORT_IPAD=1 -D ENABLE_STATE_RESTORATION=1

# Daemon files
WeaponXDaemon_FILES = WeaponXDaemon.m
WeaponXDaemon_CFLAGS = -fobjc-arc
WeaponXDaemon_FRAMEWORKS = Foundation IOKit
WeaponXDaemon_INSTALL_PATH = /Library/WeaponX
WeaponXDaemon_CODESIGN_FLAGS = -Sent.plist
WeaponXDaemon_LDFLAGS = -framework IOKit

# Ensure app is installed to the correct location with proper permissions
ProjectX_INSTALL_PATH = /Applications
ProjectX_APPLICATION_MODE = 0755

# Make sure both tweak and application are built
all::
	@echo "Building tweak, application, and daemon..."

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

# Custom rule to ensure our scripts are included in the package
internal-stage::
	@echo "Adding custom scripts to package..."
	@mkdir -p $(THEOS_STAGING_DIR)/DEBIAN
	@cp -a DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/
	@cp -a DEBIAN/preinst $(THEOS_STAGING_DIR)/DEBIAN/
	@cp -a DEBIAN/prerm $(THEOS_STAGING_DIR)/DEBIAN/
	@chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/postinst
	@chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/preinst
	@chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/prerm
	@echo "Adding setup script to package..."
	@mkdir -p $(THEOS_STAGING_DIR)/usr/bin
	@cp -a setup_app.sh $(THEOS_STAGING_DIR)/usr/bin/projectx-setup
	@chmod 755 $(THEOS_STAGING_DIR)/usr/bin/projectx-setup
	@echo "Creating MobileSubstrate directories for compatibility..."
	@mkdir -p $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/
	@cp -a $(THEOS_OBJ_DIR)/ProjectXTweak.* $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/
	@echo "Ensuring LaunchScreen.storyboard is properly compiled..."
	@if [ -f "LaunchScreen.storyboard" ]; then \
		mkdir -p $(THEOS_STAGING_DIR)/Applications/ProjectX.app/; \
		ibtool --compile $(THEOS_STAGING_DIR)/Applications/ProjectX.app/LaunchScreen.storyboardc LaunchScreen.storyboard || true; \
		cp -a LaunchScreen.storyboard $(THEOS_STAGING_DIR)/Applications/ProjectX.app/; \
	fi
	@echo "Ensuring varCleanRules.json is in app bundle..."
	@if [ -f "varCleanRules.json" ]; then \
		mkdir -p $(THEOS_STAGING_DIR)/Applications/ProjectX.app/; \
		cp -a varCleanRules.json $(THEOS_STAGING_DIR)/Applications/ProjectX.app/; \
	fi
	@echo "Adding LaunchDaemon for persistent operation..."
	@mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons
	@mkdir -p $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian
	@mkdir -p $(THEOS_STAGING_DIR)/var/mobile/Library/Preferences
	@cp -a com.hydra.weaponx.guardian.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/
	@chmod 644 $(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist
	@chmod 755 $(THEOS_STAGING_DIR)/Library/WeaponX
	@chmod 755 $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian
	@touch $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/daemon.log
	@touch $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/guardian-stdout.log
	@touch $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/guardian-stderr.log
	@chmod 664 $(THEOS_STAGING_DIR)/Library/WeaponX/Guardian/*.log
	@echo "Installing WeaponXDaemon..."
	@cp -a $(THEOS_OBJ_DIR)/WeaponXDaemon $(THEOS_STAGING_DIR)/Library/WeaponX/
	@chmod 755 $(THEOS_STAGING_DIR)/Library/WeaponX/WeaponXDaemon
	@echo "Adding debug tools..."
	@mkdir -p $(THEOS_STAGING_DIR)/usr/bin
	@cp -a weaponx-debug.sh $(THEOS_STAGING_DIR)/usr/bin/weaponx-debug
	@chmod 755 $(THEOS_STAGING_DIR)/usr/bin/weaponx-debug

export CFLAGS = -fobjc-arc -Wno-error

ProjectXCLI_FILES = ProjectXCLIbinary.m DeviceNameManager.m InlineHook.m IdentifierManager.m IDFAManager.m IDFVManager.m WiFiManager.m SerialNumberManager.m ProjectXLogging.m fishhook.c ProfileManager.m IOSVersionInfo.m
ProjectXCLI_CFLAGS = -fobjc-arc -Wno-error=unused-variable -Wno-error=unused-function -I$(THEOS_VENDOR_INCLUDE_PATH)
ProjectXCLI_FRAMEWORKS = UIKit Foundation AdSupport UserNotifications IOKit Security
ProjectXCLI_PRIVATE_FRAMEWORKS = MobileCoreServices AppSupport
ProjectXCLI_LDFLAGS = -L$(THEOS_VENDOR_LIBRARY_PATH)

after-package::
	@echo "🔍 Checking package contents..."
	@mkdir -p $(THEOS_STAGING_DIR)/../debug
	@PACKAGE_FILE="$$(ls -t ./packages/com.hydra.projectx_*_iphoneos-arm64.deb | head -1)" && \
	if [ -f "$$PACKAGE_FILE" ]; then \
		echo "Extracting $$PACKAGE_FILE"; \
		(cd $(THEOS_STAGING_DIR)/../debug && ar -x "../../$$PACKAGE_FILE" && tar -xf data.tar.*); \
	else \
		echo "❌ Package file not found!"; \
		exit 1; \
	fi
	@echo "✅ Checking WeaponXDaemon executable..."
	@ls -la $(THEOS_STAGING_DIR)/../debug/var/jb/Library/WeaponX/WeaponXDaemon || echo "❌ WeaponXDaemon not found!"
	@echo "✅ Checking LaunchDaemon plist..."
	@ls -la $(THEOS_STAGING_DIR)/../debug/var/jb/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist || echo "❌ LaunchDaemon plist not found!"
	@echo "✅ Checking Guardian directory and log files..."
	@ls -la $(THEOS_STAGING_DIR)/../debug/var/jb/Library/WeaponX/Guardian/ || echo "❌ Guardian directory not found!"
	@echo "Package check completed!"
