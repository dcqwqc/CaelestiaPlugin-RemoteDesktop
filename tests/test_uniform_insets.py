import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QML = (ROOT / "bar/RemotePopout.qml").read_text()


class DevicesPaddingTests(unittest.TestCase):
    def test_shared_content_inset(self):
        self.assertIn("readonly property real horizontalInset: Tokens.padding.small", QML)
        self.assertGreaterEqual(QML.count("Layout.leftMargin: root.horizontalInset"), 6)
        self.assertEqual(QML.count("Layout.leftMargin: root.horizontalInset"),
                         QML.count("Layout.rightMargin: root.horizontalInset"))

    def test_vpn_subrows_no_second_inset(self):
        vp = QML.split("component VpnRoutePanel: ColumnLayout {", 1)[1]
        inside = vp.split("    Flickable {\n        anchors.fill: parent", 1)[0]
        self.assertIn("No second inset here", inside)
        self.assertNotIn("Layout.leftMargin: 7", inside)
        self.assertNotIn("Layout.rightMargin: 7", inside)

    def test_no_unnecessary_speed_caption(self):
        self.assertNotIn("fastest first", QML)
        self.assertNotIn('qsTr("%1 available")', QML)
        self.assertIn("id: serverList", QML)
        self.assertIn("Math.min(3, vpn.servers.length)", QML)

    def test_device_actions_and_routes_remain(self):
        self.assertIn("id: deviceContent", QML)
        self.assertIn("vpnPanel.connected ? vpnPanel.countryName", QML)
        self.assertIn("RemoteDesktop.RemoteStatus.setExitNode(nodeId)", QML)
        self.assertIn("id: vpnPanel", QML)


if __name__ == "__main__":
    unittest.main()
