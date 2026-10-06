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
    property bool remoteSearch: true  // query npm / crates.io / GitHub as you type (Settings)
    property string lookupQ: ""       // last query handed to lookup()
    property var remoteHits: ({})     // backend -> [{name: "npm:foo", backend, desc}], from the last answer
    readonly property var remote: Object.keys(searchers).reduce((a, k) => a.concat(remoteHits[k] || []), [])
    property var verified: ({})       // "npm:foo" -> {ok, desc}; absent = not checked yet / network error
    // debounce pending or a request in flight: UIs show a "searching" hint.
    // A plain flag (see settle()), not a binding on Timer.running: restart() flips that false->true on
    // every keystroke and the UI would blink.
    property bool lookingUp: false
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
        const r = PluginService.loadPluginData("mise", "remoteSearch", true);
        remoteSearch = !(r === false || r === "false");
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
        if (!raw.endsWith("@") && ((c > 0 && c < raw.length - 1) || (reg && bare !== raw))) {
            const v = verified[bare];
            const note = v ? (v.ok ? " · ✓" + (v.desc ? " " + v.desc : "") : " · ✗ not found") : "";
            out.push({
                name: raw,
                backend: (isInstalled(bare) && bare !== raw ? "re-pin " + bare + " (now " + (versions[bare] || "?") + ")" : "direct · " + (c > 0 ? raw.substring(0, c) : reg.backend)) + note,
                installed: raw === bare && isInstalled(raw),
                direct: true
            });
        }
        const hits = registry.filter(r => r.name.includes(base) || r.backend.toLowerCase().includes(base));
        // exact > prefix > substring > backend-only match, then shortest name
        const score = r => r.name === base ? 0 : r.name.startsWith(base) ? 1 : r.name.includes(base) ? 2 : 3;
        hits.sort((a, b) => score(a) - score(b) || a.name.length - b.name.length);
        hits.slice(0, 12).forEach(r => out.push({
                    name: r.name,
                    backend: r.backend,
                    installed: isInstalled(r.name),
                    direct: false
                }));
        // remote hits for what is being typed: free text -> backends marked `free`, `backend:q` -> that one.
        // Older hits that still match stay visible while the next request is in flight.
        const b = c > 0 ? base.substring(0, c) : "";
        const term = c > 0 ? base.substring(c + 1) : base;
        const cap = b ? maxPrefixed : maxFree;   // per backend
        const seen = {};
        if (remoteSearch && term)
            remote.filter(r => (b ? r.backend === b : searchers[r.backend].free) && r.name.toLowerCase().includes(term) && r.name !== raw && !out.some(o => o.name === r.name) && (seen[r.backend] = (seen[r.backend] || 0) + 1) <= cap).forEach(r => out.push({
                        name: r.name,
                        backend: r.backend + " · " + r.desc,
                        installed: isInstalled(r.name),
                        direct: false
                    }));
        return out;
    }

    // ---- remote lookup: search package sites, verify a typed backend:tool ----
    readonly property int maxFree: 5        // hits per backend for free text (no prefix)
    readonly property int maxPrefixed: 15   // hits for `backend:query`

    // Backends we can search. `free` = also searched for plain text; the rest only after their
    // prefix, or free text would drown in results (and GitHub allows 10 searches/min unauthenticated).
    // Not searchable (no usable API): go, aqua, gitlab, ubi, spm, http, s3, asdf, vfox.
    readonly property var searchers: ({
            npm: {
                free: true,
                url: (t, n) => "https://registry.npmjs.org/-/v1/search?size=" + n + "&text=" + encodeURIComponent(t),
                parse: j => (j.objects || []).map(o => ({
                            name: o.package.name,
                            desc: o.package.description
                        }))
            },
            cargo: {
                free: true,
                url: (t, n) => "https://crates.io/api/v1/crates?per_page=" + n + "&q=" + encodeURIComponent(t),
                parse: j => (j.crates || []).map(o => ({
                            name: o.name,
                            desc: o.description
                        }))
            },
            github: {
                free: false,
                url: (t, n) => t.includes("/") ? "" : "https://api.github.com/search/repositories?per_page=" + n + "&q=" + encodeURIComponent(t),
                parse: j => (j.items || []).map(o => ({
                            name: o.full_name,
                            desc: o.description
                        }))
            },
            // anaconda.org searches every channel at once (up to 100 hits, 1-3 s) and ignores channel
            // filters: keep conda-forge, the channel mise installs from, best match first
            conda: {
                free: false,
                url: (t, n) => "https://api.anaconda.org/search?name=" + encodeURIComponent(t),
                parse: (j, t) => {
                    const q = t.toLowerCase();
                    const score = n => n === q ? 0 : n.startsWith(q) ? 1 : 2;
                    return (Array.isArray(j) ? j : []).filter(o => o.owner === "conda-forge").sort((a, b) => score(a.name) - score(b.name) || a.name.length - b.name.length).map(o => ({
                                name: o.name,
                                desc: o.summary
                            }));
                }
            },
            gem: {
                free: false,
                url: (t, n) => "https://rubygems.org/api/v1/search.json?query=" + encodeURIComponent(t),
                parse: j => (Array.isArray(j) ? j : []).map(o => ({
                            name: o.name,
                            desc: o.info
                        }))
            },
            dotnet: {
                free: false,
                url: (t, n) => "https://azuresearch-usnc.nuget.org/query?take=" + n + "&q=" + encodeURIComponent(t),
                parse: j => (j.data || []).map(o => ({
                            name: o.id,
                            desc: o.description
                        }))
            }
        })

    // Exact-name check for `backend:tool`: URL that answers 200 if it exists, 404 if not ("" = cannot check).
    readonly property var verifiers: ({
            npm: t => "https://registry.npmjs.org/" + encodeURIComponent(t) + "/latest",
            cargo: t => "https://crates.io/api/v1/crates/" + encodeURIComponent(t),
            pipx: t => "https://pypi.org/pypi/" + encodeURIComponent(t) + "/json",
            pypi: t => "https://pypi.org/pypi/" + encodeURIComponent(t) + "/json",
            gem: t => "https://rubygems.org/api/v1/gems/" + encodeURIComponent(t) + ".json",
            conda: t => "https://api.anaconda.org/package/conda-forge/" + encodeURIComponent(t),
            dotnet: t => "https://api.nuget.org/v3-flatcontainer/" + encodeURIComponent(t.toLowerCase()) + "/index.json",
            // module path: capitals are escaped as !lower in the proxy protocol
            go: t => "https://proxy.golang.org/" + t.replace(/[A-Z]/g, c => "!" + c.toLowerCase()) + "/@latest",
            // the aqua registry is a folder per owner/repo
            aqua: t => /^[^/]+\/[^/]+/.test(t) ? "https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/" + t + "/registry.yaml" : "",
            github: t => /^[^/]+\/[^/]+$/.test(t) ? "https://api.github.com/repos/" + t : "",
            ubi: t => /^[^/]+\/[^/]+$/.test(t) ? "https://api.github.com/repos/" + t : "",
            spm: t => /^[^/]+\/[^/]+$/.test(t) ? "https://api.github.com/repos/" + t : "",
            gitlab: t => t.includes("/") ? "https://gitlab.com/api/v4/projects/" + encodeURIComponent(t) : ""
        })

    // Call from the UI whenever the query changes; debounced, one request per backend at a time.
    function lookup(raw) {
        const q = (raw || "").trim();
        if (q === lookupQ)
            return;
        lookupQ = q;
        if (!q)
            remoteHits = ({});
        if (remoteSearch && q.length >= 2)
            lookingUp = true;
        lookupTimer.restart();
        if (!lookupTimer.running || q.length < 2)
            settle();
    }

    // clear lookingUp once the debounce is over and no request is in flight
    function settle() {
        lookingUp = remoteSearch && lookupQ.length >= 2 && (lookupTimer.running || verifyFetch.running || Object.keys(searchers).some(k => fetchers[k].running));
    }

    // what to ask the network for this query
    function fetchRemote() {
        const q = lookupQ;
        if (!remoteSearch || q.length < 2)
            return;
        const bare = q.replace(/\[.*\]$/, "").replace(/@[^/@:]*$/, "");
        const c = bare.indexOf(":");
        const b = c > 0 ? bare.substring(0, c) : "";
        const t = c > 0 ? bare.substring(c + 1) : bare;
        // typed backend:tool -> does it exist? (git+/URL specs are not checked)
        if (t && verifiers[b] && !verified[bare] && !/:\/\/|^git\+/.test(t)) {
            const u = verifiers[b](t);
            if (u)
                verifyFetch.start(u, bare);
        }
        // `@scope/...` and paths are not search terms
        if (t.length < 3 || /^[@/]|:\/\//.test(t))
            return;
        // always ask, even when the registry has the name: skipping would leave the hits of an
        // earlier, shorter query on screen and the list would depend on how you typed
        const n = b ? maxPrefixed : maxFree;
        Object.keys(searchers).forEach(k => {
            if (b ? b !== k : !searchers[k].free)
                return;
            const u = searchers[k].url(t, n);
            if (u)
                fetchers[k].start(u, t);
        });
    }

    // answer of a search request
    function gotHits(b, status, json, term) {
        if (status !== 200 || !json)
            return;
        const m = Object.assign({}, remoteHits);
        m[b] = searchers[b].parse(json, term).slice(0, maxPrefixed).map(h => ({
                    name: b + ":" + h.name,
                    backend: b,
                    desc: h.desc || ""
                }));
        remoteHits = m;
    }

    // 200 = exists, 404 = does not; anything else (offline, rate limit) stays unknown
    function gotVerify(tool, status, j) {
        if (status !== 200 && status !== 404)
            return;
        const info = j ? j.info : null;
        const d = j ? (j.description || (typeof info === "string" ? info : info && info.summary) || j.summary || (j.crate && j.crate.description) || "") : "";
        const v = Object.assign({}, verified);
        v[tool] = {
            ok: status === 200,
            desc: String(d).trim().replace(/\s+/g, " ").substring(0, 80)
        };
        verified = v;
    }

    Timer {
        id: lookupTimer
        interval: 350
        onTriggered: {
            root.fetchRemote();
            root.settle();
        }
    }

    // one curl at a time; a request that arrives meanwhile waits and replaces any older waiting one.
    // stdout = body + "\n" + http status (000 = network failure). backend "" = verification.
    component Fetch: Process {
        id: f
        property string backend: ""
        property string want: ""
        property string waitUrl: ""
        property string waitWant: ""
        function start(url, w) {
            if (running) {
                waitUrl = url;
                waitWant = w;
                return;
            }
            want = w;
            command = ["curl", "-s", "--max-time", "6", "-A", "dms-mise-plugin", "-w", "\n%{http_code}", url];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const i = text.lastIndexOf("\n");
                let j = null;
                try {
                    j = JSON.parse(text.substring(0, i));
                } catch (e) {}
                const s = parseInt(text.substring(i + 1)) || 0;
                if (f.backend)
                    root.gotHits(f.backend, s, j, f.want);
                else
                    root.gotVerify(f.want, s, j);
            }
        }
        onExited: {
            if (waitUrl) {
                const u = waitUrl, w = waitWant;
                waitUrl = "";
                start(u, w);
            }
            root.settle();
        }
    }

    Fetch {
        id: verifyFetch
    }
    Fetch {
        id: npmFetch
        backend: "npm"
    }
    Fetch {
        id: cargoFetch
        backend: "cargo"
    }
    Fetch {
        id: githubFetch
        backend: "github"
    }
    Fetch {
        id: condaFetch
        backend: "conda"
    }
    Fetch {
        id: gemFetch
        backend: "gem"
    }
    Fetch {
        id: dotnetFetch
        backend: "dotnet"
    }
    readonly property var fetchers: ({
            npm: npmFetch,
            cargo: cargoFetch,
            github: githubFetch,
            conda: condaFetch,
            gem: gemFetch,
            dotnet: dotnetFetch
        })

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
