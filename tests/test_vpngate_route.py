import base64
import csv
import importlib.machinery
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
script = importlib.machinery.SourceFileLoader("vpngate_route", str(ROOT / "scripts/vpngate-route")).load_module()


def sample(ip="203.0.113.11", extra=""):
    return f"""client
dev tun
proto udp
remote {ip} 1194
auth-user-pass
remote-cert-tls server
{extra}
<ca>
-----BEGIN CERTIFICATE-----
Zm9v
-----END CERTIFICATE-----
</ca>
"""


class VpnGateTests(unittest.TestCase):
    def test_only_japan_relay_is_listed(self):
        keys = ["HostName", "IP", "CountryShort", "Score", "Speed", "Ping",
                "NumVpnSessions", "OpenVPN_ConfigData_Base64"]
        def row(ip, country, score):
            return ["relay", ip, country, str(score), "54000000", "38", "2",
                    base64.b64encode(sample(ip).encode()).decode()]
        f = io.StringIO()
        w = csv.writer(f)
        w.writerow(row("203.0.113.11", "JP", 120))
        w.writerow(row("203.0.113.12", "US", 999))
        w.writerow(row("203.0.113.13", "JP", 200))
        csv_data = "#" + ",".join(keys) + "\n" + f.getvalue()
        rows = script.filtered_rows(csv_data)
        self.assertEqual([x["ip"] for x in rows], ["203.0.113.13", "203.0.113.11"])
        self.assertEqual(rows[0]["mbps"], 54.0)

    def test_strip_remote_options_and_ignore_setenv(self):
        ovpn = sample(extra='setenv bypassscript security\nverb 11\npersist-tun')
        clean = script.checked_profile(base64.b64encode(ovpn.encode()).decode(), "203.0.113.11")
        self.assertIn("remote 203.0.113.11 1194", clean)
        self.assertIn("remote-cert-tls server", clean)
        self.assertNotIn("setenv", clean)
        self.assertIn("<ca>", clean)

    def test_reject_volunteer_shell_commands(self):
        data = sample(extra="script-security 2\nup /bin/sh")
        with self.assertRaises(script.RouteError):
            script.checked_profile(base64.b64encode(data.encode()).decode(), "203.0.113.11")

    def test_reject_volunteer_different_ip(self):
        data = sample(ip="203.0.113.22")
        with self.assertRaises(script.RouteError):
            script.checked_profile(base64.b64encode(data.encode()).decode(), "203.0.113.11")

    def test_accept_profile_without_optional_eku_directive(self):
        data = sample().replace("remote-cert-tls server", "")
        clean = script.checked_profile(base64.b64encode(data.encode()).decode(), "203.0.113.11")
        self.assertNotIn("remote-cert-tls", clean)
        self.assertIn("<ca>", clean)

    def test_status_does_not_change_network(self):
        with patch.object(script, "run", return_value=""):
            s = script.status()
        self.assertFalse(s["connected"])
        self.assertFalse(s["configured"])

    def test_direct_exit_is_safe_when_not_connected(self):
        with patch.object(script, "active", return_value=False), patch.object(
            script, "status", return_value={"connected": False}
        ):
            self.assertEqual(script.disconnect(), {"connected": False})


if __name__ == "__main__":
    unittest.main()
