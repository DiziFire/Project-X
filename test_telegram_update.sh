#!/bin/bash

# Test script for Telegram username update functionality
# This script tests the Telegram username update API endpoint with enhanced debugging
# Usage: ./test_telegram_update.sh <auth_token> <telegram_username>

set -e  # Exit on error
VERBOSE=true  # Set to true for verbose debugging output

function log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "\033[0;36m[DEBUG] $1\033[0m"
    fi
}

function log_error() {
    echo -e "\033[0;31m[ERROR] $1\033[0m"
}

function log_success() {
    echo -e "\033[0;32m[SUCCESS] $1\033[0m"
}

function log_info() {
    echo -e "\033[0;34m[INFO] $1\033[0m"
}

if [ $# -lt 2 ]; then
    log_error "Usage: $0 <auth_token> <telegram_username>"
    exit 1
fi

AUTH_TOKEN="$1"
TELEGRAM_USERNAME="$2"
API_URL="https://hydra.weaponx.us"  # Change this to your actual API URL

log_info "Starting Telegram username update tests..."
log_info "Telegram username to set: $TELEGRAM_USERNAME"
log_info "API URL: $API_URL"
log_debug "Auth token: ${AUTH_TOKEN:0:6}...${AUTH_TOKEN:(-4)}"

# First get a CSRF token from the server
log_info "\n[STEP 1] Getting CSRF token from server..."
CSRF_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Accept: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    --cookie-jar cookie.txt \
    -v "${API_URL}/csrf-token" 2>&1)

# Log the full request and response for debugging
log_debug "CSRF Request/Response:"
log_debug "$CSRF_RESPONSE"

# Extract the CSRF token from the response
if echo "$CSRF_RESPONSE" | grep -q '"csrf_token"'; then
    CSRF_TOKEN=$(echo "$CSRF_RESPONSE" | grep -o '"csrf_token":"[^"]*"' | cut -d'"' -f4)
    log_success "Extracted CSRF token from JSON response"
else
    log_debug "No JSON CSRF token found, trying cookie..."
    # If we couldn't get it from the JSON, try extracting from cookie
    if [ -f cookie.txt ] && grep -q "XSRF-TOKEN" cookie.txt; then
        CSRF_TOKEN=$(grep -o "XSRF-TOKEN.*" cookie.txt | cut -f7)
        
        # URL decode the token
        if command -v python3 > /dev/null; then
            CSRF_TOKEN=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$CSRF_TOKEN'))")
            log_success "Extracted and decoded CSRF token from cookie"
        else
            log_error "Python3 not available for URL decoding"
            # Basic URL decoding fallback
            CSRF_TOKEN=$(echo "$CSRF_TOKEN" | sed 's/%/\\x/g' | xargs -0 printf "%b")
            log_success "Extracted and basic-decoded CSRF token from cookie"
        fi
    else
        log_error "No CSRF token found in cookies"
        # Fallback to direct route which should bypass CSRF
        CSRF_TOKEN="none"
    fi
fi

log_info "CSRF token: $CSRF_TOKEN"

# Test the Telegram username update API endpoint with form-urlencoded and CSRF token
log_info "\n[TEST 1] Testing with form-urlencoded content type and CSRF token..."
TEST1_RESPONSE=$(curl -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Accept: application/json" \
    -H "X-CSRF-TOKEN: $CSRF_TOKEN" \
    -H "X-Requested-With: XMLHttpRequest" \
    -b cookie.txt \
    -d "telegram_tag=$TELEGRAM_USERNAME" \
    -v "$API_URL/api/user/telegram" 2>&1)

log_debug "TEST 1 Response:"
log_debug "$TEST1_RESPONSE"

# Extract status code
if echo "$TEST1_RESPONSE" | grep -q "< HTTP/"; then
    STATUS_CODE=$(echo "$TEST1_RESPONSE" | grep "< HTTP/" | awk '{print $3}')
    if [[ "$STATUS_CODE" -ge 200 && "$STATUS_CODE" -lt 300 ]]; then
        log_success "TEST 1: Success with status code $STATUS_CODE"
    else
        log_error "TEST 1: Failed with status code $STATUS_CODE"
    fi
else
    log_error "TEST 1: Could not determine status code"
fi

# Test the direct/telegram route that should bypass CSRF
log_info "\n[TEST 2] Testing direct route that bypasses CSRF protection..."
TEST2_RESPONSE=$(curl -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Accept: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -d "telegram_tag=$TELEGRAM_USERNAME" \
    -v "$API_URL/direct/telegram" 2>&1)

log_debug "TEST 2 Response:"
log_debug "$TEST2_RESPONSE"

# Extract status code
if echo "$TEST2_RESPONSE" | grep -q "< HTTP/"; then
    STATUS_CODE=$(echo "$TEST2_RESPONSE" | grep "< HTTP/" | awk '{print $3}')
    if [[ "$STATUS_CODE" -ge 200 && "$STATUS_CODE" -lt 300 ]]; then
        log_success "TEST 2: Success with status code $STATUS_CODE"
    else
        log_error "TEST 2: Failed with status code $STATUS_CODE"
    fi
else
    log_error "TEST 2: Could not determine status code"
fi

# Test with withoutMiddleware route
log_info "\n[TEST 3] Testing route with withoutMiddleware..."
TEST3_RESPONSE=$(curl -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Accept: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -d "telegram_tag=$TELEGRAM_USERNAME" \
    -v "$API_URL/api/user/telegram" 2>&1)

log_debug "TEST 3 Response:"
log_debug "$TEST3_RESPONSE"

# Extract status code
if echo "$TEST3_RESPONSE" | grep -q "< HTTP/"; then
    STATUS_CODE=$(echo "$TEST3_RESPONSE" | grep "< HTTP/" | awk '{print $3}')
    if [[ "$STATUS_CODE" -ge 200 && "$STATUS_CODE" -lt 300 ]]; then
        log_success "TEST 3: Success with status code $STATUS_CODE"
    else
        log_error "TEST 3: Failed with status code $STATUS_CODE"
    fi
else
    log_error "TEST 3: Could not determine status code"
fi

# Test adding X-XSRF-TOKEN header which may work better
log_info "\n[TEST 4] Testing with X-XSRF-TOKEN header..."
if [ -f cookie.txt ] && grep -q "XSRF-TOKEN" cookie.txt; then
    XSRF_TOKEN=$(grep -o "XSRF-TOKEN.*" cookie.txt | cut -f7)
    TEST4_RESPONSE=$(curl -X POST \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: application/json" \
        -H "X-XSRF-TOKEN: $XSRF_TOKEN" \
        -H "X-Requested-With: XMLHttpRequest" \
        -b cookie.txt \
        -d "telegram_tag=$TELEGRAM_USERNAME" \
        -v "$API_URL/api/user/telegram" 2>&1)

    log_debug "TEST 4 Response:"
    log_debug "$TEST4_RESPONSE"

    # Extract status code
    if echo "$TEST4_RESPONSE" | grep -q "< HTTP/"; then
        STATUS_CODE=$(echo "$TEST4_RESPONSE" | grep "< HTTP/" | awk '{print $3}')
        if [[ "$STATUS_CODE" -ge 200 && "$STATUS_CODE" -lt 300 ]]; then
            log_success "TEST 4: Success with status code $STATUS_CODE"
        else
            log_error "TEST 4: Failed with status code $STATUS_CODE"
        fi
    else
        log_error "TEST 4: Could not determine status code"
    fi
else
    log_error "TEST 4: No XSRF-TOKEN cookie found, skipping test"
fi

# Verify the current Telegram tag
log_info "\n[VERIFY] Getting current Telegram tag to verify update..."
VERIFY_RESPONSE=$(curl -s -X GET \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Accept: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -v "$API_URL/api/user/telegram" 2>&1)

log_debug "VERIFY Response:"
log_debug "$VERIFY_RESPONSE"

# Check if we got a valid response and extract the telegram_tag
if echo "$VERIFY_RESPONSE" | grep -q "200 OK"; then
    # Extract the telegram_tag value from JSON
    CURRENT_TAG=$(echo "$VERIFY_RESPONSE" | grep -o '"telegram_tag":"[^"]*"' | cut -d'"' -f4)
    if [ "$CURRENT_TAG" = "$TELEGRAM_USERNAME" ] || [ "@$CURRENT_TAG" = "$TELEGRAM_USERNAME" ]; then
        log_success "VERIFICATION SUCCESSFUL: Telegram tag updated to $CURRENT_TAG"
    else
        log_error "VERIFICATION FAILED: Current tag is '$CURRENT_TAG', expected '$TELEGRAM_USERNAME'"
    fi
else
    log_error "VERIFICATION FAILED: Could not retrieve current Telegram tag"
fi

log_info "\nTests completed."

# Clean up
rm -f cookie.txt 