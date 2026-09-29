pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import dcqwqc.remotedesktop.services as RemoteDesktop
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts

    width: 336
    spacing: Tokens.spacing.extraSmall

    component ActionButton: IconButton {
        id: btn

        required property string hint
        property bool accent: false

        type: accent ? IconButton.Tonal : IconButton.Text
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
        readonly property bool isPeer: device.id === RemoteDesktop.RemoteStatus.peerId
        readonly property bool viewing: isPeer && RemoteDesktop.RemoteStatus.viewing
        readonly property bool shared: isPeer && RemoteDesktop.RemoteStatus.shared
        readonly property bool hasSession: viewing || shared

        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.extraSmall
        Layout.rightMargin: Tokens.padding.extraSmall
        Layout.topMargin: Tokens.padding.extraSmall
        Layout.bottomMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "computer"
            fontStyle: Tokens.font.icon.small
            color: hostRow.online
                ? Colours.palette.m3onSurface
                : Colours.palette.m3onSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 72
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: hostRow.device.name
                elide: Text.ElideRight
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
            }

            RowLayout {
                spacing: Tokens.spacing.extraSmall

                StyledRect {
                    implicitWidth: 6
                    implicitHeight: 6
                    radius: 3
                    color: !hostRow.online
                        ? Colours.palette.m3error
                        : hostRow.hasSession
                            ? Colours.palette.m3primary
                            : Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    text: !hostRow.online
                        ? qsTr("Offline")
                        : hostRow.viewing
                            ? qsTr("Connected")
                            : hostRow.shared
                                ? qsTr("Sharing")
                                : qsTr("Online")
                    color: !hostRow.online
                        ? Colours.palette.m3error
                        : hostRow.hasSession
                            ? Colours.palette.m3primary
                            : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 0

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
                disabled: !hostRow.online || !hostRow.device.sshAvailable
                icon: "terminal"
                hint: qsTr("Open terminal")
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.actionHost, "ssh"])
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.padding.small
        Layout.bottomMargin: Tokens.padding.extraSmall
        Layout.leftMargin: Tokens.padding.extraSmall
        text: qsTr("Remote desktop")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    Repeater {
        model: RemoteDesktop.RemoteStatus.devices.filter(device =>
            !device.isSelf
            && (
                device.canRemoteDesktop
                || device.canWake
                || (device.canSsh && device.sshAvailable)
            )
        )

        delegate: HostRow {
            required property var modelData
            device: modelData
        }
    }
}
