#!/bin/bash
# Common shell library for dotfiles scripts
# Source this file: source "$DOTFILES_DIR/lib/common.sh"
#
# shellcheck disable=SC2034  # Variables are used by calling scripts via namerefs
# shellcheck disable=SC2178  # Shellcheck doesn't understand namerefs properly

# Prevent double-sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return
_COMMON_SH_LOADED=1

# =============================================================================
# COLOR AND STYLE
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# =============================================================================
# LOCK FILE MANAGEMENT
# =============================================================================

# Use flock on Linux, mkdir-based lock on macOS (flock not available by default)
_acquire_lock() {
    local lock_file="$1"
    local lock_fd="${2:-200}"

    if command -v flock &> /dev/null; then
        # Linux: use flock
        eval "exec $lock_fd>\"$lock_file\""
        if ! flock -n "$lock_fd"; then
            return 1
        fi
        echo $$ >&"$lock_fd"
    else
        # macOS/BSD: use mkdir (atomic operation)
        local lock_dir="${lock_file}.d"
        if ! mkdir "$lock_dir" 2>/dev/null; then
            # Check if the lock is stale (process dead)
            local lock_pid
            lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Stale lock, remove and retry
                rm -rf "$lock_dir"
                if ! mkdir "$lock_dir" 2>/dev/null; then
                    return 1
                fi
            else
                return 1
            fi
        fi
        echo $$ > "$lock_dir/pid"
    fi
    return 0
}

_release_lock() {
    local lock_file="$1"
    local lock_fd="${2:-200}"

    if command -v flock &> /dev/null; then
        flock -u "$lock_fd" 2>/dev/null || true
        rm -f "$lock_file" 2>/dev/null || true
    else
        rm -rf "${lock_file}.d" 2>/dev/null || true
    fi
}

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Basic logging (no file logging)
_log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
_log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
_log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
_log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if running in a terminal
is_interactive() {
    [[ -t 0 && -t 1 ]]
}

# Check if command exists
cmd_exists() {
    command -v "$1" &> /dev/null
}

# Run command with timeout (portable across macOS and Linux)
run_with_timeout() {
    local timeout_secs="$1"
    shift

    if cmd_exists timeout; then
        timeout "$timeout_secs" "$@"
    elif cmd_exists gtimeout; then
        gtimeout "$timeout_secs" "$@"
    else
        "$@"
    fi
}

# Restore cursor visibility (call in trap)
restore_cursor() {
    tput cnorm 2>/dev/null || true
}

# =============================================================================
# OS DETECTION
# =============================================================================

# Detect OS and set global variables (bash 3.2 compatible - no namerefs)
# Sets: DETECTED_OS, DETECTED_ARCH, DETECTED_PKG_MANAGER
_detect_os() {
    DETECTED_ARCH="$(uname -m)"
    # Normalize architecture names
    case "$DETECTED_ARCH" in
        aarch64) DETECTED_ARCH="arm64" ;;
        x86_64|amd64) DETECTED_ARCH="x86_64" ;;
    esac

    if [[ "$(uname)" == "Darwin" ]]; then
        DETECTED_OS="macos"
        DETECTED_PKG_MANAGER="brew"
    elif [[ -f /etc/arch-release ]]; then
        DETECTED_OS="arch"
        DETECTED_PKG_MANAGER="pacman"
    elif [[ -f /etc/debian_version ]]; then
        DETECTED_OS="debian"
        DETECTED_PKG_MANAGER="apt"
    else
        DETECTED_OS="unknown"
        DETECTED_PKG_MANAGER=""
    fi
}

# =============================================================================
# STATE TRACKING
# =============================================================================

# Arrays for tracking (declare in calling script)
# declare -a INSTALLED_ITEMS=()
# declare -a FAILED_ITEMS=()
# declare -a SKIPPED_ITEMS=()

_track_success() {
    local -n items=$1
    local item="$2"
    items+=("$item")
}

_track_failure() {
    local -n items=$1
    local item="$2"
    local reason="${3:-unknown}"
    items+=("$item: $reason")
}

_track_skip() {
    local -n items=$1
    local item="$2"
    local reason="${3:-}"
    items+=("$item${reason:+: $reason}")
}

_print_summary() {
    local title="$1"
    local -n success_items=$2
    local -n failed_items=$3
    local -n skipped_items=$4

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                   ${title}                   ${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ ${#success_items[@]} -gt 0 ]]; then
        echo -e "${GREEN}Completed successfully:${NC}"
        for item in "${success_items[@]}"; do
            echo -e "  ${GREEN}✓${NC} $item"
        done
        echo ""
    fi

    if [[ ${#failed_items[@]} -gt 0 ]]; then
        echo -e "${RED}Failed:${NC}"
        for item in "${failed_items[@]}"; do
            echo -e "  ${RED}✗${NC} $item"
        done
        echo ""
    fi

    if [[ ${#skipped_items[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Skipped:${NC}"
        for item in "${skipped_items[@]}"; do
            echo -e "  ${DIM}-${NC} $item"
        done
        echo ""
    fi
}

# =============================================================================
# INTERACTIVE MENU SYSTEM
# =============================================================================

# Menu state (declare in calling script)
# declare -a MENU_ITEMS=()      # Display names
# declare -a MENU_SELECTED=()   # 0 or 1 for each item
# MENU_CURSOR=0

_menu_init() {
    local -n items=$1
    local -n selected=$2
    local default="${3:-1}"  # Default: all selected

    for i in "${!items[@]}"; do
        selected[i]=$default
    done
}

_menu_draw() {
    local start_row=$1
    local -n items=$2
    local -n selected=$3
    local cursor=$4
    local checkbox_color="${5:-$GREEN}"  # Color for selected checkbox

    tput cup "$start_row" 0

    for i in "${!items[@]}"; do
        local item="${items[$i]}"
        local is_selected="${selected[$i]}"

        tput el  # Clear line

        # Cursor indicator
        if [[ $i -eq $cursor ]]; then
            echo -en "${CYAN}>${NC} "
        else
            echo -n "  "
        fi

        # Checkbox
        if [[ $is_selected -eq 1 ]]; then
            echo -en "${checkbox_color}[x]${NC} "
        else
            echo -en "${DIM}[ ]${NC} "
        fi

        # Item text
        if [[ $i -eq $cursor ]]; then
            echo -e "${BOLD}${item}${NC}"
        else
            echo -e "${item}"
        fi
    done

    # Footer
    echo ""
    tput el
    echo -e "${DIM}─────────────────────────────────────────────────────${NC}"
    tput el
}

_menu_run() {
    local -n items=$1
    local -n selected=$2
    local -n cursor=$3
    local start_row="${4:-5}"
    local footer_text="${5:-[space] toggle  [a]ll  [n]one  [enter] confirm  [q]uit}"
    local checkbox_color="${6:-$GREEN}"

    local item_count=${#items[@]}

    # Hide cursor
    tput civis

    # Draw initial menu
    _menu_draw "$start_row" items selected "$cursor" "$checkbox_color"
    echo -e "  ${BOLD}${footer_text}${NC}"

    # Input loop
    while true; do
        IFS= read -rsn1 key

        case "$key" in
            # Arrow keys (escape sequences)
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A'|'[k') # Up
                        if [[ $cursor -gt 0 ]]; then
                            ((cursor--))
                        fi
                        ;;
                    '[B'|'[j') # Down
                        if [[ $cursor -lt $((item_count - 1)) ]]; then
                            ((cursor++))
                        fi
                        ;;
                esac
                ;;
            # Space - toggle
            ' ')
                if [[ ${selected[cursor]} -eq 1 ]]; then
                    selected[cursor]=0
                else
                    selected[cursor]=1
                fi
                ;;
            # Enter - confirm
            '')
                tput cnorm
                echo ""
                return 0
                ;;
            # Select all
            'a'|'A')
                for i in "${!items[@]}"; do
                    selected[i]=1
                done
                ;;
            # Select none
            'n'|'N')
                for i in "${!items[@]}"; do
                    selected[i]=0
                done
                ;;
            # Quit
            'q'|'Q')
                tput cnorm
                echo ""
                echo -e "${YELLOW}Cancelled.${NC}"
                return 1
                ;;
            # j/k vim navigation
            'j')
                if [[ $cursor -lt $((item_count - 1)) ]]; then
                    ((cursor++))
                fi
                ;;
            'k')
                if [[ $cursor -gt 0 ]]; then
                    ((cursor--))
                fi
                ;;
        esac

        _menu_draw "$start_row" items selected "$cursor" "$checkbox_color"
        echo -e "  ${BOLD}${footer_text}${NC}"
    done
}

# =============================================================================
# SUDO HANDLING
# =============================================================================

_check_sudo() {
    local -n can_sudo_ref=$1
    local headless="${2:-false}"

    can_sudo_ref=false
    if command -v sudo &> /dev/null; then
        if sudo -n true 2>/dev/null || [[ "$headless" != "true" ]]; then
            can_sudo_ref=true
        fi
    fi
}

_safe_sudo() {
    local can_sudo="$1"
    shift

    if [[ "$can_sudo" == "true" ]]; then
        sudo "$@"
    else
        _log_warn "Skipping (requires sudo): $*"
        return 1
    fi
}
