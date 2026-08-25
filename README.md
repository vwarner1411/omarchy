# Omarchy (warnerva fork)

This repository tracks a customized Omarchy fork used for a Windows + Omarchy dual-boot workstation with opinionated developer defaults.

Upstream Omarchy info: [omarchy.org](https://omarchy.org)

## What Changed In This Fork

- Supports linking Quattro's package-backed install to this fork for local command and config overrides.
- Added `omarchy-setup-dualboot` for resilient Limine dual-boot setup.
- Added `omarchy-setup-skel` to build a sanitized `/etc/skel` from an existing user.
- Added `omarchy-setup-sync-upstream` for controlled upstream merge syncs.
- Added `inplace-luks-limine-windows-runbook.md` for optional in-place LUKS conversion planning.

## Quattro Checkout Model

Omarchy Quattro installs production files from Arch packages under `/usr/share/omarchy`; regular updates do not pull this Git fork. Keep the fork checkout at `/home/warnerva/programming/omarchy` and link it after the Quattro package upgrade:

```bash
omarchy dev link /home/warnerva/programming/omarchy --no-reboot
```

The link sets `OMARCHY_PATH` and sudo's Omarchy command path after reboot. Fixed package-owned paths under `/etc`, `/usr/lib/systemd`, and similar locations still require a package build rather than a development link.

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
- fonts, desktop launcher, and icon data

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
- Maintain a local tracking branch for upstream (`upstream-<upstream-branch>` by default).
- Merge upstream changes into your custom branch using normal git merge semantics.
- Preserve local commits and force conflict resolution where both sides changed the same lines.

Default behavior:
- upstream remote name: `upstream`
- upstream URL: `https://github.com/basecamp/omarchy.git`
- upstream branch: auto-detected from `upstream/HEAD` (currently `quattro`)
- tracking branch: `upstream-<upstream-branch>` (for example `upstream-quattro`)
- target branch: current branch
- pushes tracking branch and merged target branch to `origin`
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
omarchy-setup-sync-upstream --upstream-branch master --tracking-branch upstream-master
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

These versioned scripts drive the non-upstream workstation behavior:

- `bin/omarchy-local-root-apply`
- `bin/omarchy-local-apply`

Run order:

```bash
bin/omarchy-local-root-apply
bin/omarchy-local-apply
```

Override source:

- Default override directory: `config/local-overrides/`
- Optional override path env var: `OMARCHY_LOCAL_OVERRIDES_DIR`
- If older copies exist in `~/.local/bin`, remove them to avoid drift from versioned repo scripts.
- Scripts auto-fallback to the repo root when `OMARCHY_PATH` is unset or points to a missing checkout.

### Package Delta (vs upstream baseline)

Removed by local root apply:

- `alacritty`

`eza` remains installed because it is part of the Quattro package set, but the zsh overrides route the `ls` aliases to `lsd`. `tealdeer` replaces `tldr` while satisfying the same package dependency.

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
- Uses versioned overrides from `config/local-overrides/` by default.
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

## The Omarchy Manual

The manual lives in [`manual/`](manual/), which is its authoritative source. It's
mirrored to [learn.omacom.io](https://learn.omacom.io/2/the-omarchy-manual), where
its screenshots are also hosted.

- [Welcome to Omarchy!](manual/01-welcome-to-omarchy.md)

**The Basics**

- [Getting Started](manual/02-getting-started.md)
- [Coming From Mac or Windows](manual/03-coming-from-mac-or-windows.md)
- [Navigation](manual/04-navigation.md)
- [The top bar](manual/05-the-top-bar.md)
- [Themes](manual/06-themes.md)
- [Hotkeys](manual/07-hotkeys.md)
- [Unified Clipboard & History](manual/08-unified-clipboard-history.md)
- [Reminders](manual/09-reminders.md)
- [Notices](manual/10-notices.md)
- [Text Extraction & Dictation](manual/11-text-extraction-dictation.md)
- [Screenshots & Recording](manual/12-screenshots-recording.md)
- [Toggles, idle & screensaver](manual/13-toggles-idle-screensaver.md)
- [Omarchy CLI](manual/14-omarchy-cli.md)

**The Applications**

- [Terminal](manual/15-terminal.md)
- [Neovim](manual/16-neovim.md)
- [AI](manual/17-ai.md)
- [Development Tools](manual/18-development-tools.md)
- [Shell Tools](manual/19-shell-tools.md)
- [Shell Functions](manual/20-shell-functions.md)
- [TUIs](manual/21-tuis.md)
- [GUIs](manual/22-guis.md)
- [Browsers](manual/23-browsers.md)
- [Commercial apps/services](manual/24-commercial-apps-services.md)
- [Web Apps](manual/25-web-apps.md)
- [Gaming](manual/26-gaming.md)
- [Filling out PDFs](manual/27-filling-out-pdfs.md)
- [Windows VM](manual/28-windows-vm.md)
- [Other Packages](manual/29-other-packages.md)

**Configuration**

- [Updates](manual/30-updates.md)
- [Dotfiles](manual/31-dotfiles.md)
- [Shell plugins](manual/32-shell-plugins.md)
- [Monitors](manual/33-monitors.md)
- [Keyboard, Mouse, Trackpad](manual/34-keyboard-mouse-trackpad.md)
- [Networking](manual/35-networking.md)
- [System sleep](manual/36-system-sleep.md)
- [Hardware authentication](manual/37-hardware-authentication.md)
- [Fonts](manual/38-fonts.md)
- [Backgrounds](manual/39-backgrounds.md)
- [Prompt](manual/40-prompt.md)
- [Branding](manual/41-branding.md)
- [Common tweaks](manual/42-common-tweaks.md)
- [Making your own theme](manual/43-making-your-own-theme.md)

**The Rest**

- [Mac support](manual/44-mac-support.md)
- [Troubleshooting](manual/45-troubleshooting.md)
- [FAQ](manual/46-faq.md)
- [System snapshots](manual/47-system-snapshots.md)
- [Security](manual/48-security.md)
- [Omarchy on...](manual/49-omarchy-on.md)
- [Dual Boot Install](manual/50-dual-boot-install.md)
- [Unattended Installs](manual/51-unattended-installs.md)

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
