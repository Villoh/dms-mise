pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services
import "MiseScripts.js" as Scripts

// Followed projects: which mise configs count as scopes ("" is the global config elsewhere), what
// each declares and what is outdated there. Settings decides the mode; the lists are plugin state.
Item {
    id: root

    property string mode: "off"   // off | manual (your list) | tracked (mise's tracked configs + your list), Settings
    property var manual: []             // manual list: config file paths
    property var hidden: []       // tracked ones the user dropped
    property var tracked: []      // config files mise has seen (state dir), filtered
    property var byScope: ({})        // path -> {outdated: [], bump: [], tools: {name: version}}
    property string error: ""
    signal added(string path)
    signal addFailed(string message)

    function loadState() {
        manual = PluginService.loadPluginState("mise", "projects", []) || [];
        hidden = PluginService.loadPluginState("mise", "hiddenProjects", []) || [];
    }

    function loadSettings() {
        const pm = PluginService.loadPluginData("mise", "projectsMode", "off");
        mode = pm === "manual" || pm === "tracked" ? pm : "off";
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === "mise")
                root.loadSettings();
        }
        // the Settings page edits the project lists too
        function onPluginStateChanged(pluginId) {
            if (pluginId === "mise" && !root.saving)
                root.loadState();
        }
    }

    Component.onCompleted: {
        loadSettings();
        loadState();
    }

    onModeChanged: refresh()
    onScopesChanged: projReload.restart()

    readonly property var scopes: {
        if (mode === "off")
            return [];
        const out = [];
        const add = p => {
            if (!out.includes(p))
                out.push(p);
        };
        if (mode === "tracked")
            tracked.filter(p => !hidden.includes(p)).forEach(add);
        manual.forEach(add);
        return out;
    }
    readonly property var outdated: scopes.reduce((a, s) => a.concat((byScope[s] || {}).outdated || []), [])
    readonly property var bumps: scopes.reduce((a, s) => a.concat((byScope[s] || {}).bump || []), [])

    // ---- project helpers ----
    // directory mise should run in for a config file (`<dir>/.config/mise/config.toml` belongs to <dir>)
    function dir(p) {
        const i = p.lastIndexOf("/");
        const d = p.substring(0, i) || "/";
        return p.substring(i + 1) === "config.toml" ? (d.replace(/\/(\.config\/mise|\.mise|mise)$/, "") || "/") : d;
    }

    function baseName(d) {
        return d.substring(d.lastIndexOf("/") + 1) || d;
    }

    // folder name; `name (parent)` when two followed manual share it
    function label(scope) {
        if (!scope)
            return "global";
        const d = dir(scope);
        const l = baseName(d);
        const dup = scopes.some(o => o !== scope && baseName(dir(o)) === l);
        return dup ? l + " (" + baseName(d.substring(0, d.lastIndexOf("/"))) + ")" : l;
    }

    // Two saves, and each one fires onPluginStateChanged synchronously: reloading in between would
    // overwrite the in-memory list that is not saved yet with the stale one from disk
    property bool saving: false
    function savePaths() {
        saving = true;
        PluginService.savePluginState("mise", "projects", manual);
        PluginService.savePluginState("mise", "hiddenProjects", hidden);
        saving = false;
    }

    // the file browser may hand back file:// URLs
    function plainPath(p) {
        return p.startsWith("file://") ? decodeURIComponent(p.substring(7)) : p;
    }

    // `input`: a project folder or a config file; checked and resolved by resolveProc
    function add(input) {
        const p = (input || "").trim();
        if (!p || resolveProc.running)
            return;
        error = "";
        resolveProc.command = ["sh", "-c", Scripts.resolve, "sh", p];
        resolveProc.running = true;
    }

    function commitProject(p) {
        if (!manual.includes(p))
            manual = manual.concat([p]);
        hidden = hidden.filter(h => h !== p);
        savePaths();
        added(p);
    }

    // stop following: drops it from your list, hides it if mise tracked it. Never touches the config file.
    function remove(p) {
        manual = manual.filter(x => x !== p);
        if (tracked.includes(p) && !hidden.includes(p))
            hidden = hidden.concat([p]);
        savePaths();
    }

    function show(p) {
        hidden = hidden.filter(h => h !== p);
        savePaths();
    }

    function refresh() {
        if (mode === "tracked") {
            if (!trackedProc.running)
                trackedProc.running = true;   // its answer changes `scopes`, which reloads
        } else {
            projReload.restart();
        }
    }

    function load() {
        if (!scopes.length) {
            byScope = ({});
            return;
        }
        if (projProc.running) {
            projReload.restart();
            return;
        }
        projProc.acc = ({});
        projProc.command = ["sh", "-c", Scripts.project, "sh"].concat(scopes.reduce((a, s) => a.concat([s, dir(s)]), []));
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

    Timer {
        id: projReload
        interval: 300
        onTriggered: root.load()
    }

    Process {
        id: trackedProc
        command: ["sh", "-c", Scripts.tracked]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").filter(x => x.trim());
                const home = l.shift() || "";
                // global config and scratch files are not manual
                const ps = l.filter((p, i) => l.indexOf(p) === i && !p.startsWith("/tmp/") && !p.startsWith("/etc/mise") && !p.startsWith(home + "/.config/mise/"));
                if (JSON.stringify(ps) !== JSON.stringify(root.tracked))
                    root.tracked = ps;
                else
                    projReload.restart();   // same manual, but their tools may have changed
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
                root.byScope = projProc.acc;
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
                    root.error = m;
                    root.addFailed(m);
                }
            }
        }
    }
}
