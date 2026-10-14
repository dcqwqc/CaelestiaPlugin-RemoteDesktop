pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Quest Spatial Workspace desktop selector: Shared Desktop (A) mirrors this
// machine's physical session, Private Desktop (B) is a separate headless
// session. All state comes from the qsw-session-mode CLI; nothing here is
// assumed or optimistically flipped, so an absent or failing CLI never shows
// a selectable private desktop.
Singleton {
    id: root

    // The bar runs under the systemd user manager without ~/.local/bin on PATH.
    readonly property string bin: `${Quickshell.env("HOME")}/.local/bin/qsw-session-mode`
    // Report a missing CLI as an ordinary failure instead of letting Quickshell
    // log a start warning on every poll.
    readonly property var guard: ["sh", "-c",
        '[ -x "$0" ] || { echo "qsw-session-mode is missing or not executable in ~/.local/bin." >&2; exit 127; }; exec "$0" "$@"']

    // True only after a status call exited 0 and returned a valid mode.
    property bool available: false
    property bool checked: false
    property string mode: ""
    property bool privateReady: false
    // Error reported by the CLI itself or by invoking it.
    property string statusError: ""
    // Last select/start/stop failure; cleared by the next successful action.
    property string actionError: ""
    property string pendingAction: ""
    readonly property bool busy: pendingAction.length > 0

    readonly property bool privateSelected: available && mode === "private"
    readonly property bool sharedSelected: available && mode === "shared"

    function refresh(): void {
        if (!statusProc.running)
            statusProc.launch(root.guard.concat([root.bin, "status", "--json"]));
    }

    function select(target): void {
        if (target !== "shared" && target !== "private")
            return;
        if (target === "private" && !root.privateReady) {
            root.actionError = qsTr("Private Desktop B is not ready; start it first.");
            return;
        }
        root.run(`select-${target}`, ["select", target]);
    }

    // `select private` starts the private desktop first when needed.
    function selectPrivate(): void {
        root.run("select-private", ["select", "private"]);
    }

    function start(): void {
        root.run("start", ["start"]);
    }

    function stop(): void {
        root.run("stop", ["stop"]);
    }

    function run(name, args): void {
        if (root.busy || !root.available)
            return;
        root.pendingAction = name;
        root.actionError = "";
        actionProc.launch(root.guard.concat([root.bin], args));
    }

    // Pull `error` out of CLI JSON output if present; otherwise "".
    function jsonError(text): string {
        try {
            const data = JSON.parse(text);
            return data && typeof data === "object" ? String(data.error ?? "").trim() : "";
        } catch (e) {
            return "";
        }
    }

    function applyStatus(code, out, err): void {
        root.checked = true;
        let data = null;
        try {
            data = JSON.parse(out);
        } catch (e) {
            data = null;
        }
        const validMode = data && (data.mode === "shared" || data.mode === "private");
        if (code !== 0 || !validMode) {
            root.available = false;
            root.mode = "";
            root.privateReady = false;
            root.statusError = root.jsonError(out)
                || err
                || (code !== 0
                    ? qsTr("qsw-session-mode status exited with code %1.").arg(code)
                    : qsTr("qsw-session-mode status returned no valid mode."));
            return;
        }
        root.available = true;
        root.mode = data.mode;
        root.privateReady = data.private_ready === true;
        root.statusError = String(data.error ?? "").trim();
    }

    component CliProcess: Process {
        id: proc

        property bool didStart: false
        property bool outDone: false
        property bool exitDone: false
        property bool reported: false
        property int exitCode: -1
        property string outText: ""
        property string errText: ""

        signal finished(int code, string out, string err)

        function launch(cmd): void {
            didStart = false;
            outDone = false;
            exitDone = false;
            reported = false;
            exitCode = -1;
            outText = "";
            errText = "";
            command = cmd;
            running = true;
            watchdog.restart();
        }

        // Report each launch exactly once, whichever path ends it first.
        function report(code, out, err): void {
            if (reported)
                return;
            reported = true;
            watchdog.stop();
            proc.finished(code, out, err);
        }

        function maybeFinish(): void {
            if (outDone && exitDone)
                report(exitCode, outText.trim(), errText.trim());
        }

        running: false
        onStarted: didStart = true
        // A process that never starts emits neither stdout nor exited.
        onRunningChanged: {
            if (!running && !didStart && command.length > 0)
                report(127, "", qsTr("Could not start sh to run qsw-session-mode."));
        }
        stdout: StdioCollector {
            onStreamFinished: {
                proc.outText = text;
                proc.outDone = true;
                proc.maybeFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: proc.errText = text
        }
        onExited: code => {
            proc.exitCode = code;
            proc.exitDone = true;
            proc.maybeFinish();
        }

        property Timer watchdog: Timer {
            interval: 30000
            onTriggered: {
                proc.report(124, "", qsTr("qsw-session-mode did not answer within 30 s."));
                proc.running = false;
            }
        }
    }

    CliProcess {
        id: statusProc

        onFinished: (code, out, err) => root.applyStatus(code, out, err)
    }

    CliProcess {
        id: actionProc

        onFinished: (code, out, err) => {
            const reported = root.jsonError(out);
            if (code !== 0 || reported.length > 0)
                root.actionError = reported || err
                    || qsTr("qsw-session-mode %1 failed with exit code %2.").arg(root.pendingAction).arg(code);
            root.pendingAction = "";
            root.refresh();
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
