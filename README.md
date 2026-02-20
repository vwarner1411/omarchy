# Omarchy (warnerva fork)

This repository tracks a customized Omarchy fork used for a Windows + Omarchy dual-boot workstation with opinionated developer defaults.

Upstream Omarchy info: [omarchy.org](https://omarchy.org)

## What Changed In This Fork

- Online install/update defaults target this fork (`warnerva/omarchy`) instead of upstream.
- Added `omarchy-setup-dualboot` for resilient Limine dual-boot setup.
- Added `omarchy-setup-skel` to build a sanitized `/etc/skel` from an existing user.
- Added `omarchy-setup-sync-upstream` for controlled upstream merge syncs.
- Added `inplace-luks-limine-windows-runbook.md` for optional in-place LUKS conversion planning.

## Repo Defaults

- `OMARCHY_REPO` default: `warnerva/omarchy`
- `OMARCHY_REF` default: `master`

You can override at runtime:

```bash
export OMARCHY_REPO=basecamp/omarchy
export OMARCHY_REF=master
```

## Key Commands Added

### 1) Dual boot setup (Limine)

Command: `omarchy-setup-dualboot`

Goal:
- Keep a flat Limine menu with exactly:
  - `/Omarchy`
  - `/Windows 11`
- Preserve the working Omarchy boot style/cmdline.
- Back up existing boot config before any changes.

Usage:

```bash
sudo omarchy-setup-dualboot
```

Optional targeting:

```bash
sudo omarchy-setup-dualboot --windows-esp /dev/nvme0n1p1
sudo omarchy-setup-dualboot --windows-partuuid <windows-esp-partuuid>
```

Backups are stored under `/boot/backup-limine-<timestamp>/`.

### 2) Build `/etc/skel` from your current user

Command: `omarchy-setup-skel`

Goal:
- Clone your user customization into `/etc/skel`.
- Remove symlinks (all files are copied as regular files).
- Strip private/auth/session data.
- Remove direct `/home/<user>` references from text configs.

Typical workflow:

```bash
sudo ./bin/omarchy-setup-skel --source-user warnerva --dry-run
sudo ./bin/omarchy-setup-skel --source-user warnerva
```

By default this includes:
- shell/editor config (`.zshrc`, `.nvimrc`, etc.)
- `.config`
- `.oh-my-zsh`
- `.local/share/nvim`
- `.local/share/mise` (toolchains/runtimes)
- Omarchy/fonts/desktop launcher/icon data

If you want to skip copying `mise` runtimes:

```bash
sudo ./bin/omarchy-setup-skel --source-user warnerva --skip-mise
```

After updating `/etc/skel`, recreate users that should inherit the new baseline.

### 3) Optional in-place LUKS plan

See:
- `inplace-luks-limine-windows-runbook.md`

This document is a runbook for planning in-place encryption of Linux root while keeping Windows partitions untouched. It includes explicit backup and rollback steps.

### 4) Sync upstream into your fork safely

Command: `omarchy-setup-sync-upstream`

Goal:
- Pull latest changes from `basecamp/omarchy`.
- Maintain a local tracking branch for upstream (`upstream-master` by default).
- Merge upstream changes into your custom branch using normal git merge semantics.
- Preserve local commits and force conflict resolution where both sides changed the same lines.

Default behavior:
- upstream remote name: `upstream`
- upstream URL: `https://github.com/basecamp/omarchy.git`
- upstream branch: `master`
- tracking branch: `upstream-master`
- target branch: current branch
- pushes `upstream-master` and merged target branch to `origin`
- refuses to run if tracked files are dirty (staged/unstaged)
- ignores untracked files (for example `.nvimlog`) and prints a warning

Usage:

```bash
omarchy-setup-sync-upstream
```

Common variants:

```bash
omarchy-setup-sync-upstream --target-branch dev
omarchy-setup-sync-upstream --no-push
```

If a conflict occurs, the command exits and leaves your repo in normal merge-conflict state so you can resolve intentionally.

## Suggested Validation After Changes

Dual boot:

```bash
grep -E '^/' /boot/limine.conf
```

Skel integrity:

```bash
sudo find /etc/skel -type l
sudo grep -RIl --fixed-strings "/home/warnerva" /etc/skel || true
```

## Workstation Baseline Notes

Current workstation defaults this fork is tracking:

- Shell: `zsh` with `oh-my-zsh`
- Zsh plugin chain: `git`, `autoupdate`, `zsh-syntax-highlighting`, `zsh-autosuggestions`, `zsh-completions`
- Terminal direction: Ghostty-first (with Omarchy theme integration)
- Prompt: `starship`
- CLI preferences: `lsd`, `tealdeer`, `yazi`
- Networking/input tools expected on system: `tailscale`, `keyd`
- Optional cross-platform shell support: `powershell` (`pwsh`)

Most of these are carried into new users through the `omarchy-setup-skel` flow.

## Local Customization Scripts

These workstation-local scripts drive the non-upstream behavior:

- `~/.local/bin/omarchy-local-root-apply`
- `~/.local/bin/omarchy-local-apply`

### Package Delta (vs upstream baseline)

Removed by local root apply:

- `tldr`
- `eza`
- `alacritty`

Added by local root apply (pacman):

- `ansible`
- `aria2`
- `base-devel`
- `btop`
- `bzip2`
- `ca-certificates`
- `coreutils`
- `curl`
- `fastfetch`
- `fontconfig`
- `fzf`
- `git`
- `ghostty`
- `gnupg`
- `iftop`
- `iotop`
- `jq`
- `keyd`
- `kitty`
- `lsd`
- `lynx`
- `mosh`
- `ncdu`
- `ncurses`
- `neovim`
- `nfs-utils`
- `openssh`
- `plocate`
- `python`
- `python-pip`
- `python-pipx`
- `python-virtualenv`
- `ripgrep`
- `rsync`
- `starship`
- `sysstat`
- `tailscale`
- `tar`
- `tealdeer`
- `tree`
- `unzip`
- `wget`
- `xz`
- `yazi`
- `yt-dlp`
- `zip`
- `zsh`

Added by local root apply (AUR, when `yay` is available):

- `powershell-bin`

### Configuration Delta (vs upstream baseline)

From `omarchy-local-root-apply`:

- Enables and starts `tailscaled.service`.
- Enables and starts `keyd.service`.
- Installs `/etc/keyd/default.conf` with `capslock = esc`.
- Sets default user shell to `/usr/bin/zsh` (if needed).

From `omarchy-local-apply`:

- Copies user overrides into:
  - `~/.zshrc`
  - `~/.config/ghostty/config`
  - `~/.config/starship.toml`
  - `~/.config/lsd/config.yaml`
  - `~/.config/lsd/colors.yaml`
  - `~/.nvimrc`
- Ensures `oh-my-zsh` and plugin chain are installed:
  - `autoupdate`
  - `zsh-autosuggestions`
  - `zsh-completions`
  - `zsh-syntax-highlighting`
- Applies shell behavior/aliases that differ from upstream:
  - `ls` family aliases routed to `lsd`
  - `tldr` alias routed to `tealdeer`
  - `yz` alias for `yazi`
  - `powershell` alias for `pwsh`
  - `omarchski`/`aptski` alias to `omarchy-update`
- Applies Ghostty override settings:
  - font family `Hack Nerd Font Mono`
  - reduced scroll multiplier
  - split navigation/resize keybinds
  - async backend set to `epoll`
- Applies local Neovim compatibility layer in `~/.nvimrc`:
  - loads LazyVim base from `~/.config/nvim/init.lua`
  - enforces two-space indentation defaults
  - prefers `tokyonight-night` colorscheme

### Desktop + Screensaver Branding Delta

Current local branding/theme state captured into user config and inherited through `omarchy-setup-skel`:

- Theme name: `tokyo-night`
- Desktop background: `~/.config/omarchy/backgrounds/tokyo-night/0-grudark-1.png`
- Terminal font override in Ghostty: `Hack Nerd Font Mono`
- Screensaver ASCII branding in `~/.config/omarchy/branding/screensaver.txt` set to:
  - `Inkfish`
  - `Hydra`

## Repository Layout

- `bin/` - executable `omarchy-*` commands
- `install/` - install flow and setup scripts
- `config/` - default user config copied to `~/.config`
- `default/` - default assets/templates used across the system
- `themes/` - theme packs and color definitions
- `migrations/` - versioned post-install migration scripts

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
