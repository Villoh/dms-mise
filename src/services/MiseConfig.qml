pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services
import "MiseSearch.js" as Search

// `mise settings`: every setting mise knows, and the ones set in the global config. Edits run here, not
// in MiseJobs: no banner (it shifts the list), no success toast, no inventory re-check. A failure toasts.
Item {
    id: root

    property var all: []   // see Search.parseSettings
    property var queue: [] // `settings set|unset` argument lists still to run, in order
    property var err: []   // stderr of the one running

    function matching(q) {
        return Search.filterSettings(all, q);
    }

    function refresh() {
        if (!readProc.running)
            readProc.running = true;
    }

    function run(args) {
        queue = queue.concat([args]);
        next();
    }

    function next() {
        if (setProc.running || !queue.length)
            return;
        err = [];
        setProc.command = ["mise"].concat(queue[0]);
        queue = queue.slice(1);
        setProc.running = true;
    }

    // `KEY=VALUE`: one argument, so a value like `-1` is not taken for a flag. mise checks the value
    // against the setting's type and its error reaches the toast. The row shows the new value at once;
    // the read after the command settles it (and puts it back if mise refused).
    function set(key, value) {
        all = all.map(s => s.key === key ? Object.assign({}, s, {
                value: String(value)
            }) : s);
        run(["settings", "set", key + "=" + value]);
    }

    // back to mise's default: removes the key from the global config
    function unset(key) {
        run(["settings", "unset", key]);
    }

    function toggle(key) {
        const s = all.find(x => x.key === key);
        if (s)
            set(key, s.value !== "true");
    }

    Component.onCompleted: refresh()

    Process {
        id: setProc
        stderr: SplitParser {
            onRead: l => root.err = root.err.concat([l.replace(/^mise ERROR\s*/, "")])
        }
        onExited: code => {
            if (code !== 0)
                ToastService.showError("mise", root.err.filter(l => l.trim() && !/^Version:|^Run with/.test(l)).join("\n"));
            if (!root.queue.length)
                root.refresh();
            root.next();
        }
    }

    Process {
        id: readProc
        command: ["mise", "settings", "ls", "--all", "--json-extended"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const l = Search.parseSettings(JSON.parse(text));
                    // same list: leave it alone, a new array rebuilds the view
                    if (JSON.stringify(l) === JSON.stringify(root.all))
                        return;
                    root.all = l;
                } catch (e) {}
            }
        }
    }
}
