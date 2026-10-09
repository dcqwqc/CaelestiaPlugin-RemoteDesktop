pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia

Singleton {
    id: root

    // The bar is started by the systemd user manager, whose PATH does not
    // carry ~/.local/bin, so `kagami-remote` cannot be resolved by name from
    // here. The Hyprland keybind spells the path out for the same reason.
    readonly property string bin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/remote-desktop/scripts/remote-desktop`
    readonly property string exitNodeBin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/remote-desktop/scripts/tailscale-exit-node`
    readonly property string tunnelStatusBin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/remote-desktop/scripts/openai-tunnel-status`
    readonly property string connectivityBin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/remote-desktop/scripts/connectivity-repair`

    // Tailscale exit-node state. Selecting one routes all ordinary internet
    // traffic through that peer while keeping local-LAN access available.
    property var exitNodes: []
    property string exitNodeId: ""
    property string exitNodeName: ""
    property string preferredExitNodeId: ""
    property bool exitNodeChanging: false
    property string exitNodeError: ""

    readonly property bool exitNodeActive: exitNodeId.length > 0

    // Which machines this desk actually has, from kagami-remote's own view of
    // hosts.conf. This used to be a literal list of hostnames written twice in
    // the device mapping below, so adding a third machine -- or renaming one --
    // meant editing the shell. hosts.conf is already the one place that knows;
    // now it is the only place.
    property var configuredHosts: ({})
    property var deviceTypes: ({})
    readonly property string deviceTypesFile: `${Quickshell.env("HOME")}/.config/caelestia/remote-desktop/device-types.conf`

    property var devices: []
    property var hostOnline: ({})
    property var sshProbeTargets: []
    property var sshAvailability: ({})
    property string sshProbeError: ""
    readonly property string sshProbeBin: `${Quickshell.env("HOME")}/.local/share/caelestia/plugins/remote-desktop/scripts/device-ssh-probe`
    property string tailscaleError: qsTr("Tailscale status has not completed its first check.")
    property string tailscaleBackend: "unknown"

    function deviceHealth(device): string {
        if (tailscaleError.length > 0) return "unknown";
        if (!device.online) return "offline";
        if (sshProbeError.length > 0) return "unknown";
        if (!device.sshKnown) return "unknown";
        return device.sshAvailable ? "reachable" : "degraded";
    }

    function deviceError(device): string {
        if (tailscaleError.length > 0) return tailscaleError;
        if (!device.online) {
            if (device.isSelf)
                return qsTr("Local Tailscale backend is %1; local tailnet connectivity is unavailable.").arg(tailscaleBackend);
            const seen = String(device.lastSeen ?? "");
            const last = seen.length > 0 && !seen.startsWith("0001-")
                ? qsTr(" Last seen: %1.").arg(seen) : "";
            return qsTr("Tailscale reports %1 offline; its underlying power/network cause is not observable here.").arg(device.name) + last;
        }
        if (sshProbeError.length > 0) return sshProbeError;
        if (!device.sshKnown)
            return sshProbeError.length > 0 ? sshProbeError : qsTr("SSH port 22 has not been checked yet on %1.").arg(device.actionHost);
        if (!device.sshAvailable)
            return String(device.sshReason ?? "").length > 0
                ? device.sshReason
                : qsTr("SSH TCP/22 at %1 is not reachable; the probe returned no further details.").arg(device.actionHost);
        return "";
    }

    // OpenAI MCP tunnel health is discovered from server-class devices rather
    // than hardcoding a machine name. The helper finds the server that actually
    // hosts philipedia-terminal and returns its watchdog status.
    property var tunnelProbeTargets: []
    property string tunnelState: "unknown"
    property string tunnelHost: ""
    property string tunnelReason: qsTr("MCP tunnel health has not been checked yet.")

    readonly property string overallHealth: {
        const local = devices.find(device => device.isSelf);
        const own = local ? deviceHealth(local) : "unknown";
        const tunnel = tunnelState === "online" ? "reachable" : tunnelState;
        if (own === "offline" || tunnel === "offline" || connectivityState === "offline" || connectivityState === "blocked")
            return "offline";
        if (own === "degraded" || tunnel === "degraded" || (connectivityState !== "online" && connectivityState !== "unknown"))
            return "degraded";
        if (own === "unknown" || tunnel === "unknown" || connectivityState === "unknown")
            return "unknown";
        return "reachable";
    }

    readonly property string overallError: {
        const errors = [];
        const local = devices.find(device => device.isSelf);
        if (!local) errors.push(tailscaleError || qsTr("Local device is absent from the latest Tailscale status response."));
        else if (deviceHealth(local) !== "reachable") errors.push(qsTr("Local device: %1").arg(deviceError(local)));
        if (tunnelState !== "online") errors.push(qsTr("MCP tunnel: %1").arg(tunnelReason || qsTr("Probe returned %1 without details.").arg(tunnelState)));
        if (connectivityState !== "online") errors.push(qsTr("Network: %1").arg(connectivityMessage || qsTr("Connectivity check pending (%1).").arg(connectivityState)));
        return errors.join(String.fromCharCode(10));
    }

    // Diagnose connectivity without restarting remote-access services.
    // A blocked control plane often cannot be repaired by local restarts.
    property string connectivityState: "unknown"
    property string connectivityMessage: ""
    property bool connectivityRepairing: false
    property string connectivityRepairError: ""

    // A session has a direction, and the two halves are found in different
    // places. `viewing` is answerable here -- it is our own Moonlight client.
    // `shared` is the peer's client looking at us, which only the peer can see,
    // so it costs a round trip and is polled far less often.
    property string localState: "disconnected"
    property string linkState: "disconnected"

    readonly property bool viewing: localState === "viewing"
    readonly property bool shared: !viewing && linkState === "shared"
    // Kept as the single "is anything up between these two machines" flag.
    readonly property bool streaming: viewing || shared

    // The one other machine this host can hold a session with. Both ends run
    // Sunshine and Moonlight, so the popout no longer asks "is this the host
    // that streams?" but simply "is this the other one?".
    readonly property string peerId: {
        const peer = devices.find(device => device.canRemoteDesktop && !device.isSelf);
        return peer ? peer.id : "";
    }

    function refresh(): void {
        if (!tailscaleProc.running)
            tailscaleProc.running = true;
        if (!localStateProc.running)
            localStateProc.running = true;
    }

    // Read-only, on-demand diagnosis. Never restart tailscaled, sshd or any
    // service from the refresh control: it may be the user's only remote path.
    // Polls run automatically as well, so this is just an immediate recheck.
    function refreshNow(): void {
        root.refresh();
        root.diagnoseConnectivity();
        if (!tunnelStatusProc.running)
            tunnelStatusProc.running = true;
        if (!linkStateProc.running)
            linkStateProc.running = true;
        if (!sshProbeProc.running && root.sshProbeTargets.length > 0)
            sshProbeProc.running = true;
    }

    function diagnoseConnectivity(): void {
        if (!connectivityDiagProc.running)
            connectivityDiagProc.running = true;
    }

    // Compatibility with older callers: repair requests are diagnostic-only
    // until a separate, explicitly confirmed and connection-safe repair flow
    // is designed.
    function repairConnectivity(): void {
        root.refreshNow();
    }

    function setExitNode(nodeId): void {
        if (exitNodeChanging)
            return;

        let target = "";
        if (nodeId.length > 0) {
            const node = exitNodes.find(candidate => candidate.id === nodeId);
            if (!node || !node.online) {
                exitNodeError = qsTr("That exit node is offline.");
                return;
            }
            target = node.actionHost;
            preferredExitNodeId = node.id;
        }

        exitNodeChanging = true;
        exitNodeError = "";
        exitNodeProc.errorText = "";
        exitNodeProc.command = target.length > 0
            ? [exitNodeBin, "set", target]
            : [exitNodeBin, "off"];
        exitNodeProc.running = true;
    }

    function toggleExitNode(): void {
        if (exitNodeActive) {
            setExitNode("");
            return;
        }

        let node = exitNodes.find(candidate => candidate.id === preferredExitNodeId && candidate.online);
        if (!node)
            node = exitNodes.find(candidate => candidate.online);
        if (!node) {
            exitNodeError = qsTr("No exit node is online.");
            return;
        }
        setExitNode(node.id);
    }

    Component.onCompleted: {
        hostsProc.running = true;
        deviceTypesProc.running = true;
        root.refresh();
        root.diagnoseConnectivity();
    }

    // Read once at startup: hosts.conf is hand-edited, not something that
    // changes while the bar is up.
    Process {
        id: hostsProc

        command: [root.bin, "--hosts"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const hosts = {};
                    for (const host of data.hosts ?? [])
                        hosts[host.name.toLowerCase()] = host;
                    root.configuredHosts = hosts;
                } catch (e) {
                    // Leave it empty: no configured hosts means no session and
                    // no wake actions offered, which is the right answer on a
                    // machine with no hosts.conf.
                }
            }
        }
    }

    // Device form factor is separate from connectivity. Keeping it in a
    // tiny config file means the UI never hardcodes specific host names.
    Process {
        id: deviceTypesProc

        command: ["cat", root.deviceTypesFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const types = {};
                for (const rawLine of text.split("\n")) {
                    const line = rawLine.trim();
                    if (!line.length || line.startsWith("#"))
                        continue;
                    const parts = line.split(/\s+/);
                    if (parts.length >= 2)
                        types[parts[0].toLowerCase()] = parts[1].toLowerCase();
                }
                root.deviceTypes = types;
            }
        }
    }

    Process {
        id: tailscaleProc

        command: ["tailscale", "status", "--json"]
        running: false
        property string stderrText: ""
        stderr: StdioCollector { onStreamFinished: tailscaleProc.stderrText = text.trim() }
        onExited: code => {
            if (code !== 0)
                root.tailscaleError = qsTr("tailscale status --json failed (exit %1): %2").arg(code).arg(stderrText || qsTr("no error output"));
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.tailscaleBackend = String(data.BackendState ?? "unknown");
                    root.tailscaleError = data.BackendState === "Running" ? ""
                        : qsTr("Tailscale backend state is %1%2").arg(root.tailscaleBackend)
                            .arg(Array.isArray(data.Health) && data.Health.length > 0 ? ": " + data.Health.join("; ") : "");
                    const byHost = {};
                    const devices = [];
                    const exitNodes = [];
                    let activeExitNodeId = "";
                    let activeExitNodeName = "";
                    const addDevice = (node, isSelf) => {
                        if (!node?.HostName)
                            return;

                        const actionHost = (node.DNSName || node.HostName).replace(/\.$/, "");
                        // HostName is not unique on a tailnet: two machines on a tailnet
                        // can share a HostName differing only in case, which
                        // lowercasing collided into one id. That put a second, offline                        // duplicate row in the popout carrying Connect and Wake,
                        // and -- because peerId takes the first match -- aimed
                        // the session state at the wrong machine entirely. The
                        // MagicDNS label is unique by construction (they differ in the DNS
                        // label even when the HostName does not), so identity comes from there and
                        // falls back to HostName only if DNSName is absent.
                        const hostId = (actionHost.split(".")[0] || node.HostName).toLowerCase();
                        // Tailscale's Self.Online is a control-plane status bit and can
                        // briefly be false even while this machine's tailnet address is
                        // fully usable. For the local host, treat a running Tailscale
                        // backend with an assigned tailnet IP as available, then let the
                        // TCP/22 probe below decide whether SSH is actually reachable.
                        const online = isSelf
                            ? data.BackendState === "Running" && (node.TailscaleIPs ?? []).length > 0
                            : data.BackendState === "Running" && !!node.Online;
                        byHost[hostId] = online;

                        if (!isSelf && node.ExitNodeOption) {
                            const active = !!node.ExitNode;
                            exitNodes.push({
                                id: hostId,
                                name: node.HostName,
                                actionHost: actionHost,
                                online: online,
                                active: active
                            });
                            if (active) {
                                activeExitNodeId = hostId;
                                activeExitNodeName = node.HostName;
                            }
                        }

                        devices.push({
                            id: hostId,
                            name: node.HostName,
                            actionHost: actionHost,
                            online: online,
                            lastSeen: String(node.LastSeen ?? ""),
                            os: node.OS || "",
                            type: root.deviceTypes[hostId]
                                || ((node.OS || "").toLowerCase() === "android" ? "phone"
                                    : (node.OS || "").toLowerCase() === "ios" ? "tablet"
                                    : "desktop"),
                            isSelf: isSelf,
                            // Configured in hosts.conf, never inferred from
                            // tailnet membership. Both hosts serve and both
                            // consume: the link is symmetric, so any configured
                            // machine this shell is not running on is a valid
                            // session target.
                            canRemoteDesktop: !!root.configuredHosts[hostId],
                            // Wake needs a MAC. Tailscale deliberately does not
                            // expose them, so this is exactly the set of hosts
                            // whose hosts.conf line carries one.
                            canWake: !isSelf && !!root.configuredHosts[hostId]?.mac,
                            // `tailscale status --json` only reports the optional
                            // Tailscale SSH service here. That is not an indicator
                            // of regular SSH over a Tailscale address, which is what
                            // this action launches. Offer it for every peer; ssh
                            // itself remains responsible for authentication/access.
                            canSsh: !isSelf,
                            // Preserve the previous port-22 result while a new
                            // Tailscale snapshot is being probed. Without this the
                            // icon visibly alternates gray/dark every refresh.
                            sshKnown: !online || root.sshAvailability[actionHost] !== undefined,
                            sshAvailable: online && !!root.sshAvailability[actionHost]?.reachable,
                            sshReason: String(root.sshAvailability[actionHost]?.reason ?? "")
                        });
                    };

                    addDevice(data.Self, true);
                    for (const peer of Object.values(data.Peer ?? {}))
                        addDevice(peer, false);
                    const availableExitNodes = exitNodes
                        .filter(node => node.online || node.active)
                        .sort((a, b) => a.name.localeCompare(b.name));
                    if (JSON.stringify(root.exitNodes) !== JSON.stringify(availableExitNodes))
                        root.exitNodes = availableExitNodes;
                    root.exitNodeId = activeExitNodeId;
                    root.exitNodeName = activeExitNodeName;
                    if (activeExitNodeId.length > 0)
                        root.preferredExitNodeId = activeExitNodeId;

                    root.devices = devices;
                    root.hostOnline = byHost;
                    root.sshProbeTargets = devices
                        .filter(device => device.online)
                        .map(device => device.actionHost);
                    if (!sshProbeProc.running && root.sshProbeTargets.length > 0)
                        sshProbeProc.running = true;

                    root.tunnelProbeTargets = devices
                        .filter(device => device.type === "server" && !device.isSelf)
                        .map(device => device.actionHost);
                    if (!tunnelStatusProc.running)
                        tunnelStatusProc.running = true;
                } catch (e) {
                    // Retain device identities but never show a stale green status.
                    root.tailscaleError = qsTr("Cannot parse Tailscale status JSON: %1").arg(String(e));
                }
            }
        }
    }

    // Tailscale reports peer reachability, not whether a regular SSH daemon is
    // listening. Probe TCP/22 without authenticating so dead SSH endpoints are
    // disabled in the popout before the user launches Ghostty.
    Process {
        id: sshProbeProc

        command: [root.sshProbeBin].concat(root.sshProbeTargets)
        running: false
        property string stderrText: ""
        stderr: StdioCollector { onStreamFinished: sshProbeProc.stderrText = text.trim() }
        onExited: code => {
            if (code !== 0)
                root.sshProbeError = qsTr("SSH diagnostic command failed (exit %1): %2").arg(code).arg(stderrText || qsTr("no output"));
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const available = JSON.parse(text);
                    if (!available || typeof available !== "object" || Array.isArray(available))
                        throw new Error("Expected a JSON object of host diagnostics");
                    root.sshAvailability = Object.assign({}, root.sshAvailability, available);
                    root.sshProbeError = "";
                    root.devices = root.devices.map(device => {
                        const result = root.sshAvailability[device.actionHost];
                        const updated = Object.assign({}, device);
                        updated.sshKnown = !device.online || result !== undefined;
                        updated.sshAvailable = !!device.online && !!result?.reachable;
                        updated.sshReason = String(result?.reason ?? "");
                        return updated;
                    });
                } catch (e) {
                    root.sshProbeError = qsTr("Cannot parse SSH diagnostics: %1").arg(String(e));
                }
            }
        }
    }

    // The tunnel can be alive as a process while its OpenAI control-plane
    // poller is stuck. Ask the server-side watchdog for semantic health instead
    // of treating TCP reachability as tunnel health.
    Process {
        id: tunnelStatusProc

        command: [root.tunnelStatusBin].concat(root.tunnelProbeTargets)
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text);
                    const state = String(status.state ?? "unknown");
                    root.tunnelState = ["online", "degraded", "offline"].includes(state)
                        ? state
                        : "unknown";
                    root.tunnelHost = String(status.host ?? "");
                    root.tunnelReason = root.tunnelState === "online" ? "" : String(status.reason || qsTr("Tunnel probe returned %1 without diagnostic detail.").arg(root.tunnelState));
                } catch (e) {
                    root.tunnelState = "unknown";
                    root.tunnelReason = qsTr("Cannot parse MCP tunnel diagnostic response: %1").arg(String(e));
                }
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.tunnelState = "unknown";
                root.tunnelReason = qsTr("MCP tunnel diagnostic process exited with code %1.").arg(code);
            }
        }
    }


    Process {
        id: connectivityDiagProc
        command: [root.connectivityBin, "diagnose"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.connectivityState = String(data.state ?? "unknown");
                    const message = String(data.message ?? "");
                    root.connectivityMessage = root.connectivityRepairError.length > 0
                        ? `${message} ${root.connectivityRepairError}`.trim()
                        : message;
                } catch (e) {
                    root.connectivityState = "unknown";
                    root.connectivityMessage = root.connectivityRepairError.length > 0
                        ? root.connectivityRepairError
                        : qsTr("Could not check remote connectivity.");
                }
                root.connectivityRepairing = false;
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.connectivityState = "unknown";
                root.connectivityMessage = qsTr("Connectivity diagnosis command exited with code %1.").arg(code);
                root.connectivityRepairing = false;
            }
        }
    }

    Process {
        id: exitNodeProc

        property string errorText: ""

        running: false
        stderr: StdioCollector {
            onStreamFinished: exitNodeProc.errorText = text.trim()
        }
        onExited: code => {
            root.exitNodeChanging = false;
            if (code !== 0)
                root.exitNodeError = exitNodeProc.errorText.length > 0
                    ? exitNodeProc.errorText
                    : qsTr("Could not change the exit node.");
            else
                root.exitNodeError = "";

            exitNodeRefreshTimer.restart();
        }
    }

    Timer {
        id: exitNodeRefreshTimer
        interval: 450
        repeat: false
        onTriggered: root.refresh()
    }

    // The cheap half: purely a look at this machine's own Moonlight client, so
    // it never leaves the box and can run on the bar's ordinary cadence.
    Process {
        id: localStateProc

        command: [root.bin, "peer", "status-local"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const state = text.trim();
                root.localState = state === "viewing" ? "viewing" : "disconnected";
            }
        }
    }

    // The expensive half. `status` answers locally when we are the viewer and
    // only reaches for SSH when we are not, so this costs a round trip exactly
    // in the case it is asking about -- someone else watching this screen.
    // That is not a state that changes silently or often, and polling it at the
    // bar's rate would have put an SSH handshake on the tailnet every five
    // seconds on both machines now that both of them can be the far end.
    Process {
        id: linkStateProc

        command: [root.bin, "peer", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.linkState = text.trim();
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!tunnelStatusProc.running)
                tunnelStatusProc.running = true;
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            root.refresh();
            // Re-run the cheap connectivity diagnosis too. This clears stale
            // "network is blocking Tailscale" warnings automatically after
            // the rescue tunnel/control plane recovers.
            root.diagnoseConnectivity();
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: linkStateProc.running = true
    }
}
