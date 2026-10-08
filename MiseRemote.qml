pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services
import "MiseSearch.js" as Search

// Remote lookup: search package sites as you type and verify a typed `backend:tool`.
// The pure part (which backends, URLs, parsers, ranking) is MiseSearch.js; this holds the
// debounce, the one-curl-per-backend queue, the GitHub token and the answers.
Item {
    id: root

    property bool remoteSearch: true   // query npm / crates.io / GitHub as you type (Settings)
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

    function loadSettings() {
        const r = PluginService.loadPluginData("mise", "remoteSearch", true);
        remoteSearch = !(r === false || r === "false");
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === "mise")
                root.loadSettings();
        }
    }

    Component.onCompleted: loadSettings()

    // ---- remote lookup: search package sites, verify a typed backend:tool ----
    // Call from the UI whenever the query changes; debounced, one request per backend at a time.
    function lookup(raw) {
        const q = Search.alias((raw || "").trim());
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
}
