#
# Executes commands at login pre-zshrc.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

#
# Browser
#

if [[ "$OSTYPE" == darwin* ]]; then
  export BROWSER='open'
fi

export PAGER='less'

#
# Language
#

if [[ -z "$LANG" ]]; then
  export LANG='en_US.UTF-8'
fi

#
# Paths
#
# Go: check default GOPATH first ($HOME/go), then GOPATH env, then `go env` as fallback
# This avoids slow `go env` call (~100ms) for users with default setup
if [[ -d "$HOME/go/bin" ]]; then
  export PATH="$PATH:$HOME/go/bin"
elif [[ -n "$GOPATH" && -d "$GOPATH/bin" ]]; then
  export PATH="$PATH:$GOPATH/bin"
elif command -v go &>/dev/null; then
  # Fallback for custom GOPATH users who haven't set GOPATH env var
  _gopath="$(go env GOPATH 2>/dev/null)"
  [[ -n "$_gopath" && -d "$_gopath/bin" ]] && export PATH="$PATH:$_gopath/bin"
  unset _gopath
fi

# Ensure path arrays do not contain duplicates.
typeset -gU cdpath fpath mailpath path

#
# Less
#

# Set the default Less options.
# Mouse-wheel scrolling has been disabled by -X (disable screen clearing).
# Remove -X and -F (exit if the content fits on one screen) to enable it.
export LESS='-F -g -i -M -R -S -w -X -z-4'

# Set the Less input preprocessor.
# Try both `lesspipe` and `lesspipe.sh` as either might exist on a system.
if (( $#commands[(i)lesspipe(|.sh)] )); then
  export LESSOPEN="| /usr/bin/env $commands[(i)lesspipe(|.sh)] %s 2>&-"
fi

#
# Temporary Files
#

if [[ ! -d "$TMPDIR" ]]; then
  export TMPDIR="/tmp/$LOGNAME"
  mkdir -p -m 700 "$TMPDIR"
fi

TMPPREFIX="${TMPDIR%/}/zsh"

# Homebrew setup - detect ARM vs Intel Mac, skip on Linux
if [[ "$OSTYPE" == darwin* ]]; then
  if [[ -f /opt/homebrew/bin/brew ]]; then
    # Apple Silicon (ARM)
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    # Intel Mac
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
