#!/bin/bash

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# --- Global Variables ---
DOTFILES_DIR="$HOME/.dotfiles"
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
        success "gum is already installed."
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
    success "gum installed."
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
            info "Updating Homebrew..."
            brew update
            ;;
        pacman)
            info "Updating pacman..."
            sudo pacman -Syu --noconfirm
            ;;
        apt)
            info "Updating apt..."
            sudo apt-get update
            ;;
    esac
    success "Package manager ready."
}

# --- Core Package Installation ---
install_core_packages() {
    info "Installing core packages..."

    case "$OS" in
        macos)
            info "Installing packages from Brewfile..."
            brew bundle --file="$DOTFILES_DIR/homebrew/Brewfile" || warn "Some Brewfile packages may have failed"
            ;;
        arch)
            local PACKAGES=(
                git stow zsh neovim tmux fzf bat htop github-cli jq tree wget
                zoxide lazygit ripgrep fd ffmpeg p7zip poppler imagemagick
                kitty nodejs npm onefetch
            )
            info "Installing: ${PACKAGES[*]}"
            sudo pacman -S --noconfirm --needed "${PACKAGES[@]}"

            # Install yazi from official repos (available in Arch)
            sudo pacman -S --noconfirm --needed yazi

            # Install scmpuff from AUR if yay is available
            if pkg_installed yay; then
                yay -S --noconfirm scmpuff || warn "scmpuff installation failed"
            else
                warn "yay not found, skipping scmpuff (AUR package)"
            fi
            ;;
        debian)
            local PACKAGES=(
                git stow zsh neovim tmux fzf bat htop gh jq tree wget curl
                zoxide ripgrep fd-find build-essential ffmpeg p7zip-full unzip
                poppler-utils librsvg2-bin imagemagick kitty nodejs npm
            )
            info "Installing: ${PACKAGES[*]}"
            sudo apt-get install -y "${PACKAGES[@]}"

            # Install lazygit (not in default Ubuntu repos)
            if ! pkg_installed lazygit; then
                info "Installing lazygit..."
                LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
                curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
                sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit
                rm /tmp/lazygit.tar.gz
            fi

            # Install yazi (not in default Ubuntu repos)
            if ! pkg_installed yazi; then
                info "Installing yazi..."
                local YAZI_URL=$(curl -s "https://api.github.com/repos/sxyazi/yazi/releases/latest" | grep -Po '"browser_download_url": "\K[^"]*x86_64-unknown-linux-musl.zip')
                curl -Lo /tmp/yazi.zip "$YAZI_URL"
                unzip -o /tmp/yazi.zip -d /tmp/yazi
                sudo mv /tmp/yazi/yazi-x86_64-unknown-linux-musl/yazi /usr/local/bin/
                sudo mv /tmp/yazi/yazi-x86_64-unknown-linux-musl/ya /usr/local/bin/
                rm -rf /tmp/yazi.zip /tmp/yazi
            fi

            # Install onefetch
            if ! pkg_installed onefetch; then
                info "Installing onefetch..."
                curl -Lo /tmp/onefetch.deb "https://github.com/o2sh/onefetch/releases/latest/download/onefetch_linux_amd64.deb" 2>/dev/null || \
                    curl -Lo /tmp/onefetch.deb "$(curl -s https://api.github.com/repos/o2sh/onefetch/releases/latest | grep -Po '"browser_download_url": "\K[^"]*amd64.deb')"
                sudo dpkg -i /tmp/onefetch.deb || sudo apt-get install -f -y
                rm /tmp/onefetch.deb
            fi

            # Install scmpuff
            if ! pkg_installed scmpuff; then
                info "Installing scmpuff..."
                local SCMPUFF_URL=$(curl -s "https://api.github.com/repos/mroth/scmpuff/releases/latest" | grep -Po '"browser_download_url": "\K[^"]*linux_amd64.tar.gz')
                curl -Lo /tmp/scmpuff.tar.gz "$SCMPUFF_URL"
                sudo tar xf /tmp/scmpuff.tar.gz -C /usr/local/bin scmpuff
                rm /tmp/scmpuff.tar.gz
            fi
            ;;
    esac
    success "Core packages installed."
}

# --- Install NPM Tools ---
install_npm_tools() {
    info "Installing global npm packages..."
    local NPM_PACKAGES=(
        "eslint@latest"
        "prettier@latest"
        "eslint-config-airbnb-base@latest"
        "eslint-plugin-import@latest"
        "eslint-config-prettier@latest"
    )

    # Add gemini-cli on Linux (already in Brewfile for macOS)
    if [[ "$OS" != "macos" ]]; then
        NPM_PACKAGES+=("@google/gemini-cli@latest")
    fi

    sudo npm install -g "${NPM_PACKAGES[@]}" || warn "Some npm packages may have failed"
    success "NPM packages installed."
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

# --- Install TPM (Tmux Plugin Manager) ---
install_tpm() {
    info "Installing TPM (Tmux Plugin Manager)..."
    if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
        success "TPM already installed."
    else
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
        success "TPM installed."
    fi
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
    [[ -f "$AW_INSTALL_DIR/dist/kitty.css" ]] && rm "$AW_INSTALL_DIR/dist/kitty.css"
}

# --- Install GrumpyVim ---
install_grumpyvim() {
    info "Installing GrumpyVim..."
    local NVIM_CONFIG_DIR="$HOME/.config/nvim"

    if [[ -d "$NVIM_CONFIG_DIR" ]]; then
        if [[ -d "$NVIM_CONFIG_DIR/.git" ]] && git -C "$NVIM_CONFIG_DIR" remote -v | grep -q "grumpy-vim"; then
            success "GrumpyVim already installed."
            return
        fi
        warn "Existing Neovim config found. Backing up..."
        mv "$NVIM_CONFIG_DIR" "$NVIM_CONFIG_DIR.bak.$(date +%F-%H%M%S)"
    fi

    git clone https://github.com/edylim/grumpy-vim.git "$NVIM_CONFIG_DIR"
    success "GrumpyVim installed."
}

# --- Stow Dotfiles ---
stow_package() {
    local pkg="$1"
    info "Stowing $pkg..."
    cd "$DOTFILES_DIR"
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

# --- Display Summary ---
display_summary() {
    gum style \
        --border normal \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 212 \
        "Dotfiles Installer for macOS, Ubuntu & Omarchy"

    echo ""
    gum style --foreground 212 "This will install and configure:"
    echo ""
    echo "  Core Tools:     git, stow, zsh, neovim, tmux, fzf, bat, ripgrep, fd"
    echo "  CLI Utilities:  htop, jq, tree, wget, zoxide, lazygit, yazi"
    echo "  Media:          ffmpeg, imagemagick, poppler"
    echo "  Terminal:       kitty"
    echo "  Shell:          Prezto framework, Powerlevel10k theme"
    echo "  Dev Tools:      Node.js, ESLint, Prettier"
    echo "  Extras:         Awrit, GrumpyVim, vim-kitty-navigator"
    echo ""
}

# --- Main Interactive Menu ---
main() {
    detect_os
    setup_package_manager
    install_gum

    display_summary

    # Phase 1: Core choices
    gum style "Select components to install:"
    echo ""

    local choices
    choices=$(gum choose --no-limit --height 15 \
        "Core Packages" \
        "Zsh + Prezto" \
        "Kitty Terminal" \
        "Tmux + TPM" \
        "GrumpyVim (Neovim)" \
        "Awrit (Terminal Browser)" \
        "vim-kitty-navigator" \
        "Yazi (File Manager)" \
        "Linting (ESLint/Prettier)" \
        "Set Zsh as Default Shell"
    )

    if [[ -z "$choices" ]]; then
        warn "No selections made. Exiting."
        exit 0
    fi

    echo ""
    gum style --foreground 212 "Selected: "
    echo "$choices" | sed 's/^/  - /'
    echo ""

    if ! gum confirm "Proceed with installation?"; then
        info "Installation cancelled."
        exit 0
    fi

    echo ""
    gum style --foreground 212 "Starting installation..."
    echo ""

    # Track what to stow
    local stow_packages=()

    # Core Packages
    if echo "$choices" | grep -q "Core Packages"; then
        install_core_packages
    fi

    # Zsh + Prezto
    if echo "$choices" | grep -q "Zsh + Prezto"; then
        install_prezto
        stow_packages+=("zsh")
    fi

    # Kitty Terminal
    if echo "$choices" | grep -q "Kitty Terminal"; then
        stow_packages+=("kitty")
    fi

    # Tmux + TPM
    if echo "$choices" | grep -q "Tmux + TPM"; then
        install_tpm
        stow_packages+=("tmux")
    fi

    # GrumpyVim
    if echo "$choices" | grep -q "GrumpyVim"; then
        install_grumpyvim
    fi

    # Awrit
    if echo "$choices" | grep -q "Awrit"; then
        install_awrit
        stow_packages+=("awrit")
    fi

    # vim-kitty-navigator
    if echo "$choices" | grep -q "vim-kitty-navigator"; then
        stow_packages+=("vim-kitty-navigator")
    fi

    # Yazi
    if echo "$choices" | grep -q "Yazi"; then
        stow_packages+=("yazi")
    fi

    # Linting
    if echo "$choices" | grep -q "Linting"; then
        install_npm_tools
        stow_packages+=("linting")
    fi

    # Git config (always stow if we have any selections)
    stow_packages+=("git")

    # Stow all selected packages
    if [[ ${#stow_packages[@]} -gt 0 ]]; then
        stow_dotfiles "${stow_packages[@]}"
    fi

    # Set Zsh as default
    if echo "$choices" | grep -q "Set Zsh as Default"; then
        set_zsh_default
    fi

    echo ""
    gum style \
        --foreground 212 \
        --border double \
        --padding "1 2" \
        "Installation complete!"

    echo ""
    info "Next steps:"
    echo "  1. Log out and log back in for shell changes to take effect"
    echo "  2. Run 'tmux' and press 'prefix + I' to install tmux plugins"
    echo "  3. Open nvim to let plugins install automatically"
    echo ""
}

# Run main
main "$@"
