#!/usr/bin/env python3
"""Static safety checks for the automatic connectivity recovery loop."""
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
WATCHDOG = ROOT / "scripts/network-tunnel-watchdog"
SERVICE = ROOT / "systemd/user/remote-desktop-watchdog.service"
TIMER = ROOT / "systemd/user/remote-desktop-watchdog.timer"


class NetworkTunnelWatchdogTests(unittest.TestCase):
    def test_shell_is_valid(self):
        subprocess.run(["bash", "-n", str(WATCHDOG)], check=True)

    def test_recovery_is_bounded(self):
        text = WATCHDOG.read_text()
        self.assertIn("REMOTE_WATCHDOG_MIN_FAILURES", text)
        self.assertIn("REMOTE_WATCHDOG_COOLDOWN", text)
        self.assertIn("flock -n", text)
        self.assertNotIn("tailscale down", text)

    def test_service_is_sandboxed_and_timer_persistent(self):
        service = SERVICE.read_text()
        timer = TIMER.read_text()
        self.assertIn("NoNewPrivileges=yes", service)
        self.assertIn("ProtectSystem=strict", service)
        self.assertIn("StateDirectory=remote-desktop-watchdog", service)
        self.assertIn("Persistent=true", timer)


if __name__ == "__main__":
    unittest.main()
