#!/bin/bash

#===============================================================================
#
#   Linux Dash - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Python 3 for running linux-dash
#   - Clones the linux-dash repository
#   - Creates systemd service for automatic startup
#   - Nginx as reverse proxy with basic authentication
#   - SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/andchir/linux-dash2
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
REPO_URL="https://github.com/andchir/linux-dash2.git"
APP_NAME="linux-dash"
SERVICE_NAME="linux-dash"
INSTALLER_USER="installer_user"
APP_PORT="8765"

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
    echo "  domain_name    The domain name for Linux Dash (e.g., dash.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 dash.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., dash.example.com)"
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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Linux Dash${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Git, Python 3, Nginx, Certbot                                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Linux Dash monitoring dashboard                                       ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Systemd service for auto-start                                        ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Nginx reverse proxy with basic authentication                         ${CYAN}║${NC}"
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

    print_step "Installing Git..."
    apt-get install -y -qq git > /dev/null 2>&1
    print_success "Git installed"

    print_step "Installing Python 3..."
    apt-get install -y -qq python3 > /dev/null 2>&1
    print_success "Python 3 installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_step "Installing additional dependencies..."
    apt-get install -y -qq curl wget apache2-utils > /dev/null 2>&1
    print_success "Additional dependencies installed"

    print_success "All system dependencies installed successfully!"
}

clone_repository() {
    print_header "Setting Up Repository"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        print_info "Repository already exists at $INSTALL_DIR"
        print_step "Discarding local changes..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git checkout ." > /dev/null 2>&1
        print_success "Local changes discarded"
        print_step "Pulling latest updates..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git pull" > /dev/null 2>&1
        print_success "Repository updated successfully"
    else
        if [[ -d "$INSTALL_DIR" ]]; then
            print_warning "Directory $INSTALL_DIR exists but is not a git repository."
            print_step "Backing up existing directory..."
            mv "$INSTALL_DIR" "${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
            print_success "Backup created"
        fi

        print_step "Cloning repository to $INSTALL_DIR..."
        su - "$CURRENT_USER" -c "git clone --depth 1 '$REPO_URL' '$INSTALL_DIR'" > /dev/null 2>&1
        print_success "Repository cloned successfully"
    fi

    cd "$INSTALL_DIR"
    print_info "Working directory: $INSTALL_DIR"
}


create_systemd_service() {
    print_header "Creating Systemd Service"

    print_step "Creating service file..."

    tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Linux Dash - A simple low-overhead web dashboard for Linux
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR/app
ExecStart=/usr/bin/python3 $INSTALL_DIR/app/server/server_py3.py --port $APP_PORT
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

    # Wait for service to be ready
    print_step "Waiting for Linux Dash to be ready..."
    sleep 3

    # Verify service is running
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_success "Linux Dash is running"
    else
        print_warning "Service may not have started properly. Check logs with: journalctl -u $SERVICE_NAME"
    fi
}

create_htpasswd() {
    print_header "Creating Authentication"

    HTPASSWD_FILE="/etc/nginx/.htpasswd-linux-dash"

    # Check if htpasswd file already exists
    if [[ -f "$HTPASSWD_FILE" ]]; then
        print_info "Authentication file already exists"
        print_step "Skipping password generation to preserve existing credentials..."

        # Read existing username from file
        ADMIN_USERNAME=$(head -1 "$HTPASSWD_FILE" | cut -d':' -f1)
        ADMIN_PASSWORD="(stored in $HTPASSWD_FILE)"
        export ADMIN_USERNAME ADMIN_PASSWORD
        print_success "Using existing authentication configuration"
        return
    fi

    ADMIN_USERNAME="admin"
    ADMIN_PASSWORD=$(generate_password)

    print_step "Creating htpasswd file for basic authentication..."
    htpasswd -bc "$HTPASSWD_FILE" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" > /dev/null 2>&1
    chmod 640 "$HTPASSWD_FILE"
    chown root:www-data "$HTPASSWD_FILE"
    print_success "Authentication file created"

    # Store credentials for reference
    CREDENTIALS_FILE="$HOME_DIR/.linux-dash-credentials"
    cat > "$CREDENTIALS_FILE" << EOF
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_PASSWORD=$ADMIN_PASSWORD
EOF
    chown "$CURRENT_USER":"$CURRENT_USER" "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    print_success "Credentials saved to $CREDENTIALS_FILE"

    export ADMIN_USERNAME ADMIN_PASSWORD
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
        auth_basic "Linux Dash Monitoring";
        auth_basic_user_file /etc/nginx/.htpasswd-linux-dash;

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

    # Retry settings for handling transient Let's Encrypt errors
    local max_attempts=3
    local retry_delay=10
    local attempt=1
    local certbot_success=false

    while [[ $attempt -le $max_attempts ]]; do
        print_step "Running Certbot (attempt $attempt of $max_attempts)..."

        # Run certbot with automatic configuration
        if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
            certbot_success=true
            break
        else
            if [[ $attempt -lt $max_attempts ]]; then
                print_warning "Certbot attempt $attempt failed. Retrying in $retry_delay seconds..."
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
        print_info "certbot --nginx -d $DOMAIN_NAME"
    fi
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
    echo -e "  ${CYAN}•${NC} Dashboard URL:  ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}•${NC} Local URL:      ${BOLD}http://localhost:$APP_PORT${NC}"
    echo -e "  ${CYAN}•${NC} Install path:   ${BOLD}$INSTALL_DIR${NC}"
    echo ""

    echo -e "${WHITE}Admin Credentials:${NC}"
    echo -e "  ${CYAN}•${NC} Username:       ${BOLD}$ADMIN_USERNAME${NC}"
    echo -e "  ${CYAN}•${NC} Password:       ${BOLD}$ADMIN_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}•${NC} Check status:   ${BOLD}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} Restart:        ${BOLD}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} View logs:      ${BOLD}sudo journalctl -u ${SERVICE_NAME}${NC}"
    echo ""

    echo -e "${WHITE}Configuration Files:${NC}"
    echo -e "  ${CYAN}•${NC} Nginx config:   ${BOLD}/etc/nginx/sites-available/$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}•${NC} Service file:   ${BOLD}/etc/systemd/system/${SERVICE_NAME}.service${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} Credentials are stored in: ${BOLD}$HOME_DIR/.linux-dash-credentials${NC}"
    echo -e "  ${CYAN}•${NC} Please save the admin password in a secure location"
    echo -e "  ${CYAN}•${NC} Linux Dash binds to localhost only for security"
    echo -e "  ${CYAN}•${NC} All external access goes through Nginx with authentication"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to access the dashboard"
    echo -e "  ${CYAN}2.${NC} Log in with the admin credentials above"
    echo -e "  ${CYAN}3.${NC} Explore system monitoring features"
    echo ""

    print_success "Thank you for using Linux Dash!"
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
    clone_repository
    add_user_to_www_data
    create_htpasswd
    create_systemd_service
    configure_nginx
    setup_ssl_certificate

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
