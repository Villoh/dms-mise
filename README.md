# mise for DankMaterialShell

Install, update and remove [mise](https://mise.jdx.dev) tools from DMS.

Composite plugin: a **DankBar widget**, a **keybind panel** (same UI, no bar needed) and a **launcher** (`mise` trigger).

| Updates | Tools |
| :---: | :---: |
| ![Updates tab](preview/updates.png) | ![Tools tab](preview/tools.png) |

## Install

Needs [DMS](https://danklinux.com) 1.5.0 or newer (1.6.0 for the keybind panel's *Window* look) and `mise` on your `PATH`. `curl` is used for live search.

```sh
dms plugins install mise
```

Or browse for it in DMS Settings → Plugins. Without the registry, clone it into the plugins folder:

```sh
git clone https://github.com/Villoh/dms-mise ~/.config/DankMaterialShell/plugins/mise
dms restart
```

Update with `dms plugins update mise`.

## Quickstart

1. Enable **mise** in Settings → Plugins and add its widget to your bar. The chef hat shows a counter when updates are pending; click it for the popout.
2. Bind the panel to a key, no bar needed:

   ```sh
   dms ipc call mise toggle   # also: open, close
   ```

   Binding examples for Hyprland and niri are in [Usage](docs/usage.md#keybind-panel).
3. Or open the launcher and type `mise`, then a query: it offers upgrades and installs from the registry or any `backend:tool` (`npm:package`, `github:Owner/repo`).
4. To also manage tools declared in project `mise.toml` files, turn on *Project tools* in Settings → Plugins → mise ([Project tools](docs/projects.md)).

By default it only touches your **global** mise config. Remove is two clicks (bin icon, then the red check).

## Docs

| | |
| --- | --- |
| [Usage](docs/usage.md) | The bar widget, the keybind panel and the launcher |
| [Project tools](docs/projects.md) | Following project configs, the scope picker, badge counts |
| [Installing tools](docs/installing-tools.md) | `backend:tool`, options, versions, the `http` form, live search, GitHub token |
| [Reference](docs/reference.md) | Settings, the commands it runs, how your mise settings affect it, limits |
| [Development](docs/development.md) | Dev setup, file layout, tests |

## License

[MIT](LICENSE)
