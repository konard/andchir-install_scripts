#!/bin/bash

#===============================================================================
#
#   Form.io + MongoDB - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Node.js 20.x (LTS)
#   - MongoDB 8.0 database
#   - Form.io form and API platform (from source)
#   - Nginx as reverse proxy
#   - SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/formio/formio
#   Documentation: https://github.com/formio/formio#readme
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
APP_NAME="formio"
SERVICE_NAME="formio"
INSTALLER_USER="installer_user"
APP_PORT="3001"
NODE_VERSION="20"
MONGODB_VERSION="8.0"
REPO_URL="https://github.com/formio/formio.git"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""

# Database credentials (will be generated)
DB_NAME="formio"
DB_USER="formio"
DB_PASSWORD=""

# Form.io configuration
ADMIN_EMAIL="admin@example.com"
ADMIN_PASSWORD=""
JWT_SECRET=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name>"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for Form.io (e.g., forms.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 forms.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., forms.example.com)"
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

generate_jwt_secret() {
    # Generate a secure JWT secret (64 characters)
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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Form.io + MongoDB${NC}                                                       ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Node.js ${NODE_VERSION}.x (LTS)                                                     ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} MongoDB ${MONGODB_VERSION} database                                                  ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Form.io form and API platform                                         ${CYAN}║${NC}"
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
    apt-get install -y -qq \
        curl \
        wget \
        git \
        build-essential \
        nginx \
        certbot \
        python3-certbot-nginx \
        gnupg \
        ca-certificates \
        apt-transport-https \
        software-properties-common > /dev/null 2>&1
    print_success "System packages installed"
}

install_nodejs() {
    print_header "Installing Node.js ${NODE_VERSION}.x"

    # Check if Node.js is already installed
    if command -v node &> /dev/null; then
        CURRENT_NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ "$CURRENT_NODE_VERSION" == "$NODE_VERSION" ]]; then
            print_info "Node.js ${NODE_VERSION}.x is already installed"
            print_info "Version: $(node -v)"
            return
        else
            print_warning "Different Node.js version detected: $(node -v)"
            print_step "Installing Node.js ${NODE_VERSION}.x..."
        fi
    fi

    print_step "Adding NodeSource repository..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - > /dev/null 2>&1
    print_success "NodeSource repository added"

    print_step "Installing Node.js..."
    apt-get install -y -qq nodejs > /dev/null 2>&1
    print_success "Node.js installed: $(node -v)"
    print_success "npm installed: $(npm -v)"

    # Install yarn globally
    print_step "Installing Yarn package manager..."
    npm install -g yarn > /dev/null 2>&1
    print_success "Yarn installed: $(yarn -v)"
}

install_mongodb() {
    print_header "Installing MongoDB ${MONGODB_VERSION}"

    # Check if MongoDB is already installed
    if systemctl is-active --quiet mongod; then
        print_info "MongoDB is already installed and running"
        return
    fi

    print_step "Adding MongoDB GPG key..."
    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc | \
        gpg --dearmor -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg > /dev/null 2>&1
    print_success "MongoDB GPG key added"

    print_step "Adding MongoDB repository..."
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/${MONGODB_VERSION} multiverse" | \
        tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list > /dev/null
    print_success "MongoDB repository added"

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing MongoDB..."
    apt-get install -y -qq mongodb-org > /dev/null 2>&1
    print_success "MongoDB installed"

    print_step "Starting MongoDB service..."
    systemctl start mongod
    systemctl enable mongod > /dev/null 2>&1
    print_success "MongoDB service started and enabled"
}

setup_mongodb_database() {
    print_header "Setting Up MongoDB Database"

    # Generate database password
    DB_PASSWORD=$(generate_password)

    print_step "Creating database user '$DB_USER'..."

    # Check if user already exists
    USER_EXISTS=$(sudo -u mongodb mongosh --quiet --eval "db.getSiblingDB('admin').getUser('$DB_USER')" 2>/dev/null | grep -c "\"user\" : \"$DB_USER\"" || true)

    if [[ "$USER_EXISTS" -gt 0 ]]; then
        print_info "Database user '$DB_USER' already exists"
    else
        # Create database user with readWrite role
        sudo -u mongodb mongosh --quiet <<EOF > /dev/null
use $DB_NAME
db.createUser({
  user: "$DB_USER",
  pwd: "$DB_PASSWORD",
  roles: [
    { role: "readWrite", db: "$DB_NAME" }
  ]
})
EOF
        print_success "Database user '$DB_USER' created"
    fi

    print_success "Database '$DB_NAME' configured"
}

clone_repository() {
    print_header "Cloning Form.io Repository"

    if [[ -d "$INSTALL_DIR" ]]; then
        print_info "Repository already exists at $INSTALL_DIR"
        print_step "Updating repository..."

        # Execute git commands as installer_user
        sudo -u "$INSTALLER_USER" bash <<EOF
cd "$INSTALL_DIR"
git checkout . > /dev/null 2>&1
git pull > /dev/null 2>&1
EOF
        print_success "Repository updated"
    else
        print_step "Cloning repository from $REPO_URL..."
        sudo -u "$INSTALLER_USER" git clone "$REPO_URL" "$INSTALL_DIR" > /dev/null 2>&1
        print_success "Repository cloned"
    fi

    print_info "Installation directory: $INSTALL_DIR"
}

install_application() {
    print_header "Installing Form.io Application"

    print_step "Installing dependencies..."
    sudo -u "$INSTALLER_USER" bash <<EOF
cd "$INSTALL_DIR"
yarn install > /dev/null 2>&1
EOF
    print_success "Dependencies installed"

    print_step "Building VM module..."
    sudo -u "$INSTALLER_USER" bash <<EOF
cd "$INSTALL_DIR"
yarn build:vm > /dev/null 2>&1
EOF
    print_success "VM module built"

    print_step "Building portal..."
    sudo -u "$INSTALLER_USER" bash <<EOF
cd "$INSTALL_DIR"
yarn build:portal > /dev/null 2>&1
EOF
    print_success "Portal built"
}

configure_environment() {
    print_header "Configuring Environment Variables"

    # Generate credentials if not already set
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        ADMIN_PASSWORD=$(generate_password)
    fi
    if [[ -z "$JWT_SECRET" ]]; then
        JWT_SECRET=$(generate_jwt_secret)
    fi

    ENV_FILE="$INSTALL_DIR/.env"

    print_step "Creating environment configuration..."

    # Create or update .env file
    sudo -u "$INSTALLER_USER" cat > "$ENV_FILE" <<EOF
# MongoDB Configuration
MONGO_URL=mongodb://localhost:27017/$DB_NAME
MONGO_HIGH_AVAILABILITY=false

# Server Configuration
PORT=$APP_PORT
NODE_ENV=production

# Admin User Configuration
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASS=$ADMIN_PASSWORD

# Security Configuration
JWT_SECRET=$JWT_SECRET

# Form.io Configuration
FORMIO_FILES_SERVER=https://$DOMAIN_NAME

# Debug (disabled in production)
DEBUG=

# Node.js Configuration
NODE_OPTIONS=--no-node-snapshot
EOF

    print_success "Environment configuration created"
    print_info "Configuration file: $ENV_FILE"
}

setup_systemd_service() {
    print_header "Setting Up Systemd Service"

    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    print_step "Creating systemd service file..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Form.io Form and API Platform
After=network.target mongod.service
Wants=mongod.service

[Service]
Type=simple
User=$INSTALLER_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=/usr/bin/node --no-node-snapshot main.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    print_success "Systemd service file created"

    print_step "Reloading systemd daemon..."
    systemctl daemon-reload
    print_success "Systemd daemon reloaded"

    # Check if service is already running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_step "Restarting $SERVICE_NAME service..."
        systemctl restart "$SERVICE_NAME"
        print_success "Service restarted"
    else
        print_step "Starting $SERVICE_NAME service..."
        systemctl start "$SERVICE_NAME"
        print_success "Service started"
    fi

    print_step "Enabling $SERVICE_NAME service..."
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1
    print_success "Service enabled"

    sleep 3

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "$SERVICE_NAME service is running"
    else
        print_error "$SERVICE_NAME service failed to start"
        print_info "Check logs with: journalctl -u $SERVICE_NAME -n 50"
        exit 1
    fi
}

configure_nginx() {
    print_header "Configuring Nginx"

    NGINX_CONFIG="/etc/nginx/sites-available/$DOMAIN_NAME"
    NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN_NAME"

    print_step "Creating Nginx configuration..."

    cat > "$NGINX_CONFIG" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME;

    # Logs
    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;

    # Redirect all HTTP traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }

    # Let's Encrypt verification
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME;

    # Logs
    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;

    # SSL certificates (will be configured by certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy settings
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;

        # Increase timeouts for long-running requests
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
    }

    # Increase body size limit for file uploads
    client_max_body_size 50M;
}
EOF

    print_success "Nginx configuration created"

    # Enable site if not already enabled
    if [[ ! -L "$NGINX_ENABLED" ]]; then
        print_step "Enabling Nginx site..."
        ln -s "$NGINX_CONFIG" "$NGINX_ENABLED"
        print_success "Nginx site enabled"
    else
        print_info "Nginx site already enabled"
    fi

    print_step "Testing Nginx configuration..."
    nginx -t > /dev/null 2>&1
    print_success "Nginx configuration is valid"

    print_step "Reloading Nginx..."
    systemctl reload nginx
    print_success "Nginx reloaded"
}

setup_ssl() {
    print_header "Setting Up SSL Certificate"

    # Check if certificate already exists
    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_info "SSL certificate already exists for $DOMAIN_NAME"
        print_warning "Skipping certificate creation"
        return
    fi

    print_step "Obtaining SSL certificate from Let's Encrypt..."
    print_info "This may take a moment..."

    certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect > /dev/null 2>&1

    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_success "SSL certificate obtained successfully"
    else
        print_error "Failed to obtain SSL certificate"
        print_warning "You may need to configure DNS and try again"
        print_info "Manual setup: certbot --nginx -d $DOMAIN_NAME"
    fi
}

generate_report() {
    print_header "Installation Complete!"

    REPORT_FILE="$HOME_DIR/${APP_NAME}_installation_report.txt"

    cat > "$REPORT_FILE" <<EOF
================================================================================
Form.io Installation Report
================================================================================
Installation Date: $(date)
Domain: $DOMAIN_NAME
Installation Directory: $INSTALL_DIR

================================================================================
Access Information
================================================================================
URL: https://$DOMAIN_NAME
Admin Email: $ADMIN_EMAIL
Admin Password: $ADMIN_PASSWORD

================================================================================
Database Information
================================================================================
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASSWORD
MongoDB URL: mongodb://localhost:27017/$DB_NAME

================================================================================
Security Information
================================================================================
JWT Secret: $JWT_SECRET

================================================================================
Service Management
================================================================================
View logs:
  sudo journalctl -u $SERVICE_NAME -f

Restart service:
  sudo systemctl restart $SERVICE_NAME

Stop service:
  sudo systemctl stop $SERVICE_NAME

Start service:
  sudo systemctl start $SERVICE_NAME

Check service status:
  sudo systemctl status $SERVICE_NAME

================================================================================
Nginx Management
================================================================================
Test configuration:
  sudo nginx -t

Reload Nginx:
  sudo systemctl reload nginx

Access logs:
  sudo tail -f /var/log/nginx/${DOMAIN_NAME}_access.log

Error logs:
  sudo tail -f /var/log/nginx/${DOMAIN_NAME}_error.log

================================================================================
SSL Certificate
================================================================================
Certificate location: /etc/letsencrypt/live/$DOMAIN_NAME/
Auto-renewal: Configured via certbot

Renew manually:
  sudo certbot renew

================================================================================
IMPORTANT SECURITY NOTES
================================================================================
1. Change the default admin password immediately after first login
2. Keep the JWT secret secure and never share it
3. Regular backups of MongoDB database are recommended
4. Keep all software components up to date

================================================================================
EOF

    chown "$INSTALLER_USER:$INSTALLER_USER" "$REPORT_FILE"
    chmod 600 "$REPORT_FILE"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}${WHITE}Installation Summary${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}Form.io URL:${NC}       ${CYAN}https://$DOMAIN_NAME${NC}"
    echo -e "${WHITE}Admin Email:${NC}       ${CYAN}$ADMIN_EMAIL${NC}"
    echo -e "${WHITE}Admin Password:${NC}    ${CYAN}$ADMIN_PASSWORD${NC}"
    echo ""
    echo -e "${WHITE}Database:${NC}          ${CYAN}$DB_NAME${NC}"
    echo -e "${WHITE}DB User:${NC}           ${CYAN}$DB_USER${NC}"
    echo -e "${WHITE}DB Password:${NC}       ${CYAN}$DB_PASSWORD${NC}"
    echo ""
    echo -e "${YELLOW}⚠${NC}  ${WHITE}Full installation report saved to:${NC}"
    echo -e "   ${CYAN}$REPORT_FILE${NC}"
    echo ""
    echo -e "${GREEN}✔${NC}  ${GREEN}Form.io is now running and accessible!${NC}"
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

    install_dependencies
    install_nodejs
    install_mongodb
    setup_installer_user
    setup_mongodb_database
    clone_repository
    install_application
    configure_environment
    setup_systemd_service
    configure_nginx
    setup_ssl
    generate_report
}

# Run main function
main "$@"
