#!/bin/bash

# Test script for device removal functionality
# This script tests the device removal API endpoint to verify our changes
# Usage: ./test_device_removal.sh <auth_token> <device_uuid>

if [ $# -lt 2 ]; then
    echo "Usage: $0 <auth_token> <device_uuid>"
    exit 1
fi

AUTH_TOKEN="$1"
DEVICE_UUID="$2"
API_URL="http://localhost:8000"  # Change this to your actual API URL

echo "Testing device removal functionality..."
echo "Device UUID: $DEVICE_UUID"
echo "API URL: $API_URL"

# Test the device removal API endpoint
echo -e "\n[TEST 1] Testing with POST method and force_remove parameter..."
curl -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"force_remove": true}' \
    -v "$API_URL/api/devices/$DEVICE_UUID/revoke"

echo -e "\n\n[TEST 2] For comparison, testing with DELETE method..."
curl -X DELETE \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -v "$API_URL/api/devices/$DEVICE_UUID"

echo -e "\n\nTests completed." 