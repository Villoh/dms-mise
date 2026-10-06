# mise for DankMaterialShell

Install, update and remove [mise](https://mise.jdx.dev) tools from DMS.

Composite plugin: a **DankBar widget**, a **keybind panel** (same UI, no bar needed) and a **launcher** (`mise` trigger).

| Updates | Tools |
| :---: | :---: |
| ![Updates tab](preview/updates.png) | ![Tools tab](preview/tools.png) |

## Widget

Pill with the mise logo. Two counters appear next to it: updates (primary colour) and bumps (orange, with an up arrow). The logo is primary when updates are pending, orange when only bumps are; it turns red if the check fails and blinks while mise is working.

Click it for the popout:

- **Updates**: outdated tools (`current → latest`), filter box, backend chips, per-tool download button, and **Update all** at the bottom. If some tools are pinned or have a newer major, **Bump all** appears next to it (click twice to confirm).
- **Tools**: your installed tools (version, remove). Type to search installed tools and the mise registry; the download icon installs. Enter installs the first result not yet installed.
- Refresh button checks on demand. A banner shows what mise is doing and its last output line; failures show the last lines of output in a toast.

Each update row can be **skipped** (`skip_next`: that target version only, it shows again when a newer one appears) or **ignored** (`visibility_off`: the tool, whatever the version). Ignored items are not counted in the badge and are left out of *Update all*, *Bump all* and the launcher. The `ignored N` chip lists them with an undo button. Also listed, with undo and *Clear all*, in Settings → Plugins → mise. Stored in the plugin state (`~/.local/state/DankMaterialShell/plugins/mise_state.json`), not in your mise config. Handy for a release that fails to install (e.g. a badly published npm package that `aube` rejects).

Remove is two steps: bin icon, then the red check.

## Keybind panel

A panel you can bind to a key, with the same **Updates** and **Tools** tabs as the widget's popout. It opens on Updates when something is pending (updates or bumps) and on Tools otherwise; Settings → *Keybind panel opens on* can pin it to Updates or Tools. Two looks, chosen in Settings → Plugins → mise → *Keybind panel*:

- **Overlay** (default): DMS's centered modal. It closes on a click outside, and you can drag the header to move it (double-click recenters; kept until the shell restarts). No compositor border, only DMS's own.
- **Window**: a real floating window, like DMS's System Monitor. The border and rounding come from your compositor config, and it moves and resizes like any other window (drag the header or use your window-move binding; double-click the header to maximize). Window class `com.danklinux.dms`, title `mise`, if you want a window rule. Tested on Hyprland only; the compositor has to float DMS windows.

In both: the search field is focused on open; Esc, the close button or the same keybind closes it.

```sh
dms ipc call mise toggle   # also: open, close
```

Hyprland (Lua config, 0.55+):

```text
hl.bind("SUPER + CTRL + M", hl.dsp.exec_cmd("dms ipc call mise toggle"))
```

Hyprland (`hyprland.conf`):

```text
bind = SUPER CTRL, M, exec, dms ipc call mise toggle
```

niri:

```text
Mod+M { spawn "dms" "ipc" "call" "mise" "toggle"; }
```

Row buttons need the mouse; Enter in the search field installs the first result not yet installed. For a fully keyboard-driven flow use the launcher below.

## Launcher

`mise` + query: upgrades for outdated tools (empty query also offers *Upgrade all*), installs from the registry or any `backend:tool`. Installed tools can be removed with Tab / right-click → *Remove*.

## Installing anything, with options

The registry is only a curated subset. Type any `backend:tool` and use it as-is:

```text
pipx:package
npm:package
cargo:crate
github:Owner/repo
```

Tool options go in brackets, exactly as `mise use` accepts them:

```text
pipx:package[uvx_args=--python 3.14]
npm:package[allow_builds=["node-pty"]]
```

They are written to the config as an inline table and kept on updates. Text is passed unchanged, so it is case-sensitive.

Pin a version with `@`: `ripgrep@14.0.3` or `pipx:package@1.2`. The version part is *not* a prefix filter, it is what `mise use` writes, so `@14.0.3` pins exactly and `@14` follows the latest 14.x. (The separator is `@`, not `:`.) Entries with a version or options always show as installable, even if the tool is already installed, so you can re-pin or reconfigure it.

## Settings

Settings → Plugins → mise: check interval (15 min, 30 min, 1 h, 4 h, daily). Default 30 min.

## What it runs

| Action | Command |
| --- | --- |
| Check | `mise outdated --json`, `mise outdated --bump --json`, `mise ls --json` |
| Registry | `mise registry` (once, at load) |
| Update | `mise upgrade --yes [tool]` |
| Bump | `mise upgrade --bump --yes <tool>` |
| Install | `mise use --global --yes <tool>` |
| Remove | `mise unuse --global --yes <tool>` |

One job at a time.

## Limits

- `install` and `remove` write the **global** mise config (`~/.config/mise/config.toml`). If that file is managed (chezmoi, home-manager) it ends up dirty or read-only.
- `remove` only works for tools in the global config; one that lives only in a project `mise.toml` fails with mise's error.
- `mise upgrade` respects the requested version (`node = "22"` never goes to 24, an exact pin never moves). Those show as **bump** rows (warning icon, from `mise outdated --bump`) with their own button, which runs `mise upgrade --bump <tool>` and rewrites the version in the global config. Bumps are not counted in the badge and are never part of *Update all*. Turn them off in Settings.
- It does not update the mise binary itself. If mise comes from nix/a package manager, update it there.
- Old inactive versions are not pruned. Skipped versions that were superseded stay in the ignored list until you undo them.
- No install-time options UI: use the bracket syntax above.
- Toast duration is controlled by DMS.

## Development

```sh
ln -s "$PWD" ~/.config/DankMaterialShell/plugins/mise
dms ipc call plugins reload mise
```

`reload` is enough for `MiseBar.qml` / `MiseLauncher.qml` / `MiseDaemon.qml` edits. `MiseService.qml` is a singleton and `MisePanel.qml` is registered, both through `qmldir`, and `plugin.json` is read at scan time: for those, run `dms restart`. `Qt5Compat` is not available in every DMS install, so the logo is tinted with `QtQuick.Effects` (`MultiEffect` mask) instead.

Logo: `assets/mise.svg`, from <https://mise.jdx.dev/logo.svg>.

## License

[MIT](LICENSE)
