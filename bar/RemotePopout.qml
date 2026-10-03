pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Plugins
import qs.components
import qs.components.controls
import qs.services
import dcqwqc.remotedesktop.services as RemoteDesktop
import qs.utils

ColumnLayout {
    id: root

    width: 304
    spacing: Tokens.spacing.extraSmall

    property var exitMenuItems: []

    readonly property var remoteSettings: {
        const plugin = Plugins.plugins.find(candidate => candidate.id === "dcqwqc/remotedesktop");
        return plugin ? plugin.settings : null;
    }

    function deviceOverrides(): var {
        if (!root.remoteSettings)
            return {};
        try {
            const parsed = JSON.parse(root.remoteSettings.deviceOverridesJson || "{}");
            return parsed && typeof parsed === "object" ? parsed : {};
        } catch (e) {
            return {};
        }
    }

    function deviceOverride(device): var {
        return root.deviceOverrides()[device.id] ?? {};
    }

    function defaultDeviceEnabled(device): bool {
        return !!device.isSelf
            || !!device.online
            || !!device.canRemoteDesktop
            || !!device.canWake
            || (!!device.canSsh && !!device.sshAvailable);
    }

    function deviceEnabled(device): bool {
        const cfg = root.deviceOverride(device);
        return cfg.enabled === undefined ? root.defaultDeviceEnabled(device) : !!cfg.enabled;
    }

    function defaultDeviceIcon(device): string {
        const type = String(device.type ?? "");
        if (type === "phone")
            return "smartphone";
        if (type === "server")
            return "dns";
        if (type === "laptop")
            return "laptop";
        if (type === "tablet")
            return "tablet_mac";
        return "desktop_windows";
    }

    function deviceIcon(device): string {
        const chosen = String(root.deviceOverride(device).icon ?? "auto");
        return chosen === "auto" ? root.defaultDeviceIcon(device) : chosen;
    }

    function deviceName(device): string {
        const custom = String(root.deviceOverride(device).name ?? "").trim();
        return custom.length > 0 ? custom : device.name;
    }

    readonly property string phoneMirrorBin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/phone-mirror/scripts/phone`
    property bool phoneMirrorAvailable: false
    property bool phoneMirrorConfigured: false
    property string phoneMirrorHost: ""

    function normaliseHost(value): string {
        let host = String(value ?? "").trim().toLowerCase();
        if (host.includes("@"))
            host = host.split("@").pop();
        host = host.replace(/:\d+$/, "").replace(/\.$/, "");
        return host;
    }

    function phoneMirrorMatches(device): bool {
        if (!root.phoneMirrorAvailable || !root.phoneMirrorConfigured || device.type !== "phone")
            return false;
        const wanted = root.normaliseHost(root.phoneMirrorHost);
        if (!wanted)
            return false;
        const candidates = [device.id, device.actionHost, device.name]
            .map(value => root.normaliseHost(value));
        const wantedShort = wanted.split(".")[0];
        return candidates.some(value => value === wanted || value.split(".")[0] === wantedShort);
    }

    Process {
        id: phoneMirrorProbe
        command: [root.phoneMirrorBin, "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.phoneMirrorAvailable = true;
                    root.phoneMirrorConfigured = !!data.configured;
                    root.phoneMirrorHost = String(data.ssh_host || data.tailscale_ip || "");
                } catch (e) {
                    root.phoneMirrorAvailable = false;
                    root.phoneMirrorConfigured = false;
                    root.phoneMirrorHost = "";
                }
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.phoneMirrorAvailable = false;
                root.phoneMirrorConfigured = false;
            }
        }
    }

    function syncExitMenu(): void {
        routeMenu.active = null;
    }

    function rebuildExitMenu(): void {
        for (const item of exitMenuItems) {
            if (item !== directExitItem)
                item.destroy();
        }

        const items = [directExitItem];
        for (const node of RemoteDesktop.RemoteStatus.exitNodes) {
            const item = exitNodeMenuItem.createObject(root, {
                text: node.name,
                icon: "router",
                nodeId: node.id
            });
            if (item)
                items.push(item);
        }
        exitMenuItems = items;
        routeMenu.items = items;
        syncExitMenu();
    }

    Component.onCompleted: rebuildExitMenu()

    Connections {
        target: RemoteDesktop.RemoteStatus
        function onExitNodesChanged(): void { root.rebuildExitMenu(); }
        function onExitNodeIdChanged(): void { root.syncExitMenu(); }
    }

    MenuItem {
        id: directExitItem
        property string nodeId: ""
        text: qsTr("Direct")
        icon: "public"
    }

    Component {
        id: exitNodeMenuItem

        MenuItem {
            required property string nodeId
        }
    }

    component ActionButton: IconButton {
        id: btn

        required property string hint
        property bool accent: false

        type: IconButton.Text
        font: Tokens.font.icon.small
        shapeMorph: false

        Tooltip {
            target: btn
            text: btn.hint
        }
    }

    component HostRow: RowLayout {
        id: hostRow

        required property var device

        readonly property bool online: !!device.online
        readonly property string health: !online
            ? "offline"
            : !device.sshKnown
                ? "unknown"
                : device.sshAvailable
                    ? "reachable"
                    : "degraded"
        readonly property bool isPeer: device.id === RemoteDesktop.RemoteStatus.peerId
        readonly property bool viewing: isPeer && RemoteDesktop.RemoteStatus.viewing
        readonly property bool shared: isPeer && RemoteDesktop.RemoteStatus.shared
        readonly property bool hasSession: viewing || shared

        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.extraSmall
        Layout.rightMargin: Tokens.padding.extraSmall
        Layout.topMargin: Tokens.padding.extraSmall
        Layout.bottomMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.extraSmall

        Item {
            id: deviceIconWrap

            implicitWidth: deviceIcon.implicitWidth
            implicitHeight: deviceIcon.implicitHeight
            Layout.alignment: Qt.AlignVCenter

            MaterialIcon {
                id: deviceIcon

                anchors.centerIn: parent
                text: root.deviceIcon(hostRow.device)
                fontStyle: Tokens.font.icon.small
                color: hostRow.online
                    ? Colours.palette.m3onSurface
                    : Colours.palette.m3onSurfaceVariant
            }

            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                anchors.right: deviceIcon.right
                anchors.bottom: deviceIcon.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2
                color: hostRow.health === "reachable"
                    ? "#43a047"
                    : hostRow.health === "degraded"
                        ? "#d99a00"
                        : hostRow.health === "offline"
                            ? Colours.palette.m3error
                            : Colours.palette.m3outline
                border.width: 1
                border.color: Colours.palette.m3surface
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 72
            Layout.alignment: Qt.AlignVCenter
            text: root.deviceName(hostRow.device)
            elide: Text.ElideRight
            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 0

            ActionButton {
                visible: root.phoneMirrorMatches(hostRow.device)
                disabled: !hostRow.online
                icon: "link"
                hint: qsTr("Mirror phone")
                onClicked: Quickshell.execDetached([root.phoneMirrorBin])
            }

            ActionButton {
                visible: hostRow.device.canRemoteDesktop
                disabled: !hostRow.online || hostRow.shared
                accent: hostRow.viewing
                icon: hostRow.viewing ? "desktop_windows" : "link"
                hint: hostRow.viewing ? qsTr("Open remote desktop") : qsTr("Connect")
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.id, "open"])
            }

            ActionButton {
                visible: hostRow.hasSession
                icon: "link_off"
                hint: qsTr("Disconnect")
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.id, "leave"])
            }

            ActionButton {
                visible: hostRow.device.canWake
                icon: "bolt"
                hint: qsTr("Wake")
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.id, "wake"])
            }

            ActionButton {
                visible: hostRow.device.canSsh
                disabled: !hostRow.online || (hostRow.device.type !== "phone" && !hostRow.device.sshAvailable)
                icon: "terminal"
                hint: qsTr("Open terminal")
                onClicked: hostRow.device.type === "phone" ? Quickshell.execDetached(["kitty", "-e", "ssh", "nothing-phone"]) : Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.actionHost, "ssh"])
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.padding.extraSmall
        Layout.bottomMargin: 0
        Layout.leftMargin: Tokens.padding.extraSmall
        text: qsTr("Remote desktop")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    Repeater {
        model: RemoteDesktop.RemoteStatus.devices.filter(device => root.deviceEnabled(device))

        delegate: HostRow {
            required property var modelData
            device: modelData
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.extraSmall
        Layout.rightMargin: Tokens.padding.extraSmall
        Layout.topMargin: 0
        Layout.bottomMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            text: "route"
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Route")
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.small
        }

        Item {
            id: routePicker

            implicitWidth: routePickerRow.implicitWidth
            implicitHeight: routePickerRow.implicitHeight

            RowLayout {
                id: routePickerRow

                anchors.fill: parent
                spacing: 2

                StyledText {
                    text: RemoteDesktop.RemoteStatus.exitNodeActive
                        ? RemoteDesktop.RemoteStatus.exitNodeName
                        : qsTr("Direct")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }

                MaterialIcon {
                    text: "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: !RemoteDesktop.RemoteStatus.exitNodeChanging
                cursorShape: Qt.PointingHandCursor
                onClicked: routeMenu.expanded = !routeMenu.expanded
            }

            Menu {
                id: routeMenu

                attachTo: routePicker
                items: root.exitMenuItems
                active: null
                onItemSelected: item => {
                    RemoteDesktop.RemoteStatus.setExitNode(item.nodeId);
                    Qt.callLater(() => routeMenu.active = null);
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.extraSmall + Tokens.padding.large
        Layout.rightMargin: Tokens.padding.extraSmall
        Layout.bottomMargin: Tokens.padding.extraSmall
        visible: RemoteDesktop.RemoteStatus.exitNodeError.length > 0
        text: RemoteDesktop.RemoteStatus.exitNodeError
        color: Colours.palette.m3error
        wrapMode: Text.Wrap
        font: Tokens.font.label.small
    }
}
