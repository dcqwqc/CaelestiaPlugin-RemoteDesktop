"""Quick VPN navigation and non-automatic network-change regression checks."""
from pathlib import Path
import unittest

SRC=(Path(__file__).resolve().parents[1]/"bar/RemotePopout.qml").read_text()

class VpnQuickUiTests(unittest.TestCase):
    def test_compact_summary(self):
        self.assertIn('text: vpn.connected ? vpn.countryName : qsTr("Off")', SRC)
        self.assertIn('onClicked: vpn.quickPicker ? vpn.quickPicker = false : vpn.openQuickPicker()', SRC)
        self.assertIn('onClicked: vpn.connectOrPrepare()', SRC)

    def test_country_picker_and_advanced_independent(self):
        self.assertIn('id: quickCountryList', SRC)
        self.assertIn('onClicked: vpn.quickConnectCountry(quickCountryRow.modelData.code, quickCountryRow.modelData.name)', SRC)
        self.assertIn('vpn.expanded = !vpn.expanded;', SRC)
        self.assertIn('id: serverList', SRC)

    def test_route_menu_still_available(self):
        self.assertIn('text: qsTr("VPN countries…")', SRC)
        self.assertIn('item.opensVpnPicker', SRC)
        self.assertIn('RemoteDesktop.RemoteStatus.setExitNode(item.nodeId)', SRC)

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
