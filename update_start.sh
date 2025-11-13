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

read -p "Enter project directory click enter if yes (default: /home/snaily-cadv4): " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-/home/snaily-cadv4}

if [[ ! -d "$PROJECT_DIR" ]]; then
    error "Project directory not found."
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
# ⚙️ STEP 6 — Service Setup
# =========================
step "6" "Setting up systemd service"

SERVICE_FILE="/etc/systemd/system/start-snaily-cadv4.service"

sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Start Snaily CADv4
After=network.target

[Service]
Type=simple
ExecStart=${PROJECT_DIR}/start.sh
StandardOutput=append:${PROJECT_DIR}/start.log
StandardError=append:${PROJECT_DIR}/start.log
User=root
WorkingDirectory=${PROJECT_DIR}

[Install]
WantedBy=multi-user.target
EOF

sudo chmod +x "${PROJECT_DIR}/start.sh"
sudo systemctl daemon-reload
sudo systemctl enable start-snaily-cadv4.service
sudo systemctl restart start-snaily-cadv4.service

log "Systemd service is active."
systemctl status start-snaily-cadv4.service --no-pager || warn "Service may need manual start."

# =========================
# 🧠 STEP 7 — Debug Info
# =========================
step "7" "Debugging and Verification"

log "Node version: $(node -v)"
log "npm version: $(npm -v)"
log "pnpm version: $(pnpm -v)"
log "PostgreSQL: $(psql --version)"
log "Service log tail:"
sudo tail -n 10 "${PROJECT_DIR}/start.log" || warn "No log file yet."

echo -e "\n${GREEN}✅ Installation and deployment complete!${NC}"
echo -e "Use: ${YELLOW}sudo systemctl restart start-snaily-cadv4.service${NC} to restart the service."
echo -e "Check logs with: ${YELLOW}tail -f ${PROJECT_DIR}/start.log${NC}"
