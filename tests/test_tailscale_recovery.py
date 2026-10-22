"""One-click recovery must be explicit, bounded, observable and non-destructive."""
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/connectivity-repair"
STATUS = (ROOT / "services/RemoteStatus.qml").read_text()
PANEL = (ROOT / "bar/RemotePopout.qml").read_text()


class TailscaleRecoveryTests(unittest.TestCase):
    def invoke(self, mode="repair-tailscale", *, auth=True, backend="Running", ping=True, home=True, api="ok"):
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            for name, content in {
                "pkexec": "#!/bin/sh\necho called >>\"$REPAIR_MARKER\"\n" + ("exit 0\n" if auth else "echo denied >&2\nexit 126\n"),
                "tailscale": "#!/bin/sh\nif [ \"$1\" = status ]; then echo '{\"BackendState\":\"'\"$MOCK_BACKEND\"'\"}'; exit 0; fi\nif [ \"$1\" = ping ]; then [ \"$MOCK_PING\" = yes ]; exit $?; fi\nexit 1\n",
                "curl": '#!/bin/sh\n[ "$MOCK_HOME" = yes ] || exit 1\ncase "$*" in *api/v1/health*) printf \'{"service":"home-api","status":"%s"}\\n\' "$MOCK_API" ;; esac\n',
                "nmcli": "#!/bin/sh\necho 'GENERAL.CONNECTION:test network'\n"
            }.items():
                path = d / name
                path.write_text(content)
                path.chmod(0o755)
            marker = d / "mutations"
            env = {**os.environ, "PATH": f"{d}:{Path(shutil.which('jq')).parent}:{os.environ.get('PATH', '/usr/bin:/bin')}", "REPAIR_MARKER": str(marker),
                   "MOCK_BACKEND": backend, "MOCK_PING": "yes" if ping else "no",
                   "MOCK_HOME": "yes" if home else "no", "MOCK_API": api}
            proc = subprocess.run([str(SCRIPT), mode], text=True, capture_output=True, env=env, timeout=10)
            return proc, json.loads(proc.stdout), marker.exists()

    def test_success_restarts_once_and_requires_peer_and_home(self):
        proc, result, called = self.invoke()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(result["ok"])
        self.assertTrue(called)

    def test_denied_polkit_reports_failure(self):
        proc, result, called = self.invoke(auth=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(result["ok"])
        self.assertTrue(called)
        self.assertIn("not authorized", result["message"])

    def test_no_login_does_not_claim_recovered(self):
        proc, result, _ = self.invoke(backend="NeedsLogin")
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(result["ok"])
        self.assertIn("NeedsLogin", result["message"])

    def test_running_but_peer_missing_not_green(self):
        proc, result, _ = self.invoke(ping=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(result["ok"])
        self.assertIn("Philipedia", result["message"])

    def test_peer_ok_but_home_missing_not_green(self):
        proc, result, _ = self.invoke(home=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(result["ok"])
        self.assertIn("Home Dashboard", result["message"])

    def test_degraded_home_api_does_not_claim_success(self):
        proc, result, _ = self.invoke(api="degraded")
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(result["ok"])
        self.assertIn("Home API", result["message"])

    def test_diagnose_does_not_restart_anything(self):
        proc, result, called = self.invoke(mode="diagnose")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(result["state"], "online")
        self.assertFalse(called)

    def test_refresh_is_diagnostic_only_and_recovery_explicit(self):
        self.assertIn('onClicked: RemoteDesktop.RemoteStatus.refreshNow()', PANEL)
        self.assertIn('onClicked: RemoteDesktop.RemoteStatus.reconnectTailscale()', PANEL)
        self.assertIn('function reconnectTailscale(): void', STATUS)
        self.assertIn('command: [root.connectivityBin, "repair-tailscale"]', STATUS)
        self.assertNotIn('pkexec', STATUS)
        self.assertIn('device.serverHint', STATUS)
        self.assertIn('device.tunnelCandidate', STATUS)
        self.assertIn('node.ExitNodeOption', STATUS)


if __name__ == '__main__':
    unittest.main()
