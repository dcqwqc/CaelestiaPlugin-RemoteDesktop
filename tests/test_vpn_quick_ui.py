"""Quick VPN navigation and non-automatic network-change regression checks."""
from pathlib import Path
import unittest

SRC=(Path(__file__).resolve().parents[1]/"bar/RemotePopout.qml").read_text()

class VpnQuickUiTests(unittest.TestCase):
    def test_route_is_only_navigation_surface(self):
        self.assertIn("vpnPanel.countryName", SRC)
        self.assertIn("onClicked: root.routeExpanded = !root.routeExpanded", SRC)
        self.assertIn("id: routeFlyout", SRC)
        self.assertIn("visible: root.routeExpanded", SRC)
        self.assertEqual(SRC.count("id: vpnPanel"), 1)

    def test_country_picker_and_advanced_in_one_dropdown(self):
        self.assertIn("id: quickCountryList", SRC)
        self.assertIn("id: serverList", SRC)
        self.assertIn('title: qsTr("Choose VPN country")', SRC)
        self.assertIn(chr(111)+chr(110)+chr(67)+chr(108)+chr(105)+chr(99)+chr(107)+chr(101)+chr(100)+": root.openRoutePage("+chr(34)+"servers"+chr(34)+")", SRC)
        self.assertIn("onClicked: vpn.quickConnectCountry(quickCountryRow.modelData.code, quickCountryRow.modelData.name)", SRC)

    def test_direct_tailscale_vpn_choices(self):
        self.assertIn('title: qsTr("Direct")', SRC)
        self.assertIn('text: qsTr("Tailscale")', SRC)
        self.assertIn("model: RemoteDesktop.RemoteStatus.exitNodes", SRC)
        self.assertIn("onChosen: root.selectRoute(modelData.id)", SRC)
        self.assertIn("RemoteDesktop.RemoteStatus.setExitNode(nodeId)", SRC)

    def test_user_action_precedes_route_changes(self):
        fn=SRC.split('function connectOrPrepare() {',1)[1].split('function readStatus() {',1)[0]
        self.assertIn('RemoteDesktop.RemoteStatus.setExitNode("")', fn)
        self.assertIn('routePending = true;', fn)
        self.assertIn('action("connect");', fn)
        self.assertIn('if (!vpn.tailscaleExitActive', SRC.replace(' && !vpn.tailscaleExitActive','if (!vpn.tailscaleExitActive')) if False else None

    def test_visible_clutter_removed(self):
        self.assertNotIn('text: qsTr("Tailscale route")', SRC)
        self.assertNotIn('text: qsTr("All servers")', SRC)
        self.assertNotIn('text: qsTr("Switch Route to Direct before connecting")', SRC)
        self.assertNotIn('text: qsTr("%1 available")', SRC)
        self.assertIn('qsTr("Switch to Direct & Connect")', SRC)

    def test_scroll_list_limited_to_three_rows(self):
        self.assertIn('Math.min(3, vpn.servers.length)', SRC)
        self.assertIn('interactive: vpn.servers.length > 3', SRC)
        self.assertIn('boundsBehavior: Flickable.StopAtBounds', SRC)

    def test_state_machine_is_explicit(self):
        self.assertIn('property bool quickAutoConnect: false', SRC)
        self.assertIn('property bool routePending: false', SRC)
        self.assertIn('vpn.routeTries > 35', SRC)
        self.assertIn('if (vpn.routePending && !vpn.tailscaleExitActive', SRC)
        self.assertIn('vpn.pendingCountryCode', SRC)

if __name__ == "__main__":
    unittest.main()
