#!/bin/bash

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# Note: This script uses indexed arrays (bash 3.2+), not associative arrays
# macOS ships with bash 3.2, so we maintain compatibility

# --- Global Variables ---
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OS=""
DRY_RUN=false
HEADLESS=false
REMOVE_PACKAGES=false

# Stow packages managed by this dotfiles repo
STOW_PACKAGES=(
    "awrit"
    "bin"
    "git"
    "jankyborders"
    "kitty"
    "linting"
    "mise"
    "sketchybar"
    "yarn"
    "zsh"
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

# --- Logging ---
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# --- Cleanup and signal handling ---
cleanup() {
    tput cnorm 2>/dev/null || true  # Restore cursor
}
trap cleanup EXIT INT TERM

# --- OS Detection ---
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        OS="macos"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    else
        OS="unknown"
    fi
}

# --- Unstow Functions ---
unstow_package() {
    local pkg="$1"
    local pkg_dir="$DOTFILES_DIR/$pkg"

    if [[ ! -d "$pkg_dir" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would unstow: $pkg${NC}"
        return 0
    fi

    if stow -d "$DOTFILES_DIR" -t "$HOME" -D "$pkg" 2>/dev/null; then
        echo -e "  ${DIM}Unstowed: $pkg${NC}"
    else
        warn "Could not unstow $pkg (may not be stowed)"
    fi
}

unstow_all() {
    info "Removing stowed dotfiles..."

    if ! command -v stow &> /dev/null; then
        warn "GNU Stow not found. Cannot unstow packages."
        return 1
    fi

    for pkg in "${STOW_PACKAGES[@]}"; do
        unstow_package "$pkg"
    done

    success "Dotfiles unstowed."
}

# --- Remove Additional Components ---
remove_prezto() {
    local prezto_dir="${ZDOTDIR:-$HOME}/.zprezto"

    if [[ ! -d "$prezto_dir" ]]; then
        echo -e "  ${DIM}Prezto not installed${NC}"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would remove: $prezto_dir${NC}"
        return 0
    fi

    rm -rf "$prezto_dir"
    echo -e "  ${DIM}Removed: $prezto_dir${NC}"
}

remove_grumpyvim() {
    local nvim_dir="$HOME/.config/nvim"

    if [[ ! -d "$nvim_dir" ]]; then
        echo -e "  ${DIM}GrumpyVim not installed${NC}"
        return 0
    fi

    # Check if it's actually grumpyvim
    if [[ -d "$nvim_dir/.git" ]] && git -C "$nvim_dir" remote -v 2>/dev/null | grep -q "grumpyvim"; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${DIM}[dry-run] Would remove: $nvim_dir${NC}"
            return 0
        fi
        rm -rf "$nvim_dir"
        echo -e "  ${DIM}Removed: $nvim_dir${NC}"

        # Also clean nvim data
        rm -rf "$HOME/.local/share/nvim" 2>/dev/null || true
        rm -rf "$HOME/.local/state/nvim" 2>/dev/null || true
        rm -rf "$HOME/.cache/nvim" 2>/dev/null || true
    else
        echo -e "  ${DIM}Neovim config exists but is not GrumpyVim, skipping${NC}"
    fi
}

remove_awrit() {
    local awrit_dir="$HOME/.awrit"

    if [[ ! -d "$awrit_dir" ]]; then
        echo -e "  ${DIM}Awrit not installed${NC}"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would remove: $awrit_dir${NC}"
        return 0
    fi

    rm -rf "$awrit_dir"
    echo -e "  ${DIM}Removed: $awrit_dir${NC}"
}

remove_mise_data() {
    local mise_dir="$HOME/.local/share/mise"
    local mise_cache="$HOME/.cache/mise"

    if [[ ! -d "$mise_dir" && ! -d "$mise_cache" ]]; then
        echo -e "  ${DIM}Mise data not found${NC}"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        [[ -d "$mise_dir" ]] && echo -e "  ${DIM}[dry-run] Would remove: $mise_dir${NC}"
        [[ -d "$mise_cache" ]] && echo -e "  ${DIM}[dry-run] Would remove: $mise_cache${NC}"
        return 0
    fi

    rm -rf "$mise_dir" 2>/dev/null || true
    rm -rf "$mise_cache" 2>/dev/null || true
    echo -e "  ${DIM}Removed mise data directories${NC}"
}

restore_backups() {
    local backup_base="$HOME/.dotfiles-backup"

    if [[ ! -d "$backup_base" ]]; then
        echo -e "  ${DIM}No backups found${NC}"
        return 0
    fi

    info "Found backups in $backup_base"

    if [[ "$HEADLESS" == true ]]; then
        echo -e "  ${DIM}Skipping backup restoration in headless mode${NC}"
        return 0
    fi

    echo -n "Restore backed up files? [y/N]: "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        # Find most recent backup
        local latest_backup
        latest_backup=$(ls -td "$backup_base"/*/ 2>/dev/null | head -1)

        if [[ -n "$latest_backup" && -d "$latest_backup" ]]; then
            info "Restoring from: $latest_backup"
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would restore files from $latest_backup${NC}"
            else
                # Copy files back, preserving directory structure
                # Use process substitution to avoid subshell issues with while loop
                local restore_failed=false
                pushd "$latest_backup" > /dev/null
                while IFS= read -r -d '' file; do
                    local relative="${file#./}"
                    local dest="$HOME/$relative"
                    local dest_dir
                    dest_dir=$(dirname "$dest")
                    if ! mkdir -p "$dest_dir"; then
                        warn "Failed to create directory: $dest_dir"
                        restore_failed=true
                        continue
                    fi
                    if cp "$file" "$dest"; then
                        echo -e "  ${DIM}Restored: $relative${NC}"
                    else
                        warn "Failed to restore: $relative"
                        restore_failed=true
                    fi
                done < <(find . -type f -print0)
                popd > /dev/null

                if [[ "$restore_failed" == true ]]; then
                    warn "Some files could not be restored"
                fi
            fi
            success "Backups restored."
        else
            warn "No backup directories found."
        fi
    fi
}

# =============================================================================
# INTERACTIVE MENU SYSTEM
# =============================================================================

declare -a MENU_ITEMS=(
    "Unstow all dotfiles (remove symlinks)"
    "Remove Prezto (zsh framework)"
    "Remove GrumpyVim (neovim config)"
    "Remove Awrit"
    "Remove Mise data (runtimes)"
    "Restore backed up files"
)

declare -a MENU_FUNCS=(
    "unstow_all"
    "remove_prezto"
    "remove_grumpyvim"
    "remove_awrit"
    "remove_mise_data"
    "restore_backups"
)

declare -a MENU_SELECTED
MENU_CURSOR=0

init_menu() {
    # All selected by default except restore_backups
    for i in "${!MENU_ITEMS[@]}"; do
        if [[ "${MENU_FUNCS[$i]}" == "restore_backups" ]]; then
            MENU_SELECTED[$i]=0
        else
            MENU_SELECTED[$i]=1
        fi
    done
}

draw_menu() {
    local start_row=$1

    tput cup "$start_row" 0

    for i in "${!MENU_ITEMS[@]}"; do
        local item="${MENU_ITEMS[$i]}"
        local selected="${MENU_SELECTED[$i]}"

        tput el

        if [[ $i -eq $MENU_CURSOR ]]; then
            echo -en "${CYAN}>${NC} "
        else
            echo -n "  "
        fi

        if [[ $selected -eq 1 ]]; then
            echo -en "${RED}[x]${NC} "
        else
            echo -en "${DIM}[ ]${NC} "
        fi

        if [[ $i -eq $MENU_CURSOR ]]; then
            echo -e "${BOLD}${item}${NC}"
        else
            echo -e "${item}"
        fi
    done

    echo ""
    tput el
    echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
    tput el
    echo -e "  ${BOLD}[space]${NC} toggle  ${BOLD}[a]${NC}ll  ${BOLD}[n]${NC}one  ${BOLD}[u]${NC}ninstall  ${BOLD}[q]${NC}uit"
}

run_menu() {
    local start_row=5
    local item_count=${#MENU_ITEMS[@]}

    tput civis  # Hide cursor

    clear
    echo ""
    echo -e "  ${BOLD}${RED}Dotfiles Uninstaller${NC}"
    echo -e "  ${DIM}$OS ($(uname -m))${NC}"
    echo ""

    draw_menu $start_row

    while true; do
        IFS= read -rsn1 key

        case "$key" in
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A') # Up
                        if [[ $MENU_CURSOR -gt 0 ]]; then
                            ((MENU_CURSOR--))
                        fi
                        ;;
                    '[B') # Down
                        if [[ $MENU_CURSOR -lt $((item_count - 1)) ]]; then
                            ((MENU_CURSOR++))
                        fi
                        ;;
                esac
                ;;
            ' '|'')
                if [[ ${MENU_SELECTED[$MENU_CURSOR]} -eq 1 ]]; then
                    MENU_SELECTED[$MENU_CURSOR]=0
                else
                    MENU_SELECTED[$MENU_CURSOR]=1
                fi
                ;;
            'a'|'A')
                for i in "${!MENU_ITEMS[@]}"; do
                    MENU_SELECTED[$i]=1
                done
                ;;
            'n'|'N')
                for i in "${!MENU_ITEMS[@]}"; do
                    MENU_SELECTED[$i]=0
                done
                ;;
            'u'|'U')
                tput cnorm
                echo ""
                return 0
                ;;
            'q'|'Q')
                tput cnorm
                echo ""
                echo -e "${YELLOW}Cancelled.${NC}"
                exit 0
                ;;
            'j')
                if [[ $MENU_CURSOR -lt $((item_count - 1)) ]]; then
                    ((MENU_CURSOR++))
                fi
                ;;
            'k')
                if [[ $MENU_CURSOR -gt 0 ]]; then
                    ((MENU_CURSOR--))
                fi
                ;;
        esac

        draw_menu $start_row
    done
}

# =============================================================================
# MAIN UNINSTALL LOGIC
# =============================================================================

run_uninstall() {
    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}Starting dry-run (no changes will be made)...${NC}"
    else
        echo -e "${RED}Starting uninstall...${NC}"
    fi
    echo ""

    for i in "${!MENU_ITEMS[@]}"; do
        if [[ ${MENU_SELECTED[$i]} -eq 1 ]]; then
            "${MENU_FUNCS[$i]}"
        fi
    done

    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${GREEN}${BOLD}Dry-run complete. No changes were made.${NC}"
    else
        echo -e "${GREEN}${BOLD}Uninstall complete!${NC}"
        echo -e "${DIM}Note: Installed packages (brew, pacman, apt) were not removed.${NC}"
        echo -e "${DIM}The dotfiles repository itself remains at: $DOTFILES_DIR${NC}"
    fi
}

# =============================================================================
# CLI ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
Usage: uninstall.sh [OPTIONS]

Uninstall dotfiles and related components.

Options:
  -n, --dry-run     Show what would be removed without making changes
  -y, --yes         Run in headless mode (no interactive menu)
  -h, --help        Show this help message

Examples:
  ./uninstall.sh              # Interactive mode
  ./uninstall.sh --dry-run    # Preview what would be removed
  ./uninstall.sh --yes        # Uninstall everything without prompts

Note: This script does NOT remove packages installed via brew/pacman/apt.
To completely remove those, use your package manager directly.
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
    init_menu

    if [[ "$HEADLESS" == true ]]; then
        info "Running in headless mode - removing all selected components"
    else
        if [[ ! -t 0 ]]; then
            error "Not running in a terminal. Use --yes for non-interactive mode."
        fi

        echo ""
        echo -e "${YELLOW}${BOLD}WARNING:${NC} This will remove dotfiles symlinks and related components."
        echo -n "Continue? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi

        run_menu
    fi

    run_uninstall
}

main "$@"
