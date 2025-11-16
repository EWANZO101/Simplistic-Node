#!/bin/bash
# ============================================================
# SNAILYCAD COMPLETE ALL-IN-ONE INSTALLER & MANAGER - WITH NGINX
# ============================================================

set -e
set -o pipefail

# =========================
# COLORS & LOG FUNCTIONS
# =========================
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[0;36m"
NC="\033[0m"

log() { echo -e "${GREEN}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
step() { echo -e "\n${BLUE}=== STEP $1: $2 ===${NC}\n"; }
section() { echo -e "\n${BLUE}--- $1 ---${NC}\n"; }

# =========================
# CONFIGURATION
# =========================
DEFAULT_PROJECT_PATH="/home/snaily-cadv4"
REPO_URL="https://github.com/SnailyCAD/snaily-cadv4.git"
SERVICE_NAME="start-snaily-cadv4"

# =========================
# APT LOCK HANDLER
# =========================
wait_for_apt_lock() {
    local max_wait=300
    local waited=0
    local check_interval=2
    
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        
        if [ $waited -ge $max_wait ]; then
            warn "apt lock timeout reached after ${max_wait}s"
            return 1
        fi
        
        if [ $waited -eq 0 ]; then
            warn "Waiting for apt lock to be released..."
        fi
        
        sleep $check_interval
        waited=$((waited + check_interval))
        
        if [ $((waited % 10)) -eq 0 ]; then
            info "Still waiting... (${waited}s elapsed)"
        fi
    done
    
    if [ $waited -gt 0 ]; then
        log "apt lock released after ${waited}s"
    fi
    
    return 0
}

force_clear_apt_locks() {
    warn "Force clearing apt locks..."
    sudo killall apt apt-get dpkg 2>/dev/null || true
    sleep 2
    sudo rm -rf /var/lib/apt/lists/lock
    sudo rm -rf /var/cache/apt/archives/lock
    sudo rm -rf /var/lib/dpkg/lock*
    sudo dpkg --configure -a 2>/dev/null || true
    log "apt locks cleared"
}

safe_apt_install() {
    local packages="$@"
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if wait_for_apt_lock; then
            if sudo apt install -y $packages; then
                return 0
            fi
        fi
        
        retry=$((retry + 1))
        
        if [ $retry -lt $max_retries ]; then
            warn "apt install failed (attempt $retry/$max_retries)"
            if [ $retry -eq 2 ]; then
                force_clear_apt_locks
            fi
            sleep 5
        fi
    done
    
    error "Failed to install packages after $max_retries attempts"
    return 1
}

safe_apt_update() {
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if wait_for_apt_lock; then
            if sudo apt update; then
                return 0
            fi
        fi
        
        retry=$((retry + 1))
        
        if [ $retry -lt $max_retries ]; then
            warn "apt update failed (attempt $retry/$max_retries)"
            if [ $retry -eq 2 ]; then
                force_clear_apt_locks
            fi
            sleep 5
        fi
    done
    
    error "Failed to update packages after $max_retries attempts"
    return 1
}

# =========================
# NODE.JS INSTALLATION FUNCTIONS
# =========================
install_nodejs_22() {
    log "Installing Node.js 22.x..."
    warn "Removing existing Node.js installations to prevent conflicts..."
    sudo apt remove --purge -y nodejs npm
    sudo rm -rf /etc/apt/sources.list.d/nodesource.list
    sudo rm -rf /etc/apt/sources.list.d/nodistro.list
    sudo rm -rf /usr/lib/node_modules
    sudo rm -rf /usr/local/lib/node_modules
    sudo rm -rf ~/.npm
    sudo apt autoremove -y
    sudo apt clean
    safe_apt_update
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    safe_apt_install nodejs
    log "Node.js version: $(node -v)"
    log "npm version: $(npm -v)"
}

fix_nodejs_conflict() {
    section "FIXING NODE.JS VERSION CONFLICT"
    warn "This will remove all existing Node.js versions and install fresh Node.js 22.x"
    read -p "Continue? (y/n): " CONFIRM
    
    if [[ "$CONFIRM" != "y" ]]; then
        log "Cancelled"
        return
    fi
    
    log "Removing existing Node.js installations..."
    sudo systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    sudo apt remove --purge -y nodejs npm
    sudo rm -rf /etc/apt/sources.list.d/nodesource.list
    sudo rm -rf /etc/apt/sources.list.d/nodistro.list
    sudo rm -rf /usr/lib/node_modules
    sudo rm -rf /usr/local/lib/node_modules
    sudo rm -rf ~/.npm
    sudo rm -rf ~/.nvm
    sudo rm -rf /opt/nodejs
    sudo apt autoremove -y
    sudo apt clean
    safe_apt_update
    log "Installing Node.js 22.x..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    safe_apt_install nodejs
    sudo npm install -g npm@latest
    log "Node.js conflict fixed!"
    echo ""
    log "Current versions:"
    log "Node.js: $(node -v)"
    log "npm: $(npm -v)"
}

# =========================
# SELF-HEAL FUNCTION
# =========================
self_fix() {
    warn "Attempting self-repair for: $1"
    case "$1" in
        "apt-lock")
            force_clear_apt_locks
            ;;
        "update-failed")
            sudo apt clean
            safe_apt_update || true
            ;;
        "node-missing")
            install_nodejs_22
            ;;
        "npm-fix")
            sudo npm cache clean --force
            sudo npm install -g npm@latest
            ;;
        "node-version-conflict")
            fix_nodejs_conflict
            ;;
        "pnpm-missing")
            sudo npm install -g pnpm@latest || curl -fsSL https://get.pnpm.io/install.sh | sh -
            ;;
        "postgres-missing")
            safe_apt_update
            safe_apt_install postgresql-16 postgresql-contrib
            ;;
        *)
            warn "No fix method for $1"
            ;;
    esac
}

# =========================
# NGINX CONFIGURATION
# =========================
install_nginx() {
    step "10" "Installing & Configuring Nginx"
    
    if command -v nginx >/dev/null 2>&1; then
        log "Nginx already installed: $(nginx -v 2>&1)"
        
        # Ensure it's running
        if ! systemctl is-active --quiet nginx; then
            log "Starting Nginx service..."
            sudo systemctl enable nginx
            sudo systemctl start nginx
        fi
    else
        log "Installing Nginx..."
        safe_apt_install nginx
        sudo systemctl enable nginx
        sudo systemctl start nginx
    fi
    
    log "Nginx installed and running successfully"
}

configure_nginx() {
    section "CONFIGURING NGINX REVERSE PROXY"
    
    if [[ -z "$CAD_DOMAIN" ]] || [[ -z "$API_DOMAIN" ]]; then
        error "Domain variables not set. Please run full installation first."
        return 1
    fi
    
    log "Creating Nginx configuration for SnailyCAD..."
    
    # API Configuration
    API_CONFIG="/etc/nginx/sites-available/snailycad-api"
    sudo bash -c "cat > $API_CONFIG" <<EOFAPI
server {
    # API Server Configuration
    server_name ${API_DOMAIN};
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # Security headers
    add_header X-XSS-Protection          "1; mode=block" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header Referrer-Policy           "no-referrer" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-DNS-Prefetch-Control on;
    add_header Cross-Origin-Resource-Policy "cross-origin";
    
    listen 80;
}
EOFAPI
    
    # Client Configuration
    CLIENT_CONFIG="/etc/nginx/sites-available/snailycad-client"
    sudo bash -c "cat > $CLIENT_CONFIG" <<EOFCLIENT
server {
    # Client Server Configuration
    server_name ${CAD_DOMAIN};
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Security headers
    add_header X-XSS-Protection          "1; mode=block" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header Referrer-Policy           "no-referrer" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-DNS-Prefetch-Control on;
    add_header Cross-Origin-Resource-Policy "same-site";
    
    listen 80;
}
EOFCLIENT
    
    # Enable sites
    sudo ln -sf "$API_CONFIG" /etc/nginx/sites-enabled/snailycad-api 2>/dev/null || true
    sudo ln -sf "$CLIENT_CONFIG" /etc/nginx/sites-enabled/snailycad-client 2>/dev/null || true
    
    # Remove default site if exists
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    log "Testing Nginx configuration..."
    if sudo nginx -t; then
        log "Nginx configuration is valid"
        sudo systemctl reload nginx
        log "Nginx reloaded successfully"
    else
        error "Nginx configuration test failed!"
        return 1
    fi
    
    echo ""
    log "Nginx reverse proxy configured successfully!"
    info "API domain: $API_DOMAIN (proxies to localhost:8080)"
    info "Client domain: $CAD_DOMAIN (proxies to localhost:3000)"
    echo ""
    warn "Next steps:"
    info "1. Point your DNS records to this server's IP"
    info "2. Install SSL certificates with: sudo certbot --nginx"
}

setup_ssl() {
    section "SETTING UP SSL WITH CERTBOT"
    
    if ! command -v certbot >/dev/null 2>&1; then
        log "Installing Certbot..."
        safe_apt_install certbot python3-certbot-nginx
    else
        log "Certbot already installed"
    fi
    
    if [[ -z "$CAD_DOMAIN" ]] || [[ -z "$API_DOMAIN" ]]; then
        warn "Domain variables not set. Please configure manually."
        info "Run: sudo certbot --nginx"
        return
    fi
    
    echo ""
    warn "Before continuing, ensure:"
    info "1. DNS A records point to this server's IP:"
    info "   - $CAD_DOMAIN"
    info "   - $API_DOMAIN"
    info "2. Ports 80 and 443 are open in your firewall"
    echo ""
    read -p "Have you configured DNS and firewall? (y/n): " DNS_READY
    
    if [[ "$DNS_READY" != "y" ]]; then
        warn "Please configure DNS first, then run this option again"
        return
    fi
    
    # Ask for email
    echo ""
    read -p "Enter your email address for SSL certificate notifications: " CERT_EMAIL
    
    if [[ -z "$CERT_EMAIL" ]]; then
        error "Email is required for SSL certificates"
        return 1
    fi
    
    log "Running Certbot for SSL certificates..."
    log "Agreeing to Terms of Service: YES"
    log "Email sharing with EFF: NO (automatic)"
    
    # Run certbot with automatic answers: Y for ToS, N for email sharing
    echo -e "Y\nN" | sudo certbot --nginx \
        -d "$CAD_DOMAIN" \
        -d "$API_DOMAIN" \
        --email "$CERT_EMAIL" \
        --redirect || {
        warn "Certbot failed. You may need to run it manually:"
        info "sudo certbot --nginx"
        return 1
    }
    
    log "SSL certificates installed successfully!"
    
    # Setup auto-renewal
    log "Setting up automatic renewal..."
    sudo systemctl enable certbot.timer || true
    sudo systemctl start certbot.timer || true
    
    info "SSL is now active on your domains!"
}

# =========================
# MAIN MENU
# =========================
show_menu() {
    clear
    echo "============================================"
    echo " SNAILYCAD INSTALLER & MANAGER - WITH NGINX"
    echo "============================================"
    echo ""
    echo "Choose an option:"
    echo ""
    echo "  1. Quick Install (Complete Auto-Install)"
    echo "  2. Update & Deploy Existing Installation"
    echo "  3. Verify Installation (Diagnostics)"
    echo "  4. Setup Systemd Service"
    echo "  5. Database Setup Only"
    echo "  6. Clean Install (Remove & Reinstall)"
    echo "  7. Fix Node.js Version Conflict"
    echo "  8. Configure Nginx Reverse Proxy"
    echo "  9. Setup SSL Certificates (Certbot)"
    echo " 10. Exit"
    echo ""
    read -p "Enter your choice (1-10): " CHOICE
    echo ""
}

# =========================
# INSTALL NGINX & CERTBOT (AUTO)
# =========================
auto_install_nginx_certbot() {
    log "Installing Nginx..."
    safe_apt_update
    safe_apt_install nginx
    
    log "Starting Nginx service..."
    sudo systemctl enable nginx
    sudo systemctl start nginx
    
    log "Installing Certbot and Nginx plugin..."
    safe_apt_install certbot python3-certbot-nginx
    
    log "✓ Nginx and Certbot installed successfully!"
}

# =========================
# INSTALL PREREQUISITES
# =========================
install_prerequisites() {
    step "1" "Installing System Prerequisites"
    
    log "Updating package lists..."
    if ! safe_apt_update; then
        self_fix "update-failed"
    fi
    
    log "Upgrading existing packages..."
    safe_apt_install upgrade || warn "Upgrade had issues, continuing..."
    
    log "Installing base packages..."
    safe_apt_install git curl wget gnupg lsb-release software-properties-common pwgen
    
    # Auto-install Nginx and Certbot
    auto_install_nginx_certbot
    
    if command -v node >/dev/null 2>&1; then
        CURRENT_NODE=$(node -v)
        CURRENT_NPM=$(npm -v 2>/dev/null || echo "npm error")
        log "Current Node.js: $CURRENT_NODE"
        log "Current npm: $CURRENT_NPM"
        
        if [[ ! "$CURRENT_NODE" =~ v22\. ]]; then
            warn "Wrong Node.js version detected. Installing Node.js 22.x..."
            install_nodejs_22
        else
            log "Node.js 22.x already installed"
            if [[ "$CURRENT_NPM" == "npm error" ]]; then
                self_fix "npm-fix"
            fi
        fi
    else
        install_nodejs_22
    fi
    
    log "Updating npm to latest version..."
    sudo npm install -g npm@latest
    
    if ! command -v pnpm >/dev/null 2>&1; then
        log "Installing pnpm..."
        sudo npm install -g pnpm@latest
    else
        log "pnpm already installed: $(pnpm -v)"
    fi
    
    log "Prerequisites installed successfully!"
}

# =========================
# INSTALL POSTGRESQL
# =========================
install_postgresql() {
    step "2" "Installing PostgreSQL 16"
    
    if command -v psql >/dev/null 2>&1; then
        log "PostgreSQL already installed: $(psql --version)"
        return
    fi
    
    safe_apt_install wget gnupg lsb-release
    RELEASE=$(lsb_release -cs)
    echo "deb http://apt.postgresql.org/pub/repos/apt ${RELEASE}-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
    wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    safe_apt_update
    safe_apt_install postgresql-16 postgresql-contrib
    
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
    log "PostgreSQL 16 installed and running"
}

# =========================
# SETUP DATABASE
# =========================
setup_database() {
    step "3" "Setting Up Database"
    
    DB_PASSWORD=$(pwgen -s 20 1)
    DB_USER="snailycad"
    DB_NAME="snaily-cadv4"
    
    log "Generated secure database password"
    
    sudo -u postgres psql <<EOF 2>/dev/null || log "User/Database may already exist"
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
        CREATE USER "$DB_USER" WITH SUPERUSER PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE "$DB_NAME"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec

GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER";
EOF
    
    log "Database '$DB_NAME' and user '$DB_USER' ready"
    export DB_PASSWORD DB_USER DB_NAME
}

# =========================
# CLONE REPOSITORY
# =========================
clone_repository() {
    step "4" "Cloning Repository"
    
    if [[ -d "$PROJECT_PATH" ]]; then
        warn "Project directory already exists: $PROJECT_PATH"
        read -p "Remove and re-clone? (y/n): " RECLONE
        if [[ "$RECLONE" == "y" ]]; then
            sudo rm -rf "$PROJECT_PATH"
        else
            log "Keeping existing directory"
            return
        fi
    fi
    
    log "Cloning Snaily CAD repository..."
    cd /home
    git clone "$REPO_URL" || {
        error "Failed to clone repository"
        exit 1
    }
    
    log "Repository cloned successfully"
}

# =========================
# INSTALL DEPENDENCIES
# =========================
install_dependencies() {
    step "5" "Installing Project Dependencies"
    
    cd "$PROJECT_PATH" || {
        error "Cannot access project directory: $PROJECT_PATH"
        exit 1
    }
    
    log "Installing dependencies with pnpm (this may take several minutes)..."
    pnpm install || {
        error "Failed to install dependencies"
        exit 1
    }
    
    log "Dependencies installed successfully!"
}

# =========================
# GENERATE ENV FILE
# =========================
generate_env() {
    step "6" "Generating .env Configuration"
    
    cd "$PROJECT_PATH"
    
    if [ ! -f ".env.example" ]; then
        error ".env.example not found!"
        exit 1
    fi
    
    echo ""
    read -p "Enter CAD domain (e.g., cad.example.com): " CAD_DOMAIN
    read -p "Enter API domain (e.g., api.example.com): " API_DOMAIN
    read -p "Enter ROOT domain (e.g., example.com): " ROOT_DOMAIN
    echo ""
    
    # Export for nginx configuration
    export CAD_DOMAIN API_DOMAIN ROOT_DOMAIN
    
    JWT_SECRET=$(pwgen -s 32 1)
    ENCRYPTION_TOKEN=$(pwgen -s 32 1)
    
    log "Generating .env file..."
    
    if [[ -f ".env" ]]; then
        mv .env .env.backup.$(date +%s)
        info "Backed up existing .env file"
    fi
    
    cp .env.example .env
    
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
}

# =========================
# BUILD PROJECT
# =========================
build_project() {
    step "7" "Building Project"
    
    cd "$PROJECT_PATH"
    
    log "Building Snaily CAD (this may take several minutes)..."
    pnpm run build || {
        error "Build failed!"
        warn "You can manually build later with: cd $PROJECT_PATH && pnpm run build"
        return 1
    }
    
    log "Project built successfully!"
}

# =========================
# CREATE START SCRIPT
# =========================
create_start_script() {
    step "8" "Creating start.sh Script"
    
    START_SCRIPT="$PROJECT_PATH/start.sh"
    
    if [[ -f "$START_SCRIPT" ]]; then
        log "start.sh already exists"
        return
    fi
    
    cat > "$START_SCRIPT" <<'EOFSTART'
#!/bin/bash
set -e
set -o pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

log() { echo -e "${GREEN}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error_exit() { echo -e "${RED}[x]${NC} $1" >&2; exit 1; }

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:$HOME/.local/bin:/usr/local/lib/nodejs/bin:$PATH"

if [ -d "/usr/local/lib/nodejs" ]; then
    export PATH="/usr/local/lib/nodejs/bin:$PATH"
fi

if [ -d "$HOME/.local/share/pnpm" ]; then
    export PATH="$HOME/.local/share/pnpm:$PATH"
fi

log "Environment Information:"
log "Node: $(node -v)"
log "npm: $(npm -v)"
log "pnpm: $(command -v pnpm && pnpm -v || echo 'NOT FOUND')"
log "git: $(command -v git || echo 'NOT FOUND')"

deploy_project() {
    log "Starting project deployment..."
    
    PROJECT_DIR="/home/snaily-cadv4"
    
    if [[ ! -d "$PROJECT_DIR" ]]; then
        error_exit "Directory $PROJECT_DIR not found"
    fi
    
    cd "$PROJECT_DIR" || error_exit "Failed to change directory"
    
    command -v git >/dev/null 2>&1 || error_exit "git not found"
    command -v pnpm >/dev/null 2>&1 || error_exit "pnpm not found"
    command -v node >/dev/null 2>&1 || error_exit "node not found"
    
    log "Copying environment settings..."
    node scripts/copy-env.mjs --client --api || error_exit "Failed to copy env"
    
    log "Stashing local changes..."
    git stash save "pre-deploy-$(date +%F-%T)" >/dev/null 2>&1 || warn "No changes to stash"
    
    log "Fetching latest changes..."
    git fetch origin main || error_exit "Failed to fetch"
    
    log "Pulling latest changes..."
    git reset --hard origin/main || error_exit "Failed to reset"
    
    log "Installing dependencies..."
    pnpm install || error_exit "Failed to install dependencies"
    
    log "Building project..."
    pnpm run build || error_exit "Failed to build"
    
    log "Starting project..."
    pnpm run start || error_exit "Failed to start"
    
    log "Deployment completed successfully"
}

deploy_project
EOFSTART
    
    sudo chmod +x "$START_SCRIPT"
    log "start.sh is executable"
}

# =========================
# SETUP SYSTEMD SERVICE
# =========================
setup_systemd() {
    step "9" "Setting Up Systemd Service"
    
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    START_SCRIPT="$PROJECT_PATH/start.sh"
    
    if [[ ! -f "$START_SCRIPT" ]]; then
        create_start_script
    fi
    
    FULL_PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/root/.local/bin:/usr/local/lib/nodejs/bin:/opt/nodejs/bin"
    
    log "Creating systemd service file..."
    
    sudo bash -c "cat > $SERVICE_FILE" <<EOFSERVICE
[Unit]
Description=Start Snaily CADv4
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
ExecStart=/bin/bash ${START_SCRIPT}
StandardOutput=append:${PROJECT_PATH}/start.log
StandardError=append:${PROJECT_PATH}/start.log
User=root
WorkingDirectory=${PROJECT_PATH}
Restart=on-failure
RestartSec=10
Environment="PATH=${FULL_PATH}"
Environment="NODE_ENV=production"
Environment="HOME=/root"

[Install]
WantedBy=multi-user.target
EOFSERVICE
    
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}.service
    sudo systemctl restart ${SERVICE_NAME}.service
    
    log "Systemd service configured"
    sleep 3
    
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        log "Service is running successfully"
    else
        warn "Service may need manual intervention"
        systemctl status ${SERVICE_NAME}.service --no-pager -l | head -10
    fi
}

# =========================
# VERIFY INSTALLATION
# =========================
verify_installation() {
    section "Running System Verification"
    
    ISSUES_FOUND=0
    
    if command -v node >/dev/null 2>&1; then
        log "Node.js: $(node -v)"
        log "npm: $(npm -v)"
        
        if [[ ! "$(node -v)" =~ v22\. ]]; then
            error "Wrong Node.js version! Expected 22.x but got $(node -v)"
            ((ISSUES_FOUND++))
        fi
    else
        error "Node.js NOT installed"
        ((ISSUES_FOUND++))
    fi
    
    if command -v pnpm >/dev/null 2>&1; then
        log "pnpm: $(pnpm -v)"
    else
        error "pnpm NOT installed"
        ((ISSUES_FOUND++))
    fi
    
    if command -v psql >/dev/null 2>&1; then
        log "PostgreSQL: $(psql --version)"
        if systemctl is-active --quiet postgresql; then
            log "PostgreSQL service is running"
        else
            warn "PostgreSQL service NOT running"
        fi
    else
        error "PostgreSQL NOT installed"
        ((ISSUES_FOUND++))
    fi
    
    if command -v nginx >/dev/null 2>&1; then
        log "Nginx: $(nginx -v 2>&1)"
        if systemctl is-active --quiet nginx; then
            log "Nginx service is running"
        else
            warn "Nginx service NOT running"
        fi
    else
        warn "Nginx NOT installed"
    fi
    
    if [[ -d "$PROJECT_PATH" ]]; then
        log "Project directory exists: $PROJECT_PATH"
        
        if [[ -f "$PROJECT_PATH/package.json" ]]; then
            log "package.json found"
        else
            error "package.json NOT found"
            ((ISSUES_FOUND++))
        fi
        
        if [[ -f "$PROJECT_PATH/.env" ]]; then
            log ".env file exists"
        else
            warn ".env file NOT found"
        fi
        
        if [[ -f "$PROJECT_PATH/start.sh" ]]; then
            log "start.sh exists"
            if [[ -x "$PROJECT_PATH/start.sh" ]]; then
                log "start.sh is executable"
            else
                error "start.sh NOT executable"
                ((ISSUES_FOUND++))
            fi
        else
            error "start.sh NOT found"
            ((ISSUES_FOUND++))
        fi
    else
        error "Project directory NOT found: $PROJECT_PATH"
        ((ISSUES_FOUND++))
    fi
    
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        log "Systemd service file exists"
        
        if systemctl is-enabled --quiet ${SERVICE_NAME}.service 2>/dev/null; then
            log "Service is enabled"
        else
            warn "Service NOT enabled"
        fi
        
        if systemctl is-active --quiet ${SERVICE_NAME}.service; then
            log "Service is RUNNING"
        else
            error "Service NOT running"
            ((ISSUES_FOUND++))
            info "Status:"
            systemctl status ${SERVICE_NAME}.service --no-pager -l | head -10
        fi
    else
        warn "Systemd service NOT configured"
    fi
    
    # Check Nginx configs
    if [[ -f "/etc/nginx/sites-available/snailycad-api" ]]; then
        log "Nginx API config exists"
    else
        warn "Nginx API config NOT found"
    fi
    
    if [[ -f "/etc/nginx/sites-available/snailycad-client" ]]; then
        log "Nginx Client config exists"
    else
        warn "Nginx Client config NOT found"
    fi
    
    echo ""
    if [[ $ISSUES_FOUND -eq 0 ]]; then
        echo -e "${GREEN}✔ No critical issues found! System is ready.${NC}"
    else
        echo -e "${RED}✘ Found $ISSUES_FOUND issue(s) that need attention${NC}"
    fi
}

# =========================
# QUICK INSTALL
# =========================
quick_install() {
    section "QUICK INSTALL - Complete Setup"
    
    install_prerequisites
    install_postgresql
    setup_database
    
    read -p "Enter project directory (default: $DEFAULT_PROJECT_PATH): " input_dir
    PROJECT_PATH="${input_dir:-$DEFAULT_PROJECT_PATH}"
    
    clone_repository
    install_dependencies
    generate_env
    build_project
    create_start_script
    setup_systemd
    
    # Ask if user wants nginx setup
    echo ""
    read -p "Do you want to setup Nginx reverse proxy now? (y/n): " SETUP_NGINX
    if [[ "$SETUP_NGINX" == "y" ]]; then
        install_nginx
        configure_nginx
        
        echo ""
        read -p "Do you want to setup SSL certificates now? (y/n): " SETUP_SSL
        if [[ "$SETUP_SSL" == "y" ]]; then
            setup_ssl
        fi
    fi
    
    echo ""
    echo "=============================================="
    echo -e "${GREEN}✔ INSTALLATION COMPLETE!${NC}"
    echo "=============================================="
    echo ""
    verify_installation
    echo ""
    info "Project location: $PROJECT_PATH"
    info "Service name: ${SERVICE_NAME}.service"
    echo ""
    info "Useful commands:"
    echo "  sudo systemctl restart ${SERVICE_NAME}.service"
    echo "  sudo systemctl status ${SERVICE_NAME}.service"
    echo "  tail -f $PROJECT_PATH/start.log"
    echo "  sudo nginx -t  # Test nginx config"
    echo "  sudo systemctl reload nginx"
    echo ""
    
    if [[ "$SETUP_NGINX" == "y" ]]; then
        info "Your SnailyCAD is accessible at:"
        echo "  Client: http://$CAD_DOMAIN"
        echo "  API: http://$API_DOMAIN"
        echo ""
        if [[ "$SETUP_SSL" != "y" ]]; then
            warn "Don't forget to setup SSL with: sudo certbot --nginx"
        fi
    fi
}

# =========================
# UPDATE & DEPLOY
# =========================
update_deploy() {
    section "UPDATE & DEPLOY"
    
    echo "Enter project directory path (press Enter for default: $DEFAULT_PROJECT_PATH)"
    read -p "Path: " CUSTOM_PATH
    PROJECT_PATH="${CUSTOM_PATH:-$DEFAULT_PROJECT_PATH}"
    
    if [[ ! -d "$PROJECT_PATH" ]]; then
        error "Project directory not found: $PROJECT_PATH"
        warn "Please run Quick Install first (Option 1)"
        return
    fi
    
    cd "$PROJECT_PATH"
    
    log "Fetching latest code..."
    if [[ -d ".git" ]]; then
        git fetch origin main && git reset --hard origin/main
    else
        warn "Not a git repository. Skipping git operations."
    fi
    
    log "Installing dependencies..."
    pnpm install
    
    log "Building project..."
    pnpm run build
    
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        log "Restarting service..."
        sudo systemctl restart ${SERVICE_NAME}.service
    fi
    
    log "Update complete!"
}

# =========================
# CLEAN INSTALL
# =========================
clean_install() {
    section "CLEAN INSTALL - Remove & Reinstall"
    
    warn "This will remove $DEFAULT_PROJECT_PATH, all data, and PostgreSQL database!"
    read -p "Are you sure? Type 'yes' to confirm: " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log "Cancelled"
        return
    fi
    
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        log "Stopping service..."
        sudo systemctl stop ${SERVICE_NAME}.service
    fi
    
    if [[ -d "$DEFAULT_PROJECT_PATH" ]]; then
        log "Removing project directory..."
        sudo rm -rf "$DEFAULT_PROJECT_PATH"
    fi

    if command -v psql >/dev/null 2>&1; then
        read -p "Enter PostgreSQL database name to remove (or leave empty to skip): " DB_NAME
        if [[ -n "$DB_NAME" ]]; then
            log "Dropping PostgreSQL database $DB_NAME..."
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
            log "Database $DB_NAME removed."
        else
            log "Skipping PostgreSQL removal."
        fi
    else
        log "PostgreSQL not installed, skipping."
    fi
    
    log "Starting fresh installation..."
    quick_install
}

# =========================
# DATABASE SETUP ONLY
# =========================
database_only() {
    section "DATABASE SETUP ONLY"
    
    install_postgresql
    setup_database
    
    log "Database setup complete!"
    echo ""
    info "Database: $DB_NAME"
    info "User: $DB_USER"
    info "Password: $DB_PASSWORD"
    echo ""
    warn "Save these credentials!"
}

# =========================
# SERVICE SETUP ONLY
# =========================
service_only() {
    section "SYSTEMD SERVICE SETUP"
    
    read -p "Enter project directory (default: $DEFAULT_PROJECT_PATH): " input_dir
    PROJECT_PATH="${input_dir:-$DEFAULT_PROJECT_PATH}"
    
    if [[ ! -d "$PROJECT_PATH" ]]; then
        error "Project directory not found: $PROJECT_PATH"
        return
    fi
    
    create_start_script
    setup_systemd
    
    log "Service setup complete!"
}

# =========================
# NGINX SETUP ONLY
# =========================
nginx_only() {
    section "NGINX CONFIGURATION"
    
    read -p "Enter project directory (default: $DEFAULT_PROJECT_PATH): " input_dir
    PROJECT_PATH="${input_dir:-$DEFAULT_PROJECT_PATH}"
    
    if [[ ! -d "$PROJECT_PATH" ]]; then
        error "Project directory not found: $PROJECT_PATH"
        warn "Please run Quick Install first"
        return
    fi
    
    # Check if .env exists to get domains
    if [[ -f "$PROJECT_PATH/.env" ]]; then
        log "Reading domains from .env file..."
        CAD_DOMAIN=$(grep "NEXT_PUBLIC_CLIENT_URL" "$PROJECT_PATH/.env" | cut -d'=' -f2 | tr -d '"' | sed 's|https://||' | sed 's|http://||')
        API_DOMAIN=$(grep "NEXT_PUBLIC_PROD_ORIGIN" "$PROJECT_PATH/.env" | cut -d'=' -f2 | tr -d '"' | sed 's|https://||' | sed 's|http://||' | sed 's|/v1||')
        
        if [[ -n "$CAD_DOMAIN" ]] && [[ -n "$API_DOMAIN" ]]; then
            log "Found domains:"
            info "Client: $CAD_DOMAIN"
            info "API: $API_DOMAIN"
            read -p "Use these domains? (y/n): " USE_EXISTING
            
            if [[ "$USE_EXISTING" != "y" ]]; then
                read -p "Enter CAD domain (e.g., cad.example.com): " CAD_DOMAIN
                read -p "Enter API domain (e.g., api.example.com): " API_DOMAIN
            fi
        else
            read -p "Enter CAD domain (e.g., cad.example.com): " CAD_DOMAIN
            read -p "Enter API domain (e.g., api.example.com): " API_DOMAIN
        fi
    else
        read -p "Enter CAD domain (e.g., cad.example.com): " CAD_DOMAIN
        read -p "Enter API domain (e.g., api.example.com): " API_DOMAIN
    fi
    
    export CAD_DOMAIN API_DOMAIN
    
    install_nginx
    configure_nginx
    
    echo ""
    read -p "Do you want to setup SSL certificates now? (y/n): " SETUP_SSL
    if [[ "$SETUP_SSL" == "y" ]]; then
        setup_ssl
    fi
}

# =========================
# MAIN PROGRAM
# =========================
main() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    while true; do
        show_menu
        
        case $CHOICE in
            1)
                quick_install
                read -p "Press Enter to continue..."
                ;;
            2)
                update_deploy
                read -p "Press Enter to continue..."
                ;;
            3)
                PROJECT_PATH="$DEFAULT_PROJECT_PATH"
                verify_installation
                read -p "Press Enter to continue..."
                ;;
            4)
                service_only
                read -p "Press Enter to continue..."
                ;;
            5)
                database_only
                read -p "Press Enter to continue..."
                ;;
            6)
                clean_install
                read -p "Press Enter to continue..."
                ;;
            7)
                fix_nodejs_conflict
                read -p "Press Enter to continue..."
                ;;
            8)
                nginx_only
                read -p "Press Enter to continue..."
                ;;
            9)
                setup_ssl
                read -p "Press Enter to continue..."
                ;;
            10)
                log "Goodbye!"
                exit 0
                ;;
            *)
                warn "Invalid choice. Please enter a number between 1-10."
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

main "$@"
