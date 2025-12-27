#!/bin/bash

#===============================================================================
#
#   3x-ui - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Git, Curl, Wget, Tar, Nginx, Certbot
#   - Downloads and installs 3x-ui panel from GitHub (includes bundled Xray)
#   - Creates systemd services for automatic startup
#   - Configures Nginx as reverse proxy
#   - Obtains SSL certificate via Let's Encrypt
#
#   Note: 3x-ui includes its own bundled Xray binary. No external Xray service
#   is needed, which prevents port conflicts with nginx.
#
#   3x-ui Repository: https://github.com/MHSanaei/3x-ui
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
APP_NAME="3x-ui"
SERVICE_NAME="x-ui"
INSTALLER_USER="installer_user"
INSTALL_DIR="/usr/local/x-ui"
APP_PORT=""  # Will be set dynamically

# These will be set during installation
CURRENT_USER=""
HOME_DIR=""
PANEL_USERNAME=""
PANEL_PASSWORD=""
WEB_BASE_PATH=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name> [panel_port]"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for the panel (e.g., panel.example.com)"
    echo "  panel_port     (Optional) Panel port number (default: random 1024-62000)"
    echo ""
    echo "Example:"
    echo "  $0 panel.example.com"
    echo "  $0 panel.example.com 2053"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., panel.example.com)"
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

generate_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

generate_password() {
    # Generate a secure random password
    openssl rand -base64 24 | tr -d '/+=' | head -c 16
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

    print_success "Installer user configured: $INSTALLER_USER"
    print_info "Home directory: $HOME_DIR"
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for Ubuntu. Proceed with caution on other distributions."
    fi
}

get_architecture() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *)
            print_error "Unsupported CPU architecture: $(uname -m)"
            exit 1
            ;;
    esac
}

get_latest_version() {
    # Get the latest version from GitHub API
    # Uses timeouts to prevent hanging on network issues
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

#-------------------------------------------------------------------------------
# Main installation functions
#-------------------------------------------------------------------------------

show_banner() {
    clear
    echo ""
    echo -e "${CYAN}   ╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}3x-ui Panel${NC}                                                             ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} 3x-ui panel with bundled Xray for VPN/proxy                           ${CYAN}║${NC}"
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

    # Handle optional port argument
    if [[ -n "$2" ]]; then
        if [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -ge 1024 ]] && [[ "$2" -le 65535 ]]; then
            APP_PORT="$2"
        else
            print_error "Invalid port number: $2 (must be 1024-65535)"
            exit 1
        fi
    else
        # Generate random port between 1024 and 62000
        APP_PORT=$(shuf -i 1024-62000 -n 1)
    fi

    print_header "Configuration"
    print_success "Domain configured: $DOMAIN_NAME"
    print_success "Panel port: $APP_PORT"
}

install_dependencies() {
    print_header "Installing System Dependencies"

    # Set non-interactive mode for all package installations
    export DEBIAN_FRONTEND=noninteractive

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing required packages..."
    apt-get install -y -qq wget curl tar tzdata > /dev/null 2>&1
    print_success "Core utilities installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_success "All system dependencies installed successfully!"
}

check_xray_bundled() {
    # Note: 3x-ui bundles its own Xray binary in /usr/local/x-ui/bin/
    # We don't need to install the external Xray service from XTLS/Xray-install
    # as it would conflict with nginx and other services on ports 80/443.
    # The 3x-ui panel manages its own bundled Xray internally.

    print_header "Checking Xray Service"

    # Stop and disable the external xray service if it exists (to prevent port conflicts)
    if systemctl is-active --quiet xray 2>/dev/null; then
        print_step "Stopping external xray service to prevent port conflicts..."
        systemctl stop xray 2>/dev/null || true
        print_success "External xray service stopped"
    fi

    if systemctl is-enabled --quiet xray 2>/dev/null; then
        print_step "Disabling external xray service..."
        systemctl disable xray 2>/dev/null || true
        print_success "External xray service disabled"
    fi

    print_info "3x-ui includes a bundled Xray binary"
    print_info "The panel will manage Xray internally - no external service needed"
    print_success "Xray check completed!"
}

download_and_install_xui() {
    print_header "Installing 3x-ui Panel"

    local ARCH
    ARCH=$(get_architecture)
    print_info "Detected architecture: $ARCH"

    # Get the latest version
    print_step "Fetching latest 3x-ui version..."
    local TAG_VERSION
    TAG_VERSION=$(get_latest_version)

    if [[ -z "$TAG_VERSION" ]]; then
        print_error "Failed to fetch 3x-ui version from GitHub API"
        print_info "This may be due to network issues or GitHub API rate limiting (60 requests/hour)"
        print_info "Please try again later or check your network connection"
        exit 1
    fi

    print_success "Latest version: $TAG_VERSION"

    # Check if x-ui is already installed and get current version
    if [[ -f "$INSTALL_DIR/x-ui" ]]; then
        local CURRENT_VERSION
        CURRENT_VERSION=$("$INSTALL_DIR/x-ui" version 2>/dev/null || echo "")
        if [[ "$CURRENT_VERSION" == "$TAG_VERSION" ]]; then
            print_info "3x-ui $TAG_VERSION is already installed"
            print_step "Skipping download..."
            return
        else
            print_info "Updating 3x-ui from $CURRENT_VERSION to $TAG_VERSION"
            # Stop service before updating
            if systemctl is-active --quiet x-ui; then
                print_step "Stopping x-ui service..."
                systemctl stop x-ui
            fi
        fi
    fi

    # Download 3x-ui
    local DOWNLOAD_URL="https://github.com/MHSanaei/3x-ui/releases/download/${TAG_VERSION}/x-ui-linux-${ARCH}.tar.gz"
    local TEMP_FILE="/tmp/x-ui-linux-${ARCH}.tar.gz"

    print_step "Downloading 3x-ui $TAG_VERSION..."
    if ! wget --inet4-only -q -O "$TEMP_FILE" "$DOWNLOAD_URL"; then
        print_error "Failed to download 3x-ui. Please check network connectivity."
        exit 1
    fi
    print_success "Download completed"

    # Download x-ui management script
    print_step "Downloading x-ui management script..."
    if ! wget --inet4-only -q -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh; then
        print_error "Failed to download x-ui.sh"
        exit 1
    fi
    chmod +x /usr/bin/x-ui
    print_success "Management script installed"

    # Remove old installation if exists (preserve database)
    if [[ -d "$INSTALL_DIR" ]]; then
        print_step "Backing up existing database..."
        if [[ -f "$INSTALL_DIR/db/x-ui.db" ]]; then
            cp "$INSTALL_DIR/db/x-ui.db" /tmp/x-ui.db.backup
        fi
        print_step "Removing old installation..."
        rm -rf "$INSTALL_DIR"
    fi

    # Extract new version
    print_step "Extracting 3x-ui..."
    cd /usr/local/
    tar zxvf "$TEMP_FILE" > /dev/null 2>&1
    rm -f "$TEMP_FILE"
    print_success "3x-ui extracted"

    # Restore database if backup exists
    if [[ -f /tmp/x-ui.db.backup ]]; then
        print_step "Restoring database..."
        mkdir -p "$INSTALL_DIR/db"
        mv /tmp/x-ui.db.backup "$INSTALL_DIR/db/x-ui.db"
        print_success "Database restored"
    fi

    # Set permissions
    cd "$INSTALL_DIR"
    chmod +x x-ui

    # Handle ARM architectures
    if [[ "$ARCH" == "armv5" || "$ARCH" == "armv6" || "$ARCH" == "armv7" ]]; then
        mv bin/xray-linux-${ARCH} bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x bin/xray-linux-${ARCH} 2>/dev/null || true

    print_success "3x-ui $TAG_VERSION installed successfully"
}

configure_xui_settings() {
    print_header "Configuring 3x-ui Panel Settings"

    # Check if this is a fresh installation or existing one
    local HAS_DEFAULT_CREDENTIALS
    HAS_DEFAULT_CREDENTIALS=$("$INSTALL_DIR/x-ui" setting -show true 2>/dev/null | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}' || echo "true")

    local EXISTING_WEB_BASE_PATH
    EXISTING_WEB_BASE_PATH=$("$INSTALL_DIR/x-ui" setting -show true 2>/dev/null | grep -Eo 'webBasePath: .+' | awk '{print $2}' || echo "")

    # Check if credentials file already exists (for idempotency)
    local CREDS_FILE="$HOME_DIR/.3x-ui-credentials"

    if [[ -f "$CREDS_FILE" ]]; then
        print_info "Credentials file already exists"
        print_step "Loading existing credentials..."
        source "$CREDS_FILE"
        print_success "Using existing credentials"
    elif [[ "$HAS_DEFAULT_CREDENTIALS" == "true" ]] || [[ ${#EXISTING_WEB_BASE_PATH} -lt 4 ]]; then
        # Generate new credentials for fresh installation
        PANEL_USERNAME=$(generate_random_string 10)
        PANEL_PASSWORD=$(generate_password)
        WEB_BASE_PATH=$(generate_random_string 18)

        print_step "Configuring panel with secure credentials..."
        "$INSTALL_DIR/x-ui" setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" -port "$APP_PORT" -webBasePath "$WEB_BASE_PATH" > /dev/null 2>&1
        print_success "Panel credentials configured"

        # Save credentials to file for future reference
        print_step "Saving credentials to file..."
        cat > "$CREDS_FILE" << EOF
PANEL_USERNAME="$PANEL_USERNAME"
PANEL_PASSWORD="$PANEL_PASSWORD"
WEB_BASE_PATH="$WEB_BASE_PATH"
APP_PORT="$APP_PORT"
EOF
        chown "$CURRENT_USER":"$CURRENT_USER" "$CREDS_FILE"
        chmod 600 "$CREDS_FILE"
        print_success "Credentials saved to $CREDS_FILE"
    else
        print_info "Panel already configured with custom credentials"
        print_step "Preserving existing configuration..."

        # Read existing settings
        PANEL_USERNAME=$("$INSTALL_DIR/x-ui" setting -show true 2>/dev/null | grep -Eo 'username: .+' | awk '{print $2}' || echo "(existing)")
        PANEL_PASSWORD="(stored in panel database)"
        WEB_BASE_PATH="$EXISTING_WEB_BASE_PATH"
        APP_PORT=$("$INSTALL_DIR/x-ui" setting -show true 2>/dev/null | grep -Eo 'port: .+' | awk '{print $2}' || echo "$APP_PORT")

        print_success "Using existing panel configuration"
    fi

    # Run database migration
    print_step "Running database migration..."
    "$INSTALL_DIR/x-ui" migrate > /dev/null 2>&1 || true
    print_success "Database migration completed"
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    # Check if service file already exists from x-ui package
    if [[ -f "$INSTALL_DIR/x-ui.service" ]]; then
        print_step "Using x-ui bundled service file..."
        cp -f "$INSTALL_DIR/x-ui.service" /etc/systemd/system/
    else
        print_step "Creating service file..."

        tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=x-ui Service
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/x-ui run
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    fi

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

    # Wait for service to start
    sleep 2

    # Verify service is running
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_success "x-ui service is running"
    else
        print_warning "x-ui service may not have started correctly. Check: systemctl status x-ui"
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

    location /${WEB_BASE_PATH} {
        proxy_pass http://127.0.0.1:$APP_PORT/${WEB_BASE_PATH};
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

    # Handle WebSocket connections for xray
    location /ws {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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

    echo -e "${WHITE}Panel Access:${NC}"
    echo -e "  ${CYAN}•${NC} URL:           ${BOLD}https://$DOMAIN_NAME/${WEB_BASE_PATH}${NC}"
    echo -e "  ${CYAN}•${NC} Username:      ${BOLD}$PANEL_USERNAME${NC}"
    echo -e "  ${CYAN}•${NC} Password:      ${BOLD}$PANEL_PASSWORD${NC}"
    echo -e "  ${CYAN}•${NC} Port:          ${BOLD}$APP_PORT${NC}"
    echo -e "  ${CYAN}•${NC} WebBasePath:   ${BOLD}$WEB_BASE_PATH${NC}"
    echo ""

    echo -e "${WHITE}Installation Paths:${NC}"
    echo -e "  ${CYAN}•${NC} Install dir:   ${BOLD}$INSTALL_DIR${NC}"
    echo -e "  ${CYAN}•${NC} Database:      ${BOLD}$INSTALL_DIR/db/x-ui.db${NC}"
    echo -e "  ${CYAN}•${NC} Credentials:   ${BOLD}$HOME_DIR/.3x-ui-credentials${NC}"
    echo ""

    echo -e "${WHITE}3x-ui Panel Management (includes bundled Xray):${NC}"
    echo -e "  ${CYAN}•${NC} Check status:  ${BOLD}sudo systemctl status x-ui${NC}"
    echo -e "  ${CYAN}•${NC} Restart:       ${BOLD}sudo systemctl restart x-ui${NC}"
    echo -e "  ${CYAN}•${NC} View logs:     ${BOLD}sudo journalctl -u x-ui${NC}"
    echo -e "  ${CYAN}•${NC} Panel CLI:     ${BOLD}x-ui${NC}"
    echo ""

    echo -e "${WHITE}x-ui Control Menu:${NC}"
    echo -e "  ${CYAN}•${NC} x-ui              - Admin Management Script"
    echo -e "  ${CYAN}•${NC} x-ui start        - Start"
    echo -e "  ${CYAN}•${NC} x-ui stop         - Stop"
    echo -e "  ${CYAN}•${NC} x-ui restart      - Restart"
    echo -e "  ${CYAN}•${NC} x-ui status       - Current Status"
    echo -e "  ${CYAN}•${NC} x-ui settings     - Current Settings"
    echo -e "  ${CYAN}•${NC} x-ui log          - Check logs"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} Credentials are stored in: ${BOLD}$HOME_DIR/.3x-ui-credentials${NC}"
    echo -e "  ${CYAN}•${NC} Please save the panel password in a secure location"
    echo -e "  ${CYAN}•${NC} For personal use only - do not use for illegal purposes"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME/${WEB_BASE_PATH}${NC} to access the panel"
    echo -e "  ${CYAN}2.${NC} Log in with the credentials above"
    echo -e "  ${CYAN}3.${NC} Configure your VPN/proxy settings"
    echo ""

    print_success "Thank you for using 3x-ui Installation Script!"
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
    print_info "Port: $APP_PORT"
    print_info "User: $CURRENT_USER"
    echo ""

    # Execute installation steps
    install_dependencies
    check_xray_bundled
    download_and_install_xui
    configure_xui_settings
    add_user_to_www_data
    create_systemd_service
    configure_nginx
    setup_ssl_certificate

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
