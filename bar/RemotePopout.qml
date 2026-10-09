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
import dcqwqc.devices.services as RemoteDesktop
import qs.utils

Item {
    id: root

    implicitWidth: 304
    // Keep the bar popout within a small/rotated display; expanding several
    // peers scrolls inside the panel rather than pushing it off screen.
    implicitHeight: Math.min(deviceContent.implicitHeight, maxPanelHeight)
    readonly property real maxPanelHeight: Math.max(220,
        Math.min(680, (Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 900) - 96))

    property var exitMenuItems: []
    // Keep expanded peers stable across the five-second Tailscale poll, which
    // replaces the device objects (and may recreate Repeater delegates).
    property var expandedDevices: ({})
    readonly property var selfDevice: RemoteDesktop.RemoteStatus.devices.find(device => device.isSelf)
    readonly property var listedDevices: {
        const local = selfDevice ?? {
            id: "local-device-pending",
            name: qsTr("This device"),
            actionHost: "",
            online: false,
            sshKnown: false,
            sshAvailable: false,
            type: "desktop",
            isSelf: true,
            canSsh: false,
            canRemoteDesktop: false,
            canWake: false
        };
        const peers = RemoteDesktop.RemoteStatus.devices
            .filter(device => !device.isSelf && root.deviceEnabled(device))
            .sort((a, b) => root.deviceName(a).localeCompare(root.deviceName(b)));
        return [local].concat(peers);
    }

    function isDeviceExpanded(id): bool {
        return !!expandedDevices[id];
    }

    function toggleDeviceExpanded(id): void {
        const next = Object.assign({}, expandedDevices);
        if (next[id]) delete next[id];
        else next[id] = true;
        expandedDevices = next;
    }

    readonly property var remoteSettings: {
        const plugin = Plugins.plugins.find(candidate => candidate.id === "dcqwqc/devices");
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
        if (!device.isSelf && String(device.name ?? "").trim().toLowerCase() === "localhost")
            return false;
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

    }

    component HostRow: ColumnLayout {
        id: hostRow

        required property var device

        readonly property bool isSelf: !!device.isSelf
        readonly property bool expanded: isSelf || root.isDeviceExpanded(device.id)
        readonly property bool online: !!device.online
        // The local device summarizes the complete status of this machine,
        // including its MCP tunnel and connectivity dependencies.
        readonly property string health: isSelf
            ? RemoteDesktop.RemoteStatus.overallHealth
            : RemoteDesktop.RemoteStatus.deviceHealth(device)
        readonly property string healthError: isSelf
            ? RemoteDesktop.RemoteStatus.overallError
            : RemoteDesktop.RemoteStatus.deviceError(device)
        readonly property bool isPeer: device.id === RemoteDesktop.RemoteStatus.peerId
        readonly property bool viewing: isPeer && RemoteDesktop.RemoteStatus.viewing
        readonly property bool shared: isPeer && RemoteDesktop.RemoteStatus.shared
        readonly property bool hasSession: viewing || shared
        // No status words: the dot is the only at-a-glance health indicator.

        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        Layout.rightMargin: Tokens.padding.small
        Layout.topMargin: Tokens.padding.extraSmall
        Layout.bottomMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Item {
                id: deviceIconWrap
                implicitWidth: 28
                implicitHeight: 28
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
                    color: hostRow.health === "reachable" ? "#43a047"
                        : hostRow.health === "offline" ? Colours.palette.m3error
                        : "#d99a00" // Pending/unknown is amber, never silently green.
                    border.width: 1
                    border.color: Colours.palette.m3surface
                }
            }

            // The name and small chevron are one left-aligned cluster.
            // The arrow stays immediately next to the visible text even when
            // wide names are elided to leave room for the action controls.
            Item {
                id: nameAndChevron
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: deviceNameText.implicitHeight + 2

                StyledText {
                    id: deviceNameText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, parent.width - (hostRow.isSelf ? 0 : 19)))
                    text: root.deviceName(hostRow.device)
                    elide: Text.ElideRight
                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                }

                Item {
                    id: detailsChevron
                    visible: !hostRow.isSelf
                    width: 19
                    height: 24
                    anchors.left: deviceNameText.right
                    anchors.verticalCenter: parent.verticalCenter

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: hostRow.expanded ? "expand_less" : "expand_more"
                        fontStyle: Tokens.font.icon.size(deviceNameText.font.pointSize).build()
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleDeviceExpanded(hostRow.device.id)
                    }
                }
            }

            // Connect / Wake / Terminal stay on the main row and are never
            // gated by the diagnostics chevron, just like the original UI.
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
                    onClicked: hostRow.device.type === "phone"
                        ? Quickshell.execDetached(["ghostty", "-e", "ssh", "nothing-phone"])
                        : Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.actionHost, "ssh"])
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.extraSmall
            visible: hostRow.health !== "reachable" && hostRow.expanded
            text: hostRow.healthError.length > 0
                ? hostRow.healthError : qsTr("Health check pending; no diagnostic details received yet.")
            color: Colours.palette.m3error
            wrapMode: Text.Wrap
            font: Tokens.font.label.small
        }

        // Remote peers can show their diagnosis on demand without moving any actions.
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.extraSmall
            visible: !hostRow.isSelf && hostRow.expanded && hostRow.health === "reachable"
            text: qsTr("Tailscale connected · SSH TCP/22 reachable")
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
            font: Tokens.font.label.small
        }
    }

    Flickable {
        anchors.fill: parent
        clip: true
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: deviceContent.implicitHeight

        ColumnLayout {
            id: deviceContent
            width: parent.width
            spacing: Tokens.spacing.extraSmall

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.padding.extraSmall
        Layout.leftMargin: Tokens.padding.extraSmall
        Layout.rightMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Devices")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        ActionButton {
            icon: "refresh"
            hint: qsTr("Check device connections now")
            onClicked: RemoteDesktop.RemoteStatus.refreshNow()
        }
    }

    // All devices remain listed, but only the current device is always expanded.
    // Unlike the old filter, the local device can never be hidden by overrides.
    Repeater {
        model: root.listedDevices

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
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            text: "cloud_sync"
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("MCP tunnel")
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.small
        }

        Rectangle {
            width: 7
            height: 7
            radius: 3.5
            color: RemoteDesktop.RemoteStatus.tunnelState === "online" ? "#43a047"
                : RemoteDesktop.RemoteStatus.tunnelState === "offline" ? Colours.palette.m3error
                : "#d99a00"
        }

        StyledText {
            text: RemoteDesktop.RemoteStatus.tunnelHost
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
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

        } // deviceContent
    } // Flickable
}
