# Reference

## Settings

Settings → Plugins → mise: check interval (15 min, 30 min, 1 h, 4 h, daily). Default 30 min. Also: keybind panel mode and tab, pinned/major updates, live search toggle, project tools (off / manual / tracked) and the project list.

## What it runs

| Action | Command |
| --- | --- |
| Check | `mise outdated --json`, `mise outdated --bump --json`, `mise ls --json` (and the same with `-C <project>` per followed project) |
| Registry | `mise registry --json` (once, at load) |
| Live search | `curl` to registry.npmjs.org, crates.io, api.github.com, pypi.org (only while typing, see [Installing tools](installing-tools.md#live-search-and-verification)); `mise tool --json <aqua:name>` to check an `aqua:` name (10 s timeout) |
| GitHub token | `mise token github --raw` (once per session, on the first GitHub request) |
| Update | `mise upgrade --yes [tool]` (`mise -C <project> upgrade ...` for a project) |
| Bump | `mise upgrade --bump --yes <tool>` (same `-C`) |
| Install | `mise use --global --yes <tool>`, or `mise use --path <config> --yes <tool>` for a project (under `locked = true` see *Your mise settings*) |
| Details | `mise tool --json <tool>`, `mise ls-remote <tool>` (30 s timeout, only when a row is expanded) |
| Remove a version | `mise uninstall --yes <tool>@<version>` |
| Prune | `mise ls --prunable --json` (with every check), `mise prune --tools --yes [tool]` |
| Remove | `mise unuse --global --yes <tool>`, or `mise unuse --path <config> --yes <tool>` for a project; then `mise lock -g` (or `mise -C <project> lock`) only if `mise lock --dry-run` reports stale entries, then `mise prune --tools --yes <tool>` (see *Limits*) |
| Trust | `mise trust <config>` for each project you check in the list the fix button opens (shield or lock) |
| Lock | `mise lock -g`, or `mise -C <project> lock`, for each scope you check in the same list |

One job at a time.

## Your mise settings

The plugin only runs `mise` and never edits its settings; it works with these:

| Setting | What happens |
| --- | --- |
| `locked = true` | Respected. `mise use` refuses a tool the lockfile has no entry for, so for a plain tool (`name` or `name@version`; a version already in the config is rewritten, as `mise use` does) *Install* does what you would by hand: `mise config set` writes it to the config, `mise lock` locks it (`mise lock --bump` for `latest`: without it, a version already locked for the tool would hold it back), `mise install` installs it. Tools with `[options]`, a `.` in the name, or declared in that config with options (a table or a list) fail with mise's error and a hint: add them to the config yourself, run `mise lock` and `mise install`, or turn on *Install with `locked` off* in Settings (then only Install runs with `MISE_LOCKED=0` and mise writes the lockfile entries). `lockfile = true` alone does not create a lockfile: run `mise lock` once in a project. When `mise use` goes through (the version is already installed, for example by another scope), *Install* then runs `mise lock <tool>` in that scope so the lockfile matches the config. Update and Bump always run with your settings. |
| `paranoid = true` / untrusted configs | A project config has to be trusted by hand (`mise trust`), and again each time its content changes outside mise. Until then the project shows nothing and the popout says `not trusted, run mise trust there` and a shield button appears next to the scope picker: click it for a list with a *Trust* and a *Lock* section (each with its own check all), check the ones to fix (an untrusted project starts unchecked when there are several) and click the button (only do it for configs you wrote or reviewed). The plugin itself never runs `mise trust` unless you click that button, but Install runs `mise use`, and mise trusts the config `use` writes to (even when it fails): that is mise's behavior, not a setting of the plugin. The one other place it runs `mise trust` is the locked-install flow above, after its own edit of a project config, and only if that config loaded right before and no longer does (that is, under `paranoid`). |
| Tools missing from the lockfile | `mise outdated` skips them, so the list would say *up to date*. The popout says `tools missing from the lockfile, run mise lock` instead, with the same list (locks start checked) running `mise lock` for the checked ones (`mise lock -g` for the global config); one failing does not stop the others. It resolves versions and writes `mise.lock`, not your config. Happens after editing a `mise.toml` by hand or pulling a change to it. |
| `minimum_release_age` | Applied by mise itself; the plugin passes no flag that overrides it. |
| `disable_backends`, `enable_tools` | The registry list follows them. Live search and a typed `backend:tool` do not: installing a disabled one fails with mise's own message. |
| `auto_install_disable_tools`, `sandbox.*`, `trusted_config_paths` | Not used: the plugin never runs `mise x`, `run` or tasks. |

## Limits

- Without a project selected, `install` and `remove` write the **global** mise config (`~/.config/mise/config.toml`). If that file is managed (chezmoi, home-manager) it ends up dirty or read-only. Project installs write that project's `mise.toml`, so they show up in git.
- `remove` only works on the config you pick: a tool declared only in a project fails on *Global* (and the other way round) with mise's error.
- `remove` is mise's own sequence for the scope you pick: `unuse` takes the tool out of that config, `lock` clears its entries from that scope's lockfile (only when `mise lock --dry-run` says something is stale, so no lockfile is ever created and nothing is rewritten when there is nothing to clear), and `prune` deletes the versions that nothing needs. **mise** decides what is deleted: a version that another tracked config, a tool stub or a running process still needs stays, and the toast just says `Removed`. `lock` is needed because `unuse` leaves the tool's entries in `mise.lock` and `prune` counts a lockfile as a requirement. Side effect: `mise lock` also refreshes the platform entries of other tools in that lockfile (on a copy of a real one it changed the `linux-arm64` asset of two tools), which is what you get when you run it by hand.
- Project configs that mise does not trust fail to load; that project shows nothing and the popout says so (see *Your mise settings*).
- `mise upgrade` respects the requested version (`node = "22"` never goes to 24, an exact pin never moves). Those show as **bump** rows (warning icon, from `mise outdated --bump`) with their own button, which runs `mise upgrade --bump <tool>` and rewrites the version in the config that declares the tool. Bumps are not counted in the badge and are never part of *Update all*. Turn them off in Settings.
- It does not update the mise binary itself. If mise comes from nix/a package manager, update it there.
- Old inactive versions are not pruned. Skipped versions that were superseded stay in the ignored list until you undo them.
- No install-time options UI: use the [bracket syntax](installing-tools.md).
- Toast duration is controlled by DMS.
