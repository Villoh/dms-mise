# Development

```sh
ln -s "$PWD" ~/.config/DankMaterialShell/plugins/mise
dms ipc call plugins reload mise
```

`reload` is enough for `MiseBar.qml` / `MiseLauncher.qml` / `MiseDaemon.qml` edits. The singletons and `MisePanel.qml` are registered through `qmldir`, the `.js` libraries are cached for the life of the engine, and `plugin.json` is read at scan time: for those, run `dms restart`.

## Layout

One file per concern, all flat in the plugin folder (Quickshell resolves them through `qmldir`):

| File | Role |
| --- | --- |
| `MiseService.qml` | Global inventory (`mise ls` / `outdated` / `registry`), ignored updates, settings, the actions (`upgrade`, `bump`, `install`, `uninstall`, `prune`) and what mixes global and project state (`toolsIn`, `scopeWarning`) |
| `MiseProjects.qml` | Followed projects: mode, lists, `scopes`, per-scope data, add / remove |
| `MiseJobs.qml` | One mise job at a time: command queue, log, toasts, `finished` |
| `MiseRemote.qml` | Search-as-you-type on package sites and the exact-name check, with the GitHub token |
| `MiseInfo.qml` | Row details (`mise tool`, `ls-remote`) and the `http:` latest check |
| `MiseSearch.js` | Pure search / ranking / parsers / verifier URLs, no Quickshell (tested) |
| `MiseScripts.js` | The `sh` scripts the services run |
| `MisePanel.qml` | The popout: derives the rows and the picked scope, lays out the pieces below |
| `MisePanelToolbar`, `MiseJobBanner`, `MiseBackendChips`, `MiseUpdateRow`, `MiseToolRow`, `MiseToolDetails`, `MiseVersionChip`, `MiseHttpForm` + `MiseHttpDraft`, `MiseScopeMenu`, `MiseFixMenu` | Panel pieces, fed by properties; `MiseConfirm` is the shared arm-then-confirm click |
| `MiseBar.qml`, `MiseLauncher.qml`, `MiseDaemon.qml`, `MiseSettings.qml` | Bar widget, launcher provider, daemon, settings page |

## Tests

The search, ranking and verification logic has no Quickshell dependency (`MiseSearch.js`) and is tested against recorded API answers in `tests/fixtures/`, with Node's standard library only:

```sh
node --test
```

CI runs the same command with the `nodejs` pinned in `.github/workflows/ci.yml`. To refresh a fixture, save the answer of the URL in `MiseSearch.js` (`searchers` / `verifiers`), trimmed to the fields the parser reads.

Logo: `assets/mise.svg`, from <https://mise.jdx.dev/logo.svg>. The bar pill uses the `chef_hat` icon from Material Symbols instead: the logo line art is too fine to read at bar size.
