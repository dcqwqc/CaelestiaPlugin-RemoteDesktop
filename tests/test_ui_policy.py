"""Guard against reverting the current-device-first, collapsed-peers UX."""
import shutil
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POP = (ROOT / 'bar/RemotePopout.qml').read_text()
STATUS = (ROOT / 'services/RemoteStatus.qml').read_text()
BAR = (ROOT / 'bar/RemoteEntry.qml').read_text()
SETTINGS_UI = (ROOT / 'SettingsUi.qml').read_text()


class DevicePanelPolicyTests(unittest.TestCase):
    def test_current_device_always_listed_independent_of_user_hide_setting(self):
        self.assertIn('return [local].concat(peers)', POP)
        self.assertIn('.filter(device => !device.isSelf && root.deviceEnabled(device))', POP)

    def test_hide_generic_loopback_peer_default(self):
        self.assertIn('String(device.name ?? "").trim().toLowerCase() === "localhost"', POP)
        self.assertIn('return [local].concat(peers)', POP)
        self.assertIn('cfg.enabled === undefined ? root.defaultDeviceEnabled(device) : !!cfg.enabled', POP)

    def test_current_device_has_no_expand_control(self):
        self.assertIn('readonly property bool expanded: isSelf || root.isDeviceExpanded(device.id)', POP)
        self.assertIn('visible: !hostRow.isSelf', POP)

    def test_non_green_local_diagnostic_is_automatically_visible(self):
        self.assertIn('visible: hostRow.health !== "reachable" && hostRow.expanded', POP)
        self.assertIn('RemoteDesktop.RemoteStatus.overallError', POP)
        self.assertIn('RemoteDesktop.RemoteStatus.overallHealth', POP)

    def test_expansion_persists_across_refresh(self):
        self.assertIn('property var expandedDevices: ({})', POP)
        self.assertIn('root.isDeviceExpanded(device.id)', POP)
        self.assertIn('root.toggleDeviceExpanded(hostRow.device.id)', POP)

    def test_long_content_scrolls_inside_screen_bound(self):
        self.assertIn('contentHeight: deviceContent.implicitHeight', POP)
        self.assertIn('implicitHeight: Math.min(deviceContent.implicitHeight, maxPanelHeight)', POP)
        self.assertIn('clip: true', POP)

    def test_aggregate_reasons_have_valid_newline_separator(self):
        self.assertIn('return errors.join(String.fromCharCode(10));', STATUS)

    def test_action_buttons_always_in_compact_row(self):
        row = POP.split('component HostRow: ColumnLayout {', 1)[1]
        main, details = row.split('// Remote peers can show their diagnosis', 1)
        # They must occur before the expandable diagnostics instead of inside
        # an expanded-only RowLayout, as they did in the previous revision.
        controls = main.split('// Connect / Wake / Terminal stay on the main row', 1)[1]
        controls = controls.split("// Remote peers can show their diagnosis", 1)[0]
        for action in ('Mirror phone', 'Open remote desktop', 'Disconnect', 'Wake', 'Open terminal'):
            with self.subTest(action=action):
                self.assertIn(action, controls)
        self.assertNotIn('visible: !hostRow.isSelf && hostRow.expanded', controls)

    def test_chevron_is_small_and_immediately_after_name(self):
        self.assertIn('anchors.left: deviceNameText.right', POP)
        self.assertIn('fontStyle: Tokens.font.icon.size(deviceNameText.font.pointSize).build()', POP)
        self.assertIn('onClicked: root.toggleDeviceExpanded(hostRow.device.id)', POP)
        self.assertIn('visible: !hostRow.isSelf', POP)

    def test_status_has_coloured_dot_but_no_status_word_labels(self):
        self.assertNotIn('readonly property string statusLabel:', POP)
        self.assertNotIn('qsTr("Healthy")', POP)
        self.assertNotIn('qsTr("Degraded")', POP)
        self.assertNotIn('qsTr("Offline")', POP)
        self.assertNotIn('qsTr("Checking")', POP)
        self.assertNotIn('Devices status: %1', BAR)
        self.assertIn('"#43a047"', POP)
        self.assertIn('"#d99a00"', POP)
        self.assertIn('Colours.palette.m3error', POP)

    def test_refresh_is_diagnostic_only_and_auto_polling_remains(self):
        self.assertIn('onClicked: RemoteDesktop.RemoteStatus.refreshNow()', POP)
        self.assertNotIn('onClicked: RemoteDesktop.RemoteStatus.repairConnectivity()', POP)
        self.assertIn('function refreshNow(): void', STATUS)
        self.assertIn('root.diagnoseConnectivity();', STATUS)
        self.assertIn('if (!tunnelStatusProc.running)', STATUS)
        self.assertIn('interval: 5000', STATUS)
        self.assertIn('interval: 10000', STATUS)
        # Never tear down the only remote-access path by clicking refresh.
        self.assertNotIn('"pkexec"', STATUS)
        self.assertNotIn('repairUserProc.running = true', STATUS)
        self.assertNotIn('systemctl", "restart"', STATUS)

    def test_no_oversized_device_tooltips_but_inline_errors_remain(self):
        self.assertNotIn('Tooltip {', POP)
        self.assertNotIn('Tooltip {', BAR)
        self.assertIn('visible: hostRow.health !== "reachable" && hostRow.expanded', POP)
        self.assertIn('color: Colours.palette.m3error', POP)
        self.assertIn('RemoteDesktop.RemoteStatus.overallError', BAR)

    def test_settings_agree_with_loopback_visibility(self):
        self.assertIn('String(device.name ?? "").trim().toLowerCase() === "localhost"', SETTINGS_UI)
        self.assertIn('cfg.enabled === undefined ? root.defaultEnabled(device) : !!cfg.enabled', SETTINGS_UI)

    def test_qml_syntax(self):
        exe = shutil.which('qmlformat') or '/usr/lib/qt6/bin/qmlformat'
        for rel in ('bar/RemotePopout.qml', 'bar/RemoteEntry.qml', 'services/RemoteStatus.qml', 'SettingsUi.qml'):
            with self.subTest(file=rel):
                run = subprocess.run([exe, str(ROOT/rel)], text=True, capture_output=True)
                self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == '__main__':
    unittest.main()
