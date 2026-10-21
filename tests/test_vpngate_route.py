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
    def test_all_countries_are_listed_and_filtered_on_demand(self):
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
        self.assertEqual([x["ip"] for x in rows],
                         ["203.0.113.12", "203.0.113.13", "203.0.113.11"])
        self.assertEqual(script.relay_options(rows, "US")[0]["ip"], "203.0.113.12")
        self.assertEqual([r["ip"] for r in script.relay_options(rows, "JP")],
                         ["203.0.113.13", "203.0.113.11"])
        self.assertEqual([(c["code"], c["count"]) for c in script.country_options(rows)],
                         [("JP", 2), ("US", 1)])
        self.assertEqual(rows[0]["mbps"], 54.0)

    def test_import_response_regex_is_valid(self):
        import re
        import inspect
        body = inspect.getsource(script.connect)
        self.assertIn('match = re.search', body)
        self.assertTrue(re.search(r"Connection ['‘](.+?)['’] \(",
                                  "Connection 'selected' (abcd)"))

    def test_country_labels_are_readable_even_from_old_cache(self):
        self.assertEqual(script.display_country("KR", "Korea Republic of"), "South Korea")
        self.assertEqual(script.display_country("HR", "Croatia (LOCAL Name Hrvatska)"), "Croatia")
        self.assertEqual(script.display_country("VN", "Viet Nam"), "Vietnam")
        rows = [{"country":"RU","countryName":"Russian Federation"}]
        self.assertEqual(script.country_options(rows)[0]["name"], "Russia")

    def test_servers_are_sorted_by_advertised_bandwidth_without_truncation(self):
        servers = [
            {"country": "JP", "id": f"id{n}", "ip": f"192.0.2.{n + 1}",
             "score": 9999 if n == 0 else 1,
             "mbps": float(n), "ping": 20, "sessions": 0}
            for n in range(25)
        ]
        visible = script.relay_options(servers, "JP", sort="line", history={})
        self.assertEqual(len(visible), 25)
        self.assertEqual([s["mbps"] for s in visible],
                         sorted([s["mbps"] for s in servers], reverse=True))
        self.assertEqual(visible[0]["id"], "id24")
        self.assertEqual(visible[-1]["id"], "id0")

    def test_country_code_is_validated(self):
        with self.assertRaises(script.RouteError):
            script.relay_options([], "../JP")
        self.assertEqual(script.relay_options([], "DE"), [])

    def test_saved_cache_keeps_all_countries_without_fetch(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            p = Path(td)/"cache.json"
            rows = [{"country":"DE","countryName":"Germany","id":"a","ip":"203.0.113.3"},
                    {"country":"US","countryName":"United States","id":"b","ip":"203.0.113.4"}]
            script.put_json.__globals__["STATE"] = Path(td)
            script.put_json(p, {"time":0, "servers":rows})
            from unittest.mock import patch
            with patch.object(script,"CACHE",p), patch.object(script,"run",side_effect=AssertionError("network fetch")):
                loaded, stale = script.directory()
            self.assertEqual(loaded,rows)
            self.assertTrue(stale)

    def test_strip_remote_options_and_ignore_setenv(self):
        ovpn = sample(extra='setenv bypassscript security\nverb 11\npersist-tun')
        clean = script.checked_profile(base64.b64encode(ovpn.encode()).decode(), "203.0.113.11")
        self.assertIn("remote 203.0.113.11 1194", clean)
        self.assertIn("remote-cert-tls server", clean)
        self.assertNotIn("setenv", clean)
        self.assertIn("<ca>", clean)

    def test_live_vpngate_cipher_negotiation(self):
        data = sample(extra="data-ciphers AES-128-CBC")
        data = data.replace("auth-user-pass", "")
        data = data.replace("remote-cert-tls server", "")
        clean = script.checked_profile(base64.b64encode(data.encode()).decode(), "203.0.113.11")
        self.assertIn("data-ciphers AES-128-CBC", clean)
        self.assertNotIn("auth-user-pass", clean)

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
