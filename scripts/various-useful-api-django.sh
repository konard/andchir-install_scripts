#!/bin/bash

#===============================================================================
#
#   Various Useful API Django - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Git, Python 3, MySQL, Nginx, Certbot
#   - Clones the various-useful-api-django repository
#   - Sets up Python virtual environment with all dependencies
#   - Configures MySQL database
#   - Creates systemd services for automatic startup
#   - Configures Nginx as reverse proxy
#   - Obtains SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/andchir/various-useful-api-django
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
REPO_URL="https://github.com/andchir/various-useful-api-django.git"
APP_NAME="various-useful-api-django"
SERVICE_NAME="various-useful-apis"
SOCKET_PATH="/run/gunicorn_various_useful_apis.sock"
PYTHON_VERSION="python3"
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo ~$CURRENT_USER)
INSTALL_DIR="$HOME_DIR/$APP_NAME"
VENV_DIR="$INSTALL_DIR/venv"

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

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

generate_secret_key() {
    # Generate Django secret key
    openssl rand -base64 48 | tr -d '/+='
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root!"
        print_info "Run as a regular user with sudo privileges."
        exit 1
    fi
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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Various Useful API Django${NC}                                             ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Git, Python 3, MySQL Server, Nginx, Certbot                          ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Django application with virtual environment                          ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Systemd services for auto-start                                      ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} SSL certificate via Let's Encrypt                                    ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

get_domain_name() {
    print_header "Domain Configuration"

    while true; do
        echo -e "${WHITE}Please enter your domain name (e.g., api.example.com):${NC}"
        echo -n -e "${CYAN}➜ ${NC}"
        read -r DOMAIN_NAME

        # Validate domain name format
        if [[ -z "$DOMAIN_NAME" ]]; then
            print_error "Domain name cannot be empty. Please try again."
            continue
        fi

        # Basic domain validation regex
        if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid domain format. Please enter a valid domain (e.g., api.example.com)"
            continue
        fi

        echo ""
        print_info "Domain name: ${BOLD}$DOMAIN_NAME${NC}"
        echo -e "${WHITE}Is this correct? (y/n):${NC} "
        read -r confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        fi
    done

    print_success "Domain configured: $DOMAIN_NAME"
}

install_dependencies() {
    print_header "Installing System Dependencies"

    print_step "Updating package lists..."
    sudo apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing Git..."
    sudo apt-get install -y -qq git > /dev/null 2>&1
    print_success "Git installed"

    print_step "Installing Python 3 and development tools..."
    sudo apt-get install -y -qq python3 python3-pip python3-venv python3-dev > /dev/null 2>&1
    print_success "Python 3 installed"

    print_step "Installing MySQL Server..."
    # Set non-interactive mode for MySQL installation
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server libmysqlclient-dev pkg-config > /dev/null 2>&1
    print_success "MySQL Server installed"

    print_step "Installing Nginx..."
    sudo apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    sudo apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_step "Installing additional dependencies..."
    sudo apt-get install -y -qq build-essential libffi-dev libssl-dev > /dev/null 2>&1
    print_success "Additional dependencies installed"

    print_success "All system dependencies installed successfully!"
}

clone_repository() {
    print_header "Cloning Repository"

    if [[ -d "$INSTALL_DIR" ]]; then
        print_warning "Directory $INSTALL_DIR already exists."
        print_step "Backing up existing directory..."
        sudo mv "$INSTALL_DIR" "${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        print_success "Backup created"
    fi

    print_step "Cloning repository to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR" > /dev/null 2>&1
    print_success "Repository cloned successfully"

    cd "$INSTALL_DIR"
    print_info "Working directory: $INSTALL_DIR"
}

setup_python_environment() {
    print_header "Setting Up Python Virtual Environment"

    cd "$INSTALL_DIR"

    print_step "Creating virtual environment..."
    $PYTHON_VERSION -m venv "$VENV_DIR"
    print_success "Virtual environment created"

    print_step "Activating virtual environment..."
    source "$VENV_DIR/bin/activate"
    print_success "Virtual environment activated"

    print_step "Upgrading pip..."
    pip install --upgrade pip > /dev/null 2>&1
    print_success "Pip upgraded"

    print_step "Installing Python dependencies (this may take a few minutes)..."
    pip install -r requirements.txt > /dev/null 2>&1
    print_success "All Python dependencies installed"

    deactivate
}

configure_mysql() {
    print_header "Configuring MySQL Database"

    DB_NAME="various_useful_apis"
    DB_USER="various_api_user"
    DB_PASSWORD=$(generate_password)

    print_step "Starting MySQL service..."
    sudo systemctl start mysql
    sudo systemctl enable mysql > /dev/null 2>&1
    print_success "MySQL service started"

    print_step "Creating database and user..."

    # Create database and user
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"

    print_success "Database '$DB_NAME' created"
    print_success "User '$DB_USER' created with privileges"

    # Save credentials for later use
    export DB_NAME DB_USER DB_PASSWORD
}

create_env_file() {
    print_header "Creating Environment Configuration"

    cd "$INSTALL_DIR"

    DJANGO_SECRET_KEY=$(generate_secret_key)

    print_step "Creating .env file..."

    cat > .env << EOF
APP_ENV=prod
MYSQL_DATABASE_NAME=$DB_NAME
MYSQL_DATABASE_USER=$DB_USER
MYSQL_DATABASE_PASSWORD=$DB_PASSWORD
SSL_CERT_PATH=/etc/letsencrypt/live/$DOMAIN_NAME/
EMAIL_HOST=
EMAIL_PORT=465
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
EMAIL_USE_TLS=False
EMAIL_USE_SSL=True
ALLOWED_HOSTS=127.0.0.1,localhost,$DOMAIN_NAME
ADMIN_LOG_OWNER_SECTION_NAME=Log owners
SECRET_KEY=$DJANGO_SECRET_KEY
EOF

    chmod 600 .env
    print_success ".env file created with secure permissions"

    print_info "Database credentials saved in .env file"
}

run_django_setup() {
    print_header "Running Django Setup"

    cd "$INSTALL_DIR"
    source "$VENV_DIR/bin/activate"

    print_step "Running database migrations..."
    python manage.py migrate > /dev/null 2>&1
    print_success "Database migrations completed"

    print_step "Collecting static files..."
    python manage.py collectstatic --noinput > /dev/null 2>&1
    print_success "Static files collected"

    # Create cache directory
    mkdir -p django_cache
    chmod 755 django_cache

    # Create media directory
    mkdir -p media
    chmod 755 media

    deactivate
    print_success "Django setup completed"
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    print_step "Creating socket file..."

    sudo tee /etc/systemd/system/${SERVICE_NAME}.socket > /dev/null << EOF
[Unit]
Description=gunicorn socket for $APP_NAME

[Socket]
ListenStream=$SOCKET_PATH
SocketUser=www-data
SocketMode=600

[Install]
WantedBy=sockets.target
EOF

    print_success "Socket file created"

    print_step "Creating service file..."

    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=gunicorn daemon for $APP_NAME
Requires=${SERVICE_NAME}.socket
After=network.target

[Service]
User=$CURRENT_USER
Group=www-data
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/gunicorn \\
          --access-logfile - \\
          --error-logfile '$INSTALL_DIR/gunicorn-errors.txt' \\
          --timeout 120 \\
          --workers 3 \\
          --bind unix:$SOCKET_PATH \\
          app.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service file created"

    print_step "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    print_success "Systemd daemon reloaded"

    print_step "Enabling and starting socket..."
    sudo systemctl enable ${SERVICE_NAME}.socket > /dev/null 2>&1
    sudo systemctl start ${SERVICE_NAME}.socket
    print_success "Socket enabled and started"

    print_step "Starting service..."
    sudo systemctl start ${SERVICE_NAME}.service
    print_success "Service started"
}

configure_nginx() {
    print_header "Configuring Nginx"

    print_step "Creating Nginx configuration..."

    sudo tee /etc/nginx/sites-available/$DOMAIN_NAME > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    # Redirect HTTP to HTTPS (will be enabled after SSL setup)
    # return 301 https://\$server_name\$request_uri;

    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location /static/ {
        alias $INSTALL_DIR/static/;
    }

    location /media/ {
        alias $INSTALL_DIR/media/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$SOCKET_PATH;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    client_max_body_size 100M;
}
EOF

    print_success "Nginx configuration created"

    print_step "Enabling site..."
    sudo ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
    print_success "Site enabled"

    print_step "Testing Nginx configuration..."
    if sudo nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        sudo nginx -t
        exit 1
    fi

    print_step "Restarting Nginx..."
    sudo systemctl restart nginx
    print_success "Nginx restarted"
}

setup_ssl_certificate() {
    print_header "Setting Up SSL Certificate"

    print_info "Obtaining SSL certificate from Let's Encrypt..."
    print_warning "Make sure DNS is properly configured and pointing to this server!"
    echo ""

    print_step "Running Certbot..."

    # Run certbot with automatic configuration
    if sudo certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        print_success "SSL certificate obtained and configured"

        print_step "Setting up automatic renewal..."
        sudo systemctl enable certbot.timer > /dev/null 2>&1
        sudo systemctl start certbot.timer
        print_success "Automatic certificate renewal enabled"
    else
        print_warning "SSL certificate setup failed. You can run it manually later:"
        print_info "sudo certbot --nginx -d $DOMAIN_NAME"
    fi
}

add_user_to_www_data() {
    print_header "Configuring User Permissions"

    print_step "Adding $CURRENT_USER to www-data group..."
    sudo usermod -aG www-data $CURRENT_USER
    print_success "User added to www-data group"

    print_step "Setting directory permissions..."
    sudo chown -R $CURRENT_USER:www-data "$INSTALL_DIR"
    sudo chmod -R 755 "$INSTALL_DIR"
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
    echo -e "  ${CYAN}•${NC} Virtual env:   ${BOLD}$VENV_DIR${NC}"
    echo ""

    echo -e "${WHITE}Database Details:${NC}"
    echo -e "  ${CYAN}•${NC} Database:      ${BOLD}$DB_NAME${NC}"
    echo -e "  ${CYAN}•${NC} User:          ${BOLD}$DB_USER${NC}"
    echo -e "  ${CYAN}•${NC} Password:      ${BOLD}(stored in .env file)${NC}"
    echo ""

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}•${NC} Check status:  ${BOLD}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} Restart:       ${BOLD}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} View logs:     ${BOLD}sudo journalctl -u ${SERVICE_NAME}${NC}"
    echo ""

    echo -e "${WHITE}API Endpoints:${NC}"
    echo -e "  ${CYAN}•${NC} Swagger UI:    ${BOLD}https://$DOMAIN_NAME/api/schema/swagger-ui/${NC}"
    echo -e "  ${CYAN}•${NC} ReDoc:         ${BOLD}https://$DOMAIN_NAME/api/schema/redoc/${NC}"
    echo -e "  ${CYAN}•${NC} Admin:         ${BOLD}https://$DOMAIN_NAME/admin/${NC}"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Create superuser:   ${BOLD}cd $INSTALL_DIR && source venv/bin/activate && python manage.py createsuperuser${NC}"
    echo -e "  ${CYAN}2.${NC} Configure email settings in ${BOLD}$INSTALL_DIR/.env${NC} if needed"
    echo -e "  ${CYAN}3.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to verify the installation"
    echo ""

    print_success "Thank you for using Various Useful API Django!"
    echo ""
}

#-------------------------------------------------------------------------------
# Main execution
#-------------------------------------------------------------------------------

main() {
    # Pre-flight checks
    check_root
    check_ubuntu

    # Show welcome banner
    show_banner

    # Get domain name from user
    get_domain_name

    echo ""
    print_info "Starting installation. This may take several minutes..."
    print_info "Please do not interrupt the process."
    echo ""
    sleep 2

    # Execute installation steps
    install_dependencies
    clone_repository
    setup_python_environment
    configure_mysql
    create_env_file
    add_user_to_www_data
    run_django_setup
    create_systemd_service
    configure_nginx
    setup_ssl_certificate

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
