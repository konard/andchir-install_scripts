#!/bin/bash

#===============================================================================
# Test script for IP filtering and Basic Auth argument parsing
# This script tests the argument parsing logic for mysql-phpmyadmin.sh and
# postgresql-mathesar.sh without actually running the installation.
#===============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Mock functions that would normally call real services
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_info() { echo -e "[INFO] $1"; }
print_header() { echo ""; echo "=== $1 ==="; echo ""; }

# Validation functions (same as in the scripts)
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done
    return 0
}

# Test helper
run_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test argument parsing function
parse_arguments() {
    DOMAIN_NAME=""
    ALLOWED_IP=""
    ENABLE_BASIC_AUTH="false"

    if [[ $# -lt 1 ]] || [[ -z "$1" ]]; then
        return 1
    fi

    DOMAIN_NAME="$1"
    if ! validate_domain "$DOMAIN_NAME"; then
        return 1
    fi
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --allowed-ip)
                if [[ -z "$2" ]] || [[ "$2" == --* ]]; then
                    return 1
                fi
                ALLOWED_IP="$2"
                if ! validate_ip "$ALLOWED_IP"; then
                    return 1
                fi
                shift 2
                ;;
            --basic-auth)
                ENABLE_BASIC_AUTH="true"
                shift
                ;;
            *)
                return 1
                ;;
        esac
    done

    return 0
}

echo "================================================"
echo "Testing IP Filtering and Basic Auth Arguments"
echo "================================================"
echo ""

# Test 1: Domain only
echo "--- Test 1: Domain only ---"
parse_arguments "db.example.com"
run_test "Domain set correctly" "db.example.com" "$DOMAIN_NAME"
run_test "No allowed IP" "" "$ALLOWED_IP"
run_test "Basic auth disabled" "false" "$ENABLE_BASIC_AUTH"
echo ""

# Test 2: Domain with --allowed-ip
echo "--- Test 2: Domain with --allowed-ip ---"
parse_arguments "db.example.com" "--allowed-ip" "192.168.1.100"
run_test "Domain set correctly" "db.example.com" "$DOMAIN_NAME"
run_test "Allowed IP set" "192.168.1.100" "$ALLOWED_IP"
run_test "Basic auth disabled" "false" "$ENABLE_BASIC_AUTH"
echo ""

# Test 3: Domain with --basic-auth
echo "--- Test 3: Domain with --basic-auth ---"
parse_arguments "db.example.com" "--basic-auth"
run_test "Domain set correctly" "db.example.com" "$DOMAIN_NAME"
run_test "No allowed IP" "" "$ALLOWED_IP"
run_test "Basic auth enabled" "true" "$ENABLE_BASIC_AUTH"
echo ""

# Test 4: Domain with both options
echo "--- Test 4: Domain with both options ---"
parse_arguments "db.example.com" "--allowed-ip" "10.0.0.1" "--basic-auth"
run_test "Domain set correctly" "db.example.com" "$DOMAIN_NAME"
run_test "Allowed IP set" "10.0.0.1" "$ALLOWED_IP"
run_test "Basic auth enabled" "true" "$ENABLE_BASIC_AUTH"
echo ""

# Test 5: Both options in reverse order
echo "--- Test 5: Both options in reverse order ---"
parse_arguments "mathesar.example.com" "--basic-auth" "--allowed-ip" "172.16.0.50"
run_test "Domain set correctly" "mathesar.example.com" "$DOMAIN_NAME"
run_test "Allowed IP set" "172.16.0.50" "$ALLOWED_IP"
run_test "Basic auth enabled" "true" "$ENABLE_BASIC_AUTH"
echo ""

# Test 6: Invalid IP address
echo "--- Test 6: Invalid IP address ---"
if parse_arguments "db.example.com" "--allowed-ip" "256.1.1.1" 2>/dev/null; then
    run_test "Invalid IP rejected" "fail" "pass"
else
    run_test "Invalid IP rejected" "fail" "fail"
fi
echo ""

# Test 7: Missing IP after --allowed-ip
echo "--- Test 7: Missing IP after --allowed-ip ---"
if parse_arguments "db.example.com" "--allowed-ip" 2>/dev/null; then
    run_test "Missing IP rejected" "fail" "pass"
else
    run_test "Missing IP rejected" "fail" "fail"
fi
echo ""

# Test 8: Invalid domain
echo "--- Test 8: Invalid domain ---"
if parse_arguments "invalid" 2>/dev/null; then
    run_test "Invalid domain rejected" "fail" "pass"
else
    run_test "Invalid domain rejected" "fail" "fail"
fi
echo ""

# Test 9: Unknown option
echo "--- Test 9: Unknown option ---"
if parse_arguments "db.example.com" "--unknown-option" 2>/dev/null; then
    run_test "Unknown option rejected" "fail" "pass"
else
    run_test "Unknown option rejected" "fail" "fail"
fi
echo ""

# Summary
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
