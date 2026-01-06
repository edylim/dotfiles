#!/bin/bash
# Common shell library for dotfiles scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"

# --- Color and Style ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# --- Logging Functions ---
# These output to appropriate streams and can be used by any script

_log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
_log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
_log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
_log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- Utility Functions ---

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

# --- Cleanup Helpers ---

# Restore cursor visibility (call in trap)
restore_cursor() {
    tput cnorm 2>/dev/null || true
}
