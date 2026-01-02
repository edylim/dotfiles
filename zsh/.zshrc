# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

echo -ne "\e]0;🐈\a"

# Source PreztoV
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# yarn path
export PATH=$HOME/.yarn/bin:$PATH

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
export GREP_COLOR="00;38;5;61"
export GREP_COLORS="00;38;5;61"

# Dir colors (gdircolors on macOS via coreutils, dircolors on Linux)
if [[ -f ~/.dircolors ]]; then
  if command -v gdircolors &> /dev/null; then
    eval $(gdircolors ~/.dircolors)
  elif command -v dircolors &> /dev/null; then
    eval $(dircolors ~/.dircolors)
  fi
fi

# SCMPuff
if command -v scmpuff &> /dev/null; then
  eval "$(scmpuff init -s)"
fi

export MUSIC_APP="Spotify"

##################
# HISTORY SETTINGS
##################
setopt hist_ignore_all_dups inc_append_history
HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000

# Beep on errors and notify on background task completion
setopt beep nomatch notify

# Vim Bindings
bindkey -v
zstyle :compinstall filename '~/.zshrc'

# load our own completion functions
fpath=(~/.zsh/completion /usr/local/share/zsh/site-functions $fpath)

# Note: compinit is handled by Prezto's completion module

###################
# TERMINAL SETTINGS
###################

# Plugins
# plugins=(git zsh-autosuggestions web-search)

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
[[ -f ~/.aliases ]] && source ~/.aliases

# Local config
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# export NVM_DIR="~/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
# if command -v pyenv 1>/dev/null 2>&1; then
#   eval "$(pyenv init -)"
# fi

# asdf
export ASDF_DIR="$HOME/.asdf"
[[ -f "$HOME/.asdf/asdf.sh" ]] && . "$HOME/.asdf/asdf.sh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# macOS-specific settings
if [[ "$(uname)" == "Darwin" ]]; then
  export PATH="/usr/local/opt/openssl/bin:$PATH"
fi

# awrit
export PATH="$HOME/.local/bin:$PATH"

# zoxide
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# fzf - fuzzy finder (--zsh requires fzf 0.48.0+, fallback to sourcing script)
if command -v fzf &> /dev/null; then
  if fzf --zsh &> /dev/null; then
    source <(fzf --zsh)
  elif [[ -f ~/.fzf.zsh ]]; then
    source ~/.fzf.zsh
  elif [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
    [[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
  fi
fi

# Kitty ssh kitten - copies terminfo to remote hosts
[ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"

# onefetch
# git repository greeter
if command -v onefetch &> /dev/null; then
  last_repository=
  check_directory_for_new_repository() {
    current_repository=$(git rev-parse --show-toplevel 2> /dev/null)

    if [ "$current_repository" ] && \
       [ "$current_repository" != "$last_repository" ]; then
      onefetch
    fi
    last_repository=$current_repository
  }
  function cd {
    builtin cd "$@"
    check_directory_for_new_repository
  }
fi

# optional, greet also when opening shell directly in repository directory
# adds time to startup
#check_directory_for_new_repository
