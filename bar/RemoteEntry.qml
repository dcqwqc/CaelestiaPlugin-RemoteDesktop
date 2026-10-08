import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import dcqwqc.devices.services as RemoteDesktop

Item {
    id: root

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "devices"
        color: Colours.palette.m3secondary
        fontStyle: Tokens.font.icon.small
    }

    // One compact status light for the remote path.
    Rectangle {
        readonly property var host: RemoteDesktop.RemoteStatus.devices.find(device => device.isSelf)
        readonly property string localHealth: !host
            ? "unknown"
            : !host.online
                ? "offline"
                : !host.sshKnown
                    ? "unknown"
                    : host.sshAvailable
                        ? "reachable"
                        : "degraded"
        readonly property string tunnelHealth: RemoteDesktop.RemoteStatus.tunnelState
        readonly property string health: localHealth === "offline" || tunnelHealth === "offline"
            ? "offline"
            : localHealth === "degraded" || tunnelHealth === "degraded"
                ? "degraded"
                : localHealth === "unknown" || tunnelHealth === "unknown"
                    ? "unknown"
                    : "reachable"

        visible: true
        width: 6
        height: 6
        radius: 3
        anchors.right: icon.right
        anchors.bottom: icon.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
        color: health === "reachable"
            ? "#43a047"
            : health === "degraded"
                ? "#d99a00"
                : health === "offline"
                    ? Colours.palette.m3error
                    : Colours.palette.m3outline
        border.width: 1
        border.color: Colours.palette.m3surface
    }
}
