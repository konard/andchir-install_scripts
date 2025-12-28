#!/bin/bash

#===============================================================================
#
#   Jitsi Meet - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Prosody XMPP server
#   - Jitsi Meet video conferencing platform
#   - Jitsi Videobridge (JVB)
#   - Jicofo (Jitsi Conference Focus)
#   - Nginx as reverse proxy
#   - SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/jitsi/jitsi-meet
#   Documentation: https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-quickstart
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
APP_NAME="jitsi-meet"
SERVICE_NAME="jitsi-meet"
INSTALLER_USER="installer_user"

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
    echo "  domain_name    The domain name for Jitsi Meet (e.g., meet.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 meet.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., meet.example.com)"
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
    echo -e "${CYAN}   ╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Jitsi Meet${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Prosody XMPP server                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Jitsi Meet video conferencing platform                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Jitsi Videobridge (JVB)                                               ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Jicofo (Jitsi Conference Focus)                                       ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Nginx as reverse proxy                                                ${CYAN}║${NC}"
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
    apt-get install -y -qq curl wget gnupg2 lsb-release ca-certificates apt-transport-https software-properties-common > /dev/null 2>&1
    print_success "Core utilities installed"

    # Add universe repository if not already added
    print_step "Enabling universe repository..."
    add-apt-repository -y universe > /dev/null 2>&1 || true
    apt-get update -qq
    print_success "Universe repository enabled"

    print_step "Installing OpenJDK 17..."
    apt-get install -y -qq openjdk-17-jdk-headless > /dev/null 2>&1
    print_success "OpenJDK 17 installed"

    print_step "Installing Lua 5.2..."
    apt-get install -y -qq lua5.2 > /dev/null 2>&1
    print_success "Lua 5.2 installed"

    print_success "All system dependencies installed successfully!"
}

setup_prosody_repository() {
    print_header "Setting Up Prosody Repository"

    # Check if Prosody repository is already configured
    if [[ -f "/etc/apt/sources.list.d/prosody-debian-packages.list" ]]; then
        print_info "Prosody repository already configured"
    else
        print_step "Adding Prosody GPG key..."
        curl -sL https://prosody.im/files/prosody-debian-packages.key -o /usr/share/keyrings/prosody-debian-packages.key
        print_success "Prosody GPG key added"

        print_step "Adding Prosody repository..."
        echo "deb [signed-by=/usr/share/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main" > /etc/apt/sources.list.d/prosody-debian-packages.list
        print_success "Prosody repository added"
    fi

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"
}

setup_jitsi_repository() {
    print_header "Setting Up Jitsi Repository"

    # Check if Jitsi repository is already configured
    if [[ -f "/etc/apt/sources.list.d/jitsi-stable.list" ]]; then
        print_info "Jitsi repository already configured"
    else
        print_step "Adding Jitsi GPG key..."
        curl -sL https://download.jitsi.org/jitsi-key.gpg.key | gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg
        print_success "Jitsi GPG key added"

        print_step "Adding Jitsi repository..."
        echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" > /etc/apt/sources.list.d/jitsi-stable.list
        print_success "Jitsi repository added"
    fi

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"
}

configure_firewall() {
    print_header "Configuring Firewall"

    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        print_step "Installing UFW..."
        apt-get install -y -qq ufw > /dev/null 2>&1
        print_success "UFW installed"
    fi

    print_step "Configuring firewall rules..."

    # Allow SSH first to prevent lockout
    ufw allow 22/tcp > /dev/null 2>&1 || true

    # Allow Jitsi Meet required ports
    ufw allow 80/tcp > /dev/null 2>&1 || true   # SSL certificate verification
    ufw allow 443/tcp > /dev/null 2>&1 || true  # General access (HTTPS)
    ufw allow 10000/udp > /dev/null 2>&1 || true # Video/audio RTP
    ufw allow 3478/udp > /dev/null 2>&1 || true  # STUN
    ufw allow 5349/tcp > /dev/null 2>&1 || true  # Fallback TCP for video/audio

    print_success "Firewall rules configured"

    # Enable UFW if not already enabled
    print_step "Enabling firewall..."
    echo "y" | ufw enable > /dev/null 2>&1 || true
    print_success "Firewall enabled"

    print_info "Open ports: 22/tcp, 80/tcp, 443/tcp, 10000/udp, 3478/udp, 5349/tcp"
}

configure_hostname() {
    print_header "Configuring Hostname"

    print_step "Setting hostname to $DOMAIN_NAME..."
    hostnamectl set-hostname "$DOMAIN_NAME"
    print_success "Hostname set"

    # Add domain to /etc/hosts if not already present
    if ! grep -q "$DOMAIN_NAME" /etc/hosts; then
        print_step "Adding domain to /etc/hosts..."
        echo "127.0.0.1 $DOMAIN_NAME" >> /etc/hosts
        print_success "Domain added to /etc/hosts"
    else
        print_info "Domain already present in /etc/hosts"
    fi
}

preconfigure_jitsi() {
    print_header "Pre-configuring Jitsi Meet"

    print_step "Setting up debconf for non-interactive installation..."

    # Pre-configure the hostname
    echo "jitsi-videobridge2 jitsi-videobridge/jvb-hostname string $DOMAIN_NAME" | debconf-set-selections
    echo "jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate (You will later get a chance to obtain a Let's encrypt certificate)" | debconf-set-selections
    echo "jitsi-meet-web-config jitsi-meet/jaas-choice boolean false" | debconf-set-selections
    echo "jitsi-meet-prosody jitsi-meet-prosody/jvb-hostname string $DOMAIN_NAME" | debconf-set-selections

    print_success "Jitsi Meet pre-configured for non-interactive installation"
}

install_jitsi_meet() {
    print_header "Installing Jitsi Meet"

    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive

    print_step "Installing Jitsi Meet (this may take several minutes)..."
    apt-get install -y -qq jitsi-meet > /dev/null 2>&1
    print_success "Jitsi Meet installed"

    # Verify installation
    print_step "Verifying installation..."

    local services_ok=true

    if systemctl is-active --quiet prosody; then
        print_success "Prosody XMPP server is running"
    else
        print_warning "Prosody XMPP server is not running"
        services_ok=false
    fi

    if systemctl is-active --quiet jitsi-videobridge2; then
        print_success "Jitsi Videobridge is running"
    else
        print_warning "Jitsi Videobridge is not running"
        services_ok=false
    fi

    if systemctl is-active --quiet jicofo; then
        print_success "Jicofo is running"
    else
        print_warning "Jicofo is not running"
        services_ok=false
    fi

    if [[ "$services_ok" == false ]]; then
        print_step "Restarting Jitsi services..."
        systemctl restart prosody jitsi-videobridge2 jicofo
        sleep 5
        print_success "Jitsi services restarted"
    fi
}

configure_nginx() {
    print_header "Configuring Nginx"

    # Jitsi Meet installation creates its own nginx configuration
    # We just need to verify it's working

    print_step "Verifying Nginx configuration..."

    if nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi

    # Check if jitsi nginx config exists
    if [[ -f "/etc/nginx/sites-enabled/$DOMAIN_NAME.conf" ]] || [[ -f "/etc/nginx/sites-enabled/${DOMAIN_NAME}.conf" ]]; then
        print_success "Jitsi Meet Nginx configuration found"
    else
        print_info "Nginx configuration managed by Jitsi Meet"
    fi

    # Ensure Nginx is running
    print_step "Ensuring Nginx is running..."
    systemctl enable nginx > /dev/null 2>&1
    systemctl restart nginx
    print_success "Nginx is running"

    # Configure separate log files for the domain
    print_step "Configuring domain-specific log files..."

    # Find and update the Jitsi nginx config
    local nginx_config=""
    if [[ -f "/etc/nginx/sites-available/$DOMAIN_NAME.conf" ]]; then
        nginx_config="/etc/nginx/sites-available/$DOMAIN_NAME.conf"
    elif [[ -f "/etc/nginx/sites-available/${DOMAIN_NAME}.conf" ]]; then
        nginx_config="/etc/nginx/sites-available/${DOMAIN_NAME}.conf"
    fi

    if [[ -n "$nginx_config" ]] && [[ -f "$nginx_config" ]]; then
        # Check if access_log is already configured for the domain
        if ! grep -q "access_log /var/log/nginx/${DOMAIN_NAME}" "$nginx_config"; then
            # Add log configuration after the first server block opening
            sed -i "/server {/a\\    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;\\n    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;" "$nginx_config" 2>/dev/null || true
            print_success "Domain-specific log files configured"
            systemctl reload nginx
        else
            print_info "Domain-specific log files already configured"
        fi
    fi
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

    # Use the Jitsi script for obtaining Let's Encrypt certificate
    print_step "Running Jitsi Let's Encrypt script..."

    # Retry settings for handling transient Let's Encrypt errors
    local max_attempts=3
    local retry_delay=10
    local attempt=1
    local certbot_success=false

    while [[ $attempt -le $max_attempts ]]; do
        print_step "Running Let's Encrypt setup (attempt $attempt of $max_attempts)..."

        # Run the Jitsi Let's Encrypt script with automatic email skip
        if echo "" | /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh 2>/dev/null; then
            certbot_success=true
            break
        else
            if [[ $attempt -lt $max_attempts ]]; then
                print_warning "Let's Encrypt attempt $attempt failed. Retrying in $retry_delay seconds..."
                sleep $retry_delay
                # Increase delay for next attempt (exponential backoff)
                retry_delay=$((retry_delay * 2))
            fi
        fi
        ((attempt++))
    done

    if [[ "$certbot_success" == true ]]; then
        print_success "SSL certificate obtained and configured"

        print_step "Setting up automatic renewal..."
        systemctl enable certbot.timer > /dev/null 2>&1
        systemctl start certbot.timer
        print_success "Automatic certificate renewal enabled"
    else
        print_warning "SSL certificate setup failed after $max_attempts attempts. You can run it manually later:"
        print_info "/usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh"
    fi
}

configure_high_capacity() {
    print_header "Configuring for High Capacity"

    print_step "Optimizing system limits for video conferencing..."

    # Check if limits are already configured
    if grep -q "DefaultLimitNOFILE=65000" /etc/systemd/system.conf 2>/dev/null; then
        print_info "System limits already configured"
    else
        print_step "Updating system limits..."

        # Backup original file
        cp /etc/systemd/system.conf /etc/systemd/system.conf.bak

        # Update or add limits
        if grep -q "^DefaultLimitNOFILE=" /etc/systemd/system.conf; then
            sed -i 's/^DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65000/' /etc/systemd/system.conf
        else
            echo "DefaultLimitNOFILE=65000" >> /etc/systemd/system.conf
        fi

        if grep -q "^DefaultLimitNPROC=" /etc/systemd/system.conf; then
            sed -i 's/^DefaultLimitNPROC=.*/DefaultLimitNPROC=65000/' /etc/systemd/system.conf
        else
            echo "DefaultLimitNPROC=65000" >> /etc/systemd/system.conf
        fi

        if grep -q "^DefaultTasksMax=" /etc/systemd/system.conf; then
            sed -i 's/^DefaultTasksMax=.*/DefaultTasksMax=65000/' /etc/systemd/system.conf
        else
            echo "DefaultTasksMax=65000" >> /etc/systemd/system.conf
        fi

        print_success "System limits updated"

        print_step "Reloading systemd daemon..."
        systemctl daemon-reload
        print_success "Systemd daemon reloaded"
    fi
}

restart_services() {
    print_header "Restarting Services"

    print_step "Restarting Jitsi services..."

    systemctl restart prosody
    print_success "Prosody restarted"

    systemctl restart jitsi-videobridge2
    print_success "Jitsi Videobridge restarted"

    systemctl restart jicofo
    print_success "Jicofo restarted"

    systemctl restart nginx
    print_success "Nginx restarted"

    # Wait for services to be fully up
    print_step "Waiting for services to start..."
    sleep 5
    print_success "All services restarted"
}

create_installation_directory() {
    print_header "Creating Installation Directory"

    print_step "Creating installation directory..."
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR'"
    print_success "Installation directory created"

    print_info "Installation directory: $INSTALL_DIR"
}

create_management_script() {
    print_header "Creating Management Script"

    print_step "Creating management script..."

    cat > "$INSTALL_DIR/manage.sh" << 'EOF'
#!/bin/bash

# Jitsi Meet Management Script
# Usage: ./manage.sh [command]

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

case "$1" in
    start)
        echo -e "${CYAN}Starting Jitsi Meet services...${NC}"
        sudo systemctl start prosody jitsi-videobridge2 jicofo nginx
        echo -e "${GREEN}Services started${NC}"
        ;;
    stop)
        echo -e "${CYAN}Stopping Jitsi Meet services...${NC}"
        sudo systemctl stop jicofo jitsi-videobridge2 prosody
        echo -e "${GREEN}Services stopped${NC}"
        ;;
    restart)
        echo -e "${CYAN}Restarting Jitsi Meet services...${NC}"
        sudo systemctl restart prosody jitsi-videobridge2 jicofo nginx
        echo -e "${GREEN}Services restarted${NC}"
        ;;
    status)
        echo -e "${CYAN}Jitsi Meet Services Status:${NC}"
        echo ""
        echo -e "${WHITE}Prosody:${NC}"
        systemctl status prosody --no-pager -l 2>/dev/null | head -3
        echo ""
        echo -e "${WHITE}Jitsi Videobridge:${NC}"
        systemctl status jitsi-videobridge2 --no-pager -l 2>/dev/null | head -3
        echo ""
        echo -e "${WHITE}Jicofo:${NC}"
        systemctl status jicofo --no-pager -l 2>/dev/null | head -3
        echo ""
        echo -e "${WHITE}Nginx:${NC}"
        systemctl status nginx --no-pager -l 2>/dev/null | head -3
        ;;
    logs)
        SERVICE="${2:-jitsi-videobridge2}"
        echo -e "${CYAN}Showing logs for $SERVICE...${NC}"
        sudo journalctl -u "$SERVICE" -f
        ;;
    update)
        echo -e "${CYAN}Updating Jitsi Meet...${NC}"
        sudo apt-get update
        sudo apt-get upgrade -y jitsi-meet
        echo -e "${GREEN}Jitsi Meet updated${NC}"
        ;;
    config)
        echo -e "${CYAN}Configuration Files:${NC}"
        echo "  Jitsi Meet:      /etc/jitsi/meet/"
        echo "  Videobridge:     /etc/jitsi/videobridge/"
        echo "  Jicofo:          /etc/jitsi/jicofo/"
        echo "  Prosody:         /etc/prosody/"
        echo "  Nginx:           /etc/nginx/"
        ;;
    *)
        echo "Jitsi Meet Management Script"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs|update|config}"
        echo ""
        echo "Commands:"
        echo "  start         - Start all Jitsi Meet services"
        echo "  stop          - Stop all Jitsi Meet services"
        echo "  restart       - Restart all Jitsi Meet services"
        echo "  status        - Show status of all services"
        echo "  logs [svc]    - Show logs (default: jitsi-videobridge2)"
        echo "                  Services: prosody, jitsi-videobridge2, jicofo, nginx"
        echo "  update        - Update Jitsi Meet to latest version"
        echo "  config        - Show configuration file locations"
        ;;
esac
EOF

    chmod +x "$INSTALL_DIR/manage.sh"
    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/manage.sh"
    print_success "Management script created"
}

add_user_to_www_data() {
    print_header "Configuring User Permissions"

    print_step "Adding $CURRENT_USER to www-data group..."
    usermod -aG www-data "$CURRENT_USER"
    print_success "User added to www-data group"

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
    echo -e "  ${CYAN}•${NC} Domain:           ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}•${NC} Install path:     ${BOLD}$INSTALL_DIR${NC}"
    echo ""

    echo -e "${WHITE}Jitsi Meet Components:${NC}"
    echo -e "  ${CYAN}•${NC} Jitsi Meet Web:   ${BOLD}/usr/share/jitsi-meet${NC}"
    echo -e "  ${CYAN}•${NC} Prosody:          ${BOLD}/etc/prosody${NC}"
    echo -e "  ${CYAN}•${NC} Videobridge:      ${BOLD}/etc/jitsi/videobridge${NC}"
    echo -e "  ${CYAN}•${NC} Jicofo:           ${BOLD}/etc/jitsi/jicofo${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}•${NC} Check status:     ${BOLD}systemctl status prosody jitsi-videobridge2 jicofo${NC}"
    echo -e "  ${CYAN}•${NC} View JVB logs:    ${BOLD}journalctl -u jitsi-videobridge2 -f${NC}"
    echo -e "  ${CYAN}•${NC} View Jicofo logs: ${BOLD}journalctl -u jicofo -f${NC}"
    echo -e "  ${CYAN}•${NC} Restart all:      ${BOLD}systemctl restart prosody jitsi-videobridge2 jicofo nginx${NC}"
    echo ""

    echo -e "${WHITE}Management Script:${NC}"
    echo -e "  ${CYAN}•${NC} Start:            ${BOLD}$INSTALL_DIR/manage.sh start${NC}"
    echo -e "  ${CYAN}•${NC} Stop:             ${BOLD}$INSTALL_DIR/manage.sh stop${NC}"
    echo -e "  ${CYAN}•${NC} Status:           ${BOLD}$INSTALL_DIR/manage.sh status${NC}"
    echo -e "  ${CYAN}•${NC} Logs:             ${BOLD}$INSTALL_DIR/manage.sh logs${NC}"
    echo -e "  ${CYAN}•${NC} Update:           ${BOLD}$INSTALL_DIR/manage.sh update${NC}"
    echo ""

    echo -e "${WHITE}Network Ports:${NC}"
    echo -e "  ${CYAN}•${NC} 80/tcp:           ${BOLD}HTTP (Let's Encrypt verification)${NC}"
    echo -e "  ${CYAN}•${NC} 443/tcp:          ${BOLD}HTTPS (Web access)${NC}"
    echo -e "  ${CYAN}•${NC} 10000/udp:        ${BOLD}Video/Audio RTP${NC}"
    echo -e "  ${CYAN}•${NC} 3478/udp:         ${BOLD}STUN${NC}"
    echo -e "  ${CYAN}•${NC} 5349/tcp:         ${BOLD}Fallback TCP for video/audio${NC}"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to access Jitsi Meet"
    echo -e "  ${CYAN}2.${NC} Create a room by typing a name and clicking 'Start Meeting'"
    echo -e "  ${CYAN}3.${NC} Share the room URL with participants"
    echo -e "  ${CYAN}4.${NC} Check ${BOLD}https://jitsi.github.io/handbook/${NC} for documentation"
    echo ""

    echo -e "${YELLOW}Security Notes:${NC}"
    echo -e "  ${CYAN}•${NC} By default, anyone can create rooms"
    echo -e "  ${CYAN}•${NC} For secure deployment, configure authentication in:"
    echo -e "    ${BOLD}/etc/prosody/conf.avail/$DOMAIN_NAME.cfg.lua${NC}"
    echo ""

    print_success "Thank you for using Jitsi Meet installer!"
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
    setup_prosody_repository
    setup_jitsi_repository
    configure_firewall
    configure_hostname
    preconfigure_jitsi
    install_jitsi_meet
    configure_nginx
    setup_ssl_certificate
    configure_high_capacity
    restart_services
    create_installation_directory
    add_user_to_www_data
    create_management_script

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
