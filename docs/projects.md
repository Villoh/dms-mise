# Project tools

By default the plugin only manages the **global** config. Turn on *Project tools* in Settings to also list, update, bump, install and remove tools declared in project configs (`mise.toml`, `.mise.toml`, `.config/mise/config.toml`, ...):

| Mode | Projects followed |
| --- | --- |
| Off (default) | none, nothing changes |
| Manual | only the ones you add |
| Tracked | every config mise has already seen (`<state dir>/tracked-configs`, existing files only, the global config and `/tmp` skipped) plus the ones you add |

Add a project from Settings → *Projects* (**Browse** or type the path), or from the popout: scope button → *Add project…* opens DMS's folder browser; the keyboard icon on that row lets you paste a folder or a config file path instead (`~` works). Either way it is checked before it is saved, and a folder without a mise config is rejected. The **x** next to a project in the scope menu (or the list in Settings) stops following it. That only edits the plugin's list: a tracked project is hidden (undo in Settings), and no config file is ever touched.

In the popout, the scope button next to refresh opens a menu: **Global** (the default, so nothing changes until you pick something else), **All** or one project. *Update all* and *Bump all* act on the picked scope, and **Install writes to the picked project** (to global when *All* is selected). Rows show where they come from when *All* is selected. Only the tools a project config declares are listed for it; inherited global tools stay under *Global*.

The bar badge counts **Global** only by default; *Bar badge counts* in Settings switches it to global + the projects you follow. The popout's header, tab count and *Update all* always follow the scope picked in its menu, and a dot on the scope button (plus a hint in the empty list) tells you when another scope has something pending.

The tracked list is mise's internal state, not a stable API. If it ever changes shape, *Tracked* finds nothing and *Manual* keeps working.
