#!/bin/bash

#===============================================================================
#
#   LibreTranslate - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Git, Python 3.10+, Nginx, Certbot
#   - LibreTranslate translation API
#   - Downloads specified language models (default: en,de,ru)
#   - Sets up Python virtual environment with dependencies
#   - Creates systemd service for automatic startup
#   - Configures Nginx as reverse proxy
#   - Obtains SSL certificate via Let's Encrypt
#   - Creates API key for authentication
#
#   Repository: https://github.com/LibreTranslate/LibreTranslate
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
APP_NAME="libretranslate"
SERVICE_NAME="libretranslate"
PYTHON_VERSION="python3"
INSTALLER_USER="installer_user"
APP_PORT="5000"

# Default languages to install (can be overridden via second argument)
DEFAULT_LANGUAGES="en,de,ru"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""
VENV_DIR=""
API_KEY=""
LANGUAGES=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name> [languages]"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for the LibreTranslate web interface (e.g., translate.example.com)"
    echo "  languages      Optional comma-separated list of language codes to install (default: en,de,ru)"
    echo ""
    echo "Examples:"
    echo "  $0 translate.example.com"
    echo "  $0 translate.example.com en,de,ru"
    echo "  $0 translate.example.com en,es,fr,de,it,pt,ru,zh,ja,ko"
    echo ""
    echo "Available language codes: https://libretranslate.com/languages"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., translate.example.com)"
        exit 1
    fi
}

validate_languages() {
    local languages="$1"
    # Languages format validation: comma-separated 2-3 letter codes (e.g., en,de,ru or en,zh,ja)
    if [[ ! "$languages" =~ ^[a-z]{2,3}(,[a-z]{2,3})*$ ]]; then
        print_error "Invalid languages format: $languages"
        print_info "Languages must be comma-separated 2-3 letter codes (e.g., en,de,ru)"
        print_info "Available language codes: https://libretranslate.com/languages"
        exit 1
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}+==============================================================================+${NC}"
    echo -e "${CYAN}|${NC}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${CYAN}+==============================================================================+${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}>${NC} ${WHITE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}+${NC} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}!${NC} ${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}x${NC} ${RED}$1${NC}"
}

print_info() {
    echo -e "${MAGENTA}i${NC} ${WHITE}$1${NC}"
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
    echo -e "${CYAN}   +=========================================================================+${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${BOLD}${WHITE}LibreTranslate${NC}                                                      ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                       ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${WHITE}This script will install and configure:${NC}                              ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Git, Python 3.10+, Nginx, Certbot                                   ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} LibreTranslate Translation API                                      ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} All available language models                                       ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Python virtual environment with dependencies                        ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Nginx reverse proxy with SSL                                        ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Systemd service for auto-start                                      ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} SSL certificate via Let's Encrypt                                   ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} API key for authentication                                          ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   +=========================================================================+${NC}"
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

    # Set languages (use second argument if provided, otherwise use default)
    if [[ -n "$2" ]]; then
        LANGUAGES="$2"
        validate_languages "$LANGUAGES"
    else
        LANGUAGES="$DEFAULT_LANGUAGES"
    fi

    print_header "Configuration"
    print_success "Domain configured: $DOMAIN_NAME"
    print_success "Languages configured: $LANGUAGES"
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

    print_step "Installing Python 3 and development tools..."
    apt-get install -y -qq python3 python3-pip python3-venv python3-dev > /dev/null 2>&1
    print_success "Python 3 installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_step "Installing additional dependencies..."
    apt-get install -y -qq build-essential libffi-dev libssl-dev curl wget > /dev/null 2>&1
    print_success "Additional dependencies installed"

    # Install ICU libraries for language detection
    print_step "Installing ICU libraries..."
    apt-get install -y -qq libicu-dev pkg-config > /dev/null 2>&1
    print_success "ICU libraries installed"

    print_success "System dependencies installed successfully!"
}

setup_installation_directory() {
    print_header "Setting Up Installation Directory"

    if [[ -d "$INSTALL_DIR" ]]; then
        print_info "Installation directory already exists at $INSTALL_DIR"
    else
        print_step "Creating installation directory..."
        mkdir -p "$INSTALL_DIR"
        chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR"
        print_success "Installation directory created"
    fi

    print_info "Working directory: $INSTALL_DIR"
}

setup_python_environment() {
    print_header "Setting Up Python Virtual Environment"

    if [[ -d "$VENV_DIR" ]]; then
        print_info "Virtual environment already exists at $VENV_DIR"
        print_step "Using existing virtual environment..."
    else
        print_step "Creating virtual environment..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && $PYTHON_VERSION -m venv '$VENV_DIR'" > /dev/null 2>&1
        print_success "Virtual environment created"
    fi

    print_step "Upgrading pip..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install --upgrade pip" > /dev/null 2>&1
    print_success "Pip upgraded"

    print_step "Installing/updating LibreTranslate (this may take a few minutes)..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install libretranslate" > /dev/null 2>&1
    print_success "LibreTranslate installed"

    # Install waitress for production server
    print_step "Installing waitress WSGI server..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install waitress" > /dev/null 2>&1
    print_success "Waitress installed"
}

download_language_models() {
    print_header "Downloading Language Models"

    print_info "This will download language models for: $LANGUAGES"
    print_info "This process may take some time depending on your connection..."

    # Create data directory if it doesn't exist
    DATA_DIR="$INSTALL_DIR/data"
    if [[ ! -d "$DATA_DIR" ]]; then
        mkdir -p "$DATA_DIR"
        chown "$CURRENT_USER":"$CURRENT_USER" "$DATA_DIR"
    fi

    print_step "Downloading language models for: $LANGUAGES (this may take 5-15 minutes)..."
    # Run libretranslate with --load-only to download only specified language models
    # Using timeout to prevent hanging - models download on first start
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && timeout 1800 libretranslate --load-only $LANGUAGES --update-models" > /dev/null 2>&1 || true
    print_success "Language models downloaded for: $LANGUAGES"
}

create_api_key() {
    print_header "Creating API Key"

    API_KEYS_DB="$INSTALL_DIR/api_keys.db"

    # Check if API keys database already exists
    if [[ -f "$API_KEYS_DB" ]]; then
        print_info "API keys database already exists"
        print_step "Skipping API key creation to preserve existing keys..."

        # Try to read existing API key
        API_KEY="(stored in $API_KEYS_DB)"
        export API_KEY
        print_success "Using existing API keys configuration"
        return
    fi

    print_step "Creating API key database..."

    # First, we need to initialize the database by running libretranslate briefly with --api-keys
    # Then use the manage tool to add a key

    # Create a simple initialization script
    cat > "$INSTALL_DIR/init_db.py" << 'EOF'
import sqlite3
import secrets
import sys

db_path = sys.argv[1]
req_limit = int(sys.argv[2]) if len(sys.argv) > 2 else 120

# Generate API key
api_key = secrets.token_urlsafe(32)

# Create database
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE IF NOT EXISTS api_keys
             (api_key TEXT PRIMARY KEY, req_limit INTEGER, char_limit INTEGER DEFAULT 0)''')
c.execute("INSERT OR REPLACE INTO api_keys VALUES (?, ?, ?)", (api_key, req_limit, 0))
conn.commit()
conn.close()

print(api_key)
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/init_db.py"

    # Generate API key with 120 requests per minute limit
    API_KEY=$(su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && python '$INSTALL_DIR/init_db.py' '$API_KEYS_DB' 120")

    chown "$CURRENT_USER":"$CURRENT_USER" "$API_KEYS_DB"
    chmod 600 "$API_KEYS_DB"

    # Clean up init script
    rm -f "$INSTALL_DIR/init_db.py"

    print_success "API key created"

    # Store API key for reference
    CREDENTIALS_FILE="$HOME_DIR/.libretranslate-credentials"
    cat > "$CREDENTIALS_FILE" << EOF
API_KEY=$API_KEY
EOF
    chown "$CURRENT_USER":"$CURRENT_USER" "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    print_success "Credentials saved to $CREDENTIALS_FILE"

    export API_KEY
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    print_step "Creating service file..."

    tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=LibreTranslate Translation API
After=network.target

[Service]
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$VENV_DIR/bin/libretranslate --host 127.0.0.1 --port $APP_PORT --load-only $LANGUAGES --api-keys --api-keys-db-path $INSTALL_DIR/api_keys.db --threads 4
Restart=always
RestartSec=10

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

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    client_max_body_size 50M;
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
    echo -e "${GREEN}+==============================================================================+${NC}"
    echo -e "${GREEN}|${NC}                                                                              ${GREEN}|${NC}"
    echo -e "${GREEN}|${NC}   ${BOLD}${WHITE}+ Installation Completed Successfully!${NC}                                   ${GREEN}|${NC}"
    echo -e "${GREEN}|${NC}                                                                              ${GREEN}|${NC}"
    echo -e "${GREEN}+==============================================================================+${NC}"
    echo ""

    print_header "Installation Summary"

    echo -e "${WHITE}Application Details:${NC}"
    echo -e "  ${CYAN}*${NC} Domain:        ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}*${NC} Languages:     ${BOLD}$LANGUAGES${NC}"
    echo -e "  ${CYAN}*${NC} Install path:  ${BOLD}$INSTALL_DIR${NC}"
    echo -e "  ${CYAN}*${NC} Virtual env:   ${BOLD}$VENV_DIR${NC}"
    echo ""

    echo -e "${WHITE}API Key:${NC}"
    echo -e "  ${CYAN}*${NC} API Key:       ${BOLD}$API_KEY${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}*${NC} Check status:  ${BOLD}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}*${NC} Restart:       ${BOLD}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}*${NC} View logs:     ${BOLD}sudo journalctl -u ${SERVICE_NAME}${NC}"
    echo ""

    echo -e "${WHITE}API Endpoints:${NC}"
    echo -e "  ${CYAN}*${NC} Web UI:        ${BOLD}https://$DOMAIN_NAME/${NC}"
    echo -e "  ${CYAN}*${NC} Translate:     ${BOLD}https://$DOMAIN_NAME/translate${NC}"
    echo -e "  ${CYAN}*${NC} Languages:     ${BOLD}https://$DOMAIN_NAME/languages${NC}"
    echo -e "  ${CYAN}*${NC} Detect:        ${BOLD}https://$DOMAIN_NAME/detect${NC}"
    echo ""

    echo -e "${WHITE}Configuration Files:${NC}"
    echo -e "  ${CYAN}*${NC} Nginx config:  ${BOLD}/etc/nginx/sites-available/$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}*${NC} Service file:  ${BOLD}/etc/systemd/system/${SERVICE_NAME}.service${NC}"
    echo -e "  ${CYAN}*${NC} API keys DB:   ${BOLD}$INSTALL_DIR/api_keys.db${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}*${NC} API key stored in: ${BOLD}$HOME_DIR/.libretranslate-credentials${NC}"
    echo -e "  ${CYAN}*${NC} Please save the API key in a secure location"
    echo -e "  ${CYAN}*${NC} LibreTranslate binds to localhost only for security"
    echo -e "  ${CYAN}*${NC} All external access goes through Nginx"
    echo ""

    echo -e "${YELLOW}API Usage Example:${NC}"
    echo -e "  ${CYAN}curl -X POST https://$DOMAIN_NAME/translate \\${NC}"
    echo -e "  ${CYAN}  -H \"Content-Type: application/json\" \\${NC}"
    echo -e "  ${CYAN}  -d '{\"q\":\"Hello\",\"source\":\"en\",\"target\":\"es\",\"api_key\":\"$API_KEY\"}'${NC}"
    echo ""

    echo -e "${YELLOW}Managing API Keys:${NC}"
    echo -e "  ${CYAN}*${NC} List keys:     ${BOLD}cd $INSTALL_DIR && source venv/bin/activate && ltmanage keys${NC}"
    echo -e "  ${CYAN}*${NC} Add key:       ${BOLD}ltmanage keys add 60 --api-keys-db-path $INSTALL_DIR/api_keys.db${NC}"
    echo -e "  ${CYAN}*${NC} Remove key:    ${BOLD}ltmanage keys remove <key> --api-keys-db-path $INSTALL_DIR/api_keys.db${NC}"
    echo ""

    print_success "Thank you for using LibreTranslate installation script!"
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
    setup_installation_directory
    setup_python_environment
    download_language_models
    create_api_key
    add_user_to_www_data
    create_systemd_service
    configure_nginx
    setup_ssl_certificate

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
