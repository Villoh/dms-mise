pragma Singleton

import QtQuick
import Quickshell.Io
import "MiseSearch.js" as Search

// Tool details for the row expander: `mise tool --json` + the last versions from `mise ls-remote`,
// one mise call at a time; and the `latest` check of the http: form.
Item {
    id: root

    // infoKey(name, scope) -> {meta, versions, metaError, versionsError}; undefined = not asked, null = in flight
    property var info: ({})
    readonly property int maxVersions: 20

    // "name|scope": a tool answers per scope (active versions differ between global and a project)
    function infoKey(name, scope) {
        return Search.bareName(name) + "|" + scope;
    }

    // run a mise command for an info key, in its scope
    function infoArgs(k, args) {
        const i = k.indexOf("|");
        return MiseService.inDir(k.slice(i + 1), args(k.slice(0, i)));
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

    Connections {
        target: MiseJobs
        function onFinished() {
            root.refreshInfo();
        }
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
}
