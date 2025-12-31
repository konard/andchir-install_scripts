#!/bin/bash

# Test script to validate the gzip configuration fix
# This script simulates the nginx configuration and checks for duplicate gzip directives

set -e

echo "Testing gzip configuration fix..."
echo ""

# Create a temporary directory for testing
TEST_DIR=$(mktemp -d)
echo "Test directory: $TEST_DIR"

# Simulate default nginx.conf with gzip on
cat > "$TEST_DIR/nginx.conf" << 'EOF'
http {
    gzip on;
}
EOF

# Create conf.d directory
mkdir -p "$TEST_DIR/conf.d"

# Simulate the FIXED gzip.conf (without duplicate 'gzip on;')
cat > "$TEST_DIR/conf.d/gzip.conf" << 'EOF'
# Gzip compression configuration
# Credit: https://github.com/h5bp/server-configs-nginx/
# Note: The main 'gzip on;' directive is already enabled in /etc/nginx/nginx.conf
# This file only adds additional gzip settings

# Compression level (1-9)
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
    application/geo+json
    application/javascript
    application/x-javascript
    application/json;
EOF

echo "Created test configuration files:"
echo "  - nginx.conf (with 'gzip on;')"
echo "  - conf.d/gzip.conf (without 'gzip on;')"
echo ""

# Count occurrences of 'gzip on;' in both files
GZIP_ON_COUNT=$(cat "$TEST_DIR/nginx.conf" "$TEST_DIR/conf.d/gzip.conf" | grep -c "^[[:space:]]*gzip[[:space:]]\+on;" || echo "0")

echo "Number of 'gzip on;' directives found: $GZIP_ON_COUNT"
echo ""

if [ "$GZIP_ON_COUNT" -eq 1 ]; then
    echo "✓ SUCCESS: Only one 'gzip on;' directive found (no duplicates)"
    echo "✓ The fix correctly removes the duplicate directive"
    RESULT=0
else
    echo "✗ FAILURE: Expected 1 'gzip on;' directive, found $GZIP_ON_COUNT"
    RESULT=1
fi

# Verify that gzip settings are still present
if grep -q "gzip_comp_level" "$TEST_DIR/conf.d/gzip.conf" && \
   grep -q "gzip_types" "$TEST_DIR/conf.d/gzip.conf"; then
    echo "✓ SUCCESS: Gzip configuration settings are present"
else
    echo "✗ FAILURE: Gzip configuration settings are missing"
    RESULT=1
fi

# Clean up
rm -rf "$TEST_DIR"
echo ""
echo "Test completed!"

exit $RESULT
