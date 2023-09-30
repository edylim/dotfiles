# Dotfiles (MacOS)

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

Set mouse to a faster track speed Uncheck "Scroll direction: Natural"

## Keyboard

Set repeat speed fast Set repeat delay low

# Software

## Xcode

```shell
xcode-select --install
```

## Dotfile Setup

```shell
export DOTFILE_DIR=~/dotfiles # Local dotfiles folder
git clone https://github.com/edylim/dotfiles $DOTFILE_DIR
```

## ZSH Setup

### Set Default Shell

```shell
echo "/usr/local/bin/zsh" | sudo tee -a /etc/shells
chsh -s $(which zsh)
```

### Prezto

[Prezto](https://github.com/sorin-ionescu/prezto.git) is a fork of oh-my-zsh

```shell
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
```

## Homebrew

[Brew](http://brew.sh/)

```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
cd $DOTFILE_DIR
brew bundle
```

### Setup Symlinks

```shell
ln -s $DOTFILE_DIR/zsh/zshrc.symlink ~/.zshrc
ln -s $DOTFILE_DIR/zsh/zpreztorc.symlink ~/.zpreztorc
ln -s $DOTFILE_DIR/zsh/zprofile.symlink ~/.zprofile
ln -s $DOTFILE_DIR/zsh/dircolors.symlink ~/.dircolors
ln -s $DOTFILE_DIR/zsh/aliases.symlink ~/.aliases
```

## Git

```shell
git config --global user.name <user_name>
git config --global user.email <user_name>@users.noreply.github.com
git config --global push.default simple
```

## Github

### Generate ssh key

```shell
ssh-keygen
```

Just press enter twice for default.

```shell
cat ~/.ssh/id_rsa.pub | pbcopy
```

Paste into github's ssh setting

### Spacemacs Github Integration

Grant access to repo and gist [Set Access Tokens](https://github.com/settings/tokens)

```shell
git config --global github.oauth-token <token>
```

### Custom configurations

edit ~/.zshenv and set your own DEV<sub>DIR</sub> and DOTFILE<sub>DIR</sub>

### Restart your terminal

```shell
gem install bundle
rbenv rehash
```

### Symlink

```shell
ln -s $DOTFILE_DIR/rails/pryrc.symlink ~/.pryrc
```

### Linters

```shell
gem install rufo ruby-lint rubocop scss_lint scss_lint_reporter_checkstyle
```

### Restart your terminal here

## Pwoerline Fonts

[Powerline Fonts Repo](https://github.com/powerline/fonts)

```shell
mkdir -p $DEV_DIR/powerline
git clone https://github.com/powerline/fonts.git $DEV_DIR/powerline
$DEV_DIR/powerline/install.sh
```

## Brew Bundle

Skip this next command if you want the rest of your setup to be annoying

```shell
brew bundle
```

## Python

```shell
mkdir -p $DOTFILE_DIR/.virtualenv
pyenv install --list # find latest python version
pyenv install 3.9.2
pyenv global 3.9.2
pyenv local 3.9.2
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python get-pip.py
```

## asdf

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

### Yarn

```shell
brew install yarn
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
