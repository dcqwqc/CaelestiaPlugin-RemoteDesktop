"""Devices self-healing must be bounded and diagnostic text must be copyable."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/connectivity-repair"
STATUS = (ROOT / "services/RemoteStatus.qml").read_text()
PANEL = (ROOT / "bar/RemotePopout.qml").read_text()


class SelfHealingTests(unittest.TestCase):
    def call_safe(self, enabled=True, active=False, start_ok=True):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "systemctl").write_text("""#!/bin/sh
case "$*" in
  *is-enabled*) [ "$TEST_ENABLED" = 1 ]; exit $? ;;
  *is-active*) [ "$TEST_ACTIVE" = 1 ] || [ -e "$TEST_MARKER" ]; exit $? ;;
  *start*) [ "$TEST_START_OK" = 1 ] || exit 1; touch "$TEST_MARKER"; exit 0 ;;
esac
exit 4
""")
            (path / "systemctl").chmod(0o755)
            marker = path / "started"
            env = {**os.environ, "PATH": str(path) + ":" + os.environ.get("PATH", "/usr/bin:/bin"),
                   "TEST_ENABLED": "1" if enabled else "0",
                   "TEST_ACTIVE": "1" if active else "0",
                   "TEST_START_OK": "1" if start_ok else "0",
                   "TEST_MARKER": str(marker)}
            result = subprocess.run(["bash", str(SCRIPT), "repair-safe"],
                                    env=env, capture_output=True, text=True, timeout=10)
            return result.returncode, json.loads(result.stdout), marker.exists()

    def test_running_services_never_restart(self):
        rc, outcome, touched = self.call_safe(enabled=True, active=True)
        self.assertEqual(rc, 0)
        self.assertTrue(outcome["ok"])
        self.assertFalse(touched)

    def test_disabled_services_stay_off(self):
        rc, outcome, touched = self.call_safe(enabled=False)
        self.assertEqual(rc, 0)
        self.assertFalse(touched)

    def test_enabled_stopped_service_recovers(self):
        rc, outcome, touched = self.call_safe()
        self.assertEqual(rc, 0)
        self.assertTrue(outcome["ok"])
        self.assertTrue(touched)

    def test_failure_not_misreported_as_success(self):
        rc, outcome, touched = self.call_safe(start_ok=False)
        self.assertNotEqual(rc, 0)
        self.assertFalse(outcome["ok"])
        self.assertFalse(touched)

    def test_automatic_repair_cannot_restart_tailscale(self):
        self.assertIn("function safeSelfHeal(explicitAction)", STATUS)
        self.assertIn("interval: 15000", STATUS)
        self.assertIn("failedHealthChecks < 3", STATUS)
        self.assertIn("lastSelfHealAt < 300000", STATUS)
        self.assertIn('command: [root.connectivityBin, "repair-safe"]', STATUS)
        self.assertIn("reconnectTailscale(); // Only explicit click", STATUS)
        self.assertIn('onClicked: RemoteDesktop.RemoteStatus.refreshNow()', PANEL)
        self.assertIn("onClicked: RemoteDesktop.RemoteStatus.repairConnection()", PANEL)
        self.assertNotIn("pkexec", STATUS)
        auto_mode = SCRIPT.read_text().split("if [[ $mode == repair-safe ]]; then")[1].split("if [[ $mode == repair-tailscale ]]; then")[0]
        self.assertNotIn("pkexec", auto_mode)
        self.assertNotIn("systemctl --user restart", auto_mode)

    def test_red_errors_have_click_to_copy_behavior(self):
        self.assertIn("component CopyableError: StyledText", PANEL)
        self.assertIn("Quickshell.clipboardText = String(errorLabel.text ||", PANEL)
        self.assertGreaterEqual(PANEL.count("CopyableError {"), 4)


if __name__ == "__main__":
    unittest.main()
