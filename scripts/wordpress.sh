#!/bin/bash

#===============================================================================
#
#   WordPress - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - WordPress CMS
#   - MySQL/MariaDB Database
#   - Nginx Web Server
#   - PHP with required extensions
#   - SSL certificate via Let's Encrypt
#
#   Creates a complete WordPress installation with secure configuration.
#
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Color definitions for beautiful output
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Configuration variables
#-------------------------------------------------------------------------------
APP_NAME="wordpress"
INSTALLER_USER="installer_user"
WORDPRESS_VERSION="latest"
WP_CLI_VERSION="2.9.0"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name> [site_title]"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for WordPress (e.g., blog.example.com)"
    echo "  site_title     Optional: The title of the WordPress site (default: 'WordPress Site')"
    echo ""
    echo "Example:"
    echo "  $0 blog.example.com"
    echo "  $0 blog.example.com 'My Awesome Blog'"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., blog.example.com)"
        exit 1
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}+------------------------------------------------------------------------------+${NC}"
    echo -e "${CYAN}|${NC}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${CYAN}+------------------------------------------------------------------------------+${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}>${NC} ${WHITE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} ${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}[X]${NC} ${RED}$1${NC}"
}

print_info() {
    echo -e "${MAGENTA}[i]${NC} ${WHITE}$1${NC}"
}

generate_password() {
    # Generate a secure random password
    openssl rand -base64 24 | tr -d '/+=' | head -c 20
}

generate_salt() {
    # Generate WordPress authentication keys and salts
    openssl rand -base64 48 | tr -d '/+=' | head -c 64
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        print_info "Run with: sudo $0 <domain_name>"
        exit 1
    fi
}

setup_installer_user() {
    print_header "Setting Up Installer User"

    # Check if installer_user already exists
    if id "$INSTALLER_USER" &>/dev/null; then
        print_info "User '$INSTALLER_USER' already exists"
    else
        print_step "Creating user '$INSTALLER_USER'..."
        useradd -m -s /bin/bash "$INSTALLER_USER"
        print_success "User '$INSTALLER_USER' created"
    fi

    # Add user to sudo group for necessary operations
    print_step "Adding '$INSTALLER_USER' to sudo group..."
    usermod -aG sudo "$INSTALLER_USER"
    print_success "User added to sudo group"

    # Set up variables for the installer user
    CURRENT_USER="$INSTALLER_USER"
    HOME_DIR=$(eval echo ~$INSTALLER_USER)
    INSTALL_DIR="/var/www/$DOMAIN_NAME"

    print_success "Installer user configured: $INSTALLER_USER"
    print_info "Home directory: $HOME_DIR"
    print_info "Installation directory: $INSTALL_DIR"
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for Ubuntu. Proceed with caution on other distributions."
    fi
}

#-------------------------------------------------------------------------------
# Main installation functions
#-------------------------------------------------------------------------------

show_banner() {
    clear
    echo ""
    echo -e "${CYAN}   +-------------------------------------------------------------------------+${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${BOLD}${WHITE}WordPress${NC}                                                            ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                       ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${WHITE}This script will install and configure:${NC}                              ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} WordPress CMS (latest version)                                     ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} MySQL Database Server                                              ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Nginx Web Server                                                   ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} PHP with required extensions                                       ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} SSL certificate via Let's Encrypt                                  ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   +-------------------------------------------------------------------------+${NC}"
    echo ""
}

parse_arguments() {
    # Check if domain name argument is provided
    if [[ $# -lt 1 ]] || [[ -z "$1" ]]; then
        print_error "Domain name is required!"
        show_usage
    fi

    DOMAIN_NAME="$1"
    validate_domain "$DOMAIN_NAME"

    # Optional site title
    SITE_TITLE="${2:-WordPress Site}"

    print_header "Configuration"
    print_success "Domain configured: $DOMAIN_NAME"
    print_success "Site title: $SITE_TITLE"
}

install_dependencies() {
    print_header "Installing System Dependencies"

    # Set non-interactive mode for all package installations
    export DEBIAN_FRONTEND=noninteractive

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing PHP and required extensions..."
    apt-get install -y -qq \
        php-fpm \
        php-mysql \
        php-curl \
        php-gd \
        php-intl \
        php-mbstring \
        php-soap \
        php-xml \
        php-xmlrpc \
        php-zip \
        php-imagick > /dev/null 2>&1
    print_success "PHP and extensions installed"

    print_step "Installing MySQL Server..."
    apt-get install -y -qq mysql-server > /dev/null 2>&1
    print_success "MySQL Server installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_step "Installing additional utilities..."
    apt-get install -y -qq wget curl unzip > /dev/null 2>&1
    print_success "Additional utilities installed"

    print_success "All system dependencies installed successfully!"
}

configure_mysql() {
    print_header "Configuring MySQL Database"

    print_step "Starting MySQL service..."
    systemctl start mysql
    systemctl enable mysql > /dev/null 2>&1
    print_success "MySQL service started and enabled"

    # Database name derived from domain (replace dots and dashes with underscores)
    DB_NAME="wp_$(echo "$DOMAIN_NAME" | tr '.-' '_' | cut -c1-16)"
    DB_USER="wp_$(echo "$DOMAIN_NAME" | tr '.-' '_' | cut -c1-10)"

    # Check if WordPress credentials file already exists
    WP_CREDENTIALS_FILE="$HOME_DIR/.wordpress_${DOMAIN_NAME}_credentials"

    if [[ -f "$WP_CREDENTIALS_FILE" ]]; then
        print_info "WordPress credentials file already exists"
        print_step "Reading existing credentials..."
        DB_NAME=$(grep "^DB_NAME=" "$WP_CREDENTIALS_FILE" | cut -d'=' -f2)
        DB_USER=$(grep "^DB_USER=" "$WP_CREDENTIALS_FILE" | cut -d'=' -f2)
        DB_PASSWORD=$(grep "^DB_PASSWORD=" "$WP_CREDENTIALS_FILE" | cut -d'=' -f2)
        WP_ADMIN_USER=$(grep "^WP_ADMIN_USER=" "$WP_CREDENTIALS_FILE" | cut -d'=' -f2)
        WP_ADMIN_PASSWORD=$(grep "^WP_ADMIN_PASSWORD=" "$WP_CREDENTIALS_FILE" | cut -d'=' -f2)
        WP_ADMIN_EMAIL=$(grep "^WP_ADMIN_EMAIL=" "$WP_CREDENTIALS_FILE" | cut -d'=' -f2)
        print_success "Using existing WordPress configuration"
    else
        print_step "Generating secure passwords..."
        DB_PASSWORD=$(generate_password)
        WP_ADMIN_USER="admin"
        WP_ADMIN_PASSWORD=$(generate_password)
        WP_ADMIN_EMAIL="admin@$DOMAIN_NAME"

        print_step "Checking if database '$DB_NAME' exists..."
        if mysql -e "USE $DB_NAME" 2>/dev/null; then
            print_info "Database '$DB_NAME' already exists"
        else
            print_step "Creating database '$DB_NAME'..."
            mysql -e "CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            print_success "Database created"
        fi

        print_step "Checking if database user '$DB_USER' exists..."
        USER_EXISTS=$(mysql -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$DB_USER' AND host = 'localhost');")
        if [[ "$USER_EXISTS" == "1" ]]; then
            print_info "Database user '$DB_USER' already exists"
            print_step "Updating user password..."
            mysql -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
        else
            print_step "Creating database user '$DB_USER'..."
            mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
        fi
        print_success "Database user configured"

        print_step "Granting privileges..."
        mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
        mysql -e "FLUSH PRIVILEGES;"
        print_success "Database privileges granted"

        print_step "Saving WordPress credentials..."
        cat > "$WP_CREDENTIALS_FILE" << EOF
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
WP_ADMIN_USER=$WP_ADMIN_USER
WP_ADMIN_PASSWORD=$WP_ADMIN_PASSWORD
WP_ADMIN_EMAIL=$WP_ADMIN_EMAIL
EOF
        chown "$CURRENT_USER":"$CURRENT_USER" "$WP_CREDENTIALS_FILE"
        chmod 600 "$WP_CREDENTIALS_FILE"
        print_success "Credentials saved to $WP_CREDENTIALS_FILE"
    fi

    # Export for later use
    export DB_NAME DB_USER DB_PASSWORD WP_ADMIN_USER WP_ADMIN_PASSWORD WP_ADMIN_EMAIL
}

download_wordpress() {
    print_header "Installing WordPress"

    if [[ -d "$INSTALL_DIR" ]] && [[ -f "$INSTALL_DIR/wp-config.php" ]]; then
        print_info "WordPress already installed at $INSTALL_DIR"
        print_step "Updating WordPress core files..."

        # Preserve wp-config.php and wp-content
        print_step "Backing up configuration..."
        cp "$INSTALL_DIR/wp-config.php" /tmp/wp-config.php.backup

        # Download fresh WordPress
        TEMP_DIR=$(mktemp -d)
        print_step "Downloading latest WordPress..."
        wget -q -O /tmp/wordpress-latest.tar.gz https://wordpress.org/latest.tar.gz
        tar -xzf /tmp/wordpress-latest.tar.gz -C "$TEMP_DIR"

        # Update core files (excluding wp-content and wp-config.php)
        print_step "Updating core files..."
        rsync -a --exclude='wp-content' --exclude='wp-config.php' "$TEMP_DIR/wordpress/" "$INSTALL_DIR/"

        # Restore wp-config.php
        mv /tmp/wp-config.php.backup "$INSTALL_DIR/wp-config.php"

        # Clean up
        rm -rf "$TEMP_DIR" /tmp/wordpress-latest.tar.gz

        print_success "WordPress updated"
    else
        print_step "Creating installation directory..."
        mkdir -p "$INSTALL_DIR"

        print_step "Downloading latest WordPress..."
        wget -q -O /tmp/wordpress-latest.tar.gz https://wordpress.org/latest.tar.gz
        print_success "Download completed"

        print_step "Extracting WordPress..."
        tar -xzf /tmp/wordpress-latest.tar.gz -C /tmp/
        cp -a /tmp/wordpress/. "$INSTALL_DIR/"
        print_success "Extraction completed"

        # Clean up
        rm -rf /tmp/wordpress /tmp/wordpress-latest.tar.gz

        print_success "WordPress installed at $INSTALL_DIR"
    fi
}

configure_wordpress() {
    print_header "Configuring WordPress"

    WP_CONFIG_FILE="$INSTALL_DIR/wp-config.php"

    if [[ -f "$WP_CONFIG_FILE" ]]; then
        print_info "WordPress configuration already exists"
        print_step "Skipping configuration to preserve existing settings..."
        print_success "Using existing WordPress configuration"
        return
    fi

    print_step "Creating wp-config.php..."

    # Generate WordPress salts
    AUTH_KEY=$(generate_salt)
    SECURE_AUTH_KEY=$(generate_salt)
    LOGGED_IN_KEY=$(generate_salt)
    NONCE_KEY=$(generate_salt)
    AUTH_SALT=$(generate_salt)
    SECURE_AUTH_SALT=$(generate_salt)
    LOGGED_IN_SALT=$(generate_salt)
    NONCE_SALT=$(generate_salt)

    cat > "$WP_CONFIG_FILE" << WPCONFIG
<?php
/**
 * WordPress Configuration File
 *
 * Generated by automated installer for $DOMAIN_NAME
 */

// ** Database settings ** //
define( 'DB_NAME', '$DB_NAME' );
define( 'DB_USER', '$DB_USER' );
define( 'DB_PASSWORD', '$DB_PASSWORD' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

// ** Authentication Unique Keys and Salts ** //
define( 'AUTH_KEY',         '$AUTH_KEY' );
define( 'SECURE_AUTH_KEY',  '$SECURE_AUTH_KEY' );
define( 'LOGGED_IN_KEY',    '$LOGGED_IN_KEY' );
define( 'NONCE_KEY',        '$NONCE_KEY' );
define( 'AUTH_SALT',        '$AUTH_SALT' );
define( 'SECURE_AUTH_SALT', '$SECURE_AUTH_SALT' );
define( 'LOGGED_IN_SALT',   '$LOGGED_IN_SALT' );
define( 'NONCE_SALT',       '$NONCE_SALT' );

// ** WordPress Database Table prefix ** //
\$table_prefix = 'wp_';

// ** Debugging mode ** //
define( 'WP_DEBUG', false );

// ** Security settings ** //
define( 'DISALLOW_FILE_EDIT', true );
define( 'FORCE_SSL_ADMIN', true );

// ** File system settings ** //
define( 'FS_METHOD', 'direct' );

// ** WordPress URLs ** //
define( 'WP_HOME', 'https://$DOMAIN_NAME' );
define( 'WP_SITEURL', 'https://$DOMAIN_NAME' );

// ** Absolute path to WordPress directory ** //
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

// ** Sets up WordPress vars and included files ** //
require_once ABSPATH . 'wp-settings.php';
WPCONFIG

    chown www-data:www-data "$WP_CONFIG_FILE"
    chmod 640 "$WP_CONFIG_FILE"

    print_success "WordPress configuration created"
}

install_wp_cli() {
    print_header "Installing WP-CLI"

    WP_CLI_PATH="/usr/local/bin/wp"

    if [[ -f "$WP_CLI_PATH" ]]; then
        print_info "WP-CLI already installed"
        print_step "Updating WP-CLI..."
        "$WP_CLI_PATH" cli update --yes > /dev/null 2>&1 || true
        print_success "WP-CLI is up to date"
    else
        print_step "Downloading WP-CLI..."
        curl -s -o /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        print_success "WP-CLI downloaded"

        print_step "Installing WP-CLI..."
        chmod +x /tmp/wp-cli.phar
        mv /tmp/wp-cli.phar "$WP_CLI_PATH"
        print_success "WP-CLI installed at $WP_CLI_PATH"
    fi
}

setup_wordpress_site() {
    print_header "Setting Up WordPress Site"

    # Check if WordPress is already installed (tables exist)
    print_step "Checking if WordPress is already installed..."

    # Run wp-cli as www-data user
    if sudo -u www-data "$WP_CLI_PATH" core is-installed --path="$INSTALL_DIR" 2>/dev/null; then
        print_info "WordPress is already installed"
        print_step "Skipping WordPress setup..."
        print_success "Using existing WordPress installation"
        return
    fi

    print_step "Running WordPress installation..."
    sudo -u www-data "$WP_CLI_PATH" core install \
        --path="$INSTALL_DIR" \
        --url="https://$DOMAIN_NAME" \
        --title="$SITE_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email

    print_success "WordPress installation completed"

    print_step "Setting permalink structure..."
    sudo -u www-data "$WP_CLI_PATH" rewrite structure '/%postname%/' --path="$INSTALL_DIR"
    print_success "Permalinks configured"

    print_step "Updating WordPress settings..."
    sudo -u www-data "$WP_CLI_PATH" option update timezone_string 'UTC' --path="$INSTALL_DIR"
    sudo -u www-data "$WP_CLI_PATH" option update date_format 'Y-m-d' --path="$INSTALL_DIR"
    sudo -u www-data "$WP_CLI_PATH" option update time_format 'H:i' --path="$INSTALL_DIR"
    print_success "WordPress settings updated"
}

get_php_fpm_socket() {
    # Find the PHP-FPM socket path dynamically
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    PHP_FPM_SOCKET="/run/php/php${PHP_VERSION}-fpm.sock"

    if [[ ! -S "$PHP_FPM_SOCKET" ]]; then
        # Try to find any PHP-FPM socket
        PHP_FPM_SOCKET=$(find /run/php -name "php*-fpm.sock" 2>/dev/null | head -1)
    fi

    echo "$PHP_FPM_SOCKET"
}

configure_nginx() {
    print_header "Configuring Nginx"

    # Check if SSL certificate already exists - if so, skip nginx configuration
    # to preserve the existing HTTPS configuration created by certbot
    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $DOMAIN_NAME already exists"
        print_step "Skipping Nginx configuration to preserve existing HTTPS settings..."
        print_success "Using existing Nginx configuration"
        return
    fi

    PHP_FPM_SOCKET=$(get_php_fpm_socket)

    if [[ -z "$PHP_FPM_SOCKET" ]]; then
        print_error "PHP-FPM socket not found!"
        exit 1
    fi

    print_info "Using PHP-FPM socket: $PHP_FPM_SOCKET"

    print_step "Creating Nginx configuration..."

    tee /etc/nginx/sites-available/$DOMAIN_NAME > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    root $INSTALL_DIR;
    index index.php index.html index.htm;

    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP handling
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 300;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
    }

    # Deny access to wp-config.php
    location ~* wp-config\.php {
        deny all;
    }

    # Deny access to xmlrpc.php (prevent brute force attacks)
    location = /xmlrpc.php {
        deny all;
    }

    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Deny access to sensitive files
    location ~* /(wp-content/uploads/).*\.php\$ {
        deny all;
    }

    client_max_body_size 64M;
}
EOF

    print_success "Nginx configuration created"

    print_step "Enabling site..."
    ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
    print_success "Site enabled"

    print_step "Testing Nginx configuration..."
    if nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi

    print_step "Restarting Nginx..."
    systemctl restart nginx
    print_success "Nginx restarted"

    # Ensure PHP-FPM is running
    print_step "Restarting PHP-FPM..."
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    systemctl restart "php${PHP_VERSION}-fpm"
    print_success "PHP-FPM restarted"
}

setup_ssl_certificate() {
    print_header "Setting Up SSL Certificate"

    # Check if SSL certificate already exists
    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $DOMAIN_NAME already exists"
        print_step "Skipping certificate creation..."
        print_success "Using existing SSL certificate"

        # Make sure certbot timer is enabled for renewals
        print_step "Ensuring automatic renewal is enabled..."
        systemctl enable certbot.timer > /dev/null 2>&1
        systemctl start certbot.timer
        print_success "Automatic certificate renewal enabled"
        return
    fi

    print_info "Obtaining SSL certificate from Let's Encrypt..."
    print_info "Make sure DNS is properly configured and pointing to this server."

    print_step "Running Certbot..."

    # Run certbot with automatic configuration
    if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        print_success "SSL certificate obtained and configured"

        print_step "Setting up automatic renewal..."
        systemctl enable certbot.timer > /dev/null 2>&1
        systemctl start certbot.timer
        print_success "Automatic certificate renewal enabled"
    else
        print_warning "SSL certificate setup failed. You can run it manually later:"
        print_info "certbot --nginx -d $DOMAIN_NAME"
    fi
}

set_permissions() {
    print_header "Setting File Permissions"

    print_step "Setting ownership to www-data..."
    chown -R www-data:www-data "$INSTALL_DIR"
    print_success "Ownership set"

    print_step "Setting directory permissions (755)..."
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    print_success "Directory permissions set"

    print_step "Setting file permissions (644)..."
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
    print_success "File permissions set"

    print_step "Securing wp-config.php..."
    chmod 640 "$INSTALL_DIR/wp-config.php"
    print_success "wp-config.php secured"

    print_step "Adding $CURRENT_USER to www-data group..."
    usermod -aG www-data "$CURRENT_USER"
    print_success "User added to www-data group"
}

show_completion_message() {
    echo ""
    echo -e "${GREEN}+------------------------------------------------------------------------------+${NC}"
    echo -e "${GREEN}|${NC}                                                                              ${GREEN}|${NC}"
    echo -e "${GREEN}|${NC}   ${BOLD}${WHITE}[OK] Installation Completed Successfully!${NC}                                ${GREEN}|${NC}"
    echo -e "${GREEN}|${NC}                                                                              ${GREEN}|${NC}"
    echo -e "${GREEN}+------------------------------------------------------------------------------+${NC}"
    echo ""

    print_header "Installation Summary"

    echo -e "${WHITE}WordPress Site:${NC}"
    echo -e "  ${CYAN}*${NC} Site URL:          ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}*${NC} Admin URL:         ${BOLD}https://$DOMAIN_NAME/wp-admin${NC}"
    echo -e "  ${CYAN}*${NC} Install path:      ${BOLD}$INSTALL_DIR${NC}"
    echo ""

    echo -e "${WHITE}WordPress Admin Credentials:${NC}"
    echo -e "  ${CYAN}*${NC} Username:          ${BOLD}$WP_ADMIN_USER${NC}"
    echo -e "  ${CYAN}*${NC} Password:          ${BOLD}$WP_ADMIN_PASSWORD${NC}"
    echo -e "  ${CYAN}*${NC} Email:             ${BOLD}$WP_ADMIN_EMAIL${NC}"
    echo ""

    echo -e "${WHITE}Database Credentials:${NC}"
    echo -e "  ${CYAN}*${NC} Database name:     ${BOLD}$DB_NAME${NC}"
    echo -e "  ${CYAN}*${NC} Database user:     ${BOLD}$DB_USER${NC}"
    echo -e "  ${CYAN}*${NC} Database password: ${BOLD}$DB_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}*${NC} MySQL status:      ${BOLD}sudo systemctl status mysql${NC}"
    echo -e "  ${CYAN}*${NC} Nginx status:      ${BOLD}sudo systemctl status nginx${NC}"
    echo -e "  ${CYAN}*${NC} PHP-FPM status:    ${BOLD}sudo systemctl status php*-fpm${NC}"
    echo -e "  ${CYAN}*${NC} Restart MySQL:     ${BOLD}sudo systemctl restart mysql${NC}"
    echo -e "  ${CYAN}*${NC} Restart Nginx:     ${BOLD}sudo systemctl restart nginx${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}*${NC} Credentials are stored in: ${BOLD}$WP_CREDENTIALS_FILE${NC}"
    echo -e "  ${CYAN}*${NC} Please save the passwords in a secure location"
    echo -e "  ${CYAN}*${NC} Consider changing the default passwords after first login"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME/wp-admin${NC} to log in"
    echo -e "  ${CYAN}2.${NC} Configure your WordPress site settings"
    echo -e "  ${CYAN}3.${NC} Install themes and plugins as needed"
    echo -e "  ${CYAN}4.${NC} Create your first post!"
    echo ""

    print_success "Thank you for using WordPress installer!"
    echo ""
}

#-------------------------------------------------------------------------------
# Main execution
#-------------------------------------------------------------------------------

main() {
    # Parse command line arguments first (before any output)
    parse_arguments "$@"

    # Pre-flight checks
    check_root
    check_ubuntu

    # Show welcome banner
    show_banner

    # Setup installer user and switch context
    setup_installer_user

    echo ""
    print_info "Starting installation. This may take several minutes..."
    print_info "Domain: $DOMAIN_NAME"
    print_info "Site Title: $SITE_TITLE"
    print_info "User: $CURRENT_USER"
    echo ""

    # Execute installation steps
    install_dependencies
    configure_mysql
    download_wordpress
    configure_wordpress
    install_wp_cli
    set_permissions
    configure_nginx
    setup_ssl_certificate
    setup_wordpress_site

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
