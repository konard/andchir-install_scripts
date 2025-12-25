#!/bin/bash

#===============================================================================
#
#   PostgreSQL + Mathesar - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - PostgreSQL 16 database server
#   - Mathesar - intuitive spreadsheet-like interface for PostgreSQL
#   - Nginx as reverse proxy
#   - SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/mathesar-foundation/mathesar
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
APP_NAME="mathesar"
SERVICE_NAME="mathesar"
INSTALLER_USER="installer_user"
APP_PORT="8000"
MATHESAR_VERSION="0.8.0"
POSTGRESQL_VERSION="16"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""

# Database credentials (will be generated)
DB_NAME="mathesar_django"
DB_USER="mathesar"
DB_PASSWORD=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name>"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for the application (e.g., mathesar.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 mathesar.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., mathesar.example.com)"
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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}PostgreSQL + Mathesar${NC}                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} PostgreSQL ${POSTGRESQL_VERSION} database server                                       ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Mathesar web interface                                                ${CYAN}║${NC}"
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
    apt-get install -y -qq curl wget gnupg2 lsb-release > /dev/null 2>&1
    print_success "Core utilities installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_success "All system dependencies installed successfully!"
}

install_postgresql() {
    print_header "Installing PostgreSQL ${POSTGRESQL_VERSION}"

    # Check if PostgreSQL is already installed
    if command -v psql &> /dev/null; then
        INSTALLED_VERSION=$(psql --version | grep -oP '\d+' | head -1)
        if [[ "$INSTALLED_VERSION" -ge "$POSTGRESQL_VERSION" ]]; then
            print_info "PostgreSQL $INSTALLED_VERSION is already installed"
            print_step "Skipping PostgreSQL installation..."

            # Ensure PostgreSQL service is running
            print_step "Ensuring PostgreSQL service is running..."
            systemctl start postgresql
            systemctl enable postgresql > /dev/null 2>&1
            print_success "PostgreSQL service is running"
            return
        fi
    fi

    print_step "Adding PostgreSQL APT repository..."
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    print_success "PostgreSQL repository added"

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing PostgreSQL ${POSTGRESQL_VERSION}..."
    apt-get install -y -qq postgresql-${POSTGRESQL_VERSION} postgresql-contrib-${POSTGRESQL_VERSION} > /dev/null 2>&1
    print_success "PostgreSQL ${POSTGRESQL_VERSION} installed"

    print_step "Starting PostgreSQL service..."
    systemctl start postgresql
    systemctl enable postgresql > /dev/null 2>&1
    print_success "PostgreSQL service started and enabled"
}

setup_database() {
    print_header "Setting Up Mathesar Database"

    # Check if .env file already exists with credentials
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        print_info "Environment file already exists at $INSTALL_DIR/.env"
        # Read existing database password
        DB_PASSWORD=$(grep "^DATABASE_URL=" "$INSTALL_DIR/.env" 2>/dev/null | sed -n 's/.*mathesar:\([^@]*\)@.*/\1/p' || echo "")
        if [[ -z "$DB_PASSWORD" ]]; then
            DB_PASSWORD=$(generate_password)
        fi
    else
        DB_PASSWORD=$(generate_password)
    fi

    # Check if database user already exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        print_info "Database user '$DB_USER' already exists"
        print_step "Updating password for user '$DB_USER'..."
        sudo -u postgres psql -c "ALTER USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD';" > /dev/null 2>&1
        print_success "Password updated for user '$DB_USER'"
    else
        print_step "Creating database user '$DB_USER'..."
        sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD' CREATEDB;" > /dev/null 2>&1
        print_success "Database user '$DB_USER' created"
    fi

    # Check if database already exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
        print_info "Database '$DB_NAME' already exists"
        print_step "Skipping database creation..."
    else
        print_step "Creating database '$DB_NAME'..."
        sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" > /dev/null 2>&1
        print_success "Database '$DB_NAME' created"
    fi

    print_success "Database setup completed"
    print_info "Database: $DB_NAME"
    print_info "User: $DB_USER"
}

install_mathesar() {
    print_header "Installing Mathesar"

    # Create installation directory
    print_step "Creating installation directory..."
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR'"
    print_success "Installation directory created"

    # Check if Mathesar is already installed
    if [[ -f "$INSTALL_DIR/bin/mathesar" ]]; then
        print_info "Mathesar is already installed at $INSTALL_DIR"
        print_step "Checking for updates..."

        CURRENT_VERSION=$("$INSTALL_DIR/bin/mathesar" version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
        if [[ "$CURRENT_VERSION" == "$MATHESAR_VERSION" ]]; then
            print_info "Mathesar v$MATHESAR_VERSION is already installed"
            print_success "Using existing Mathesar installation"
            return
        else
            print_info "Updating Mathesar from v$CURRENT_VERSION to v$MATHESAR_VERSION"
        fi
    fi

    # Download and run install script
    print_step "Downloading Mathesar installer v$MATHESAR_VERSION..."
    INSTALL_SCRIPT_URL="https://github.com/mathesar-foundation/mathesar/releases/download/${MATHESAR_VERSION}/install.sh"
    su - "$CURRENT_USER" -c "curl -sSfL '$INSTALL_SCRIPT_URL' -o '$INSTALL_DIR/install.sh'"
    su - "$CURRENT_USER" -c "chmod +x '$INSTALL_DIR/install.sh'"
    print_success "Installer downloaded"

    print_step "Running Mathesar installer..."
    DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}"
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && ./install.sh . -c '$DATABASE_URL'" > /dev/null 2>&1
    print_success "Mathesar installed"

    # Clean up installer script
    rm -f "$INSTALL_DIR/install.sh"

    print_info "Mathesar installed at: $INSTALL_DIR"
}

create_env_file() {
    print_header "Creating Environment Configuration"

    # Check if .env file already exists
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        print_info ".env file already exists at $INSTALL_DIR/.env"

        # Check if ALLOWED_HOSTS is set correctly
        if grep -q "^ALLOWED_HOSTS=" "$INSTALL_DIR/.env"; then
            CURRENT_HOSTS=$(grep "^ALLOWED_HOSTS=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
            if [[ "$CURRENT_HOSTS" != *"$DOMAIN_NAME"* ]]; then
                print_step "Updating ALLOWED_HOSTS to include $DOMAIN_NAME..."
                sed -i "s/^ALLOWED_HOSTS=.*/ALLOWED_HOSTS=$DOMAIN_NAME,localhost/" "$INSTALL_DIR/.env"
                print_success "ALLOWED_HOSTS updated"
            else
                print_info "ALLOWED_HOSTS already includes $DOMAIN_NAME"
            fi
        else
            print_step "Adding ALLOWED_HOSTS to .env file..."
            echo "ALLOWED_HOSTS=$DOMAIN_NAME,localhost" >> "$INSTALL_DIR/.env"
            print_success "ALLOWED_HOSTS added"
        fi

        print_success "Using existing .env file"
        return
    fi

    print_step "Creating .env file..."

    DATABASE_URL="postgres://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}"

    # Create .env file
    cat > "$INSTALL_DIR/.env" << EOF
DATABASE_URL=$DATABASE_URL
ALLOWED_HOSTS=$DOMAIN_NAME,localhost
SECRET_KEY=$(generate_password)$(generate_password)
WEB_CONCURRENCY=3
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    print_success ".env file created with secure permissions"
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    print_step "Creating service file..."

    tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Mathesar - PostgreSQL Web Interface
After=network.target network-online.target postgresql.service
Requires=network-online.target

[Service]
Type=notify
User=$CURRENT_USER
Group=$CURRENT_USER
RuntimeDirectory=mathesar
WorkingDirectory=$INSTALL_DIR
ExecStart=/bin/bash -c '$INSTALL_DIR/bin/mathesar run'
EnvironmentFile=$INSTALL_DIR/.env
Restart=on-failure
RestartSec=5s

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

    # Wait for service to start
    print_step "Waiting for Mathesar to start..."
    sleep 5

    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_success "Mathesar service is running"
    else
        print_warning "Mathesar service may not have started correctly"
        print_info "Check logs with: journalctl -u ${SERVICE_NAME}"
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

    # Static files
    location /static/ {
        alias $INSTALL_DIR/static/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # Media files
    location /media/ {
        alias $INSTALL_DIR/.media/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

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

    print_step "Setting directory permissions..."
    chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    # Ensure media directory exists with proper permissions
    if [[ -d "$INSTALL_DIR/.media" ]]; then
        chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/.media"
    fi

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
    echo -e "  ${CYAN}•${NC} Data path:     ${BOLD}$INSTALL_DIR/.media${NC}"
    echo ""

    echo -e "${WHITE}PostgreSQL Database:${NC}"
    echo -e "  ${CYAN}•${NC} Database:      ${BOLD}$DB_NAME${NC}"
    echo -e "  ${CYAN}•${NC} User:          ${BOLD}$DB_USER${NC}"
    echo -e "  ${CYAN}•${NC} Password:      ${BOLD}$DB_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}Access:${NC}"
    echo -e "  ${CYAN}•${NC} Web URL:       ${BOLD}https://$DOMAIN_NAME${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}•${NC} Check status:  ${BOLD}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} Restart:       ${BOLD}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} View logs:     ${BOLD}sudo journalctl -u ${SERVICE_NAME}${NC}"
    echo ""

    echo -e "${WHITE}PostgreSQL Management:${NC}"
    echo -e "  ${CYAN}•${NC} Connect:       ${BOLD}sudo -u postgres psql${NC}"
    echo -e "  ${CYAN}•${NC} Check status:  ${BOLD}sudo systemctl status postgresql${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} Database credentials are stored in: ${BOLD}$INSTALL_DIR/.env${NC}"
    echo -e "  ${CYAN}•${NC} Please save the database password in a secure location"
    echo -e "  ${CYAN}•${NC} On first access, you will need to create an admin account"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to access Mathesar"
    echo -e "  ${CYAN}2.${NC} Create your admin account on first login"
    echo -e "  ${CYAN}3.${NC} Connect to your PostgreSQL databases and start exploring"
    echo -e "  ${CYAN}4.${NC} Check ${BOLD}https://docs.mathesar.org${NC} for documentation"
    echo ""

    print_success "Thank you for using PostgreSQL + Mathesar!"
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
    install_postgresql
    setup_database
    install_mathesar
    create_env_file
    add_user_to_www_data
    create_systemd_service
    configure_nginx
    setup_ssl_certificate

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
