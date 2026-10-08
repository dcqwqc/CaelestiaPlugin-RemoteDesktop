pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Plugins
import qs.components
import qs.components.controls
import qs.modules.nexus.common
import qs.services
import dcqwqc.devices.services as RemoteDesktop

ColumnLayout {
    id: root

    property var settings: null
    Layout.fillWidth: true
    spacing: Tokens.spacing.extraSmall / 2

    readonly property var iconChoices: [
        { label: "Auto", value: "auto" },
        { label: "Desktop PC", value: "desktop_windows" },
        { label: "Laptop", value: "laptop" },
        { label: "Server", value: "dns" },
        { label: "Phone", value: "smartphone" },
        { label: "Tablet", value: "tablet_mac" }
    ]

    readonly property var devices: {
        const copy = (RemoteDesktop.RemoteStatus.devices ?? []).slice();
        copy.sort((a, b) => {
            const aSelf = a.isSelf ? 0 : 1;
            const bSelf = b.isSelf ? 0 : 1;
            if (aSelf !== bSelf)
                return aSelf - bSelf;
            return String(a.name ?? a.id).localeCompare(String(b.name ?? b.id));
        });
        return copy;
    }

    function readOverrides(): var {
        if (!root.settings)
            return {};
        try {
            const parsed = JSON.parse(root.settings.deviceOverridesJson || "{}");
            return parsed && typeof parsed === "object" ? parsed : {};
        } catch (e) {
            return {};
        }
    }

    function overrideFor(device): var {
        return root.readOverrides()[device.id] ?? {};
    }

    function defaultEnabled(device): bool {
        return !!device.isSelf
            || !!device.online
            || !!device.canRemoteDesktop
            || !!device.canWake
            || (!!device.canSsh && !!device.sshAvailable);
    }

    function enabledFor(device): bool {
        const cfg = root.overrideFor(device);
        return cfg.enabled === undefined ? root.defaultEnabled(device) : !!cfg.enabled;
    }

    function customNameFor(device): string {
        return String(root.overrideFor(device).name ?? "");
    }

    function iconChoiceFor(device): string {
        return String(root.overrideFor(device).icon ?? "auto");
    }

    function defaultIconFor(device): string {
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

    function effectiveIconFor(device): string {
        const chosen = root.iconChoiceFor(device);
        return chosen === "auto" ? root.defaultIconFor(device) : chosen;
    }

    function iconLabel(value): string {
        const item = root.iconChoices.find(choice => choice.value === value);
        return item ? item.label : "Auto";
    }

    function writeOverride(deviceId, key, value): void {
        if (!root.settings)
            return;

        const all = root.readOverrides();
        const current = Object.assign({}, all[deviceId] ?? {});
        current[key] = value;
        all[deviceId] = current;
        root.settings.deviceOverridesJson = JSON.stringify(all);
    }

    component IconPicker: Item {
        id: picker

        required property var device

        implicitWidth: button.implicitWidth
        implicitHeight: button.implicitHeight

        property alias expanded: button.expanded

        readonly property var menuEntries: root.iconChoices.map(choice => optionItem.createObject(picker, {
            text: choice.label,
            storedValue: choice.value
        }))

        SplitButton {
            id: button
            anchors.fill: parent
            type: SplitButton.Tonal
            menuItems: picker.menuEntries
            active: {
                const current = root.iconChoiceFor(picker.device);
                const idx = root.iconChoices.findIndex(choice => choice.value === current);
                return picker.menuEntries[Math.max(0, idx)] ?? null;
            }
            stateLayer.onClicked: button.expanded = !button.expanded
            menu.onItemSelected: item => root.writeOverride(picker.device.id, "icon", item.storedValue)
        }

        Component {
            id: optionItem
            MenuItem {
                property string storedValue
            }
        }
    }

    SectionHeader {
        first: true
        text: "Devices"
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        Layout.rightMargin: Tokens.padding.small
        Layout.bottomMargin: Tokens.spacing.small
        text: "Rename devices, hide them from Devices, or override the automatically detected icon."
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        wrapMode: Text.WordWrap
    }

    Repeater {
        id: deviceRepeater
        model: root.devices

        ConnectedRect {
            id: deviceRow

            required property var modelData
            required property int index

            readonly property var device: modelData

            Layout.fillWidth: true
            first: index === 0
            last: index === deviceRepeater.count - 1
            implicitHeight: deviceLayout.implicitHeight + Tokens.padding.medium * 2
            clip: false
            z: iconPicker.expanded ? 20 : 0

            ColumnLayout {
                id: deviceLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    Item {
                        readonly property string health: !deviceRow.device.online
                            ? "offline"
                            : !deviceRow.device.sshKnown
                                ? "unknown"
                                : deviceRow.device.sshAvailable
                                    ? "reachable"
                                    : "degraded"

                        implicitWidth: previewIcon.implicitWidth
                        implicitHeight: previewIcon.implicitHeight

                        MaterialIcon {
                            id: previewIcon
                            anchors.centerIn: parent
                            text: root.effectiveIconFor(deviceRow.device)
                            color: root.enabledFor(deviceRow.device)
                                ? Colours.palette.m3onSurface
                                : Colours.palette.m3outline
                            font: Tokens.font.icon.medium
                        }

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            anchors.right: previewIcon.right
                            anchors.bottom: previewIcon.bottom
                            anchors.rightMargin: -2
                            anchors.bottomMargin: -2
                            color: parent.health === "reachable"
                                ? "#43a047"
                                : parent.health === "degraded"
                                    ? "#d99a00"
                                    : parent.health === "offline"
                                        ? Colours.palette.m3error
                                        : Colours.palette.m3outline
                            border.width: 1
                            border.color: Colours.palette.m3surface
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.customNameFor(deviceRow.device).trim().length
                                ? root.customNameFor(deviceRow.device)
                                : deviceRow.device.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: deviceRow.device.id
                                + (deviceRow.device.isSelf ? " · this device" : "")
                                + " · " + (!deviceRow.device.online
                                    ? "offline"
                                    : !deviceRow.device.sshKnown
                                        ? "checking…"
                                        : deviceRow.device.sshAvailable
                                            ? "reachable"
                                            : "Tailscale only")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledSwitch {
                        checked: root.enabledFor(deviceRow.device)
                        onToggled: root.writeOverride(deviceRow.device.id, "enabled", checked)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: nameInput.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainerHighest

                        StyledTextField {
                            id: nameInput
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            text: root.customNameFor(deviceRow.device)
                            placeholderText: deviceRow.device.name
                            horizontalAlignment: TextInput.AlignLeft
                            onEditingFinished: root.writeOverride(deviceRow.device.id, "name", text.trim())
                        }
                    }

                    IconPicker {
                        id: iconPicker
                        device: deviceRow.device
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.devices.length === 0
        text: "No Tailscale devices found."
        color: Colours.palette.m3outline
        font: Tokens.font.body.small
    }

    SectionHeader {
        text: "Streaming"
    }

    StepperRow {
        Layout.fillWidth: true
        first: true
        label: "Bitrate"
        subtext: "Kbps. Zero derives it from the streamed resolution."
        from: 0
        to: 80000
        stepSize: 500
        value: root.settings?.bitrate ?? 0
        onMoved: value => { if (root.settings) root.settings.bitrate = value; }
    }

    StepperRow {
        Layout.fillWidth: true
        label: "Frame rate"
        from: 30
        to: 144
        stepSize: 5
        value: root.settings?.fps ?? 60
        onMoved: value => { if (root.settings) root.settings.fps = value; }
    }

    StepperRow {
        Layout.fillWidth: true
        label: "Freeze after"
        subtext: "Seconds an unwatched remote workspace stays alive."
        from: 15
        to: 3600
        stepSize: 15
        value: root.settings?.freezeDelay ?? 300
        onMoved: value => { if (root.settings) root.settings.freezeDelay = value; }
    }

    ToggleRow {
        Layout.fillWidth: true
        text: "Follow the client's keyboard layout"
        subtext: "Retargets only the injected remote keyboard layout."
        checked: root.settings?.followKeyboardLayout ?? true
        onToggled: if (root.settings) root.settings.followKeyboardLayout = checked
    }

    SelectRow {
        id: systemKeysRow

        Layout.fillWidth: true
        last: true
        label: "Send system shortcuts to the remote"
        subtext: "Controls where Super and other system shortcuts are handled."

        readonly property var options: ["never", "fullscreen", "always"]
        readonly property var optionItems: options.map(option => systemKeyOption.createObject(systemKeysRow, { text: option }))

        menuItems: optionItems
        active: optionItems[Math.max(0, options.indexOf(root.settings?.captureSystemKeys ?? "always"))] ?? null
        onSelected: item => { if (root.settings) root.settings.captureSystemKeys = item.text; }

        Component {
            id: systemKeyOption
            MenuItem {}
        }
    }
}
