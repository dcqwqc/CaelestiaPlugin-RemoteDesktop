.pragma library

// A Tailscale hostname is a display label, NOT device identity. The numeric
// node ID is stable across hostname changes; IP/DNS are fallback identities
// only for malformed or older status responses missing that ID.
function identityKey(node) {
    const id = String(node?.ID ?? "").trim();
    if (id && id !== "0")
        return "node:" + id;
    const ips = (node?.TailscaleIPs ?? []).filter(ip => !!ip).slice().sort();
    if (ips.length > 0)
        return "ip:" + ips.join(",");
    const dns = String(node?.DNSName ?? "").trim().toLowerCase().replace(/\.$/, "");
    return dns ? "dns:" + dns : "hostname:" + String(node?.HostName ?? "").trim().toLowerCase();
}

function distinctNodes(self, peers) {
    const result = [];
    const seenKeys = new Set();
    const seenIPs = new Set();
    function add(node, isSelf) {
        if (!node?.HostName)
            return;
        const key = identityKey(node);
        const ips = (node.TailscaleIPs ?? []).filter(ip => !!ip);
        // Prefer Self over a stale/duplicated peer record. Never merge simply
        // because two REAL machines happen to share a generic hostname.
        if (seenKeys.has(key) || ips.some(ip => seenIPs.has(ip)))
            return;
        seenKeys.add(key);
        for (const ip of ips)
            seenIPs.add(ip);
        result.push({ node: node, isSelf: isSelf });
    }
    add(self, true);
    for (const peer of peers ?? [])
        add(peer, false);
    return result;
}

function displayName(node) {
    const raw = String(node?.HostName ?? "").trim();
    if (!/^(localhost|localhost\.localdomain)$/i.test(raw))
        return raw;
    // A genuine peer sometimes reports HostName=localhost while Tailscale
    // gives it a distinct MagicDNS name (e.g. ipad). Use that actual peer
    // label rather than showing an apparent second local computer.
    const dnsLabel = String(node?.DNSName ?? "").trim().replace(/\.$/, "").split(".")[0];
    return dnsLabel && !/^(localhost|localhost\.localdomain)$/i.test(dnsLabel)
        ? dnsLabel : raw;
}

function retainOnlineAvailability(availability, devices) {
    const liveHosts = new Set(devices.filter(device => device.online)
        .map(device => device.actionHost));
    const retained = {};
    for (const [host, result] of Object.entries(availability))
        if (liveHosts.has(host))
            retained[host] = result;
    return retained;
}

function deviceHealth(device, tailscaleError, backendState, sshProbeError) {
    // A valid "Stopped" tailnet snapshot is offline (red), not a perpetual
    // unknown/amber status. A failed/unparseable poll is unknown, never green.
    if (!device.online && backendState !== "Running")
        return "offline";
    if (tailscaleError)
        return "unknown";
    if (!device.online)
        return "offline";
    if (sshProbeError || !device.sshKnown)
        return "unknown";
    return device.sshAvailable ? "reachable" : "degraded";
}
