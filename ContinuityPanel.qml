pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: Tokens.spacing.small

    readonly property string continuityBin: Quickshell.env("HOME") + "/.local/bin/celestios-continuity"
    readonly property string handoffBin: Quickshell.env("HOME") + "/.local/bin/celestios-handoff"
    property var statusData: ({})
    property var handoffData: ({})
    property string feedback: ""
    readonly property string target: statusData.host === "mirai" ? "tachibana" : "mirai"
    readonly property bool busy: statusProcess.running || handoffProcess.running || launchProcess.running
    readonly property var syncthing: statusData.syncthing || ({})
    readonly property var apps: statusData.profile?.apps || ({})

    function refresh(): void {
        if (root.busy)
            return;
        statusProcess.command = [root.continuityBin, "status"];
        statusProcess.running = true;
    }

    Process {
        id: statusProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.statusData = JSON.parse(text);
                    if (root.statusData.host === "mirai" || root.statusData.host === "tachibana") {
                        handoffProcess.command = [root.handoffBin, "--to", root.target];
                        handoffProcess.running = true;
                    }
                } catch (err) {
                    root.feedback = qsTr("Could not read Continuity status");
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                root.feedback = qsTr("Continuity backend unavailable");
        }
    }

    Process {
        id: handoffProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.handoffData = JSON.parse(text);
                } catch (err) {
                    root.handoffData = ({ ready: false, blockers: ["Handoff status unavailable"] });
                }
            }
        }
        onExited: code => {
            if (code !== 0 && !(root.handoffData.blockers || []).length)
                root.feedback = qsTr("Handoff prerequisites are not verified");
        }
    }

    Process {
        id: launchProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.feedback = result.launch_requested
                        ? qsTr("Handoff request delivered; confirm the destination workspace")
                        : qsTr("No handoff was launched");
                } catch (err) {
                    root.feedback = qsTr("Handoff result unavailable — do not retry automatically");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.feedback = qsTr("Handoff not verified. Check the destination before retrying.");
            }
        }
        onExited: code => {
            if (code !== 0)
                root.feedback = qsTr("Handoff blocked or unconfirmed; no automatic retry");
            root.refresh();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    ConnectedRect {
        Layout.fillWidth: true
        implicitHeight: panel.implicitHeight + Tokens.padding.large * 2

        ColumnLayout {
            id: panel
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Continuity")
                    font: Tokens.font.title.small
                }
                IconButton {
                    icon: "refresh"
                    type: IconButton.Text
                    disabled: root.busy
                    onClicked: root.refresh()
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.syncthing.connected
                    ? qsTr("Files connected · %1 synced folders").arg((root.syncthing.folders || []).length)
                    : qsTr("File synchronization offline or unverified")
                color: root.syncthing.connected ? Colours.palette.m3primary : Colours.palette.m3outline
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("%1 selected app profiles · %2")
                    .arg(Object.keys(root.apps).length)
                    .arg((root.syncthing.versioning_missing || []).length === 0
                        ? qsTr("File versioning enabled") : qsTr("File versioning needs attention"))
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                text: root.handoffData.ready
                    ? qsTr("Zen Space handoff ready")
                    : (root.handoffData.blockers || []).join(" · ") || qsTr("Checking Zen handoff…")
                color: root.handoffData.ready ? Colours.palette.m3primary : Colours.palette.m3outline
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            IconTextButton {
                Layout.fillWidth: true
                icon: "arrow_forward"
                text: qsTr("Continue on %1").arg(root.target === "mirai" ? "Mirai" : "Tachibana")
                type: IconTextButton.Tonal
                disabled: root.busy || !root.handoffData.ready
                onClicked: {
                    if (!root.handoffData.ready || root.busy)
                        return;
                    root.feedback = qsTr("Requesting handoff…");
                    launchProcess.command = [root.handoffBin, "--to", root.target, "--execute"];
                    launchProcess.running = true;
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !!root.feedback
                text: root.feedback
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }
    }
}
