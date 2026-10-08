import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import dcqwqc.devices.services as RemoteDesktop

Item {
    id: root

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight
    readonly property string health: RemoteDesktop.RemoteStatus.overallHealth
    readonly property string healthError: RemoteDesktop.RemoteStatus.overallError
    readonly property bool hovered: statusHover.hovered

    HoverHandler { id: statusHover }

    Tooltip {
        target: root
        delay: 250
        text: root.health === "reachable" ? qsTr("Devices")
            : qsTr("Devices%1%2").arg(String.fromCharCode(10)).arg(root.healthError)
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "devices"
        color: Colours.palette.m3secondary
        fontStyle: Tokens.font.icon.small
    }

    // One compact status light for the remote path.
    Rectangle {
        visible: true
        width: 6
        height: 6
        radius: 3
        anchors.right: icon.right
        anchors.bottom: icon.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
        color: root.health === "reachable" ? "#43a047"
            : root.health === "offline" ? Colours.palette.m3error
            : "#d99a00"
        border.width: 1
        border.color: Colours.palette.m3surface
    }
}
