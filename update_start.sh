#!/bin/bash
# ============================================================
# 🔍 Double-Check Script for Snaily CADv4 Deployment
# ============================================================
# This script verifies the installation and diagnoses issues
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

PROJECT_DIR="${1:-/home/snaily-cadv4}"
ISSUES_FOUND=0

# ============================================================
# SECTION 1: System Requirements
# ============================================================
section "1. Checking System Requirements"

# Node.js
if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node -v)
    log "Node.js installed: $NODE_VERSION"
    info "  Path: $(which node)"
else
    error "Node.js NOT installed"
    ((ISSUES_FOUND++))
fi

# npm
if command -v npm >/dev/null 2>&1; then
    NPM_VERSION=$(npm -v)
    log "npm installed: $NPM_VERSION"
    info "  Path: $(which npm)"
else
    error "npm NOT installed"
    ((ISSUES_FOUND++))
fi

# pnpm
if command -v pnpm >/dev/null 2>&1; then
    PNPM_VERSION=$(pnpm -v)
    log "pnpm installed: $PNPM_VERSION"
    info "  Path: $(which pnpm)"
else
    error "pnpm NOT installed"
    ((ISSUES_FOUND++))
fi

# git
if command -v git >/dev/null 2>&1; then
    GIT_VERSION=$(git --version)
    log "git installed: $GIT_VERSION"
    info "  Path: $(which git)"
else
    error "git NOT installed"
    ((ISSUES_FOUND++))
fi

# PostgreSQL
if command -v psql >/dev/null 2>&1; then
    PSQL_VERSION=$(psql --version)
    log "PostgreSQL installed: $PSQL_VERSION"
    info "  Path: $(which psql)"
    
    if systemctl is-active --quiet postgresql; then
        log "PostgreSQL service is running"
    else
        warn "PostgreSQL service is NOT running"
        info "  Start with: sudo systemctl start postgresql"
    fi
else
    error "PostgreSQL NOT installed"
    ((ISSUES_FOUND++))
fi

# ============================================================
# SECTION 2: Project Directory
# ============================================================
section "2. Checking Project Directory"

if [[ -d "$PROJECT_DIR" ]]; then
    log "Project directory exists: $PROJECT_DIR"
    
    # Check permissions
    if [[ -r "$PROJECT_DIR" ]]; then
        log "Directory is readable"
    else
        error "Directory is NOT readable"
        ((ISSUES_FOUND++))
    fi
    
    # List important files
    info "Directory contents:"
    ls -lah "$PROJECT_DIR" | head -15
    
    # Check for package.json
    if [[ -f "$PROJECT_DIR/package.json" ]]; then
        log "package.json found"
    else
        error "package.json NOT found"
        ((ISSUES_FOUND++))
    fi
    
    # Check for node_modules
    if [[ -d "$PROJECT_DIR/node_modules" ]]; then
        log "node_modules directory exists"
    else
        warn "node_modules NOT found - dependencies may not be installed"
    fi
    
    # Check for .env files
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        log ".env file found"
    else
        warn ".env file NOT found"
    fi
    
else
    error "Project directory NOT found: $PROJECT_DIR"
    ((ISSUES_FOUND++))
fi

# ============================================================
# SECTION 3: start.sh Script
# ============================================================
section "3. Checking start.sh Script"

START_SCRIPT="$PROJECT_DIR/start.sh"

if [[ -f "$START_SCRIPT" ]]; then
    log "start.sh exists"
    
    # Check if executable
    if [[ -x "$START_SCRIPT" ]]; then
        log "start.sh is executable"
    else
        error "start.sh is NOT executable"
        info "  Fix with: sudo chmod +x $START_SCRIPT"
        ((ISSUES_FOUND++))
    fi
    
    # Show first few lines
    info "start.sh preview (first 10 lines):"
    head -10 "$START_SCRIPT" | sed 's/^/    /'
    
    # Check for shebang
    if head -1 "$START_SCRIPT" | grep -q "^#!"; then
        log "Shebang found in start.sh"
    else
        warn "No shebang found in start.sh"
    fi
    
else
    error "start.sh NOT found at $START_SCRIPT"
    ((ISSUES_FOUND++))
fi

# ============================================================
# SECTION 4: Systemd Service
# ============================================================
section "4. Checking Systemd Service"

SERVICE_FILE="/etc/systemd/system/start-snaily-cadv4.service"

if [[ -f "$SERVICE_FILE" ]]; then
    log "Service file exists: $SERVICE_FILE"
    
    info "Service file content:"
    cat "$SERVICE_FILE" | sed 's/^/    /'
    
    # Check if enabled
    if systemctl is-enabled --quiet start-snaily-cadv4.service 2>/dev/null; then
        log "Service is enabled (will start on boot)"
    else
        warn "Service is NOT enabled"
        info "  Enable with: sudo systemctl enable start-snaily-cadv4.service"
    fi
    
    # Check if active
    if systemctl is-active --quiet start-snaily-cadv4.service; then
        log "Service is RUNNING"
    else
        error "Service is NOT running"
        ((ISSUES_FOUND++))
        
        # Get the status
        info "Service status:"
        systemctl status start-snaily-cadv4.service --no-pager -l | sed 's/^/    /'
    fi
    
    # Check for recent failures
    FAILED_COUNT=$(systemctl show start-snaily-cadv4.service -p NRestarts --value)
    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        warn "Service has failed and restarted $FAILED_COUNT times"
    fi
    
else
    error "Service file NOT found: $SERVICE_FILE"
    ((ISSUES_FOUND++))
fi

# ============================================================
# SECTION 5: Logs Analysis
# ============================================================
section "5. Analyzing Logs"

LOG_FILE="$PROJECT_DIR/start.log"

if [[ -f "$LOG_FILE" ]]; then
    log "Log file exists: $LOG_FILE"
    
    LOG_SIZE=$(du -h "$LOG_FILE" | cut -f1)
    info "Log file size: $LOG_SIZE"
    
    info "Last 30 lines of log:"
    tail -30 "$LOG_FILE" | sed 's/^/    /'
    
    # Check for common errors
    echo ""
    if grep -q "command not found" "$LOG_FILE" 2>/dev/null; then
        error "Found 'command not found' errors in logs"
        ((ISSUES_FOUND++))
    fi
    
    if grep -q "pnpm not found\|node not found\|git not found" "$LOG_FILE" 2>/dev/null; then
        error "Missing binary errors found in logs"
        ((ISSUES_FOUND++))
    fi
    
    if grep -q "error\|Error\|ERROR" "$LOG_FILE" 2>/dev/null; then
        warn "Error messages found in logs"
        info "Showing error lines:"
        grep -i "error" "$LOG_FILE" | tail -5 | sed 's/^/    /'
    fi
    
else
    warn "Log file NOT found: $LOG_FILE"
    info "Log file will be created when service starts"
fi

# Check systemd journal
info "Recent systemd journal entries:"
journalctl -u start-snaily-cadv4.service -n 10 --no-pager 2>/dev/null | sed 's/^/    /' || warn "Could not read journal"

# ============================================================
# SECTION 6: Environment & PATH
# ============================================================
section "6. Environment Check"

info "Current PATH:"
echo "    $PATH"

info "PATH in service (from systemd):"
systemctl show start-snaily-cadv4.service -p Environment --value | sed 's/^/    /' 2>/dev/null || warn "Could not read service environment"

# Check what user the service runs as
SERVICE_USER=$(systemctl show start-snaily-cadv4.service -p User --value 2>/dev/null)
info "Service runs as user: ${SERVICE_USER:-unknown}"

# ============================================================
# SECTION 7: Port Check
# ============================================================
section "7. Network & Ports"

# Check common ports
for PORT in 3000 3001 5432 80 443; do
    if ss -tuln | grep -q ":$PORT "; then
        log "Port $PORT is in use"
        info "  $(ss -tuln | grep ":$PORT " | head -1)"
    else
        info "Port $PORT is free"
    fi
done

# ============================================================
# SECTION 8: Summary & Recommendations
# ============================================================
section "8. Summary & Recommendations"

if [[ $ISSUES_FOUND -eq 0 ]]; then
    echo -e "${GREEN}✅ No critical issues found!${NC}"
else
    echo -e "${RED}⚠️  Found $ISSUES_FOUND issue(s) that need attention${NC}"
fi

echo -e "\n${BLUE}Quick Fix Commands:${NC}"
echo -e "  ${YELLOW}# If service not running:${NC}"
echo -e "    sudo systemctl restart start-snaily-cadv4.service"
echo -e ""
echo -e "  ${YELLOW}# If start.sh not executable:${NC}"
echo -e "    sudo chmod +x $START_SCRIPT"
echo -e ""
echo -e "  ${YELLOW}# Test start.sh manually:${NC}"
echo -e "    cd $PROJECT_DIR && bash start.sh"
echo -e ""
echo -e "  ${YELLOW}# View live logs:${NC}"
echo -e "    tail -f $LOG_FILE"
echo -e ""
echo -e "  ${YELLOW}# View systemd journal:${NC}"
echo -e "    journalctl -u start-snaily-cadv4.service -f"
echo -e ""
echo -e "  ${YELLOW}# Re-run installation:${NC}"
echo -e "    sudo ./update_start.sh"
echo -e ""

# Exit with error code if issues found
exit $ISSUES_FOUND
