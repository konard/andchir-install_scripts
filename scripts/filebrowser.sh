#!/bin/bash

#===============================================================================
#
#   FileBrowser Quantum - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Git, Curl, Nginx, Certbot
#   - Downloads and installs FileBrowser Quantum
#   - Creates systemd services for automatic startup
#   - Configures Nginx as reverse proxy
#   - Obtains SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/gtsteffaniak/filebrowser
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
APP_NAME="filebrowser"
SERVICE_NAME="filebrowser"
INSTALLER_USER="installer_user"
APP_PORT="8080"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""
DATA_DIR=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name>"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for the application (e.g., files.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 files.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., files.example.com)"
        exit 1
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}➜${NC} ${WHITE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✔${NC} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} ${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}✖${NC} ${RED}$1${NC}"
}

print_info() {
    echo -e "${MAGENTA}ℹ${NC} ${WHITE}$1${NC}"
}

generate_password() {
    # Generate a secure random password
    openssl rand -base64 24 | tr -d '/+=' | head -c 20
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
    DATA_DIR="$INSTALL_DIR/data"

    print_success "Installer user configured: $INSTALLER_USER"
    print_info "Home directory: $HOME_DIR"
    print_info "Installation directory: $INSTALL_DIR"
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for Ubuntu. Proceed with caution on other distributions."
    fi
}

get_latest_filebrowser_version() {
    # Get the latest version from GitHub API
    curl -sL "https://api.github.com/repos/gtsteffaniak/filebrowser/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}

#-------------------------------------------------------------------------------
# Main installation functions
#-------------------------------------------------------------------------------

show_banner() {
    clear
    echo ""
    echo -e "${CYAN}   ╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}FileBrowser Quantum${NC}                                                     ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} FileBrowser Quantum file manager                                     ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Nginx as reverse proxy                                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Systemd services for auto-start                                       ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} SSL certificate via Let's Encrypt                                     ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
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

    print_step "Installing required packages..."
    apt-get install -y -qq curl wget > /dev/null 2>&1
    print_success "Core utilities installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_success "All system dependencies installed successfully!"
}

download_filebrowser() {
    print_header "Downloading FileBrowser Quantum"

    # Create installation directory
    print_step "Creating installation directory..."
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR'"
    su - "$CURRENT_USER" -c "mkdir -p '$DATA_DIR'"
    print_success "Installation directory created"

    # Get the latest version
    print_step "Fetching latest FileBrowser version..."
    FB_VERSION=$(get_latest_filebrowser_version)

    if [[ -z "$FB_VERSION" ]]; then
        print_warning "Could not determine latest version, using fallback version v1.1.0-stable"
        FB_VERSION="v1.1.0-stable"
    fi

    print_success "Latest version: $FB_VERSION"

    # Check if FileBrowser is already installed
    if [[ -f "$INSTALL_DIR/filebrowser" ]]; then
        CURRENT_VERSION=$("$INSTALL_DIR/filebrowser" --version 2>/dev/null | head -1 || echo "")
        if [[ "$CURRENT_VERSION" == *"$FB_VERSION"* ]]; then
            print_info "FileBrowser $FB_VERSION is already installed"
            print_step "Skipping download..."
            print_success "Using existing FileBrowser installation"
            return
        else
            print_info "Updating FileBrowser from $CURRENT_VERSION to $FB_VERSION"
        fi
    fi

    # Determine architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            FB_ARCH="amd64"
            ;;
        aarch64)
            FB_ARCH="arm64"
            ;;
        armv7l)
            FB_ARCH="armv7"
            ;;
        armv6l)
            FB_ARCH="armv6"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    DOWNLOAD_URL="https://github.com/gtsteffaniak/filebrowser/releases/download/${FB_VERSION}/linux-${FB_ARCH}-filebrowser"
    TEMP_FILE="/tmp/filebrowser_${FB_VERSION}"

    print_step "Downloading FileBrowser $FB_VERSION for linux-${FB_ARCH}..."
    wget -q -O "$TEMP_FILE" "$DOWNLOAD_URL"
    print_success "Download completed"

    print_step "Installing FileBrowser..."
    mv "$TEMP_FILE" "$INSTALL_DIR/filebrowser"
    print_success "FileBrowser installed"

    print_step "Setting executable permissions..."
    chmod +x "$INSTALL_DIR/filebrowser"
    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/filebrowser"
    print_success "Permissions set"

    print_info "FileBrowser installed at: $INSTALL_DIR/filebrowser"
}

create_config_file() {
    print_header "Creating Configuration"

    # Check if config file already exists
    if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
        print_info "config.yaml already exists at $INSTALL_DIR/config.yaml"
        print_step "Skipping config file creation to preserve existing configuration..."
        print_success "Using existing config.yaml file"

        # Read existing credentials for summary
        if [[ -f "$INSTALL_DIR/.env" ]]; then
            ADMIN_USERNAME=$(grep "^ADMIN_USERNAME=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
            ADMIN_PASSWORD="(stored in .env file)"
        fi
        export ADMIN_USERNAME ADMIN_PASSWORD
        return
    fi

    ADMIN_USERNAME="admin"
    ADMIN_PASSWORD=$(generate_password)

    print_step "Creating config.yaml file..."

    # Create config.yaml file
    cat > "$INSTALL_DIR/config.yaml" << EOF
server:
  port: $APP_PORT
  baseURL: "/"
  externalUrl: "https://$DOMAIN_NAME"
  database: "$DATA_DIR/database.db"
  cacheDir: "$DATA_DIR/cache"
  logging:
    - levels: "info|warning|error"
  sources:
    - path: "$DATA_DIR/files"
      name: "Files"
      config:
        defaultUserScope: "/"
        createUserDir: true
auth:
  adminUsername: "$ADMIN_USERNAME"
  adminPassword: "$ADMIN_PASSWORD"
  tokenExpirationHours: 24
  methods:
    password:
      enabled: true
      minLength: 8
userDefaults:
  darkMode: true
  stickySidebar: true
  permissions:
    admin: false
    modify: true
    share: true
    delete: true
    create: true
    download: true
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/config.yaml"
    chmod 600 "$INSTALL_DIR/config.yaml"
    print_success "config.yaml file created with secure permissions"

    # Create .env file to store credentials for reference
    print_step "Creating .env file for credentials reference..."
    cat > "$INSTALL_DIR/.env" << EOF
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_PASSWORD=$ADMIN_PASSWORD
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    print_success ".env file created"

    # Create files directory
    print_step "Creating files storage directory..."
    su - "$CURRENT_USER" -c "mkdir -p '$DATA_DIR/files'"
    su - "$CURRENT_USER" -c "mkdir -p '$DATA_DIR/cache'"
    print_success "Storage directories created"

    # Save credentials for summary
    export ADMIN_USERNAME ADMIN_PASSWORD
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    print_step "Creating service file..."

    tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=FileBrowser Quantum File Manager
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/filebrowser -c $INSTALL_DIR/config.yaml
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service file created"

    print_step "Reloading systemd daemon..."
    systemctl daemon-reload
    print_success "Systemd daemon reloaded"

    print_step "Enabling service..."
    systemctl enable ${SERVICE_NAME}.service > /dev/null 2>&1
    print_success "Service enabled"

    # Check if service already exists and is active, then restart; otherwise start
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_step "Service already running, restarting..."
        systemctl restart ${SERVICE_NAME}.service
        print_success "Service restarted"
    else
        print_step "Starting service..."
        systemctl start ${SERVICE_NAME}.service
        print_success "Service started"
    fi
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

    print_step "Creating Nginx configuration..."

    tee /etc/nginx/sites-available/$DOMAIN_NAME > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;

    # Redirect HTTP to HTTPS (will be enabled after SSL setup)
    # return 301 https://\$server_name\$request_uri;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
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

    client_max_body_size 10G;
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

    print_step "Adding www-data to $INSTALLER_USER group..."
    usermod -aG "$INSTALLER_USER" www-data
    print_success "www-data added to $INSTALLER_USER group (allows nginx access to files)"

    print_step "Setting directory permissions..."
    chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    print_success "Directory permissions configured"
}

show_completion_message() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}   ${BOLD}${WHITE}✔ Installation Completed Successfully!${NC}                                   ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_header "Installation Summary"

    echo -e "${WHITE}Application Details:${NC}"
    echo -e "  ${CYAN}•${NC} Domain:        ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}•${NC} Install path:  ${BOLD}$INSTALL_DIR${NC}"
    echo -e "  ${CYAN}•${NC} Files path:    ${BOLD}$DATA_DIR/files${NC}"
    echo ""

    echo -e "${WHITE}Admin Credentials:${NC}"
    echo -e "  ${CYAN}•${NC} Username:      ${BOLD}$ADMIN_USERNAME${NC}"
    echo -e "  ${CYAN}•${NC} Password:      ${BOLD}$ADMIN_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}•${NC} Check status:  ${BOLD}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} Restart:       ${BOLD}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} View logs:     ${BOLD}sudo journalctl -u ${SERVICE_NAME}${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} Admin credentials are stored in: ${BOLD}$INSTALL_DIR/.env${NC}"
    echo -e "  ${CYAN}•${NC} Configuration file: ${BOLD}$INSTALL_DIR/config.yaml${NC}"
    echo -e "  ${CYAN}•${NC} Please save the admin password in a secure location"
    echo -e "  ${CYAN}•${NC} Files are stored in: ${BOLD}$DATA_DIR/files${NC}"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to access FileBrowser"
    echo -e "  ${CYAN}2.${NC} Log in with the admin credentials above"
    echo -e "  ${CYAN}3.${NC} Create additional users and configure access rules"
    echo -e "  ${CYAN}4.${NC} Check ${BOLD}https://github.com/gtsteffaniak/filebrowser${NC} for documentation"
    echo ""

    print_success "Thank you for using FileBrowser Quantum!"
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
    download_filebrowser
    create_config_file
    add_user_to_www_data
    create_systemd_service
    configure_nginx
    setup_ssl_certificate

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
