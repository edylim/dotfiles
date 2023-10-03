# MacOS settings

## Hostname

Change Hostname:

```shell
sudo scutil --set HostName <hostname>
```

## File Dialogs

Set OSX Save dialog to always be expanded

```shell
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
```

## Mouse

Set mouse to faster track speed

## Keyboard

Set repeat speed fast, repeat delay low

# Initial Software

## Xcode

```shell
xcode-select --install
```

## ZSH Setup

```shell
echo "/usr/local/bin/zsh" | sudo tee -a /etc/shells
chsh -s $(which zsh)
```

## Dotfile Setup

```shell
export DOTFILE_DIR=~/dotfiles # Local dotfiles folder
git clone https://github.com/edylim/dotfiles $DOTFILE_DIR
```

### Prezto

[Prezto](https://github.com/sorin-ionescu/prezto.git) is a fork of oh-my-zsh

```shell
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
```

### Homebrew

[Brew](http://brew.sh/)

```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
cd $DOTFILE_DIR && brew bundle
```

### Symlinks

```shell
ln -s $DOTFILE_DIR/zsh/zshrc.symlink ~/.zshrc
ln -s $DOTFILE_DIR/zsh/zpreztorc.symlink ~/.zpreztorc
ln -s $DOTFILE_DIR/zsh/zprofile.symlink ~/.zprofile
ln -s $DOTFILE_DIR/zsh/dircolors.symlink ~/.dircolors
ln -s $DOTFILE_DIR/zsh/aliases.symlink ~/.aliases
```

### Git

```shell
git config --global user.name <user_name>
git config --global user.email <user_name>@users.noreply.github.com
git config --global push.default simple
```

### Generate ssh key

```shell
ssh-keygen
```

Just press enter twice for default.

```shell
cat ~/.ssh/id_rsa.pub | pbcopy
```

Setup [Github](https://github.com) ssh

```shell
git config --global github.oauth-token <token>
```

### iTerm2

Change bg color to #1d2021

### Custom configurations

edit ~/.zshenv and set your own DEV<sub>DIR</sub> and DOTFILE<sub>DIR</sub>

### Restart your terminal

# asdf

```shell
brew install asdf gpg
```

then

```shell
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
```

## Node

```shell
asdf plugin-add nodejs
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
asdf list-all nodejs # Find latest version
asdf install nodejs <version>
asdf global nodejs <version>
asdf local nodejs <version>
asdf reshim nodejs # to be able to find npm
```

### Linters

```shell
npm install -g tern js-beautify
npm install -g eslint babel-eslint

export PKG=eslint-config-airbnb;
npm info "$PKG@latest" peerDependencies --json | command sed 's/[\{\},]//g ; s/: /@/g' | xargs npm install -g "$PKG@latest"

ln -s $DOTFILE_DIR/eslint/eslintrc.symlink ~/.eslintrc

yarn global add prettier
```

## Tmux

```shell
mkdir -p ~/.tmux/plugins
ln -s $DOTFILE_DIR/tmux/tmux.conf.symlink ~/.tmux.conf
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### Install Plugins

run tmux, then ctrl-s shift-i

## Youtube-dl

```shell
mkdir -p ~/.config/youtube-dl
ln -s $DOTFILE_DIR/youtube-dl.conf.symlink ~/.config/youtube-dl/config
```
