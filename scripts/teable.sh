#!/bin/bash

#===============================================================================
#
#   Teable + PostgreSQL + Redis - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Docker and Docker Compose
#   - PostgreSQL 15 database (via Docker)
#   - Redis 7 cache (via Docker)
#   - Teable spreadsheet-database platform (via Docker)
#   - Nginx as reverse proxy
#   - SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/teableio/teable
#   Documentation: https://help.teable.ai/en/deploy/docker
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
APP_NAME="teable"
SERVICE_NAME="teable"
INSTALLER_USER="installer_user"
APP_PORT="3000"
POSTGRESQL_VERSION="15.4"
REDIS_VERSION="7.2.4"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""

# Database credentials (will be generated)
DB_NAME="teable"
DB_USER="teable"
DB_PASSWORD=""

# Redis password
REDIS_PASSWORD=""

# Teable secret key
SECRET_KEY=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name>"
    echo ""
    echo "Arguments:"
    echo "  domain_name    The domain name for Teable (e.g., teable.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 teable.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., teable.example.com)"
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
    # Generate a secure secret key (32 bytes hex)
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

    # Add user to docker group for Docker access
    if getent group docker > /dev/null 2>&1; then
        print_step "Adding '$INSTALLER_USER' to docker group..."
        usermod -aG docker "$INSTALLER_USER"
        print_success "User added to docker group"
    fi

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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Teable + PostgreSQL + Redis${NC}                                            ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Docker and Docker Compose                                             ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} PostgreSQL ${POSTGRESQL_VERSION} database (via Docker)                               ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Redis ${REDIS_VERSION} cache (via Docker)                                      ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Teable spreadsheet-database platform                                  ${CYAN}║${NC}"
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

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_success "All system dependencies installed successfully!"
}

install_docker() {
    print_header "Installing Docker"

    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        print_info "Docker $DOCKER_VERSION is already installed"

        # Ensure Docker service is running
        print_step "Ensuring Docker service is running..."
        systemctl start docker
        systemctl enable docker > /dev/null 2>&1
        print_success "Docker service is running"
    else
        print_step "Adding Docker GPG key..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        print_success "Docker GPG key added"

        print_step "Adding Docker repository..."
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        print_success "Docker repository added"

        print_step "Updating package lists..."
        apt-get update -qq
        print_success "Package lists updated"

        print_step "Installing Docker..."
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
        print_success "Docker installed"

        print_step "Starting Docker service..."
        systemctl start docker
        systemctl enable docker > /dev/null 2>&1
        print_success "Docker service started and enabled"
    fi

    # Add installer user to docker group
    print_step "Adding $CURRENT_USER to docker group..."
    usermod -aG docker "$CURRENT_USER"
    print_success "User added to docker group"

    # Verify Docker Compose is available
    if docker compose version > /dev/null 2>&1; then
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
        print_success "Docker Compose $COMPOSE_VERSION is available"
    else
        print_error "Docker Compose is not available"
        exit 1
    fi
}

create_installation_directory() {
    print_header "Creating Installation Directory"

    print_step "Creating installation directory..."
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR'"
    print_success "Installation directory created"

    print_info "Installation directory: $INSTALL_DIR"
}

create_env_file() {
    print_header "Creating Environment Configuration"

    # Check if .env file already exists with credentials
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        print_info "Environment file already exists at $INSTALL_DIR/.env"
        # Read existing credentials
        DB_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$INSTALL_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
        REDIS_PASSWORD=$(grep "^REDIS_PASSWORD=" "$INSTALL_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
        SECRET_KEY=$(grep "^SECRET_KEY=" "$INSTALL_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "")

        if [[ -z "$DB_PASSWORD" ]]; then
            DB_PASSWORD=$(generate_password)
        fi
        if [[ -z "$REDIS_PASSWORD" ]]; then
            REDIS_PASSWORD=$(generate_password)
        fi
        if [[ -z "$SECRET_KEY" ]]; then
            SECRET_KEY=$(generate_secret_key)
        fi

        # Update domain if changed
        print_step "Updating domain configuration..."
        sed -i "s|^PUBLIC_ORIGIN=.*|PUBLIC_ORIGIN=https://$DOMAIN_NAME|" "$INSTALL_DIR/.env"
        print_success "Domain configuration updated"
        return
    fi

    print_step "Generating secure credentials..."
    DB_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    SECRET_KEY=$(generate_secret_key)
    print_success "Credentials generated"

    print_step "Creating .env file..."

    cat > "$INSTALL_DIR/.env" << EOF
# Teable Configuration
# Replace the default password below with a strong password (ASCII) of at least 8 characters.
POSTGRES_PASSWORD=$DB_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
SECRET_KEY=$SECRET_KEY

# Replace the following with a publicly accessible address
PUBLIC_ORIGIN=https://$DOMAIN_NAME

# ---------------------
# Postgres
POSTGRES_HOST=teable-db
POSTGRES_PORT=5432
POSTGRES_DB=$DB_NAME
POSTGRES_USER=$DB_USER

# Redis
REDIS_HOST=teable-cache
REDIS_PORT=6379
REDIS_DB=0

# App
PRISMA_DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@\${POSTGRES_HOST}:\${POSTGRES_PORT}/\${POSTGRES_DB}
BACKEND_CACHE_PROVIDER=redis
BACKEND_CACHE_REDIS_URI=redis://default:\${REDIS_PASSWORD}@\${REDIS_HOST}:\${REDIS_PORT}/\${REDIS_DB}
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    print_success ".env file created with secure permissions"
}

create_docker_compose() {
    print_header "Creating Docker Compose Configuration"

    # Check if docker-compose.yml already exists
    if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
        print_info "docker-compose.yml already exists"
        print_step "Skipping docker-compose.yml creation to preserve existing configuration..."
        print_success "Using existing docker-compose.yml"
        return
    fi

    print_step "Creating docker-compose.yml..."

    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  teable:
    image: ghcr.io/teableio/teable:latest
    restart: always
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - teable-data:/app/.assets:rw
    env_file:
      - .env
    environment:
      - NEXT_ENV_IMAGES_ALL_REMOTE=true
    networks:
      - teable
    depends_on:
      teable-db:
        condition: service_healthy
      teable-cache:
        condition: service_healthy
    healthcheck:
      test: ['CMD', 'curl', '-f', 'http://localhost:3000/health']
      start_period: 5s
      interval: 5s
      timeout: 3s
      retries: 3

  teable-db:
    image: postgres:15.4
    restart: always
    volumes:
      - teable-db:/var/lib/postgresql/data:rw
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    networks:
      - teable
    healthcheck:
      test: ['CMD-SHELL', "sh -c 'pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}'"]
      interval: 10s
      timeout: 3s
      retries: 3

  teable-cache:
    image: redis:7.2.4
    restart: always
    volumes:
      - teable-cache:/data:rw
    networks:
      - teable
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    healthcheck:
      test: ['CMD', 'redis-cli', '--raw', 'incr', 'ping']
      interval: 10s
      timeout: 3s
      retries: 3

networks:
  teable:
    name: teable-network

volumes:
  teable-db: {}
  teable-data: {}
  teable-cache: {}
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/docker-compose.yml"
    chmod 644 "$INSTALL_DIR/docker-compose.yml"
    print_success "docker-compose.yml created"
}

start_docker_containers() {
    print_header "Starting Docker Containers"

    print_step "Pulling Docker images..."
    cd "$INSTALL_DIR"
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && docker compose pull" > /dev/null 2>&1
    print_success "Docker images pulled"

    # Check if containers are already running
    if su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && docker compose ps -q" 2>/dev/null | grep -q .; then
        print_info "Containers are already running"
        print_step "Restarting containers to apply any changes..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && docker compose down" > /dev/null 2>&1
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && docker compose up -d" > /dev/null 2>&1
        print_success "Containers restarted"
    else
        print_step "Starting containers..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && docker compose up -d" > /dev/null 2>&1
        print_success "Containers started"
    fi

    # Wait for containers to be healthy
    print_step "Waiting for services to be ready..."
    sleep 15

    # Check if teable is responding
    local retries=30
    local count=0
    while [[ $count -lt $retries ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$APP_PORT/health" 2>/dev/null | grep -q "200"; then
            print_success "Teable is ready and responding"
            break
        fi
        ((count++))
        sleep 2
    done

    if [[ $count -eq $retries ]]; then
        print_warning "Teable may not be fully ready yet. Check logs with: docker compose logs -f teable"
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
        proxy_buffering off;
        chunked_transfer_encoding on;
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

    print_step "Adding www-data to $INSTALLER_USER group..."
    usermod -aG "$INSTALLER_USER" www-data
    print_success "www-data added to $INSTALLER_USER group"

    print_step "Setting directory permissions..."
    chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod 600 "$INSTALL_DIR/.env"
    print_success "Directory permissions configured"
}

create_management_script() {
    print_header "Creating Management Script"

    print_step "Creating management script..."

    cat > "$INSTALL_DIR/manage.sh" << 'EOF'
#!/bin/bash

# Teable Management Script
# Usage: ./manage.sh [command]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

case "$1" in
    start)
        echo "Starting Teable..."
        docker compose up -d
        ;;
    stop)
        echo "Stopping Teable..."
        docker compose down
        ;;
    restart)
        echo "Restarting Teable..."
        docker compose restart
        ;;
    logs)
        docker compose logs -f "${2:-teable}"
        ;;
    status)
        docker compose ps
        ;;
    update)
        echo "Updating Teable..."
        docker compose pull
        docker compose up -d
        ;;
    backup)
        BACKUP_DIR="$SCRIPT_DIR/backups"
        BACKUP_NAME="teable-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        echo "Creating backup: $BACKUP_NAME"
        docker compose exec -T teable-db pg_dump -U teable teable > "$BACKUP_DIR/$BACKUP_NAME.sql"
        echo "Backup saved to: $BACKUP_DIR/$BACKUP_NAME.sql"
        ;;
    *)
        echo "Teable Management Script"
        echo ""
        echo "Usage: $0 {start|stop|restart|logs|status|update|backup}"
        echo ""
        echo "Commands:"
        echo "  start    - Start Teable containers"
        echo "  stop     - Stop Teable containers"
        echo "  restart  - Restart Teable containers"
        echo "  logs     - Show logs (optional: logs teable-db)"
        echo "  status   - Show container status"
        echo "  update   - Update Teable to latest version"
        echo "  backup   - Backup PostgreSQL database"
        ;;
esac
EOF

    chmod +x "$INSTALL_DIR/manage.sh"
    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/manage.sh"
    print_success "Management script created"
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

    echo -e "${WHITE}PostgreSQL Database:${NC}"
    echo -e "  ${CYAN}•${NC} Host:             ${BOLD}teable-db (Docker internal)${NC}"
    echo -e "  ${CYAN}•${NC} Port:             ${BOLD}5432${NC}"
    echo -e "  ${CYAN}•${NC} Database:         ${BOLD}$DB_NAME${NC}"
    echo -e "  ${CYAN}•${NC} User:             ${BOLD}$DB_USER${NC}"
    echo -e "  ${CYAN}•${NC} Password:         ${BOLD}$DB_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}Redis Cache:${NC}"
    echo -e "  ${CYAN}•${NC} Host:             ${BOLD}teable-cache (Docker internal)${NC}"
    echo -e "  ${CYAN}•${NC} Port:             ${BOLD}6379${NC}"
    echo -e "  ${CYAN}•${NC} Password:         ${BOLD}$REDIS_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}Teable Configuration:${NC}"
    echo -e "  ${CYAN}•${NC} Web URL:          ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}•${NC} Internal port:    ${BOLD}$APP_PORT${NC}"
    echo ""

    echo -e "${WHITE}Docker Management:${NC}"
    echo -e "  ${CYAN}•${NC} Check status:     ${BOLD}cd $INSTALL_DIR && docker compose ps${NC}"
    echo -e "  ${CYAN}•${NC} View logs:        ${BOLD}cd $INSTALL_DIR && docker compose logs -f${NC}"
    echo -e "  ${CYAN}•${NC} Restart:          ${BOLD}cd $INSTALL_DIR && docker compose restart${NC}"
    echo -e "  ${CYAN}•${NC} Update:           ${BOLD}cd $INSTALL_DIR && docker compose pull && docker compose up -d${NC}"
    echo ""

    echo -e "${WHITE}Management Script:${NC}"
    echo -e "  ${CYAN}•${NC} Start:            ${BOLD}$INSTALL_DIR/manage.sh start${NC}"
    echo -e "  ${CYAN}•${NC} Stop:             ${BOLD}$INSTALL_DIR/manage.sh stop${NC}"
    echo -e "  ${CYAN}•${NC} Logs:             ${BOLD}$INSTALL_DIR/manage.sh logs${NC}"
    echo -e "  ${CYAN}•${NC} Backup:           ${BOLD}$INSTALL_DIR/manage.sh backup${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} Credentials are stored in: ${BOLD}$INSTALL_DIR/.env${NC}"
    echo -e "  ${CYAN}•${NC} Please save the database and Redis passwords in a secure location"
    echo -e "  ${CYAN}•${NC} On first access, you will need to create an account"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME${NC} to access Teable"
    echo -e "  ${CYAN}2.${NC} Create your account on first login"
    echo -e "  ${CYAN}3.${NC} Start creating your spreadsheet databases"
    echo -e "  ${CYAN}4.${NC} Check ${BOLD}https://help.teable.ai${NC} for documentation"
    echo ""

    print_success "Thank you for using Teable installer!"
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
    install_docker
    create_installation_directory
    create_env_file
    create_docker_compose
    start_docker_containers
    add_user_to_www_data
    configure_nginx
    setup_ssl_certificate
    create_management_script

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
