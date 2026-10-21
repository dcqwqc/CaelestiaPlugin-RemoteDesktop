pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import dcqwqc.devices
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: Tokens.spacing.medium
    // Custom settings are loaded only when the Devices plugin's Settings
    // section is expanded, so the background status poll is scoped to it.

    readonly property string backend: Quickshell.env("HOME") + "/.local/bin/caelestia-connect"
    property var snapshot: ({})
    property var packageDiff: ({})
    property string feedback: ""
    property string commandError: ""
    property string pendingCommand: ""
    property bool advancedOpen: false
    property bool busy: commandProcess.running || compareProcess.running
    readonly property var connection: snapshot.input_connection || ({})
    readonly property var layoutInfo: snapshot.layout || ({})
    readonly property var services: snapshot.services || ({})
    readonly property var clipboard: snapshot.clipboard || ({})
    readonly property var sync: snapshot.sync || ({})
    readonly property bool miraiRight: layoutInfo.mirai_side !== "left"
    readonly property int verticalOffset: Number(layoutInfo.mirai_offset_pct || 0)
    readonly property string peerName: snapshot.peer === "mirai" ? "Mirai" : "Tachibana"
    readonly property bool statusKnown: connection.status !== undefined
    readonly property bool sharing: statusKnown && !!connection.both_daemons_running
    readonly property bool separate: statusKnown && !connection.local_daemon_running && !connection.peer_daemon_running
    readonly property string edge: snapshot.host === "mirai"
        ? (miraiRight ? qsTr("left") : qsTr("right"))
        : (miraiRight ? qsTr("right") : qsTr("left"))

    function refresh(): void {
        if (statusProcess.running)
            return;
        statusProcess.command = [backend, "status"];
        statusProcess.running = true;
    }

    function perform(args: var): void {
        if (busy)
            return;
        commandError = "";
        feedback = "";
        pendingCommand = args.length ? String(args[0]) : "";
        commandProcess.command = [backend].concat(args);
        commandProcess.running = true;
    }

    Process {
        id: statusProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.snapshot = JSON.parse(text);
                } catch (e) {
                    if (!Object.keys(root.snapshot).length)
                        root.feedback = qsTr("Connection status unavailable");
                }
            }
        }
    }

    Process {
        id: commandProcess
        running: false
        stderr: StdioCollector {
            onStreamFinished: root.commandError = text.trim()
        }
        onExited: code => {
            if (code !== 0)
                root.feedback = root.commandError.length
                    ? root.commandError : qsTr("Couldn't apply the change");
            else if (root.pendingCommand === "send")
                root.feedback = qsTr("File sent to %1").arg(root.peerName);
            root.refresh();
        }
    }

    Process {
        id: compareProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.packageDiff = JSON.parse(text);
                } catch (e) {
                    root.feedback = qsTr("App comparison unavailable");
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                root.feedback = qsTr("App comparison failed");
        }
    }

    Timer {
        interval: 20000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium
        MaterialIcon {
            text: "devices"
            font: Tokens.font.icon.large
            color: Colours.palette.m3onSurfaceVariant
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                text: qsTr("Mirai  ↔  Tachibana")
                font: Tokens.font.title.medium
            }
            StyledText {
                text: root.snapshot.peer_online
                    ? qsTr("Connected")
                    : qsTr("Other computer offline")
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
        IconButton {
            icon: "refresh"
            type: IconButton.Text
            disabled: statusProcess.running
            onClicked: root.refresh()
        }
    }

    // PRIMARY: one decision and one safe escape.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: inputContent.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainerLowest
        radius: Tokens.rounding.large

        ColumnLayout {
            id: inputContent
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Mouse & keyboard")
                    font: Tokens.font.title.small
                }
                IconButton {
                    visible: root.connection.local_daemon_running
                    icon: "keyboard_return"
                    type: IconButton.Text
                    disabled: root.busy
                    onClicked: root.perform(["return-control"])
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                IconTextButton {
                    Layout.fillWidth: true
                    fillWidth: true
                    isToggle: true
                    checked: root.separate
                    internalChecked: checked
                    type: IconTextButton.Tonal
                    icon: "mouse"
                    text: qsTr("Separate")
                    disabled: root.busy
                    onClicked: if (!root.separate) root.perform(["mouse-mode", "separate"])
                }
                IconTextButton {
                    Layout.fillWidth: true
                    fillWidth: true
                    isToggle: true
                    checked: root.sharing
                    internalChecked: checked
                    type: IconTextButton.Tonal
                    icon: "join"
                    text: qsTr("Unified")
                    disabled: root.busy || (!root.snapshot.peer_online && !root.sharing)
                    // An active daemon pair can still have a broken
                    // input stream; pressing Unified again must retry.
                    onClicked: root.perform(root.sharing
                        ? ["input-reconnect", "--onsite"]
                        : ["mouse-mode", "unified"])
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.sharing
                    ? qsTr("Move through the %1 edge to control %2").arg(root.edge).arg(root.peerName)
                    : root.separate
                    ? qsTr("Each computer uses its own mouse")
                    : qsTr("Input connection needs attention")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }

    // PRIMARY: an actual draggable monitor arrangement, sized for laptops.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: screensContent.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainerLowest
        radius: Tokens.rounding.large

        ColumnLayout {
            id: screensContent
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Screen arrangement")
                    font: Tokens.font.title.small
                }
                StyledText {
                    text: qsTr("Drag to align")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 122
                Item {
                    id: arrangement
                    width: 260
                    height: 122
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        id: tachibanaScreen
                        x: root.miraiRight ? 4 : 152
                        y: 30
                        width: 104
                        height: 62
                        radius: Tokens.rounding.small
                        color: Colours.tPalette.m3surfaceContainerHigh
                        border.width: 1
                        border.color: Colours.palette.m3outlineVariant
                        StyledText {
                            anchors.centerIn: parent
                            text: "Tachibana"
                            font: Tokens.font.label.medium
                        }
                    }

                    Rectangle {
                        id: miraiScreen
                        x: root.miraiRight ? 152 : 4
                        y: 30 + root.verticalOffset * 0.34
                        width: 104
                        height: 62
                        radius: Tokens.rounding.small
                        color: Colours.tPalette.m3surfaceContainerHigh
                        border.width: 1
                        border.color: Colours.palette.m3outline
                        StyledText {
                            anchors.centerIn: parent
                            text: "Mirai"
                            font: Tokens.font.label.medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.busy && root.snapshot.peer_online
                            cursorShape: Qt.OpenHandCursor
                            drag.target: miraiScreen
                            drag.minimumX: 0
                            drag.maximumX: arrangement.width - miraiScreen.width
                            drag.minimumY: 1
                            drag.maximumY: arrangement.height - miraiScreen.height - 1
                            onReleased: {
                                const side = miraiScreen.x < tachibanaScreen.x ? "left" : "right";
                                const offset = Math.round(Math.max(-75, Math.min(75, (miraiScreen.y - 30) / 0.34)));
                                if (side !== (root.miraiRight ? "right" : "left") || offset !== root.verticalOffset)
                                    root.perform(["layout-set", "--side", side, "--offset", String(offset)]);
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Mirai: %1 · %2% height offset")
                        .arg(root.miraiRight ? qsTr("right") : qsTr("left"))
                        .arg(root.verticalOffset)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                IconButton {
                    icon: "remove"
                    type: IconButton.Text
                    disabled: root.busy || !root.snapshot.peer_online || root.verticalOffset <= -75
                    onClicked: root.perform(["layout-set", "--side",
                        root.miraiRight ? "right" : "left",
                        "--offset", String(Math.max(-75, root.verticalOffset - 10))])
                }
                IconButton {
                    icon: "add"
                    type: IconButton.Text
                    disabled: root.busy || !root.snapshot.peer_online || root.verticalOffset >= 75
                    onClicked: root.perform(["layout-set", "--side",
                        root.miraiRight ? "right" : "left",
                        "--offset", String(Math.min(75, root.verticalOffset + 10))])
                }
            }
        }
    }

    // SECONDARY: one compact row instead of a diagnostic card.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: clipboardRow.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainerLowest
        radius: Tokens.rounding.large
        RowLayout {
            id: clipboardRow
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small
            MaterialIcon {
                text: "content_copy"
                font: Tokens.font.icon.medium
                color: Colours.palette.m3onSurfaceVariant
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: qsTr("Clipboard")
                    font: Tokens.font.body.medium
                }
                StyledText {
                    text: root.clipboard.watcher_active
                        ? qsTr("Text sharing enabled")
                        : qsTr("Text sharing off")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
            IconTextButton {
                icon: root.clipboard.watcher_active ? "link_off" : "link"
                text: root.clipboard.watcher_active ? qsTr("Turn off") : qsTr("Share")
                type: IconTextButton.Tonal
                disabled: root.busy || (!root.snapshot.peer_online && !root.clipboard.watcher_active)
                onClicked: root.perform(root.clipboard.watcher_active
                    ? ["clipboard-stop"] : ["clipboard-start", "--onsite"])
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: sendContent.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainerLowest
        radius: Tokens.rounding.large
        ColumnLayout {
            id: sendContent
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                MaterialIcon {
                    text: "upload_file"
                    font: Tokens.font.icon.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: qsTr("Send a file")
                        font: Tokens.font.body.medium
                    }
                    StyledText {
                        text: qsTr("Drop here · to %1").arg(root.peerName)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
        DropArea {
            anchors.fill: parent
            enabled: !root.busy && root.snapshot.peer_online
            onDropped: drop => {
                if (!drop.hasUrls || drop.urls.length !== 1) {
                    root.feedback = qsTr("Drop one local file");
                    return;
                }
                const url = String(drop.urls[0]);
                if (!url.startsWith("file:///")) {
                    root.feedback = qsTr("Only local files can be sent");
                    return;
                }
                root.perform(["send", decodeURIComponent(url.substring(7))]);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        MaterialIcon {
            text: root.sync.healthy ? "check_circle" : "sync"
            font: Tokens.font.icon.small
            color: Colours.palette.m3onSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            text: root.sync.healthy ? qsTr("Files synced")
                : root.sync.connected ? qsTr("Syncing files")
                : qsTr("File sync unavailable")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }
        IconButton {
            icon: root.advancedOpen ? "expand_less" : "expand_more"
            type: IconButton.Text
            onClicked: root.advancedOpen = !root.advancedOpen
        }
        StyledText {
            text: qsTr("More")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.advancedOpen = !root.advancedOpen
            }
        }
    }

    // Kept for troubleshooting, out of everyday view.
    Rectangle {
        visible: root.advancedOpen
        Layout.fillWidth: true
        implicitHeight: advancedContent.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainerLowest
        radius: Tokens.rounding.large
        ColumnLayout {
            id: advancedContent
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small
            StyledText {
                text: qsTr("Connection tools")
                font: Tokens.font.title.small
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                IconTextButton {
                    icon: "keyboard_return"
                    text: qsTr("Release mouse")
                    type: IconTextButton.Tonal
                    disabled: root.busy || !root.connection.local_daemon_running
                    onClicked: root.perform(["return-control"])
                }
                IconTextButton {
                    icon: "sync"
                    text: qsTr("Repair")
                    type: IconTextButton.Tonal
                    disabled: root.busy || !root.snapshot.peer_online
                    onClicked: root.perform(["input-reconnect", "--onsite"])
                }
                IconTextButton {
                    icon: "difference"
                    text: qsTr("Compare apps")
                    type: IconTextButton.Tonal
                    disabled: root.busy
                    onClicked: {
                        compareProcess.command = [root.backend, "compare"];
                        compareProcess.running = true;
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: qsTr("Mouse: %1 · Syncthing: %2 · Sunshine: %3")
                    .arg(root.sharing ? qsTr("unified") : root.separate ? qsTr("separate") : qsTr("partial"))
                    .arg(root.services.syncthing?.active ? qsTr("on") : qsTr("off"))
                    .arg(root.services.sunshine?.active ? qsTr("on") : qsTr("off"))
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: !!root.packageDiff.explicit_packages
                text: qsTr("Package differences: %1 local, %2 remote")
                    .arg(root.packageDiff.explicit_packages?.only_local?.length ?? 0)
                    .arg(root.packageDiff.explicit_packages?.only_peer?.length ?? 0)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.feedback.length > 0
        text: root.feedback
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
        wrapMode: Text.WordWrap
    }

}
