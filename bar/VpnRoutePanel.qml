pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import qs.components

// VPN Gate is an *internet* VPN; it does not replace the independent MCP tunnel
// or the Tailscale remote-device route. No VPN is enabled on startup.
ColumnLayout {
    id: vpn
    Layout.fillWidth: true
    spacing: 6

    readonly property string helper: Quickshell.env("HOME")
        + "/.local/share/caelestia/plugins/remote-desktop/scripts/vpngate-route"
    property bool expanded: false
    property bool connected: false
    property bool tailscaleExitActive: false
    property bool busy: false
    property bool stale: false
    property bool allServers: false
    property string serverIp: ""
    property string selectedId: ""
    property string errorText: ""
    property string feedback: ""
    property string lastAction: ""
    property var servers: []

    function execute(action, serverId) {
        if (busy)
            return;
        if (action !== "status")
            errorText = "";
        if (action === "connect") {
            if (!selectedId) {
                errorText = qsTr("Select a Japan server first.");
                return;
            }
            feedback = qsTr("Connecting to Japan…");
        } else if (action === "disconnect") {
            feedback = qsTr("Restoring direct connection…");
        } else if (action === "refresh") {
            feedback = qsTr("Refreshing VPN Gate servers…");
        }
        lastAction = action;
        busy = true;
        command.command = [helper, action].concat(serverId ? [serverId] : []);
        command.running = true;
    }

    Process {
        id: command
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim());
                    if (!result.ok) {
                        vpn.errorText = result.error || qsTr("Could not complete VPN action.");
                        return;
                    }
                    if (vpn.lastAction === "servers" || vpn.lastAction === "refresh") {
                        vpn.servers = result.servers || [];
                        vpn.stale = !!result.stale;
                        if (!vpn.servers.some(server => server.id === vpn.selectedId))
                            vpn.selectedId = vpn.servers.length ? vpn.servers[0].id : "";
                        vpn.feedback = vpn.stale ? qsTr("Showing cached relays; directory unavailable.") : "";
                    } else if (vpn.lastAction === "status") {
                        vpn.connected = !!result.connected;
                        vpn.tailscaleExitActive = !!result.tailscaleExitActive;
                        vpn.serverIp = result.server || "";
                        if (vpn.connected)
                            vpn.feedback = "";
                    } else if (vpn.lastAction === "verify") {
                        vpn.feedback = result.japan
                            ? qsTr("Verified Japanese IP: ") + result.ip
                            : qsTr("Exit is not in Japan: ") + (result.country || "unknown");
                    } else if (vpn.lastAction === "connect") {
                        vpn.connected = !!result.connected;
                        vpn.serverIp = result.server || "";
                        vpn.feedback = result.connected ? qsTr("Connected. Verify the external IP.") : qsTr("Connection not confirmed.");
                    } else if (vpn.lastAction === "disconnect") {
                        vpn.connected = !!result.connected;
                        vpn.feedback = qsTr("Direct connection restored.");
                    }
                } catch (e) {
                    vpn.errorText = qsTr("VPN helper returned an unexpected response.");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() && !vpn.errorText)
                    vpn.errorText = text.trim().slice(0, 220);
            }
        }
        onExited: code => {
            vpn.busy = false;
            if (code !== 0 && !vpn.errorText)
                vpn.errorText = qsTr("VPN action failed. Try again or check NetworkManager permissions.");
            if (vpn.lastAction === "connect" || vpn.lastAction === "disconnect")
                statusTimer.restart();
            else if (vpn.expanded && vpn.lastAction === "status" && !vpn.servers.length)
                Qt.callLater(() => vpn.execute("servers", ""));
        }
    }

    Timer {
        id: statusTimer
        interval: 850
        repeat: false
        onTriggered: vpn.execute("status", "")
    }
    Timer {
        interval: 12000
        repeat: true
        running: vpn.expanded && vpn.visible
        onTriggered: if (!vpn.busy) vpn.execute("status", "")
    }
    Component.onCompleted: vpn.execute("status", "")
    onExpandedChanged: {
        if (expanded) {
            if (!servers.length)
                execute("servers", "");
            else
                execute("status", "");
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: heading.implicitHeight + 18
        radius: 10
        color: vpn.expanded ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

        RowLayout {
            id: heading
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 7

            MaterialIcon {
                text: vpn.connected ? "vpn_lock" : "public"
                color: vpn.connected ? "#43a047" : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: qsTr("Internet VPN")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.small
                }
                StyledText {
                    text: vpn.connected ? qsTr("VPN Gate · Japan") : qsTr("Direct · VPN Gate available")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }
            Rectangle {
                width: 7
                height: 7
                radius: 4
                color: vpn.connected ? "#43a047" : Colours.palette.m3onSurfaceVariant
            }
            MaterialIcon {
                text: vpn.expanded ? "expand_less" : "expand_more"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: vpn.expanded = !vpn.expanded
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.bottomMargin: 6
        spacing: 8
        visible: vpn.expanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialIcon {
                text: "flag"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
            StyledText {
                Layout.fillWidth: true
                text: qsTr("Japan · Volunteer relays")
                font: Tokens.font.body.small
            }
            Rectangle {
                width: 26
                height: 26
                radius: 9
                color: Colours.tPalette.m3surfaceContainerHighest
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "refresh"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !vpn.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vpn.execute("refresh", "")
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: vpn.tailscaleExitActive && !vpn.connected
            text: qsTr("Your current Route uses a Tailscale exit node. Select Route → Direct above before connecting. Tailscale itself stays connected.")
            font: Tokens.font.label.small
            color: "#b78720"
            wrapMode: Text.Wrap
        }
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Choose an exit server. Your MCP tunnel and Tailscale devices remain separate.")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
        }

        Repeater {
            model: vpn.allServers ? vpn.servers : vpn.servers.slice(0, 4)
            delegate: Rectangle {
                id: relay
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 42
                radius: 9
                readonly property bool selected: vpn.selectedId === modelData.id
                color: relay.selected ? Colours.tPalette.m3surfaceContainerHighest : "transparent"
                border.width: relay.selected ? 1 : 0
                border.color: Colours.palette.m3onSurfaceVariant
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6
                    MaterialIcon {
                        text: relay.selected ? "radio_button_checked" : "radio_button_unchecked"
                        fontStyle: Tokens.font.icon.small
                        color: relay.selected ? "#43a047" : Colours.palette.m3onSurfaceVariant
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: qsTr("Japan relay %1").arg(relay.index + 1)
                            font: Tokens.font.body.small
                        }
                        StyledText {
                            text: relay.modelData.ip
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: relay.modelData.mbps.toFixed(1) + " Mb/s"
                            font: Tokens.font.label.small
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: relay.modelData.ping > 0 ? relay.modelData.ping + " ms" : qsTr("Ping unknown")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !vpn.busy && !vpn.connected
                    cursorShape: Qt.PointingHandCursor
                    onClicked: vpn.selectedId = relay.modelData.id
                }
            }
        }
        StyledText {
            visible: vpn.servers.length === 0 && !vpn.busy && !vpn.errorText
            Layout.fillWidth: true
            text: qsTr("No servers loaded. Tap refresh to check VPN Gate.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
        }
        StyledText {
            visible: vpn.servers.length > 4
            Layout.alignment: Qt.AlignRight
            text: vpn.allServers ? qsTr("Show fewer") : qsTr("Show all %1 relays").arg(vpn.servers.length)
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: vpn.allServers = !vpn.allServers
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: 11
            color: vpn.connected ? Colours.tPalette.m3surfaceContainerHighest : Colours.palette.m3onSurface
            opacity: vpn.busy ? 0.55 : 1
            RowLayout {
                anchors.centerIn: parent
                spacing: 7
                MaterialIcon {
                    text: vpn.connected ? "power_settings_new" : "vpn_lock"
                    color: vpn.connected ? Colours.palette.m3onSurface : Colours.palette.m3surface
                    fontStyle: Tokens.font.icon.small
                }
                StyledText {
                    text: vpn.busy ? qsTr("Working…") :
                          vpn.connected ? qsTr("Disconnect VPN") : qsTr("Connect to Japan")
                    color: vpn.connected ? Colours.palette.m3onSurface : Colours.palette.m3surface
                    font: Tokens.font.body.small
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: !vpn.busy
                onClicked: vpn.execute(vpn.connected ? "disconnect" : "connect", vpn.selectedId)
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: vpn.connected && !vpn.busy
            text: qsTr("Verify public IP ↗")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: vpn.execute("verify", "")
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: vpn.busy || vpn.feedback.length > 0
            text: vpn.feedback
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
        }
        StyledText {
            Layout.fillWidth: true
            visible: vpn.errorText.length > 0
            text: vpn.errorText
            color: Colours.palette.m3error
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
        }
        StyledText {
            Layout.fillWidth: true
            text: qsTr("Whole-device internet exit · Free volunteer VPN. Privacy and Netflix availability not guaranteed.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
        }
    }
}
