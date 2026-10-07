import QtQuick
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string pluginId: "mise"
    property string trigger: "mise"

    signal itemsChanged

    // registry/outdated/installed load async: refresh results when they land
    property Connections svc: Connections {
        target: MiseService
        function onRegistryChanged() {
            root.poke();
        }
        function onOutdatedChanged() {
            root.poke();
        }
        function onBumpsChanged() {
            root.poke();
        }
        function onInstalledChanged() {
            root.poke();
        }
        function onProjectDataChanged() {
            root.poke();
        }
        function onCheckingChanged() {
            root.poke();
        }
        function onRemoteChanged() {
            root.poke();
        }
        function onVerifiedChanged() {
            root.poke();
        }
        function onLookingUpChanged() {
            root.poke();
        }
        function onLastErrorChanged() {
            root.poke();
        }
        function onUncheckedChanged() {
            root.poke();
        }
    }

    function poke() {
        if (pluginService)
            pluginService.requestLauncherUpdate(pluginId);
    }

    // action = kind:tool, or kind:tool<TAB>config-path for a project scope (tool names contain ':')
    function act(kind, tool, scope) {
        return kind + ":" + tool + (scope ? "\t" + scope : "");
    }

    // " · project" next to rows that belong to a project config
    function where(scope) {
        return scope ? " · " + MiseService.scopeLabel(scope) : "";
    }

    function getItems(query) {
        const raw = (query || "").trim();   // search() needs the original case: github:Owner/Repo, [opts]
        const q = raw.toLowerCase();
        MiseService.lookup(raw);   // debounced npm / crates.io / GitHub lookup; results arrive via onRemoteChanged
        const items = [];
        const out = MiseService.outdated.filter(t => t.name.toLowerCase().includes(q));

        if (!q && out.length > 1)
            items.push({
                name: "Upgrade all (" + out.length + ")",
                icon: "material:upgrade",
                comment: out.map(t => t.name).join(", "),
                action: "upgrade:",
                categories: ["mise"]
            });
        out.forEach(t => items.push({
                name: "Upgrade " + t.name,
                icon: "material:upgrade",
                comment: t.current + " → " + t.latest + where(t.scope),
                action: act("upgrade", t.name, t.scope),
                categories: ["mise"]
            }));

        MiseService.bumps.filter(t => t.name.toLowerCase().includes(q)).forEach(t => items.push({
                name: "Bump " + t.name,
                icon: "material:upgrade",
                comment: t.current + " → " + t.bump + " · rewrites mise config" + where(t.scope),
                action: act("bump", t.name, t.scope),
                categories: ["mise"]
            }));

        MiseService.search(raw).forEach(r => items.push({
                name: (r.installed ? "Installed: " : "Install ") + r.name,
                icon: "material:" + (r.installed ? "check_circle" : "download"),
                comment: r.installed ? (MiseService.versions[r.name] || "") + " · Tab to remove" : r.backend,
                action: (r.installed ? "installed:" : "install:") + r.name,
                categories: ["mise"]
            }));
        if (q && MiseService.lookingUp)
            items.push({
                name: "Searching…",
                icon: "material:sync",
                comment: "remote results appear here",
                action: "noop:",
                categories: ["mise"]
            });
        if (q)
            MiseService.notices.forEach(n => items.push({
                    name: n,
                    icon: "material:cloud_off",
                    comment: "results from it are missing",
                    action: "noop:",
                    categories: ["mise"]
                }));
        // nothing pending and no query: an empty list reads as "broken", so say what is going on
        if (!q && items.length === 0)
            items.push({
                name: MiseService.checking ? "Checking for updates…" : "All tools are up to date",
                icon: "material:" + (MiseService.checking ? "sync" : "check_circle"),
                comment: MiseService.installed.length + " installed · type a name or backend:tool to install · Enter to re-check",
                action: "refresh:",
                categories: ["mise"]
            });
        // keep this order: the launcher re-scores plugin items with its own fuzzy match unless they
        // carry `_preScored` (it would list `dotnet:Avalonia`, the exact hit, seventh)
        items.forEach((it, i) => it._preScored = 1000 - i);
        return items;
    }

    // Tab / right-click on an install / installed row. Global first, then one entry per followed project:
    // Remove where the tool is there, Install where it is not.
    function getContextMenuActions(item) {
        const a = item?.action || "";
        if (!a.startsWith("installed:") && !a.startsWith("install:"))
            return [];
        const tool = a.substring(a.indexOf(":") + 1);
        const out = [];
        [""].concat(MiseService.scopes).forEach(s => {
            const here = s ? tool in MiseService.toolsIn(s) : MiseService.installed.includes(tool);
            const loc = s ? " in " + MiseService.scopeLabel(s) : (MiseService.scopes.length ? " globally" : "");
            // plain `Install` stays the main action of install rows; the menu only adds the project ones
            if (!here && !s && a.startsWith("install:"))
                return;
            out.push({
                icon: here ? "delete" : "download",
                text: (here ? "Remove " : "Install ") + tool + loc,
                closeLauncher: true,
                action: () => here ? MiseService.uninstall(tool, s) : MiseService.install(tool, s)
            });
        });
        return out;
    }

    function executeItem(item) {
        if (!item?.action)
            return;
        const i = item.action.indexOf(":");
        const kind = item.action.substring(0, i);
        const rest = item.action.substring(i + 1).split("\t");
        const tool = rest[0];
        const scope = rest[1] || "";
        if (kind === "refresh")
            MiseService.refresh();
        else if (kind === "bump")
            MiseService.bump(tool, scope);
        else if (kind === "upgrade")
            MiseService.upgrade(tool, tool ? scope : undefined);
        else
        // no tool = Upgrade all, every scope
        if (kind === "install")
            MiseService.install(tool, scope);
    }
}
