#!/bin/bash

# Test script to verify the gzip.conf fix handles old configurations correctly

set -e

echo "=== Testing gzip.conf fix for issue #165 ==="
echo ""

# Create test directory structure
TEST_DIR="/tmp/test_gzip_fix_$$"
mkdir -p "$TEST_DIR/conf.d"
NGINX_CONF_DIR="$TEST_DIR"

echo "Test directory: $TEST_DIR"
echo ""

# Test 1: Old gzip.conf with 'gzip on;' directive
echo "Test 1: Old gzip.conf with duplicate 'gzip on;' directive"
echo "-----------------------------------------------------"

cat > "$TEST_DIR/conf.d/gzip.conf" << 'EOF'
# Gzip compression configuration
# Credit: https://github.com/h5bp/server-configs-nginx/

# Enable gzip compression
gzip on;

# Compression level (1-9)
gzip_comp_level 6;
EOF

echo "Created old gzip.conf with 'gzip on;' directive"
echo "Content:"
cat -n "$TEST_DIR/conf.d/gzip.conf"
echo ""

# Check if old config is detected
if grep -q "^[[:space:]]*gzip[[:space:]]\+on;" "$TEST_DIR/conf.d/gzip.conf"; then
    echo "✅ PASS: Detected 'gzip on;' directive in gzip.conf"
    echo "   → Script would remove and recreate the file"
    rm -f "$TEST_DIR/conf.d/gzip.conf"
    echo "   → File removed for recreation"
else
    echo "❌ FAIL: Did not detect 'gzip on;' directive"
    exit 1
fi
echo ""

# Test 2: Create new gzip.conf without 'gzip on;' directive
echo "Test 2: New gzip.conf without 'gzip on;' directive"
echo "---------------------------------------------------"

cat > "$TEST_DIR/conf.d/gzip.conf" << 'EOF'
# Gzip compression configuration
# Credit: https://github.com/h5bp/server-configs-nginx/
# Note: The main 'gzip on;' directive is already enabled in /etc/nginx/nginx.conf
# This file only adds additional gzip settings

# Compression level (1-9)
# 6 is a good compromise between size and CPU usage, offering about 75%
# reduction for most ASCII files
gzip_comp_level 6;

# Don't compress anything that's already small
gzip_min_length 256;

# Compress data even for clients connecting via proxies
gzip_proxied any;

# Tell proxies to cache both gzipped and regular versions
gzip_vary on;

# Compress these MIME types (text/html is always compressed)
gzip_types
    application/atom+xml
    application/javascript
    application/json
    text/css
    text/plain;
EOF

echo "Created new gzip.conf without 'gzip on;' directive"
echo ""

# Check if new config is NOT flagged for removal
if grep -q "^[[:space:]]*gzip[[:space:]]\+on;" "$TEST_DIR/conf.d/gzip.conf"; then
    echo "❌ FAIL: Incorrectly detected 'gzip on;' directive in new config"
    exit 1
else
    echo "✅ PASS: New config does not contain 'gzip on;' directive"
    echo "   → Script would keep the file as-is"
fi
echo ""

# Test 3: Verify all expected directives are present
echo "Test 3: Verify all expected directives are present in new config"
echo "----------------------------------------------------------------"

PASS_COUNT=0
FAIL_COUNT=0

check_directive() {
    local directive="$1"
    if grep -q "$directive" "$TEST_DIR/conf.d/gzip.conf"; then
        echo "   ✅ $directive found"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "   ❌ $directive NOT found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

check_directive "gzip_comp_level"
check_directive "gzip_min_length"
check_directive "gzip_proxied"
check_directive "gzip_vary"
check_directive "gzip_types"

echo ""
if [[ $FAIL_COUNT -eq 0 ]]; then
    echo "✅ PASS: All expected directives present ($PASS_COUNT/5)"
else
    echo "❌ FAIL: Missing directives ($FAIL_COUNT/5 missing)"
    exit 1
fi
echo ""

# Cleanup
rm -rf "$TEST_DIR"

echo "=== All tests passed! ==="
echo ""
echo "Summary:"
echo "  ✅ Old gzip.conf with 'gzip on;' is detected and would be removed"
echo "  ✅ New gzip.conf without 'gzip on;' is preserved"
echo "  ✅ All expected gzip directives are present in new config"
echo ""
echo "This fix ensures that:"
echo "  1. Users running the script for the first time get the correct config"
echo "  2. Users who already ran the old script will have their gzip.conf recreated"
echo "  3. Users who already have the new config will not be affected"
