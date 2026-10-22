from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
POP=(ROOT/"bar/RemotePopout.qml").read_text()
SETTINGS=(ROOT/"SettingsUi.qml").read_text()
CONNECT=(ROOT/"PluginConnectSettings.qml").read_text()
class UnifiedRouteTests(unittest.TestCase):
    def test_all_route_features_inside_one_dropdown(self):
        section=POP.split("id: routeDetails",1)[1].split("} // deviceContent",1)[0]
        for required in ['title: qsTr("Direct")','text: qsTr("Tailscale")','text: qsTr("VPN countries")','id: vpnPanel']:
            self.assertIn(required, section)
        self.assertEqual(POP.count("id: vpnPanel"), 1)
        self.assertNotIn("id: routeMenu", POP)
    def test_no_vpn_footer_or_gray_fills(self):
        self.assertNotIn("m3surfaceContainerHighest", POP.split("component VpnRoutePanel:",1)[1].split("Flickable {",1)[0])
        self.assertNotIn("m3surfaceContainerHighest", SETTINGS)
        self.assertNotIn("m3surfaceContainerLowest", CONNECT)
    def test_settings_preserves_controls_without_cards(self):
        self.assertIn('text: qsTr("Device appearance")', SETTINGS)
        self.assertIn("id: deviceRow", SETTINGS)
        self.assertNotIn("ConnectedRect {", SETTINGS)
        self.assertIn("onToggled: root.writeOverride", SETTINGS)
        self.assertIn("onClicked: root.perform(", CONNECT)
    def test_no_network_changes_on_expand(self):
        fn=POP.split("onRouteExpandedChanged: {",1)[1].split("component RouteChoice:",1)[0]
        self.assertIn('vpnPanel.browse("countries", "")', fn)
        self.assertNotIn('RemoteDesktop.RemoteStatus.setExitNode(',fn)
        self.assertNotIn('vpnPanel.action("connect")',fn)
