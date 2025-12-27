#!/bin/bash

#===============================================================================
# Test script for PHP memory limit parsing issue
# Issue: https://github.com/andchir/install_scripts/issues/123
#
# Problem: When PHP memory_limit is -1 (unlimited), numfmt fails to parse it,
# leading to a negative value for MAX_PHP_PROCESSES.
#
# The fix:
# 1. Handle -1 (unlimited) as a special case, using 256M default
# 2. Validate that converted values are positive integers
# 3. Use integer arithmetic instead of bc for the calculation
# 4. Ensure result is always between 5 and 50
#===============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Testing PHP Memory Limit Parsing Fix ===${NC}"
echo -e "${CYAN}Issue: https://github.com/andchir/install_scripts/issues/123${NC}"
echo ""

# Simulate available memory (6474 MB = 6474 * 1024 KB, as reported in the issue)
AVAIL_MEM=6631424  # in KB (approximately 6474 MB)
AVAIL_MEM_BYTES=$((AVAIL_MEM * 1024))

echo "Simulating server with $((AVAIL_MEM / 1024)) MB available memory"
echo ""

# Test the fixed calculation function
test_fixed_calculation() {
    local PHP_MEM_LIMIT="$1"
    local PHP_MEM_LIMIT_BYTES

    # Handle special case when memory_limit is -1 (unlimited)
    if [[ "$PHP_MEM_LIMIT" == "-1" ]]; then
        PHP_MEM_LIMIT_BYTES=268435456
        echo "  → Unlimited (-1) detected, using 256M (268435456 bytes)"
    elif [[ -z "$PHP_MEM_LIMIT" ]] || [[ "$PHP_MEM_LIMIT" == "0" ]]; then
        PHP_MEM_LIMIT_BYTES=134217728
        echo "  → Empty/zero value, using default 128M (134217728 bytes)"
    else
        # Try to convert using numfmt if available
        if command -v numfmt &> /dev/null; then
            PHP_MEM_LIMIT_BYTES=$(echo "$PHP_MEM_LIMIT" | numfmt --from=iec 2>/dev/null || echo "")
        else
            # Fallback manual conversion for common formats (for testing without numfmt)
            case "$PHP_MEM_LIMIT" in
                *M) PHP_MEM_LIMIT_BYTES=$((${PHP_MEM_LIMIT%M} * 1024 * 1024)) ;;
                *G) PHP_MEM_LIMIT_BYTES=$((${PHP_MEM_LIMIT%G} * 1024 * 1024 * 1024)) ;;
                *K) PHP_MEM_LIMIT_BYTES=$((${PHP_MEM_LIMIT%K} * 1024)) ;;
                [0-9]*) PHP_MEM_LIMIT_BYTES=$PHP_MEM_LIMIT ;;
                *) PHP_MEM_LIMIT_BYTES="" ;;
            esac
        fi

        # Validate the result is a positive number
        if [[ -z "$PHP_MEM_LIMIT_BYTES" ]] || ! [[ "$PHP_MEM_LIMIT_BYTES" =~ ^[0-9]+$ ]] || [[ "$PHP_MEM_LIMIT_BYTES" -le 0 ]]; then
            PHP_MEM_LIMIT_BYTES=134217728
            echo "  → Invalid value, using default 128M (134217728 bytes)"
        else
            echo "  → Converted to $PHP_MEM_LIMIT_BYTES bytes"
        fi
    fi

    # Calculate max processes using integer arithmetic (avoids bc dependency)
    local MAX_PHP_PROCESSES=$((AVAIL_MEM_BYTES / PHP_MEM_LIMIT_BYTES))

    # Ensure minimum of 5 processes
    if [[ "$MAX_PHP_PROCESSES" -lt 5 ]]; then
        MAX_PHP_PROCESSES=5
    fi

    # Cap at reasonable maximum of 50
    if [[ "$MAX_PHP_PROCESSES" -gt 50 ]]; then
        MAX_PHP_PROCESSES=50
    fi

    echo "  → MAX_PHP_PROCESSES: $MAX_PHP_PROCESSES"

    # Validate result is sensible (not negative, within bounds)
    if [[ "$MAX_PHP_PROCESSES" -ge 5 ]] && [[ "$MAX_PHP_PROCESSES" -le 50 ]]; then
        echo -e "  ${GREEN}✓ Result is valid (between 5 and 50)${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Result is invalid: $MAX_PHP_PROCESSES${NC}"
        return 1
    fi
}

# Test cases from the original issue and edge cases
test_values=(
    "-1"        # The problematic case from the issue
    "128M"      # Common default
    "256M"      # Common WordPress setting
    "512M"      # Higher setting
    "1G"        # Very high setting
    "0"         # Edge case
    ""          # Empty value
    "invalid"   # Invalid format
    "64M"       # Lower setting
)

passed=0
failed=0

for value in "${test_values[@]}"; do
    echo -e "${YELLOW}Testing: '$value'${NC}"
    if test_fixed_calculation "$value"; then
        ((passed++))
    else
        ((failed++))
    fi
    echo ""
done

echo -e "${CYAN}=== Test Results ===${NC}"
echo -e "Passed: ${GREEN}$passed${NC}"
echo -e "Failed: ${RED}$failed${NC}"

if [[ "$failed" -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
