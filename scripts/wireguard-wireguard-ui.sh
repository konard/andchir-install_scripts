#!/bin/bash

#===============================================================================
#
#   WireGuard + WireGuard-UI - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - WireGuard VPN server
#   - WireGuard-UI web interface for management
#   - Nginx as reverse proxy for the web interface
#   - Systemd services for automatic startup
#   - SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/ngoduykhanh/wireguard-ui
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
APP_NAME="wireguard-ui"
SERVICE_NAME="wireguard-ui"
INSTALLER_USER="installer_user"
APP_PORT="5000"
WG_PORT="51820"
WG_INTERFACE="wg0"

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
    echo "  domain_name    The domain name for the WireGuard-UI (e.g., wg.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 wg.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., wg.example.com)"
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

generate_session_secret() {
    # Generate a secure session secret (32 bytes)
    openssl rand -hex 32
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

get_public_ip() {
    # Get the public IP address
    curl -s https://api.ipify.org || curl -s https://ifconfig.me || hostname -I | awk '{print $1}'
}

get_latest_wireguard_ui_version() {
    # Get the latest version from GitHub API
    curl -sL "https://api.github.com/repos/ngoduykhanh/wireguard-ui/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/'
}

#-------------------------------------------------------------------------------
# Main installation functions
#-------------------------------------------------------------------------------

show_banner() {
    clear
    echo ""
    echo -e "${CYAN}   ╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}WireGuard + WireGuard-UI${NC}                                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} WireGuard VPN server                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} WireGuard-UI web management interface                                 ${CYAN}║${NC}"
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
    apt-get install -y -qq curl wget tar > /dev/null 2>&1
    print_success "Core utilities installed"

    print_step "Installing WireGuard..."
    apt-get install -y -qq wireguard wireguard-tools > /dev/null 2>&1
    print_success "WireGuard installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_success "All system dependencies installed successfully!"
}

configure_ip_forwarding() {
    print_header "Configuring IP Forwarding"

    print_step "Enabling IPv4 forwarding..."
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        print_success "IPv4 forwarding enabled in sysctl.conf"
    else
        print_info "IPv4 forwarding already enabled"
    fi

    print_step "Enabling IPv6 forwarding..."
    if ! grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
        print_success "IPv6 forwarding enabled in sysctl.conf"
    else
        print_info "IPv6 forwarding already enabled"
    fi

    print_step "Applying sysctl settings..."
    sysctl -p > /dev/null 2>&1
    print_success "Sysctl settings applied"
}

download_wireguard_ui() {
    print_header "Downloading WireGuard-UI"

    # Create installation directory
    print_step "Creating installation directory..."
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR'"
    print_success "Installation directory created"

    # Get the latest version
    print_step "Fetching latest WireGuard-UI version..."
    WG_UI_VERSION=$(get_latest_wireguard_ui_version)

    if [[ -z "$WG_UI_VERSION" ]]; then
        print_warning "Could not determine latest version, using fallback version 0.6.2"
        WG_UI_VERSION="0.6.2"
    fi

    print_success "Latest version: $WG_UI_VERSION"

    # Check if WireGuard-UI is already installed
    if [[ -f "$INSTALL_DIR/wireguard-ui" ]]; then
        CURRENT_VERSION=$("$INSTALL_DIR/wireguard-ui" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "")
        if [[ "$CURRENT_VERSION" == "$WG_UI_VERSION" ]]; then
            print_info "WireGuard-UI v$WG_UI_VERSION is already installed"
            print_step "Skipping download..."
            print_success "Using existing WireGuard-UI installation"
            return
        else
            print_info "Updating WireGuard-UI from v$CURRENT_VERSION to v$WG_UI_VERSION"
        fi
    fi

    # Determine architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            WG_UI_ARCH="amd64"
            ;;
        aarch64)
            WG_UI_ARCH="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    DOWNLOAD_URL="https://github.com/ngoduykhanh/wireguard-ui/releases/download/v${WG_UI_VERSION}/wireguard-ui-v${WG_UI_VERSION}-linux-${WG_UI_ARCH}.tar.gz"
    TEMP_TAR="/tmp/wireguard-ui_${WG_UI_VERSION}.tar.gz"

    print_step "Downloading WireGuard-UI v$WG_UI_VERSION..."
    wget -q -O "$TEMP_TAR" "$DOWNLOAD_URL"
    print_success "Download completed"

    print_step "Extracting WireGuard-UI..."
    su - "$CURRENT_USER" -c "tar -xzf '$TEMP_TAR' -C '$INSTALL_DIR'" > /dev/null 2>&1
    print_success "WireGuard-UI extracted"

    print_step "Setting executable permissions..."
    chmod +x "$INSTALL_DIR/wireguard-ui"
    print_success "Permissions set"

    # Clean up
    rm -f "$TEMP_TAR"

    print_info "WireGuard-UI installed at: $INSTALL_DIR/wireguard-ui"
}

generate_wireguard_keys() {
    print_header "Generating WireGuard Keys"

    # Check if WireGuard config already exists
    if [[ -f "/etc/wireguard/${WG_INTERFACE}.conf" ]]; then
        print_info "WireGuard configuration already exists"
        print_step "Skipping key generation..."
        print_success "Using existing WireGuard configuration"
        return
    fi

    print_step "Generating server private key..."
    WG_PRIVATE_KEY=$(wg genkey)
    print_success "Private key generated"

    print_step "Generating server public key..."
    WG_PUBLIC_KEY=$(echo "$WG_PRIVATE_KEY" | wg pubkey)
    print_success "Public key generated"

    print_step "Getting server public IP..."
    SERVER_PUBLIC_IP=$(get_public_ip)
    print_success "Public IP: $SERVER_PUBLIC_IP"

    # Create WireGuard configuration
    print_step "Creating WireGuard configuration..."

    # Detect the default network interface
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

    cat > "/etc/wireguard/${WG_INTERFACE}.conf" << EOF
[Interface]
PrivateKey = $WG_PRIVATE_KEY
Address = 10.252.1.1/24
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE

# Peers will be added by WireGuard-UI
EOF

    chmod 600 "/etc/wireguard/${WG_INTERFACE}.conf"
    print_success "WireGuard configuration created"

    # Export for later use
    export WG_PRIVATE_KEY WG_PUBLIC_KEY SERVER_PUBLIC_IP
}

create_env_file() {
    print_header "Creating Environment Configuration"

    # Check if .env file already exists
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        print_info ".env file already exists at $INSTALL_DIR/.env"
        print_step "Skipping .env file creation to preserve existing configuration..."
        print_success "Using existing .env file"

        # Read existing credentials for summary
        if [[ -f "$INSTALL_DIR/.env" ]]; then
            ADMIN_USERNAME=$(grep "^WGUI_USERNAME=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
            ADMIN_PASSWORD="(stored in .env file)"
        fi
        export ADMIN_USERNAME ADMIN_PASSWORD
        return
    fi

    ADMIN_USERNAME="admin"
    ADMIN_PASSWORD=$(generate_password)
    SESSION_SECRET=$(generate_session_secret)
    SERVER_PUBLIC_IP=$(get_public_ip)

    print_step "Creating .env file..."

    # Create .env file
    cat > "$INSTALL_DIR/.env" << EOF
# WireGuard-UI Configuration
BIND_ADDRESS=127.0.0.1:$APP_PORT
SESSION_SECRET=$SESSION_SECRET

# Admin credentials
WGUI_USERNAME=$ADMIN_USERNAME
WGUI_PASSWORD=$ADMIN_PASSWORD

# WireGuard configuration
WGUI_CONFIG_FILE_PATH=/etc/wireguard/${WG_INTERFACE}.conf
WG_CONF_TEMPLATE=
WGUI_LOG_LEVEL=INFO

# Server settings
WGUI_ENDPOINT_ADDRESS=$SERVER_PUBLIC_IP
WGUI_SERVER_LISTEN_PORT=$WG_PORT
WGUI_SERVER_INTERFACE_ADDRESSES=10.252.1.1/24
WGUI_DEFAULT_CLIENT_ALLOWED_IPS=0.0.0.0/0
WGUI_DEFAULT_CLIENT_USE_SERVER_DNS=true
WGUI_DNS=1.1.1.1,8.8.8.8
WGUI_MTU=1420
WGUI_PERSISTENT_KEEPALIVE=15
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    print_success ".env file created with secure permissions"

    # Save credentials for summary
    export ADMIN_USERNAME ADMIN_PASSWORD
}

setup_wireguard_permissions() {
    print_header "Setting Up WireGuard Permissions"

    print_step "Adding $INSTALLER_USER to appropriate groups..."
    # Add user to the group that can manage WireGuard
    usermod -aG sudo "$CURRENT_USER"
    print_success "User permissions configured"

    print_step "Setting WireGuard directory permissions..."
    chown -R root:root /etc/wireguard
    chmod 700 /etc/wireguard
    chmod 600 /etc/wireguard/*.conf 2>/dev/null || true
    print_success "WireGuard directory permissions set"

    # Create sudoers file for wireguard-ui to restart WireGuard without password
    print_step "Configuring sudo permissions for WireGuard management..."
    cat > /etc/sudoers.d/wireguard-ui << EOF
# Allow wireguard-ui service to manage WireGuard
$INSTALLER_USER ALL=(ALL) NOPASSWD: /usr/bin/wg
$INSTALLER_USER ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
$INSTALLER_USER ALL=(ALL) NOPASSWD: /bin/systemctl start wg-quick@*
$INSTALLER_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop wg-quick@*
$INSTALLER_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart wg-quick@*
$INSTALLER_USER ALL=(ALL) NOPASSWD: /bin/systemctl status wg-quick@*
EOF
    chmod 440 /etc/sudoers.d/wireguard-ui
    print_success "Sudo permissions configured"
}

create_systemd_services() {
    print_header "Creating Systemd Services"

    # Create main WireGuard-UI service
    print_step "Creating WireGuard-UI service file..."

    tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=WireGuard-UI Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/wireguard-ui -bind-address \${BIND_ADDRESS}
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    print_success "WireGuard-UI service file created"

    # Create wgui.path for watching WireGuard config changes
    print_step "Creating WireGuard config watcher (wgui.path)..."

    tee /etc/systemd/system/wgui.path > /dev/null << EOF
[Unit]
Description=Watch /etc/wireguard/${WG_INTERFACE}.conf for changes

[Path]
PathModified=/etc/wireguard/${WG_INTERFACE}.conf

[Install]
WantedBy=multi-user.target
EOF

    print_success "wgui.path created"

    # Create wgui.service for restarting WireGuard on config change
    print_step "Creating WireGuard restart service (wgui.service)..."

    tee /etc/systemd/system/wgui.service > /dev/null << EOF
[Unit]
Description=Restart WireGuard
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart wg-quick@${WG_INTERFACE}.service

[Install]
RequiredBy=wgui.path
EOF

    print_success "wgui.service created"

    print_step "Reloading systemd daemon..."
    systemctl daemon-reload
    print_success "Systemd daemon reloaded"

    # Enable and start WireGuard
    print_step "Enabling and starting WireGuard..."
    systemctl enable wg-quick@${WG_INTERFACE} > /dev/null 2>&1

    if systemctl is-active --quiet wg-quick@${WG_INTERFACE}; then
        systemctl restart wg-quick@${WG_INTERFACE}
        print_success "WireGuard restarted"
    else
        systemctl start wg-quick@${WG_INTERFACE}
        print_success "WireGuard started"
    fi

    # Enable and start path watcher
    print_step "Enabling config watcher..."
    systemctl enable wgui.path > /dev/null 2>&1
    systemctl enable wgui.service > /dev/null 2>&1
    systemctl start wgui.path
    print_success "Config watcher enabled"

    # Enable and start WireGuard-UI
    print_step "Enabling WireGuard-UI service..."
    systemctl enable ${SERVICE_NAME}.service > /dev/null 2>&1
    print_success "Service enabled"

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

    client_max_body_size 10M;
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

configure_firewall() {
    print_header "Configuring Firewall"

    # Check if ufw is installed
    if ! command -v ufw &> /dev/null; then
        print_info "UFW not installed, skipping firewall configuration"
        print_warning "Make sure to open port $WG_PORT/udp for WireGuard connections"
        return
    fi

    print_step "Allowing SSH..."
    ufw allow ssh > /dev/null 2>&1
    print_success "SSH allowed"

    print_step "Allowing HTTP..."
    ufw allow http > /dev/null 2>&1
    print_success "HTTP allowed"

    print_step "Allowing HTTPS..."
    ufw allow https > /dev/null 2>&1
    print_success "HTTPS allowed"

    print_step "Allowing WireGuard port ($WG_PORT/udp)..."
    ufw allow $WG_PORT/udp > /dev/null 2>&1
    print_success "WireGuard port allowed"

    print_step "Enabling firewall..."
    echo "y" | ufw enable > /dev/null 2>&1 || true
    print_success "Firewall configured"
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

    SERVER_PUBLIC_IP=$(get_public_ip)

    print_header "Installation Summary"

    echo -e "${WHITE}Application Details:${NC}"
    echo -e "  ${CYAN}•${NC} Web Interface:   ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}•${NC} Install path:    ${BOLD}$INSTALL_DIR${NC}"
    echo -e "  ${CYAN}•${NC} WireGuard port:  ${BOLD}$WG_PORT/udp${NC}"
    echo ""

    echo -e "${WHITE}Admin Credentials:${NC}"
    echo -e "  ${CYAN}•${NC} Username:        ${BOLD}$ADMIN_USERNAME${NC}"
    echo -e "  ${CYAN}•${NC} Password:        ${BOLD}$ADMIN_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}WireGuard Server:${NC}"
    echo -e "  ${CYAN}•${NC} Server IP:       ${BOLD}$SERVER_PUBLIC_IP${NC}"
    echo -e "  ${CYAN}•${NC} Listen Port:     ${BOLD}$WG_PORT${NC}"
    echo -e "  ${CYAN}•${NC} Interface:       ${BOLD}$WG_INTERFACE${NC}"
    echo -e "  ${CYAN}•${NC} Config file:     ${BOLD}/etc/wireguard/${WG_INTERFACE}.conf${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}•${NC} WireGuard-UI status:  ${BOLD}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} WireGuard status:     ${BOLD}sudo systemctl status wg-quick@${WG_INTERFACE}${NC}"
    echo -e "  ${CYAN}•${NC} Restart UI:           ${BOLD}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} Restart WireGuard:    ${BOLD}sudo systemctl restart wg-quick@${WG_INTERFACE}${NC}"
    echo -e "  ${CYAN}•${NC} View UI logs:         ${BOLD}sudo journalctl -u ${SERVICE_NAME}${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} Admin credentials are stored in: ${BOLD}$INSTALL_DIR/.env${NC}"
    echo -e "  ${CYAN}•${NC} Please save the admin password in a secure location"
    echo -e "  ${CYAN}•${NC} Change the default password after first login"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to access WireGuard-UI"
    echo -e "  ${CYAN}2.${NC} Log in with the credentials above"
    echo -e "  ${CYAN}3.${NC} Add clients in the web interface"
    echo -e "  ${CYAN}4.${NC} Download client configurations or scan QR codes"
    echo ""

    print_success "Thank you for using WireGuard + WireGuard-UI!"
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
    configure_ip_forwarding
    generate_wireguard_keys
    download_wireguard_ui
    create_env_file
    setup_wireguard_permissions
    add_user_to_www_data
    create_systemd_services
    configure_nginx
    setup_ssl_certificate
    configure_firewall

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
