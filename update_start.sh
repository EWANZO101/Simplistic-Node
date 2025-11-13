#!/bin/bash
# ============================================================
# 🧠 update_start.sh — Automated Installer + Deployment Script
# ============================================================
# ✅ Notes:
#  - Uses latest pnpm, Node.js 22.x (via Nodesource), and PostgreSQL 16.
#  - Includes debug + self-healing (retries failed installs).
#  - Safe for Ubuntu 22.04+.
#  - Includes step-by-step confirmation prompts.
# ============================================================

set -e
set -o pipefail

# =========================
# 🎨 COLORS & LOG FUNCTIONS
# =========================
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

log() { echo -e "${GREEN}[✔]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1" >&2; }
step() { echo -e "\n${BLUE}=== STEP $1: $2 ===${NC}\n"; }

# =========================
# 🩺 SELF-HEAL FUNCTION
# =========================
self_fix() {
    warn "Attempting self-repair for: $1"
    case "$1" in
        "apt-lock")
            sudo rm -rf /var/lib/apt/lists/lock
            sudo rm -rf /var/cache/apt/archives/lock
            sudo rm -rf /var/lib/dpkg/lock*
            sudo dpkg --configure -a
            ;;
        "update-failed")
            sudo apt clean
            sudo apt update -y || true
            ;;
        "node-missing")
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo apt install -y nodejs
            ;;
        "pnpm-missing")
            sudo npm install -g pnpm@latest || curl -fsSL https://get.pnpm.io/install.sh | sh -
            ;;
        "postgres-missing")
            sudo apt update -y
            sudo apt install -y postgresql-16 postgresql-contrib
            ;;
        *)
            warn "No fix method for $1"
            ;;
    esac
}

# =========================
# 🧩 STEP 1 — System Update
# =========================
step "1" "Updating system packages"
if ! sudo apt update && sudo apt upgrade -y; then
    self_fix "update-failed"
fi
log "System packages updated successfully."

# =========================
# 🟢 STEP 2 — Node.js Setup
# =========================
step "2" "Installing Node.js 22.x"
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt install -y nodejs || self_fix "node-missing"
else
    log "Node.js already installed: $(node -v)"
fi

# Update npm
sudo npm install -g npm@latest || self_fix "npm-missing"
log "Node.js and npm are ready."

# =========================
# 🔵 STEP 3 — pnpm Install
# =========================
step "3" "Installing pnpm (latest)"
if ! command -v pnpm >/dev/null 2>&1; then
    sudo npm install -g pnpm@latest || self_fix "pnpm-missing"
else
    log "pnpm already installed: $(pnpm -v)"
fi

# =========================
# 🐘 STEP 4 — PostgreSQL 16
# =========================
step "4" "Installing PostgreSQL 16"
if ! command -v psql >/dev/null 2>&1; then
    sudo apt install -y wget gnupg lsb-release
    RELEASE=$(lsb_release -cs)
    echo "deb http://apt.postgresql.org/pub/repos/apt ${RELEASE}-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
    wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    sudo apt update -y
    sudo apt install -y postgresql-16 postgresql-contrib || self_fix "postgres-missing"
else
    log "PostgreSQL already installed: $(psql --version)"
fi
sudo systemctl enable postgresql
sudo systemctl start postgresql
log "PostgreSQL 16 is running."

# =========================
# 🧰 STEP 5 — Deploy Project
# =========================
step "5" "Deploying Snaily-CADv4"

read -p "Enter project directory (default: /home/snaily-cadv4): " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-/home/snaily-cadv4}

if [[ ! -d "$PROJECT_DIR" ]]; then
    error "Project directory not found: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

log "Fetching latest code..."
git fetch origin main && git reset --hard origin/main

log "Installing dependencies..."
pnpm install || { self_fix "pnpm-missing"; pnpm install; }

log "Building project..."
pnpm run build || error "Build failed. Check logs."

# =========================
# 🔍 STEP 6 — Get or Create start.sh
# =========================
step "6" "Setting up start.sh script"

START_SCRIPT="${PROJECT_DIR}/start.sh"

# Check if start.sh already exists
if [[ -f "$START_SCRIPT" ]]; then
    log "start.sh already exists. Keeping existing file."
else
    log "start.sh not found. Downloading from GitHub..."
    
    # Try to download from GitHub
    if curl -fsSL https://raw.githubusercontent.com/EWANZO101/Simplistic-Node/main/start.sh -o "$START_SCRIPT"; then
        log "Successfully downloaded start.sh from GitHub"
    else
        warn "Failed to download from GitHub. Creating default start.sh..."
        
        cat > "$START_SCRIPT" <<'EOFSTART'
#!/bin/bash
set -e
set -o pipefail

# Colors for better readability
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# Function to print status messages
log() {
    echo -e "${GREEN}[*]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error_exit() {
    echo -e "${RED}[x]${NC} $1" >&2
    exit 1
}

# Set up PATH to include common binary locations
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:$HOME/.local/bin:$PATH"

# Add Node.js and npm paths
if [ -d "/usr/local/lib/nodejs" ]; then
    export PATH="/usr/local/lib/nodejs/bin:$PATH"
fi

# Add pnpm path if installed globally
if [ -d "$HOME/.local/share/pnpm" ]; then
    export PATH="$HOME/.local/share/pnpm:$PATH"
fi

# Log environment for debugging
log "Environment Information:"
log "PATH: $PATH"
log "Node: $(command -v node || echo 'NOT FOUND')"
log "pnpm: $(command -v pnpm || echo 'NOT FOUND')"
log "git: $(command -v git || echo 'NOT FOUND')"

# Function to deploy the project
deploy_project() {
    log "Starting project deployment..."
    
    PROJECT_DIR="/home/snaily-cadv4"
    
    if [[ ! -d "$PROJECT_DIR" ]]; then
        error_exit "Directory $PROJECT_DIR not found or inaccessible."
    fi
    
    cd "$PROJECT_DIR" || error_exit "Failed to change directory to $PROJECT_DIR."
    
    # Ensure git and pnpm are available
    command -v git >/dev/null 2>&1 || error_exit "git not found. Please install git."
    command -v pnpm >/dev/null 2>&1 || error_exit "pnpm not found. Please install pnpm."
    command -v node >/dev/null 2>&1 || error_exit "node not found. Please install Node.js."
    
    # Copy environment settings
    log "Copying environment settings..."
    if ! node scripts/copy-env.mjs --client --api; then
        error_exit "Failed to copy environment settings."
    fi
    
    # Git operations
    log "Stashing any local changes..."
    git stash save "pre-deploy-$(date +%F-%T)" >/dev/null 2>&1 || warn "No changes to stash."
    
    log "Fetching latest changes from origin/main..."
    git fetch origin main || error_exit "Failed to fetch from git."
    
    log "Pulling latest changes..."
    git reset --hard origin/main || error_exit "Failed to reset to latest commit."
    
    # Install dependencies
    log "Installing dependencies with pnpm..."
    pnpm install || error_exit "Failed to install dependencies."
    
    # Build the project
    log "Building the project..."
    pnpm run build || error_exit "Failed to build the project."
    
    # Start the project
    log "Starting the project..."
    pnpm run start || error_exit "Failed to start the project."
    
    log "✅ Deployment completed successfully."
}

# Execute deployment
deploy_project
EOFSTART

# Make start.sh executable
sudo chmod +x "$START_SCRIPT"
log "start.sh created and made executable"

# =========================
# ⚙️ STEP 7 — Service Setup
# =========================
step "7" "Setting up systemd service"

SERVICE_FILE="/etc/systemd/system/start-snaily-cadv4.service"

sudo bash -c "cat > $SERVICE_FILE" <<EOFSERVICE
[Unit]
Description=Start Snaily CADv4
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
ExecStart=/bin/bash ${START_SCRIPT}
StandardOutput=append:${PROJECT_DIR}/start.log
StandardError=append:${PROJECT_DIR}/start.log
User=root
WorkingDirectory=${PROJECT_DIR}
Restart=on-failure
RestartSec=10
Environment="PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/root/.local/bin"
Environment="NODE_ENV=production"

[Install]
WantedBy=multi-user.target
EOFSERVICE

sudo systemctl daemon-reload
sudo systemctl enable start-snaily-cadv4.service
sudo systemctl restart start-snaily-cadv4.service

log "Systemd service is active."
sleep 3
systemctl status start-snaily-cadv4.service --no-pager || warn "Service may need manual start."

# =========================
# 🧠 STEP 8 — Debug Info
# =========================
step "8" "Debugging and Verification"

log "Node version: $(node -v)"
log "npm version: $(npm -v)"
log "pnpm version: $(pnpm -v)"
log "PostgreSQL: $(psql --version)"
log "Project directory contents:"
ls -la "$PROJECT_DIR" | head -20

if [[ -f "${PROJECT_DIR}/start.log" ]]; then
    log "Service log tail:"
    sudo tail -n 20 "${PROJECT_DIR}/start.log"
else
    warn "No log file yet. Wait a moment and check: tail -f ${PROJECT_DIR}/start.log"
fi

echo -e "\n${GREEN}✅ Installation and deployment complete!${NC}"
echo -e "\n${BLUE}Quick Reference Commands:${NC}"
echo -e "  Restart service:  ${YELLOW}sudo systemctl restart start-snaily-cadv4.service${NC}"
echo -e "  Stop service:     ${YELLOW}sudo systemctl stop start-snaily-cadv4.service${NC}"
echo -e "  Service status:   ${YELLOW}sudo systemctl status start-snaily-cadv4.service${NC}"
echo -e "  View logs:        ${YELLOW}tail -f ${PROJECT_DIR}/start.log${NC}"
echo -e "  View last 50:     ${YELLOW}tail -n 50 ${PROJECT_DIR}/start.log${NC}"
echo -e ""
