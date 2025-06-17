#!/bin/bash

# Test script for the AppDataCleaner with enhanced app group container cleaning

if [ -z "$1" ]; then
    echo "Usage: $0 <bundle_id>"
    echo "Example: $0 com.ubercab.UberClient"
    exit 1
fi

BUNDLE_ID=$1
LOG_FILE="clean_test_log.txt"

echo "Starting test for bundle ID: $BUNDLE_ID"
echo "Logs will be saved to $LOG_FILE"

# Clear previous log
rm -f "$LOG_FILE"

# Write a timestamp to the log
date > "$LOG_FILE"

# Run the app with arguments to trigger the data cleaning process
echo "Running data cleaning test..."
echo "Command: xcrun simctl launch --console-pty booted com.hydra.projectx \"clean_test\" \"$BUNDLE_ID\"" >> "$LOG_FILE"
xcrun simctl launch --console-pty booted com.hydra.projectx "clean_test" "$BUNDLE_ID" 2>&1 | tee -a "$LOG_FILE"

echo
echo "Test completed. Check $LOG_FILE for results."
echo "Analyzing log file for uncleared data paths..."

# Check if there are any uncleared data paths in the log
if grep -q "UNCLEARED:" "$LOG_FILE"; then
    echo "⚠️ FOUND UNCLEARED DATA PATHS:"
    grep -A 10 "WARNING: Verification found" "$LOG_FILE"
else
    echo "✅ SUCCESS: No uncleared data paths found."
fi

# Check the final verification result
if grep -q "Data cleared verification: Failed" "$LOG_FILE"; then
    echo "❌ VERIFICATION FAILED"
else
    echo "✅ VERIFICATION PASSED"
fi

echo
echo "Done. Full log is available in $LOG_FILE" 