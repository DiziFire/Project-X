#!/bin/bash

# Script to download and set up tweak dependencies
echo "Setting up tweak dependencies..."

# Create directories if they don't exist
mkdir -p ./frameworks
mkdir -p ./include
mkdir -p ./include/ellekit



# Update THEOS environment if needed
if [ -d "$THEOS" ]; then
    echo "Setting up THEOS integration..."
    mkdir -p "$THEOS/vendor/include"
    
fi

echo "Dependencies setup complete!"
echo "Note: ElleKit will be installed on the device as a dependency when the package is installed." 