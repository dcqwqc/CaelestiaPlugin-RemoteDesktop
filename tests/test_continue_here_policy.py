"""Policy guards for the Continue Here section: explicit action only, no shell, graceful offline."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QML = (ROOT / 'bar/ContinueHere.qml').read_text()
POP = (ROOT / 'bar/RemotePopout.qml').read_text()


class ContinueHerePolicyTests(unittest.TestCase):
    def test_section_is_mounted_in_the_devices_popout(self):
        self.assertIn('ContinueHere {', POP)

    def test_nothing_runs_until_opened_and_nothing_launches_until_clicked(self):
        self.assertNotIn('running: true', QML)                       # no startup probe
        self.assertEqual(QML.count('--execute'), 1)                  # single launch path
        self.assertIn('onClicked: root.cont()', QML)
        self.assertIn('if (root.expanded)\n                    root.refresh()', QML)

    def test_no_shell_interpolation(self):
        self.assertNotRegex(QML, r'"(sh|bash|fish)"')
        self.assertNotIn('-c"', QML)
        self.assertIn('const args = [cli, "handoff"', QML)

    def test_graceful_offline_and_unsupported_states(self):
        for text in ('is offline', 'too old for Space handoff', 'Continuity tool unavailable', 'No Spaces found'):
            self.assertIn(text, QML)
        self.assertIn('canContinue', QML)
        self.assertIn('spaces.length > 0', QML)

    def test_only_existing_spaces_are_offered(self):
        self.assertIn('root.spaces = peer && peer.spaces ? peer.spaces : [];', QML)
        self.assertNotIn('"--create', QML)

    def test_launch_function_called_only_from_click_handler(self):
        calls = [m.start() for m in re.finditer(r'root\.cont\(\)', QML)]
        self.assertEqual(len(calls), 1)
        line = QML[:calls[0]].rsplit('\n', 1)[-1]
        self.assertIn('onClicked:', line)
        self.assertIn('if (!canContinue)', QML)

if __name__ == '__main__':
    unittest.main()
