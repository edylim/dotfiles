#!/bin/bash

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# --- Bootstrap: Handle curl pipe installation ---
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/edylim/dotfiles/master/install.sh)"
DOTFILES_REPO="git@github.com:edylim/dotfiles.git"
DOTFILES_TARGET="$HOME/.dotfiles"

if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
    echo "Bootstrapping dotfiles installation..."
    if ! command -v git &> /dev/null; then
        echo "Error: git is required. Please install git first."
        exit 1
    fi
    if [[ -d "$DOTFILES_TARGET" ]]; then
        echo "Updating existing dotfiles..."
        git -C "$DOTFILES_TARGET" pull --rebase || true
    else
        echo "Cloning dotfiles to $DOTFILES_TARGET..."
        git clone "$DOTFILES_REPO" "$DOTFILES_TARGET"
    fi
    exec "$DOTFILES_TARGET/install.sh"
fi

# --- Global Variables ---
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OS=""
PKG_MANAGER=""

# --- Color and Style ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
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
        OS="arch"
        PKG_MANAGER="pacman"
    elif [[ -f /etc/debian_version ]]; then
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

# Install brew packages, skipping already installed
brew_install() {
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
                if [[ -f /opt/homebrew/bin/brew ]]; then
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
            sudo pacman -S --noconfirm --needed git stow curl wget
            ;;
        debian)
            sudo apt-get install -y git stow curl wget
            ;;
    esac
    success "Core packages installed."
}

install_cli_tools() {
    info "Installing CLI tools..."
    # Note: ripgrep, fd, lazygit installed by grumpyvim
    case "$OS" in
        macos)
            brew_install zsh fzf bat htop gh jq tree zoxide yazi mas
            ;;
        arch)
            sudo pacman -S --noconfirm --needed zsh fzf bat htop github-cli jq tree zoxide yazi
            ;;
        debian)
            sudo apt-get install -y zsh fzf bat htop gh jq tree
            if ! pkg_installed zoxide; then
                curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
            fi
            if ! pkg_installed yazi; then
                cargo install --locked yazi-fm yazi-cli 2>/dev/null || warn "yazi requires cargo. Install manually."
            fi
            ;;
    esac
    success "CLI tools installed."
}

install_ai_tools() {
    info "Installing AI CLI tools..."
    case "$OS" in
        macos)
            brew_install gemini-cli
            # Claude Code CLI
            if ! pkg_installed claude; then
                npm install -g @anthropic-ai/claude-code
            else
                echo -e "  ${DIM}claude already installed${NC}"
            fi
            ;;
        *)
            # Claude Code CLI (requires npm)
            if pkg_installed claude; then
                echo -e "  ${DIM}claude already installed${NC}"
            elif command -v npm &> /dev/null; then
                npm install -g @anthropic-ai/claude-code
            else
                warn "npm not found. Install Node.js first for Claude Code CLI."
            fi
            ;;
    esac
    success "AI tools installed."
}

install_git_tools() {
    info "Installing git tools..."
    case "$OS" in
        macos)
            brew_install scmpuff onefetch
            ;;
        arch)
            sudo pacman -S --noconfirm --needed onefetch
            # scmpuff may need AUR
            if pkg_installed yay; then
                yay -S --noconfirm scmpuff
            fi
            ;;
        debian)
            # scmpuff and onefetch need manual install
            warn "scmpuff/onefetch not in apt repos. Install manually if needed."
            ;;
    esac
    success "Git tools installed."
}

install_media_tools() {
    info "Installing media tools..."
    case "$OS" in
        macos)
            brew_install ffmpeg sevenzip poppler resvg imagemagick
            ;;
        arch)
            sudo pacman -S --noconfirm --needed ffmpeg p7zip poppler imagemagick
            ;;
        debian)
            sudo apt-get install -y ffmpeg p7zip-full poppler-utils imagemagick
            ;;
    esac
    success "Media tools installed."
}

install_mise() {
    info "Installing Mise (Runtime Manager)..."
    case "$OS" in
        macos)
            if ! pkg_installed mise; then
                brew install mise
            fi
            ;;
        arch)
            if ! pkg_installed mise; then
                sudo pacman -S --noconfirm --needed mise || curl https://mise.run | sh
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
    eval "$(mise activate bash)" 2>/dev/null || true
    success "Mise installed."
}

configure_mise_runtimes() {
    info "Configuring runtimes via Mise..."
    # Ensure mise config directory exists before any mise commands
    mkdir -p "$HOME/.config/mise"
    if ! command -v mise &> /dev/null; then
        if [[ -f "$HOME/.local/bin/mise" ]]; then
            export PATH="$HOME/.local/bin:$PATH"
        fi
        eval "$(mise activate bash)" 2>/dev/null || true
    fi
    mise use --global node@latest
    mise use --global python@latest
    success "Runtimes configured."
}

install_yarn() {
    info "Installing Yarn..."
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

install_kitty() {
    info "Installing Kitty terminal..."
    case "$OS" in
        macos)
            cask_install kitty font-symbols-only-nerd-font
            ;;
        arch)
            sudo pacman -S --noconfirm --needed kitty
            ;;
        debian)
            if ! pkg_installed kitty; then
                curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
            else
                echo -e "  ${DIM}kitty already installed${NC}"
            fi
            ;;
    esac
    success "Kitty installed."
}

install_chrome() {
    info "Installing Google Chrome..."
    case "$OS" in
        macos)
            cask_install google-chrome
            ;;
        debian)
            if ! pkg_installed google-chrome; then
                wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
                sudo dpkg -i /tmp/chrome.deb || sudo apt-get install -f -y
                rm /tmp/chrome.deb
            else
                echo -e "  ${DIM}google-chrome already installed${NC}"
            fi
            ;;
        arch)
            if pkg_installed google-chrome; then
                echo -e "  ${DIM}google-chrome already installed${NC}"
            elif pkg_installed yay; then
                yay -S --noconfirm google-chrome
            elif pkg_installed paru; then
                paru -S --noconfirm google-chrome
            else
                warn "AUR helper not found. Skipping Chrome."
            fi
            ;;
    esac
    success "Chrome installed."
}

install_jankyborders() {
    [[ "$OS" != "macos" ]] && return
    info "Installing JankyBorders..."
    if brew_installed borders; then
        echo -e "  ${DIM}borders already installed${NC}"
    else
        brew tap FelixKratz/formulae
        brew install borders
    fi
    success "JankyBorders installed."
}

install_sketchybar() {
    [[ "$OS" != "macos" ]] && return
    info "Installing SketchyBar..."
    if ! brew_installed sketchybar; then
        brew tap FelixKratz/formulae
        brew install sketchybar
    else
        echo -e "  ${DIM}sketchybar already installed${NC}"
    fi
    cask_install sf-symbols
    brew_install jq
    success "SketchyBar installed."
}

install_awrit() {
    info "Installing Awrit..."
    local AW_INSTALL_DIR="$HOME/.awrit"
    if [[ -f "$AW_INSTALL_DIR/awrit" ]]; then
        success "Awrit already installed."
    else
        curl -fsS https://chase.github.io/awrit/get | DOWNLOAD_TO="$AW_INSTALL_DIR" bash
        success "Awrit downloaded."
    fi
    if [[ -f "$AW_INSTALL_DIR/dist/kitty.css" && ! -L "$AW_INSTALL_DIR/dist/kitty.css" ]]; then
         rm "$AW_INSTALL_DIR/dist/kitty.css"
    fi
}

install_grumpyvim() {
    info "Installing GrumpyVim..."
    local NVIM_CONFIG_DIR="$HOME/.config/nvim"

    # Handle symlinks (including broken ones)
    if [[ -L "$NVIM_CONFIG_DIR" ]]; then
        local link_target
        link_target=$(readlink "$NVIM_CONFIG_DIR")
        if [[ -d "$link_target" ]] && [[ -d "$link_target/.git" ]] && git -C "$link_target" remote -v 2>/dev/null | grep -q "grumpyvim"; then
            info "GrumpyVim already linked."
            return
        else
            warn "Removing existing symlink at $NVIM_CONFIG_DIR..."
            rm "$NVIM_CONFIG_DIR"
        fi
    fi

    if [[ -d "$NVIM_CONFIG_DIR" ]]; then
        if [[ -d "$NVIM_CONFIG_DIR/.git" ]] && git -C "$NVIM_CONFIG_DIR" remote -v | grep -q "grumpyvim"; then
            info "GrumpyVim already cloned. Pulling latest..."
            git -C "$NVIM_CONFIG_DIR" pull --rebase || true
        else
            warn "Existing Neovim config found. Backing up..."
            mv "$NVIM_CONFIG_DIR" "$NVIM_CONFIG_DIR.bak.$(date +%F-%H%M%S)"
            git clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
        fi
    else
        git clone https://github.com/edylim/grumpyvim.git "$NVIM_CONFIG_DIR"
    fi

    if [[ -f "$NVIM_CONFIG_DIR/install.sh" ]]; then
        chmod +x "$NVIM_CONFIG_DIR/install.sh"
        bash "$NVIM_CONFIG_DIR/install.sh"
    fi
    success "GrumpyVim installed."
}

install_prezto() {
    info "Installing Prezto..."
    if [[ -d "${ZDOTDIR:-$HOME}/.zprezto" ]]; then
        success "Prezto already installed."
    else
        git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
        success "Prezto installed."
    fi
}

set_zsh_default() {
    info "Setting Zsh as default shell..."
    local ZSH_PATH
    ZSH_PATH=$(which zsh)
    if [[ "$SHELL" == "$ZSH_PATH" ]]; then
        success "Zsh is already the default shell."
        return
    fi
    if ! grep -q "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
    fi
    if chsh -s "$ZSH_PATH"; then
        success "Default shell changed to Zsh."
    else
        warn "Could not change default shell. Run manually: chsh -s $ZSH_PATH"
    fi
}

# --- Stow Dotfiles ---
stow_package() {
    local pkg="$1"
    info "Stowing $pkg..."
    cd "$DOTFILES_DIR"
    if [[ ! -d "$pkg" ]]; then
        warn "Package directory '$pkg' not found. Skipping."
        return
    fi

    # Check for conflicts with dry run
    local backup_dir="$HOME/.dotfiles-backup/$(date +%F-%H%M%S)"
    local conflicts
    conflicts=$(stow -t "$HOME" -n "$pkg" 2>&1 || true)

    # Handle "existing target" conflicts (real files)
    local existing_targets
    existing_targets=$(echo "$conflicts" | grep "existing target .* since" | sed -n 's/.*existing target \(.*\) since.*/\1/p' || true)

    # Handle "not owned by stow" conflicts (symlinks not created by stow)
    local not_owned
    not_owned=$(echo "$conflicts" | grep "not owned by stow" | sed -n 's/.*existing target is not owned by stow: \(.*\)/\1/p' || true)

    # Back up and remove conflicting files
    if [[ -n "$existing_targets" || -n "$not_owned" ]]; then
        mkdir -p "$backup_dir"

        for target in $existing_targets $not_owned; do
            [[ -z "$target" ]] && continue
            local full_path="$HOME/$target"

            if [[ -L "$full_path" ]]; then
                # It's a symlink - back up what it points to if it exists
                local link_target
                link_target=$(readlink "$full_path")
                if [[ -e "$link_target" ]]; then
                    echo -e "  ${DIM}Removing symlink $target (-> $link_target)${NC}"
                fi
                rm "$full_path"
            elif [[ -e "$full_path" ]]; then
                # It's a real file - back it up
                local target_dir
                target_dir=$(dirname "$backup_dir/$target")
                mkdir -p "$target_dir"
                mv "$full_path" "$backup_dir/$target"
                echo -e "  ${DIM}Backed up $target${NC}"
            fi
        done
    fi

    # -t $HOME ensures symlinks go to home directory, not parent of dotfiles dir
    stow -t "$HOME" -R "$pkg" 2>/dev/null || stow -t "$HOME" "$pkg"
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

# =============================================================================
# INTERACTIVE MENU SYSTEM
# =============================================================================

declare -a MENU_ITEMS
declare -a MENU_SELECTED
declare -a MENU_MACOS_ONLY
MENU_CURSOR=0

init_menu() {
    MENU_ITEMS=(
        "Core Packages (git, stow, curl, wget)"
        "CLI Tools (zsh, fzf, bat, zoxide, yazi, htop, gh)"
        "Git Tools (scmpuff, onefetch)"
        "Media Tools (ffmpeg, imagemagick, poppler)"
        "AI Tools (claude, gemini-cli)"
        "Mise & Runtimes (Node.js, Python)"
        "Yarn"
        "Kitty Terminal"
        "Google Chrome"
        "GrumpyVim (Neovim)"
        "Zsh & Prezto"
        "Awrit"
        "JankyBorders (macOS)"
        "SketchyBar (macOS)"
        "Linting Configs"
        "Bin Scripts"
        "Git Config"
    )

    # Track which items are macOS only (indices: 12=JankyBorders, 13=SketchyBar)
    MENU_MACOS_ONLY=(0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0)

    # All selected by default
    for i in "${!MENU_ITEMS[@]}"; do
        MENU_SELECTED[$i]=1
    done
}

draw_menu() {
    local start_row=$1
    local total=${#MENU_ITEMS[@]}

    # Move cursor to start position
    tput cup $start_row 0

    for i in "${!MENU_ITEMS[@]}"; do
        local item="${MENU_ITEMS[$i]}"
        local selected="${MENU_SELECTED[$i]}"
        local is_macos_only="${MENU_MACOS_ONLY[$i]}"

        # Skip macOS-only items on other platforms
        if [[ "$is_macos_only" -eq 1 && "$OS" != "macos" ]]; then
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
    for i in "${!MENU_ITEMS[@]}"; do
        local is_macos_only="${MENU_MACOS_ONLY[$i]}"
        if [[ "$is_macos_only" -eq 1 && "$OS" != "macos" ]]; then
            continue
        fi
        visible+=($i)
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
    echo -e "${CYAN}Starting installation...${NC}"
    echo ""

    # 0: Core Packages
    if [[ ${MENU_SELECTED[0]} -eq 1 ]]; then
        install_core_packages
    fi

    # 1: CLI Tools
    if [[ ${MENU_SELECTED[1]} -eq 1 ]]; then
        install_cli_tools
    fi

    # 2: Git Tools
    if [[ ${MENU_SELECTED[2]} -eq 1 ]]; then
        install_git_tools
    fi

    # 3: Media Tools
    if [[ ${MENU_SELECTED[3]} -eq 1 ]]; then
        install_media_tools
    fi

    # 4: AI Tools
    if [[ ${MENU_SELECTED[4]} -eq 1 ]]; then
        install_ai_tools
    fi

    # 5: Mise & Runtimes
    if [[ ${MENU_SELECTED[5]} -eq 1 ]]; then
        install_mise
        configure_mise_runtimes
        stow_pkgs+=("mise")
    fi

    # 6: Yarn
    if [[ ${MENU_SELECTED[6]} -eq 1 ]]; then
        install_yarn
        stow_pkgs+=("yarn")
    fi

    # 7: Kitty Terminal
    if [[ ${MENU_SELECTED[7]} -eq 1 ]]; then
        install_kitty
        stow_pkgs+=("kitty")
    fi

    # 8: Google Chrome
    if [[ ${MENU_SELECTED[8]} -eq 1 ]]; then
        install_chrome
    fi

    # 9: GrumpyVim
    if [[ ${MENU_SELECTED[9]} -eq 1 ]]; then
        install_grumpyvim
    fi

    # 10: Zsh & Prezto
    if [[ ${MENU_SELECTED[10]} -eq 1 ]]; then
        install_prezto
        set_zsh_default
        stow_pkgs+=("zsh")
    fi

    # 11: Awrit
    if [[ ${MENU_SELECTED[11]} -eq 1 ]]; then
        install_awrit
        stow_pkgs+=("awrit")
    fi

    # 12: JankyBorders (macOS)
    if [[ ${MENU_SELECTED[12]} -eq 1 && "$OS" == "macos" ]]; then
        install_jankyborders
        stow_pkgs+=("jankyborders")
    fi

    # 13: SketchyBar (macOS)
    if [[ ${MENU_SELECTED[13]} -eq 1 && "$OS" == "macos" ]]; then
        install_sketchybar
        stow_pkgs+=("sketchybar")
    fi

    # 14: Linting Configs
    if [[ ${MENU_SELECTED[14]} -eq 1 ]]; then
        stow_pkgs+=("linting")
    fi

    # 15: Bin Scripts
    if [[ ${MENU_SELECTED[15]} -eq 1 ]]; then
        stow_pkgs+=("bin")
    fi

    # 16: Git Config
    if [[ ${MENU_SELECTED[16]} -eq 1 ]]; then
        stow_pkgs+=("git")
    fi

    # Stow all selected packages
    if [[ ${#stow_pkgs[@]} -gt 0 ]]; then
        stow_dotfiles "${stow_pkgs[@]}"
    fi

    # Trust mise config files after stowing
    if [[ ${MENU_SELECTED[5]} -eq 1 ]] && command -v mise &> /dev/null; then
        info "Trusting mise config files..."
        mise trust "$HOME/.config/mise/config.toml" 2>/dev/null || true
        mise trust "$HOME/.tool-versions" 2>/dev/null || true
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Installation complete!${NC}"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    detect_os
    setup_package_manager
    init_menu
    run_menu
    run_installation
}

main "$@"
