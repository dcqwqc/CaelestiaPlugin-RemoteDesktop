import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
QML=(ROOT/"bar/RemotePopout.qml").read_text()
PY=(ROOT/"scripts/vpngate-route").read_text()

class VpnQualityUI(unittest.TestCase):
    def test_default_sort_and_four_modes(self):
        self.assertIn('property string sortMode: "recommended"', QML)
        for mode in ("recommended","fastest","latency","line"):
            self.assertIn('id: "'+mode+'"',QML)
        self.assertIn('vpn.browse("sort", modeRow.modelData.id)',QML)
    def test_small_scroll_list_preserved(self):
        self.assertIn('id: serverList',QML)
        self.assertIn('Math.min(3, vpn.servers.length)',QML)
        self.assertIn('visible: vpn.sortExpanded',QML)
    def test_data_labels_not_misrepresented(self):
        self.assertIn('Mb/s · line',QML)
        self.assertIn('Mb/s · tested',QML)
        self.assertIn('No RTT test',QML)
        self.assertIn('relayRow.modelData.latencyMs',QML)
        self.assertNotIn('3.7 Gb/s real',QML)
    def test_explicit_opt_in_probes_and_bandwidth(self):
        self.assertIn('vpn.browse("probe", vpn.countryCode)',QML)
        self.assertIn('vpn.action("benchmark")',QML)
        self.assertIn('Measure VPN download speed (2 MB)',QML)
        self.assertIn('--max-filesize", "2050000"',PY)
        self.assertIn('def record_connection',PY)
    def test_keeps_tailscale_and_route(self):
        self.assertIn('RemoteDesktop.RemoteStatus.setExitNode(item.nodeId)',QML)
        self.assertIn('root.vpnConnected ? root.vpnExitCountry',QML)
        self.assertIn('tunnel',QML.lower())
    def test_no_unnecessary_footer_messages(self):
        self.assertNotIn('Using saved server list',QML)
        self.assertNotIn('fastest first',QML)

if __name__=="__main__":
    unittest.main()
