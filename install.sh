#!/bin/bash

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# --- Global Variables ---
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OS=""
PKG_MANAGER=""

# --- Color and Style ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- OS Detection ---
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        OS="macos"
        PKG_MANAGER="brew"
    elif [[ -f /etc/arch-release ]]; then
        # Arch Linux or Omarchy
        OS="arch"
        PKG_MANAGER="pacman"
    elif [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        OS="debian"
        PKG_MANAGER="apt"
    else
        error "Unsupported OS. This script supports macOS, Ubuntu/Debian, and Arch/Omarchy."
    fi
    info "Detected OS: $OS (package manager: $PKG_MANAGER)"
}

# --- Package Installation Helpers ---
pkg_install() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        brew)   brew install "$pkg" ;;
        pacman) sudo pacman -S --noconfirm --needed "$pkg" ;;
        apt)    sudo apt-get install -y "$pkg" ;;
    esac
}

pkg_installed() {
    command -v "$1" &> /dev/null
}

# --- Gum Installation ---
install_gum() {
    if pkg_installed gum; then
        return 0
    fi

    info "Installing gum (required for interactive menu)..."
    case "$PKG_MANAGER" in
        brew)
            brew install gum
            ;;
        pacman)
            sudo pacman -S --noconfirm gum
            ;;
        apt)
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y gum
            ;;
    esac
}

# --- Package Manager Setup ---
setup_package_manager() {
    info "Setting up package manager..."
    case "$PKG_MANAGER" in
        brew)
            if ! pkg_installed brew; then
                info "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                if [[ -f /opt/homebrew/bin/brew ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -f /usr/local/bin/brew ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            fi
            # brew update # Optional, can be slow
            ;;
        pacman)
            # sudo pacman -Syu --noconfirm # Optional
            ;;
        apt)
            sudo apt-get update
            ;;
    esac
}

# --- Core Package Installation ---
install_core_packages() {
    info "Installing core packages (git, stow, curl)..."

    case "$OS" in
        macos)
            brew install git stow curl wget
            ;;
        arch)
            sudo pacman -S --noconfirm --needed git stow curl wget
            ;;
        debian)
            sudo apt-get install -y git stow curl wget
            ;;
    esac
    success "Core packages installed."
}

# --- Install Mise & Runtimes ---
install_mise() {
    info "Installing Mise (Runtime Manager)..."
    
    # Install Mise
    case "$OS" in
        macos)
            if ! pkg_installed mise; then
                brew install mise
            fi
            ;;
        arch)
            if ! pkg_installed mise; then
                sudo pacman -S --noconfirm --needed mise || \
                # Fallback to AUR or manual if not in repo (it is in Extra usually)
                curl https://mise.run | sh
            fi
            ;;
        debian)
            if ! pkg_installed mise; then
                # Debian doesn't have mise in standard repos usually
                curl https://mise.run | sh
                # Add to path for this session
                export PATH="$HOME/.local/bin:$PATH"
            fi
            ;;
    esac

    # Activate mise for this script session
    eval "$(mise activate bash)"
    success "Mise installed."
}

configure_mise_runtimes() {
    info "Configuring Runtimes via Mise (Node.js, Python)..."
    
    # Ensure mise is active
    if ! command -v mise &> /dev/null; then
        # Try finding it if not in PATH yet
        if [[ -f "$HOME/.local/bin/mise" ]]; then
            export PATH="$HOME/.local/bin:$PATH"
        fi
        eval "$(mise activate bash)"
    fi

    # Install Node.js
    info "Installing Node.js (latest)..."
    mise use --global node@latest
    
    # Install Python
    info "Installing Python (latest)..."
    mise use --global python@latest

    success "Runtimes configured."
}

# --- Install Yarn ---
install_yarn() {
    info "Installing Yarn..."
    
    # Ensure we have node
    if ! command -v node &> /dev/null; then
        warn "Node.js not found. Installing via mise..."
        install_mise
        configure_mise_runtimes
    fi

    if ! pkg_installed yarn; then
        npm install -g yarn || warn "Failed to install yarn via npm"
    else
        success "Yarn already installed."
    fi
}

# --- Install Chrome ---
install_chrome() {
    info "Installing Google Chrome..."
    case "$OS" in
        macos)
            brew install --cask google-chrome
            ;;
        debian)
            if ! pkg_installed google-chrome; then
                wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
                sudo dpkg -i /tmp/chrome.deb || sudo apt-get install -f -y
                rm /tmp/chrome.deb
            else
                success "Chrome already installed."
            fi
            ;;
        arch)
            # Check for yay or paru
            if pkg_installed yay; then
                yay -S --noconfirm google-chrome
            elif pkg_installed paru; then
                paru -S --noconfirm google-chrome
            else
                warn "AUR helper (yay/paru) not found. Skipping Chrome installation on Arch."
                warn "Install manually or install 'yay' first."
            fi
            ;;
    esac
}

# --- Install JankyBorders (macOS only) ---
install_jankyborders() {
    if [[ "$OS" != "macos" ]]; then
        return
    fi
    info "Installing JankyBorders..."
    brew tap FelixKratz/formulae
    brew install borders
}

# --- Install Awrit ---
install_awrit() {
    info "Installing Awrit..."
    local AW_INSTALL_DIR="$HOME/.awrit"

    if [[ -f "$AW_INSTALL_DIR/awrit" ]]; then
        success "Awrit already installed."
    else
        curl -fsS https://chase.github.io/awrit/get | DOWNLOAD_TO="$AW_INSTALL_DIR" bash
        success "Awrit downloaded."
    fi

    # Remove default kitty.css so stow can create symlink
    # We copied existing config to awrit/.awrit/dist/kitty.css
    # Stow will handle the linking if the target file doesn't exist or is a link
    if [[ -f "$AW_INSTALL_DIR/dist/kitty.css" && ! -L "$AW_INSTALL_DIR/dist/kitty.css" ]]; then
         rm "$AW_INSTALL_DIR/dist/kitty.css"
    fi
}

# --- Install GrumpyVim ---
install_grumpyvim() {
    info "Installing GrumpyVim..."
    local NVIM_CONFIG_DIR="$HOME/.config/nvim"

    if [[ -d "$NVIM_CONFIG_DIR" ]]; then
        if [[ -d "$NVIM_CONFIG_DIR/.git" ]] && git -C "$NVIM_CONFIG_DIR" remote -v | grep -q "grumpyvim"; then
            info "GrumpyVim already cloned. Running its installer..."
        else
            warn "Existing Neovim config found. Backing up..."
            mv "$NVIM_CONFIG_DIR" "$NVIM_CONFIG_DIR.bak.$(date +%F-%H%M%S)"
            git clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
        fi
    else
        git clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
    fi

    # Execute GrumpyVim's own install script
    if [[ -f "$NVIM_CONFIG_DIR/install.sh" ]]; then
        info "Executing GrumpyVim install script..."
        chmod +x "$NVIM_CONFIG_DIR/install.sh"
        bash "$NVIM_CONFIG_DIR/install.sh"
    fi
    
    success "GrumpyVim installed."
}

# --- Stow Dotfiles ---
stow_package() {
    local pkg="$1"
    info "Stowing $pkg..."
    # Ensure dotfiles dir is where we expect
    cd "$DOTFILES_DIR"
    
    # Check if package directory exists
    if [[ ! -d "$pkg" ]]; then
        warn "Package directory '$pkg' not found in $DOTFILES_DIR. Skipping."
        return
    fi

    stow -R "$pkg" 2>/dev/null || stow "$pkg"
    cd - > /dev/null
}

stow_dotfiles() {
    local packages=("$@")
    info "Linking configuration files with Stow..."
    for pkg in "${packages[@]}"; do
        stow_package "$pkg"
    done
    success "Dotfiles stowed."
}

# --- Install Prezto ---
install_prezto() {
    info "Installing Prezto..."
    if [[ -d "${ZDOTDIR:-$HOME}/.zprezto" ]]; then
        success "Prezto already installed."
    else
        git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
        success "Prezto installed."
    fi
}

# --- Set Zsh as Default Shell ---
set_zsh_default() {
    info "Setting Zsh as default shell..."
    local ZSH_PATH
    ZSH_PATH=$(which zsh)

    if [[ "$SHELL" == "$ZSH_PATH" ]]; then
        success "Zsh is already the default shell."
        return
    fi

    # Add zsh to /etc/shells if not present
    if ! grep -q "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
    fi

    if chsh -s "$ZSH_PATH"; then
        success "Default shell changed to Zsh."
    else
        warn "Could not change default shell. Run manually: chsh -s $ZSH_PATH"
    fi
}

# --- Main Interactive Menu ---
main() {
    detect_os
    setup_package_manager
    install_gum

    echo ""
    gum style \
        --border normal \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 212 \
        "Dotfiles Installer (macOS, Ubuntu, Omarchy)"

    # Define available packages
    local ALL_PACKAGES=(
        "Core (Git, Stow, Curl)" 
        "Zsh & Prezto"
        "Mise & Runtimes (Node, Python)" 
        "Yarn" 
        "Google Chrome" 
        "Kitty Terminal"
        "GrumpyVim (Neovim)" 
        "Awrit" 
        "JankyBorders (macOS)" 
        "Linting Configs"
        "Bin Scripts"
        "Stow Configs"
    )

    # Join array with commas for default selection
    # Use a subshell or temporary IFS change to avoid affecting subsequent commands
    local ALL_SELECTED
    ALL_SELECTED=$(IFS=, ; echo "${ALL_PACKAGES[*]}")
    
    local choices
    choices=$(gum choose --no-limit --height 15 --selected="$ALL_SELECTED" "${ALL_PACKAGES[@]}")

    if [[ -z "$choices" ]]; then
        warn "No selections made. Exiting."
        exit 0
    fi

    echo ""
    gum style --foreground 212 "Starting installation..."

    local stow_pkgs=()

    if echo "$choices" | grep -q "Core"; then
        install_core_packages
    fi

    if echo "$choices" | grep -q "Zsh & Prezto"; then
        install_prezto
        set_zsh_default
        stow_pkgs+=("zsh")
    fi

    if echo "$choices" | grep -q "Mise & Runtimes"; then
        install_mise
        configure_mise_runtimes
        stow_pkgs+=("mise")
    fi

    if echo "$choices" | grep -q "Yarn"; then
        install_yarn
        stow_pkgs+=("yarn")
    fi

    if echo "$choices" | grep -q "Google Chrome"; then
        install_chrome
    fi

    if echo "$choices" | grep -q "Kitty Terminal"; then
        stow_pkgs+=("kitty")
    fi

    if echo "$choices" | grep -q "GrumpyVim"; then
        install_grumpyvim
    fi

    if echo "$choices" | grep -q "Awrit"; then
        install_awrit
        stow_pkgs+=("awrit")
    fi

    if echo "$choices" | grep -q "JankyBorders"; then
        install_jankyborders
        stow_pkgs+=("jankyborders")
    fi
    
    if echo "$choices" | grep -q "Linting Configs"; then
        stow_pkgs+=("linting")
    fi

    if echo "$choices" | grep -q "Bin Scripts"; then
        stow_pkgs+=("bin")
    fi

    if echo "$choices" | grep -q "Stow Configs"; then
        # Stow git by default if Stow Configs is selected
        stow_pkgs+=("git")
    fi

    # Perform stowing if any packages are added to stow_pkgs
    if [[ ${#stow_pkgs[@]} -gt 0 ]]; then
        stow_dotfiles "${stow_pkgs[@]}"
    fi

    echo ""
    gum style --foreground 212 "Installation complete!"
}

main "$@"
