#!/bin/bash

# Colors for better output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Building and running Telegram Test program${NC}"
echo -e "${BLUE}===================================================${NC}"

# Navigate to clientside directory
cd "$(dirname "$0")"

# Check if AUTH_TOKEN argument is provided
if [ "$#" -lt 2 ]; then
    echo -e "${RED}Usage: $0 AUTH_TOKEN NEW_TELEGRAM_TAG${NC}"
    exit 1
fi

# Set up source files
SOURCE_FILES=(
    "TelegramTest.m"
    "TelegramDirectManager.m"
)

# Check if we have APIManager.m for URL handling
if [ -f "APIManager.m" ]; then
    SOURCE_FILES+=("APIManager.m")
    echo -e "${GREEN}Found APIManager.m${NC}"
else
    echo -e "${YELLOW}Warning: APIManager.m not found, creating stub implementation${NC}"
    
    # Create stub APIManager.h if not exists
    if [ ! -f "APIManager.h" ]; then
        cat > APIManager.h << 'EOF'
#import <Foundation/Foundation.h>

@interface APIManager : NSObject

+ (instancetype)sharedManager;
- (NSString *)apiUrlForEndpoint:(NSString *)endpoint;

@end
EOF
        echo -e "${GREEN}Created APIManager.h stub${NC}"
    fi
    
    # Create stub APIManager.m if not exists
    cat > APIManager.m << 'EOF'
#import "APIManager.h"

@implementation APIManager

+ (instancetype)sharedManager {
    static APIManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (NSString *)apiUrlForEndpoint:(NSString *)endpoint {
    // This is a stub implementation - in the real app, this would use the proper base URL
    // For this test, we'll assume the server is running locally on port 8000
    return [NSString stringWithFormat:@"http://localhost:8000/%@", endpoint];
}

@end
EOF
    SOURCE_FILES+=("APIManager.m")
    echo -e "${GREEN}Created APIManager.m stub${NC}"
fi

# Define the output binary name
OUTPUT_BIN="telegram_test_app"

# Compile the sources - adding TELEGRAM_TEST_MAIN define flag to enable the main function
echo -e "${BLUE}Compiling Telegram test...${NC}"
clang -framework Foundation -fobjc-arc -DTELEGRAM_TEST_MAIN ${SOURCE_FILES[@]} -o $OUTPUT_BIN

# Check if compilation succeeded
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Compilation successful!${NC}"
echo -e "${BLUE}Running test...${NC}"
echo -e "${BLUE}===================================================${NC}"

# Run the test with the provided auth token and new Telegram tag
./$OUTPUT_BIN "$1" "$2"

# Check run status
RUN_STATUS=$?
if [ $RUN_STATUS -ne 0 ]; then
    echo -e "${RED}Test failed with exit code: $RUN_STATUS${NC}"
fi

# Cleanup
echo -e "${BLUE}Cleaning up...${NC}"
rm -f $OUTPUT_BIN

echo -e "${GREEN}Done!${NC}" 