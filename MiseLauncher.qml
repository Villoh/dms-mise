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
    }

    function poke() {
        if (pluginService)
            pluginService.requestLauncherUpdate(pluginId);
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
                comment: t.current + " → " + t.latest,
                action: "upgrade:" + t.name,
                categories: ["mise"]
            }));

        MiseService.bumps.filter(t => t.name.toLowerCase().includes(q)).forEach(t => items.push({
                name: "Bump " + t.name,
                icon: "material:upgrade",
                comment: t.current + " → " + t.bump + " · rewrites mise config",
                action: "bump:" + t.name,
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
                name: "Searching npm, crates.io…",
                icon: "material:sync",
                comment: "remote results appear here",
                action: "noop:",
                categories: ["mise"]
            });
        // nothing pending and no query: an empty list reads as "broken", so say what is going on
        if (!q && items.length === 0)
            items.push({
                name: MiseService.checking ? "Checking for updates…" : "All tools are up to date",
                icon: "material:" + (MiseService.checking ? "sync" : "check_circle"),
                comment: MiseService.installed.length + " installed · type a name or backend:tool to install · Enter to re-check",
                action: "refresh:",
                categories: ["mise"]
            });
        return items;
    }

    // Tab / right-click on an installed tool -> Remove
    function getContextMenuActions(item) {
        if (!item?.action?.startsWith("installed:"))
            return [];
        const tool = item.action.substring(10);
        return [{
                icon: "delete",
                text: "Remove " + tool,
                closeLauncher: true,
                action: () => MiseService.uninstall(tool)
            }];
    }

    function executeItem(item) {
        if (!item?.action)
            return;
        const i = item.action.indexOf(":");
        const kind = item.action.substring(0, i);
        const tool = item.action.substring(i + 1);
        if (kind === "refresh")
            MiseService.refresh();
        else if (kind === "bump")
            MiseService.bump(tool);
        else if (kind === "upgrade")
            MiseService.upgrade(tool);
        else if (kind === "install")
            MiseService.install(tool);
    }
}
