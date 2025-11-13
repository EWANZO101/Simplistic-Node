#!/bin/bash
# ============================================================
# 🚀 Complete Snaily CAD Installer
# ============================================================
# This script handles the full installation process:
# 1. Clone repository
# 2. Install dependencies (requires restart)
# 3. Setup PostgreSQL and .env (on second run)
# ============================================================

set -e
set -o pipefail

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[0;36m"
NC="\033[0m"

log() { echo -e "${GREEN}[✔]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# Configuration
INSTALL_DIR="/home"
PROJECT_NAME="snaily-cadv4"
PROJECT_PATH="$INSTALL_DIR/$PROJECT_NAME"
STATE_FILE="/tmp/snailycad_install_state"
REPO_URL="https://github.com/SnailyCAD/snaily-cadv4.git"

# ============================================================
# Check Installation State
# ============================================================
check_state() {
    if [[ -f "$STATE_FILE" ]]; then
        INSTALL_STATE=$(cat "$STATE_FILE")
    else
        INSTALL_STATE="initial"
    fi
}

save_state() {
    echo "$1" > "$STATE_FILE"
}

# ============================================================
# PHASE 1: Clone Repository & Install Dependencies
# ============================================================
phase1_clone_and_install() {
    section "Phase 1: Cloning Repository & Installing Dependencies"
    
    # Check if already cloned
    if [[ -d "$PROJECT_PATH" ]]; then
        warn "Project directory already exists: $PROJECT_PATH"
        read -p "Do you want to remove it and re-clone? (y/n): " RECLONE
        if [[ "$RECLONE" == "y" ]]; then
            log "Removing existing directory..."
            sudo rm -rf "$PROJECT_PATH"
        else
            log "Keeping existing directory, skipping clone..."
        fi
    fi
    
    # Clone repository if needed
    if [[ ! -d "$PROJECT_PATH" ]]; then
        log "Cloning Snaily CAD repository..."
        cd "$INSTALL_DIR"
        git clone "$REPO_URL" || {
            error "Failed to clone repository"
            exit 1
        }
        log "Repository cloned successfully"
    fi
    
    # Navigate to project
    cd "$PROJECT_PATH" || {
        error "Failed to navigate to $PROJECT_PATH"
        exit 1
    }
    
    log "Current directory: $(pwd)"
    
    # Check for pnpm
    if ! command -v pnpm >/dev/null 2>&1; then
        error "pnpm is not installed!"
        info "Please install pnpm first with: npm install -g pnpm"
        exit 1
    fi
    
    # Install dependencies
    log "Installing dependencies with pnpm..."
    log "This may take several minutes..."
    
    if pnpm install; then
        log "✅ Dependencies installed successfully!"
    else
        error "Failed to install dependencies"
        exit 1
    fi
    
    # Save state and prompt for restart
    save_state "phase1_complete"
    
    echo ""
    section "Phase 1 Complete!"
    echo -e "${GREEN}✅ Repository cloned and dependencies installed${NC}"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📌 IMPORTANT: Please run this script again to continue${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Run: ${GREEN}sudo ./complete-install.sh${NC}"
    echo ""
    exit 0
}

# ============================================================
# PHASE 2: PostgreSQL Setup & .env Configuration
# ============================================================
phase2_database_setup() {
    section "Phase 2: Database Setup & Configuration"
    
    log "Continuing installation from Phase 1..."
    
    if [[ ! -d "$PROJECT_PATH" ]]; then
        error "Project directory not found: $PROJECT_PATH"
        error "Please run Phase 1 first!"
        exit 1
    fi
    
    cd "$PROJECT_PATH"
    
    # Check if PostgreSQL is installed
    if ! command -v psql >/dev/null 2>&1; then
        log "PostgreSQL not found. Installing PostgreSQL 16..."
        
        sudo apt update -y
        sudo apt install -y wget gnupg lsb-release software-properties-common pwgen
        
        RELEASE=$(lsb_release -cs)
        echo "deb http://apt.postgresql.org/pub/repos/apt ${RELEASE}-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
        wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/postgresql.asc >/dev/null
        
        sudo apt update -y
        sudo apt install -y postgresql-16 postgresql-contrib
        
        sudo systemctl enable postgresql
        sudo systemctl start postgresql
        
        log "PostgreSQL 16 installed: $(psql --version)"
    else
        log "PostgreSQL already installed: $(psql --version)"
        
        # Make sure pwgen is installed
        if ! command -v pwgen >/dev/null 2>&1; then
            log "Installing pwgen..."
            sudo apt install -y pwgen
        fi
    fi
    
    echo ""
    section "Generating Secure Credentials"
    
    DB_PASSWORD=$(pwgen -s 20 1)
    JWT_SECRET=$(pwgen -s 32 1)
    ENCRYPTION_TOKEN=$(pwgen -s 32 1)
    
    info "Generated POSTGRES_PASSWORD: $DB_PASSWORD"
    info "Generated JWT_SECRET: $JWT_SECRET"
    info "Generated ENCRYPTION_TOKEN: $ENCRYPTION_TOKEN"
    
    echo ""
    section "Creating Database & User"
    
    DB_USER="snailycad"
    DB_NAME="snaily-cadv4"
    
    # Check if user exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        warn "User '$DB_USER' already exists, skipping user creation"
    else
        log "Creating database user..."
        sudo -u postgres psql <<EOF
CREATE USER "$DB_USER" WITH SUPERUSER PASSWORD '$DB_PASSWORD';
EOF
        log "User '$DB_USER' created"
    fi
    
    # Check if database exists
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        warn "Database '$DB_NAME' already exists, skipping database creation"
    else
        log "Creating database..."
        sudo -u postgres psql <<EOF
CREATE DATABASE "$DB_NAME";
GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER";
EOF
        log "Database '$DB_NAME' created"
    fi
    
    echo ""
    section "Domain Configuration"
    
    read -p "Enter CAD domain (e.g., cad.example.com): " CAD_DOMAIN
    read -p "Enter API domain (e.g., api.example.com): " API_DOMAIN
    read -p "Enter ROOT domain (e.g., example.com): " ROOT_DOMAIN
    
    echo ""
    section "Generating .env File"
    
    if [ ! -f ".env.example" ]; then
        error ".env.example not found in $PROJECT_PATH"
        exit 1
    fi
    
    if [[ -f ".env" ]]; then
        warn ".env file already exists"
        read -p "Do you want to overwrite it? (y/n): " OVERWRITE
        if [[ "$OVERWRITE" != "y" ]]; then
            log "Keeping existing .env file"
            save_state "complete"
            phase2_complete_message
            return
        fi
        mv .env .env.backup.$(date +%s)
        log "Backed up existing .env file"
    fi
    
    cp .env.example .env
    
    # Update .env with generated values
    sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=\"$DB_PASSWORD\"|g" .env
    sed -i "s|POSTGRES_USER=.*|POSTGRES_USER=\"$DB_USER\"|g" .env
    sed -i "s|DB_HOST=.*|DB_HOST=\"localhost\"|g" .env
    sed -i "s|DB_PORT=.*|DB_PORT=\"5432\"|g" .env
    sed -i "s|POSTGRES_DB=.*|POSTGRES_DB=\"$DB_NAME\"|g" .env
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=\"$JWT_SECRET\"|g" .env
    sed -i "s|ENCRYPTION_TOKEN=.*|ENCRYPTION_TOKEN=\"$ENCRYPTION_TOKEN\"|g" .env
    sed -i "s|CORS_ORIGIN_URL=.*|CORS_ORIGIN_URL=\"https://$CAD_DOMAIN\"|g" .env
    sed -i "s|NEXT_PUBLIC_CLIENT_URL=.*|NEXT_PUBLIC_CLIENT_URL=\"https://$CAD_DOMAIN\"|g" .env
    sed -i "s|NEXT_PUBLIC_PROD_ORIGIN=.*|NEXT_PUBLIC_PROD_ORIGIN=\"https://$API_DOMAIN/v1\"|g" .env
    sed -i "s|DOMAIN=.*|DOMAIN=\"$ROOT_DOMAIN\"|g" .env
    sed -i "s|SECURE_COOKIES_FOR_IFRAME=.*|SECURE_COOKIES_FOR_IFRAME=\"true\"|g" .env
    
    log ".env file generated successfully!"
    
    echo ""
    warn "Opening .env for review and final adjustments..."
    sleep 2
    nano .env
    
    # Mark as complete
    save_state "complete"
    
    phase2_complete_message
}

phase2_complete_message() {
    echo ""
    section "Installation Complete! 🎉"
    
    echo -e "${GREEN}✅ Repository cloned to: $PROJECT_PATH${NC}"
    echo -e "${GREEN}✅ Dependencies installed${NC}"
    echo -e "${GREEN}✅ PostgreSQL configured${NC}"
    echo -e "${GREEN}✅ Database created${NC}"
    echo -e "${GREEN}✅ .env file generated${NC}"
    echo ""
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  ${YELLOW}1. Build the project:${NC}"
    echo -e "     cd $PROJECT_PATH"
    echo -e "     pnpm run build"
    echo -e ""
    echo -e "  ${YELLOW}2. Run the deployment script (will setup systemd service):${NC}"
    echo -e "     sudo ./update_start.sh"
    echo -e "     ${CYAN}(When prompted, enter: $PROJECT_PATH)${NC}"
    echo -e ""
    echo -e "  ${YELLOW}3. Or verify everything with:${NC}"
    echo -e "     sudo ./doublecheck.sh $PROJECT_PATH"
    echo ""
    
    info "📂 Project location: $PROJECT_PATH"
    info "🗄️  Database name: snaily-cadv4"
    info "👤 Database user: snailycad"
    info "🔑 Database password: (stored in .env)"
    echo ""
    
    echo -e "${CYAN}💡 Tip: When running update_start.sh, use this path:${NC}"
    echo -e "   ${GREEN}$PROJECT_PATH${NC}"
    echo ""
}

# ============================================================
# Main Script Logic
# ============================================================

echo "============================================"
echo " 🚀 SNAILYCAD COMPLETE INSTALLER"
echo "============================================"
echo ""

# Check current state
check_state

case "$INSTALL_STATE" in
    "initial")
        log "Starting Phase 1: Clone & Install Dependencies"
        phase1_clone_and_install
        ;;
    
    "phase1_complete")
        log "Phase 1 already complete"
        log "Starting Phase 2: Database Setup & Configuration"
        phase2_database_setup
        ;;
    
    "complete")
        log "Installation already complete!"
        echo ""
        warn "Do you want to:"
        echo "  1. Re-run Phase 2 (Database & .env setup)"
        echo "  2. Start fresh (remove everything and start over)"
        echo "  3. Exit"
        echo ""
        read -p "Choose option (1/2/3): " CHOICE
        
        case "$CHOICE" in
            1)
                phase2_database_setup
                ;;
            2)
                warn "This will delete $PROJECT_PATH and start over!"
                read -p "Are you sure? (yes/no): " CONFIRM
                if [[ "$CONFIRM" == "yes" ]]; then
                    sudo rm -rf "$PROJECT_PATH"
                    rm -f "$STATE_FILE"
                    log "Cleaned up. Run the script again to start fresh."
                else
                    log "Cancelled"
                fi
                ;;
            3)
                log "Exiting..."
                exit 0
                ;;
            *)
                error "Invalid choice"
                exit 1
                ;;
        esac
        ;;
    
    *)
        error "Unknown state: $INSTALL_STATE"
        exit 1
        ;;
esac
