#!/bin/sh

echo "Setting up ProjectX app..."

# Detect jailbreak type
if [ -d "/var/jb" ]; then
    JBPREFIX="/var/jb"
    echo "Detected rootless jailbreak at /var/jb"
elif [ -d "/var/LIB" ]; then
    JBPREFIX="/var/LIB"
    echo "Detected rootless jailbreak at /var/LIB"
else
    JBPREFIX=""
    echo "Detected rootful jailbreak"
fi

# Fix permissions for ElleKit directory
echo "Setting up ElleKit directories..."
mkdir -p ${JBPREFIX}/Library/ElleKit/DynamicLibraries
chmod 755 ${JBPREFIX}/Library/ElleKit
chmod 755 ${JBPREFIX}/Library/ElleKit/DynamicLibraries

# For backwards compatibility with MobileSubstrate
echo "Setting up MobileSubstrate directories (for compatibility)..."
mkdir -p ${JBPREFIX}/Library/MobileSubstrate/DynamicLibraries
chmod 755 ${JBPREFIX}/Library/MobileSubstrate
chmod 755 ${JBPREFIX}/Library/MobileSubstrate/DynamicLibraries

# Ensure the dylib has proper permissions
echo "Setting up tweak permissions..."
if [ -f "${JBPREFIX}/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.dylib" ]; then
    chmod 644 ${JBPREFIX}/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.dylib
fi

if [ -f "${JBPREFIX}/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist" ]; then
    chmod 644 ${JBPREFIX}/Library/MobileSubstrate/DynamicLibraries/ProjectXTweak.plist
fi

if [ -f "${JBPREFIX}/Library/ElleKit/DynamicLibraries/ProjectXTweak.dylib" ]; then
    chmod 644 ${JBPREFIX}/Library/ElleKit/DynamicLibraries/ProjectXTweak.dylib
fi

if [ -f "${JBPREFIX}/Library/ElleKit/DynamicLibraries/ProjectXTweak.plist" ]; then
    chmod 644 ${JBPREFIX}/Library/ElleKit/DynamicLibraries/ProjectXTweak.plist
fi

# Fix path issues - specific to Dopamine 2
if [ -d "${JBPREFIX}/var/jb/Applications/ProjectX.app" ] && [ ! -d "${JBPREFIX}/Applications/ProjectX.app" ]; then
    echo "Fixing duplicate path issue..."
    mkdir -p ${JBPREFIX}/Applications
    cp -R ${JBPREFIX}/var/jb/Applications/ProjectX.app ${JBPREFIX}/Applications/
fi

# For standard rootless path issues
if [ -d "${JBPREFIX}/var/jb/Applications/ProjectX.app" ] && [ ! -d "${JBPREFIX}/Applications/ProjectX.app" ]; then
    echo "Fixing path issue..."
    mkdir -p ${JBPREFIX}/Applications
    cp -R ${JBPREFIX}/var/jb/Applications/ProjectX.app ${JBPREFIX}/Applications/
fi

# Ensure app permissions are correct
if [ -d "${JBPREFIX}/Applications/ProjectX.app" ]; then
    echo "Setting app permissions..."
    chmod 755 ${JBPREFIX}/Applications/ProjectX.app
    chmod 755 ${JBPREFIX}/Applications/ProjectX.app/ProjectX
    
    # Force app registration with SpringBoard - Dopamine 2 methods
    echo "Registering app with SpringBoard..."
    if command -v uicache >/dev/null 2>&1; then
        uicache --path ${JBPREFIX}/Applications/ProjectX.app
    fi
else
    echo "App not found in expected locations"
fi

# Handle SpringBoard reload based on available tools
if [ -f "${JBPREFIX}/usr/bin/sbreload" ]; then
    echo "Reloading SpringBoard using sbreload..."
    ${JBPREFIX}/usr/bin/sbreload
elif [ -f "${JBPREFIX}/usr/bin/ldrestart" ]; then
    echo "Light restarting device..."
    ${JBPREFIX}/usr/bin/ldrestart
else
    echo "Restarting SpringBoard directly..."
    killall -9 SpringBoard
fi

echo "Setup complete!" 