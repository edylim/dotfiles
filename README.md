- [OS X Options](#sec-1)
  - [Hostname](#sec-1-1)
  - [File Dialogs](#sec-1-2)
  - [Mouse](#sec-1-3)
  - [Keyboard](#sec-1-4)
- [Software](#sec-2)
  - [iTerm2](#sec-2-1a)
  - [Xcode](#sec-2-1b)
  - [Homebrew](#sec-2-2)
  - [Git](#sec-2-3)
  - [Github](#sec-2-4)
    - [Generate ssh key](#sec-2-4-1)
    - [Spacemacs Github Integration](#sec-2-4-2)
  - [Dotfile Setup](#sec-2-5)
  - [ZSH Setup](#sec-2-6)
    - [Set Default Shell](#sec-2-6-1)
    - [Prezto](#sec-2-6-2)
    - [Setup Symlinks](#sec-2-6-3)
    - [Custom configurations](#sec-2-6-4)
    - [Restart your terminal](#sec-2-6-5)
  - [Ruby](#sec-2-7)
    - [Rbenv](#sec-2-7-1)
    - [Symlink](#sec-2-7-2)
    - [Linters](#sec-2-7-3)
    - [Restart your terminal here](#sec-2-7-4)
  - [Poewrline Fonts](#sec-2-8)
  - [Brew Bundle](#sec-2-9)
  - [Python](#sec-2-10)
  - [asdf](#sec-2-11)
  - [Node](#sec-2-12)
    - [Node Version Manager](#sec-2-12-1)
    - [Bower](#sec-2-12-2)
    - [React Generator](#sec-2-12-3)
    - [Yarn](#sec-2-12-4)
    - [Linters](#sec-2-12-5)
  - [Vim](#sec-2-13)
    - [Prerequiste](#sec-2-13-1)
    - [Symlinks](#sec-2-13-2)
    - [Plugin Installs](#sec-2-13-3)
  - [SpaceMacs](#sec-2-14)
    - [Markdown Support](#sec-2-14-1)
  - [Tmux](#sec-2-15)
    - [Install Plugins](#sec-2-15-1)
  - [Tig](#sec-2-16)
  - [Silver Searcher](#sec-2-17)
  - [Youtube-dl](#sec-2-18)
  - [Livestream](#sec-2-19)

# Optional OS X Options<a id="sec-1"></a>

## Hostname<a id="sec-1-1"></a>

Change Hostname:

```shell
sudo scutil --set HostName <hostname>
```

## File Dialogs<a id="sec-1-2"></a>

Set OSX Save dialog to always be expanded

```shell
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
```

## Mouse<a id="sec-1-3"></a>

Set mouse to a faster track speed Uncheck "Scroll direction: Natural"

## Keyboard<a id="sec-1-4"></a>

Set repeat speed fast Set repeat delay low

# Software<a id="sec-2"></a>

## iterm2<a id="sec-2-1a"></a>

[iTerm2](https://iterm2.com/)

## Xcode<a id="sec-2-1b"></a>

```shell
xcode-select --install
```

## Homebrew<a id="sec-2-2"></a>

[Brew](http://brew.sh/)
```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Git<a id="sec-2-3"></a>

```shell
brew install git
git config --global user.name <user_name>
git config --global user.email <user_name>@users.noreply.github.com
git config --global push.default simple
```

## Github<a id="sec-2-4"></a>

### Generate ssh key<a id="sec-2-4-1"></a>

```shell
ssh-keygen
```
Just press enter twice for default.
```shell
cat ~/.ssh/id_rsa.pub | pbcopy
```

Paste into github's ssh setting

### Spacemacs Github Integration<a id="sec-2-4-2"></a>

Grant access to repo and gist [Set Access Tokens](https://github.com/settings/tokens)

```shell
git config --global github.oauth-token <token>
```

## Dotfile Setup<a id="sec-2-5"></a>

```shell
export DOTFILE_DIR=~/projects/dotfiles # or wherever
git clone https://github.com/edylim/dotfiles $DOTFILE_DIR
```

## ZSH Setup<a id="sec-2-6"></a>

### Set Default Shell<a id="sec-2-6-1"></a>

```shell
echo "/usr/local/bin/zsh" | sudo tee -a /etc/shells
chsh -s $(which zsh)
```

### Prezto<a id="sec-2-6-2"></a>

[Prezto](https://github.com/sorin-ionescu/prezto.git)

```shell
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
```

### Setup Symlinks<a id="sec-2-6-3"></a>

```shell
ln -s $DOTFILE_DIR/zsh/zshrc.symlink ~/.zshrc
ln -s $DOTFILE_DIR/zsh/zshenv.symlink ~/.zshenv
ln -s $DOTFILE_DIR/zsh/zpreztorc.symlink ~/.zpreztorc
ln -s $DOTFILE_DIR/zsh/zprofile.symlink ~/.zprofile
ln -s $DOTFILE_DIR/zsh/dircolors.symlink ~/.dircolors
ln -s $DOTFILE_DIR/zsh/aliases.symlink ~/.aliases
```

### Custom configurations<a id="sec-2-6-4"></a>

edit ~/.zshenv and set your own DEV<sub>DIR</sub> and DOTFILE<sub>DIR</sub>

Install zplug, scmpuff and coreutils
```shell
brew install zplug
brew install scmpuff
brew install coreutils
```

Turn off group-writable permissions for compinit
```shell
chmod g-w /usr/local/share/zsh
chmod g-w /usr/local/share/zsh/site-functions
```

### Restart your terminal<a id="sec-2-6-5"></a>

## Ruby<a id="sec-2-7"></a>

### Rbenv<a id="sec-2-7-1"></a>

```shell
brew install ruby-build rbenv
rbenv install -l # find which is the latest ruby version
rbenv install 3.0.0
rbenv local 3.0.0
rbenv global 3.0.0
```

### Restart your terminal

```shell
gem install bundle
rbenv rehash
```

### Symlink<a id="sec-2-7-2"></a>

```shell
ln -s $DOTFILE_DIR/rails/pryrc.symlink ~/.pryrc
```

### Linters<a id="sec-2-7-3"></a>

```shell
gem install rufo ruby-lint rubocop scss_lint scss_lint_reporter_checkstyle
```

### Restart your terminal here<a id="sec-2-7-4"></a>

## Pwoerline Fonts<a id="sec-2-8"></a>

[Powerline Fonts Repo](https://github.com/powerline/fonts)
```shell
mkdir -p $DEV_DIR/powerline
git clone https://github.com/powerline/fonts.git $DEV_DIR/powerline
$DEV_DIR/powerline/install.sh
```

## Brew Bundle<a id="sec-2-9"></a>

Skip this next command if you want the rest of your setup to be annoying
```shell
brew bundle
```

## Python<a id="sec-2-10"></a>

```shell
mkdir -p $DOTFILE_DIR/.virtualenv
pyenv install --list # find latest python version
pyenv install 3.9.2
pyenv global 3.9.2
pyenv local 3.9.2
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python get-pip.py
```

## asdf<a id="sec-2-11"></a>

```shell
brew install asdf gpg
```
then 
```shell
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
```

## Node<a id="sec-2-12"></a>

```shell
asdf plugin-add nodejs
bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'
asdf list-all nodejs # Find latest version
asdf install nodejs <version>
asdf global nodejs <version>
asdf local nodejs <version>
asdf reshim nodejs # to be able to find npm
```

### Yarn<a id="sec-2-12-4"></a>

```shell
brew install yarn
```

### Linters<a id="sec-2-12-5"></a>

```shell
npm install -g tern js-beautify
npm install -g eslint babel-eslint

export PKG=eslint-config-airbnb;
npm info "$PKG@latest" peerDependencies --json | command sed 's/[\{\},]//g ; s/: /@/g' | xargs npm install -g "$PKG@latest"

ln -s $DOTFILE_DIR/eslint/eslintrc.symlink ~/.eslintrc

yarn global add prettier
```

## Vim<a id="sec-2-13"></a>

### Prerequiste<a id="sec-2-13-1"></a>

```shell
mkdir -p ~/.vim/autoload
```

### Symlinks<a id="sec-2-13-2"></a>

```shell
ln -s $DOTFILE_DIR/vim/snippets ~/.vim/
ln -s $DOTFILE_DIR/vim/functions ~/.vim/functions
ln -s $DOTFILE_DIR/vim/plugins ~/.vim/plugins
ln -s $DOTFILE_DIR/vim/vimrc.symlink ~/.vimrc
ln -s $DOTFILE_DIR/vim/ignore.vim.symlink ~/.vim/ignore.vim
ln -s $DOTFILE_DIR/ctags.symlink ~/.ctags
```

### Plugin Installs<a id="sec-2-13-3"></a>

Run vim :PlugInstall

## SpaceMacs<a id="sec-2-14"></a>

```shell
mkdir -p ~/.spacemacs.d
git clone https://github.com/syl20bnr/spacemacs ~/.emacs.d
ln -s $DOTFILE_DIR/spacemacs/init.el.symlink ~/.spacemacs.d/init.el
```

### Markdown Support<a id="sec-2-14-1"></a>

```shell
npm install -g vmd
```

## Tmux<a id="sec-2-15"></a>

```shell
mkdir -p ~/.tmux/plugins
ln -s $DOTFILE_DIR/tmux/tmux.conf.symlink ~/.tmux.conf
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### Install Plugins<a id="sec-2-15-1"></a>

run tmux, then ctrl-s shift-i

## Tig<a id="sec-2-16"></a>

```shell
ln -s $DOTFILE_DIR/tigrc.symlink ~/.tigrc
```

## Silver Searcher<a id="sec-2-17"></a>

```shell
ln -s $DOTFILE_DIR/agignore.symlink ~/.agignore
```

## Youtube-dl<a id="sec-2-18"></a>

```shell
mkdir -p ~/.config/youtube-dl
ln -s $DOTFILE_DIR/youtube-dl.conf.symlink ~/.config/youtube-dl/config
```

## Livestream<a id="sec-2-19"></a>

Configure Twitch Oauth

```shell
livestreamer --twitch-oauth-authenticate
```

Copy the access<sub>token</sub> in URL to ~/.livestreamerrc
