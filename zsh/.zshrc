# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Set terminal title (only in terminals that support emoji)
[[ "$TERM_PROGRAM" == @(kitty|iTerm*|Apple_Terminal|vscode) || "$TERM" == "xterm-kitty" ]] && echo -ne "\e]0;🐈\a"

# Source Prezto
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# PATH additions (with guards to prevent duplication)
[[ ":$PATH:" != *":$HOME/.yarn/bin:"* ]] && export PATH="$HOME/.yarn/bin:$PATH"
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

# no correction suggestions
unsetopt CORRECT

################
# THEME SETTINGS
################

# makes color constants available
autoload -U colors
colors

# enable colored output from ls, etc
export CLICOLOR=1
export GREP_COLORS="ms=00;38;5;61:mc=00;38;5;61:sl=:cx=:fn=35:ln=32:bn=32:se=36"

# Dir colors (gdircolors on macOS via coreutils, dircolors on Linux)
if [[ -f "$HOME/.dircolors" ]]; then
  if command -v gdircolors &> /dev/null; then
    eval "$(gdircolors "$HOME/.dircolors")"
  elif command -v dircolors &> /dev/null; then
    eval "$(dircolors "$HOME/.dircolors")"
  fi
fi

# SCMPuff
if command -v scmpuff &> /dev/null; then
  eval "$(scmpuff init -s)"
fi


##################
# HISTORY SETTINGS
##################
setopt hist_ignore_all_dups inc_append_history
HISTFILE="$HOME/.histfile"
HISTSIZE=10000
SAVEHIST=10000

# Beep on errors and notify on background task completion
setopt beep nomatch notify

# Vim Bindings
bindkey -v
zstyle :compinstall filename "$HOME/.zshrc"

# load our own completion functions
fpath=("$HOME/.zsh/completion" /usr/local/share/zsh/site-functions $fpath)

# Note: compinit is handled by Prezto's completion module

###################
# TERMINAL SETTINGS
###################

# Disable flow control
setopt NO_FLOW_CONTROL

# handy keybindings
bindkey "^A" beginning-of-line
bindkey "^E" end-of-line
bindkey "^K" kill-line
bindkey "^U" backward-kill-line
bindkey "^R" history-incremental-search-backward
bindkey "^P" history-search-backward
bindkey "^Y" accept-and-hold
bindkey "^N" insert-last-word
bindkey -s "^T" "^[Isudo ^[A" # "t" for "toughguy"

# Remove aliases (gls alias from git conflicts with coreutils gls)
unalias gls 2>/dev/null

# Load other program settings
# aliases
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"

# macOS-specific settings (OpenSSL path differs by architecture)
if [[ "$(uname)" == "Darwin" ]]; then
  if [[ -d "/opt/homebrew/opt/openssl/bin" ]]; then
    [[ ":$PATH:" != *":/opt/homebrew/opt/openssl/bin:"* ]] && export PATH="/opt/homebrew/opt/openssl/bin:$PATH"
  elif [[ -d "/usr/local/opt/openssl/bin" ]]; then
    [[ ":$PATH:" != *":/usr/local/opt/openssl/bin:"* ]] && export PATH="/usr/local/opt/openssl/bin:$PATH"
  fi
fi

# zoxide
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# fzf - fuzzy finder (--zsh requires fzf 0.48.0+, fallback to sourcing script)
if command -v fzf &> /dev/null; then
  # Try --zsh flag (fzf 0.48.0+), capture output to avoid running twice
  local _fzf_init
  if _fzf_init=$(fzf --zsh 2>/dev/null); then
    eval "$_fzf_init"
  elif [[ -f "$HOME/.fzf.zsh" ]]; then
    source "$HOME/.fzf.zsh"
  elif [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
    [[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
  fi
  unset _fzf_init
fi

# Kitty ssh kitten - copies terminfo to remote hosts
[ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"

# mise - runtime version manager (Node.js, Python, etc.)
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)"
fi

# onefetch - git repository greeter (opt-in, set ONEFETCH_ON_CD=1 to enable)
# This hooks cd to show repo info, which adds latency to every directory change
# Set ONEFETCH_TIMEOUT to control max wait time (default: 2 seconds)
if [[ -n "$ONEFETCH_ON_CD" ]] && command -v onefetch &> /dev/null; then
  _onefetch_last_repository=
  _onefetch_timeout="${ONEFETCH_TIMEOUT:-2}"

  _onefetch_check_repository() {
    local current_repository
    current_repository=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$current_repository" && "$current_repository" != "$_onefetch_last_repository" ]]; then
      # Run with timeout to prevent hanging
      if command -v timeout &> /dev/null; then
        timeout "$_onefetch_timeout" onefetch 2>/dev/null
      elif command -v gtimeout &> /dev/null; then
        gtimeout "$_onefetch_timeout" onefetch 2>/dev/null
      else
        onefetch 2>/dev/null
      fi
    fi
    _onefetch_last_repository=$current_repository
  }

  function cd {
    builtin cd "$@" && _onefetch_check_repository
  }

  # Convenience alias to cd without triggering onefetch (uses builtin directly)
  alias cds='builtin cd'
fi
