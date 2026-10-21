pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// One-click "Continue here": hand an existing Zen Space (plus optional project,
// Orbit conversation and URL) to the other computer. Nothing runs until the
// popout section is opened, and nothing launches until Continue is clicked.
ColumnLayout {
    id: root

    readonly property string cli: `${Quickshell.env("HOME")}/.local/bin/celestios-continuity`
    property bool expanded: false
    property bool loaded: false
    property string localHost: ""
    property string targetHost: ""
    property string targetState: "unknown"   // ok | offline | error | unknown
    property bool targetSpaceFlag: false
    property var spaces: []
    property int spaceIndex: 0
    property string statusText: ""
    property bool statusIsError: false
    readonly property bool busy: targetsProbe.running || handoffRun.running
    readonly property bool canContinue: loaded && targetState === "ok" && targetSpaceFlag
        && spaces.length > 0 && !busy

    Layout.fillWidth: true
    spacing: Tokens.spacing.extraSmall

    function refresh(): void {
        if (!targetsProbe.running)
            targetsProbe.running = true;
    }

    Process {
        id: targetsProbe
        command: [root.cli, "handoff-targets"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.localHost = String(data.host ?? "");
                    const peers = Object.keys(data.targets ?? {}).filter(h => h !== root.localHost);
                    root.targetHost = peers.length > 0 ? peers[0] : "";
                    const peer = root.targetHost ? data.targets[root.targetHost] : null;
                    root.targetState = peer ? String(peer.state) : "unknown";
                    root.targetSpaceFlag = !!(peer && peer.space_flag);
                    // Spaces must exist on the target; they are never created here.
                    root.spaces = peer && peer.spaces ? peer.spaces : [];
                    root.spaceIndex = 0;
                    root.loaded = true;
                    if (root.targetState === "offline")
                        root.say(qsTr("%1 is offline").arg(root.targetHost), true);
                    else if (!root.targetSpaceFlag && root.targetState === "ok")
                        root.say(qsTr("Zen on %1 is too old for Space handoff").arg(root.targetHost), true);
                    else
                        root.say("", false);
                } catch (e) {
                    root.loaded = true;
                    root.targetState = "error";
                    root.say(qsTr("Continuity tool unavailable"), true);
                }
            }
        }
        onExited: code => {
            if (code !== 0 && !root.loaded) {
                root.loaded = true;
                root.targetState = "error";
                root.say(qsTr("Continuity tool unavailable"), true);
            }
        }
    }

    Process {
        id: handoffRun
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const r = data.remote ?? data;
                    if (data.state === "offline")
                        root.say(qsTr("%1 is offline").arg(root.targetHost), true);
                    else if (r.state === "launched")
                        root.say(qsTr("Opened on %1").arg(root.targetHost), false);
                    else
                        root.say(String(r.reason ?? r.state ?? data.reason ?? qsTr("Not opened")), true);
                } catch (e) {
                    root.say(qsTr("Handoff failed"), true);
                }
            }
        }
    }

    function say(message: string, isError: bool): void {
        statusText = message;
        statusIsError = isError;
    }

    function cont(): void {
        if (!canContinue)
            return;
        const args = [cli, "handoff", "--origin", localHost, "--target", targetHost,
            "--space", spaces[spaceIndex].uuid];
        const url = urlField ? urlField.text.trim() : "";
        if (url.length > 0)
            args.push("--url", url);
        if (projectField && projectField.text.trim().length > 0)
            args.push("--project", projectField.text.trim());
        if (orbitField && orbitField.text.trim().length > 0)
            args.push("--orbit", orbitField.text.trim());
        args.push("--execute");   // only reached from the Continue click
        say(qsTr("Opening on %1…").arg(targetHost), false);
        handoffRun.command = args;
        handoffRun.running = true;
    }

    Item {
        id: header
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.extraSmall
        Layout.rightMargin: Tokens.padding.extraSmall
        implicitHeight: headerRow.implicitHeight

        RowLayout {
            id: headerRow
            anchors.fill: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: "devices_fold"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Continue here")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
            }

            MaterialIcon {
                text: root.expanded ? "expand_less" : "expand_more"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.expanded = !root.expanded;
                if (root.expanded)
                    root.refresh();   // first probe happens on open, never at startup
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.extraSmall
        Layout.rightMargin: Tokens.padding.extraSmall
        visible: root.expanded
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            visible: root.targetHost.length > 0
            text: qsTr("To %1").arg(root.targetHost)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        IconTextButton {
            Layout.fillWidth: true
            fillWidth: true
            type: IconTextButton.Tonal
            icon: "tab_group"
            text: root.spaces.length > 0 ? root.spaces[root.spaceIndex].name || qsTr("Space") : qsTr("No Spaces found")
            font: Tokens.font.label.medium
            verticalPadding: Tokens.padding.extraSmall
            disabled: root.spaces.length < 2
            onClicked: root.spaceIndex = (root.spaceIndex + 1) % root.spaces.length
        }

        Repeater {
            model: [
                { id: "projectInput", hint: qsTr("Project (optional)") },
                { id: "orbitInput", hint: qsTr("Orbit conversation (optional)") },
                { id: "urlInput", hint: qsTr("https:// link (optional)") }
            ]
            delegate: StyledRect {
                id: field
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: input.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainerHighest

                StyledTextField {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    placeholderText: field.modelData.hint
                    horizontalAlignment: TextInput.AlignLeft
                    Component.onCompleted: {
                        if (field.modelData.id === "projectInput") root.projectField = input;
                        else if (field.modelData.id === "orbitInput") root.orbitField = input;
                        else root.urlField = input;
                    }
                }
            }
        }

        IconTextButton {
            Layout.fillWidth: true
            fillWidth: true
            type: IconTextButton.Filled
            icon: "arrow_forward"
            text: qsTr("Continue")
            font: Tokens.font.label.medium
            verticalPadding: Tokens.padding.extraSmall
            disabled: !root.canContinue
            onClicked: root.cont()
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.statusText.length > 0
            text: root.statusText
            wrapMode: Text.Wrap
            color: root.statusIsError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    property var projectField: null
    property var orbitField: null
    property var urlField: null
}
