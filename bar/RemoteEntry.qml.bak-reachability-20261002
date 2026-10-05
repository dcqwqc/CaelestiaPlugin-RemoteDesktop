import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import dcqwqc.remotedesktop.services as RemoteDesktop

Item {
    id: root

    implicitWidth: icon.implicitHeight + Tokens.padding.small
    implicitHeight: icon.implicitHeight

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "cast_connected"
        color: Colours.palette.m3secondary
        fontStyle: Tokens.font.icon.small
    }

    // Small at-a-glance dot: green while actively streaming, muted red when the
    // peer is unreachable over Tailscale, otherwise invisible (idle).
    //
    // It used to watch one machine by name, which reported that host's health
    // to itself -- always online, so the offline half of the indicator could
    // only ever fire on the laptop. It follows whichever host is the far end.
    Rectangle {
        readonly property bool online: !RemoteDesktop.RemoteStatus.peerId || !!RemoteDesktop.RemoteStatus.hostOnline[RemoteDesktop.RemoteStatus.peerId]
        readonly property bool streaming: RemoteDesktop.RemoteStatus.streaming

        visible: streaming || !online
        width: 6
        height: 6
        radius: 3
        anchors.right: icon.right
        anchors.bottom: icon.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
        color: streaming ? Colours.palette.m3primary : Colours.palette.m3error
        border.width: 1
        border.color: Colours.palette.m3surface
    }
}
