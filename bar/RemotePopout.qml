pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QtControls
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import Caelestia.Plugins
import qs.components
import qs.components.controls
import qs.services
import dcqwqc.devices.services as RemoteDesktop
import dcqwqc.devices.quest as Quest
import qs.utils

Item {
    id: root

    // One truthful route label: the effective VPN country takes precedence
    // over the independent Tailscale exit-node selector.
    property bool vpnConnected: false
    property string vpnExitCountry: ""

    // Single horizontal inset for every primary section in the Devices tab.
    // Nested detail rows retain their left indent but have no extra right inset.
    readonly property real horizontalInset: Tokens.padding.small

    implicitWidth: 304
    // Keep the bar popout within a small/rotated display; expanding several
    // peers scrolls inside the panel rather than pushing it off screen.
    implicitHeight: Math.min(deviceContent.implicitHeight, maxPanelHeight)
    readonly property real maxPanelHeight: Math.max(220,
        Math.min(680, (Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 900) - 96))

    // Connect independent/unified mouse modes (scoped to paired desktops)
    readonly property string mouseModeBin: Quickshell.env("HOME") + "/.local/bin/caelestia-connect-mouse-mode"
    property string mouseMode: "unknown"
    property var mouseDesktopAvailable: null
    property bool mouseStatusChecked: false
    // Keep mode information visible for a configured online pair even when
    // the peer session has stopped. Only the actual Connect action needs a
    // verified compositor. This avoids silently hiding the entire control.
    readonly property bool mousePeerPresent: root.listedDevices.some(d =>
        !d.isSelf && d.online && d.canRemoteDesktop
        && !!root.transferTarget(d))
    readonly property bool mouseControlsAvailable: mousePeerPresent
    readonly property bool mouseConnectReady: mousePeerPresent && mouseDesktopAvailable === true
    property string mouseFeedback: ""
    property bool mousePending: mouseModeSet.running

    function refreshMouseMode(): void {
        if (mouseModePoll.running || mousePending)
            return;
        mouseModePoll.command = [mouseModeBin, "status"];
        mouseModePoll.running = true;
    }

    function chooseMouseMode(mode: string): void {
        if (mousePending)
            return;
        mouseFeedback = qsTr("Switching mouse mode…");
        mouseModeSet.command = [mouseModeBin, "set", mode].concat(mode === "unified" ? ["--onsite"] : []);
        mouseModeSet.running = true;
    }

    Process {
        id: mouseModePoll
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.mouseMode = data.mode;
                    root.mouseDesktopAvailable = typeof data.desktop_available === "boolean" ? data.desktop_available : null;
                    root.mouseStatusChecked = true;
                } catch (e) { root.mouseMode = "unknown"; root.mouseDesktopAvailable = null; root.mouseStatusChecked = true; }
            }
        }
    }

    Process {
        id: mouseModeSet
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.mouseMode = data.mode;
                    root.mouseFeedback = data.mode === "separate"
                        ? qsTr("Independent mice enabled on both computers")
                        : data.mode === "unified"
                        ? qsTr("Unified mouse and keyboard enabled")
                        : qsTr("Input state needs checking");
                } catch (e) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.mouseFeedback = text.trim();
            }
        }
        onExited: code => {
            if (code !== 0 && !root.mouseFeedback.startsWith("Mouse mode:"))
                root.mouseFeedback = qsTr("Could not change mouse mode; check peer SSH connection.");
            root.refreshMouseMode();
        }
    }

    Timer {
        interval: 7000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refreshMouseMode()
    }
    onVisibleChanged: if (visible) root.refreshMouseMode()
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
            || device.type === "server"
            || device.type === "headset"
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
        if (type === "headset")
            return "head_mounted_device";
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

    // Drag and drop is restricted to the paired desktop. Never send a file
    // automatically to an arbitrary Tailscale or SSH device.
    readonly property string transferBin: Quickshell.env("HOME") + "/.local/bin/caelestia-connect-send-target"
    property string transferFeedback: ""
    property string transferHostId: ""

    function transferTarget(device): string {
        if (!device || device.isSelf) return "";
        const values = [device.actionHost, device.name].map(x => root.normaliseHost(x).split(".")[0]);
        return values.includes("mirai") ? "mirai" : values.includes("tachibana") ? "tachibana" : "";
    }

    function sendFilesToDevice(device, drop): void {
        const target = transferTarget(device);
        if (!target || !drop.hasUrls || drop.urls.length === 0) {
            drop.accepted = false;
            return;
        }
        const paths = [];
        for (const item of drop.urls) {
            const url = String(item);
            if (!url.startsWith("file:///")) {
                root.transferHostId = String(device.id);
                root.transferFeedback = qsTr("Only local files can be dropped");
                drop.accepted = false;
                return;
            }
            paths.push(decodeURIComponent(url.substring(7)));
        }
        root.transferHostId = String(device.id);
        root.transferFeedback = qsTr("Sending %1 file(s) to %2. A desktop notification confirms completion.")
            .arg(paths.length).arg(target === "mirai" ? "Mirai" : "Tachibana");
        Quickshell.execDetached([transferBin, target].concat(paths));
        drop.accepted = true;
    }

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

    // Quest mirroring works over USB or wireless ADB, independently of the
    // headset's Tailscale state, so it has its own reachability probe.
    readonly property string questMirrorBin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/remote-desktop/scripts/quest-mirror`
    property bool questMirrorAvailable: false
    property bool questMirrorRunning: false
    property string questMirrorTransport: ""

    Process {
        id: questMirrorProbe
        command: [root.questMirrorBin, "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.questMirrorAvailable = !!data.available;
                    root.questMirrorRunning = !!data.running;
                    root.questMirrorTransport = String(data.transport ?? "");
                } catch (e) {
                    root.questMirrorAvailable = false;
                    root.questMirrorRunning = false;
                }
            }
        }
    }

    // Only while the popout is open: cheap adb/pgrep checks.
    Timer {
        interval: 3000
        repeat: true
        running: root.visible
        onTriggered: if (!questMirrorProbe.running) questMirrorProbe.running = true
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
        property bool showHint: false

        // Compact safety hint positioned to the LEFT of the recovery button.
        // It is a floating popup, never increasing the header layout width.
        QtControls.Popup {
            id: compactHint
            parent: btn
            x: -width - Tokens.spacing.small
            y: Math.min(0, (btn.height - height) / 2)
            width: 218
            padding: 9
            height: hintMessage.implicitHeight + padding * 2
            visible: btn.showHint && btn.hovered
            modal: false
            focus: false
            closePolicy: QtControls.Popup.NoAutoClose
            background: Rectangle {
                color: Colours.palette.m3surfaceContainerHighest
                radius: Tokens.rounding.small
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
            }
            contentItem: StyledText {
                id: hintMessage
                width: compactHint.width - compactHint.padding * 2
                text: btn.hint
                wrapMode: Text.WordWrap
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface
            }
        }

        // Material Symbols Rounded in a circular, understated touch target.
        // Keep control dimensions constant as active state changes.
        type: accent ? IconButton.Tonal : IconButton.Text
        font: Tokens.font.icon.small
        padding: Tokens.padding.extraSmall / 2
        isRound: true
        radiusMorph: false
        shapeMorph: false

        // Most icons are outlined; an active action receives a soft tint.
        inactiveColour: Qt.alpha(Colours.palette.m3primary, 0.12)
        inactiveOnColour: accent ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        label.fill: accent ? 1 : 0

    }

    component HostRow: ColumnLayout {
        id: hostRow

        required property var device

        readonly property bool isSelf: !!device.isSelf
        readonly property bool isHeadset: device.type === "headset"
        readonly property bool expanded: isSelf || root.isDeviceExpanded(device.id)
        // A headset counts as reachable whenever ADB reaches it (USB or
        // network), even while its Tailscale client is asleep.
        readonly property bool online: !!device.online || (isHeadset && root.questMirrorAvailable)
        // The local device summarizes the complete status of this machine,
        // including its MCP tunnel and connectivity dependencies.
        readonly property string health: isSelf
            ? RemoteDesktop.RemoteStatus.overallHealth
            : isHeadset ? (root.questMirrorAvailable ? "reachable" : "offline")
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
        Layout.leftMargin: root.horizontalInset
        Layout.rightMargin: root.horizontalInset
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

                DropArea {
                    id: nameDrop
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(0, parent.width - 19)
                    z: 5
                    enabled: !hostRow.isSelf && !!root.transferTarget(hostRow.device)
                    onEntered: drag => {
                        if (!drag.hasUrls || drag.urls.length === 0)
                            drag.accepted = false;
                    }
                    onDropped: drop => root.sendFilesToDevice(hostRow.device, drop)
                    Rectangle {
                        anchors.fill: parent
                        radius: 5
                        color: "transparent"
                        border.width: nameDrop.containsDrag ? 1 : 0
                        border.color: Colours.palette.m3outlineVariant
                    }
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


            // Compact, right-aligned per-device actions; details expand independently.
            // Connect / Wake / Terminal stay on the main row.
            RowLayout {
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                spacing: 0

                ActionButton {
                    visible: hostRow.isHeadset
                    disabled: !root.questMirrorAvailable && !root.questMirrorRunning
                    accent: root.questMirrorRunning
                    icon: root.questMirrorRunning ? "link_off" : "cast"
                    hint: root.questMirrorRunning ? qsTr("Stop headset mirroring") : qsTr("Mirror headset")
                    onClicked: {
                        Quickshell.execDetached([root.questMirrorBin]);
                        root.questMirrorRunning = !root.questMirrorRunning;
                    }
                }
                ActionButton {
                    visible: root.phoneMirrorMatches(hostRow.device)
                    disabled: !hostRow.online
                    icon: "smartphone"
                    hint: qsTr("Mirror phone")
                    onClicked: Quickshell.execDetached([root.phoneMirrorBin])
                }
                // Per-device shortcut for the unified mouse/keyboard mode.
                // This must remain available for stopping sharing even if the
                // peer compositor disconnects while the input mode is active.
                ActionButton {
                    visible: !hostRow.isSelf && !!root.transferTarget(hostRow.device)
                        && (root.mouseControlsAvailable || root.mouseMode === "unified")
                    disabled: root.mousePending ||
                        (root.mouseMode !== "unified" && !root.mouseConnectReady)
                    accent: root.mouseMode === "unified"
                    icon: "swap_horiz"
                    hint: root.mousePending ? qsTr("Switching mouse mode…")
                        : root.mouseMode === "unified" ? qsTr("Stop sharing mouse & keyboard")
                        : !root.mouseStatusChecked ? qsTr("Checking mouse sharing availability…")
                        : !root.mouseConnectReady ? qsTr("Mouse sharing unavailable: peer desktop offline")
                        : qsTr("Share mouse & keyboard")
                    onClicked: root.chooseMouseMode(root.mouseMode === "unified" ? "separate" : "unified")
                }
                ActionButton {
                    visible: hostRow.online && root.mouseConnectReady
                        && hostRow.device.canRemoteDesktop && !!root.transferTarget(hostRow.device)
                    disabled: hostRow.shared
                    accent: hostRow.viewing
                    icon: "desktop_windows"
                    hint: qsTr("Open remote desktop")
                    onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin,
                        root.transferTarget(hostRow.device) || hostRow.device.actionHost, "open"])
                }
                ActionButton {
                    visible: hostRow.online && root.mouseConnectReady
                        && !!root.transferTarget(hostRow.device)
                    icon: "visibility"
                    hint: qsTr("Preview one app (view only)")
                    onClicked: Quickshell.execDetached([Quickshell.env("HOME")
                        + "/.local/bin/caelestia-connect-window-preview-launch"])
                }
                ActionButton {
                    visible: hostRow.hasSession
                    icon: "link_off"
                    hint: qsTr("Disconnect remote session")
                    onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin,
                        hostRow.device.id, "leave"])
                }
                ActionButton {
                    visible: hostRow.device.canWake && !hostRow.online
                    icon: "bolt"
                    hint: qsTr("Wake computer")
                    onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin,
                        hostRow.device.id, "wake"])
                }
                ActionButton {
                    visible: hostRow.device.canSsh && !hostRow.isHeadset
                    disabled: !hostRow.online ||
                        (hostRow.device.type !== "phone" && !hostRow.device.sshAvailable)
                    icon: "code"
                    hint: qsTr("Open terminal")
                    onClicked: hostRow.device.type === "phone"
                        ? Quickshell.execDetached(["ghostty", "-e", "ssh", "nothing-phone"])
                        : Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin,
                            hostRow.device.actionHost, "ssh"])
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: 0
            visible: hostRow.health !== "reachable" && hostRow.expanded
            text: hostRow.isHeadset
                ? qsTr("Not reachable over ADB · plug in USB once to enable wireless")
                : hostRow.healthError.length > 0
                ? hostRow.healthError : qsTr("Health check pending; no diagnostic details received yet.")
            color: Colours.palette.m3error
            wrapMode: Text.Wrap
            font: Tokens.font.label.small
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.clipboardText = String(parent.text || "")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: 0
            visible: hostRow.expanded && !hostRow.isSelf && !!root.transferTarget(hostRow.device)
            text: qsTr("Drop files on this device's name to send to ~/Received Files")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: 0
            visible: root.transferHostId === String(hostRow.device.id) && root.transferFeedback.length > 0
            text: root.transferFeedback
            color: Colours.palette.m3primary
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        // Remote peers can show their diagnosis on demand without moving any actions.
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: 0
            visible: !hostRow.isSelf && hostRow.expanded && hostRow.health === "reachable"
            text: hostRow.isHeadset
                ? (root.questMirrorTransport === "usb" ? qsTr("ADB over USB") : qsTr("ADB over network"))
                : qsTr("Tailscale connected · SSH TCP/22 reachable")
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
            font: Tokens.font.label.small
        }

        // Which desktop of this computer the headset shows and controls.
        Loader {
            // This is a control for the local host's desktop, not another
            // device row. Indent it beneath the computer name and label the
            // host explicitly so it cannot be confused with the Quest peer.
            Layout.fillWidth: true
            Layout.leftMargin: 36
            Layout.rightMargin: 0
            active: hostRow.isSelf && Quest.QuestSession.available
            visible: active
            sourceComponent: HeadsetDesktop { hostLabel: root.deviceName(hostRow.device) }
        }
    }

    // Shared: the local computer's desktop. Private: a separate desktop with
    // its own windows, pointer and keyboard, started on demand. This is a
    // nested host setting, deliberately distinct from the Quest device row.
    component HeadsetDesktop: ColumnLayout {
        id: choice

        property string hostLabel: qsTr("this computer")
        readonly property var session: Quest.QuestSession
        readonly property bool wantsPrivate: session.pendingAction === "select-private" || session.pendingAction === "start"
        readonly property bool wantsShared: session.pendingAction === "select-shared"

        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            Item {
                implicitWidth: 20
                implicitHeight: 20
                Layout.alignment: Qt.AlignVCenter

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "desktop_windows"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3secondary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Quest desktop")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Hosted by %1").arg(choice.hostLabel)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 20 + Tokens.spacing.extraSmall
            spacing: Tokens.spacing.extraSmall

            ButtonRow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                IconTextButton {
                    fillWidth: true
                    isToggle: true
                    type: IconTextButton.Tonal
                    icon: "screen_share"
                    text: qsTr("Shared")
                    font: Tokens.font.label.medium
                    verticalPadding: Tokens.padding.extraSmall
                    checked: choice.wantsShared || (choice.session.sharedSelected && !choice.wantsPrivate)
                    internalChecked: checked
                    disabled: choice.session.busy
                    onClicked: if (!choice.session.sharedSelected) choice.session.select("shared")
                }

                IconTextButton {
                    fillWidth: true
                    isToggle: true
                    type: IconTextButton.Tonal
                    icon: "lock_person"
                    text: qsTr("Private")
                    font: Tokens.font.label.medium
                    verticalPadding: Tokens.padding.extraSmall
                    checked: choice.wantsPrivate || (choice.session.privateSelected && !choice.wantsShared)
                    internalChecked: checked
                    disabled: choice.session.busy
                    // Choosing Private starts it when needed.
                    onClicked: if (!choice.session.privateSelected) choice.session.selectPrivate()
                }
            }

            // A private desktop left running in the background can be closed
            // here; it otherwise keeps its windows for next time.
            ActionButton {
                visible: choice.session.privateReady && choice.session.sharedSelected
                disabled: choice.session.busy
                icon: "power_settings_new"
                hint: qsTr("Close the private desktop")
                onClicked: choice.session.stop()
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 20 + Tokens.spacing.extraSmall
            visible: !choice.session.busy && (choice.session.actionError.length > 0 || choice.session.statusError.length > 0)
            text: choice.session.actionError.length > 0 ? choice.session.actionError : choice.session.statusError
            color: Colours.palette.m3error
            wrapMode: Text.Wrap
            font: Tokens.font.label.small
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.clipboardText = String(parent.text || "")
            }
        }
    }

    component VpnRoutePanel: ColumnLayout {
        id: vpn
        Layout.fillWidth: true
        spacing: 4

        readonly property string helper: Quickshell.env("HOME")
            + "/.local/share/caelestia/plugins/remote-desktop/scripts/vpngate-route"
        property bool expanded: false
        property bool connected: false
        property bool tailscaleExitActive: false
        property bool browsing: false
        property bool working: false
        property bool showCountries: false
        property bool sortExpanded: false
        property string sortMode: "recommended"
        property var sortModes: [
            { id: "recommended", label: qsTr("Recommended") },
            { id: "fastest", label: qsTr("Fastest") },
            { id: "latency", label: qsTr("Low latency") },
            { id: "line", label: qsTr("Line speed") }
        ]
        property string probeSummary: ""
        property string measuredSpeed: ""
        property string countryCode: "JP"
        property string countryName: "Japan"
        property string selectedId: ""
        property string serverIp: ""
        property string errorText: ""
        property string verifiedExit: ""
        property string browseAction: ""
        property string nextCountry: ""
        property string actionName: ""
        property var countries: []
        property var servers: []

        onConnectedChanged: {
            root.vpnConnected = connected;
            root.vpnExitCountry = connected ? countryName : "";
        }
        onCountryNameChanged: if (connected) root.vpnExitCountry = countryName;

        function sortLabel(mode) {
            const option = sortModes.find(x => x.id === mode);
            return option ? option.label : qsTr("Recommended");
        }

        function readStatus() {
            if (statusProcess.running || working)
                return;
            statusProcess.command = [helper, "status"];
            statusProcess.running = true;
        }

        function browse(action, argument) {
            if (browsing)
                return;
            browsing = true;
            browseAction = action;
            browserProcess.command = [helper, action].concat(argument ? [argument] : []);
            browserProcess.running = true;
        }

        function changeCountry(code, name) {
            if (browsing || working || connected)
                return;
            countryCode = code;
            countryName = name;
            showCountries = false;
            sortExpanded = false;
            probeSummary = "";
            selectedId = "";
            servers = [];
            browse("servers", code);
        }

        function action(name) {
            if (working)
                return;
            if (name === "connect" && !selectedId) {
                errorText = qsTr("Choose a server.");
                return;
            }
            if (name === "connect" && tailscaleExitActive) {
                errorText = qsTr("Set Route to Direct first.");
                return;
            }
            working = true;
            actionName = name;
            errorText = "";
            verifiedExit = "";
            actionProcess.command = [helper, name]
                .concat(name === "connect" ? [selectedId] : []);
            actionProcess.running = true;
        }

        Process {
            id: statusProcess
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const result = JSON.parse(text.trim());
                        if (!result.ok)
                            return;
                        vpn.connected = !!result.connected;
                        vpn.tailscaleExitActive = !!result.tailscaleExitActive;
                        if (result.sort) vpn.sortMode = result.sort;
                        vpn.serverIp = result.server || "";
                        if (vpn.connected && result.serverId)
                            vpn.selectedId = result.serverId;
                        if (vpn.connected && result.country) {
                            vpn.countryCode = result.country;
                            vpn.countryName = result.location || result.country;
                        }
                    } catch (e) {}
                }
            }
        }

        Process {
            id: browserProcess
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const result = JSON.parse(text.trim());
                        if (!result.ok) {
                            vpn.errorText = result.error || qsTr("Couldn't load VPN Gate.");
                            return;
                        }
                        if (vpn.browseAction === "sort") {
                            vpn.sortMode = result.sort || "recommended";
                            vpn.nextCountry = vpn.countryCode;
                        } else if (vpn.browseAction === "probe") {
                            vpn.probeSummary = qsTr("%1/%2 reachable")
                                .arg(result.responsive || 0).arg(result.checked || 0);
                            vpn.nextCountry = vpn.countryCode;
                        } else if (vpn.browseAction === "countries" || vpn.browseAction === "refresh") {
                            vpn.countries = result.countries || [];
                            if (!vpn.countries.some(c => c.code === vpn.countryCode) && vpn.countries.length) {
                                vpn.countryCode = vpn.countries[0].code;
                                vpn.countryName = vpn.countries[0].name;
                            } else {
                                const selected = vpn.countries.find(c => c.code === vpn.countryCode);
                                if (selected) vpn.countryName = selected.name;
                            }
                            vpn.nextCountry = vpn.countryCode;
                        } else if (vpn.browseAction === "servers") {
                            vpn.servers = result.servers || [];
                            if (!vpn.servers.some(s => s.id === vpn.selectedId))
                                vpn.selectedId = vpn.servers.length ? vpn.servers[0].id : "";
                            if (vpn.connected) {
                                const currentIndex = vpn.servers.findIndex(s => s.id === vpn.selectedId);
                                if (currentIndex >= 0)
                                    Qt.callLater(() => serverList.positionViewAtIndex(currentIndex, ListView.Center));
                            }
                        }
                    } catch (e) {
                        vpn.errorText = qsTr("Couldn't read server list.");
                    }
                }
            }
            onExited: code => {
                vpn.browsing = false;
                if (code !== 0 && !vpn.errorText)
                    vpn.errorText = qsTr("Server directory unavailable. Try refresh.");
                if (code === 0 && vpn.nextCountry) {
                    const codeToLoad = vpn.nextCountry;
                    vpn.nextCountry = "";
                    Qt.callLater(() => vpn.browse("servers", codeToLoad));
                }
            }
        }

        Process {
            id: actionProcess
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const result = JSON.parse(text.trim());
                        if (!result.ok) {
                            vpn.errorText = result.error || qsTr("VPN connection failed.");
                            return;
                        }
                        if (vpn.actionName === "verify") {
                            vpn.verifiedExit = qsTr("%1 · %2").arg(result.country || "?").arg(result.ip || "?");
                        } else if (vpn.actionName === "benchmark") {
                            vpn.measuredSpeed = Number(result.measuredMbps).toFixed(1) + " Mb/s";
                            vpn.verifiedExit = qsTr("%1 · %2").arg(result.country || "?").arg(result.ip || "?");
                        } else {
                            vpn.connected = !!result.connected;
                            vpn.serverIp = result.server || "";
                        }
                    } catch (e) {
                        vpn.errorText = qsTr("VPN returned an invalid response.");
                    }
                }
            }
            onExited: code => {
                vpn.working = false;
                if (code !== 0 && !vpn.errorText)
                    vpn.errorText = qsTr("VPN action failed. Check NetworkManager or retry.");
                if (code === 0 && vpn.actionName === "benchmark" && !vpn.browsing)
                    Qt.callLater(() => vpn.browse("servers", vpn.countryCode));
                statusTimer.restart();
            }
        }

        Timer {
            id: statusTimer
            interval: 650
            repeat: false
            onTriggered: vpn.readStatus()
        }
        Timer {
            interval: 15000
            repeat: true
            running: vpn.visible
            onTriggered: vpn.readStatus()
        }
        Component.onCompleted: vpn.readStatus()
        onExpandedChanged: {
            if (expanded) {
                readStatus();
                if (!countries.length)
                    browse("countries", "");
            } else {
                showCountries = false;
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 33
            radius: Tokens.rounding.medium
            color: vpn.expanded ? Colours.tPalette.m3surfaceContainerHighest : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 7
                spacing: Tokens.spacing.extraSmall
                MaterialIcon {
                    text: "public"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    text: qsTr("VPN")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: vpn.connected ? "#43a047" : Colours.palette.m3onSurfaceVariant
                }
                StyledText {
                    text: vpn.connected ? vpn.countryName : qsTr("Off")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                MaterialIcon {
                    text: vpn.expanded ? "expand_less" : "expand_more"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
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
            // The parent VPN section already has the shared horizontal inset.
            // No second inset here: country, servers and connect share edges.
            Layout.bottomMargin: 3
            spacing: 4
            visible: vpn.expanded

            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 9
                    color: Colours.tPalette.m3surfaceContainerHighest
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 7
                        spacing: 5
                        StyledText {
                            Layout.fillWidth: true
                            text: vpn.countries.length ? vpn.countryName
                                : vpn.browsing ? qsTr("Loading countries…") : qsTr("Choose country")
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurface
                        }
                        MaterialIcon {
                            text: vpn.showCountries ? "expand_less" : "expand_more"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !vpn.connected && vpn.countries.length > 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: vpn.showCountries = !vpn.showCountries
                    }
                }
                Rectangle {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 9
                    color: Colours.tPalette.m3surfaceContainerHighest
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "refresh"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !vpn.browsing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            vpn.errorText = "";
                            vpn.browse("refresh", "");
                        }
                    }
                }
            }

            ListView {
                id: countryList
                Layout.fillWidth: true
                Layout.preferredHeight: vpn.showCountries ? Math.min(5, vpn.countries.length) * 30 : 0
                visible: vpn.showCountries
                clip: true
                interactive: vpn.countries.length > 5
                boundsBehavior: Flickable.StopAtBounds
                model: vpn.countries
                delegate: Rectangle {
                    id: countryRow
                    required property var modelData
                    width: countryList.width
                    height: 30
                    radius: 7
                    color: countryRow.modelData.code === vpn.countryCode
                        ? Colours.tPalette.m3surfaceContainerHighest : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        spacing: 5
                        StyledText {
                            Layout.fillWidth: true
                            text: countryRow.modelData.name
                            font: Tokens.font.label.small
                        }
                        StyledText {
                            text: countryRow.modelData.count
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !vpn.browsing
                        onClicked: vpn.changeCountry(countryRow.modelData.code, countryRow.modelData.name)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    text: qsTr("Servers · %1").arg(vpn.servers.length
                        || vpn.countries.find(c => c.code === vpn.countryCode)?.count || 0)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                Item { Layout.fillWidth: true }
                ActionButton {
                    icon: "network_check"
                    disabled: vpn.browsing || vpn.connected
                    hint: vpn.probeSummary
                        ? qsTr("Local TCP check: %1 · Check again").arg(vpn.probeSummary)
                        : qsTr("Check local TCP response (up to 12 relays, no VPN change)")
                    onClicked: vpn.browse("probe", vpn.countryCode)
                }
                Rectangle {
                    implicitWidth: Math.max(94, sortName.implicitWidth + 23)
                    implicitHeight: 26
                    radius: 8
                    color: Colours.tPalette.m3surfaceContainerHighest
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 6
                        spacing: 3
                        StyledText {
                            id: sortName
                            text: vpn.sortLabel(vpn.sortMode)
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                        }
                        MaterialIcon {
                            text: vpn.sortExpanded ? "expand_less" : "expand_more"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !vpn.browsing
                        onClicked: {
                            vpn.showCountries = false;
                            vpn.sortExpanded = !vpn.sortExpanded;
                        }
                    }
                }
            }

            ListView {
                id: sortList
                Layout.fillWidth: true
                Layout.preferredHeight: vpn.sortExpanded ? vpn.sortModes.length * 29 : 0
                visible: vpn.sortExpanded
                clip: true
                interactive: false
                model: vpn.sortModes
                delegate: Rectangle {
                    id: modeRow
                    required property var modelData
                    width: sortList.width
                    height: 29
                    radius: 7
                    color: modeRow.modelData.id === vpn.sortMode
                        ? Colours.tPalette.m3surfaceContainerHighest : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: modeRow.modelData.label
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                        }
                        MaterialIcon {
                            visible: modeRow.modelData.id === vpn.sortMode
                            text: "check"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !vpn.browsing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            vpn.sortExpanded = false;
                            vpn.browse("sort", modeRow.modelData.id);
                        }
                    }
                }
            }

            ListView {
                id: serverList
                Layout.fillWidth: true
                readonly property int rowHeight: 34
                Layout.preferredHeight: Math.min(3, vpn.servers.length) * rowHeight
                implicitHeight: Math.min(3, vpn.servers.length) * rowHeight
                visible: vpn.servers.length > 0
                clip: true
                interactive: vpn.servers.length > 3
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                model: vpn.servers
                delegate: Rectangle {
                    id: relayRow
                    required property var modelData
                    required property int index
                    width: serverList.width
                    height: serverList.rowHeight
                    radius: 8
                    readonly property bool selected: vpn.selectedId === relayRow.modelData.id
                    color: relayRow.selected ? Colours.tPalette.m3surfaceContainerHighest : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 6
                        MaterialIcon {
                            text: relayRow.selected ? "radio_button_checked" : "radio_button_unchecked"
                            fontStyle: Tokens.font.icon.small
                            color: relayRow.selected ? "#43a047" : Colours.palette.m3onSurfaceVariant
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Server %1").arg(relayRow.index + 1)
                            font: Tokens.font.label.small
                        }
                        StyledText {
                            text: vpn.sortMode === "latency"
                                ? relayRow.modelData.latencyMs !== null
                                    ? relayRow.modelData.latencyMs + " ms · checked" : qsTr("No RTT test")
                                : relayRow.modelData.measuredMbps !== null
                                    ? relayRow.modelData.measuredMbps.toFixed(1) + " Mb/s · tested"
                                : relayRow.modelData.mbps.toFixed(1) + " Mb/s · line"
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !vpn.connected && !vpn.working
                        cursorShape: Qt.PointingHandCursor
                        onClicked: vpn.selectedId = relayRow.modelData.id
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 9
                    color: vpn.connected ? Colours.tPalette.m3surfaceContainerHighest : Colours.palette.m3onSurface
                    opacity: vpn.working || (!vpn.connected && (!vpn.selectedId || vpn.tailscaleExitActive)) ? 0.58 : 1
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialIcon {
                            text: vpn.connected ? "power_settings_new" : "vpn_lock"
                            fontStyle: Tokens.font.icon.small
                            color: vpn.connected ? Colours.palette.m3onSurface : Colours.palette.m3surface
                        }
                        StyledText {
                            text: vpn.working
                                ? vpn.actionName === "verify" ? qsTr("Checking IP…")
                                : vpn.actionName === "disconnect" ? qsTr("Disconnecting…") : qsTr("Connecting…")
                                : vpn.connected ? qsTr("Disconnect · %1").arg(vpn.countryName)
                                : vpn.tailscaleExitActive ? qsTr("Route → Direct first")
                                : !vpn.selectedId ? qsTr("Select a server")
                                : qsTr("Connect · %1").arg(vpn.countryName)
                            font: Tokens.font.label.small
                            color: vpn.connected ? Colours.palette.m3onSurface : Colours.palette.m3surface
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !vpn.working && (vpn.connected || (!!vpn.selectedId && !vpn.tailscaleExitActive))
                        cursorShape: Qt.PointingHandCursor
                        onClicked: vpn.action(vpn.connected ? "disconnect" : "connect")
                    }
                }
                ActionButton {
                    visible: vpn.connected
                    icon: "travel_explore"
                    hint: vpn.verifiedExit ? qsTr("Verified exit: %1").arg(vpn.verifiedExit)
                        : qsTr("Verify exit IP")
                    onClicked: vpn.action("verify")
                }
                ActionButton {
                    visible: vpn.connected
                    icon: "speed"
                    disabled: vpn.working
                    hint: vpn.measuredSpeed
                        ? qsTr("Measured: %1 · Retest (2 MB)").arg(vpn.measuredSpeed)
                        : qsTr("Measure VPN download speed (2 MB)")
                    onClicked: vpn.action("benchmark")
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: vpn.errorText.length > 0
                text: vpn.errorText
                color: Colours.palette.m3error
                font: Tokens.font.label.small
                wrapMode: Text.Wrap
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.clipboardText = String(parent.text || "")
                }
            }
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
        Layout.leftMargin: root.horizontalInset
        Layout.rightMargin: root.horizontalInset
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Devices")
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
        }

        // Automatic recovery comes first. Explicit repair is a fallback
        // requiring authorization if Tailscale must be restarted.
        ActionButton {
            id: connectionRecoveryButton
            visible: RemoteDesktop.RemoteStatus.tailscaleStatusChecked
                && RemoteDesktop.RemoteStatus.overallHealth !== "reachable"
            icon: RemoteDesktop.RemoteStatus.selfHealing
                || RemoteDesktop.RemoteStatus.connectivityRepairing
                ? "hourglass_top" : "build_circle"
            accent: true
            showHint: true
            hint: RemoteDesktop.RemoteStatus.selfHealing
                ? qsTr("Automatic recovery is checking enabled user services.")
                : qsTr("Repair connection: recheck diagnostics and recover stopped user services. Tailscale restart requires authorization. VPN routes and files remain unchanged.")
            disabled: RemoteDesktop.RemoteStatus.selfHealing
                || RemoteDesktop.RemoteStatus.connectivityRepairing
            onClicked: RemoteDesktop.RemoteStatus.repairConnection()
        }

        ActionButton {
            icon: "refresh"
            hint: qsTr("Refresh status only; no restarts or route changes")
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
        Layout.leftMargin: root.horizontalInset
        Layout.rightMargin: root.horizontalInset
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
        Layout.leftMargin: root.horizontalInset
        Layout.rightMargin: root.horizontalInset
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
                    text: root.vpnConnected ? root.vpnExitCountry
                        : RemoteDesktop.RemoteStatus.exitNodeActive
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

                // Menu falls back to attachTo.parent when there is no QsWindow.
                // That parent is a RowLayout here, so its anchors.fill binding
                // conflicts with layout geometry (undefined Qt behavior).
                // Use the popout root for the menu overlay instead.
                parent: root
                attachTo: routePicker
                // The route picker is the last row; open the menu above it
                // instead of past the bottom edge of the popout/screen.
                attachSideY: Menu.Top
                thisSideY: Menu.Bottom
                items: root.exitMenuItems
                active: null
                onItemSelected: item => {
                    if (root.vpnConnected) {
                        // The Route row reports the effective exit, including
                        // VPN Gate, not just the Tailscale selection.
                        if (!item.nodeId)
                            vpnPanel.action("disconnect");
                        else {
                            vpnPanel.expanded = true;
                            vpnPanel.errorText = qsTr("Disconnect VPN before choosing a Tailscale exit node.");
                        }
                    } else {
                        RemoteDesktop.RemoteStatus.setExitNode(item.nodeId);
                    }
                    Qt.callLater(() => routeMenu.active = null);
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: root.horizontalInset
        Layout.rightMargin: root.horizontalInset
        Layout.bottomMargin: Tokens.padding.extraSmall
        visible: RemoteDesktop.RemoteStatus.exitNodeError.length > 0
        text: RemoteDesktop.RemoteStatus.exitNodeError
        color: Colours.palette.m3error
        wrapMode: Text.Wrap
        font: Tokens.font.label.small
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.clipboardText = String(parent.text || "")
        }
    }

    // Separate from the existing Tailscale Route/MCP tunnel controls.
    VpnRoutePanel {
        id: vpnPanel
        Layout.fillWidth: true
        Layout.leftMargin: root.horizontalInset
        Layout.rightMargin: root.horizontalInset
    }

        } // deviceContent
    } // Flickable
}
