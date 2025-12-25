#!/bin/bash

#===============================================================================
#
#   MySQL + phpMyAdmin - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - MySQL Server
#   - phpMyAdmin with Nginx
#   - SSL certificate via Let's Encrypt
#
#   Creates secure database access through phpMyAdmin web interface.
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
APP_NAME="phpmyadmin"
INSTALLER_USER="installer_user"
PHPMYADMIN_VERSION="5.2.1"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name>"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for phpMyAdmin (e.g., db.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 db.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., db.example.com)"
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

generate_blowfish_secret() {
    # Generate a 32-character blowfish secret for phpMyAdmin
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
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
    INSTALL_DIR="$HOME_DIR/$APP_NAME"

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
    echo -e "${CYAN}   |${NC}   ${BOLD}${WHITE}MySQL + phpMyAdmin${NC}                                                   ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                       ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${WHITE}This script will install and configure:${NC}                              ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} MySQL Server                                                       ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} phpMyAdmin web interface                                           ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Nginx as web server                                                ${CYAN}|${NC}"
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

    print_header "Domain Configuration"
    print_success "Domain configured: $DOMAIN_NAME"
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
    apt-get install -y -qq php-fpm php-mysql php-mbstring php-zip php-gd php-json php-curl php-xml > /dev/null 2>&1
    print_success "PHP and extensions installed"

    print_step "Installing MySQL Server..."
    apt-get install -y -qq mysql-server > /dev/null 2>&1
    print_success "MySQL Server installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_step "Installing additional utilities..."
    apt-get install -y -qq wget unzip > /dev/null 2>&1
    print_success "Additional utilities installed"

    print_success "All system dependencies installed successfully!"
}

configure_mysql() {
    print_header "Configuring MySQL Database"

    print_step "Starting MySQL service..."
    systemctl start mysql
    systemctl enable mysql > /dev/null 2>&1
    print_success "MySQL service started and enabled"

    # Check if root password is already set by checking credentials file
    MYSQL_CREDENTIALS_FILE="$HOME_DIR/.mysql_credentials"

    if [[ -f "$MYSQL_CREDENTIALS_FILE" ]]; then
        print_info "MySQL credentials file already exists"
        print_step "Reading existing credentials..."
        MYSQL_ROOT_PASSWORD=$(grep "^MYSQL_ROOT_PASSWORD=" "$MYSQL_CREDENTIALS_FILE" | cut -d'=' -f2)
        PMA_USER=$(grep "^PMA_USER=" "$MYSQL_CREDENTIALS_FILE" | cut -d'=' -f2)
        PMA_PASSWORD=$(grep "^PMA_PASSWORD=" "$MYSQL_CREDENTIALS_FILE" | cut -d'=' -f2)
        print_success "Using existing MySQL configuration"
    else
        print_step "Generating secure passwords..."
        MYSQL_ROOT_PASSWORD=$(generate_password)
        PMA_USER="pma_admin"
        PMA_PASSWORD=$(generate_password)

        print_step "Setting MySQL root password..."
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '$MYSQL_ROOT_PASSWORD';"
        print_success "MySQL root password set"

        print_step "Creating phpMyAdmin admin user..."
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$PMA_USER'@'localhost' IDENTIFIED BY '$PMA_PASSWORD';"
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO '$PMA_USER'@'localhost' WITH GRANT OPTION;"
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
        print_success "phpMyAdmin admin user created: $PMA_USER"

        print_step "Saving MySQL credentials..."
        cat > "$MYSQL_CREDENTIALS_FILE" << EOF
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
PMA_USER=$PMA_USER
PMA_PASSWORD=$PMA_PASSWORD
EOF
        chown "$CURRENT_USER":"$CURRENT_USER" "$MYSQL_CREDENTIALS_FILE"
        chmod 600 "$MYSQL_CREDENTIALS_FILE"
        print_success "Credentials saved to $MYSQL_CREDENTIALS_FILE"
    fi

    # Export for later use
    export MYSQL_ROOT_PASSWORD PMA_USER PMA_PASSWORD
}

download_phpmyadmin() {
    print_header "Installing phpMyAdmin"

    PHPMYADMIN_DIR="/usr/share/phpmyadmin"

    if [[ -d "$PHPMYADMIN_DIR" ]]; then
        print_info "phpMyAdmin already installed at $PHPMYADMIN_DIR"
        print_step "Checking version..."

        # Try to get current version
        if [[ -f "$PHPMYADMIN_DIR/README" ]]; then
            CURRENT_PMA_VERSION=$(grep -oP 'Version \K[0-9.]+' "$PHPMYADMIN_DIR/README" 2>/dev/null || echo "unknown")
            if [[ "$CURRENT_PMA_VERSION" == "$PHPMYADMIN_VERSION" ]]; then
                print_success "phpMyAdmin $PHPMYADMIN_VERSION is already installed"
                return
            else
                print_info "Updating phpMyAdmin from $CURRENT_PMA_VERSION to $PHPMYADMIN_VERSION"
            fi
        fi
    fi

    DOWNLOAD_URL="https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip"
    TEMP_ZIP="/tmp/phpmyadmin-${PHPMYADMIN_VERSION}.zip"

    print_step "Downloading phpMyAdmin $PHPMYADMIN_VERSION..."
    wget -q -O "$TEMP_ZIP" "$DOWNLOAD_URL"
    print_success "Download completed"

    print_step "Extracting phpMyAdmin..."
    unzip -o -q "$TEMP_ZIP" -d /tmp/
    print_success "Extraction completed"

    print_step "Installing phpMyAdmin to $PHPMYADMIN_DIR..."
    rm -rf "$PHPMYADMIN_DIR"
    mv "/tmp/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages" "$PHPMYADMIN_DIR"
    print_success "phpMyAdmin installed"

    # Create tmp directory for phpMyAdmin
    print_step "Creating temporary directory for phpMyAdmin..."
    mkdir -p "$PHPMYADMIN_DIR/tmp"
    chown -R www-data:www-data "$PHPMYADMIN_DIR/tmp"
    chmod 755 "$PHPMYADMIN_DIR/tmp"
    print_success "Temporary directory created"

    # Clean up
    rm -f "$TEMP_ZIP"

    print_info "phpMyAdmin installed at: $PHPMYADMIN_DIR"
}

configure_phpmyadmin() {
    print_header "Configuring phpMyAdmin"

    PHPMYADMIN_DIR="/usr/share/phpmyadmin"
    CONFIG_FILE="$PHPMYADMIN_DIR/config.inc.php"

    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "phpMyAdmin configuration already exists"
        print_step "Skipping configuration to preserve existing settings..."
        print_success "Using existing phpMyAdmin configuration"
        return
    fi

    print_step "Generating blowfish secret..."
    BLOWFISH_SECRET=$(generate_blowfish_secret)
    print_success "Blowfish secret generated"

    print_step "Creating phpMyAdmin configuration..."

    cat > "$CONFIG_FILE" << 'EOFCONFIG'
<?php
/**
 * phpMyAdmin configuration file
 */

declare(strict_types=1);

// Blowfish secret for cookie encryption
$cfg['blowfish_secret'] = 'BLOWFISH_SECRET_PLACEHOLDER';

// Server configuration
$i = 0;

// First server
$i++;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;

// Directories
$cfg['UploadDir'] = '';
$cfg['SaveDir'] = '';

// Temporary directory
$cfg['TempDir'] = '/usr/share/phpmyadmin/tmp';

// Security settings
$cfg['CheckConfigurationPermissions'] = false;

// Theme
$cfg['ThemeDefault'] = 'pmahomme';
EOFCONFIG

    # Replace placeholder with actual blowfish secret
    sed -i "s/BLOWFISH_SECRET_PLACEHOLDER/$BLOWFISH_SECRET/" "$CONFIG_FILE"

    chown www-data:www-data "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"

    print_success "phpMyAdmin configuration created"
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

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCKET;
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

add_user_to_www_data() {
    print_header "Configuring User Permissions"

    print_step "Adding $CURRENT_USER to www-data group..."
    usermod -aG www-data "$CURRENT_USER"
    print_success "User added to www-data group"

    print_step "Setting directory permissions..."
    chown -R www-data:www-data /usr/share/phpmyadmin
    chmod -R 755 /usr/share/phpmyadmin
    print_success "Directory permissions configured"
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

    echo -e "${WHITE}Application Details:${NC}"
    echo -e "  ${CYAN}*${NC} phpMyAdmin URL:    ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}*${NC} Install path:      ${BOLD}/usr/share/phpmyadmin${NC}"
    echo ""

    echo -e "${WHITE}MySQL Credentials:${NC}"
    echo -e "  ${CYAN}*${NC} Root password:     ${BOLD}$MYSQL_ROOT_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}phpMyAdmin Login:${NC}"
    echo -e "  ${CYAN}*${NC} Username:          ${BOLD}$PMA_USER${NC}"
    echo -e "  ${CYAN}*${NC} Password:          ${BOLD}$PMA_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}*${NC} MySQL status:      ${BOLD}sudo systemctl status mysql${NC}"
    echo -e "  ${CYAN}*${NC} Nginx status:      ${BOLD}sudo systemctl status nginx${NC}"
    echo -e "  ${CYAN}*${NC} Restart MySQL:     ${BOLD}sudo systemctl restart mysql${NC}"
    echo -e "  ${CYAN}*${NC} Restart Nginx:     ${BOLD}sudo systemctl restart nginx${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}*${NC} Credentials are stored in: ${BOLD}$HOME_DIR/.mysql_credentials${NC}"
    echo -e "  ${CYAN}*${NC} Please save the passwords in a secure location"
    echo -e "  ${CYAN}*${NC} Consider changing the default passwords after first login"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to access phpMyAdmin"
    echo -e "  ${CYAN}2.${NC} Log in with the credentials shown above"
    echo -e "  ${CYAN}3.${NC} Create databases and users as needed"
    echo ""

    print_success "Thank you for using MySQL + phpMyAdmin installer!"
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
    print_info "User: $CURRENT_USER"
    echo ""

    # Execute installation steps
    install_dependencies
    configure_mysql
    download_phpmyadmin
    configure_phpmyadmin
    add_user_to_www_data
    configure_nginx
    setup_ssl_certificate

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
