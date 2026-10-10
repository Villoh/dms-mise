# Usage

## Widget

Pill with a chef hat icon. Two counters appear next to it: updates (primary colour) and bumps (orange, with an up arrow). The icon is primary when updates are pending, orange when only bumps are; it turns red if the check fails and blinks while mise is working.

Click it for the popout:

- **Updates**: outdated tools (`current → latest`; `not installed → version` for a tool your config declares but that is not installed yet, whose button installs it), filter box, backend chips, per-tool download button, and **Update all** at the bottom. If some tools are pinned or have a newer major, **Bump all** appears next to it (click twice to confirm).
- **Tools**: the tools of the scope you picked (version, remove). *Global* lists what your global config declares; a tool that is installed only because a project declares it shows under that project, not under *Global*, and a version nothing declares is only reachable through *Prune unused versions*. A tool your config declares but that is not installed shows `not installed` with a download button (installs the declared version) and does not count as installed. Type to search installed tools and the mise registry; the download icon installs. Enter installs the first result not yet installed.
- **Settings**: every [mise setting](https://mise.jdx.dev/configuration/settings.html) with its description, from `mise settings ls --all`. Filter by name or description. Grouped in sections (General, then one per group such as `npm`; the ones you have set are highlighted), with a chip per section to show just one. Booleans have a switch; anything else a text field (Enter or the check button that appears while you edit it saves; lists are comma separated, e.g. `a,b`). The undo button resets a setting to mise's default by removing it from your **global** config (`~/.config/mise/config.toml`); mise validates the value, so a wrong type fails with its message in a toast. Project configs are not touched.
- Refresh button checks on demand: the icon spins on hover and the button turns into a spinner while checking (held briefly so quick checks stay visible). A banner shows what mise is doing and its last output line; failures show the last lines of output in a toast.

Each update row can be **skipped** (`skip_next`: that target version only, it shows again when a newer one appears) or **ignored** (`visibility_off`: the tool, whatever the version). Ignored items are not counted in the badge and are left out of *Update all*, *Bump all* and the launcher. The `ignored N` chip lists them with an undo button. Also listed, with undo and *Clear all*, in Settings → Plugins → mise. Stored in the plugin state (`~/.local/state/DankMaterialShell/plugins/mise_state.json`), not in your mise config. Handy for a release that fails to install (e.g. a badly published npm package that `aube` rejects).

Remove is two steps: bin icon, then the red check.

## Keybind panel

A panel you can bind to a key, with the same **Updates**, **Tools** and **Settings** tabs as the widget's popout. It opens on Updates when something is pending (updates or bumps) and on Tools otherwise; Settings → *Keybind panel opens on* can pin it to Updates or Tools. Two looks, chosen in Settings → Plugins → mise → *Keybind panel*:

- **Overlay** (default): DMS's centered modal. It closes on a click outside, and you can drag the header to move it (double-click recenters; kept until the shell restarts). No compositor border, only DMS's own.
- **Window**: a real floating window, like DMS's System Monitor. The border and rounding come from your compositor config, and it moves and resizes like any other window (drag the header or use your window-move binding; double-click the header to maximize). Window class `com.danklinux.dms`, title `mise`, if you want a window rule. Tested on Hyprland only; the compositor has to float DMS windows. Needs DMS 1.6.0 or newer: on older versions the option is greyed out in Settings and the overlay is used.

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

`mise` + query: upgrades for outdated tools (empty query also offers *Upgrade all*), installs from the registry or any `backend:tool`. Installed tools can be removed with Tab / right-click → *Remove*. With *Project tools* on, that menu also lists one *Install in / Remove from `<project>`* entry per followed project, and upgrade rows carry the project name.

`mise` + `set` (or `settings`) manages [mise settings](https://mise.jdx.dev/configuration/settings.html) in the global config: `set` lists them, `set <part of a name>` narrows the list. Enter on a boolean toggles it. For any other type, add the value after the full name, `set jobs 4`, and Enter writes it. Tab / right-click on a setting you have set → *Reset to default*.
