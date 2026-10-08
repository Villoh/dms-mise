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
    readonly property var outdated: outdatedRaw.concat(projectOutdated).filter(t => !isIgnored(t.name, t.latest))
    property var installed: []   // really installed: ["node", "pipx:harlequin", ...]
    property var missing: []     // declared in the global config but not installed (mise lists them too)
    property var versions: ({})  // name -> active version
    property var prunable: ({})  // name -> [versions] no tracked config uses (`mise ls --prunable`)
    readonly property int prunableCount: Object.keys(prunable).reduce((n, k) => n + prunable[k].length, 0)
    property var registry: []    // [{name, backend}] ~1000 curated entries
    property bool checking: false
    property string error: ""
    property double lastCheck: 0
    property int intervalMin: 30  // minutes between background checks (Settings)
    property bool showBumps: true // list pinned / newer-major versions too (Settings)
    property var bumpRaw: []      // `mise outdated --bump`: [{name, requested, current, latest, bump}]
    // ---- scopes: "" = global config, otherwise the path of a project's mise config file ----
    property string projectsMode: "off"   // off | manual (your list) | tracked (mise's tracked configs + your list), Settings
    property var projects: []             // manual list: config file paths
    property var hiddenProjects: []       // tracked ones the user dropped
    property var trackedProjects: []      // config files mise has seen (state dir), filtered
    property var projectData: ({})        // path -> {outdated: [], bump: [], tools: {name: version}}
    property string projectError: ""
    signal projectAdded(string path)
    signal projectAddFailed(string message)
    readonly property var scopes: {
        if (projectsMode === "off")
            return [];
        const out = [];
        const add = p => {
            if (!out.includes(p))
                out.push(p);
        };
        if (projectsMode === "tracked")
            trackedProjects.filter(p => !hiddenProjects.includes(p)).forEach(add);
        projects.forEach(add);
        return out;
    }
    readonly property var projectOutdated: scopes.reduce((a, s) => a.concat((projectData[s] || {}).outdated || []), [])
    readonly property var projectBumps: scopes.reduce((a, s) => a.concat((projectData[s] || {}).bump || []), [])

    // bump-only = outdated beyond what the requested version allows; `upgrade` can't reach them
    readonly property var bumps: showBumps ? bumpRaw.concat(projectBumps).filter(b => !outdatedRaw.concat(projectOutdated).some(o => o.name === b.name && o.scope === b.scope) && !isIgnored(b.name, b.bump)) : []

    // bar badge: "global" (default) or "all" (global + followed projects)
    property string badgeScope: "global"
    readonly property var badgeOutdated: inFilter(outdated, badgeScope === "all" ? "*" : "")
    readonly property var badgeBumps: inFilter(bumps, badgeScope === "all" ? "*" : "")

    function loadState() {
        ignored = PluginService.loadPluginState("mise", "ignored", []) || [];
        projects = PluginService.loadPluginState("mise", "projects", []) || [];
        hiddenProjects = PluginService.loadPluginState("mise", "hiddenProjects", []) || [];
    }

    function loadSettings() {
        const m = parseInt(PluginService.loadPluginData("mise", "interval", "30"));
        intervalMin = m > 0 ? m : 30;
        loadState();
        const pm = PluginService.loadPluginData("mise", "projectsMode", "off");
        projectsMode = pm === "manual" || pm === "tracked" ? pm : "off";
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
        // the Settings page edits the ignored and project lists too
        function onPluginStateChanged(pluginId) {
            if (pluginId === "mise" && !root.saving)
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

    onProjectsModeChanged: refreshProjects()
    onScopesChanged: projReload.restart()

    // ---- project helpers ----
    // directory mise should run in for a config file (`<dir>/.config/mise/config.toml` belongs to <dir>)
    function projectDir(p) {
        const i = p.lastIndexOf("/");
        const d = p.substring(0, i) || "/";
        return p.substring(i + 1) === "config.toml" ? (d.replace(/\/(\.config\/mise|\.mise|mise)$/, "") || "/") : d;
    }

    function baseName(d) {
        return d.substring(d.lastIndexOf("/") + 1) || d;
    }

    // folder name; `name (parent)` when two followed projects share it
    function scopeLabel(scope) {
        if (!scope)
            return "global";
        const d = projectDir(scope);
        const l = baseName(d);
        const dup = scopes.some(o => o !== scope && baseName(projectDir(o)) === l);
        return dup ? l + " (" + baseName(d.substring(0, d.lastIndexOf("/"))) + ")" : l;
    }

    // "*" / undefined = every scope
    function inFilter(rows, scope) {
        return scope === undefined || scope === "*" ? rows : rows.filter(r => r.scope === scope);
    }

    function toolsIn(scope) {
        return scope ? ((projectData[scope] || {}).tools || {}) : versions;
    }

    function installedIn(scope) {
        return scope ? Object.keys(toolsIn(scope)).filter(n => !missingIn(scope).includes(n)).sort() : installed;
    }

    // declared in that config, not installed yet: `mise upgrade <tool>` installs the declared version
    function missingIn(scope) {
        return scope ? Object.keys((projectData[scope] || {}).missing || {}).sort() : missing;
    }

    // Two saves, and each one fires onPluginStateChanged synchronously: reloading in between would
    // overwrite the in-memory list that is not saved yet with the stale one from disk
    property bool saving: false
    function savePaths() {
        saving = true;
        PluginService.savePluginState("mise", "projects", projects);
        PluginService.savePluginState("mise", "hiddenProjects", hiddenProjects);
        saving = false;
    }

    // the file browser may hand back file:// URLs
    function plainPath(p) {
        return p.startsWith("file://") ? decodeURIComponent(p.substring(7)) : p;
    }

    // `input`: a project folder or a config file; checked and resolved by resolveProc
    function addProject(input) {
        const p = (input || "").trim();
        if (!p || resolveProc.running)
            return;
        projectError = "";
        resolveProc.command = ["sh", "-c", Scripts.resolve, "sh", p];
        resolveProc.running = true;
    }

    function commitProject(p) {
        if (!projects.includes(p))
            projects = projects.concat([p]);
        hiddenProjects = hiddenProjects.filter(h => h !== p);
        savePaths();
        projectAdded(p);
    }

    // stop following: drops it from your list, hides it if mise tracked it. Never touches the config file.
    function removeProject(p) {
        projects = projects.filter(x => x !== p);
        if (trackedProjects.includes(p) && !hiddenProjects.includes(p))
            hiddenProjects = hiddenProjects.concat([p]);
        savePaths();
    }

    function showProject(p) {
        hiddenProjects = hiddenProjects.filter(h => h !== p);
        savePaths();
    }

    function refreshProjects() {
        if (projectsMode === "tracked") {
            if (!trackedProc.running)
                trackedProc.running = true;   // its answer changes `scopes`, which reloads
        } else {
            projReload.restart();
        }
    }

    function loadProjects() {
        if (!scopes.length) {
            projectData = ({});
            return;
        }
        if (projProc.running) {
            projReload.restart();
            return;
        }
        projProc.acc = ({});
        projProc.command = ["sh", "-c", Scripts.project, "sh"].concat(scopes.reduce((a, s) => a.concat([s, projectDir(s)]), []));
        projProc.running = true;
    }

    function parseProjLine(l) {
        const a = l.indexOf("\t");
        const b = l.indexOf("\t", a + 1);
        if (a < 0 || b < 0)
            return;
        const kind = l.substring(0, a);
        const path = l.substring(a + 1, b);
        let d;
        try {
            d = JSON.parse(l.substring(b + 1));
        } catch (e) {
            return;
        }
        const acc = projProc.acc;
        const e = acc[path] || (acc[path] = {
                outdated: [],
                bump: [],
                tools: {},
                missing: {},
                warn: ""
            });
        if (kind === "warn") {
            e.warn = d;
            return;
        }
        // `mise` run in a project also reports the global tools: keep only what this config declares
        if (kind === "ls") {
            Object.keys(d).forEach(n => {
                const own = (d[n] || []).filter(x => x.source && x.source.path === path);
                const x = own.find(y => y.active) || own[0];
                if (!x)
                    return;
                e.tools[n] = x.version || x.requested_version || "";
                if (!own.some(y => y.installed))
                    e.missing[n] = true;
            });
            return;
        }
        const rows = Object.keys(d).filter(k => (d[k].name || k) in e.tools).map(k => ({
                    name: d[k].name || k,
                    requested: d[k].requested || "",
                    current: d[k].current || "",
                    latest: d[k].latest || "",
                    bump: d[k].bump || d[k].latest || "",
                    scope: path
                })).sort((x, y) => x.name.localeCompare(y.name));
        if (kind === "outdated")
            e.outdated = rows;
        else if (kind === "bump")
            e.bump = rows;
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
            remoteSearch: MiseRemote.enabled
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
        refreshProjects();
    }

    // why a scope shows nothing ("" = nothing to say); `*` = the first project that has a reason
    readonly property var warnText: ({
            untrusted: "not trusted, run `mise trust` there",
            unlocked: "tools missing from its lockfile, run `mise lock` (`-g` for global)"
        })
    property bool globalUnlocked: false   // `mise outdated` skipped global tools missing from the lockfile
    function warnOf(s) {
        return s ? (projectData[s] || {}).warn : globalUnlocked ? "unlocked" : "";
    }
    // the first scope of `scope` ("*" = global, then every project) with something to say; undefined = none
    function warnedScope(scope) {
        return (scope === "*" ? [""].concat(scopes) : [scope]).find(x => warnOf(x));
    }
    function scopeWarning(scope) {
        const s = warnedScope(scope);
        return s === undefined ? "" : scopeLabel(s) + ": " + warnText[warnOf(s)];
    }

    // what the warning of a scope asks for, as a button would run it: `mise trust` on the project's config, or
    // `mise lock` for its tools (`-g` for the global config). Only ever called from a button that asks twice.
    function fix(scope) {
        if (warnOf(scope) === "untrusted")
            MiseJobs.run(["trust", scope], "Trusting " + scopeLabel(scope), "Trusted " + scopeLabel(scope));
        else
            MiseJobs.run(scope ? ["-C", projectDir(scope), "lock"] : ["lock", "-g"], "Locking " + scopeLabel(scope), "Locked " + scopeLabel(scope));
    }

    // project scopes run in the project's directory, so mise reads and rewrites that config
    function inDir(scope, args) {
        return scope ? ["-C", projectDir(scope)].concat(args) : args;
    }

    function inLabel(scope) {
        return scope ? " in " + scopeLabel(scope) : "";
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
        return ["sh", "-c", Scripts.lockAfterUse, "sh", scope ? projectDir(scope) : "", bareName(tool)];
    }

    function lockedInstall(tool, scope) {
        const n = bareName(tool);
        const v = tool.substring(n.length + 1) || "latest";
        if (!/^[\w:@\/-]+$/.test(n) || !/^[\w.-]+$/.test(v) || (tool !== n && tool[n.length] !== "@"))
            return [];
        return ["sh", "-c", Scripts.locked, "sh", scope || "", scope ? projectDir(scope) : "", n, v];
    }

    // `npm:foo@1.2` / `foo[opt=x]` -> `npm:foo`
    function bareName(n) {
        return Search.bareName(n);
    }

    // removes from that config and prunes the installed version
    function uninstall(tool, scope) {
        MiseJobs.run(scope ? ["unuse", "--path", scope, "--yes", tool] : ["unuse", "--global", "--yes", tool], "Removing " + tool + inLabel(scope), "Removed " + tool + inLabel(scope));
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
                    const d = JSON.parse(text);
                    const keys = Object.keys(d);
                    const has = k => d[k].some(x => x.installed);
                    root.installed = keys.filter(has);
                    root.missing = keys.filter(k => !has(k));
                    const v = {};
                    keys.forEach(k => v[k] = (d[k].find(x => x.active) || d[k][0] || {}).version || "");
                    root.versions = v;
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

    Timer {
        id: projReload
        interval: 300
        onTriggered: root.loadProjects()
    }

    Process {
        id: trackedProc
        command: ["sh", "-c", Scripts.tracked]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").filter(x => x.trim());
                const home = l.shift() || "";
                // global config and scratch files are not projects
                const ps = l.filter((p, i) => l.indexOf(p) === i && !p.startsWith("/tmp/") && !p.startsWith("/etc/mise") && !p.startsWith(home + "/.config/mise/"));
                if (JSON.stringify(ps) !== JSON.stringify(root.trackedProjects))
                    root.trackedProjects = ps;
                else
                    projReload.restart();   // same projects, but their tools may have changed
            }
        }
    }

    Process {
        id: projProc
        property var acc: ({})
        // the whole output, not line by line: `exited` can fire before the last lines are read
        stdout: StdioCollector {
            onStreamFinished: {
                projProc.acc = ({});
                text.split("\n").forEach(l => root.parseProjLine(l));
                root.projectData = projProc.acc;
            }
        }
    }

    Process {
        id: resolveProc
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p)
                    root.commitProject(p);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const m = text.trim();
                if (m) {
                    root.projectError = m;
                    root.projectAddFailed(m);
                }
            }
        }
    }

    Process {
        id: regProc
        command: ["mise", "registry"]
        stdout: StdioCollector {
            onStreamFinished: root.registry = text.split("\n").filter(l => l.trim()).map(l => {
                const p = l.trim().split(/\s+/);
                return {
                    name: p[0],
                    backend: p.slice(1).join(" ")
                };
            })
        }
    }
}
