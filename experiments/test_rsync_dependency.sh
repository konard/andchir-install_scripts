#!/bin/bash

# Test script to verify rsync is included in dependencies
# This script checks if rsync is in the install_dependencies function

set -e

echo "Testing rsync dependency fix..."
echo ""

SCRIPT_PATH="../scripts/wordpress.sh"

# Check if the script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "✗ FAILURE: wordpress.sh not found at $SCRIPT_PATH"
    exit 1
fi

# Check if rsync is in the install_dependencies function
if grep -A 50 "install_dependencies()" "$SCRIPT_PATH" | grep -q "apt-get install.*rsync"; then
    echo "✓ SUCCESS: rsync is included in install_dependencies function"
    RESULT=0
else
    echo "✗ FAILURE: rsync is NOT included in install_dependencies function"
    RESULT=1
fi

# Check if rsync is used in the download_wordpress function
if grep -A 50 "download_wordpress()" "$SCRIPT_PATH" | grep -q "rsync"; then
    echo "✓ SUCCESS: rsync is used in download_wordpress function"
else
    echo "✗ FAILURE: rsync is NOT used in download_wordpress function"
    RESULT=1
fi

# Verify rsync is installed alongside other utilities
if grep -A 50 "install_dependencies()" "$SCRIPT_PATH" | grep "apt-get install.*wget curl unzip bc rsync"; then
    echo "✓ SUCCESS: rsync is installed with other utilities (wget, curl, unzip, bc)"
else
    echo "⚠ WARNING: rsync might not be installed with other utilities"
    echo "  Please verify the installation line includes: wget curl unzip bc rsync"
fi

echo ""
echo "Test completed!"

exit $RESULT
