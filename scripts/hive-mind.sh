#!/bin/bash

#===============================================================================
#
#   Hive Mind + Telegram Bot - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Docker and Docker Compose
#   - Hive Mind AI orchestrator (via Docker)
#   - Telegram Bot integration
#
#   Repository: https://github.com/link-assistant/hive-mind
#   Documentation: https://github.com/link-assistant/hive-mind#readme
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
APP_NAME="hive-mind"
INSTALLER_USER="installer_user"
DOCKER_IMAGE="konard/hive-mind:latest"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""

# Telegram Bot configuration (will be set from arguments)
TELEGRAM_BOT_TOKEN=""
TELEGRAM_GROUP_ID=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <telegram_bot_token> <telegram_group_id>"
    echo ""
    echo "Arguments:"
    echo "  telegram_bot_token   Telegram Bot API token (from @BotFather)"
    echo "  telegram_group_id    Telegram Group ID (negative number for groups)"
    echo ""
    echo "Example:"
    echo "  $0 123456789:ABCdefGHIjklMNOpqrsTUVwxyz -1002975819706"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_telegram_token() {
    local token="$1"
    # Basic Telegram bot token validation (format: number:alphanumeric)
    if [[ ! "$token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid Telegram bot token format: $token"
        print_info "Token should be in format: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
        exit 1
    fi
}

validate_telegram_group_id() {
    local group_id="$1"
    # Group IDs are negative numbers, but can also be positive for private chats
    if [[ ! "$group_id" =~ ^-?[0-9]+$ ]]; then
        print_error "Invalid Telegram group ID format: $group_id"
        print_info "Group ID should be a number (negative for groups, e.g., -1002975819706)"
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
        print_info "Run with: sudo $0 <telegram_bot_token> <telegram_group_id>"
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
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Hive Mind + Telegram Bot${NC}                                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Docker and Docker Compose                                             ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Hive Mind AI orchestrator                                             ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Telegram Bot integration                                              ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

parse_arguments() {
    # Check if all required arguments are provided
    if [[ $# -lt 2 ]] || [[ -z "$1" ]] || [[ -z "$2" ]]; then
        print_error "Missing required arguments!"
        show_usage
    fi

    TELEGRAM_BOT_TOKEN="$1"
    TELEGRAM_GROUP_ID="$2"

    validate_telegram_token "$TELEGRAM_BOT_TOKEN"
    validate_telegram_group_id "$TELEGRAM_GROUP_ID"

    print_header "Configuration"
    print_success "Telegram Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
    print_success "Telegram Group ID: $TELEGRAM_GROUP_ID"
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
    su - "$CURRENT_USER" -c "mkdir -p '$INSTALL_DIR/data'"
    print_success "Installation directory created"

    print_info "Installation directory: $INSTALL_DIR"
}

create_env_file() {
    print_header "Creating Environment Configuration"

    # Check if .env file already exists with credentials
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        print_info "Environment file already exists at $INSTALL_DIR/.env"

        # Update telegram configuration if changed
        print_step "Updating Telegram configuration..."
        sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN|" "$INSTALL_DIR/.env"
        sed -i "s|^TELEGRAM_GROUP_ID=.*|TELEGRAM_GROUP_ID=$TELEGRAM_GROUP_ID|" "$INSTALL_DIR/.env"
        print_success "Telegram configuration updated"
        return
    fi

    print_step "Creating .env file..."

    cat > "$INSTALL_DIR/.env" << EOF
# Hive Mind Configuration

# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_GROUP_ID=$TELEGRAM_GROUP_ID
TELEGRAM_BOT_VERBOSE=true

# Timezone
TZ=UTC
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
  hive-mind:
    image: konard/hive-mind:latest
    container_name: hive-mind
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - ./data:/root
    command: >
      hive-telegram-bot
      --token ${TELEGRAM_BOT_TOKEN}
      --allowed-chats "(${TELEGRAM_GROUP_ID})"
      --verbose
    healthcheck:
      test: ["CMD", "pgrep", "-f", "hive-telegram-bot"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
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

    # Wait for containers to be ready
    print_step "Waiting for services to be ready..."
    sleep 10

    # Check if hive-mind container is running
    local retries=30
    local count=0
    while [[ $count -lt $retries ]]; do
        if su - "$CURRENT_USER" -c "docker ps --filter 'name=hive-mind' --filter 'status=running' -q" 2>/dev/null | grep -q .; then
            print_success "Hive Mind container is running"
            break
        fi
        ((count++))
        sleep 2
    done

    if [[ $count -eq $retries ]]; then
        print_warning "Hive Mind may not be fully ready yet. Check logs with: docker compose logs -f hive-mind"
    fi
}

set_directory_permissions() {
    print_header "Configuring Directory Permissions"

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

# Hive Mind Management Script
# Usage: ./manage.sh [command]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

case "$1" in
    start)
        echo "Starting Hive Mind..."
        docker compose up -d
        ;;
    stop)
        echo "Stopping Hive Mind..."
        docker compose down
        ;;
    restart)
        echo "Restarting Hive Mind..."
        docker compose restart
        ;;
    logs)
        docker compose logs -f "${2:-hive-mind}"
        ;;
    status)
        docker compose ps
        ;;
    update)
        echo "Updating Hive Mind..."
        docker compose pull
        docker compose up -d
        ;;
    shell)
        echo "Opening shell in Hive Mind container..."
        docker compose exec hive-mind /bin/bash
        ;;
    *)
        echo "Hive Mind Management Script"
        echo ""
        echo "Usage: $0 {start|stop|restart|logs|status|update|shell}"
        echo ""
        echo "Commands:"
        echo "  start    - Start Hive Mind containers"
        echo "  stop     - Stop Hive Mind containers"
        echo "  restart  - Restart Hive Mind containers"
        echo "  logs     - Show logs"
        echo "  status   - Show container status"
        echo "  update   - Update Hive Mind to latest version"
        echo "  shell    - Open shell in container"
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
    echo -e "  ${CYAN}•${NC} Install path:     ${BOLD}$INSTALL_DIR${NC}"
    echo ""

    echo -e "${WHITE}Telegram Bot Configuration:${NC}"
    echo -e "  ${CYAN}•${NC} Bot Token:        ${BOLD}${TELEGRAM_BOT_TOKEN:0:10}...${NC}"
    echo -e "  ${CYAN}•${NC} Allowed Group ID: ${BOLD}$TELEGRAM_GROUP_ID${NC}"
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
    echo -e "  ${CYAN}•${NC} Shell:            ${BOLD}$INSTALL_DIR/manage.sh shell${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} Configuration stored in: ${BOLD}$INSTALL_DIR/.env${NC}"
    echo -e "  ${CYAN}•${NC} Telegram Bot Token is sensitive - keep it secure"
    echo ""

    echo -e "${YELLOW}Telegram Bot Usage:${NC}"
    echo -e "  ${CYAN}•${NC} Add the bot to your Telegram group"
    echo -e "  ${CYAN}•${NC} Available commands: /solve, /hive, /limits, /help"
    echo -e "  ${CYAN}•${NC} Commands work only in allowed group chats"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Add the bot to your Telegram group (ID: $TELEGRAM_GROUP_ID)"
    echo -e "  ${CYAN}2.${NC} Use /help in the group to see available commands"
    echo -e "  ${CYAN}3.${NC} Check ${BOLD}https://github.com/link-assistant/hive-mind${NC} for documentation"
    echo ""

    print_success "Thank you for using Hive Mind + Telegram Bot installer!"
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
    print_info "User: $CURRENT_USER"
    echo ""

    # Execute installation steps
    install_dependencies
    install_docker
    create_installation_directory
    create_env_file
    create_docker_compose
    start_docker_containers
    set_directory_permissions
    create_management_script

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
