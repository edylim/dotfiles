#!/bin/bash

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# Note: This script uses indexed arrays (bash 3.2+), not associative arrays
# macOS ships with bash 3.2, so we maintain compatibility

# --- Bootstrap: Handle curl pipe installation ---
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/edylim/dotfiles/master/install.sh)"
DOTFILES_REPO="https://github.com/edylim/dotfiles.git"
DOTFILES_TARGET="$HOME/.dotfiles"

if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
    echo "Bootstrapping dotfiles installation..."
    if ! command -v git &> /dev/null; then
        echo "Error: git is required. Please install git first."
        exit 1
    fi
    if [[ -d "$DOTFILES_TARGET" ]]; then
        echo "Updating existing dotfiles..."
        if ! git -C "$DOTFILES_TARGET" pull --rebase; then
            echo "Warning: Failed to update dotfiles, continuing with existing version..."
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

# --- Menu Item Configuration ---
# Each item: name|install_func|stow_pkg|macos_only
# stow_pkg is empty if no stowing needed
declare -a MENU_CONFIG=(
    "Core Packages (git, stow, curl, wget)|install_core_packages||false"
    "CLI Tools (zsh, fzf, bat, zoxide, yazi, htop, gh)|install_cli_tools||false"
    "Git Tools (scmpuff, onefetch)|install_git_tools||false"
    "Media Tools (ffmpeg, imagemagick, poppler)|install_media_tools||false"
    "AI Tools (claude, gemini-cli)|install_ai_tools||false"
    "Mise & Runtimes (Node.js LTS, Python)|install_mise_and_runtimes|mise|false"
    "Yarn|install_yarn|yarn|false"
    "Kitty Terminal|install_kitty|kitty|false"
    "Google Chrome|install_chrome||false"
    "GrumpyVim (Neovim)|install_grumpyvim||false"
    "Zsh & Prezto|install_zsh_prezto|zsh|false"
    "Awrit|install_awrit|awrit|false"
    "JankyBorders (macOS)|install_jankyborders|jankyborders|true"
    "SketchyBar (macOS)|install_sketchybar|sketchybar|true"
    "Linting Configs||linting|false"
    "Bin Scripts||bin|false"
    "Git Config||git|false"
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
            # Both failed - skip rotation this time, don't silently ignore
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

# --- Cleanup and signal handling ---
cleanup() {
    tput cnorm 2>/dev/null || true  # Restore cursor
}
trap cleanup EXIT INT TERM

# --- Dependency Validation ---
STOW_AVAILABLE=false

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

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
    fi
}

# Verify stow is available before attempting to stow
require_stow() {
    if ! command -v stow &> /dev/null; then
        error "GNU Stow is required but not installed. Please install Core Packages first."
    fi
}

# --- OS Detection ---
detect_os() {
    ARCH="$(uname -m)"
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

# --- Package Installation Helpers ---
pkg_install() {
    local pkg="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install: $pkg${NC}"
        return 0
    fi
    case "$PKG_MANAGER" in
        brew)   brew install "$pkg" ;;
        pacman) sudo pacman -S --noconfirm --needed "$pkg" ;;
        apt)    sudo apt-get install -y "$pkg" ;;
    esac
}

pkg_installed() {
    command -v "$1" &> /dev/null
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

# Git clone with timeout to prevent hanging
GIT_TIMEOUT="${GIT_TIMEOUT:-120}"  # Default 2 minutes

git_clone() {
    local repo="$1"
    local dest="$2"
    shift 2
    local extra_args=("$@")

    if command -v timeout &> /dev/null; then
        timeout "$GIT_TIMEOUT" git clone "${extra_args[@]}" "$repo" "$dest"
    elif command -v gtimeout &> /dev/null; then
        # macOS with coreutils
        gtimeout "$GIT_TIMEOUT" git clone "${extra_args[@]}" "$repo" "$dest"
    else
        # Fallback without timeout
        git clone "${extra_args[@]}" "$repo" "$dest"
    fi
}

git_pull() {
    local dir="$1"
    shift
    local extra_args=("$@")

    if command -v timeout &> /dev/null; then
        timeout "$GIT_TIMEOUT" git -C "$dir" pull "${extra_args[@]}"
    elif command -v gtimeout &> /dev/null; then
        gtimeout "$GIT_TIMEOUT" git -C "$dir" pull "${extra_args[@]}"
    else
        git -C "$dir" pull "${extra_args[@]}"
    fi
}

git_submodule_update() {
    local dir="$1"
    shift
    local extra_args=("$@")

    if command -v timeout &> /dev/null; then
        timeout "$GIT_TIMEOUT" git -C "$dir" submodule update "${extra_args[@]}"
    elif command -v gtimeout &> /dev/null; then
        gtimeout "$GIT_TIMEOUT" git -C "$dir" submodule update "${extra_args[@]}"
    else
        git -C "$dir" submodule update "${extra_args[@]}"
    fi
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
    [[ -d "/Applications/$1.app" ]] || [[ -d "$HOME/Applications/$1.app" ]]
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
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            # Source Homebrew if not already in PATH (avoid duplication)
            if ! command -v brew &> /dev/null; then
                if [[ "$ARCH" == "arm64" ]] && [[ -f /opt/homebrew/bin/brew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -f /usr/local/bin/brew ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            fi
            ;;
        pacman)
            ;;
        apt)
            sudo apt-get update
            ;;
    esac
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

install_core_packages() {
    info "Installing core packages..."
    case "$OS" in
        macos)
            brew_install git stow curl wget coreutils
            ;;
        arch)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: git stow curl wget${NC}"
            else
                sudo pacman -S --noconfirm --needed git stow curl wget
            fi
            ;;
        debian)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: git stow curl wget${NC}"
            else
                sudo apt-get install -y git stow curl wget
            fi
            ;;
    esac
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
                sudo pacman -S --noconfirm --needed zsh fzf bat htop github-cli jq tree zoxide yazi || failed=true
            fi
            ;;
        debian)
            if [[ "$DRY_RUN" != true ]]; then
                sudo apt-get install -y zsh fzf bat htop gh jq tree || failed=true
            fi
            if ! pkg_installed zoxide; then
                info "Installing zoxide..."
                if [[ "$DRY_RUN" != true ]]; then
                    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash || warn "zoxide installation failed"
                fi
            fi
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
        warn "Some CLI tools may not have installed correctly"
    else
        success "CLI tools installed."
    fi
}

install_ai_tools() {
    info "Installing AI CLI tools..."
    local installed_something=false

    case "$OS" in
        macos)
            brew_install gemini-cli
            installed_something=true
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
        warn "npm not found. Install Node.js/mise first for Claude Code CLI."
    fi

    if [[ "$installed_something" == true ]]; then
        success "AI tools installed."
    else
        warn "No AI tools were installed (missing dependencies)."
    fi
}

install_git_tools() {
    info "Installing git tools..."
    local installed=false
    case "$OS" in
        macos)
            brew_install scmpuff onefetch
            installed=true
            ;;
        arch)
            if [[ "$DRY_RUN" != true ]]; then
                sudo pacman -S --noconfirm --needed onefetch && installed=true
                # scmpuff may need AUR
                if pkg_installed yay; then
                    yay -S --noconfirm scmpuff
                elif pkg_installed paru; then
                    paru -S --noconfirm scmpuff
                else
                    warn "scmpuff requires AUR helper (yay/paru)"
                fi
            fi
            ;;
        debian)
            # scmpuff and onefetch need manual install on Debian
            warn "scmpuff/onefetch not in apt repos. Install manually:"
            warn "  onefetch: https://github.com/o2sh/onefetch/releases"
            warn "  scmpuff: https://github.com/mroth/scmpuff/releases"
            return 0
            ;;
    esac
    if [[ "$installed" == true ]] || [[ "$DRY_RUN" == true ]]; then
        success "Git tools installed."
    fi
}

install_media_tools() {
    info "Installing media tools..."
    case "$OS" in
        macos)
            brew_install ffmpeg sevenzip poppler resvg imagemagick
            ;;
        arch)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: ffmpeg p7zip poppler imagemagick${NC}"
            else
                sudo pacman -S --noconfirm --needed ffmpeg p7zip poppler imagemagick
            fi
            ;;
        debian)
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install: ffmpeg p7zip-full poppler-utils imagemagick${NC}"
            else
                sudo apt-get install -y ffmpeg p7zip-full poppler-utils imagemagick
            fi
            ;;
    esac
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
                brew install mise
            fi
            ;;
        arch)
            if ! pkg_installed mise; then
                if ! sudo pacman -S --noconfirm --needed mise 2>/dev/null; then
                    info "Mise not in pacman, installing via script..."
                    curl https://mise.run | sh
                fi
            fi
            ;;
        debian)
            if ! pkg_installed mise; then
                curl https://mise.run | sh
                export PATH="$HOME/.local/bin:$PATH"
            fi
            ;;
    esac
    mkdir -p "$HOME/.config/mise"

    # Activate mise for this session
    if command -v mise &> /dev/null; then
        eval "$(mise activate bash)"
    elif [[ -f "$HOME/.local/bin/mise" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        eval "$("$HOME/.local/bin/mise" activate bash)"
    else
        warn "Mise installed but could not activate. You may need to restart your shell."
        return 1
    fi

    # Configure runtimes with LTS versions (not latest)
    info "Installing Node.js LTS and Python via Mise..."
    mise use --global node@lts
    mise use --global python@3.12  # Stable version, not bleeding edge

    if verify_installed node && verify_installed python; then
        success "Mise and runtimes installed."
    else
        warn "Mise installed but some runtimes may need manual setup."
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
            warn "npm not found and mise not available. Install Mise & Runtimes first, then Yarn."
            return 1
        fi
    fi

    # Now npm should be available
    if command -v npm &> /dev/null; then
        if npm install -g yarn; then
            success "Yarn installed."
        else
            warn "Yarn installation failed"
            return 1
        fi
    else
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
            sudo pacman -S --noconfirm --needed kitty
            ;;
        debian)
            if pkg_installed kitty; then
                echo -e "  ${DIM}kitty already installed${NC}"
            else
                # Download and run installer properly (not piped to sh with stdin)
                local tmp_installer
                tmp_installer=$(mktemp)
                if curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh -o "$tmp_installer"; then
                    bash "$tmp_installer"
                    rm -f "$tmp_installer"
                else
                    warn "Failed to download kitty installer"
                    rm -f "$tmp_installer"
                    return 1
                fi
            fi
            ;;
    esac
    verify_installed kitty && success "Kitty installed." || warn "Kitty installation could not be verified"
}

install_chrome() {
    info "Installing Google Chrome..."
    local installed=false

    case "$OS" in
        macos)
            cask_install google-chrome
            installed=true
            ;;
        debian)
            if pkg_installed google-chrome-stable; then
                echo -e "  ${DIM}google-chrome already installed${NC}"
                return 0
            elif [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" ]]; then
                warn "Google Chrome is only available for x86_64 on Linux. Skipping."
                return 0
            elif [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install Google Chrome${NC}"
                return 0
            else
                local chrome_deb
                chrome_deb=$(mktemp --suffix=.deb)
                if wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O "$chrome_deb"; then
                    sudo dpkg -i "$chrome_deb" || sudo apt-get install -f -y
                    rm -f "$chrome_deb"
                    installed=true
                else
                    rm -f "$chrome_deb"
                    warn "Failed to download Chrome"
                    return 1
                fi
            fi
            ;;
        arch)
            if pkg_installed google-chrome-stable; then
                echo -e "  ${DIM}google-chrome already installed${NC}"
                return 0
            elif [[ "$ARCH" != "x86_64" ]]; then
                warn "Google Chrome is only available for x86_64 on Linux. Skipping."
                return 0
            elif [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would install Google Chrome via AUR${NC}"
                return 0
            elif pkg_installed yay; then
                yay -S --noconfirm google-chrome
                installed=true
            elif pkg_installed paru; then
                paru -S --noconfirm google-chrome
                installed=true
            else
                warn "AUR helper not found. Skipping Chrome."
                return 0
            fi
            ;;
    esac

    if [[ "$installed" == true ]]; then
        success "Chrome installed."
    fi
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
        return 0
    fi

    curl -fsS https://chase.github.io/awrit/get | DOWNLOAD_TO="$AW_INSTALL_DIR" bash
    if [[ -f "$AW_INSTALL_DIR/dist/kitty.css" && ! -L "$AW_INSTALL_DIR/dist/kitty.css" ]]; then
         rm "$AW_INSTALL_DIR/dist/kitty.css"
    fi
    success "Awrit installed."
}

install_grumpyvim() {
    info "Installing GrumpyVim..."
    local NVIM_CONFIG_DIR="$HOME/.config/nvim"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would install GrumpyVim to $NVIM_CONFIG_DIR${NC}"
        return 0
    fi

    # Handle symlinks (including broken ones)
    if [[ -L "$NVIM_CONFIG_DIR" ]]; then
        local link_target
        link_target=$(readlink "$NVIM_CONFIG_DIR")
        if [[ -d "$link_target" ]] && [[ -d "$link_target/.git" ]] && git -C "$link_target" remote -v 2>/dev/null | grep -q "grumpyvim"; then
            info "GrumpyVim already linked."
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
            mv "$NVIM_CONFIG_DIR" "$NVIM_CONFIG_DIR.bak.$(date +%F-%H%M%S)"
            git_clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
        fi
    else
        git_clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
    fi

    if [[ -f "$NVIM_CONFIG_DIR/install.sh" ]]; then
        chmod +x "$NVIM_CONFIG_DIR/install.sh"
        bash "$NVIM_CONFIG_DIR/install.sh"
    fi
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
        echo -e "  ${DIM}Prezto already installed${NC}"
    else
        info "Cloning Prezto (this may take a moment)..."
        if ! git_clone https://github.com/sorin-ionescu/prezto.git "$prezto_dir" --depth 1 --recursive; then
            warn "Failed to clone Prezto"
            return 1
        fi
        # Update submodules with depth limit too
        git_submodule_update "$prezto_dir" --init --recursive --depth 1
    fi

    # Set Zsh as default shell
    local ZSH_PATH
    ZSH_PATH="$(command -v zsh)"
    if [[ -z "$ZSH_PATH" ]]; then
        warn "Zsh not found in PATH. Cannot set as default shell."
        return 1
    fi

    if [[ "$SHELL" == "$ZSH_PATH" ]]; then
        echo -e "  ${DIM}Zsh is already the default shell${NC}"
    else
        if ! grep -q "$ZSH_PATH" /etc/shells; then
            echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
        fi
        # In headless mode, chsh may prompt for password which breaks automation
        # Use sudo chsh which doesn't prompt if we already have sudo cached
        if [[ "$HEADLESS" == true ]]; then
            if sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null; then
                success "Default shell changed to Zsh."
            else
                warn "Could not change default shell in headless mode. Run manually: chsh -s $ZSH_PATH"
            fi
        elif chsh -s "$ZSH_PATH"; then
            success "Default shell changed to Zsh."
        else
            warn "Could not change default shell. Run manually: chsh -s $ZSH_PATH"
        fi
    fi

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
    local backup_dir="$HOME/.dotfiles-backup/$(date +%F-%H%M%S)-$$"
    local conflicts
    local stow_exit_code=0
    conflicts=$(stow -d "$DOTFILES_DIR" -t "$HOME" -n "$pkg" 2>&1) || stow_exit_code=$?

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
                # It's a real file - back it up
                local target_dir
                target_dir=$(dirname "$backup_dir/$target")
                mkdir -p "$target_dir"
                if mv "$full_path" "$backup_dir/$target"; then
                    echo -e "  ${DIM}Backed up $target${NC}"
                else
                    warn "Failed to backup $target"
                fi
            fi
        done
    fi

    # Run stow - try regular stow first, use -R (restow) for updates
    local stow_output
    if stow_output=$(stow -d "$DOTFILES_DIR" -t "$HOME" "$pkg" 2>&1); then
        return 0
    elif stow_output=$(stow -d "$DOTFILES_DIR" -t "$HOME" -R "$pkg" 2>&1); then
        # Restow succeeded - links were updated
        return 0
    else
        warn "Failed to stow $pkg: $stow_output"
        return 1
    fi
}

stow_dotfiles() {
    local packages=("$@")

    # Verify stow is available before attempting to link
    require_stow

    info "Linking configuration files with Stow..."
    for pkg in "${packages[@]}"; do
        stow_package "$pkg"
    done
    success "Dotfiles stowed."
}

# =============================================================================
# INTERACTIVE MENU SYSTEM
# =============================================================================

declare -a MENU_SELECTED
MENU_CURSOR=0

# Parse menu config item - use IFS splitting to avoid subshells
# Usage: IFS='|' read -r name func stow macos <<< "$config"
# This is more efficient than spawning subshells with cut

init_menu() {
    # All selected by default
    for i in "${!MENU_CONFIG[@]}"; do
        MENU_SELECTED[$i]=1
    done
}

draw_menu() {
    local start_row=$1

    # Move cursor to start position
    tput cup "$start_row" 0

    for i in "${!MENU_CONFIG[@]}"; do
        local config="${MENU_CONFIG[$i]}"
        local item func stow_pkg is_macos_only
        IFS='|' read -r item func stow_pkg is_macos_only <<< "$config"
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
        local name func stow_pkg is_macos_only
        IFS='|' read -r name func stow_pkg is_macos_only <<< "${MENU_CONFIG[$i]}"
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
    local -a visible_indices=($(get_visible_items))
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
                if [[ ${MENU_SELECTED[$MENU_CURSOR]} -eq 1 ]]; then
                    MENU_SELECTED[$MENU_CURSOR]=0
                else
                    MENU_SELECTED[$MENU_CURSOR]=1
                fi
                ;;
            # Select all
            'a'|'A')
                for i in "${visible_indices[@]}"; do
                    MENU_SELECTED[$i]=1
                done
                ;;
            # Select none
            'n'|'N')
                for i in "${visible_indices[@]}"; do
                    MENU_SELECTED[$i]=0
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

    # Process each menu item using declarative config
    for i in "${!MENU_CONFIG[@]}"; do
        if [[ ${MENU_SELECTED[$i]} -ne 1 ]]; then
            continue
        fi

        local config="${MENU_CONFIG[$i]}"
        local name func stow_pkg is_macos_only
        IFS='|' read -r name func stow_pkg is_macos_only <<< "$config"

        # Skip macOS-only items on other platforms
        if [[ "$is_macos_only" == "true" && "$OS" != "macos" ]]; then
            continue
        fi

        # Run install function if specified
        if [[ -n "$func" ]]; then
            "$func"
        fi

        # Add stow package if specified
        if [[ -n "$stow_pkg" ]]; then
            stow_pkgs+=("$stow_pkg")
        fi
    done

    # Stow all selected packages
    if [[ ${#stow_pkgs[@]} -gt 0 ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${DIM}[dry-run] Would stow: ${stow_pkgs[*]}${NC}"
        else
            stow_dotfiles "${stow_pkgs[@]}"
        fi
    fi

    # Trust mise config files after stowing (find mise index dynamically)
    local mise_selected=false
    for i in "${!MENU_CONFIG[@]}"; do
        if [[ "${MENU_CONFIG[$i]}" == *"install_mise_and_runtimes"* && ${MENU_SELECTED[$i]} -eq 1 ]]; then
            mise_selected=true
            break
        fi
    done

    if [[ "$mise_selected" == true ]] && command -v mise &> /dev/null && [[ "$DRY_RUN" != true ]]; then
        info "Trusting mise config files..."
        mise trust "$HOME/.config/mise/config.toml" 2>/dev/null || warn "Could not trust mise config"
        mise trust "$HOME/.tool-versions" 2>/dev/null || true
    fi

    echo ""
    log "Installation complete"
    echo -e "${GREEN}${BOLD}Installation complete!${NC}"
    echo -e "${DIM}Log file: $LOG_FILE${NC}"
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
