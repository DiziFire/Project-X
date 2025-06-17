#!/bin/bash

# Colors for better output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}Testing Direct Telegram PHP Script${NC}"
echo -e "${BLUE}===================================================${NC}"

# Check if AUTH_TOKEN argument is provided
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 AUTH_TOKEN NEW_TELEGRAM_TAG${NC}"
    exit 1
fi

AUTH_TOKEN="$1"
TELEGRAM_TAG="$2"
API_URL="https://hydra.weaponx.us"  # Change this to your actual API URL

echo -e "${BLUE}API URL: ${API_URL}${NC}"
echo -e "${BLUE}Testing with auth token: ${AUTH_TOKEN:0:6}...${AUTH_TOKEN:(-4)}${NC}"
echo -e "${BLUE}Testing with Telegram tag: ${TELEGRAM_TAG}${NC}\n"

# Step 1: GET current Telegram tag
echo -e "${BLUE}[STEP 1] Fetching current Telegram tag...${NC}"
CURRENT_TAG_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -H "Accept: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -v "${API_URL}/direct_telegram.php" 2>&1)

# Log the full response for debugging
echo -e "${YELLOW}GET Response:${NC}"
echo "$CURRENT_TAG_RESPONSE"
echo ""

# Extract the HTTP status code
STATUS_CODE=$(echo "$CURRENT_TAG_RESPONSE" | grep -o "< HTTP/[0-9.]* [0-9]*" | awk '{print $3}')
if [[ "$STATUS_CODE" -ge 200 && "$STATUS_CODE" -lt 300 ]]; then
    echo -e "${GREEN}GET request successful with status code: ${STATUS_CODE}${NC}"
    
    # Extract the current telegram_tag
    if echo "$CURRENT_TAG_RESPONSE" | grep -q "\"telegram_tag\""; then
        # Extract the tag value
        CURRENT_TAG=$(echo "$CURRENT_TAG_RESPONSE" | grep -o "\"telegram_tag\":\"[^\"]*\"" | cut -d'"' -f4)
        echo -e "${GREEN}Current Telegram tag: ${CURRENT_TAG:-<empty>}${NC}"
    else
        echo -e "${RED}Couldn't find telegram_tag in response${NC}"
    fi
else
    echo -e "${RED}GET request failed with status code: ${STATUS_CODE:-unknown}${NC}"
fi

echo ""

# Step 2: POST new Telegram tag
echo -e "${BLUE}[STEP 2] Setting Telegram tag to: ${TELEGRAM_TAG}...${NC}"
UPDATE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Accept: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -d "telegram_tag=${TELEGRAM_TAG}" \
    -v "${API_URL}/direct_telegram.php" 2>&1)

# Log the full response for debugging
echo -e "${YELLOW}POST Response:${NC}"
echo "$UPDATE_RESPONSE"
echo ""

# Extract the HTTP status code
STATUS_CODE=$(echo "$UPDATE_RESPONSE" | grep -o "< HTTP/[0-9.]* [0-9]*" | awk '{print $3}')
if [[ "$STATUS_CODE" -ge 200 && "$STATUS_CODE" -lt 300 ]]; then
    echo -e "${GREEN}POST request successful with status code: ${STATUS_CODE}${NC}"
    
    # Extract success message
    if echo "$UPDATE_RESPONSE" | grep -q "\"status\":\"success\""; then
        echo -e "${GREEN}Update successful!${NC}"
    else
        echo -e "${YELLOW}Update may not have been successful${NC}"
    fi
else
    echo -e "${RED}POST request failed with status code: ${STATUS_CODE:-unknown}${NC}"
fi

echo ""

# Step 3: Verify update
echo -e "${BLUE}[STEP 3] Verifying update...${NC}"
VERIFY_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer ${AUTH_TOKEN}" \
    -H "Accept: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    "${API_URL}/direct_telegram.php")

# Extract the current tag after update
if echo "$VERIFY_RESPONSE" | grep -q "\"telegram_tag\""; then
    # Extract the tag value
    UPDATED_TAG=$(echo "$VERIFY_RESPONSE" | grep -o "\"telegram_tag\":\"[^\"]*\"" | cut -d'"' -f4)
    echo -e "${BLUE}Tag after update: ${UPDATED_TAG:-<empty>}${NC}"
    
    # Clean tags for comparison (remove @ if present)
    CLEAN_EXPECTED_TAG="${TELEGRAM_TAG#@}"
    CLEAN_ACTUAL_TAG="${UPDATED_TAG#@}"
    
    if [[ "$CLEAN_ACTUAL_TAG" == "$CLEAN_EXPECTED_TAG" ]]; then
        echo -e "${GREEN}✅ VERIFICATION SUCCESSFUL: Tag was updated correctly!${NC}"
    else
        echo -e "${RED}❌ VERIFICATION FAILED: Expected '${TELEGRAM_TAG}', but got '${UPDATED_TAG}'${NC}"
    fi
else
    echo -e "${RED}Couldn't find telegram_tag in verification response${NC}"
fi

echo -e "\n${BLUE}Test completed.${NC}" 