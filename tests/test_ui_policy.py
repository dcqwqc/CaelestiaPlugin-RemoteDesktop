"""Guard against reverting the current-device-first, collapsed-peers UX."""
import shutil
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POP = (ROOT / 'bar/RemotePopout.qml').read_text()
STATUS = (ROOT / 'services/RemoteStatus.qml').read_text()


class DevicePanelPolicyTests(unittest.TestCase):
    def test_current_device_always_listed_independent_of_user_hide_setting(self):
        self.assertIn('return [local].concat(peers)', POP)
        self.assertIn('.filter(device => !device.isSelf && root.deviceEnabled(device))', POP)

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

    def test_qml_syntax(self):
        exe = shutil.which('qmlformat') or '/usr/lib/qt6/bin/qmlformat'
        for rel in ('bar/RemotePopout.qml', 'bar/RemoteEntry.qml', 'services/RemoteStatus.qml'):
            with self.subTest(file=rel):
                run = subprocess.run([exe, str(ROOT/rel)], text=True, capture_output=True)
                self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == '__main__':
    unittest.main()
