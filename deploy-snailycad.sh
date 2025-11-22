#!/bin/bash
################################################################################
# SnailyCADv4 Professional Deployment Script
# Version: 2.0.1 - FIXED .env handling
# Description: Automated deployment with validation, backup, and rollback
################################################################################

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------
readonly SCRIPT_VERSION="2.0.1"
readonly PROJECT_DIR="${PROJECT_DIR:-/home/snaily-cadv4}"
readonly ENV_FILE="${PROJECT_DIR}/.env"
readonly SERVICE_NAME="start-snaily-cadv4.service"
readonly SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
readonly BACKUP_DIR="${PROJECT_DIR}/backups"
readonly LOG_FILE="${PROJECT_DIR}/deployment.log"
readonly LOCKFILE="/var/lock/snailycad-deploy.lock"

# ------------------------------------------------------------------------------
# COLORS AND FORMATTING
# ------------------------------------------------------------------------------
readonly GREEN="\033[0;32m"
readonly RED="\033[0;31m"
readonly YELLOW="\033[1;33m"
readonly BLUE="\033[0;34m"
readonly CYAN="\033[0;36m"
readonly BOLD="\033[1m"
readonly NC="\033[0m"

# ------------------------------------------------------------------------------
# LOGGING FUNCTIONS
# ------------------------------------------------------------------------------
log() {
    local msg="$1"
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${msg}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} ${msg}"
    echo "[INFO] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} ${msg}"
    echo "[WARN] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} ${msg}" >&2
    echo "[ERROR] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

error_exit() {
    error "$1"
    cleanup
    exit 1
}

success() {
    local msg="$1"
    echo -e "${GREEN}[✓]${NC} ${msg}"
    echo "[SUCCESS] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# UTILITY FUNCTIONS
# ------------------------------------------------------------------------------
print_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║           SnailyCADv4 Professional Deployment Tool            ║
║                        Version 2.0.1                          ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

create_lockfile() {
    if [ -f "${LOCKFILE}" ]; then
        error_exit "Another deployment is already running. Lock file exists: ${LOCKFILE}"
    fi
    echo $$ > "${LOCKFILE}"
    log "Lock file created: ${LOCKFILE}"
}

cleanup() {
    if [ -f "${LOCKFILE}" ]; then
        rm -f "${LOCKFILE}"
        log "Lock file removed"
    fi
}

trap cleanup EXIT INT TERM

check_root() {
    if [ "${EUID}" -eq 0 ]; then
        warn "Running as root. This is acceptable for service installation."
    fi
}

confirm_action() {
    local prompt="$1"
    local response
    
    echo -ne "${YELLOW}${prompt} (y/n): ${NC}"
    read -r response
    
    case "${response,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

validate_command() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        error_exit "${cmd} is not installed. Please install it first."
    fi
    success "${cmd} is installed"
}

# ------------------------------------------------------------------------------
# SYSTEM CHECKS
# ------------------------------------------------------------------------------
check_dependencies() {
    log "Checking system dependencies..."
    
    local required_commands=("git" "node" "pnpm" "systemctl")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            success "${cmd} ✓"
        else
            missing_commands+=("${cmd}")
            error "${cmd} ✗ (missing)"
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        error_exit "Missing required commands: ${missing_commands[*]}"
    fi
    
    # Check versions
    info "Node version: $(node --version)"
    info "pnpm version: $(pnpm --version)"
    info "Git version: $(git --version)"
}

check_project_directory() {
    log "Validating project directory..."
    
    if [ ! -d "${PROJECT_DIR}" ]; then
        error_exit "Project directory does not exist: ${PROJECT_DIR}"
    fi
    
    cd "${PROJECT_DIR}" || error_exit "Cannot access project directory"
    
    if [ ! -d ".git" ]; then
        error_exit "Not a git repository: ${PROJECT_DIR}"
    fi
    
    if [ ! -f "package.json" ]; then
        error_exit "package.json not found in ${PROJECT_DIR}"
    fi
    
    success "Project directory validated: ${PROJECT_DIR}"
}

check_disk_space() {
    log "Checking available disk space..."
    
    local available_space=$(df -BG "${PROJECT_DIR}" | awk 'NR==2 {print $4}' | sed 's/G//')
    local required_space=5
    
    if [ "${available_space}" -lt "${required_space}" ]; then
        warn "Low disk space: ${available_space}GB available (${required_space}GB recommended)"
        if ! confirm_action "Continue anyway?"; then
            error_exit "Deployment cancelled due to low disk space"
        fi
    else
        success "Sufficient disk space: ${available_space}GB available"
    fi
}

# ------------------------------------------------------------------------------
# BACKUP FUNCTIONS
# ------------------------------------------------------------------------------
create_backup() {
    log "Creating backup..."
    
    mkdir -p "${BACKUP_DIR}"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/backup_${timestamp}.tar.gz"
    
    # Backup critical files
    tar -czf "${backup_file}" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='backups' \
        -C "${PROJECT_DIR}" . 2>/dev/null || warn "Backup completed with warnings"
    
    if [ -f "${backup_file}" ]; then
        success "Backup created: ${backup_file}"
        info "Backup size: $(du -h "${backup_file}" | cut -f1)"
        
        # Keep only last 5 backups
        cleanup_old_backups
    else
        warn "Backup file was not created"
    fi
}

cleanup_old_backups() {
    log "Cleaning up old backups (keeping last 5)..."
    
    cd "${BACKUP_DIR}" || return
    
    ls -t backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
    
    local backup_count=$(ls -1 backup_*.tar.gz 2>/dev/null | wc -l)
    info "Current backups: ${backup_count}"
}

# ------------------------------------------------------------------------------
# ENVIRONMENT CONFIGURATION
# ------------------------------------------------------------------------------
validate_env_value() {
    local name="$1"
    local value="$2"
    
    # Remove any surrounding quotes
    value=$(echo "${value}" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    
    case "${name}" in
        DISCORD_BOT_TOKEN)
            if [[ ! "${value}" =~ ^[A-Za-z0-9._-]{50,}$ ]] && [ -n "${value}" ]; then
                warn "Discord bot token format may be invalid"
            fi
            ;;
        DISCORD_SERVER_ID|DISCORD_CLIENT_ID)
            if [[ ! "${value}" =~ ^[0-9]{17,19}$ ]] && [ -n "${value}" ]; then
                warn "${name} should be a Discord snowflake ID (17-19 digits)"
            fi
            ;;
        STEAM_API_KEY)
            if [[ ! "${value}" =~ ^[A-F0-9]{32}$ ]] && [ -n "${value}" ]; then
                warn "Steam API key should be 32 hexadecimal characters"
            fi
            ;;
    esac
    
    echo "${value}"
}

prompt_env_variable() {
    local name="$1"
    local current="$2"
    local result
    
    echo ""
    echo -e "${CYAN}${BOLD}${name}${NC}"
    echo -e "${YELLOW}Paste the raw value (no quotes - they will be added automatically)${NC}"
    
    # Display current value more clearly
    if [ -n "${current}" ]; then
        echo -e "Current value: ${GREEN}${current:0:10}...${current: -4}${NC} (${#current} characters)"
    else
        echo -e "Current value: ${RED}(not set)${NC}"
    fi
    
    echo -ne "Enter new value (or press Enter to keep current): "
    read -r result
    
    # If user just pressed Enter, keep the current value
    if [ -z "${result}" ]; then
        echo "${current}"
    else
        # Validate and return the new value
        validate_env_value "${name}" "${result}"
    fi
}

configure_environment() {
    log "Configuring environment variables..."
    
    touch "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"  # Secure the env file
    
    # Load existing values - handle both quoted and unquoted formats
    local BOT="" SERVER="" CLIENT="" SECRET="" STEAM=""
    
    if [ -f "${ENV_FILE}" ] && [ -s "${ENV_FILE}" ]; then
        info "Loading existing environment values..."
        
        # Read values, handling quotes properly
        BOT=$(grep '^DISCORD_BOT_TOKEN=' "${ENV_FILE}" 2>/dev/null | sed 's/^DISCORD_BOT_TOKEN=//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || echo "")
        SERVER=$(grep '^DISCORD_SERVER_ID=' "${ENV_FILE}" 2>/dev/null | sed 's/^DISCORD_SERVER_ID=//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || echo "")
        CLIENT=$(grep '^DISCORD_CLIENT_ID=' "${ENV_FILE}" 2>/dev/null | sed 's/^DISCORD_CLIENT_ID=//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || echo "")
        SECRET=$(grep '^DISCORD_CLIENT_SECRET=' "${ENV_FILE}" 2>/dev/null | sed 's/^DISCORD_CLIENT_SECRET=//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || echo "")
        STEAM=$(grep '^STEAM_API_KEY=' "${ENV_FILE}" 2>/dev/null | sed 's/^STEAM_API_KEY=//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || echo "")
    fi
    
    echo -e "\n${BOLD}Environment Configuration${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}Enter your credentials. Press Enter to keep existing values.${NC}"
    
    # Prompt for each variable and capture the return value properly
    BOT=$(prompt_env_variable "DISCORD_BOT_TOKEN" "${BOT}")
    SERVER=$(prompt_env_variable "DISCORD_SERVER_ID" "${SERVER}")
    CLIENT=$(prompt_env_variable "DISCORD_CLIENT_ID" "${CLIENT}")
    SECRET=$(prompt_env_variable "DISCORD_CLIENT_SECRET" "${SECRET}")
    STEAM=$(prompt_env_variable "STEAM_API_KEY" "${STEAM}")
    
    # Write environment file with proper formatting
    log "Writing configuration to ${ENV_FILE}..."
    
    {
        echo "# SnailyCAD Environment Configuration"
        echo "# Generated: $(date)"
        echo ""
        echo "# Discord Bot Configuration"
        if [ -n "${BOT}" ]; then
            echo "DISCORD_BOT_TOKEN=\"${BOT}\""
        else
            echo "DISCORD_BOT_TOKEN=\"\""
        fi
        
        if [ -n "${SERVER}" ]; then
            echo "DISCORD_SERVER_ID=\"${SERVER}\""
        else
            echo "DISCORD_SERVER_ID=\"\""
        fi
        
        echo ""
        echo "# Discord OAuth Configuration"
        
        if [ -n "${CLIENT}" ]; then
            echo "DISCORD_CLIENT_ID=\"${CLIENT}\""
        else
            echo "DISCORD_CLIENT_ID=\"\""
        fi
        
        if [ -n "${SECRET}" ]; then
            echo "DISCORD_CLIENT_SECRET=\"${SECRET}\""
        else
            echo "DISCORD_CLIENT_SECRET=\"\""
        fi
        
        echo ""
        echo "# Steam API Configuration"
        
        if [ -n "${STEAM}" ]; then
            echo "STEAM_API_KEY=\"${STEAM}\""
        else
            echo "STEAM_API_KEY=\"\""
        fi
    } > "${ENV_FILE}"
    
    chmod 600 "${ENV_FILE}"
    success "Environment file updated: ${ENV_FILE}"
    
    # Show what was written (with values masked for security)
    echo -e "\n${BOLD}Configuration Summary:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -n "${BOT}" ]; then
        echo -e "  ${CYAN}DISCORD_BOT_TOKEN:${NC}       ${GREEN}SET${NC} (${#BOT} chars) ...${BOT: -4}"
    else
        echo -e "  ${CYAN}DISCORD_BOT_TOKEN:${NC}       ${RED}EMPTY${NC}"
    fi
    
    if [ -n "${SERVER}" ]; then
        echo -e "  ${CYAN}DISCORD_SERVER_ID:${NC}      ${GREEN}SET${NC} (${SERVER})"
    else
        echo -e "  ${CYAN}DISCORD_SERVER_ID:${NC}      ${RED}EMPTY${NC}"
    fi
    
    if [ -n "${CLIENT}" ]; then
        echo -e "  ${CYAN}DISCORD_CLIENT_ID:${NC}      ${GREEN}SET${NC} (${CLIENT})"
    else
        echo -e "  ${CYAN}DISCORD_CLIENT_ID:${NC}      ${RED}EMPTY${NC}"
    fi
    
    if [ -n "${SECRET}" ]; then
        echo -e "  ${CYAN}DISCORD_CLIENT_SECRET:${NC}  ${GREEN}SET${NC} (${#SECRET} chars) ...${SECRET: -4}"
    else
        echo -e "  ${CYAN}DISCORD_CLIENT_SECRET:${NC}  ${RED}EMPTY${NC}"
    fi
    
    if [ -n "${STEAM}" ]; then
        echo -e "  ${CYAN}STEAM_API_KEY:${NC}          ${GREEN}SET${NC} (${#STEAM} chars) ...${STEAM: -4}"
    else
        echo -e "  ${CYAN}STEAM_API_KEY:${NC}          ${RED}EMPTY${NC}"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Verify the file was written correctly
    if [ -f "${ENV_FILE}" ] && [ -s "${ENV_FILE}" ]; then
        local line_count=$(wc -l < "${ENV_FILE}")
        success "Verified: .env file contains ${line_count} lines"
    else
        error "Warning: .env file appears to be empty or missing!"
    fi
    
    # Manual review option
    echo ""
    if confirm_action "Would you like to manually review/edit the .env file in nano?"; then
        warn "Opening .env in nano for review..."
        echo -e "${YELLOW}Press CTRL+O then Enter to save, CTRL+X to exit${NC}"
        sleep 2
        nano "${ENV_FILE}"
        success "Manual review completed"
    fi
}

# ------------------------------------------------------------------------------
# SERVICE MANAGEMENT
# ------------------------------------------------------------------------------
stop_existing_services() {
    log "Stopping existing services..."
    
    # Stop PM2 if running
    if command -v pm2 >/dev/null 2>&1; then
        if pm2 list | grep -q "online"; then
            warn "Stopping PM2 processes..."
            pm2 stop all || warn "PM2 stop failed"
            pm2 delete all || warn "PM2 delete failed"
            success "PM2 processes stopped"
        fi
    fi
    
    # Stop systemd service if running
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        warn "Stopping systemd service..."
        sudo systemctl stop "${SERVICE_NAME}" || warn "Failed to stop service"
        success "Systemd service stopped"
    fi
}

install_systemd_service() {
    log "Installing systemd service..."
    
    # Validate pnpm path
    local pnpm_path=$(command -v pnpm)
    if [ -z "${pnpm_path}" ]; then
        error_exit "pnpm executable not found in PATH"
    fi
    
    cat << EOF | sudo tee "${SERVICE_PATH}" >/dev/null
[Unit]
Description=SnailyCADv4 Service
Documentation=https://docs.snailycad.org/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
Group=${USER}
WorkingDirectory=${PROJECT_DIR}
ExecStart=${pnpm_path} run start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snailycad

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${PROJECT_DIR}

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Environment
EnvironmentFile=${ENV_FILE}

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable "${SERVICE_NAME}"
    
    success "Systemd service installed and enabled"
}

start_systemd_service() {
    log "Starting systemd service..."
    
    sudo systemctl start "${SERVICE_NAME}"
    
    sleep 3
    
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        success "Service started successfully"
        info "Status: $(systemctl is-active "${SERVICE_NAME}")"
    else
        error "Service failed to start"
        warn "Checking logs..."
        sudo journalctl -u "${SERVICE_NAME}" -n 20 --no-pager
        error_exit "Service startup failed. Check logs above."
    fi
}

manage_service() {
    log "Checking service status..."
    
    if systemctl list-units --full --all | grep -Fq "${SERVICE_NAME}"; then
        info "Service exists: ${SERVICE_NAME}"
        
        if systemctl is-active --quiet "${SERVICE_NAME}"; then
            info "Service is currently running"
        else
            warn "Service is installed but not running"
        fi
        
        if confirm_action "Restart the service?"; then
            sudo systemctl restart "${SERVICE_NAME}"
            sleep 2
            
            if systemctl is-active --quiet "${SERVICE_NAME}"; then
                success "Service restarted successfully"
            else
                error "Service failed to restart"
                sudo journalctl -u "${SERVICE_NAME}" -n 20 --no-pager
            fi
        fi
    else
        warn "Service not found: ${SERVICE_NAME}"
        
        echo -e "\n${BOLD}Service Installation Options:${NC}"
        echo "  1) Install and start systemd service (recommended)"
        echo "  2) Skip service installation"
        echo -ne "\nChoose option [1-2]: "
        read -r option
        
        case "${option}" in
            1)
                stop_existing_services
                install_systemd_service
                start_systemd_service
                ;;
            2)
                warn "Skipping service installation"
                ;;
            *)
                warn "Invalid option. Skipping service installation."
                ;;
        esac
    fi
}

# ------------------------------------------------------------------------------
# DEPLOYMENT FUNCTIONS
# ------------------------------------------------------------------------------
copy_environment_configs() {
    log "Copying environment configurations..."
    
    if [ -f "scripts/copy-env.mjs" ]; then
        node scripts/copy-env.mjs --client --api || error_exit "copy-env.mjs failed"
        success "Environment configs copied"
    else
        warn "copy-env.mjs not found, skipping..."
    fi
}

git_operations() {
    log "Performing Git operations..."
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warn "Uncommitted changes detected"
        
        local stash_name="pre-deploy-$(date +%Y%m%d_%H%M%S)"
        git stash push -m "${stash_name}" || warn "Failed to stash changes"
        success "Changes stashed as: ${stash_name}"
    fi
    
    # Fetch latest
    log "Fetching latest changes from remote..."
    git fetch origin main || error_exit "Git fetch failed"
    
    # Show what's new
    local commits_behind=$(git rev-list --count HEAD..origin/main)
    if [ "${commits_behind}" -gt 0 ]; then
        info "Repository is ${commits_behind} commit(s) behind origin/main"
        
        echo -e "\n${BOLD}Recent commits:${NC}"
        git log --oneline --graph --decorate -5 origin/main
        
        if ! confirm_action "\nProceed with update?"; then
            error_exit "Deployment cancelled by user"
        fi
    else
        success "Repository is up to date with origin/main"
    fi
    
    # Reset to latest
    log "Resetting to origin/main..."
    git reset --hard origin/main || error_exit "Git reset failed"
    success "Repository updated to latest commit"
}

install_dependencies() {
    log "Installing dependencies with pnpm..."
    
    # Clear cache if needed
    if [ -d "node_modules" ]; then
        info "node_modules exists ($(du -sh node_modules 2>/dev/null | cut -f1))"
    fi
    
    pnpm install --frozen-lockfile || {
        warn "Frozen lockfile install failed, trying regular install..."
        pnpm install || error_exit "pnpm install failed"
    }
    
    success "Dependencies installed"
}

build_project() {
    log "Building project..."
    
    local start_time=$(date +%s)
    
    pnpm run build || error_exit "Build failed"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    success "Build completed in ${duration} seconds"
}

run_health_check() {
    log "Running post-deployment health check..."
    
    sleep 5
    
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        success "Service is running"
        
        # Check logs for errors
        local error_count=$(sudo journalctl -u "${SERVICE_NAME}" --since "1 minute ago" | grep -ci "error" || echo "0")
        
        if [ "${error_count}" -gt 0 ]; then
            warn "Found ${error_count} error(s) in recent logs"
            if confirm_action "View error logs?"; then
                sudo journalctl -u "${SERVICE_NAME}" --since "1 minute ago" | grep -i "error"
            fi
        else
            success "No errors detected in recent logs"
        fi
    else
        error "Service is not running after deployment"
        return 1
    fi
}

deploy_application() {
    log "Starting deployment process..."
    
    local deploy_start=$(date +%s)
    
    check_project_directory
    copy_environment_configs
    git_operations
    install_dependencies
    build_project
    
    local deploy_end=$(date +%s)
    local deploy_duration=$((deploy_end - deploy_start))
    
    success "Deployment completed in ${deploy_duration} seconds"
}

# ------------------------------------------------------------------------------
# MAIN WORKFLOW
# ------------------------------------------------------------------------------
print_deployment_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                  DEPLOYMENT COMPLETED ✓                       ║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Quick Reference Commands:${NC}"
    echo -e "  ${CYAN}View logs:${NC}      sudo journalctl -u ${SERVICE_NAME} -f"
    echo -e "  ${CYAN}Check status:${NC}   sudo systemctl status ${SERVICE_NAME}"
    echo -e "  ${CYAN}Restart:${NC}        sudo systemctl restart ${SERVICE_NAME}"
    echo -e "  ${CYAN}Stop:${NC}           sudo systemctl stop ${SERVICE_NAME}"
    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo -e "  ${CYAN}Env file:${NC}       ${ENV_FILE}"
    echo -e "  ${CYAN}Edit config:${NC}    nano ${ENV_FILE}"
    echo ""
    echo -e "${BOLD}Log file:${NC} ${LOG_FILE}"
    echo -e "${BOLD}Backups:${NC}  ${BACKUP_DIR}"
    echo ""
}

main() {
    print_banner
    
    log "SnailyCADv4 Deployment Script v${SCRIPT_VERSION}"
    log "Started at: $(date)"
    
    check_root
    create_lockfile
    
    # Pre-flight checks
    check_dependencies
    check_project_directory
    check_disk_space
    
    # Backup current state
    if confirm_action "Create backup before deployment?"; then
        create_backup
    fi
    
    # Configure environment
    if confirm_action "Configure environment variables?"; then
        configure_environment
    else
        info "Skipping environment configuration"
        
        # Verify .env exists if skipping configuration
        if [ ! -f "${ENV_FILE}" ] || [ ! -s "${ENV_FILE}" ]; then
            warn ".env file is missing or empty!"
            if confirm_action "Would you like to configure it now?"; then
                configure_environment
            else
                error "Deployment may fail without proper environment configuration"
            fi
        fi
    fi
    
    # Deploy application
    deploy_application
    
    # Service management
    manage_service
    
    # Health check
    run_health_check
    
    # Summary
    print_deployment_summary
    
    log "Deployment finished at: $(date)"
    success "All operations completed successfully!"
}

# ------------------------------------------------------------------------------
# SCRIPT ENTRY POINT
# ------------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
