#!/bin/bash

# Deployment script for maintance-html
# Checks git status and deploys using rsync

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${RED}❌ Error: .env file not found!${NC}"
    echo -e "${YELLOW}💡 Please copy .env.example to .env and configure your settings${NC}"
    exit 1
fi

# Source the .env file
set -a
source "$SCRIPT_DIR/.env"
set +a

# Validate required variables
if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_PATH" ]; then
    echo -e "${RED}❌ Error: Missing required environment variables${NC}"
    echo -e "${YELLOW}Please ensure REMOTE_USER, REMOTE_HOST, and REMOTE_PATH are set in .env${NC}"
    exit 1
fi

# Set defaults
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
SSH_PORT="${SSH_PORT:-22}"

echo -e "${MAGENTA}╔════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║     🚀 Starting Deployment Process     ║${NC}"
echo -e "${MAGENTA}╔════════════════════════════════════════╗${NC}"
echo ""

# Function to print status messages
print_step() {
    echo -e "${CYAN}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Change to script directory
cd "$SCRIPT_DIR"

# Check if we're in a git repository
print_step "Checking git repository..."
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not a git repository!"
    exit 1
fi
print_success "Git repository found"

# Check current branch
print_step "Checking current branch..."
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "$DEPLOY_BRANCH" ]; then
    print_error "Not on $DEPLOY_BRANCH branch! Currently on: $CURRENT_BRANCH"
    echo -e "${YELLOW}Please switch to $DEPLOY_BRANCH before deploying${NC}"
    exit 1
fi
print_success "On $DEPLOY_BRANCH branch"

# Check for uncommitted changes
print_step "Checking for uncommitted changes..."
if ! git diff-index --quiet HEAD --; then
    print_warning "You have uncommitted changes!"
    git status --short
    read -p "$(echo -e ${YELLOW}Continue anyway? [y/N]:${NC} )" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Deployment cancelled"
        exit 1
    fi
else
    print_success "Working directory clean"
fi

# Fetch from remote
print_step "Fetching from remote..."
if ! git fetch origin; then
    print_error "Failed to fetch from remote!"
    exit 1
fi
print_success "Fetched latest changes"

# Check if local is behind remote
print_step "Checking if local is up to date..."
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
BASE=$(git merge-base @ @{u} 2>/dev/null || echo "")

if [ -z "$REMOTE" ]; then
    print_warning "No upstream branch set"
elif [ "$LOCAL" = "$REMOTE" ]; then
    print_success "Local is up to date with remote"
elif [ "$LOCAL" = "$BASE" ]; then
    print_error "Local is behind remote! Please pull latest changes"
    echo -e "${YELLOW}Run: git pull origin $DEPLOY_BRANCH${NC}"
    exit 1
elif [ "$REMOTE" = "$BASE" ]; then
    print_warning "Local is ahead of remote (unpushed commits)"
else
    print_warning "Local and remote have diverged"
fi

# Check if required files exist
print_step "Checking required files..."
MISSING_FILES=()
if [ ! -f "index.html" ]; then
    MISSING_FILES+=("index.html")
fi
if [ ! -f "styles.css" ]; then
    MISSING_FILES+=("styles.css")
fi

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    print_error "Missing required files: ${MISSING_FILES[*]}"
    exit 1
fi
print_success "All required files present"

# Test SSH connection
print_step "Testing SSH connection to $REMOTE_USER@$REMOTE_HOST..."
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" exit 2>/dev/null; then
    print_warning "SSH connection test failed (this might be normal if you need to enter a password)"
else
    print_success "SSH connection successful"
fi

# Perform rsync deployment
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
print_step "Deploying files to remote server..."
echo -e "${BLUE}═══════════════════════════════════════${NC}"

RSYNC_OPTS=(
    -avz
    --progress
    --include='index.html'
    --include='styles.css'
    --exclude='*'
    -e "ssh -p $SSH_PORT"
)

if rsync "${RSYNC_OPTS[@]}" ./ "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✓ Deployment Successful! 🎉       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📦 Deployed files:${NC}"
    echo -e "   • index.html"
    echo -e "   • styles.css"
    echo -e "${CYAN}📍 Destination:${NC} $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
    echo ""
else
    echo ""
    print_error "Deployment failed!"
    exit 1
fi
