pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services

// Shared state for widget + launcher. One poll, one job at a time.
Item {
    id: root

    property var outdatedRaw: []  // [{name, requested, current, latest}] as mise reports them
    property var ignored: []      // "name" (all versions) or "name@version" (skip that target version)
    readonly property var outdated: outdatedRaw.filter(t => !isIgnored(t.name, t.latest))
    property var installed: []   // ["node", "pipx:harlequin", ...]
    property var versions: ({})  // name -> active version
    property var registry: []    // [{name, backend}] ~1000 curated entries
    property bool checking: false
    property bool busy: false
    property string jobLabel: ""
    property var jobLog: []      // last lines of mise output while a job runs
    property string error: ""
    property double lastCheck: 0
    property int intervalMin: 30  // minutes between background checks (Settings)
    property bool showBumps: true // list pinned / newer-major versions too (Settings)
    property var bumpRaw: []      // `mise outdated --bump`: [{name, requested, current, latest, bump}]
    // bump-only = outdated beyond what the requested version allows; `upgrade` can't reach them
    readonly property var bumps: showBumps ? bumpRaw.filter(b => !outdatedRaw.some(o => o.name === b.name) && !isIgnored(b.name, b.bump)) : []

    function loadSettings() {
        const m = parseInt(PluginService.loadPluginData("mise", "interval", "30"));
        intervalMin = m > 0 ? m : 30;
        ignored = PluginService.loadPluginState("mise", "ignored", []) || [];
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
                root.ignored = PluginService.loadPluginState("mise", "ignored", []) || [];
        }
    }

    // Search registry + accept any `backend:tool` (pipx:, npm:, cargo:, github:, ...)
    // since the registry is only a curated subset of what mise can install.
    function search(query) {
        const raw = (query || "").trim();   // keep case: github:Owner/Repo, [opts] are case-sensitive
        const q = raw.toLowerCase();
        if (!q)
            return [];
        const out = [];
        const isInstalled = n => installed.includes(n);
        // name without `[opts]` / `@version`  (npm:@scope/pkg keeps its @)
        const bare = raw.replace(/\[.*\]$/, "").replace(/@[^/@:]*$/, "");
        const base = bare.toLowerCase();
        const c = raw.indexOf(":");
        const reg = registry.find(r => r.name === base);
        // `backend:tool`, `backend:tool@ver`, `backend:tool[opt=val]` or `registryname@ver`
        // -> passed to `mise use` as typed. Pinned/optioned entries are never "installed":
        // they (re)configure the tool.
        if (!raw.endsWith("@") && ((c > 0 && c < raw.length - 1) || (reg && bare !== raw)))
            out.push({
                name: raw,
                backend: isInstalled(bare) && bare !== raw ? "re-pin " + bare + " (now " + (versions[bare] || "?") + ")" : "direct · " + (c > 0 ? raw.substring(0, c) : reg.backend),
                installed: raw === bare && isInstalled(raw),
                direct: true
            });
        const hits = registry.filter(r => r.name.includes(base) || r.backend.toLowerCase().includes(base));
        // exact > prefix > substring > backend-only match, then shortest name
        const score = r => r.name === base ? 0 : r.name.startsWith(base) ? 1 : r.name.includes(base) ? 2 : 3;
        hits.sort((a, b) => score(a) - score(b) || a.name.length - b.name.length);
        hits.slice(0, 40).forEach(r => out.push({
                    name: r.name,
                    backend: r.backend,
                    installed: isInstalled(r.name),
                    direct: false
                }));
        return out;
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
        const i = name.indexOf(":");
        return i > 0 ? name.substring(0, i) : "registry";
    }

    function refresh() {
        if (!checkProc.running) {
            checking = true;
            checkProc.running = true;
        }
        if (!lsProc.running)
            lsProc.running = true;
        if (!bumpProc.running)
            bumpProc.running = true;
    }

    function run(args, label, doneMsg) {
        if (busy) {
            ToastService.showError("mise", "Another job is running");
            return;
        }
        jobProc.doneMsg = doneMsg;
        jobProc.command = ["mise"].concat(args);
        jobLabel = label;
        jobLog = [];
        busy = true;
        jobProc.running = true;
    }

    function upgrade(tool) {
        // "all" = the visible ones only, so ignored tools are not upgraded behind your back
        const names = tool ? [tool] : outdated.map(t => t.name);
        if (!names.length)
            return;
        run(["upgrade", "--yes"].concat(names), tool ? "Upgrading " + tool : "Upgrading all tools", tool ? "Upgraded " + tool : "Upgraded all tools");
    }

    // rewrites the version in the global config
    function bump(tool) {
        run(["upgrade", "--bump", "--yes", tool], "Bumping " + tool, "Bumped " + tool);
    }

    // only the bump-only tools: `upgrade --bump` with no args would also rewrite in-range ones
    function bumpAll() {
        run(["upgrade", "--bump", "--yes"].concat(bumps.map(b => b.name)), "Bumping " + bumps.length + " tools", "Bumped " + bumps.length + " tools");
    }

    function install(tool) {
        run(["use", "--global", "--yes", tool], "Installing " + tool, "Installed " + tool);
    }

    // removes from the global config and prunes the installed version
    function uninstall(tool) {
        run(["unuse", "--global", "--yes", tool], "Removing " + tool, "Removed " + tool);
    }

    function pushLog(line) {
        const t = line.trim();
        if (t && !t.startsWith("DEBUG"))   // MISE_VERBOSE noise
            jobLog = jobLog.concat([t]).slice(-40);
    }

    // the useful lines of a failed job (the tail is mostly mise's own "Version:/Location:" footer)
    function failureSummary() {
        const hit = jobLog.filter(l => /×|│|ERROR|failed|mismatch|not found|denied|404|403/i.test(l) && !/Version:|--verbose|BACKTRACE/i.test(l));
        return (hit.length ? hit : jobLog).slice(-4).join("\n");
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
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    root.outdatedRaw = Object.keys(o).map(k => ({
                                name: o[k].name || k,
                                requested: o[k].requested || "",
                                current: o[k].current || "",
                                latest: o[k].latest || ""
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
                                bump: o[k].bump || o[k].latest || ""
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
                    root.installed = Object.keys(d);
                    const v = {};
                    root.installed.forEach(k => v[k] = (d[k].find(x => x.active) || d[k][0] || {}).version || "");
                    root.versions = v;
                } catch (e) {}
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

    Process {
        id: jobProc
        property string doneMsg: ""
        // verbose so a failure carries the backend's own reason (aube/npm/uv...), not just "exit code 1"
        environment: ({
                MISE_VERBOSE: "1"
            })
        stdout: SplitParser {
            onRead: l => root.pushLog(l)
        }
        stderr: SplitParser {
            onRead: l => root.pushLog(l)
        }
        onExited: code => {
            root.busy = false;
            if (code === 0)
                ToastService.showInfo("mise", doneMsg);
            else
                ToastService.showError("mise failed", root.failureSummary());
            root.refresh();
        }
    }
}
