pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services

// Shared state for widget + launcher. One poll, one job at a time.
Item {
    id: root

    property var outdatedRaw: []  // [{name, requested, current, latest}] as mise reports them
    property var ignored: []      // "name" (all versions) or "name@version" (skip that target version)
    readonly property var outdated: outdatedRaw.concat(projectOutdated).filter(t => !isIgnored(t.name, t.latest))
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
        const r = PluginService.loadPluginData("mise", "remoteSearch", true);
        remoteSearch = !(r === false || r === "false");
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
        return scope ? Object.keys(toolsIn(scope)).sort() : installed;
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
        resolveProc.command = ["sh", "-c", resolveScript, "sh", p];
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
        projProc.command = ["sh", "-c", projScript, "sh"].concat(scopes.reduce((a, s) => a.concat([s, projectDir(s)]), []));
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
            tools: {}
        });
        // `mise` run in a project also reports the global tools: keep only what this config declares
        if (kind === "ls") {
            Object.keys(d).forEach(n => {
                const own = (d[n] || []).filter(x => x.source && x.source.path === path);
                const x = own.find(y => y.active) || own[0];
                if (x)
                    e.tools[n] = x.version || x.requested_version || "";
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

    // one line per call: `<kind>\t<config>\t<json on one line>`; args come in (config, dir) pairs
    readonly property string projScript: 'while [ $# -gt 1 ]; do f=$1; d=$2; shift 2\n' + 'for k in ls outdated bump; do\n' + 'case $k in ls) a="ls --json";; outdated) a="outdated --json";; bump) a="outdated --bump --json";; esac\n' + 'printf "%s\\t%s\\t" "$k" "$f"; mise -C "$d" $a 2>/dev/null | tr -d "\\n"; printf "\\n"\n' + 'done; done'

    // first line: $HOME; then every tracked config file that still exists
    readonly property string trackedScript: 'd="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/tracked-configs"\n' + 'echo "$HOME"\n' + 'for f in "$d"/*; do [ -L "$f" ] || continue; p=$(readlink -f "$f") && [ -f "$p" ] && echo "$p"; done'

    // folder or file -> absolute config file path; error text on stderr
    readonly property string resolveScript: 'p=$1\n' + 'case "$p" in "~"|"~/"*) p="$HOME${p#"~"}";; esac\n' + 'g="${MISE_GLOBAL_CONFIG_FILE:-$HOME/.config/mise/config.toml}"\n' + 'ok() { r=$(readlink -f "$1"); [ "$r" = "$(readlink -f "$g")" ] && { echo "That is the global config" >&2; exit 1; }; echo "$r"; exit 0; }\n' + '[ -f "$p" ] && ok "$p"\n' + '[ -d "$p" ] || { echo "Not found: $1" >&2; exit 1; }\n' + 'for c in mise.toml .mise.toml mise/config.toml .mise/config.toml .config/mise.toml .config/mise/config.toml; do [ -f "$p/$c" ] && ok "$p/$c"; done\n' + 'echo "No mise config in $1" >&2; exit 1'

    // Search registry + accept any `backend:tool` (pipx:, npm:, cargo:, github:, ...)
    // since the registry is only a curated subset of what mise can install.
    // `scope`: where it would be installed ("" / omitted = global); decides what counts as installed
    function search(query, scope) {
        const sc = scope || "";
        const toolsHere = toolsIn(sc);
        const raw = (query || "").trim();   // keep case: github:Owner/Repo, [opts] are case-sensitive
        const q = raw.toLowerCase();
        if (!q)
            return [];
        const out = [];
        const isInstalled = n => sc ? n in toolsHere : installed.includes(n);
        // name without `[opts]` / `@version`  (npm:@scope/pkg keeps its @)
        const bare = raw.replace(/\[.*\]$/, "").replace(/@[^/@:]*$/, "");
        const base = bare.toLowerCase();
        const c = raw.indexOf(":");
        const b = c > 0 ? base.substring(0, c) : "";
        const term = c > 0 ? base.substring(c + 1) : base;
        const reg = registry.find(r => r.name === base);
        // plain `backend:name` that a remote hit matches: fold the hit into the direct row (canonical
        // name, description) instead of listing the same package twice. crates.io treats - and _ alike.
        const norm = b === "cargo" ? x => x.replace(/_/g, "-") : (b === "pipx" || b === "pypi") ? x => x.replace(/[-_.]+/g, "-") : x => x;
        const same = (x, y) => norm(x) === norm(y);
        const exact = remoteSearch && b && raw === bare ? remote.find(r => r.backend === b && same(r.name.toLowerCase(), base)) : null;
        // `backend:tool`, `backend:tool@ver`, `backend:tool[opt=val]` or `registryname@ver`
        // -> passed to `mise use` as typed. Pinned/optioned entries are never "installed":
        // they (re)configure the tool.
        if (!raw.endsWith("@") && ((c > 0 && c < raw.length - 1) || (reg && bare !== raw))) {
            // a hit proves the package exists, even when the exact-name check said 404 (npm and gem
            // names are case-sensitive: `npm:Playwright` is not found, `npm:playwright` is)
            const vf = verified[bare];
            const v = exact ? {
                ok: true,
                desc: (vf && vf.ok && vf.desc) || exact.desc || ""
            } : vf;
            const name = exact ? exact.name : raw;
            const note = v ? (v.ok ? " · ✓" + (v.desc ? " " + v.desc : "") : " · ✗ not found") : "";
            out.push({
                name: name,
                backend: (isInstalled(bare) && bare !== raw ? "re-pin " + bare + " (now " + (toolsHere[bare] || "?") + ")" : "direct · " + (c > 0 ? raw.substring(0, c) : reg.backend)) + note,
                installed: raw === bare && isInstalled(name),
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
    // Not searchable (no usable API): aqua, gitlab, ubi, spm, http, s3, asdf, vfox.
    readonly property var searchers: ({
            npm: {
                free: true,
                // lowercase: npm ranks case-sensitively (`Playwright` does not list `playwright` in the top 5)
                // and new package names are always lowercase. Legacy `JSONStream`-style names are still
                // found by typing them exactly (exact-name check).
                url: (t, n) => "https://registry.npmjs.org/-/v1/search?size=" + n + "&text=" + encodeURIComponent(t.toLowerCase()),
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
            // PyPI and Go have no search API: use the one behind deps.dev's own website (Google's Open
            // Source Insights). Unofficial and undocumented, may change without notice.
            pipx: depsDev("pypi"),
            pypi: depsDev("pypi"),
            go: depsDev("go"),
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
        lookingUp = remoteSearch && lookupQ.length >= 2 && (lookupTimer.running || verifyFetch.running || Object.keys(fetchers).some(k => fetchers[k].running));
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

    // searcher for one deps.dev ecosystem; results mix packages and GitHub projects, keep the packages
    function depsDev(system) {
        return {
            free: false,
            url: (t, n) => "https://deps.dev/_/search?q=" + encodeURIComponent(t) + "&system=" + system,
            parse: j => (j.results || []).filter(r => r.kind === "PACKAGE").map(r => ({
                        name: r.name,
                        desc: r.defaultVersion ? "latest " + r.defaultVersion : ""
                    }))
        };
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
            command = ["curl", "-sL", "--max-time", "6", "-A", "dms-mise-plugin", "-w", "\n%{http_code}", url];
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
        id: pipxFetch
        backend: "pipx"
    }
    Fetch {
        id: pypiFetch
        backend: "pypi"
    }
    Fetch {
        id: goFetch
        backend: "go"
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
            pipx: pipxFetch,
            pypi: pypiFetch,
            go: goFetch,
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
        refreshProjects();
    }

    function run(args, label, doneMsg) {
        runMany([args], label, doneMsg);
    }

    // commands run one after another; the first failure stops the rest
    function runMany(cmds, label, doneMsg) {
        if (busy) {
            ToastService.showError("mise", "Another job is running");
            return;
        }
        jobProc.doneMsg = doneMsg;
        jobProc.queue = cmds.slice(1);
        jobProc.command = ["mise"].concat(cmds[0]);
        jobLabel = label;
        jobLog = [];
        busy = true;
        jobProc.running = true;
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
        const rows = tool ? [{
                    name: tool,
                    scope: scope || ""
                }] : inFilter(outdated, scope);
        if (!rows.length)
            return;
        runMany(perScope(rows, ["upgrade", "--yes"]), tool ? "Upgrading " + tool + inLabel(scope) : "Upgrading all tools", tool ? "Upgraded " + tool + inLabel(scope) : "Upgraded all tools");
    }

    // rewrites the version in the config that declares the tool (global or the project's)
    function bump(tool, scope) {
        run(inDir(scope, ["upgrade", "--bump", "--yes", tool]), "Bumping " + tool + inLabel(scope), "Bumped " + tool + inLabel(scope));
    }

    // only the bump-only tools: `upgrade --bump` with no args would also rewrite in-range ones
    function bumpAll(scope) {
        const rows = inFilter(bumps, scope);
        if (!rows.length)
            return;
        runMany(perScope(rows, ["upgrade", "--bump", "--yes"]), "Bumping " + rows.length + " tools", "Bumped " + rows.length + " tools");
    }

    // scope "" / omitted = global config, otherwise the project's config file path
    function install(tool, scope) {
        run(scope ? ["use", "--path", scope, "--yes", tool] : ["use", "--global", "--yes", tool], "Installing " + tool + inLabel(scope), "Installed " + tool + inLabel(scope));
    }

    // removes from that config and prunes the installed version
    function uninstall(tool, scope) {
        run(scope ? ["unuse", "--path", scope, "--yes", tool] : ["unuse", "--global", "--yes", tool], "Removing " + tool + inLabel(scope), "Removed " + tool + inLabel(scope));
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
                    root.installed = Object.keys(d);
                    const v = {};
                    root.installed.forEach(k => v[k] = (d[k].find(x => x.active) || d[k][0] || {}).version || "");
                    root.versions = v;
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
        command: ["sh", "-c", root.trackedScript]
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

    Process {
        id: jobProc
        property string doneMsg: ""
        property var queue: []   // commands still to run after this one
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
            if (code === 0 && queue.length) {
                command = ["mise"].concat(queue[0]);
                queue = queue.slice(1);
                Qt.callLater(() => jobProc.running = true);
                return;
            }
            root.busy = false;
            if (code === 0)
                ToastService.showInfo("mise", doneMsg);
            else
                ToastService.showError("mise failed", root.failureSummary());
            root.refresh();
        }
    }
}
