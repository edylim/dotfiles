#!/bin/bash
# shellcheck disable=SC2034  # Some variables are set for state tracking

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# Note: This script uses indexed arrays (bash 3.2+), not associative arrays
# macOS ships with bash 3.2, so we maintain compatibility

# --- Bootstrap: Handle curl pipe installation ---
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/edylim/dotfiles/master/install.sh)"
#
# SECURITY NOTE: Piping curl to bash is inherently risky. If you're security-conscious,
# clone the repo first and review the code before running:
#   git clone https://github.com/edylim/dotfiles.git ~/.dotfiles && ~/.dotfiles/install.sh
#
DOTFILES_REPO="https://github.com/edylim/dotfiles.git"
DOTFILES_TARGET="$HOME/.dotfiles"

if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
    echo "Bootstrapping dotfiles installation..."
    echo ""
    echo "WARNING: You are running this script directly from the internet."
    echo "For better security, consider cloning and reviewing first:"
    echo "  git clone $DOTFILES_REPO $DOTFILES_TARGET"
    echo "  $DOTFILES_TARGET/install.sh"
    echo ""
    sleep 2

    if ! command -v git &> /dev/null; then
        echo "Error: git is required. Please install git first."
        exit 1
    fi
    if [[ -d "$DOTFILES_TARGET" ]]; then
        echo "Updating existing dotfiles..."
        # Stash any local changes before pulling
        if ! git -C "$DOTFILES_TARGET" diff --quiet 2>/dev/null; then
            echo "Stashing local changes..."
            git -C "$DOTFILES_TARGET" stash push -m "auto-stash before dotfiles update"
        fi
        if ! git -C "$DOTFILES_TARGET" pull --rebase --autostash; then
            echo "Warning: Failed to update dotfiles. Continuing with existing version..."
            echo "You may need to manually resolve conflicts in $DOTFILES_TARGET"
        fi
    else
        echo "Cloning dotfiles to $DOTFILES_TARGET..."
        git clone "$DOTFILES_REPO" "$DOTFILES_TARGET"
    fi
    exec "$DOTFILES_TARGET/install.sh" "$@"
fi

# --- Global Variables ---
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OS=""
PKG_MANAGER=""
ARCH=""
LOG_FILE="${DOTFILES_DIR}/install.log"
LOG_MAX_SIZE=102400  # 100KB max log size
DRY_RUN=false
HEADLESS=false
TAPPED_REPOS=()  # Track tapped Homebrew repos to avoid duplicates

# Lock file to prevent concurrent runs
LOCK_FILE="/tmp/dotfiles-install.lock"

# Installation state tracking
STATE_FILE="${DOTFILES_DIR}/.install-state"
declare -a INSTALLED_ITEMS=()
declare -a FAILED_ITEMS=()
declare -a SKIPPED_ITEMS=()

# XDG directories (respect user overrides)
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# --- Menu Item Configuration ---
# Each item: name|install_func|stow_pkg|macos_only|dependencies
# dependencies is comma-separated list of menu item indices that must run first
declare -a MENU_CONFIG=(
    "Core Packages (git, stow, curl, wget)|install_core_packages||false|"
    "CLI Tools (zsh, fzf, bat, zoxide, yazi, htop, gh)|install_cli_tools||false|0"
    "Git Tools (scmpuff, onefetch)|install_git_tools||false|0"
    "Media Tools (ffmpeg, imagemagick, poppler)|install_media_tools||false|0"
    "Mise & Runtimes (Node.js LTS, Python)|install_mise_and_runtimes|mise|false|0"
    "AI Tools (claude, gemini-cli)|install_ai_tools||false|0,4"
    "Yarn|install_yarn|yarn|false|4"
    "Kitty Terminal|install_kitty|kitty|false|0"
    "Google Chrome|install_chrome||false|0"
    "GrumpyVim (Neovim)|install_grumpyvim||false|0"
    "Zsh & Prezto|install_zsh_prezto|zsh|false|0,1"
    "Awrit|install_awrit|awrit|false|0"
    "JankyBorders (macOS)|install_jankyborders|jankyborders|true|0"
    "SketchyBar (macOS)|install_sketchybar|sketchybar|true|0"
    "Linting Configs||linting|false|0"
    "Bin Scripts||bin|false|0"
    "Git Config||git|false|0"
)

# --- Color and Style ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# --- Lock File Management ---
# Use flock on Linux, mkdir-based lock on macOS (flock not available by default)
acquire_lock() {
    if command -v flock &> /dev/null; then
        # Linux: use flock
        exec 200>"$LOCK_FILE"
        if ! flock -n 200; then
            error "Another instance of install.sh is already running (lock: $LOCK_FILE)"
        fi
        echo $$ >&200
    else
        # macOS/BSD: use mkdir (atomic operation)
        local lock_dir="${LOCK_FILE}.d"
        if ! mkdir "$lock_dir" 2>/dev/null; then
            # Check if the lock is stale (process dead)
            local lock_pid
            lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Stale lock, remove and retry
                rm -rf "$lock_dir"
                if ! mkdir "$lock_dir" 2>/dev/null; then
                    error "Another instance of install.sh is already running"
                fi
            else
                error "Another instance of install.sh is already running (lock: $lock_dir)"
            fi
        fi
        echo $$ > "$lock_dir/pid"
    fi
}

release_lock() {
    if command -v flock &> /dev/null; then
        flock -u 200 2>/dev/null || true
        rm -f "$LOCK_FILE" 2>/dev/null || true
    else
        rm -rf "${LOCK_FILE}.d" 2>/dev/null || true
    fi
}

# --- Logging with rotation ---
LOG_LINE_COUNT=0
LOG_ROTATE_CHECK_INTERVAL=50  # Check rotation every N log calls

rotate_log_if_needed() {
    ((LOG_LINE_COUNT++)) || true
    if [[ $((LOG_LINE_COUNT % LOG_ROTATE_CHECK_INTERVAL)) -ne 0 ]]; then
        return
    fi
    if [[ -f "$LOG_FILE" ]]; then
        local size
        # Try macOS stat first, then Linux stat
        if size=$(stat -f%z "$LOG_FILE" 2>/dev/null); then
            :  # macOS succeeded
        elif size=$(stat -c%s "$LOG_FILE" 2>/dev/null); then
            :  # Linux succeeded
        else
            # Both failed - skip rotation this time
            return
        fi
        if [[ $size -gt $LOG_MAX_SIZE ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        fi
    fi
}

log() {
    rotate_log_if_needed
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

info()    { echo -e "${BLUE}[INFO]${NC} $1"; log "INFO: $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; log "OK: $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; log "WARN: $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; log "ERROR: $1"; exit 1; }

# Track installation results
track_success() {
    local item="$1"
    INSTALLED_ITEMS+=("$item")
    log "SUCCESS: $item"
}

track_failure() {
    local item="$1"
    local reason="${2:-unknown}"
    FAILED_ITEMS+=("$item: $reason")
    log "FAILED: $item - $reason"
}

track_skip() {
    local item="$1"
    local reason="${2:-}"
    SKIPPED_ITEMS+=("$item${reason:+: $reason}")
    log "SKIPPED: $item${reason:+ - $reason}"
}

# Save state for potential rollback info
save_state() {
    {
        echo "# Dotfiles installation state - $(date)"
        echo "# This file is for reference only"
        echo ""
        echo "INSTALLED=(${INSTALLED_ITEMS[*]:-})"
        echo "FAILED=(${FAILED_ITEMS[*]:-})"
        echo "SKIPPED=(${SKIPPED_ITEMS[*]:-})"
    } > "$STATE_FILE"
}

# --- Cleanup and signal handling ---
cleanup() {
    local exit_code=$?
    tput cnorm 2>/dev/null || true  # Restore cursor
    release_lock
    save_state

    if [[ $exit_code -ne 0 ]] && [[ ${#INSTALLED_ITEMS[@]} -gt 0 ]]; then
        echo ""
        warn "Installation was interrupted. Successfully installed:"
        for item in "${INSTALLED_ITEMS[@]}"; do
            echo "  - $item"
        done
        echo ""
        echo "State saved to: $STATE_FILE"
    fi
}
trap cleanup EXIT INT TERM

# --- Dependency Validation ---
STOW_AVAILABLE=false
CAN_SUDO=false

validate_dependencies() {
    local missing=()

    # Core dependencies that must exist before we start
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    # stow is needed for linking dotfiles - track availability
    if command -v stow &> /dev/null; then
        STOW_AVAILABLE=true
    else
        warn "GNU Stow not found. Will install via Core Packages."
    fi

    # Check sudo availability (don't require it, but track it)
    if command -v sudo &> /dev/null; then
        if sudo -n true 2>/dev/null || [[ "$HEADLESS" != true ]]; then
            CAN_SUDO=true
        else
            warn "sudo available but requires password. Some installations may be skipped in headless mode."
        fi
    else
        warn "sudo not available. Some system-level installations will be skipped."
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
    fi
}

# Verify stow is available before attempting to stow
require_stow() {
    log "require_stow: checking for stow..."
    hash -r 2>/dev/null || true  # Refresh command cache

    # First, check explicit paths (more reliable than command -v in CI)
    local stow_path=""
    if [[ -x /opt/homebrew/bin/stow ]]; then
        stow_path="/opt/homebrew/bin/stow"
    elif [[ -x /usr/local/bin/stow ]]; then
        stow_path="/usr/local/bin/stow"
    elif command -v stow &> /dev/null; then
        stow_path="$(command -v stow)"
    fi

    if [[ -n "$stow_path" ]]; then
        # Ensure the directory containing stow is in PATH
        local stow_dir="${stow_path%/*}"
        if [[ ":$PATH:" != *":$stow_dir:"* ]]; then
            export PATH="$stow_dir:$PATH"
            log "require_stow: added $stow_dir to PATH"
        fi
        log "require_stow: found stow at $stow_path"
        return 0
    fi

    log "require_stow: stow not found anywhere"
    error "GNU Stow is required but not installed. Please install Core Packages first."
}

# --- OS Detection ---
detect_os() {
    ARCH="$(uname -m)"
    # Normalize architecture names
    case "$ARCH" in
        aarch64) ARCH="arm64" ;;
        x86_64|amd64) ARCH="x86_64" ;;
    esac

    if [[ "$(uname)" == "Darwin" ]]; then
        OS="macos"
        PKG_MANAGER="brew"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
        PKG_MANAGER="pacman"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        PKG_MANAGER="apt"
    else
        error "Unsupported OS. This script supports macOS, Ubuntu/Debian, and Arch/Omarchy."
    fi
    info "Detected OS: $OS ($ARCH, package manager: $PKG_MANAGER)"
}

# --- Utility Functions ---

# Run command with timeout (portable)
run_with_timeout() {
    local timeout_secs="$1"
    shift

    if command -v timeout &> /dev/null; then
        timeout "$timeout_secs" "$@"
    elif command -v gtimeout &> /dev/null; then
        gtimeout "$timeout_secs" "$@"
    else
        warn "No timeout command available - running without timeout protection"
        "$@"
    fi
}

# Require sudo, return false if not available
require_sudo() {
    if [[ "$CAN_SUDO" != true ]]; then
        return 1
    fi
    return 0
}

# Safe sudo - only runs if sudo is available
safe_sudo() {
    if require_sudo; then
        sudo "$@"
    else
        warn "Skipping (requires sudo): $*"
        return 1
    fi
}

# --- Package Installation Helpers ---
pkg_install() {
    local pkg="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install: $pkg${NC}"
        return 0
    fi
    case "$PKG_MANAGER" in
        brew)   brew install "$pkg" ;;
        pacman) safe_sudo pacman -S --noconfirm --needed "$pkg" ;;
        apt)    safe_sudo apt-get install -y "$pkg" ;;
    esac
}

pkg_installed() {
    command -v "$1" &> /dev/null
}

# Check if package is installed via package manager (more thorough)
pkg_manager_has() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        brew)   brew list --formula "$pkg" &> /dev/null || brew list --cask "$pkg" &> /dev/null ;;
        pacman) pacman -Qi "$pkg" &> /dev/null ;;
        apt)    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" ;;
    esac
}

# Verify a command was installed successfully
verify_installed() {
    local cmd="$1"
    local name="${2:-$1}"
    if command -v "$cmd" &> /dev/null; then
        return 0
    else
        warn "$name installation could not be verified"
        return 1
    fi
}

# Git operations with timeout
GIT_TIMEOUT="${GIT_TIMEOUT:-120}"  # Default 2 minutes

git_clone() {
    local repo="$1"
    local dest="$2"
    shift 2
    local extra_args=("$@")

    run_with_timeout "$GIT_TIMEOUT" git clone "${extra_args[@]}" "$repo" "$dest"
}

git_pull() {
    local dir="$1"
    shift
    local extra_args=("$@")

    run_with_timeout "$GIT_TIMEOUT" git -C "$dir" pull "${extra_args[@]}"
}

git_submodule_update() {
    local dir="$1"
    shift
    local extra_args=("$@")

    run_with_timeout "$GIT_TIMEOUT" git -C "$dir" submodule update "${extra_args[@]}"
}

# Check if brew formula is installed
brew_installed() {
    brew list --formula "$1" &> /dev/null
}

# Check if brew cask is installed
cask_installed() {
    brew list --cask "$1" &> /dev/null
}

# Check if macOS app is installed (via any method)
app_installed() {
    local app="$1"
    [[ -d "/Applications/$app.app" ]] || \
    [[ -d "$HOME/Applications/$app.app" ]] || \
    [[ -d "/System/Applications/$app.app" ]] || \
    [[ -d "/Applications/Setapp/$app.app" ]]
}

# Tap a Homebrew repo (with deduplication)
brew_tap() {
    local repo="$1"
    # Check if already tapped in this session
    for tapped in "${TAPPED_REPOS[@]:-}"; do
        [[ "$tapped" == "$repo" ]] && return 0
    done
    # Check if already tapped in brew
    if brew tap | grep -q "^${repo}$"; then
        TAPPED_REPOS+=("$repo")
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would tap: $repo${NC}"
    else
        brew tap "$repo"
    fi
    TAPPED_REPOS+=("$repo")
}

# Install brew packages, skipping already installed
brew_install() {
    if [[ "$DRY_RUN" == true ]]; then
        for pkg in "$@"; do
            if ! brew_installed "$pkg"; then
                echo -e "  ${DIM}[dry-run] Would install: $pkg${NC}"
            else
                echo -e "  ${DIM}$pkg already installed${NC}"
            fi
        done
        return 0
    fi
    local to_install=()
    for pkg in "$@"; do
        if ! brew_installed "$pkg"; then
            to_install+=("$pkg")
        else
            echo -e "  ${DIM}$pkg already installed${NC}"
        fi
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        brew install "${to_install[@]}"
        # Refresh bash's command hash table so newly installed commands are found
        hash -r 2>/dev/null || true
    fi
}

# Install brew casks, skipping already installed (checks /Applications too)
cask_install() {
    for pkg in "$@"; do
        # Map cask names to app names for checking
        local app_name=""
        case "$pkg" in
            google-chrome) app_name="Google Chrome" ;;
            sf-symbols) app_name="SF Symbols" ;;
            kitty) app_name="kitty" ;;
            font-*) app_name="" ;;  # Fonts don't have .app
        esac

        if [[ -n "$app_name" ]] && app_installed "$app_name"; then
            echo -e "  ${DIM}$pkg already installed${NC}"
        elif cask_installed "$pkg"; then
            echo -e "  ${DIM}$pkg already installed${NC}"
        elif [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${DIM}[dry-run] Would install cask: $pkg${NC}"
        else
            brew install --cask "$pkg"
        fi
    done
}

# --- Package Manager Setup ---
setup_package_manager() {
    info "Setting up package manager..."
    case "$PKG_MANAGER" in
        brew)
            if ! pkg_installed brew; then
                info "Installing Homebrew..."
                if [[ "$DRY_RUN" == true ]]; then
                    echo -e "  ${DIM}[dry-run] Would install Homebrew${NC}"
                else
                    # Download installer to temp file for inspection if desired
                    local brew_installer
                    brew_installer=$(mktemp)
                    if curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$brew_installer"; then
                        /bin/bash "$brew_installer"
                        rm -f "$brew_installer"
                    else
                        rm -f "$brew_installer"
                        error "Failed to download Homebrew installer"
                    fi
                fi
            fi
            # Source Homebrew if not already in PATH
            if ! command -v brew &> /dev/null; then
                if [[ "$ARCH" == "arm64" ]] && [[ -f /opt/homebrew/bin/brew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -f /usr/local/bin/brew ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            fi
            # Verify brew is now available
            if ! command -v brew &> /dev/null; then
                error "Homebrew installation failed or not in PATH"
            fi
            ;;
        pacman)
            # pacman is pre-installed on Arch
            ;;
        apt)
            if [[ "$DRY_RUN" != true ]] && require_sudo; then
                sudo apt-get update
            fi
            ;;
    esac
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

install_core_packages() {
    info "Installing core packages..."
    local failed=false

    case "$OS" in
        macos)
            # Ensure Homebrew paths are in PATH before and after installing
            # Critical for GitHub Actions where brew shellenv may not have run
            if [[ "$ARCH" == "arm64" ]]; then
                export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
            else
                export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
            fi
            brew_install git stow curl wget coreutils || failed=true
            ;;
        arch)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: git stow curl wget${NC}"
            elif require_sudo; then
                sudo pacman -S --noconfirm --needed git stow curl wget || failed=true
            else
                track_failure "Core Packages" "requires sudo"
                return 1
            fi
            ;;
        debian)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: git stow curl wget${NC}"
            elif require_sudo; then
                sudo apt-get install -y git stow curl wget || failed=true
            else
                track_failure "Core Packages" "requires sudo"
                return 1
            fi
            ;;
    esac

    if [[ "$failed" == true ]]; then
        track_failure "Core Packages" "package installation failed"
        return 1
    fi

    # Update stow availability flag and verify installation
    hash -r 2>/dev/null || true  # Ensure bash finds newly installed commands

    # On macOS, explicitly verify stow at the expected Homebrew location
    # The hash -r and command -v approach is unreliable in some CI environments
    if [[ "$OS" == "macos" ]]; then
        local brew_prefix
        if [[ "$ARCH" == "arm64" ]]; then
            brew_prefix="/opt/homebrew"
        else
            brew_prefix="/usr/local"
        fi

        if [[ -x "$brew_prefix/bin/stow" ]]; then
            STOW_AVAILABLE=true
            log "Stow verified at: $brew_prefix/bin/stow"
        else
            warn "stow not found at $brew_prefix/bin/stow after installation"
            log "brew_prefix: $brew_prefix"
            log "PATH: $PATH"
            # List what's actually in the bin directory
            log "Homebrew bin contents: $(ls "$brew_prefix/bin/" 2>&1 | grep -i stow || echo 'stow not found')"
        fi
    elif command -v stow &> /dev/null; then
        STOW_AVAILABLE=true
        log "Stow is now available at: $(command -v stow)"
    else
        warn "stow installation may have failed - not found in PATH"
        log "PATH: $PATH"
    fi

    track_success "Core Packages"
    success "Core packages installed."
}

install_cli_tools() {
    info "Installing CLI tools..."
    local failed=false

    # Note: ripgrep, fd, lazygit installed by grumpyvim
    case "$OS" in
        macos)
            brew_install zsh fzf bat htop gh jq tree zoxide yazi mas || failed=true
            ;;
        arch)
            if [[ "$DRY_RUN" != true ]]; then
                if require_sudo; then
                    sudo pacman -S --noconfirm --needed zsh fzf bat htop github-cli jq tree zoxide yazi || failed=true
                else
                    track_failure "CLI Tools" "requires sudo"
                    return 1
                fi
            fi
            ;;
        debian)
            if [[ "$DRY_RUN" != true ]]; then
                if require_sudo; then
                    sudo apt-get install -y zsh fzf bat htop gh jq tree || failed=true
                else
                    track_failure "CLI Tools" "requires sudo"
                    return 1
                fi
            fi
            # zoxide needs special handling on Debian
            if ! pkg_installed zoxide; then
                info "Installing zoxide..."
                if [[ "$DRY_RUN" != true ]]; then
                    local zoxide_installer
                    zoxide_installer=$(mktemp)
                    if curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o "$zoxide_installer"; then
                        bash "$zoxide_installer" || warn "zoxide installation failed"
                        rm -f "$zoxide_installer"
                    else
                        rm -f "$zoxide_installer"
                        warn "Failed to download zoxide installer"
                    fi
                fi
            fi
            # yazi needs cargo on Debian
            if ! pkg_installed yazi; then
                if command -v cargo &> /dev/null; then
                    info "Building yazi from source (this may take a few minutes)..."
                    if [[ "$DRY_RUN" != true ]]; then
                        cargo install --locked yazi-fm yazi-cli || warn "yazi build failed"
                    fi
                else
                    warn "yazi requires cargo/rust. Install rustup first, then run: cargo install --locked yazi-fm yazi-cli"
                fi
            fi
            ;;
    esac

    if [[ "$failed" == true ]]; then
        track_failure "CLI Tools" "some packages failed"
        warn "Some CLI tools may not have installed correctly"
        return 1
    fi

    track_success "CLI Tools"
    success "CLI tools installed."
}

install_ai_tools() {
    info "Installing AI CLI tools..."
    local installed_something=false

    case "$OS" in
        macos)
            brew_install gemini-cli && installed_something=true
            ;;
    esac

    # Claude Code CLI (requires npm) - all platforms
    if pkg_installed claude; then
        echo -e "  ${DIM}claude already installed${NC}"
        installed_something=true
    elif command -v npm &> /dev/null; then
        info "Installing Claude Code CLI..."
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${DIM}[dry-run] Would install: @anthropic-ai/claude-code${NC}"
            installed_something=true
        elif npm install -g @anthropic-ai/claude-code; then
            installed_something=true
        else
            warn "Failed to install Claude Code CLI"
        fi
    else
        warn "npm not found. Install Mise & Runtimes first for Claude Code CLI."
        track_skip "Claude CLI" "npm not available"
    fi

    if [[ "$installed_something" == true ]]; then
        track_success "AI Tools"
        success "AI tools installed."
    else
        track_failure "AI Tools" "no tools installed"
        warn "No AI tools were installed (missing dependencies)."
        return 1
    fi
}

install_git_tools() {
    info "Installing git tools..."
    local installed=false

    case "$OS" in
        macos)
            brew_install scmpuff onefetch && installed=true
            ;;
        arch)
            if [[ "$DRY_RUN" != true ]] && require_sudo; then
                sudo pacman -S --noconfirm --needed onefetch && installed=true
                # scmpuff needs AUR - try multiple helpers
                local aur_helper=""
                for helper in yay paru pikaur trizen aurman; do
                    if pkg_installed "$helper"; then
                        aur_helper="$helper"
                        break
                    fi
                done
                if [[ -n "$aur_helper" ]]; then
                    "$aur_helper" -S --noconfirm scmpuff || warn "scmpuff installation failed"
                else
                    warn "scmpuff requires AUR helper (yay/paru/pikaur/trizen)"
                fi
            fi
            ;;
        debian)
            # scmpuff and onefetch need manual install on Debian
            warn "scmpuff/onefetch not in apt repos. Install manually:"
            warn "  onefetch: https://github.com/o2sh/onefetch/releases"
            warn "  scmpuff: https://github.com/mroth/scmpuff/releases"
            track_skip "Git Tools" "not available via apt"
            return 0
            ;;
    esac

    if [[ "$installed" == true ]] || [[ "$DRY_RUN" == true ]]; then
        track_success "Git Tools"
        success "Git tools installed."
    else
        track_failure "Git Tools" "installation failed"
        return 1
    fi
}

install_media_tools() {
    info "Installing media tools..."
    local failed=false

    case "$OS" in
        macos)
            brew_install ffmpeg sevenzip poppler resvg imagemagick || failed=true
            ;;
        arch)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: ffmpeg p7zip poppler imagemagick${NC}"
            elif require_sudo; then
                sudo pacman -S --noconfirm --needed ffmpeg p7zip poppler imagemagick || failed=true
            else
                track_failure "Media Tools" "requires sudo"
                return 1
            fi
            ;;
        debian)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: ffmpeg p7zip-full poppler-utils imagemagick${NC}"
            elif require_sudo; then
                sudo apt-get install -y ffmpeg p7zip-full poppler-utils imagemagick || failed=true
            else
                track_failure "Media Tools" "requires sudo"
                return 1
            fi
            ;;
    esac

    if [[ "$failed" == true ]]; then
        track_failure "Media Tools" "package installation failed"
        return 1
    fi

    track_success "Media Tools"
    success "Media tools installed."
}

# Combined mise installation and runtime configuration
install_mise_and_runtimes() {
    info "Installing Mise (Runtime Manager)..."

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install mise and configure Node.js LTS + Python${NC}"
        return 0
    fi

    case "$OS" in
        macos)
            if ! pkg_installed mise; then
                brew install mise || { track_failure "Mise" "brew install failed"; return 1; }
            fi
            ;;
        arch)
            if ! pkg_installed mise; then
                if require_sudo && sudo pacman -S --noconfirm --needed mise 2>/dev/null; then
                    : # Installed via pacman
                else
                    info "Mise not in pacman, installing via script..."
                    local mise_installer
                    mise_installer=$(mktemp)
                    if curl -fsSL https://mise.run -o "$mise_installer"; then
                        sh "$mise_installer"
                        rm -f "$mise_installer"
                    else
                        rm -f "$mise_installer"
                        track_failure "Mise" "failed to download installer"
                        return 1
                    fi
                fi
            fi
            ;;
        debian)
            if ! pkg_installed mise; then
                local mise_installer
                mise_installer=$(mktemp)
                if curl -fsSL https://mise.run -o "$mise_installer"; then
                    sh "$mise_installer"
                    rm -f "$mise_installer"
                else
                    rm -f "$mise_installer"
                    track_failure "Mise" "failed to download installer"
                    return 1
                fi
                export PATH="$HOME/.local/bin:$PATH"
            fi
            ;;
    esac

    mkdir -p "$XDG_CONFIG_HOME/mise"

    # Activate mise for this session
    if command -v mise &> /dev/null; then
        eval "$(mise activate bash)"
    elif [[ -f "$HOME/.local/bin/mise" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        eval "$("$HOME/.local/bin/mise" activate bash)"
    else
        track_failure "Mise" "could not activate"
        warn "Mise installed but could not activate. You may need to restart your shell."
        return 1
    fi

    # Configure runtimes - use flexible version specs
    info "Installing Node.js LTS and Python via Mise..."
    mise use --global node@lts || warn "Failed to install Node.js"
    mise use --global python@3 || warn "Failed to install Python"  # Latest Python 3.x

    if verify_installed node && verify_installed python; then
        track_success "Mise & Runtimes"
        success "Mise and runtimes installed."
    else
        track_failure "Mise & Runtimes" "runtime installation incomplete"
        warn "Mise installed but some runtimes may need manual setup."
        return 1
    fi
}

install_yarn() {
    info "Installing Yarn..."
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install yarn${NC}"
        return 0
    fi

    if pkg_installed yarn; then
        echo -e "  ${DIM}yarn already installed${NC}"
        track_success "Yarn"
        return 0
    fi

    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        # Try to use mise to get node/npm if mise is available
        if command -v mise &> /dev/null; then
            info "npm not found, installing Node.js via mise..."
            mise use --global node@lts
            eval "$(mise activate bash)"
        else
            track_failure "Yarn" "npm not available"
            warn "npm not found and mise not available. Install Mise & Runtimes first, then Yarn."
            return 1
        fi
    fi

    # Now npm should be available
    if command -v npm &> /dev/null; then
        if npm install -g yarn; then
            track_success "Yarn"
            success "Yarn installed."
        else
            track_failure "Yarn" "npm install failed"
            warn "Yarn installation failed"
            return 1
        fi
    else
        track_failure "Yarn" "npm still not available"
        warn "npm still not available after mise setup"
        return 1
    fi
}

install_kitty() {
    info "Installing Kitty terminal..."
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install kitty${NC}"
        return 0
    fi

    case "$OS" in
        macos)
            cask_install kitty font-symbols-only-nerd-font
            ;;
        arch)
            if require_sudo; then
                sudo pacman -S --noconfirm --needed kitty
            else
                track_failure "Kitty" "requires sudo"
                return 1
            fi
            ;;
        debian)
            if pkg_installed kitty; then
                echo -e "  ${DIM}kitty already installed${NC}"
            else
                # Download installer to temp file
                local tmp_installer
                tmp_installer=$(mktemp)
                if curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh -o "$tmp_installer"; then
                    bash "$tmp_installer"
                    rm -f "$tmp_installer"
                else
                    rm -f "$tmp_installer"
                    track_failure "Kitty" "failed to download installer"
                    warn "Failed to download kitty installer"
                    return 1
                fi
            fi
            ;;
    esac

    if verify_installed kitty; then
        track_success "Kitty"
        success "Kitty installed."
    else
        track_failure "Kitty" "verification failed"
        warn "Kitty installation could not be verified"
        return 1
    fi
}

install_chrome() {
    info "Installing Google Chrome..."

    case "$OS" in
        macos)
            cask_install google-chrome
            track_success "Chrome"
            success "Chrome installed."
            ;;
        debian)
            if pkg_installed google-chrome-stable || app_installed "Google Chrome"; then
                echo -e "  ${DIM}google-chrome already installed${NC}"
                track_success "Chrome"
                return 0
            elif [[ "$ARCH" != "x86_64" ]]; then
                track_skip "Chrome" "only available for x86_64"
                warn "Google Chrome is only available for x86_64 on Linux. Skipping."
                return 0
            elif [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install Google Chrome${NC}"
                return 0
            elif ! require_sudo; then
                track_failure "Chrome" "requires sudo"
                return 1
            else
                local chrome_deb
                chrome_deb=$(mktemp --suffix=.deb)
                if wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O "$chrome_deb"; then
                    sudo dpkg -i "$chrome_deb" || sudo apt-get install -f -y
                    rm -f "$chrome_deb"
                    track_success "Chrome"
                    success "Chrome installed."
                else
                    rm -f "$chrome_deb"
                    track_failure "Chrome" "download failed"
                    warn "Failed to download Chrome"
                    return 1
                fi
            fi
            ;;
        arch)
            if pkg_installed google-chrome-stable || app_installed "Google Chrome"; then
                echo -e "  ${DIM}google-chrome already installed${NC}"
                track_success "Chrome"
                return 0
            elif [[ "$ARCH" != "x86_64" ]]; then
                track_skip "Chrome" "only available for x86_64"
                warn "Google Chrome is only available for x86_64 on Linux. Skipping."
                return 0
            elif [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install Google Chrome via AUR${NC}"
                return 0
            else
                # Try multiple AUR helpers
                local aur_helper=""
                for helper in yay paru pikaur trizen aurman; do
                    if pkg_installed "$helper"; then
                        aur_helper="$helper"
                        break
                    fi
                done
                if [[ -n "$aur_helper" ]]; then
                    "$aur_helper" -S --noconfirm google-chrome
                    track_success "Chrome"
                    success "Chrome installed."
                else
                    track_skip "Chrome" "no AUR helper found"
                    warn "AUR helper not found. Skipping Chrome."
                    return 0
                fi
            fi
            ;;
    esac
}

install_jankyborders() {
    [[ "$OS" != "macos" ]] && return 0

    info "Installing JankyBorders..."
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install borders${NC}"
        return 0
    fi

    if brew_installed borders; then
        echo -e "  ${DIM}borders already installed${NC}"
    else
        brew_tap FelixKratz/formulae
        brew install borders
    fi

    track_success "JankyBorders"
    success "JankyBorders installed."
}

install_sketchybar() {
    [[ "$OS" != "macos" ]] && return 0

    info "Installing SketchyBar..."
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install sketchybar${NC}"
        return 0
    fi

    if brew_installed sketchybar; then
        echo -e "  ${DIM}sketchybar already installed${NC}"
    else
        brew_tap FelixKratz/formulae
        brew install sketchybar
    fi
    cask_install sf-symbols
    brew_install jq

    # Build helpers if they exist and have Makefiles
    local helpers_dir="$DOTFILES_DIR/sketchybar/.config/sketchybar/helpers"
    if [[ -d "$helpers_dir" ]]; then
        info "Building SketchyBar helpers..."
        for makefile in "$helpers_dir"/*/Makefile; do
            if [[ -f "$makefile" ]]; then
                local helper_dir
                helper_dir=$(dirname "$makefile")
                (cd "$helper_dir" && make) || warn "Failed to build helper in $helper_dir"
            fi
        done
    fi

    track_success "SketchyBar"
    success "SketchyBar installed."
}

install_awrit() {
    info "Installing Awrit..."
    local AW_INSTALL_DIR="$HOME/.awrit"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$AW_INSTALL_DIR/awrit" ]]; then
            echo -e "  ${DIM}Awrit already installed${NC}"
        else
            echo -e "  ${DIM}[dry-run] Would install Awrit to $AW_INSTALL_DIR${NC}"
        fi
        return 0
    fi

    if [[ -f "$AW_INSTALL_DIR/awrit" ]]; then
        echo -e "  ${DIM}Awrit already installed${NC}"
        track_success "Awrit"
        return 0
    fi

    # Download installer to temp file first
    local awrit_installer
    awrit_installer=$(mktemp)
    if curl -fsS https://chase.github.io/awrit/get -o "$awrit_installer"; then
        DOWNLOAD_TO="$AW_INSTALL_DIR" bash "$awrit_installer"
        rm -f "$awrit_installer"
    else
        rm -f "$awrit_installer"
        track_failure "Awrit" "failed to download installer"
        warn "Failed to download Awrit installer"
        return 1
    fi

    if [[ -f "$AW_INSTALL_DIR/dist/kitty.css" && ! -L "$AW_INSTALL_DIR/dist/kitty.css" ]]; then
         rm "$AW_INSTALL_DIR/dist/kitty.css"
    fi

    track_success "Awrit"
    success "Awrit installed."
}

install_grumpyvim() {
    info "Installing GrumpyVim..."
    local NVIM_CONFIG_DIR="$XDG_CONFIG_HOME/nvim"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install GrumpyVim to $NVIM_CONFIG_DIR${NC}"
        return 0
    fi

    # Handle symlinks (including broken ones)
    if [[ -L "$NVIM_CONFIG_DIR" ]]; then
        local link_target
        link_target=$(readlink "$NVIM_CONFIG_DIR" 2>/dev/null || echo "")
        if [[ -n "$link_target" ]] && [[ -d "$link_target" ]] && [[ -d "$link_target/.git" ]] && git -C "$link_target" remote -v 2>/dev/null | grep -q "grumpyvim"; then
            info "GrumpyVim already linked."
            track_success "GrumpyVim"
            return 0
        else
            warn "Removing existing symlink at $NVIM_CONFIG_DIR..."
            rm "$NVIM_CONFIG_DIR"
        fi
    fi

    if [[ -d "$NVIM_CONFIG_DIR" ]]; then
        if [[ -d "$NVIM_CONFIG_DIR/.git" ]] && git -C "$NVIM_CONFIG_DIR" remote -v | grep -q "grumpyvim"; then
            info "GrumpyVim already cloned. Pulling latest..."
            if ! git_pull "$NVIM_CONFIG_DIR" --rebase; then
                warn "Failed to update GrumpyVim, continuing with existing version"
            fi
        else
            warn "Existing Neovim config found. Backing up..."
            local backup_name
            backup_name="$NVIM_CONFIG_DIR.bak.$(date +%F-%H%M%S)-$$"
            mv "$NVIM_CONFIG_DIR" "$backup_name"
            info "Backed up to: $backup_name"
            git_clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
        fi
    else
        git_clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
    fi

    # Run GrumpyVim's installer if it exists
    # NOTE: This executes a script from the cloned repo - review grumpyvim before running
    if [[ -f "$NVIM_CONFIG_DIR/install.sh" ]]; then
        info "Running GrumpyVim installer..."
        chmod +x "$NVIM_CONFIG_DIR/install.sh"
        bash "$NVIM_CONFIG_DIR/install.sh"
    fi

    track_success "GrumpyVim"
    success "GrumpyVim installed."
}

# Combined zsh and prezto installation
install_zsh_prezto() {
    info "Installing Zsh & Prezto..."

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install Prezto and set Zsh as default shell${NC}"
        return 0
    fi

    # Install Prezto with shallow clone for speed
    local prezto_dir="${ZDOTDIR:-$HOME}/.zprezto"
    if [[ -d "$prezto_dir" ]]; then
        # Check if it's a complete installation
        if [[ -d "$prezto_dir/.git" ]] && [[ -f "$prezto_dir/init.zsh" ]]; then
            echo -e "  ${DIM}Prezto already installed${NC}"
        else
            warn "Incomplete Prezto installation found. Removing and reinstalling..."
            rm -rf "$prezto_dir"
            info "Cloning Prezto (this may take a moment)..."
            if ! git_clone https://github.com/sorin-ionescu/prezto.git "$prezto_dir" --depth 1 --recursive; then
                track_failure "Prezto" "clone failed"
                warn "Failed to clone Prezto"
                return 1
            fi
        fi
    else
        info "Cloning Prezto (this may take a moment)..."
        if ! git_clone https://github.com/sorin-ionescu/prezto.git "$prezto_dir" --depth 1 --recursive; then
            track_failure "Prezto" "clone failed"
            warn "Failed to clone Prezto"
            return 1
        fi
    fi

    # Ensure submodules are initialized
    if ! git_submodule_update "$prezto_dir" --init --recursive --depth 1; then
        warn "Submodule update failed, Prezto may be incomplete"
    fi

    # Set Zsh as default shell
    local ZSH_PATH
    ZSH_PATH="$(command -v zsh)"
    if [[ -z "$ZSH_PATH" ]]; then
        track_failure "Zsh" "not found in PATH"
        warn "Zsh not found in PATH. Cannot set as default shell."
        return 1
    fi

    if [[ "$SHELL" == "$ZSH_PATH" ]]; then
        echo -e "  ${DIM}Zsh is already the default shell${NC}"
    else
        # Add to /etc/shells if needed
        if ! grep -q "^${ZSH_PATH}$" /etc/shells 2>/dev/null; then
            if require_sudo; then
                echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
            else
                warn "Cannot add $ZSH_PATH to /etc/shells (requires sudo)"
            fi
        fi

        # Change shell
        local shell_changed=false
        if [[ "$HEADLESS" == true ]]; then
            if require_sudo && sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null; then
                shell_changed=true
            fi
        elif chsh -s "$ZSH_PATH" 2>/dev/null; then
            shell_changed=true
        fi

        if [[ "$shell_changed" == true ]]; then
            success "Default shell changed to Zsh."
            echo ""
            echo -e "${YELLOW}NOTE: You need to log out and back in for the shell change to take effect.${NC}"
            echo ""
        else
            warn "Could not change default shell. Run manually: chsh -s $ZSH_PATH"
        fi
    fi

    track_success "Zsh & Prezto"
    success "Zsh & Prezto installed."
}

# --- Stow Dotfiles ---
stow_package() {
    local pkg="$1"

    # Validate package name - only allow safe characters
    if [[ ! "$pkg" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        warn "Invalid package name '$pkg' - only alphanumeric, dash, underscore allowed. Skipping."
        return 1
    fi

    info "Stowing $pkg..."

    if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
        warn "Package directory '$pkg' not found. Skipping."
        return 1
    fi

    # Check for conflicts with dry run
    local backup_dir
    backup_dir="$HOME/.dotfiles-backup/$(date +%F-%H%M%S)-$RANDOM-$$"
    local conflicts
    conflicts=$(stow -d "$DOTFILES_DIR" -t "$HOME" -n "$pkg" 2>&1) || true

    # Parse conflicts - handle multiple stow output formats for compatibility
    local -a conflict_files=()

    # Format 1: "existing target X since..."
    while IFS= read -r line; do
        if [[ "$line" =~ existing\ target\ (.+)\ since ]]; then
            conflict_files+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$conflicts"

    # Format 2: "existing target is not owned by stow: X"
    while IFS= read -r line; do
        if [[ "$line" =~ not\ owned\ by\ stow:\ (.+)$ ]]; then
            conflict_files+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$conflicts"

    # Format 3: "target X already exists"
    while IFS= read -r line; do
        if [[ "$line" =~ target\ (.+)\ already\ exists ]]; then
            conflict_files+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$conflicts"

    # Back up and remove conflicting files
    if [[ ${#conflict_files[@]} -gt 0 ]]; then
        mkdir -p "$backup_dir"

        for target in "${conflict_files[@]}"; do
            [[ -z "$target" ]] && continue
            local full_path="$HOME/$target"

            if [[ -L "$full_path" ]]; then
                # It's a symlink - remove it (no need to back up symlinks)
                local link_target
                link_target=$(readlink "$full_path" 2>/dev/null || echo "unknown")
                echo -e "  ${DIM}Removing symlink $target (-> $link_target)${NC}"
                rm -f "$full_path"
            elif [[ -e "$full_path" ]]; then
                # It's a real file - back it up, preserving permissions
                local target_dir
                target_dir=$(dirname "$backup_dir/$target")
                mkdir -p "$target_dir"
                if cp -p "$full_path" "$backup_dir/$target" && rm "$full_path"; then
                    echo -e "  ${DIM}Backed up $target${NC}"
                else
                    warn "Failed to backup $target"
                fi
            fi
        done
    fi

    # Run stow - try regular stow first, use -R (restow) for updates
    local stow_output
    log "Running: stow -d $DOTFILES_DIR -t $HOME $pkg"
    if stow_output=$(stow -d "$DOTFILES_DIR" -t "$HOME" "$pkg" 2>&1); then
        log "Stow $pkg succeeded"
        success "Stowed $pkg"
        return 0
    elif stow_output=$(stow -d "$DOTFILES_DIR" -t "$HOME" -R "$pkg" 2>&1); then
        # Restow succeeded - links were updated
        log "Restow $pkg succeeded"
        success "Restowed $pkg"
        return 0
    else
        warn "Failed to stow $pkg: $stow_output"
        log "Stow failed output: $stow_output"
        return 1
    fi
}

stow_dotfiles() {
    local packages=("$@")

    log "stow_dotfiles: starting with packages: ${packages[*]}"

    # Verify stow is available before attempting to link
    require_stow

    info "Linking configuration files with Stow..."
    log "Stowing packages: ${packages[*]}"
    log "DOTFILES_DIR=$DOTFILES_DIR"
    log "HOME=$HOME"
    log "which stow: $(which stow 2>&1 || echo 'not found')"
    log "stow version: $(stow --version 2>&1 | head -1 || echo 'failed')"

    local failed=false
    for pkg in "${packages[@]}"; do
        if ! stow_package "$pkg"; then
            failed=true
        fi
    done

    # Verify key symlinks were created
    info "Verifying stowed symlinks..."
    local verify_failed=false
    for pkg in "${packages[@]}"; do
        case "$pkg" in
            zsh)
                if [[ -L "$HOME/.zshrc" ]]; then
                    log "Verified: ~/.zshrc -> $(readlink "$HOME/.zshrc")"
                else
                    warn "Verification failed: ~/.zshrc is not a symlink"
                    log "~/.zshrc exists: $([[ -e "$HOME/.zshrc" ]] && echo yes || echo no)"
                    log "~/.zshrc is file: $([[ -f "$HOME/.zshrc" ]] && echo yes || echo no)"
                    log "Home directory contents: $(ls -la "$HOME" 2>&1 | head -20)"
                    verify_failed=true
                fi
                ;;
            git)
                if [[ -L "$HOME/.gitconfig" ]]; then
                    log "Verified: ~/.gitconfig -> $(readlink "$HOME/.gitconfig")"
                else
                    warn "Verification failed: ~/.gitconfig is not a symlink"
                    verify_failed=true
                fi
                ;;
        esac
    done

    if [[ "$failed" == true ]] || [[ "$verify_failed" == true ]]; then
        warn "Some packages failed to stow or verify"
    else
        success "Dotfiles stowed and verified."
    fi
}

# =============================================================================
# INTERACTIVE MENU SYSTEM
# =============================================================================

declare -a MENU_SELECTED
MENU_CURSOR=0

init_menu() {
    # All selected by default
    for i in "${!MENU_CONFIG[@]}"; do
        MENU_SELECTED[i]=1
    done
}

draw_menu() {
    local start_row=$1

    # Move cursor to start position
    tput cup "$start_row" 0

    for i in "${!MENU_CONFIG[@]}"; do
        local config="${MENU_CONFIG[$i]}"
        local item func stow_pkg is_macos_only deps
        IFS='|' read -r item func stow_pkg is_macos_only deps <<< "$config"
        local selected="${MENU_SELECTED[$i]}"

        # Skip macOS-only items on other platforms
        if [[ "$is_macos_only" == "true" && "$OS" != "macos" ]]; then
            continue
        fi

        # Clear line
        tput el

        # Cursor indicator
        if [[ $i -eq $MENU_CURSOR ]]; then
            echo -en "${CYAN}>${NC} "
        else
            echo -n "  "
        fi

        # Checkbox
        if [[ $selected -eq 1 ]]; then
            echo -en "${GREEN}[x]${NC} "
        else
            echo -en "${DIM}[ ]${NC} "
        fi

        # Item text
        if [[ $i -eq $MENU_CURSOR ]]; then
            echo -e "${BOLD}${item}${NC}"
        else
            echo -e "${item}"
        fi
    done

    # Draw footer
    echo ""
    tput el
    echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
    tput el
    echo -e "  ${BOLD}[space]${NC} toggle  ${BOLD}[a]${NC}ll  ${BOLD}[n]${NC}one  ${BOLD}[i]${NC}nstall  ${BOLD}[q]${NC}uit"
}

get_visible_items() {
    local -a visible=()
    for i in "${!MENU_CONFIG[@]}"; do
        local name func stow_pkg is_macos_only deps
        IFS='|' read -r name func stow_pkg is_macos_only deps <<< "${MENU_CONFIG[$i]}"
        if [[ "$is_macos_only" == "true" && "$OS" != "macos" ]]; then
            continue
        fi
        visible+=("$i")
    done
    echo "${visible[@]}"
}

run_menu() {
    local start_row=5

    # Get visible item indices
    local -a visible_indices=()
    read -ra visible_indices <<< "$(get_visible_items)"
    local visible_count=${#visible_indices[@]}
    local visible_cursor=0
    MENU_CURSOR=${visible_indices[0]}

    # Hide cursor
    tput civis

    # Clear screen and draw header
    clear
    echo ""
    echo -e "  ${BOLD}${CYAN}Dotfiles Installer${NC}"
    echo -e "  ${DIM}$OS ($(uname -m))${NC}"
    echo ""

    draw_menu $start_row

    # Input loop
    while true; do
        # Read single keypress
        IFS= read -rsn1 key

        case "$key" in
            # Arrow keys (escape sequences)
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A') # Up
                        if [[ $visible_cursor -gt 0 ]]; then
                            ((visible_cursor--))
                            MENU_CURSOR=${visible_indices[$visible_cursor]}
                        fi
                        ;;
                    '[B') # Down
                        if [[ $visible_cursor -lt $((visible_count - 1)) ]]; then
                            ((visible_cursor++))
                            MENU_CURSOR=${visible_indices[$visible_cursor]}
                        fi
                        ;;
                esac
                ;;
            # Space or Enter - toggle
            ' '|'')
                if [[ ${MENU_SELECTED[MENU_CURSOR]} -eq 1 ]]; then
                    MENU_SELECTED[MENU_CURSOR]=0
                else
                    MENU_SELECTED[MENU_CURSOR]=1
                fi
                ;;
            # Select all
            'a'|'A')
                for i in "${visible_indices[@]}"; do
                    MENU_SELECTED[i]=1
                done
                ;;
            # Select none
            'n'|'N')
                for i in "${visible_indices[@]}"; do
                    MENU_SELECTED[i]=0
                done
                ;;
            # Install
            'i'|'I')
                tput cnorm  # Show cursor
                echo ""
                return 0
                ;;
            # Quit
            'q'|'Q')
                tput cnorm  # Show cursor
                echo ""
                echo -e "${YELLOW}Cancelled.${NC}"
                exit 0
                ;;
            # j/k vim navigation
            'j')
                if [[ $visible_cursor -lt $((visible_count - 1)) ]]; then
                    ((visible_cursor++))
                    MENU_CURSOR=${visible_indices[$visible_cursor]}
                fi
                ;;
            'k')
                if [[ $visible_cursor -gt 0 ]]; then
                    ((visible_cursor--))
                    MENU_CURSOR=${visible_indices[$visible_cursor]}
                fi
                ;;
        esac

        draw_menu $start_row
    done
}

# =============================================================================
# MAIN INSTALLATION LOGIC
# =============================================================================

# Check and auto-select dependencies
resolve_dependencies() {
    local changed=true
    while [[ "$changed" == true ]]; do
        changed=false
        for i in "${!MENU_CONFIG[@]}"; do
            if [[ ${MENU_SELECTED[$i]} -ne 1 ]]; then
                continue
            fi

            local config="${MENU_CONFIG[$i]}"
            local name func stow_pkg is_macos_only deps
            IFS='|' read -r name func stow_pkg is_macos_only deps <<< "$config"

            if [[ -z "$deps" ]]; then
                continue
            fi

            # Enable all dependencies
            IFS=',' read -ra dep_indices <<< "$deps"
            for dep_idx in "${dep_indices[@]}"; do
                if [[ ${MENU_SELECTED[dep_idx]} -ne 1 ]]; then
                    MENU_SELECTED[dep_idx]=1
                    local dep_config="${MENU_CONFIG[dep_idx]}"
                    local dep_name
                    IFS='|' read -r dep_name _ <<< "$dep_config"
                    info "Auto-enabling dependency: $dep_name"
                    changed=true
                fi
            done
        done
    done
}

run_installation() {
    local stow_pkgs=()

    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}Starting dry-run (no changes will be made)...${NC}"
    else
        echo -e "${CYAN}Starting installation...${NC}"
    fi
    log "Installation started (dry_run=$DRY_RUN)"
    echo ""

    # Resolve dependencies first
    resolve_dependencies

    # Process each menu item using declarative config
    for i in "${!MENU_CONFIG[@]}"; do
        if [[ ${MENU_SELECTED[$i]} -ne 1 ]]; then
            continue
        fi

        local config="${MENU_CONFIG[$i]}"
        local name func stow_pkg is_macos_only deps
        IFS='|' read -r name func stow_pkg is_macos_only deps <<< "$config"

        # Skip macOS-only items on other platforms
        if [[ "$is_macos_only" == "true" && "$OS" != "macos" ]]; then
            continue
        fi

        # Run install function if specified
        if [[ -n "$func" ]]; then
            "$func" || true  # Continue on failure, we track it
        fi

        # Add stow package if specified
        if [[ -n "$stow_pkg" ]]; then
            stow_pkgs+=("$stow_pkg")
        fi
    done

    # Stow all selected packages
    info "Collected stow packages: ${stow_pkgs[*]:-none}"
    log "Stow packages to process: ${stow_pkgs[*]:-none}"
    if [[ ${#stow_pkgs[@]} -gt 0 ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${DIM}[dry-run] Would stow: ${stow_pkgs[*]}${NC}"
        else
            stow_dotfiles "${stow_pkgs[@]}"
        fi
    else
        warn "No stow packages collected - this may indicate a configuration issue"
    fi

    # Trust mise config files after stowing
    local mise_selected=false
    for i in "${!MENU_CONFIG[@]}"; do
        if [[ "${MENU_CONFIG[$i]}" == *"install_mise_and_runtimes"* && ${MENU_SELECTED[$i]} -eq 1 ]]; then
            mise_selected=true
            break
        fi
    done

    if [[ "$mise_selected" == true ]] && command -v mise &> /dev/null && [[ "$DRY_RUN" != true ]]; then
        info "Trusting mise config files..."
        mise trust "$XDG_CONFIG_HOME/mise/config.toml" 2>/dev/null || warn "Could not trust mise config"
        mise trust "$HOME/.tool-versions" 2>/dev/null || true
    fi

    # Print summary
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                   INSTALLATION SUMMARY                 ${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ ${#INSTALLED_ITEMS[@]} -gt 0 ]]; then
        echo -e "${GREEN}Successfully installed:${NC}"
        for item in "${INSTALLED_ITEMS[@]}"; do
            echo -e "  ${GREEN}✓${NC} $item"
        done
        echo ""
    fi

    if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
        echo -e "${RED}Failed:${NC}"
        for item in "${FAILED_ITEMS[@]}"; do
            echo -e "  ${RED}✗${NC} $item"
        done
        echo ""
    fi

    if [[ ${#SKIPPED_ITEMS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Skipped:${NC}"
        for item in "${SKIPPED_ITEMS[@]}"; do
            echo -e "  ${DIM}-${NC} $item"
        done
        echo ""
    fi

    log "Installation complete"
    if [[ ${#FAILED_ITEMS[@]} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}Installation complete!${NC}"
    else
        echo -e "${YELLOW}${BOLD}Installation complete with some failures.${NC}"
        echo -e "${DIM}Check the log for details: $LOG_FILE${NC}"
    fi
    echo -e "${DIM}State file: $STATE_FILE${NC}"
}

# =============================================================================
# CLI ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
Usage: install.sh [OPTIONS]

Options:
  -n, --dry-run     Show what would be installed without making changes
  -y, --yes         Run in headless mode (no interactive menu, install all)
  -h, --help        Show this help message

Examples:
  ./install.sh              # Interactive mode
  ./install.sh --dry-run    # Preview what would be installed
  ./install.sh --yes        # Install everything without prompts

Security Note:
  For better security, clone and review the repo before running:
    git clone https://github.com/edylim/dotfiles.git ~/.dotfiles
    cd ~/.dotfiles
    ./install.sh
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                HEADLESS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    parse_args "$@"

    # Acquire lock before doing anything
    acquire_lock

    detect_os
    validate_dependencies
    setup_package_manager
    init_menu

    if [[ "$HEADLESS" == true ]]; then
        # In headless mode, all items are selected by default (done in init_menu)
        info "Running in headless mode - installing all selected packages"
    else
        # Check if running interactively
        if [[ ! -t 0 ]]; then
            error "Not running in a terminal. Use --yes for non-interactive mode."
        fi
        run_menu
    fi

    run_installation
}

main "$@"
