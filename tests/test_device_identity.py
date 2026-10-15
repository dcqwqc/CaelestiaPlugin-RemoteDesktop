"""Exercise the exact Qt JavaScript device-identity module using Node."""
import shutil
import subprocess
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeviceIdentityTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "Node.js is needed for JS execution")
    def test_unique_nodes_and_health_transitions(self):
        result = subprocess.run(
            ["node", str(ROOT / "tests/test_device_identity.js")],
            cwd=ROOT, capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ingestion_uses_single_shared_identity_helper(self):
        service = (ROOT / "services/RemoteStatus.qml").read_text()
        self.assertIn('import "DeviceIdentity.js" as DeviceIdentity', service)
        self.assertIn('DeviceIdentity.distinctNodes(data.Self, Object.values(data.Peer ?? {}))', service)
        self.assertIn('name: DeviceIdentity.displayName(node)', service)
        self.assertIn('root.sshAvailability = DeviceIdentity.retainOnlineAvailability(', service)
        self.assertIn('return DeviceIdentity.deviceHealth(', service)
        self.assertIn('id: hostId,', service, "retain historic ID/config/remote-desktop command contract")
        self.assertIn('canWake: !isSelf && !!root.configuredHosts[hostId]?.mac', service)
        self.assertIn('canRemoteDesktop: !!root.configuredHosts[hostId]', service)


if __name__ == "__main__":
    unittest.main()
