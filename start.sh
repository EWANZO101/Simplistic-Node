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
