# OpenRig terminal colors

Research date: 2026-10-20. Research only: no agent, daemon, terminal setting,
or system configuration was changed.

## Finding

The strongest local explanation is inherited `NO_COLOR=1`, not a terminal
incapable of displaying color. Read-only inspection found that variable in
all seven active AI harnesses, their tmux server, and their Herdr server.
All seven attached tmux clients advertise `RGB`; sampled Claude and Codex
processes have `TERM=tmux-256color` and `COLORTERM=truecolor`.
These are local observations, not claims from upstream documentation.

A controlled PTY check of installed Codex 0.163.0, using private configuration
and `--help` only, produced zero ANSI styling sequences with `NO_COLOR=1`
and 134 with that variable removed. No model request or live agent was used.
This confirms CLI-help color detection, not a complete interactive-session
reproduction. Sampled live Claude pane text had no ANSI styles; sampled Codex
pane text had text attributes but no foreground/background color sequences.

The screenshot's green diff does not disprove this explanation: `NO_COLOR`
asks applications to suppress ordinary color; it does not stop a terminal
rendering explicitly colored output. Any nonempty value, including `0`,
requests no color under the convention. Unset the variable instead of
changing it to `0`. [NO_COLOR specification](https://no-color.org/)

Removing it from an existing shell does not change already-running agents.
The OpenRig daemon also inherited it. Neither the inspected launcher wrapper
nor the inspected desktop startup files supplied the flag explicitly, and
the current user systemd environment did not contain it. The exact original
source of the inherited flag has not been established.

## Separate the three layers

| Layer | Setting | What it changes |
| --- | --- | --- |
| Harness | Launch environment, Claude `/theme` and `/color` | Colors inside each conversation |
| Herdr | `[theme.custom]` and `[ui]` | Split borders, labels, sidebar, focus presentation |
| tmux | Terminal capabilities and tmux border options | Color transport and actual tmux separators |

The screenshot includes Herdr's Spaces/Agents sidebar. OpenRig supports
opening its tmux-backed agent sessions inside Herdr; that is distinct from
Herdr being a single plain tmux layout. [OpenRig terminal integration](https://github.com/mvschwarz/openrig/blob/v0.6.11/packages/daemon/src/domain/terminal/herdr-adapter.ts)

## Restoring harness colors

For a future launch, remove `NO_COLOR` at the component that supplies the
environment. For example, `env -u NO_COLOR <launcher> ...` removes it for that
launch. This alone cannot clean an existing tmux server's stored environment
or an existing Herdr server, and does not recolor existing agent processes.
tmux merges its global and session environments when it creates a process.
Its `set-environment -u` unsets a stored variable; session-scoped `-r` marks a
variable for removal from new processes. Any eventual cleanup must target the
actual server `/tmp/tmux-1000/software-factory`, not the unused default socket.
Do not kill the tmux server to fix colors. [tmux environment rules](https://github.com/tmux/tmux/blob/master/tmux.1#L8052-L8136)

The verified server currently has the flag globally, with no observed
session-local overrides. This is the narrowly scoped cleanup command for
its stored global environment; it has **not** been run:

```bash
tmux -L software-factory set-environment -gu NO_COLOR
```

That only affects subsequently created processes. A shell or harness that
already inherited the flag still has it. Launchers should use a clean
environment, and any existing agents should be resumed through their normal
managed workflow only after they are idle and restart/resume is approved.

Claude's official changelog distinguishes launch environment from settings:
since 2.1.143, `NO_COLOR`/`FORCE_COLOR` under `settings.json` `env` affect
subprocesses rather than its own interface. Therefore, adding a color
override there is not a reliable repair for Claude's inherited UI state.
[Claude Code changelog, 2.1.143](https://github.com/anthropics/claude-code/blob/a6e289a2e772a17b3614a9ef43303003de5cd887/CHANGELOG.md#21143)

Once colors are enabled, Claude supports `/theme` for its palette, and
`/color cyan` (also red, blue, green, yellow, purple, orange, pink) for a
distinct prompt bar per session. `/color default` resets it. These are
commands typed into Claude, not the shell or OpenRig operator. They cannot
be assumed to override a launch-time no-color flag.
[Claude command reference](https://code.claude.com/docs/en/commands#built-in-commands),
[Claude terminal themes](https://code.claude.com/docs/en/terminal-config#match-the-color-theme)

Codex's `/theme` changes highlighting for fenced code blocks and diffs; it is
not documented as a whole-interface or per-pane tint. Do not prescribe the
non-interactive `codex exec --color always` option for an interactive seat.
[Official OpenAI CLI customization](https://learn.chatgpt.com/docs/cli-customization),
[CLI options](https://learn.chatgpt.com/docs/cli/reference)

## OpenRig version boundary

The installed CLI reports 0.6.11 (`379f0a0d`), matching installation metadata.
The following is the pinned upstream baseline, not proof that every locally
patched launch path is identical. Its tmux adapter starts sessions with `-e`
identity/runtime assignments and removes inherited parent-session identity
variables, but `NO_COLOR` is not on that removal list. Classic Claude and
Codex can therefore inherit the tmux environment. A managed Claude launch
instead uses `env -i` with a specific allowlist, so launch paths differ.
[0.6.11 tmux adapter](https://github.com/mvschwarz/openrig/blob/379f0a0d106e65164c615818927267c2082ebcb4/packages/daemon/src/adapters/tmux.ts#L569-L645),
[parent identity scrub](https://github.com/mvschwarz/openrig/blob/379f0a0d106e65164c615818927267c2082ebcb4/packages/daemon/src/domain/parent-session-env.ts),
[managed Claude environment](https://github.com/mvschwarz/openrig/blob/379f0a0d106e65164c615818927267c2082ebcb4/packages/daemon/src/domain/claude-managed-launch.ts#L130-L146)

Do not copy a current-main `env:` or `rig up --env` recipe into this install:
0.6.11's rig schema does not implement those fields. Current source has added
that support and rejects empty values; `NO_COLOR: "0"` still is not removal.
No upgrade is needed just to investigate this flag.
[0.6.11 schema](https://github.com/mvschwarz/openrig/blob/379f0a0d106e65164c615818927267c2082ebcb4/packages/daemon/src/domain/rigspec-schema.ts),
[newer environment validation](https://github.com/mvschwarz/openrig/blob/8f66ee4b88c8c34cd8fad2a44c33529f18559174/packages/daemon/src/domain/seat-env.ts)

## Making panes easier to distinguish

Installed Herdr is 0.8.2. That version renders active borders/titles using
`accent`, inactive borders/titles using `overlay0`. A stronger-contrast
example for the existing `~/.config/herdr/config.toml` is below; merge keys
into existing tables instead of duplicating tables or replacing the file.
These colors are examples, not upstream defaults.
[Herdr 0.8.2 border renderer](https://github.com/herdrdev/herdr/blob/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c/src/ui/panes.rs#L481-L525),
[supported theme overrides](https://github.com/herdrdev/herdr/blob/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c/src/config/theme.rs#L99-L123)

```toml
[theme.custom]
accent = "#89dceb"
overlay0 = "#b4befe"

[ui]
pane_borders = true
show_agent_labels_on_pane_borders = true
```

These two theme tokens are shared with other Herdr UI elements; they do not
assign an individual border color per AI agent. `pane_gaps = true` is an
optional spacing change that gives each pane separate edges. The current
configuration intentionally uses `pane_gaps = false` and
`pane_outer_borders = false`, so those preferences should not be reset merely
to repair colors. In 0.8.2, `pane_borders` is a boolean: current docs showing
`"auto"` or `"always"` are for newer versions.
[0.8.2 UI configuration](https://github.com/herdrdev/herdr/blob/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c/src/config/model.rs#L876-L889)

Herdr supports `herdr server reload-config` for presentation changes without
restarting the agent panes. Use the actual instance/socket when applying it.
This reload would not remove `NO_COLOR` from running agents.
[0.8.2 reload documentation](https://github.com/herdrdev/herdr/blob/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c/docs/next/website/src/content/docs/configuration.mdx#reload-config)

There is also a separate dimming behavior in 0.8.2: when a multi-pane view is
outside Terminal mode, Herdr dims all unfocused pane contents. If Herdr is
visibly in Navigate mode, Esc exits that mode; Enter activates the selected
workspace and returns to Terminal mode. Do not blindly press Esc inside an
already-active harness, where it may interrupt work. There is no exposed
mode field in the 0.8.2 `session.snapshot` schema, and no verified read-only
client-mode getter was found. This dimming is separate from `NO_COLOR` and
cannot explain a launch-time environment flag.
[0.8.2 dimming condition](https://github.com/herdrdev/herdr/blob/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c/src/ui/panes.rs#L355-L378),
[navigation exit behavior](https://github.com/herdrdev/herdr/blob/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c/src/app/input/navigate.rs#L128-L136),
[snapshot schema](https://github.com/herdrdev/herdr/blob/9eb521456ac0d19d3ab3d9d7cea3cca10baa8a4c/src/api/schema/session.rs)

## tmux truecolor is not the immediate fix here

tmux's official guidance uses `default-terminal "tmux-256color"` inside tmux
and an outer-terminal-specific `terminal-features` entry ending `:RGB` (3.2+),
or the older `terminal-overrides` entry ending `:Tc`. The outer terminal must
really support the capability. The observed clients already advertise RGB;
do not add universal overrides or change `TERM` to `xterm-256color` inside
tmux just to treat this symptom. [tmux color FAQ](https://github.com/tmux/tmux/wiki/FAQ#how-do-i-use-rgb-colour)

Claude has a documented `CLAUDE_CODE_TMUX_TRUECOLOR=1` override for its
256-color clamp under tmux, intended only after configuring truecolor. That
is not a substitute for removing `NO_COLOR` and is not needed to prove the
current transport supports RGB. [Claude environment reference](https://code.claude.com/docs/en/env-vars)

tmux's `pane-border-style` and `pane-active-border-style` affect actual tmux
dividers. They will not recolor the Herdr dividers in this screenshot.
[tmux border styles](https://github.com/tmux/tmux/blob/master/tmux.1#L6171-L6240)
