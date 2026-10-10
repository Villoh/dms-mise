pragma Singleton

import QtQuick
import Quickshell.Io
import qs.Services

// One mise job at a time: the commands of an action run in order, their output is kept for the
// job banner, and a toast says how it ended. `finished` tells MiseService to re-read the inventory.
Item {
    id: root

    property bool busy: false
    property string label: ""   // what is running, for the banner
    property var log: []        // last lines of mise output while a job runs
    property bool installUnlocked: false  // let Install run with `locked` off, so it can add the tool to the lockfile (Settings)
    signal finished(bool ok)

    function loadSettings() {
        installUnlocked = PluginService.loadPluginData("mise", "installUnlocked", false) === true;
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === "mise")
                root.loadSettings();
        }
    }

    Component.onCompleted: loadSettings()

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
        root.label = label;
        log = [];
        busy = true;
        jobProc.running = true;
    }

    function pushLog(line) {
        const t = line.trim();
        if (t && !t.startsWith("DEBUG"))   // MISE_VERBOSE noise
            log = log.concat([t]).slice(-40);
    }

    // the useful lines of a failed job (the tail is mostly mise's own "Version:/Location:" footer)
    function failureSummary() {
        // WARN lines are other tools' noise: they must not hide the real error (an attestation failure)
        if (log.some(l => !/WARN/.test(l) && /No lockfile URL|not in the lockfile/.test(l)))
            return "`locked = true`: mise installs nothing the lockfile lacks. Add the tool to your mise config, run `mise lock`, then `mise install` (or turn on Install with `locked` off in Settings).";
        const hit = log.filter(l => /×|│|ERROR|hint:|failed|mismatch|not found|denied|404|403/i.test(l) && !/Version:|--verbose|BACKTRACE/i.test(l));
        return (hit.length ? hit : log).slice(-4).join("\n");
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
            if (code !== 0 && fallback.length && !root.installUnlocked && root.log.some(l => /No lockfile URL|not in the lockfile/.test(l))) {
                const f = fallback;
                fallback = [];
                root.log = [];
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
            root.finished(code === 0);
        }
    }
}
