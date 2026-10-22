from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
POP=(ROOT/"bar/RemotePopout.qml").read_text()
SETTINGS=(ROOT/"SettingsUi.qml").read_text()
CONNECT=(ROOT/"PluginConnectSettings.qml").read_text()
class UnifiedRouteTests(unittest.TestCase):
    def test_all_route_features_in_compact_overlay(self):
        section=POP.split("id: routeFlyout",1)[1]
        for required in ["title: qsTr(\"Direct\")","text: qsTr(\"Tailscale\")",
                         "title: qsTr(\"Choose VPN country\")","id: vpnPanel"]:
            self.assertIn(required,section)
        self.assertEqual(POP.count("id: vpnPanel"),1)
        self.assertNotIn("id: routeMenu",POP)
        self.assertIn("height: Math.min(356, root.height - 8)",POP)
        self.assertIn("Layout.fillHeight: true",section)
        self.assertNotIn("id: routeDetails",POP)
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
        fn=POP.split("onRouteExpandedChanged: {",1)[1].split("implicitWidth: 304",1)[0]
        self.assertIn("vpnPanel.readStatus()",fn)
        self.assertNotIn("RemoteDesktop.RemoteStatus.setExitNode(",fn)
        self.assertNotIn("vpnPanel.action(\"connect\")",fn)
    def test_page_separation(self):
        self.assertIn("property string routePage: \"routes\"",POP)
        self.assertIn("page === \"countries\"",POP)
        self.assertIn("page === \"servers\"",POP)
        self.assertIn("id: quickCountryList",POP)
        self.assertIn("id: serverList",POP)
        self.assertIn("placeholderText: qsTr(\"Search countries\")",POP)
    def test_real_connection_state_not_preference(self):
        self.assertIn("readonly property bool vpnVerified:",POP)
        self.assertIn("vpnPanel.verifiedCountryCode === vpnPanel.countryCode",POP)
        self.assertIn("vpn.connectAttempts < 3",POP)
    def test_background_does_not_push_device_rows(self):
        self.assertIn("z: 91",POP)
        self.assertIn("id: routeFlyout",POP)
        self.assertIn("id: deviceScroller",POP)
        self.assertIn("height: Math.min(356, root.height - 8)",POP)
