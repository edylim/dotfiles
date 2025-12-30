# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

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

# Dir colors
eval $(gdircolors ~/.dircolors)

# SCMPuff
eval "$(scmpuff init -s)"

export MUSIC_APP="Spotify"

##################
# HISTORY SETTINGS
##################
setopt hist_ignore_all_dups inc_append_history
HISTFILE=~/.histfile
HISTSIZE=4096
SAVEHIST=4096

# Beep on errors and notify on background task completion
setopt beep nomatch notify

# Vim Bindings
bindkey -v
zstyle :compinstall filename '~/.zshrc'

# load our own completion functions
fpath=(~/.zsh/completion /usr/local/share/zsh/site-functions $fpath)

# completion
autoload -U compinit
compinit

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

# Remove aliases
unalias gls #git log conflicts with dircolors gls

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
export ASDF_DIR="/Users/ed/.asdf"
. "$HOME/.asdf/asdf.sh"#

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# macOS-specific settings
if [[ "$(uname)" == "Darwin" ]]; then
  export PATH="/usr/local/opt/openssl/bin:$PATH"
fi

# awrit
export PATH="/Users/ed/.local/bin:$PATH"

# zoxide
eval "$(zoxide init zsh)"

# onefetch
# git repository greeter
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

# optional, greet also when opening shell directly in repository directory
# adds time to startup
#check_directory_for_new_repository
