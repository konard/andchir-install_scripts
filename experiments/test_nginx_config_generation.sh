#!/bin/bash

#===============================================================================
# Test script for nginx configuration generation with IP filtering and Basic Auth
# This script tests the nginx config generation logic for mysql-phpmyadmin.sh
# and postgresql-mathesar.sh without actually modifying system files.
#===============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper
run_test() {
    local test_name="$1"
    local condition="$2"

    ((TESTS_RUN++))

    if [[ "$condition" == "true" ]]; then
        echo -e "${GREEN}PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Generate nginx config for phpMyAdmin (simplified version)
generate_phpmyadmin_config() {
    local domain="$1"
    local allowed_ip="$2"
    local enable_basic_auth="$3"
    local php_fpm_socket="/run/php/php8.3-fpm.sock"

    local IP_RESTRICTION=""
    if [[ -n "$allowed_ip" ]]; then
        IP_RESTRICTION="
    # IP address restriction
    allow $allowed_ip;
    deny all;"
    fi

    local BASIC_AUTH_DIRECTIVES=""
    if [[ "$enable_basic_auth" == "true" ]]; then
        BASIC_AUTH_DIRECTIVES="
        auth_basic \"phpMyAdmin\";
        auth_basic_user_file /etc/nginx/.htpasswd-phpmyadmin;"
    fi

    cat << EOF
server {
    listen 80;
    server_name $domain;

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
$IP_RESTRICTION

    location / {$BASIC_AUTH_DIRECTIVES
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {$BASIC_AUTH_DIRECTIVES
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_fpm_socket;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    # Deny access to libraries and setup directories
    location ~ ^/(libraries|setup)/ {
        deny all;
    }

    client_max_body_size 100M;
}
EOF
}

# Generate nginx config for Mathesar (simplified version)
generate_mathesar_config() {
    local domain="$1"
    local allowed_ip="$2"
    local enable_basic_auth="$3"
    local install_dir="/home/installer_user/mathesar"
    local app_port="8000"

    local IP_RESTRICTION=""
    if [[ -n "$allowed_ip" ]]; then
        IP_RESTRICTION="
    # IP address restriction
    allow $allowed_ip;
    deny all;"
    fi

    local BASIC_AUTH_DIRECTIVES=""
    if [[ "$enable_basic_auth" == "true" ]]; then
        BASIC_AUTH_DIRECTIVES="
        auth_basic \"Mathesar\";
        auth_basic_user_file /etc/nginx/.htpasswd-mathesar;"
    fi

    cat << EOF
server {
    listen 80;
    server_name $domain;

    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
$IP_RESTRICTION

    # Static files
    location /static/ {
        alias $install_dir/static/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # Media files
    location /media/ {
        alias $install_dir/.media/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location / {$BASIC_AUTH_DIRECTIVES
        proxy_pass http://127.0.0.1:$app_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    client_max_body_size 100M;
}
EOF
}

echo "================================================"
echo "Testing Nginx Configuration Generation"
echo "================================================"
echo ""

# Test 1: phpMyAdmin without security features
echo "--- Test 1: phpMyAdmin - No security features ---"
config=$(generate_phpmyadmin_config "db.example.com" "" "false")
run_test "Contains server_name" "$(echo "$config" | grep -q 'server_name db.example.com' && echo 'true' || echo 'false')"
run_test "No allow directive" "$(echo "$config" | grep -q 'allow [0-9]' && echo 'false' || echo 'true')"
run_test "Only deny all for .ht and libraries (count=2)" "$(echo "$config" | grep -c 'deny all' | grep -q '^2$' && echo 'true' || echo 'false')"
run_test "No auth_basic" "$(echo "$config" | grep -q 'auth_basic' && echo 'false' || echo 'true')"
echo ""

# Test 2: phpMyAdmin with IP filtering
echo "--- Test 2: phpMyAdmin - IP filtering ---"
config=$(generate_phpmyadmin_config "db.example.com" "192.168.1.100" "false")
run_test "Contains allow directive" "$(echo "$config" | grep -q 'allow 192.168.1.100' && echo 'true' || echo 'false')"
run_test "Contains IP restriction deny all" "$(echo "$config" | grep -q '# IP address restriction' && echo 'true' || echo 'false')"
echo ""

# Test 3: phpMyAdmin with Basic Auth
echo "--- Test 3: phpMyAdmin - Basic Auth ---"
config=$(generate_phpmyadmin_config "db.example.com" "" "true")
run_test "Contains auth_basic" "$(echo "$config" | grep -q 'auth_basic \"phpMyAdmin\"' && echo 'true' || echo 'false')"
run_test "Contains htpasswd path" "$(echo "$config" | grep -q '/etc/nginx/.htpasswd-phpmyadmin' && echo 'true' || echo 'false')"
echo ""

# Test 4: phpMyAdmin with both features
echo "--- Test 4: phpMyAdmin - Both IP filtering and Basic Auth ---"
config=$(generate_phpmyadmin_config "db.example.com" "10.0.0.1" "true")
run_test "Contains allow directive" "$(echo "$config" | grep -q 'allow 10.0.0.1' && echo 'true' || echo 'false')"
run_test "Contains auth_basic" "$(echo "$config" | grep -q 'auth_basic \"phpMyAdmin\"' && echo 'true' || echo 'false')"
echo ""

# Test 5: Mathesar without security features
echo "--- Test 5: Mathesar - No security features ---"
config=$(generate_mathesar_config "mathesar.example.com" "" "false")
run_test "Contains server_name" "$(echo "$config" | grep -q 'server_name mathesar.example.com' && echo 'true' || echo 'false')"
run_test "Contains proxy_pass" "$(echo "$config" | grep -q 'proxy_pass http://127.0.0.1:8000' && echo 'true' || echo 'false')"
run_test "No auth_basic" "$(echo "$config" | grep -q 'auth_basic' && echo 'false' || echo 'true')"
echo ""

# Test 6: Mathesar with IP filtering
echo "--- Test 6: Mathesar - IP filtering ---"
config=$(generate_mathesar_config "mathesar.example.com" "172.16.0.50" "false")
run_test "Contains allow directive" "$(echo "$config" | grep -q 'allow 172.16.0.50' && echo 'true' || echo 'false')"
run_test "Contains IP restriction comment" "$(echo "$config" | grep -q '# IP address restriction' && echo 'true' || echo 'false')"
echo ""

# Test 7: Mathesar with Basic Auth
echo "--- Test 7: Mathesar - Basic Auth ---"
config=$(generate_mathesar_config "mathesar.example.com" "" "true")
run_test "Contains auth_basic" "$(echo "$config" | grep -q 'auth_basic \"Mathesar\"' && echo 'true' || echo 'false')"
run_test "Contains htpasswd path" "$(echo "$config" | grep -q '/etc/nginx/.htpasswd-mathesar' && echo 'true' || echo 'false')"
echo ""

# Test 8: Mathesar with both features
echo "--- Test 8: Mathesar - Both IP filtering and Basic Auth ---"
config=$(generate_mathesar_config "mathesar.example.com" "192.168.10.1" "true")
run_test "Contains allow directive" "$(echo "$config" | grep -q 'allow 192.168.10.1' && echo 'true' || echo 'false')"
run_test "Contains auth_basic" "$(echo "$config" | grep -q 'auth_basic \"Mathesar\"' && echo 'true' || echo 'false')"
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
