#!/bin/bash

#===============================================================================
# Test script for get_latest_version function improvements
# Tests the GitHub API version fetching with timeouts and fallback
#===============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_info() {
    echo -e "${MAGENTA}ℹ${NC} ${1}"
}

print_success() {
    echo -e "${GREEN}✔${NC} ${GREEN}${1}${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} ${YELLOW}${1}${NC}"
}

print_error() {
    echo -e "${RED}✖${NC} ${RED}${1}${NC}"
}

print_test() {
    echo -e "\n${BLUE}Test:${NC} ${1}"
}

# The improved get_latest_version function
get_latest_version() {
    local version
    local api_url="https://api.github.com/repos/MHSanaei/3x-ui/releases/latest"

    # First try with default settings (may use IPv6)
    version=$(curl -sL --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$version" ]]; then
        # Fallback to IPv4 only (helps when IPv6 is broken)
        print_info "Trying to fetch version with IPv4..."
        version=$(curl -4 -sL --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi

    # If still empty, provide a fallback version
    if [[ -z "$version" ]]; then
        # Hardcoded fallback - update this periodically
        local fallback_version="v2.8.5"
        print_warning "Could not fetch version from GitHub API (may be rate limited)"
        print_info "Using fallback version: $fallback_version"
        version="$fallback_version"
    fi

    echo "$version"
}

# Run tests
echo "=============================================="
echo "Testing GitHub API version fetching"
echo "=============================================="

print_test "1. Normal fetch (should work)"
version=$(get_latest_version)
if [[ -n "$version" ]]; then
    print_success "Got version: $version"
else
    print_error "Failed to get version"
fi

print_test "2. Test with timeout values"
echo "Connect timeout: 10s, Max time: 30s"
start_time=$(date +%s.%N)
version=$(curl -sL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
end_time=$(date +%s.%N)
elapsed=$(echo "$end_time - $start_time" | bc)
print_info "Elapsed time: ${elapsed}s"
if [[ -n "$version" ]]; then
    print_success "Got version: $version"
else
    print_error "Failed to get version"
fi

print_test "3. Test IPv4 fallback"
version=$(curl -4 -sL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -n "$version" ]]; then
    print_success "IPv4 fetch successful: $version"
else
    print_error "IPv4 fetch failed"
fi

print_test "4. Simulate API failure (invalid URL) - should use fallback"
# Temporarily override function to test fallback
test_fallback() {
    local version
    local api_url="https://api.github.com/repos/INVALID/INVALID/releases/latest"

    version=$(curl -sL --connect-timeout 5 --max-time 10 "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$version" ]]; then
        version=$(curl -4 -sL --connect-timeout 5 --max-time 10 "$api_url" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi

    if [[ -z "$version" ]]; then
        local fallback_version="v2.8.5"
        print_warning "Could not fetch version from GitHub API (may be rate limited)"
        print_info "Using fallback version: $fallback_version"
        version="$fallback_version"
    fi

    echo "$version"
}

fallback_version=$(test_fallback)
if [[ "$fallback_version" == "v2.8.5" ]]; then
    print_success "Fallback worked correctly: $fallback_version"
else
    print_error "Fallback did not work as expected: $fallback_version"
fi

print_test "5. Check GitHub API rate limit status"
rate_info=$(curl -sI "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>&1 | grep -i "x-ratelimit")
echo "$rate_info"

echo ""
echo "=============================================="
echo "All tests completed"
echo "=============================================="
