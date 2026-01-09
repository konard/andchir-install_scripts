#!/bin/bash

#===============================================================================
#
#   Odoo - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - PostgreSQL 16 database server
#   - Odoo - Open Source ERP and CRM
#   - Python 3.12+ with virtual environment
#   - Nginx as reverse proxy
#   - SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/odoo/odoo
#   Documentation: https://www.odoo.com/documentation/master/administration/on_premise/source.html
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
APP_NAME="odoo"
SERVICE_NAME="odoo"
INSTALLER_USER="installer_user"
APP_PORT="8069"
ODOO_VERSION="18.0"
POSTGRESQL_VERSION="16"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""
VENV_DIR=""

# Database credentials (will be generated)
DB_USER="odoo"
DB_PASSWORD=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name>"
    echo ""
    echo "Arguments:"
    echo "  domain_name              The domain name for the application (e.g., odoo.example.com)"
    echo ""
    echo "Examples:"
    echo "  $0 odoo.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., odoo.example.com)"
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
    VENV_DIR="$INSTALL_DIR/venv"

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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Odoo - Open Source ERP and CRM${NC}                                        ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} PostgreSQL ${POSTGRESQL_VERSION} database server                                       ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Odoo ${ODOO_VERSION} ERP/CRM system                                              ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Python 3.12+ with virtual environment                                 ${CYAN}║${NC}"
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

    print_header "Configuration"
    print_success "Domain configured: $DOMAIN_NAME"
}

install_dependencies() {
    print_header "Installing System Dependencies"

    # Set non-interactive mode for all package installations
    export DEBIAN_FRONTEND=noninteractive

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing core utilities..."
    apt-get install -y -qq curl wget git gnupg2 lsb-release > /dev/null 2>&1
    print_success "Core utilities installed"

    print_step "Installing Python 3 and development tools..."
    apt-get install -y -qq python3 python3-pip python3-venv python3-dev python3-wheel > /dev/null 2>&1
    print_success "Python 3 installed"

    print_step "Installing Odoo system dependencies..."
    apt-get install -y -qq \
        libldap2-dev \
        libpq-dev \
        libsasl2-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg-dev \
        libfreetype6-dev \
        liblcms2-dev \
        libwebp-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libxcb1-dev \
        zlib1g-dev \
        build-essential > /dev/null 2>&1
    print_success "Odoo system dependencies installed"

    print_step "Installing Node.js for rtlcss..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null 2>&1
    npm install -g rtlcss > /dev/null 2>&1
    print_success "Node.js and rtlcss installed"

    print_step "Installing wkhtmltopdf for PDF generation..."
    apt-get install -y -qq wkhtmltopdf > /dev/null 2>&1
    print_success "wkhtmltopdf installed"

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
    print_header "Setting Up Odoo Database User"

    # Generate password if not already set
    if [[ -z "$DB_PASSWORD" ]]; then
        if [[ -f "$INSTALL_DIR/odoo.conf" ]]; then
            # Try to extract existing password from odoo.conf
            DB_PASSWORD=$(grep "^db_password" "$INSTALL_DIR/odoo.conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
        fi
        if [[ -z "$DB_PASSWORD" ]]; then
            DB_PASSWORD=$(generate_password)
        fi
    fi

    # Check if database user already exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        print_info "Database user '$DB_USER' already exists"
        print_warning "Existing database user password will NOT be changed to protect existing applications."
        print_info "If Odoo cannot connect to the database,"
        print_info "please manually update the password in odoo.conf or reset the database user password."
    else
        print_step "Creating database user '$DB_USER'..."
        sudo -u postgres psql -c "CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASSWORD' CREATEDB;" > /dev/null 2>&1
        print_success "Database user '$DB_USER' created"
    fi

    print_success "Database user setup completed"
    print_info "User: $DB_USER"
    print_info "Note: Odoo will create databases automatically as needed"
}

install_odoo() {
    print_header "Installing Odoo"

    # Create installation directory
    print_step "Creating installation directory..."
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR'"
    print_success "Installation directory created"

    # Check if Odoo repository already exists
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        print_info "Odoo repository already exists at $INSTALL_DIR"
        print_step "Updating Odoo repository..."

        # Reset any local changes and update
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git checkout ."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git fetch --all" > /dev/null 2>&1
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git checkout $ODOO_VERSION" > /dev/null 2>&1
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git pull origin $ODOO_VERSION" > /dev/null 2>&1
        print_success "Odoo repository updated"
    else
        print_step "Cloning Odoo repository (branch $ODOO_VERSION)..."
        su - "$CURRENT_USER" -c "git clone --depth 1 --branch $ODOO_VERSION https://github.com/odoo/odoo.git '$INSTALL_DIR'" > /dev/null 2>&1
        print_success "Odoo repository cloned"
    fi

    # Setup virtual environment
    print_step "Setting up Python virtual environment..."
    if [[ -d "$VENV_DIR" ]]; then
        print_info "Virtual environment already exists at $VENV_DIR"
        print_step "Using existing virtual environment..."
    else
        print_step "Creating virtual environment..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && python3 -m venv '$VENV_DIR'" > /dev/null 2>&1
        print_success "Virtual environment created"
    fi

    print_step "Upgrading pip..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install --upgrade pip" > /dev/null 2>&1
    print_success "Pip upgraded"

    print_step "Installing/updating Python dependencies (this may take a few minutes)..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install -r requirements.txt" > /dev/null 2>&1
    print_success "Python dependencies installed"

    print_info "Odoo installed at: $INSTALL_DIR"
}

create_config_file() {
    print_header "Creating Odoo Configuration"

    CONFIG_FILE="$INSTALL_DIR/odoo.conf"

    # Check if config file already exists
    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "Configuration file already exists at $CONFIG_FILE"

        # Update only essential fields
        if ! grep -q "^proxy_mode = True" "$CONFIG_FILE"; then
            print_step "Updating proxy_mode in configuration..."
            echo "proxy_mode = True" >> "$CONFIG_FILE"
            print_success "proxy_mode updated"
        fi

        print_success "Using existing configuration file"
        return
    fi

    print_step "Creating configuration file..."

    # Create Odoo configuration file
    cat > "$CONFIG_FILE" << EOF
[options]
; This is the password that allows database operations:
admin_passwd = $(generate_password)
db_host = localhost
db_port = 5432
db_user = $DB_USER
db_password = $DB_PASSWORD
addons_path = $INSTALL_DIR/addons
xmlrpc_port = $APP_PORT
proxy_mode = True
logfile = $INSTALL_DIR/odoo.log
log_level = info
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    print_success "Configuration file created with secure permissions"
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    # Check if service already exists
    if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
        print_info "Service '${SERVICE_NAME}.service' already exists"
        print_step "Reloading systemd and restarting service..."
        systemctl daemon-reload
        systemctl restart "${SERVICE_NAME}"
        systemctl enable "${SERVICE_NAME}" > /dev/null 2>&1
        print_success "Service restarted"
        return
    fi

    print_step "Creating service file..."

    tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Odoo Open Source ERP and CRM
After=network.target network-online.target postgresql.service
Requires=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python3 $INSTALL_DIR/odoo-bin -c $INSTALL_DIR/odoo.conf
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service file created"

    print_step "Starting Odoo service..."
    systemctl daemon-reload
    systemctl start "${SERVICE_NAME}"
    systemctl enable "${SERVICE_NAME}" > /dev/null 2>&1
    print_success "Odoo service started and enabled"

    # Wait for Odoo to start
    print_step "Waiting for Odoo to start..."
    sleep 5

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        print_success "Odoo is running"
    else
        print_warning "Odoo service may not have started properly"
        print_info "Check logs with: sudo journalctl -u ${SERVICE_NAME} -n 50"
    fi
}

configure_nginx() {
    print_header "Configuring Nginx"

    NGINX_CONF="/etc/nginx/sites-available/$DOMAIN_NAME"
    NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN_NAME"

    print_step "Creating Nginx configuration..."

    # Create initial HTTP configuration
    cat > "$NGINX_CONF" << EOF
# Odoo server
upstream odoo {
    server 127.0.0.1:$APP_PORT;
}

# HTTP server - will be updated by Certbot
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME;

    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;

    # Proxy settings
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    # Proxy headers
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    # Increase proxy buffer size
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    # Force timeouts if the backend dies
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

    # Enable data compression
    gzip on;
    gzip_min_length 1100;
    gzip_buffers 4 32k;
    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
    gzip_vary on;

    # Odoo web client
    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
    }

    # Odoo long polling
    location /longpolling {
        proxy_pass http://odoo;
    }

    # Cache static files
    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo;
    }
}
EOF

    print_success "Nginx configuration created"

    # Enable the site
    if [[ ! -L "$NGINX_ENABLED" ]]; then
        print_step "Enabling Nginx site..."
        ln -s "$NGINX_CONF" "$NGINX_ENABLED"
        print_success "Nginx site enabled"
    fi

    print_step "Testing Nginx configuration..."
    if nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi

    print_step "Reloading Nginx..."
    systemctl reload nginx
    print_success "Nginx reloaded"
}

setup_ssl() {
    print_header "Setting Up SSL Certificate"

    # Check if SSL certificate already exists
    if [[ -f "/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem" ]]; then
        print_info "SSL certificate already exists for $DOMAIN_NAME"
        print_step "Skipping SSL certificate creation..."
        print_success "Using existing SSL certificate"
        return
    fi

    print_step "Obtaining SSL certificate from Let's Encrypt..."
    print_info "This process will automatically configure Nginx for HTTPS"

    # Request certificate and configure Nginx automatically
    if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        print_success "SSL certificate obtained and configured"
    else
        print_warning "Failed to obtain SSL certificate"
        print_info "You may need to:"
        print_info "1. Ensure your domain DNS points to this server"
        print_info "2. Check if port 80 and 443 are open"
        print_info "3. Run certbot manually: sudo certbot --nginx -d $DOMAIN_NAME"
    fi
}

save_credentials() {
    print_header "Saving Credentials"

    CREDS_FILE="$HOME_DIR/odoo_credentials.txt"

    # Extract admin password from config
    ADMIN_PASSWD=$(grep "^admin_passwd" "$INSTALL_DIR/odoo.conf" | cut -d'=' -f2 | tr -d ' ')

    print_step "Creating credentials file..."

    cat > "$CREDS_FILE" << EOF
========================================
Odoo Installation Credentials
========================================
Installation Date: $(date)
Domain: $DOMAIN_NAME

Database Credentials:
---------------------
Database User: $DB_USER
Database Password: $DB_PASSWORD

Odoo Master Password:
--------------------
Master Password: $ADMIN_PASSWD
(This password is used for database management operations)

Access Information:
------------------
Web Interface: https://$DOMAIN_NAME
Default Login: admin
Default Password: admin
(Change this immediately after first login!)

Installation Directory: $INSTALL_DIR
Configuration File: $INSTALL_DIR/odoo.conf
Log File: $INSTALL_DIR/odoo.log

Service Management:
------------------
Start service: sudo systemctl start $SERVICE_NAME
Stop service: sudo systemctl stop $SERVICE_NAME
Restart service: sudo systemctl restart $SERVICE_NAME
View logs: sudo journalctl -u $SERVICE_NAME -f

========================================
IMPORTANT: Keep this file secure!
========================================
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$CREDS_FILE"
    chmod 600 "$CREDS_FILE"

    print_success "Credentials saved to: $CREDS_FILE"
    print_warning "Please keep this file secure and change default passwords!"
}

show_completion_message() {
    print_header "Installation Complete!"

    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}${WHITE}Odoo has been successfully installed!${NC}                                     ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}Access your Odoo instance:${NC}"
    echo -e "  ${CYAN}https://$DOMAIN_NAME${NC}"
    echo ""
    echo -e "${WHITE}Default credentials:${NC}"
    echo -e "  Username: ${YELLOW}admin${NC}"
    echo -e "  Password: ${YELLOW}admin${NC}"
    echo -e "  ${RED}⚠ Change these immediately after first login!${NC}"
    echo ""
    echo -e "${WHITE}Service management:${NC}"
    echo -e "  Start:   ${CYAN}sudo systemctl start $SERVICE_NAME${NC}"
    echo -e "  Stop:    ${CYAN}sudo systemctl stop $SERVICE_NAME${NC}"
    echo -e "  Restart: ${CYAN}sudo systemctl restart $SERVICE_NAME${NC}"
    echo -e "  Status:  ${CYAN}sudo systemctl status $SERVICE_NAME${NC}"
    echo -e "  Logs:    ${CYAN}sudo journalctl -u $SERVICE_NAME -f${NC}"
    echo ""
    echo -e "${WHITE}Credentials file:${NC}"
    echo -e "  ${CYAN}$HOME_DIR/odoo_credentials.txt${NC}"
    echo ""
    echo -e "${MAGENTA}For documentation and support, visit:${NC}"
    echo -e "  ${CYAN}https://www.odoo.com/documentation${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Main execution
#-------------------------------------------------------------------------------

main() {
    show_banner
    check_root
    check_ubuntu
    parse_arguments "$@"
    setup_installer_user
    install_dependencies
    install_postgresql
    setup_database
    install_odoo
    create_config_file
    create_systemd_service
    configure_nginx
    setup_ssl
    save_credentials
    show_completion_message
}

main "$@"
