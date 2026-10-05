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

    // Up to four actions (switch, leave, wake, SSH) need room alongside a host
    // name. Keep the action strip visible rather than clipping its final icon.
    width: 372
    spacing: Tokens.spacing.small

    component ActionButton: StyledRect {
        id: btn

        required property string icon

        signal clicked

        implicitWidth: implicitHeight
        implicitHeight: btnIcon.implicitHeight + Tokens.padding.extraSmall

        radius: Tokens.rounding.full
        color: "transparent"
        opacity: enabled ? 1 : 0.35

        StateLayer {
            disabled: !btn.enabled
            onClicked: btn.clicked()
        }

        MaterialIcon {
            id: btnIcon

            anchors.centerIn: parent
            text: btn.icon
        }
    }

    component HostRow: RowLayout {
        id: hostRow

        required property var device

        readonly property bool online: !!device.online
        // The session, if there is one, is with the peer -- so only the peer's
        // row reports it. `viewing` is our client on their screen; `shared` is
        // their client on ours.
        readonly property bool isPeer: device.id === RemoteDesktop.RemoteStatus.peerId
        readonly property bool viewing: isPeer && RemoteDesktop.RemoteStatus.viewing
        readonly property bool shared: isPeer && RemoteDesktop.RemoteStatus.shared

        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.medium
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "computer"
        }

        ColumnLayout {
            Layout.fillWidth: true
            // Let long tailnet names elide; their implicit text width must not
            // force the action buttons past the popout's right edge.
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: hostRow.device.name
                elide: Text.ElideRight
            }

            StyledText {
                text: hostRow.device.isSelf ? qsTr("This device") : !hostRow.online ? qsTr("Offline") : hostRow.viewing ? qsTr("Online — connected") : hostRow.shared ? qsTr("Online — viewing this screen") : qsTr("Online")
                color: !hostRow.online ? Colours.palette.m3error : (hostRow.viewing || hostRow.shared) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        RowLayout {
            spacing: Tokens.spacing.small

            ActionButton {
                // Going to the session and leaving it are separate intentions,
                // so they are separate buttons rather than one control that
                // changes meaning underneath you. This is the going half: it
                // connects when nothing is up and simply takes you there when
                // something is.
                //
                // Every peer gets it now. It used to be the desktop's alone,
                // back when the stream only ran one way and the workspace it
                // lives on existed on one machine; both hosts serve and both
                // consume, so either can be the one being looked at.
                // Hidden rather than dimmed while the host is down: there is
                // nothing to connect to, and a row of dead controls under an
                // "Offline" label reads as the integration being broken.
                visible: hostRow.device.canRemoteDesktop && !hostRow.device.isSelf && hostRow.online
                icon: hostRow.viewing ? "desktop_windows" : "link"
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.id, "open"])
            }

            ActionButton {
                // The leaving half. It hands the screen back and leaves the
                // session standing, so coming back is a workspace switch rather
                // than a reconnect; pressing it again once you are already away
                // is what actually tears the session down.
                //
                // It is also the only control offered while the peer is the one
                // watching: there is no local client to step away from, so
                // kagami-remote forwards the teardown to the machine holding it.
                visible: hostRow.viewing || hostRow.shared
                icon: "link_off"
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.id, "leave"])
            }

            ActionButton {
                // Every remote device gets a Wake slot. It is enabled only when
                // we know its LAN MAC address; Tailscale deliberately does not
                // expose MACs, so guessing would send an invalid magic packet.
                visible: !hostRow.device.isSelf
                // Sending a magic packet to an awake host is harmless. Keeping the
                // control available makes the configured Wake-on-LAN capability
                // discoverable instead of making it appear to vanish with status.
                enabled: hostRow.device.canWake
                icon: "bolt"
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.id, "wake"])
            }

            ActionButton {
                // Same: an unreachable endpoint offers nothing, so it goes
                // away instead of sitting there greyed.
                visible: hostRow.device.canSsh && hostRow.device.sshAvailable
                icon: "terminal"
                onClicked: Quickshell.execDetached([RemoteDesktop.RemoteStatus.bin, hostRow.device.actionHost, "ssh"])
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.extraSmall
        text: qsTr("Remote")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    Repeater {
        model: RemoteDesktop.RemoteStatus.devices

        delegate: HostRow {
            required property var modelData

            device: modelData
        }
    }
}
