from pathlib import Path
import importlib.machinery
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
m = importlib.machinery.SourceFileLoader("vpngate_quality",str(ROOT/"scripts/vpngate-route")).load_module()


def row(n, speed=50, score=100000, country="JP", uptime=86400):
    return {"id": f"{n:016x}", "ip": f"192.0.2.{n}", "country": country,
            "score": score, "mbps": speed, "ping": 2,
            "uptime": uptime, "sessions": 14}


class VPNQualityTests(unittest.TestCase):
    def test_default_sort_and_rejected_modes(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(m, "PREFS", Path(tmp)/"preferences.json"):
                self.assertEqual(m.read_preferences(),"recommended")
                self.assertEqual(m.choose_sort("latency"), {"sort": "latency"})
                self.assertEqual(m.read_preferences(),"latency")
                with self.assertRaises(m.RouteError):
                    m.choose_sort("../../invalid")

    def test_line_mode_is_exact_provider_speed(self):
        a, b = row(1,3733), row(2,150)
        results=m.relay_options([b,a],"JP",sort="line",history={})
        self.assertEqual([r["ip"] for r in results],[a["ip"],b["ip"]])
        self.assertIsNone(results[0]["measuredMbps"])

    def test_recommended_capped_excessive_line_speed(self):
        huge=row(1,3733,score=1200,uptime=0)
        reliable=row(2,150,score=1600000,uptime=500000)
        results=m.relay_options([huge,reliable],"JP",sort="recommended",history={})
        self.assertEqual(results[0]["ip"], reliable["ip"])

    def test_real_measured_precedes_unmeasured_fastest(self):
        now=time.time()
        a=row(1,3733)
        b=row(2,80)
        history={b["ip"]:{"measured_mbps":27.1,"measured_at":now}}
        results=m.relay_options([a,b],"JP",sort="fastest",history=history)
        self.assertEqual(results[0]["ip"],b["ip"])
        self.assertEqual(results[0]["measuredMbps"],27.1)
        self.assertIsNone(results[1]["measuredMbps"])

    def test_latency_only_when_local_measurement_recent(self):
        now=time.time()
        a,b,c=row(1),row(2),row(3)
        history={a["ip"]:{"latency_ms":300,"latency_at":now},
                 b["ip"]:{"latency_ms":200,"latency_at":now},
                 c["ip"]:{"latency_ms":9,"latency_at":now-15*86400}}
        result=m.relay_options([c,a,b],"JP",sort="latency",history=history)
        self.assertEqual([r["ip"] for r in result],[b["ip"],a["ip"],c["ip"]])
        self.assertEqual(result[0]["latencyMs"],200)
        self.assertIsNone(result[2]["latencyMs"])

    def test_failures_penalized_and_observations_recorded(self):
        base=row(1)
        history={base["ip"]:{"attempts":5,"successes":0,"failure_streak":5,
                             "last_failure":time.time()}}
        self.assertLess(m.recommended_score(base,history),
                        m.recommended_score(base,{}))
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(m,"QUALITY",Path(tmp)/"history.json"), \
                 patch.object(m,"STATE",Path(tmp)):
                m.record_connection(base,False,999)
                m.record_connection(base,True,320)
                obj=m.relay_history()[base["ip"]]
                self.assertEqual((obj["attempts"],obj["successes"],obj["failure_streak"]),(2,1,0))
                self.assertEqual(obj["connect_ms"],320)

    def test_tcp_probe_only_from_sanitized_openvpn_config(self):
        import base64
        d="client\nproto udp\nremote 192.0.2.1 1194\n<ca>\n-----BEGIN CERTIFICATE-----\nZm9v\n-----END CERTIFICATE-----\n</ca>\n"
        r=row(1)
        r["config"]=base64.b64encode(d.encode()).decode()
        self.assertIsNone(m.safe_probe_endpoint(r))
        r["config"]=base64.b64encode(d.replace("proto udp","proto tcp").encode()).decode()
        self.assertEqual(m.safe_probe_endpoint(r),("192.0.2.1",1194))

    def test_benchmark_no_network_when_not_connected(self):
        with patch.object(m, "active", return_value=False), \
             patch.object(m, "run", side_effect=AssertionError("unexpected network")):
            with self.assertRaises(m.RouteError):
                m.benchmark()

    def test_benchmark_declines_direct_non_tunnel_route(self):
        with patch.object(m,"active",return_value=True), \
             patch.object(m,"read_json",return_value={"ip":"192.0.2.3","country":"JP"}), \
             patch.object(m,"run",return_value="1.1.1.1 via 192.168.1.1 dev wlan0"):
            with self.assertRaisesRegex(m.RouteError,"not routed over a VPN"):
                m.benchmark()

    def test_no_history_or_prefs_mutation_from_readonly_sort(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(m, "STATE", Path(tmp)), \
                 patch.object(m, "QUALITY", Path(tmp)/"quality.json"), \
                 patch.object(m, "PREFS", Path(tmp)/"prefs.json"):
                m.relay_options([row(1)],"JP")
                self.assertEqual(list(Path(tmp).iterdir()),[])


if __name__=="__main__":
    unittest.main()
