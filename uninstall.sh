#!/bin/bash
# shellcheck disable=SC2034  # Some variables are set for state tracking
# shellcheck source=lib/common.sh

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# Note: This script uses indexed arrays (bash 3.2+), not associative arrays
# macOS ships with bash 3.2, so we maintain compatibility

# --- Global Variables ---
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source common library
source "$DOTFILES_DIR/lib/common.sh"

# Script-specific variables
OS=""
ARCH=""
PKG_MANAGER=""
DRY_RUN=false
HEADLESS=false

# Lock file
LOCK_FILE="/tmp/dotfiles-uninstall.lock"

# State tracking
STATE_FILE="${DOTFILES_DIR}/.uninstall-state"
declare -a REMOVED_ITEMS=()
declare -a FAILED_ITEMS=()
declare -a SKIPPED_ITEMS=()

# XDG directories
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

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

# --- Logging (with file logging) ---
LOG_FILE="${DOTFILES_DIR}/uninstall.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

info()    { echo -e "${BLUE}[INFO]${NC} $1"; log "INFO: $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; log "OK: $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; log "WARN: $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; log "ERROR: $1"; exit 1; }

# --- State Tracking ---
track_success() {
    local item="$1"
    REMOVED_ITEMS+=("$item")
    log "REMOVED: $item"
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

save_state() {
    {
        echo "# Dotfiles uninstall state - $(date)"
        echo "# This file is for reference only"
        echo ""
        echo "REMOVED=(${REMOVED_ITEMS[*]:-})"
        echo "FAILED=(${FAILED_ITEMS[*]:-})"
        echo "SKIPPED=(${SKIPPED_ITEMS[*]:-})"
    } > "$STATE_FILE"
}

# --- Lock Management ---
acquire_lock() {
    if ! _acquire_lock "$LOCK_FILE"; then
        error "Another instance of uninstall.sh is already running (lock: $LOCK_FILE)"
    fi
}

release_lock() {
    _release_lock "$LOCK_FILE"
}

# --- Cleanup and signal handling ---
cleanup() {
    local exit_code=$?
    restore_cursor
    release_lock
    save_state

    if [[ $exit_code -ne 0 ]] && [[ ${#REMOVED_ITEMS[@]} -gt 0 ]]; then
        echo ""
        warn "Uninstall was interrupted. Successfully removed:"
        for item in "${REMOVED_ITEMS[@]}"; do
            echo "  - $item"
        done
        echo ""
        echo "State saved to: $STATE_FILE"
    fi
}
trap cleanup EXIT INT TERM

# --- OS Detection ---
detect_os() {
    _detect_os
    OS="$DETECTED_OS"
    ARCH="$DETECTED_ARCH"
    PKG_MANAGER="$DETECTED_PKG_MANAGER"
    if [[ "$OS" == "unknown" ]]; then
        warn "Unknown OS detected. Some features may not work correctly."
    fi
}

# =============================================================================
# UNINSTALL FUNCTIONS
# =============================================================================

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
        return 0
    else
        warn "Could not unstow $pkg (may not be stowed)"
        return 1
    fi
}

unstow_all() {
    info "Removing stowed dotfiles..."

    if ! command -v stow &> /dev/null; then
        track_failure "Unstow dotfiles" "GNU Stow not found"
        warn "GNU Stow not found. Cannot unstow packages."
        return 1
    fi

    local failed=false
    for pkg in "${STOW_PACKAGES[@]}"; do
        if ! unstow_package "$pkg"; then
            failed=true
        fi
    done

    if [[ "$failed" == true ]]; then
        track_failure "Unstow dotfiles" "some packages failed"
        return 1
    fi

    track_success "Unstow dotfiles"
    success "Dotfiles unstowed."
}

remove_prezto() {
    local prezto_dir="${ZDOTDIR:-$HOME}/.zprezto"

    if [[ ! -d "$prezto_dir" ]]; then
        echo -e "  ${DIM}Prezto not installed${NC}"
        track_skip "Prezto" "not installed"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would remove: $prezto_dir${NC}"
        return 0
    fi

    info "Removing Prezto..."
    if rm -rf "$prezto_dir"; then
        track_success "Prezto"
        success "Prezto removed."
    else
        track_failure "Prezto" "rm failed"
        return 1
    fi
}

remove_grumpyvim() {
    local nvim_dir="$XDG_CONFIG_HOME/nvim"

    if [[ ! -d "$nvim_dir" ]] && [[ ! -L "$nvim_dir" ]]; then
        echo -e "  ${DIM}GrumpyVim not installed${NC}"
        track_skip "GrumpyVim" "not installed"
        return 0
    fi

    # Handle symlinks
    if [[ -L "$nvim_dir" ]]; then
        local link_target
        link_target=$(readlink "$nvim_dir" 2>/dev/null || echo "")
        if [[ -n "$link_target" ]] && [[ -d "$link_target/.git" ]] && git -C "$link_target" remote -v 2>/dev/null | grep -q "grumpyvim"; then
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${DIM}[dry-run] Would remove symlink: $nvim_dir${NC}"
                echo -e "  ${DIM}[dry-run] Would remove: $link_target${NC}"
                return 0
            fi
            info "Removing GrumpyVim (symlinked)..."
            rm "$nvim_dir"
            rm -rf "$link_target"
        else
            track_skip "GrumpyVim" "symlink doesn't point to GrumpyVim"
            echo -e "  ${DIM}Neovim config is symlinked but not to GrumpyVim, skipping${NC}"
            return 0
        fi
    # Handle direct installation
    elif [[ -d "$nvim_dir/.git" ]] && git -C "$nvim_dir" remote -v 2>/dev/null | grep -q "grumpyvim"; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${DIM}[dry-run] Would remove: $nvim_dir${NC}"
            return 0
        fi
        info "Removing GrumpyVim..."
        rm -rf "$nvim_dir"
    else
        track_skip "GrumpyVim" "nvim config exists but is not GrumpyVim"
        echo -e "  ${DIM}Neovim config exists but is not GrumpyVim, skipping${NC}"
        return 0
    fi

    # Clean nvim data directories
    if [[ "$DRY_RUN" != true ]]; then
        rm -rf "$XDG_DATA_HOME/nvim" 2>/dev/null || true
        rm -rf "$HOME/.local/state/nvim" 2>/dev/null || true
        rm -rf "$XDG_CACHE_HOME/nvim" 2>/dev/null || true
    fi

    track_success "GrumpyVim"
    success "GrumpyVim removed."
}

remove_awrit() {
    local awrit_dir="$HOME/.awrit"

    if [[ ! -d "$awrit_dir" ]]; then
        echo -e "  ${DIM}Awrit not installed${NC}"
        track_skip "Awrit" "not installed"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would remove: $awrit_dir${NC}"
        return 0
    fi

    info "Removing Awrit..."
    if rm -rf "$awrit_dir"; then
        track_success "Awrit"
        success "Awrit removed."
    else
        track_failure "Awrit" "rm failed"
        return 1
    fi
}

remove_mise_data() {
    local mise_data="$XDG_DATA_HOME/mise"
    local mise_cache="$XDG_CACHE_HOME/mise"
    # Note: mise_config is managed by stow, don't remove it here

    if [[ ! -d "$mise_data" && ! -d "$mise_cache" ]]; then
        echo -e "  ${DIM}Mise data not found${NC}"
        track_skip "Mise data" "not found"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        [[ -d "$mise_data" ]] && echo -e "  ${DIM}[dry-run] Would remove: $mise_data${NC}"
        [[ -d "$mise_cache" ]] && echo -e "  ${DIM}[dry-run] Would remove: $mise_cache${NC}"
        return 0
    fi

    info "Removing Mise data..."
    rm -rf "$mise_data" 2>/dev/null || true
    rm -rf "$mise_cache" 2>/dev/null || true
    # Note: Don't remove mise_config as it's managed by stow

    track_success "Mise data"
    success "Mise data removed."
}

restore_backups() {
    local backup_base="$HOME/.dotfiles-backup"

    if [[ ! -d "$backup_base" ]]; then
        echo -e "  ${DIM}No backups found${NC}"
        track_skip "Restore backups" "no backups found"
        return 0
    fi

    # Find backups
    local -a backups=()
    while IFS= read -r -d '' dir; do
        backups+=("$dir")
    done < <(find "$backup_base" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "  ${DIM}No backup directories found${NC}"
        track_skip "Restore backups" "no backup directories"
        return 0
    fi

    info "Found ${#backups[@]} backup(s) in $backup_base"

    if [[ "$HEADLESS" == true ]]; then
        echo -e "  ${DIM}Skipping backup restoration in headless mode${NC}"
        track_skip "Restore backups" "headless mode"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would prompt for backup restoration${NC}"
        return 0
    fi

    # Show available backups
    echo ""
    echo "Available backups:"
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local backup_name
        backup_name=$(basename "$backup")
        local file_count
        file_count=$(find "$backup" -type f | wc -l | tr -d ' ')
        echo "  $((i+1)). $backup_name ($file_count files)"
    done
    echo ""

    echo -n "Restore from backup? Enter number (1-${#backups[@]}) or 'n' to skip: "
    read -r response

    if [[ "$response" =~ ^[0-9]+$ ]] && [[ "$response" -ge 1 ]] && [[ "$response" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((response-1))]}"
        info "Restoring from: $selected_backup"

        local restore_failed=false
        pushd "$selected_backup" > /dev/null
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

            # Preserve permissions during restore
            if cp -p "$file" "$dest"; then
                echo -e "  ${DIM}Restored: $relative${NC}"
            else
                warn "Failed to restore: $relative"
                restore_failed=true
            fi
        done < <(find . -type f -print0)
        popd > /dev/null

        if [[ "$restore_failed" == true ]]; then
            track_failure "Restore backups" "some files failed"
            warn "Some files could not be restored"
            return 1
        fi

        track_success "Restore backups"
        success "Backups restored from $selected_backup"
    else
        echo -e "  ${DIM}Skipped backup restoration${NC}"
        track_skip "Restore backups" "user declined"
    fi
}

clean_backups() {
    local backup_base="$HOME/.dotfiles-backup"

    if [[ ! -d "$backup_base" ]]; then
        echo -e "  ${DIM}No backups to clean${NC}"
        track_skip "Clean backups" "no backups found"
        return 0
    fi

    local backup_size
    backup_size=$(du -sh "$backup_base" 2>/dev/null | cut -f1 || echo "unknown")

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run] Would remove: $backup_base ($backup_size)${NC}"
        return 0
    fi

    info "Removing backup directory ($backup_size)..."
    if rm -rf "$backup_base"; then
        track_success "Clean backups"
        success "Backups cleaned."
    else
        track_failure "Clean backups" "rm failed"
        return 1
    fi
}

# =============================================================================
# MENU SYSTEM
# =============================================================================

declare -a MENU_ITEMS=(
    "Unstow all dotfiles (remove symlinks)"
    "Remove Prezto (zsh framework)"
    "Remove GrumpyVim (neovim config + data)"
    "Remove Awrit"
    "Remove Mise data (runtimes, cache)"
    "Restore backed up files"
    "Clean up backup directory"
)

declare -a MENU_FUNCS=(
    "unstow_all"
    "remove_prezto"
    "remove_grumpyvim"
    "remove_awrit"
    "remove_mise_data"
    "restore_backups"
    "clean_backups"
)

declare -a MENU_SELECTED=()
MENU_CURSOR=0

init_menu() {
    # All selected by default except restore_backups and clean_backups
    for i in "${!MENU_ITEMS[@]}"; do
        case "${MENU_FUNCS[i]}" in
            restore_backups|clean_backups)
                MENU_SELECTED[i]=0
                ;;
            *)
                MENU_SELECTED[i]=1
                ;;
        esac
    done
}

run_menu() {
    local start_row=6

    # Hide cursor
    tput civis

    # Clear screen and draw header
    clear
    echo ""
    echo -e "  ${BOLD}${RED}Dotfiles Uninstaller${NC}"
    echo -e "  ${DIM}$OS ($(uname -m))${NC}"
    echo ""
    echo -e "  ${YELLOW}WARNING: This will remove dotfiles and related components.${NC}"

    if ! _menu_run MENU_ITEMS MENU_SELECTED MENU_CURSOR "$start_row" \
        "[space] toggle  [a]ll  [n]one  [enter] uninstall  [q]uit" "$RED"; then
        exit 0
    fi
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
    log "Uninstall started (dry_run=$DRY_RUN)"
    echo ""

    for i in "${!MENU_ITEMS[@]}"; do
        if [[ ${MENU_SELECTED[$i]} -eq 1 ]]; then
            "${MENU_FUNCS[$i]}" || true  # Continue on failure, we track it
        fi
    done

    # Print summary
    _print_summary "UNINSTALL SUMMARY" REMOVED_ITEMS FAILED_ITEMS SKIPPED_ITEMS

    log "Uninstall complete"
    if [[ ${#FAILED_ITEMS[@]} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}Uninstall complete!${NC}"
    else
        echo -e "${YELLOW}${BOLD}Uninstall complete with some failures.${NC}"
        echo -e "${DIM}Check the log for details: $LOG_FILE${NC}"
    fi

    echo -e "${DIM}Note: Installed packages (brew, pacman, apt) were not removed.${NC}"
    echo -e "${DIM}The dotfiles repository itself remains at: $DOTFILES_DIR${NC}"
    echo -e "${DIM}State file: $STATE_FILE${NC}"
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

    # Acquire lock before doing anything
    acquire_lock

    detect_os
    init_menu

    if [[ "$HEADLESS" == true ]]; then
        info "Running in headless mode - removing all selected components"
    else
        if [[ ! -t 0 ]]; then
            error "Not running in a terminal. Use --yes for non-interactive mode."
        fi

        # Initial confirmation
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
