pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services
import "MiseSearch.js" as Search
import "MiseScripts.js" as Scripts

// Shared state for widget + launcher. One poll, one job at a time.
Item {
    id: root

    property var outdatedRaw: []  // [{name, requested, current, latest}] as mise reports them
    property var ignored: []      // "name" (all versions) or "name@version" (skip that target version)
    readonly property var outdated: outdatedRaw.concat(MiseProjects.outdated).filter(t => !isIgnored(t.name, t.latest))
    property var installed: []   // declared in the global config and installed: ["node", "pipx:harlequin", ...]
    property var missing: []     // declared in the global config but not installed (mise lists them too)
    property var versions: ({})  // name -> active version
    property var prunable: ({})  // name -> [versions] no tracked config uses (`mise ls --prunable`)
    readonly property int prunableCount: Object.keys(prunable).reduce((n, k) => n + prunable[k].length, 0)
    property var registry: []    // [{name, backend, desc}] ~1000 curated entries
    property bool checking: false
    property string error: ""
    property double lastCheck: 0
    property int intervalMin: 30  // minutes between background checks (Settings)
    property bool showBumps: true // list pinned / newer-major versions too (Settings)
    property var bumpRaw: []      // `mise outdated --bump`: [{name, requested, current, latest, bump}]

    // bump-only = outdated beyond what the requested version allows; `upgrade` can't reach them
    readonly property var bumps: showBumps ? bumpRaw.concat(MiseProjects.bumps).filter(b => !outdatedRaw.concat(MiseProjects.outdated).some(o => o.name === b.name && o.scope === b.scope) && !isIgnored(b.name, b.bump)) : []

    // bar badge: "global" (default) or "all" (global + followed projects)
    property string badgeScope: "global"
    readonly property var badgeOutdated: inFilter(outdated, badgeScope === "all" ? "*" : "")
    readonly property var badgeBumps: inFilter(bumps, badgeScope === "all" ? "*" : "")

    function loadState() {
        ignored = PluginService.loadPluginState("mise", "ignored", []) || [];
    }

    function loadSettings() {
        const m = parseInt(PluginService.loadPluginData("mise", "interval", "30"));
        intervalMin = m > 0 ? m : 30;
        loadState();
        badgeScope = PluginService.loadPluginData("mise", "badgeScope", "global") === "all" ? "all" : "global";
        const b = PluginService.loadPluginData("mise", "showBumps", true);
        showBumps = !(b === false || b === "false");
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === "mise")
                root.loadSettings();
        }
        // the Settings page edits the ignored list too
        function onPluginStateChanged(pluginId) {
            if (pluginId === "mise")
                root.loadState();
        }
    }

    // after a job the installed / active versions changed
    Connections {
        target: MiseJobs
        function onFinished() {
            root.refresh();
        }
    }

    // "*" / undefined = every scope
    function inFilter(rows, scope) {
        return scope === undefined || scope === "*" ? rows : rows.filter(r => r.scope === scope);
    }

    function toolsIn(scope) {
        return scope ? ((MiseProjects.byScope[scope] || {}).tools || {}) : versions;
    }

    function installedIn(scope) {
        return scope ? Object.keys(toolsIn(scope)).filter(n => !missingIn(scope).includes(n)).sort() : installed;
    }

    // declared in that config, not installed yet: `mise upgrade <tool>` installs the declared version
    function missingIn(scope) {
        return scope ? Object.keys((MiseProjects.byScope[scope] || {}).missing || {}).sort() : missing;
    }

    function alias(q) {
        return Search.alias(q);
    }

    // Search registry + accept any `backend:tool`: the pure logic lives in MiseSearch.js.
    // `scope`: where it would be installed ("" / omitted = global); decides what counts as installed
    function search(query, scope) {
        const sc = scope || "";
        const toolsHere = toolsIn(sc);
        return Search.search(query, {
            registry: registry,
            installed: sc ? Object.keys(toolsHere) : installed.concat(missing),
            tools: toolsHere,
            remote: MiseRemote.remote,
            verified: MiseRemote.verified,
            unchecked: MiseRemote.unchecked,
            remoteSearch: MiseRemote.remoteSearch
        });
    }

    function isIgnored(name, version) {
        return ignored.includes(name) || ignored.includes(name + "@" + version);
    }

    // version "" = ignore the tool whatever the version
    // ponytail: entries for versions that were superseded are never pruned, remove them from the Ignored view
    function ignore(name, version) {
        const k = version ? name + "@" + version : name;
        if (ignored.includes(k))
            return;
        ignored = ignored.concat([k]);
        PluginService.savePluginState("mise", "ignored", ignored);
    }

    function unignore(key) {
        ignored = ignored.filter(k => k !== key);
        PluginService.savePluginState("mise", "ignored", ignored);
    }

    function clearIgnored() {
        ignored = [];
        PluginService.savePluginState("mise", "ignored", ignored);
    }

    // "npm:foo" -> "npm"; plain registry names -> "registry"
    function backendOf(name) {
        return Search.backendOf(name);
    }

    function refresh() {
        if (!checkProc.running) {
            checking = true;
            checkProc.running = true;
        }
        if (!lsProc.running)
            lsProc.running = true;
        if (!pruneProc.running)
            pruneProc.running = true;
        if (!bumpProc.running)
            bumpProc.running = true;
        MiseProjects.refresh();
    }

    // why a scope shows nothing ("" = nothing to say)
    readonly property var warnText: ({
            untrusted: "not trusted, run `mise trust` there",
            unlocked: "tools missing from the lockfile, run `mise lock` (`-g` for global)"
        })
    property bool globalUnlocked: false   // `mise outdated` skipped global tools missing from the lockfile
    function warnOf(s) {
        return s ? (MiseProjects.byScope[s] || {}).warn : globalUnlocked ? "unlocked" : "";
    }
    // the scopes of `scope` ("*" = global, then every project) that have something to fix, each with its own
    // warning (warnOf): one project can wait for a trust while another is ready to lock. [] = nothing to fix.
    function warnedScopes(scope) {
        return (scope === "*" ? [""].concat(MiseProjects.scopes) : [scope]).filter(x => warnOf(x));
    }
    function scopeWarning(scope) {
        const w = warnedScopes(scope);
        if (!w.length)
            return "";
        if (w.some(x => warnOf(x) !== warnOf(w[0])))
            return w.length + " scopes: not trusted or missing from the lockfile";
        return (w.length > 1 ? w.length + " scopes" : MiseProjects.label(w[0])) + ": " + warnText[warnOf(w[0])];
    }

    // `mise trust` on the config of a scope, or `mise lock` for its tools (`-g` for the global config), as its own
    // warning asks. `scopes` are the ones the user checked in the fix list.
    function fix(scopes) {
        const trusts = scopes.filter(s => warnOf(s) === "untrusted").length;
        const what = scopes.length > 1 ? scopes.length + " scopes" : MiseProjects.label(scopes[0]);
        const [doing, done] = trusts === scopes.length ? ["Trusting ", "Trusted "] : trusts === 0 ? ["Locking ", "Locked "] : ["Fixing ", "Fixed "];
        MiseJobs.run(["sh", "-c", Scripts.fix, "sh"].concat(scopes.reduce((a, s) => a.concat([warnOf(s), s, s ? MiseProjects.dir(s) : ""]), [])), doing + what, done + what);
    }

    // project scopes run in the project's directory, so mise reads and rewrites that config
    function inDir(scope, args) {
        return scope ? ["-C", MiseProjects.dir(scope)].concat(args) : args;
    }

    function inLabel(scope) {
        return scope ? " in " + MiseProjects.label(scope) : "";
    }

    // [{name, scope}] -> one command per scope
    function perScope(rows, args) {
        const by = {};
        rows.forEach(r => (by[r.scope || ""] = by[r.scope || ""] || []).push(r.name));
        return Object.keys(by).map(s => inDir(s, args.concat(by[s])));
    }

    // no tool = all the visible ones of `scope` (every scope when omitted), so ignored tools are not
    // upgraded behind your back
    function upgrade(tool, scope) {
        const rows = tool ? [
            {
                name: tool,
                scope: scope || ""
            }
        ] : inFilter(outdated, scope);
        if (!rows.length)
            return;
        MiseJobs.runMany(perScope(rows, ["upgrade", "--yes"]), tool ? "Upgrading " + tool + inLabel(scope) : "Upgrading all tools", tool ? "Upgraded " + tool + inLabel(scope) : "Upgraded all tools");
    }

    // rewrites the version in the config that declares the tool (global or the project's)
    function bump(tool, scope) {
        MiseJobs.run(inDir(scope, ["upgrade", "--bump", "--yes", tool]), "Bumping " + tool + inLabel(scope), "Bumped " + tool + inLabel(scope));
    }

    // only the bump-only tools: `upgrade --bump` with no args would also rewrite in-range ones
    function bumpAll(scope) {
        const rows = inFilter(bumps, scope);
        if (!rows.length)
            return;
        MiseJobs.runMany(perScope(rows, ["upgrade", "--bump", "--yes"]), "Bumping " + rows.length + " tools", "Bumped " + rows.length + " tools");
    }

    // scope "" / omitted = global config, otherwise the project's config file path
    function install(tool, scope) {
        const use = scope ? ["use", "--path", scope, "--yes", tool] : ["use", "--global", "--yes", tool];
        MiseJobs.runMany(MiseJobs.installUnlocked ? [use] : [use, lockAfterUse(tool, scope)], "Installing " + tool + inLabel(scope), "Installed " + tool + inLabel(scope), lockedInstall(tool, scope));
    }

    function lockAfterUse(tool, scope) {
        const n = bareName(tool);
        return ["sh", "-c", Scripts.lockAfterUse, "sh", scope ? MiseProjects.dir(scope) : "", n, tool.substring(n.length + 1) || "latest"];
    }

    function lockedInstall(tool, scope) {
        const n = bareName(tool);
        const v = tool.substring(n.length + 1) || "latest";
        if (!/^[\w:@\/-]+$/.test(n) || !/^[\w.-]+$/.test(v) || (tool !== n && tool[n.length] !== "@"))
            return [];
        return ["sh", "-c", Scripts.locked, "sh", scope || "", scope ? MiseProjects.dir(scope) : "", n, v];
    }

    // `npm:foo@1.2` / `foo[opt=x]` -> `npm:foo`
    function bareName(n) {
        return Search.bareName(n);
    }

    // mise's own sequence: take the tool out of that config (`unuse`), clear its entries from that scope's lockfile
    // (`lock`, only when something is stale), then `prune`: mise deletes the versions that nothing needs and keeps
    // what another tracked config, a tool stub or a running process still uses.
    function uninstall(tool, scope) {
        const unuse = scope ? ["unuse", "--path", scope, "--yes", tool] : ["unuse", "--global", "--yes", tool];
        const lock = ["sh", "-c", Scripts.lockStale, "sh", scope ? MiseProjects.dir(scope) : ""];
        MiseJobs.runMany([unuse, lock, ["prune", "--tools", "--yes", tool]], "Removing " + tool + inLabel(scope), "Removed " + tool + inLabel(scope));
    }

    // removes that one installed version; the config is not touched
    function uninstallVersion(tool, version) {
        MiseJobs.run(["uninstall", "--yes", tool + "@" + version], "Removing " + tool + "@" + version, "Removed " + tool + "@" + version);
    }

    // unused versions of one tool, or of every tool when omitted. Not scoped: `mise prune` goes by all
    // the configs mise has tracked.
    function prune(tool) {
        MiseJobs.run(["prune", "--tools", "--yes"].concat(tool ? [tool] : []), tool ? "Pruning " + tool : "Pruning unused versions", tool ? "Pruned " + tool : "Pruned unused versions");
    }

    Component.onCompleted: {
        loadSettings();
        regProc.running = true;
    }

    Timer {
        interval: root.intervalMin * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: checkProc
        command: ["mise", "outdated", "--json"]
        stderr: StdioCollector {
            onStreamFinished: root.globalUnlocked = /not in the lockfile/.test(text)
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    root.outdatedRaw = Object.keys(o).map(k => ({
                                name: o[k].name || k,
                                requested: o[k].requested || "",
                                current: o[k].current || "",
                                latest: o[k].latest || "",
                                scope: ""
                            })).sort((a, b) => a.name.localeCompare(b.name));
                    root.error = "";
                    root.lastCheck = Date.now();
                } catch (e) {
                    root.error = "Could not read `mise outdated`";
                }
            }
        }
        onExited: root.checking = false
    }

    Process {
        id: bumpProc
        command: ["mise", "outdated", "--bump", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    root.bumpRaw = Object.keys(o).map(k => ({
                                name: o[k].name || k,
                                requested: o[k].requested || "",
                                current: o[k].current || "",
                                latest: o[k].latest || "",
                                bump: o[k].bump || o[k].latest || "",
                                scope: ""
                            })).sort((a, b) => a.name.localeCompare(b.name));
                } catch (e) {}
            }
        }
    }

    Process {
        id: lsProc
        command: ["mise", "ls", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const g = Search.parseGlobalLs(JSON.parse(text));
                    root.installed = g.installed;
                    root.missing = g.missing;
                    root.versions = g.versions;
                } catch (e) {}
            }
        }
    }

    Process {
        id: pruneProc
        command: ["mise", "ls", "--prunable", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const p = {};
                    Object.keys(d).forEach(k => p[k] = d[k].map(x => x.version));
                    root.prunable = p;
                } catch (e) {}
            }
        }
    }

    Process {
        id: regProc
        command: ["mise", "registry", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.registry = JSON.parse(text).map(r => ({
                                name: r.short,
                                backend: r.backends.join(" "),
                                desc: r.description || ""
                            }));
                } catch (e) {}
            }
        }
    }
}
