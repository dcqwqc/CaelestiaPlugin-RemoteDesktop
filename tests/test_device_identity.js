const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const source = fs.readFileSync(path.join(__dirname, "../services/DeviceIdentity.js"), "utf8");
const identity = vm.createContext({ Set });
vm.runInContext(source.replace(/^\.pragma library\s*\n/, ""), identity);
const node = (ID, HostName, DNSName, Online, ip) => ({
    ID, HostName, DNSName, Online, TailscaleIPs: ip ? [ip] : []
});

const self = node(101, "mirai", "mirai.tail.ts.net.", true, "100.1.0.1");
const repeatedSelf = node(101, "localhost", "mirai.tail.ts.net.", true, "100.1.0.1");
const ipad = node(202, "localhost", "ipad.tail.ts.net.", false, "100.1.0.2");
const desktop = node(303, "tachibana", "tachibana.tail.ts.net.", true, "100.1.0.3");
const anotherMirai = node(404, "Mirai", "mirais.tail.ts.net.", false, "100.1.0.4");
const peers = [repeatedSelf, ipad, desktop, anotherMirai, ipad];
const all = identity.distinctNodes(self, peers);
assert.equal(all.length, 4, "remove only actual duplicate node IDs");
assert.equal(all.filter(item => item.isSelf).length, 1, "only one local row");
assert.equal(all[0].node.ID, 101, "prefer Self record");
assert.equal(identity.displayName(ipad), "ipad", "generic localhost uses actual DNS label");
assert.equal(identity.displayName(desktop), "tachibana");
assert.equal(all.filter(item => item.node.HostName.toLowerCase() === "mirai").length, 2,
    "same display hostname is not sufficient evidence of duplicate hardware");
assert.equal(identity.distinctNodes(self, [node(null, "localhost", "", true, "100.1.0.1")]).length, 1,
    "IP fallback prevents duplicate local row when legacy peer ID is unavailable");
assert.equal(identity.distinctNodes(self, [node(505, "localhost", "unknown.tail.ts.net.", true, "100.1.0.5")]).length, 2,
    "real generic-named peers are preserved");
assert.equal(identity.displayName(node(505, "localhost", "", true)), "localhost",
    "manual overrides can still identify peers with no MagicDNS");

let devices = [
    { actionHost: "mirai.tail.ts.net", online: true, sshKnown: true, sshAvailable: true },
    { actionHost: "tachibana.tail.ts.net", online: true, sshKnown: true, sshAvailable: false }
];
const cached = {
    "mirai.tail.ts.net": { reachable: true },
    "tachibana.tail.ts.net": { reachable: false }
};
assert.equal(identity.deviceHealth(devices[0], "", "Running", ""), "reachable");
assert.equal(identity.deviceHealth(devices[1], "", "Running", ""), "degraded");
assert.equal(identity.deviceHealth(devices[0], "invalid response", "Running", ""), "unknown",
    "poll errors must not show stale green");
devices[1] = { ...devices[1], online: false, sshAvailable: false };
const afterOffline = identity.retainOnlineAvailability(cached, devices);
assert.equal(Object.hasOwn(afterOffline, "tachibana.tail.ts.net"), false,
    "offline transition invalidates previously probed SSH state");
assert.equal(Object.hasOwn(afterOffline, "mirai.tail.ts.net"), true,
    "normal online refresh retains status instead of flickering");
assert.equal(identity.deviceHealth(devices[1], "", "Running", ""), "offline");
assert.equal(identity.deviceHealth(devices[1], "Tailscale stopped", "Stopped", ""), "offline");
const comingBack = { ...devices[1], online: true, sshKnown: false, sshAvailable: false };
assert.equal(identity.deviceHealth(comingBack, "", "Running", ""), "unknown",
    "reconnection waits for a fresh SSH probe instead of falsely turning green");
assert.equal(identity.deviceHealth({ ...comingBack, sshKnown: true, sshAvailable: true }, "", "Running", ""), "reachable");
console.log("PASS: node-ID/IP deduplication, localhost DNS naming, real peers, actions' identities, and status transitions");
