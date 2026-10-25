# Development

```sh
ln -s "$PWD" ~/.config/DankMaterialShell/plugins/mise
dms ipc call plugins reload mise
```

`reload` is enough for `src/MiseBar.qml` / `src/MiseLauncher.qml` / `src/MiseDaemon.qml` edits. The singletons and `MisePanel.qml` are registered through `qmldir`, the `.js` libraries are cached for the life of the engine, and `plugin.json` is read at scan time: for those, run `dms restart`.

## Layout

One file per concern, all under `src/`. The entry points that `plugin.json` names stay at the top of `src/`; the rest is grouped in `services/`, `panel/` and `settings/`, each with its own `qmldir`, and imported by relative path (`import "../services"`):

| File | Role |
| --- | --- |
| `services/MiseService.qml` | Global inventory (`mise ls` / `outdated` / `registry`), ignored updates, settings, the actions (`upgrade`, `bump`, `install`, `uninstall`, `prune`) and what mixes global and project state (`toolsIn`, `scopeWarning`) |
| `services/MiseProjects.qml` | Followed projects: mode, lists, `scopes`, per-scope data, add / remove |
| `services/MiseJobs.qml` | One mise job at a time: command queue, log, toasts, `finished` |
| `services/MiseRemote.qml` | Search-as-you-type on package sites and the exact-name check, with the GitHub token |
| `services/MiseConfig.qml` | `mise settings`: all settings, which are set in the global config, set / unset / toggle, run on their own (no job banner or toast, errors toast) |
| `services/MiseInfo.qml` | Row details (`mise tool`, `ls-remote`) and the `http:` latest check |
| `services/MiseSearch.js` | Pure search / ranking / parsers / verifier URLs, no Quickshell (tested) |
| `services/MiseScripts.js` | The `sh` scripts the services run |
| `panel/MisePanel.qml` | The popout: derives the rows and the picked scope, lays out the pieces below |
| `panel/`: `MisePanelToolbar`, `MiseJobBanner`, `MiseBackendChips`, `MiseUpdateRow`, `MiseConfigRow`, `MiseToolRow`, `MiseToolDetails`, `MiseVersionChip`, `MiseHttpForm` + `MiseHttpDraft`, `MiseScopeMenu`, `MiseFixMenu` | Panel pieces, fed by properties; `MiseConfirm` is the shared arm-then-confirm click |
| `MiseBar.qml`, `MiseLauncher.qml`, `MiseDaemon.qml`, `MiseSettings.qml` (`src/`) | Bar widget, launcher provider, daemon, settings page (DMS `SettingsCard`s) |
| `settings/MiseLimitSlider.qml`, `settings/MiseIntervalSlider.qml` | Settings sliders that save once, on release (the second walks a fixed scale of check intervals) |

## Tests

The search, ranking and verification logic has no Quickshell dependency (`src/services/MiseSearch.js`) and is tested against recorded API answers in `tests/fixtures/`, with Node's standard library only:

```sh
node --test
```

CI runs the same command with the `nodejs` pinned in `.github/workflows/ci.yml`. To refresh a fixture, save the answer of the URL in `src/services/MiseSearch.js` (`searchers` / `verifiers`), trimmed to the fields the parser reads.

Logo: `assets/mise.svg`, from <https://mise.jdx.dev/logo.svg>. The bar pill uses the `chef_hat` icon from Material Symbols instead: the logo line art is too fine to read at bar size.
