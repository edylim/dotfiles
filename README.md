# dotfiles

Personal dotfiles for setting up a new environment on macOS, Ubuntu/Debian, and Arch Linux.

## Installation

**One-liner** (clones to `~/.dotfiles` and runs installer):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/edylim/dotfiles/master/install.sh)"
```

**Or manually:**

```bash
git clone https://github.com/edylim/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

The installer presents an interactive menu with all options selected by default:

```
  Dotfiles Installer
  macos (arm64)

> [x] Core Packages (git, stow, curl, wget)
  [x] CLI Tools (zsh, fzf, bat, zoxide, yazi, htop, gh)
  [x] Git Tools (scmpuff, onefetch)
  [x] Media Tools (ffmpeg, imagemagick, poppler)
  [x] AI Tools (claude, gemini-cli)
  [x] Mise & Runtimes (Node.js, Python)
  ...

─────────────────────────────────────────────────────
  [space] toggle  [a]ll  [n]one  [i]nstall  [q]uit
```

**Controls:** Arrow keys or `j`/`k` to navigate, `space`/`enter` to toggle, `a` to select all, `n` to select none, `i` to install, `q` to quit.

### Headless Mode

For automation/CI, use `--yes` to skip the interactive menu and install everything:

```bash
./install.sh --yes
```

### Uninstalling

To remove all stowed dotfiles and optionally installed packages:

```bash
./uninstall.sh
```

## What's Included

### Core Packages
- **git** - Version control
- **stow** - Symlink farm manager for dotfiles
- **curl/wget** - File transfer utilities
- **coreutils** - GNU core utilities (macOS)
- **bash** - Updated Bash 5.x (macOS ships with 3.2)

### CLI Tools
- **zsh** - Shell (latest from Homebrew)
- **fzf** - Fuzzy finder
- **bat** - `cat` with syntax highlighting
- **htop** - Interactive process viewer
- **gh** - GitHub CLI
- **jq** - JSON processor
- **tree** - Directory listing
- **zoxide** - Smarter `cd` command
- **yazi** - Terminal file manager
- **mas** - Mac App Store CLI (macOS)

### Git Tools
- **scmpuff** - Numeric shortcuts for git
- **onefetch** - Git repo summary

### Media Tools
- **ffmpeg** - Video/audio processing
- **imagemagick** - Image manipulation
- **poppler** - PDF utilities
- **resvg** - SVG rendering
- **sevenzip** - Archive utility

### AI Tools
- **claude** - Claude Code CLI
- **gemini-cli** - Google Gemini CLI

### Development
- **mise** - Runtime version manager (Node.js, Python)
- **yarn** - Package manager

### Applications
- **Kitty** - GPU-accelerated terminal
- **GrumpyVim** - Neovim configuration (includes neovim, lazygit, ripgrep, fd)
- **Awrit** - Terminal browser
- **JankyBorders** - Window borders (macOS)
- **SketchyBar** - Custom menu bar (macOS)
- **Google Chrome**

### Shell Configuration
- **Prezto** - Zsh configuration framework
- **Powerlevel10k** - Zsh theme

## Directory Structure

```
dotfiles/
├── awrit/          # Awrit terminal browser config
├── bin/            # Custom scripts (~/.local/bin)
├── git/            # Git configuration
├── jankyborders/   # JankyBorders config (macOS)
├── kitty/          # Kitty terminal config
├── linting/        # ESLint & Prettier configs
├── mise/           # Mise runtime config
├── sketchybar/     # SketchyBar config (macOS)
├── yarn/           # Yarn configuration
├── zsh/            # Zsh configuration
└── install.sh      # Installation script
```

## Local Configuration

Private settings go in `.local` files (not tracked by git):

| File | Purpose |
|------|---------|
| `~/.gitconfig.local` | Git user name/email |
| `~/.zshrc.local` | Private shell config |

Example `~/.gitconfig.local`:
```ini
[user]
    name = Your Name
    email = your.email@example.com
```

## Linting Configs

Shared ESLint and Prettier configs are in `linting/`. They're automatically symlinked to `~` by stow. To use in a project:

```bash
# Configs are already at ~/.eslintrc.json, ~/.prettierrc.json, etc.
# Most tools will find them automatically via config lookup
```

## Platform Support

| Platform | Status |
|----------|--------|
| macOS (Apple Silicon) | Full support |
| macOS (Intel) | Full support |
| Ubuntu/Debian | Supported |
| Arch Linux | Supported |

## Related Projects

- [GrumpyVim](https://github.com/edylim/grumpyvim) - Neovim configuration (LazyVim-based)
