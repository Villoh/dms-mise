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
    property bool installUnlocked: false  // let Install run with `locked` off, so it can add the tool to the lockfile (Settings)
    property bool remoteSearch: true  // query npm / crates.io / GitHub as you type (Settings)
    property string lookupQ: ""       // last query handed to lookup()
    property var remoteHits: ({})     // backend -> [{name: "npm:foo", backend, desc}], from the last answer
    readonly property var remote: Search.backends.reduce((a, k) => a.concat(remoteHits[k] || []), [])
    property var verified: ({})       // "npm:foo" -> {ok, desc}; absent = not checked yet / network error
    // token mise resolves for GitHub, only ever sent to api.github.com. Asked on the first GitHub
    // request, kept in memory (never written anywhere); "" = none, requests go unauthenticated.
    property string githubToken: ""
    property bool tokenAsked: false
    property bool tokenReady: false
    property var lastError: ({})      // backend -> why its last search failed ("offline", "timeout", "rate limited", "HTTP 500"); cleared by its next 200
    property var unchecked: ({})      // "npm:foo" -> why the exact-name check failed (anything but 200 / 404); the row only says "could not check" (the reason does not fit), `notices` gives it
    // what to tell the user: one line per reason, only for backends this query searches, and not while
    // a request is pending (the loading bar / Searching… take that place)
    readonly property var notices: {
        if (lookingUp)
            return [];
        const by = {};
        const add = (k, e) => {
            if (e && !(by[e] || []).includes(k))
                (by[e] = by[e] || []).push(k);
        };
        Search.searchTargets(lookupQ, remoteSearch).forEach(k => add(k, lastError[k]));
        // the exact-name check of what is typed, also for backends that are only verified (github:owner/repo)
        const p = Search.splitQuery(lookupQ);
        if (remoteSearch && p.b)
            add(p.b, unchecked[p.bare]);
        return Object.keys(by).map(e => by[e].join(", ") + " didn't answer · " + e);
    }
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
        installUnlocked = PluginService.loadPluginData("mise", "installUnlocked", false) === true;
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
            remote: remote,
            verified: verified,
            unchecked: unchecked,
            remoteSearch: remoteSearch
        });
    }

    // ---- remote lookup: search package sites, verify a typed backend:tool ----
    // Call from the UI whenever the query changes; debounced, one request per backend at a time.
    function lookup(raw) {
        const q = alias((raw || "").trim());
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
        lookingUp = remoteSearch && lookupQ.length >= 2 && (lookupTimer.running || (tokenAsked && !tokenReady) || verifyFetch.running || Object.keys(fetchers).some(k => fetchers[k].running));
    }

    // what to ask the network for this query
    function fetchRemote() {
        const q = lookupQ;
        if (!remoteSearch || q.length < 2)
            return;
        const p = Search.splitQuery(q);
        // typed backend:tool -> does it exist? (git+/URL specs are not checked)
        const u = verified[p.bare] ? "" : Search.verifyUrl(q);
        if (u)
            verifyFetch.start(u, p.bare);
        // always ask, even when the registry has the name: skipping would leave the hits of an
        // earlier, shorter query on screen and the list would depend on how you typed
        const n = p.b ? Search.maxPrefixed : Search.maxFree;
        Search.searchTargets(q, remoteSearch).forEach(k => fetchers[k].start(Search.searchers[k].url(p.t, n), p.t));
    }

    function resolveToken() {
        if (tokenAsked)
            return;
        tokenAsked = true;
        tokenProc.running = true;
        tokenTimeout.start();
    }

    // plain token characters only: it goes into a curl config line
    function tokenDone(t) {
        if (tokenReady)
            return;
        tokenReady = true;
        githubToken = /^[\w.\-]+$/.test(t) ? t : "";
        verifyFetch.next();
        Object.keys(fetchers).forEach(k => fetchers[k].next());
        settle();
    }

    // `timeout` only kills mise itself: a hung child (e.g. credential_command) would keep the pipe open
    // and every GitHub request waiting. Give up on the token instead.
    Timer {
        id: tokenTimeout
        interval: 6000
        onTriggered: {
            tokenProc.running = false;
            root.tokenDone("");
        }
    }

    // `mise token github --raw` (every source mise knows). Capped at 5 s: it may try an interactive
    // OAuth flow. Nothing or `(none)` = no token.
    Process {
        id: tokenProc
        command: ["sh", "-c", "timeout 5 mise token github --raw 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.tokenDone(text.trim())
        }
    }

    // answer of a search request. A failed backend loses its hits: older ones would pass as the answer.
    function gotHits(b, why, json, term) {
        why = why || (json ? "" : "unexpected answer");
        const e = Object.assign({}, lastError);
        const m = Object.assign({}, remoteHits);
        if (why) {
            e[b] = why;
            delete m[b];
        } else {
            delete e[b];
            m[b] = Search.parseHits(b, json, term);
        }
        lastError = e;
        remoteHits = m;
    }

    // 200 = exists, 404 = does not; anything else (offline, rate limit) stays unknown, but is flagged
    function gotVerify(tool, status, j, why) {
        const u = Object.assign({}, unchecked);
        if (status !== 200 && status !== 404) {
            u[tool] = why;
            unchecked = u;
            return;
        }
        delete u[tool];
        unchecked = u;
        const v = Object.assign({}, verified);
        v[tool] = {
            ok: status === 200,
            desc: Search.describe(j)
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
    // stdout = body + "\n" + "<http status> <curl exit code> <x-ratelimit-remaining>" (status 000 = network failure).
    // backend "" = verification.
    // api.github.com requests wait for the token lookup and carry it as a header read from a curl
    // config on stdin (-K), so it never shows in the argv `ps` lists. Other hosts never see it.
    component Fetch: Process {
        id: f
        property string backend: ""
        property string want: ""
        property bool authed: false
        property string waitUrl: ""
        property string waitWant: ""
        stdinEnabled: true
        function start(url, w) {
            const gh = Search.isGithub(url);
            if (running || (gh && !root.tokenReady)) {
                waitUrl = url;
                waitWant = w;
                if (gh)
                    root.resolveToken();
                return;
            }
            want = w;
            authed = gh && root.githubToken !== "";
            const curl = ["curl", "-sL", "--max-time", "6", "-A", "dms-mise-plugin", "-w", "\n%{http_code} %{exitcode} %header{x-ratelimit-remaining}"];
            command = authed ? ["bash", "-c", "IFS= read -r t; exec " + curl.map(a => "'" + a + "'").join(" ") + " -K <(printf 'header = \"Authorization: Bearer %s\"\\n' \"$t\") \"$1\"", "_", url] : curl.concat([url]);
            running = true;
        }
        // the request that arrived while busy or while the token was being looked up
        function next() {
            if (!waitUrl || running)
                return;
            const u = waitUrl, w = waitWant;
            waitUrl = "";
            start(u, w);
        }
        onStarted: {
            if (authed)
                write(root.githubToken + "\n");
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const i = text.lastIndexOf("\n");
                let j = null;
                try {
                    j = JSON.parse(text.substring(0, i));
                } catch (e) {}
                const tail = text.substring(i + 1).trim().split(" ");
                const s = parseInt(tail[0]) || 0;
                const why = Search.failure(s, tail[2], parseInt(tail[1]));
                if (f.backend)
                    root.gotHits(f.backend, why, j, f.want);
                else
                    root.gotVerify(f.want, s, j, why);
            }
        }
        onExited: {
            next();
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

    function run(args, label, doneMsg, fallback) {
        runMany([args], label, doneMsg, fallback);
    }

    // commands run one after another; the first failure stops the rest
    // `fallback`: a command to try, once, if the first one is refused for a missing lockfile entry
    function runMany(cmds, label, doneMsg, fallback) {
        if (busy) {
            ToastService.showError("mise", "Another job is running");
            return;
        }
        jobProc.doneMsg = doneMsg;
        jobProc.queue = cmds.slice(1);
        jobProc.fallback = fallback || [];
        jobProc.prepare(cmds[0]);
        jobLabel = label;
        jobLog = [];
        busy = true;
        jobProc.running = true;
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
            run(["trust", scope], "Trusting " + scopeLabel(scope), "Trusted " + scopeLabel(scope));
        else
            run(scope ? ["-C", projectDir(scope), "lock"] : ["lock", "-g"], "Locking " + scopeLabel(scope), "Locked " + scopeLabel(scope));
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
        const use = scope ? ["use", "--path", scope, "--yes", tool] : ["use", "--global", "--yes", tool];
        runMany(installUnlocked ? [use] : [use, lockAfterUse(tool, scope)], "Installing " + tool + inLabel(scope), "Installed " + tool + inLabel(scope), lockedInstall(tool, scope));
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

    // removes from that config and prunes the installed version
    function uninstall(tool, scope) {
        run(scope ? ["unuse", "--path", scope, "--yes", tool] : ["unuse", "--global", "--yes", tool], "Removing " + tool + inLabel(scope), "Removed " + tool + inLabel(scope));
    }

    // ---- tool info (row expander): `mise tool --json` + the last versions from `mise ls-remote` ----
    // infoKey(name, scope) -> {meta, versions, metaError, versionsError}; undefined = not asked, null = in flight
    property var info: ({})
    readonly property int maxVersions: 20

    // `npm:foo@1.2` / `foo[opt=x]` -> `npm:foo`
    function bareName(n) {
        return Search.bareName(n);
    }

    // "name|scope": a tool answers per scope (active versions differ between global and a project)
    function infoKey(name, scope) {
        return bareName(name) + "|" + scope;
    }

    // run a mise command for an info key, in its scope
    function infoArgs(k, args) {
        const i = k.indexOf("|");
        return inDir(k.slice(i + 1), args(k.slice(0, i)));
    }

    function setInfo(n, patch) {
        const m = Object.assign({}, info);
        m[n] = Object.assign({}, m[n] || {}, patch);
        info = m;
    }

    // cached after the first answer; a failed one is retried the next time the row opens
    function loadInfo(name, scope) {
        const n = infoKey(name, scope);
        const i = info[n] || {};
        if (i.meta === undefined) {
            setInfo(n, {
                meta: null,
                metaError: ""
            });
            metaAsk.ask(n);
        }
        if (i.versions === undefined) {
            setInfo(n, {
                versions: null,
                versionsError: ""
            });
            versionsAsk.ask(n);
        }
    }

    // after a job the installed / active versions changed: re-ask the cached tools (old values stay
    // on screen meanwhile; the version lists don't change)
    function refreshInfo() {
        Object.keys(info).filter(n => info[n].meta).forEach(n => metaAsk.ask(n));
    }

    // one mise call at a time, the rest wait their turn. The tool name is echoed as the first output line
    // so an answer can't be matched to the wrong tool.
    component Ask: Process {
        id: a
        property var args: t => []
        property var queue: []
        signal answer(string tool, string body)
        function ask(t) {
            if (running) {
                queue = queue.concat([t]);
                return;
            }
            command = ["sh", "-c", 'echo "$1"; shift; exec timeout 30 mise "$@"', "sh", t].concat(args(t));
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const i = text.indexOf("\n");
                a.answer(text.substring(0, i), text.substring(i + 1));
            }
        }
        onExited: {
            if (!queue.length)
                return;
            const t = queue[0];
            queue = queue.slice(1);
            ask(t);
        }
    }

    Ask {
        id: metaAsk
        args: t => root.infoArgs(t, n => ["tool", "--json", n])
        onAnswer: (tool, body) => {
            try {
                root.setInfo(tool, {
                    meta: JSON.parse(body)
                });
            } catch (e) {
                root.setInfo(tool, {
                    meta: undefined,
                    metaError: "Could not read `mise tool " + tool + "`"
                });
            }
        }
    }

    Ask {
        id: versionsAsk
        args: t => root.infoArgs(t, n => ["ls-remote", n])
        // oldest first -> newest first
        onAnswer: (tool, body) => {
            const v = body.split("\n").map(x => x.trim()).filter(x => x).slice(-root.maxVersions).reverse();
            root.setInfo(tool, v.length ? {
                versions: v
            } : {
                versions: undefined,
                versionsError: "No versions found (offline, or the tool doesn't exist)"
            });
        }
    }

    // `http:` form: what does `latest` resolve to for the typed spec? (`mise latest` follows the list order and
    // version_order, which a count of versions would not show.) Answers for an older spec are dropped, and
    // only the newest request waits behind a running one.
    property var httpCheck: ({})   // {spec, pending, latest}
    function checkHttp(spec) {
        httpCheck = {
            spec: spec,
            pending: true
        };
        checkAsk.queue = [];
        checkAsk.ask(spec);
    }

    Ask {
        id: checkAsk
        args: t => ["latest", t]
        // mise caches the version list by tool name, not by options: without this a changed url or path
        // would still answer from the first list
        environment: ({
                MISE_FETCH_REMOTE_VERSIONS_CACHE: "0"
            })
        onAnswer: (tool, body) => {
            if (root.httpCheck.spec !== tool)
                return;
            root.httpCheck = {
                spec: tool,
                pending: false,
                latest: body.trim()
            };
        }
    }

    // removes that one installed version; the config is not touched
    function uninstallVersion(tool, version) {
        run(["uninstall", "--yes", tool + "@" + version], "Removing " + tool + "@" + version, "Removed " + tool + "@" + version);
    }

    // unused versions of one tool, or of every tool when omitted. Not scoped: `mise prune` goes by all
    // the configs mise has tracked.
    function prune(tool) {
        run(["prune", "--tools", "--yes"].concat(tool ? [tool] : []), tool ? "Pruning " + tool : "Pruning unused versions", tool ? "Pruned " + tool : "Pruned unused versions");
    }

    function pushLog(line) {
        const t = line.trim();
        if (t && !t.startsWith("DEBUG"))   // MISE_VERBOSE noise
            jobLog = jobLog.concat([t]).slice(-40);
    }

    // the useful lines of a failed job (the tail is mostly mise's own "Version:/Location:" footer)
    function failureSummary() {
        if (jobLog.some(l => /No lockfile URL|not in the lockfile/.test(l)))
            return "`locked = true`: mise installs nothing the lockfile lacks. Add the tool to your mise config, run `mise lock`, then `mise install` (or turn on Install with `locked` off in Settings).";
        const hit = jobLog.filter(l => /×|│|ERROR|hint:|failed|mismatch|not found|denied|404|403/i.test(l) && !/Version:|--verbose|BACKTRACE/i.test(l));
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

    Process {
        id: jobProc
        property string doneMsg: ""
        property var queue: []   // commands still to run after this one
        property var fallback: []   // see runMany
        // verbose so a failure carries the backend's own reason (aube/npm/uv...), not just "exit code 1".
        // With `locked = true` mise refuses `use` for a tool the lockfile does not know (No lockfile URL found).
        // Only when the user allows it in Settings, `use` runs unlocked and mise writes the lockfile entries.
        function prepare(args) {
            environment = Object.assign({
                MISE_VERBOSE: "1"
            }, args[0] === "use" && root.installUnlocked ? {
                MISE_LOCKED: "0"
            } : {});
            command = args[0] === "sh" ? args : ["mise"].concat(args);
        }
        stdout: SplitParser {
            onRead: l => root.pushLog(l)
        }
        stderr: SplitParser {
            onRead: l => root.pushLog(l)
        }
        onExited: code => {
            if (code !== 0 && fallback.length && !root.installUnlocked && root.jobLog.some(l => /No lockfile URL|not in the lockfile/.test(l))) {
                const f = fallback;
                fallback = [];
                root.jobLog = [];
                prepare(f);
                Qt.callLater(() => jobProc.running = true);
                return;
            }
            if (code === 0 && queue.length) {
                prepare(queue[0]);
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
            root.refreshInfo();
        }
    }
}
