#!/usr/bin/env python3
"""Non-green Devices states must retain a human-readable, observed reason."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / 'scripts/device-ssh-probe'
TUNNEL = ROOT / 'scripts/openai-tunnel-status'

loader = importlib.machinery.SourceFileLoader('device_ssh_probe', str(PROBE))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class DeviceDiagnosticsTests(unittest.TestCase):
    def test_ssh_refused_has_specific_failure(self):
        with mock.patch.object(module.socket, 'create_connection', side_effect=ConnectionRefusedError(111, 'Connection refused')):
            host, result = module.probe('desktop.example')
        self.assertEqual(host, 'desktop.example')
        self.assertFalse(result['reachable'])
        self.assertIn('Connection refused', result['reason'])
        self.assertIn('desktop.example', result['reason'])

    def test_ssh_timeout_has_specific_failure(self):
        with mock.patch.object(module.socket, 'create_connection', side_effect=TimeoutError('timed out')):
            _, result = module.probe('computer.example')
        self.assertFalse(result['reachable'])
        self.assertIn('timed out', result['reason'])

    def test_ssh_success_has_no_error(self):
        conn = mock.MagicMock()
        with mock.patch.object(module.socket, 'create_connection', return_value=conn):
            _, result = module.probe('server.example')
        self.assertTrue(result['reachable'])
        self.assertEqual(result['reason'], '')

    def test_missing_tunnel_host_explains_unknown(self):
        result = json.loads(subprocess.check_output([str(TUNNEL)], text=True))
        self.assertEqual(result['state'], 'unknown')
        self.assertIn('No server-class', result['reason'])

    def run_mock_tunnel(self, mode):
        with tempfile.TemporaryDirectory() as tmp:
            ssh = Path(tmp) / 'ssh'
            ssh.write_text('''#!/bin/sh
case "$MOCK_SSH_MODE" in
online) printf 'online\t\n' ;;
degraded) printf 'degraded\tLast successful MCP command poll was 390s ago (watchdog limit: 150s)\n' ;;
offline) printf 'offline\tOpenAI tunnel service is inactive\n' ;;
ssherror) echo 'Connection timed out' >&2; exit 255 ;;
esac
''')
            ssh.chmod(0o755)
            env = dict(os.environ, PATH=tmp + ':' + os.environ['PATH'], MOCK_SSH_MODE=mode)
            return json.loads(subprocess.check_output([str(TUNNEL), 'sample.example'], text=True, env=env))

    def test_tunnel_states_explain_non_green(self):
        for mode in ('degraded', 'offline', 'ssherror'):
            with self.subTest(mode=mode):
                result = self.run_mock_tunnel(mode)
                self.assertTrue(result['reason'])
                self.assertNotEqual(result['state'], 'online')
        self.assertEqual(self.run_mock_tunnel('online')['reason'], '')


if __name__ == '__main__':
    unittest.main()
