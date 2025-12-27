#!/bin/bash
#
# Test script to verify the MySQL socket directory fix
#
# This script simulates the conditions that cause the socket directory issue
# and verifies that the fix works correctly.
#
# The issue: When MySQL is started in recovery mode (mysqld_safe --skip-grant-tables),
# the socket directory /var/run/mysqld may not exist, causing:
#   "Directory '/var/run/mysqld' for UNIX socket file don't exists."
#   "ERROR 2002 (HY000): Can't connect to local MySQL server through socket..."
#
# The fix: Create the socket directory with proper ownership before starting mysqld_safe.
#
# Usage (run as root):
#   sudo bash experiments/test_mysql_socket_fix.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "MySQL Socket Directory Fix Test"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Run with: sudo bash $0"
    exit 1
fi

# Check if MySQL is installed
if ! command -v mysql &> /dev/null; then
    echo -e "${YELLOW}Warning: MySQL is not installed. Installing...${NC}"
    apt-get update -qq
    apt-get install -y -qq mysql-server
fi

echo "Step 1: Stop MySQL service..."
systemctl stop mysql 2>/dev/null || true
sleep 1

echo "Step 2: Remove the socket directory to simulate the issue..."
rm -rf /var/run/mysqld
echo "  - Directory removed: /var/run/mysqld"

echo ""
echo "Step 3: Verify directory is missing..."
if [[ -d /var/run/mysqld ]]; then
    echo -e "${RED}  - Directory still exists (unexpected)${NC}"
else
    echo -e "${GREEN}  - Directory confirmed missing${NC}"
fi

echo ""
echo "Step 4: Apply the fix - create socket directory with proper ownership..."
mkdir -p /var/run/mysqld
chown mysql:mysql /var/run/mysqld
chmod 755 /var/run/mysqld
echo -e "${GREEN}  - Directory created: /var/run/mysqld${NC}"

echo ""
echo "Step 5: Verify directory exists with correct permissions..."
if [[ -d /var/run/mysqld ]]; then
    OWNER=$(stat -c '%U:%G' /var/run/mysqld)
    PERMS=$(stat -c '%a' /var/run/mysqld)
    echo "  - Owner: $OWNER"
    echo "  - Permissions: $PERMS"

    if [[ "$OWNER" == "mysql:mysql" && "$PERMS" == "755" ]]; then
        echo -e "${GREEN}  - Permissions are correct!${NC}"
    else
        echo -e "${YELLOW}  - Permissions may need adjustment${NC}"
    fi
else
    echo -e "${RED}  - Directory creation failed!${NC}"
    exit 1
fi

echo ""
echo "Step 6: Start MySQL in recovery mode..."
mysqld_safe --skip-grant-tables --skip-networking &
MYSQLD_PID=$!
sleep 3

echo ""
echo "Step 7: Test connection to MySQL..."
if mysql -u root -e "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}Success: Connected to MySQL in recovery mode!${NC}"
    RESULT="PASS"
else
    echo -e "${RED}Failed: Could not connect to MySQL${NC}"
    RESULT="FAIL"
fi

echo ""
echo "Step 8: Cleanup - stop recovery mode MySQL and start normal service..."
kill $MYSQLD_PID 2>/dev/null || true
pkill -9 mysqld 2>/dev/null || true
sleep 2
systemctl start mysql
echo "  - MySQL service restarted normally"

echo ""
echo "========================================"
echo "TEST RESULT: $RESULT"
echo "========================================"
echo ""

if [[ "$RESULT" == "PASS" ]]; then
    echo -e "${GREEN}The socket directory fix works correctly!${NC}"
    exit 0
else
    echo -e "${RED}The fix did not resolve the issue.${NC}"
    exit 1
fi
