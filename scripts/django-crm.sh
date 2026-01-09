#!/bin/bash

#===============================================================================
#
#   Django-CRM - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Git, Python 3, PostgreSQL, Nginx, Certbot
#   - Clones the django-crm repository
#   - Sets up Python virtual environment with all dependencies
#   - Configures PostgreSQL database
#   - Creates systemd services for automatic startup
#   - Configures Nginx as reverse proxy
#   - Obtains SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/DjangoCRM/django-crm
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
REPO_URL="https://github.com/DjangoCRM/django-crm.git"
APP_NAME="django-crm"
SERVICE_NAME="django-crm"
SOCKET_PATH="/run/gunicorn_django_crm.sock"
PYTHON_VERSION="python3"
INSTALLER_USER="installer_user"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""
VENV_DIR=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name>"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for Django-CRM (e.g., crm.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 crm.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., crm.example.com)"
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

generate_secret_key() {
    # Generate Django secret key (50 characters)
    openssl rand -base64 48 | tr -d '/+=' | head -c 50
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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Django-CRM${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Git, Python 3, PostgreSQL, Nginx, Certbot                            ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Django-CRM application with virtual environment                      ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Systemd services for auto-start                                      ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} SSL certificate via Let's Encrypt                                    ${CYAN}║${NC}"
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

    print_step "Installing Python 3 and development tools..."
    apt-get install -y -qq python3 python3-pip python3-venv python3-dev > /dev/null 2>&1
    print_success "Python 3 installed"

    print_step "Installing PostgreSQL Server..."
    apt-get install -y -qq postgresql postgresql-contrib libpq-dev > /dev/null 2>&1
    print_success "PostgreSQL Server installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_step "Installing additional dependencies..."
    apt-get install -y -qq build-essential libffi-dev libssl-dev > /dev/null 2>&1
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
        su - "$CURRENT_USER" -c "git clone '$REPO_URL' '$INSTALL_DIR'" > /dev/null 2>&1
        print_success "Repository cloned successfully"
    fi

    cd "$INSTALL_DIR"
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

    print_step "Installing/updating Python dependencies (this may take a few minutes)..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install -r requirements.txt" > /dev/null 2>&1
    print_success "All Python dependencies installed/updated"

    print_step "Installing Gunicorn..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install gunicorn" > /dev/null 2>&1
    print_success "Gunicorn installed"
}

configure_postgresql() {
    print_header "Configuring PostgreSQL Database"

    DB_NAME="django_crm"
    DB_USER="django_crm_user"

    print_step "Starting PostgreSQL service..."
    systemctl start postgresql
    systemctl enable postgresql > /dev/null 2>&1
    print_success "PostgreSQL service started"

    print_step "Checking if database '$DB_NAME' exists..."
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        print_info "Database '$DB_NAME' already exists"
    else
        print_step "Creating database '$DB_NAME'..."
        sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" > /dev/null 2>&1
        print_success "Database created"
    fi

    print_step "Checking if database user '$DB_USER' exists..."
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        print_info "Database user '$DB_USER' already exists"
        print_warning "Existing database user password will NOT be changed to protect existing applications."
        print_info "If this application cannot connect to the database,"
        print_info "please manually update the password in the settings.py file."
        # Generate a placeholder password for the summary - actual connection will use settings.py
        DB_PASSWORD="(existing user - check settings.py)"
    else
        DB_PASSWORD=$(generate_password)
        print_step "Creating database user '$DB_USER'..."
        sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" > /dev/null 2>&1
        print_success "Database user created"
    fi

    print_step "Granting privileges..."
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" > /dev/null 2>&1
    sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;" > /dev/null 2>&1
    print_success "Database privileges granted"

    # Save credentials for later use
    export DB_NAME DB_USER DB_PASSWORD
}

configure_django_settings() {
    print_header "Configuring Django Settings"

    SETTINGS_FILE="$INSTALL_DIR/webcrm/settings.py"

    # Check if settings have already been configured (look for our marker)
    if grep -q "# Configured by installation script" "$SETTINGS_FILE" 2>/dev/null; then
        print_info "Django settings already configured"
        print_step "Skipping settings modification to preserve existing configuration..."
        print_success "Using existing settings"
        return
    fi

    # Check if database user exists but we don't have the password
    if [[ "$DB_PASSWORD" == "(existing user - check settings.py)" ]]; then
        print_error "Database user '$DB_USER' exists but settings.py not yet configured."
        print_info "Please manually update $SETTINGS_FILE with the correct database password"
        print_info "Or reset the database user password in PostgreSQL."
        exit 1
    fi

    DJANGO_SECRET_KEY=$(generate_secret_key)

    print_step "Backing up original settings.py..."
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup_$(date +%Y%m%d_%H%M%S)"
    print_success "Backup created"

    print_step "Updating Django settings..."

    # Update SECRET_KEY
    sed -i "s/SECRET_KEY = .*/SECRET_KEY = '$DJANGO_SECRET_KEY'  # Configured by installation script/" "$SETTINGS_FILE"

    # Update DEBUG
    sed -i "s/DEBUG = .*/DEBUG = False  # Configured by installation script/" "$SETTINGS_FILE"

    # Update ALLOWED_HOSTS
    sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['$DOMAIN_NAME', 'localhost', '127.0.0.1']  # Configured by installation script/" "$SETTINGS_FILE"

    # Update database configuration to use PostgreSQL
    # We need to replace the entire DATABASES section
    cat > /tmp/django_crm_db_config.py << EOF
# Configured by installation script
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '$DB_NAME',
        'USER': '$DB_USER',
        'PASSWORD': '$DB_PASSWORD',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}
EOF

    # Find and replace DATABASES section
    # Using python to properly modify the settings file
    python3 << PYTHON_SCRIPT
import re

with open('$SETTINGS_FILE', 'r') as f:
    content = f.read()

# Find and replace DATABASES configuration
db_config = """# Configured by installation script
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '$DB_NAME',
        'USER': '$DB_USER',
        'PASSWORD': '$DB_PASSWORD',
        'HOST': 'localhost',
        'PORT': '5432',
    }
}"""

# Replace DATABASES section (handle multiline)
pattern = r'DATABASES\s*=\s*\{[^}]*\{[^}]*\}[^}]*\}'
content = re.sub(pattern, db_config, content, flags=re.DOTALL)

with open('$SETTINGS_FILE', 'w') as f:
    f.write(content)
PYTHON_SCRIPT

    # Update STATIC_ROOT and MEDIA_ROOT
    sed -i "s|STATIC_ROOT = .*|STATIC_ROOT = BASE_DIR / 'static'  # Configured by installation script|" "$SETTINGS_FILE"
    sed -i "s|MEDIA_ROOT = .*|MEDIA_ROOT = BASE_DIR / 'media'  # Configured by installation script|" "$SETTINGS_FILE"

    chown "$CURRENT_USER":"$CURRENT_USER" "$SETTINGS_FILE"
    print_success "Django settings configured"

    print_info "Database credentials saved in settings.py"
}

run_django_setup() {
    print_header "Running Django Setup"

    print_step "Running database migrations..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && python manage.py migrate" > /dev/null 2>&1
    print_success "Database migrations completed"

    print_step "Collecting static files..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && python manage.py collectstatic --noinput" > /dev/null 2>&1
    print_success "Static files collected"

    # Create media directory
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR/media' && chmod 755 '$INSTALL_DIR/media'"
    print_success "Media directory created"

    # Check if superuser already exists before creating
    print_step "Checking for existing superuser..."
    if su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && python manage.py shell -c \"from django.contrib.auth import get_user_model; User = get_user_model(); print(User.objects.filter(username='admin').exists())\"" 2>/dev/null | grep -q "True"; then
        print_info "Superuser 'admin' already exists"
        print_step "Skipping superuser creation..."
        print_success "Using existing superuser"
    else
        ADMIN_PASSWORD=$(generate_password)
        print_step "Creating superuser (admin)..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && DJANGO_SUPERUSER_PASSWORD='$ADMIN_PASSWORD' python manage.py createsuperuser --username=admin --email=admin@$DOMAIN_NAME --noinput" > /dev/null 2>&1
        print_success "Superuser created (username: admin, email: admin@$DOMAIN_NAME)"
        export ADMIN_PASSWORD
    fi

    print_success "Django setup completed"
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    print_step "Creating socket file..."

    tee /etc/systemd/system/${SERVICE_NAME}.socket > /dev/null << EOF
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

    tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
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
          webcrm.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service file created"

    print_step "Reloading systemd daemon..."
    systemctl daemon-reload
    print_success "Systemd daemon reloaded"

    print_step "Enabling and starting socket..."
    systemctl enable ${SERVICE_NAME}.socket > /dev/null 2>&1
    systemctl start ${SERVICE_NAME}.socket
    print_success "Socket enabled and started"

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
    ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
    print_success "Site enabled"

    print_step "Testing Nginx configuration..."
    nginx -t > /dev/null 2>&1
    print_success "Nginx configuration valid"

    print_step "Reloading Nginx..."
    systemctl reload nginx
    print_success "Nginx reloaded"
}

setup_ssl() {
    print_header "Setting Up SSL Certificate"

    # Check if certificate already exists
    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $DOMAIN_NAME already exists"
        print_step "Skipping SSL certificate creation..."
        print_success "Using existing SSL certificate"
        return
    fi

    print_step "Obtaining SSL certificate from Let's Encrypt..."
    print_info "This may take a moment..."

    certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect > /dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        print_success "SSL certificate obtained and configured successfully"
    else
        print_warning "Failed to obtain SSL certificate automatically"
        print_info "You can manually run: certbot --nginx -d $DOMAIN_NAME"
    fi
}

generate_report() {
    print_header "Installation Summary"

    REPORT_FILE="$HOME_DIR/django-crm-installation-report.txt"

    cat > "$REPORT_FILE" << EOF
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                     Django-CRM Installation Report                           ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

Installation Date: $(date)
Domain: $DOMAIN_NAME

─────────────────────────────────────────────────────────────────────────────
 Application Information
─────────────────────────────────────────────────────────────────────────────
Installation Directory: $INSTALL_DIR
Virtual Environment: $VENV_DIR
Application User: $CURRENT_USER

─────────────────────────────────────────────────────────────────────────────
 Database Information
─────────────────────────────────────────────────────────────────────────────
Database Type: PostgreSQL
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASSWORD

─────────────────────────────────────────────────────────────────────────────
 Admin Account
─────────────────────────────────────────────────────────────────────────────
Admin Username: admin
EOF

    if [[ -n "$ADMIN_PASSWORD" ]]; then
        cat >> "$REPORT_FILE" << EOF
Admin Password: $ADMIN_PASSWORD
Admin Email: admin@$DOMAIN_NAME

⚠ IMPORTANT: Please change the admin password after first login!
EOF
    else
        cat >> "$REPORT_FILE" << EOF
Admin Account: Already existed before this installation

ℹ Use existing admin credentials to log in.
EOF
    fi

    cat >> "$REPORT_FILE" << EOF

─────────────────────────────────────────────────────────────────────────────
 Web Access
─────────────────────────────────────────────────────────────────────────────
Application URL: https://$DOMAIN_NAME
Admin Panel: https://$DOMAIN_NAME/admin/

─────────────────────────────────────────────────────────────────────────────
 System Services
─────────────────────────────────────────────────────────────────────────────
Service Name: ${SERVICE_NAME}.service
Socket: ${SERVICE_NAME}.socket

Service Commands:
  • Check status: systemctl status ${SERVICE_NAME}.service
  • Start service: systemctl start ${SERVICE_NAME}.service
  • Stop service: systemctl stop ${SERVICE_NAME}.service
  • Restart service: systemctl restart ${SERVICE_NAME}.service
  • View logs: journalctl -u ${SERVICE_NAME}.service -f

─────────────────────────────────────────────────────────────────────────────
 Important Files
─────────────────────────────────────────────────────────────────────────────
Django Settings: $INSTALL_DIR/webcrm/settings.py
Gunicorn Errors: $INSTALL_DIR/gunicorn-errors.txt
Nginx Config: /etc/nginx/sites-available/$DOMAIN_NAME
Nginx Access Log: /var/log/nginx/${DOMAIN_NAME}_access.log
Nginx Error Log: /var/log/nginx/${DOMAIN_NAME}_error.log

─────────────────────────────────────────────────────────────────────────────
 Security Notes
─────────────────────────────────────────────────────────────────────────────
• Database credentials are stored in: $INSTALL_DIR/webcrm/settings.py
• This file has been configured with secure database settings
• Backup your database regularly
• Keep your SECRET_KEY secure and never commit it to version control
• SSL certificate will auto-renew via certbot

═══════════════════════════════════════════════════════════════════════════════

For support and documentation, visit:
• GitHub: https://github.com/DjangoCRM/django-crm
• Documentation: https://django-crm-admin.readthedocs.io/

═══════════════════════════════════════════════════════════════════════════════
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$REPORT_FILE"
    chmod 600 "$REPORT_FILE"

    print_success "Installation report generated: $REPORT_FILE"
    echo ""
    print_info "Installation Summary:"
    echo ""
    cat "$REPORT_FILE"
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
    clone_repository
    setup_python_environment
    configure_postgresql
    configure_django_settings
    run_django_setup
    create_systemd_service
    configure_nginx
    setup_ssl
    generate_report

    print_header "Installation Complete!"
    echo ""
    print_success "Django-CRM has been successfully installed!"
    echo ""
    print_info "You can now access your CRM at: ${GREEN}https://$DOMAIN_NAME${NC}"
    print_info "Admin panel: ${GREEN}https://$DOMAIN_NAME/admin/${NC}"
    echo ""
    print_warning "Please review the installation report at: $REPORT_FILE"
    echo ""
}

# Run main function with all arguments
main "$@"
