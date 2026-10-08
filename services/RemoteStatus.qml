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

    // OpenAI MCP tunnel health is discovered from server-class devices rather
    // than hardcoding a machine name. The helper finds the server that actually
    // hosts philipedia-terminal and returns its watchdog status.
    property var tunnelProbeTargets: []
    property string tunnelState: "unknown"
    property string tunnelHost: ""

    // Local control-plane health. The repair button restarts the fixed system
    // services through polkit, then user-scoped streaming/tunnel services, and
    // finally runs this diagnosis. `blocked` means normal HTTPS works but the
    // Tailscale control plane is being reset upstream, so more local restarts
    // cannot help and the UI can suggest mobile data/another Wi-Fi instead.
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

    function diagnoseConnectivity(): void {
        if (!connectivityDiagProc.running)
            connectivityDiagProc.running = true;
    }

    function repairConnectivity(): void {
        if (connectivityRepairing)
            return;
        connectivityRepairing = true;
        connectivityRepairError = "";
        connectivityMessage = qsTr("Restarting Tailscale, SSH and remote services…");
        repairUserProc.running = true;
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
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
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
                            : !!node.Online;
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
                            sshAvailable: online && !!root.sshAvailability[actionHost]
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
                    // Leave previous state on a parse failure (e.g. tailscale down).
                }
            }
        }
    }

    // Tailscale reports peer reachability, not whether a regular SSH daemon is
    // listening. Probe TCP/22 without authenticating so dead SSH endpoints are
    // disabled in the popout before the user launches Ghostty.
    Process {
        id: sshProbeProc

        command: {
            const probe = [
                "python3", "-c",
                "import json, socket, sys\n"
                + "results = {}\n"
                + "for host in sys.argv[1:]:\n"
                + "    try:\n"
                + "        connection = socket.create_connection((host, 22), timeout=0.75)\n"
                + "        connection.close()\n"
                + "        results[host] = True\n"
                + "    except OSError:\n"
                + "        results[host] = False\n"
                + "print(json.dumps(results))"
            ];
            return probe.concat(root.sshProbeTargets);
        }
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const available = JSON.parse(text);
                    root.sshAvailability = Object.assign({}, root.sshAvailability, available);
                    root.devices = root.devices.map(device => {
                        const updated = Object.assign({}, device);
                        updated.sshKnown = true;
                        updated.sshAvailable = device.online && !!available[device.actionHost];
                        return updated;
                    });
                } catch (e) {
                    // Keep the prior disabled state when the probe cannot run.
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
                    if (String(status.host ?? "").length > 0)
                        root.tunnelHost = String(status.host);
                } catch (e) {
                    root.tunnelState = "unknown";
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                root.tunnelState = "unknown";
        }
    }


    // Repair is intentionally split in two privilege domains. Optional user
    // services use try-restart so disabled features stay disabled. The two
    // system daemons need polkit; pkexec gives the user the normal graphical
    // authentication prompt without installing a broad NOPASSWD sudo rule.
    Process {
        id: repairUserProc
        command: [root.connectivityBin, "repair-user"]
        running: false
        onExited: code => {
            if (!repairSystemProc.running)
                repairSystemProc.running = true;
        }
    }

    Process {
        id: repairSystemProc
        command: ["pkexec", "/usr/bin/systemctl", "restart", "tailscaled.service", "sshd.service"]
        running: false
        stderr: StdioCollector {
            onStreamFinished: root.connectivityRepairError = text.trim()
        }
        onExited: code => {
            if (code !== 0 && root.connectivityRepairError.length === 0)
                root.connectivityRepairError = qsTr("System-service restart was cancelled or failed.");
            connectivityRepairDelay.restart();
        }
    }

    Timer {
        id: connectivityRepairDelay
        interval: 1400
        repeat: false
        onTriggered: {
            root.refresh();
            root.diagnoseConnectivity();
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
            if (code !== 0)
                root.connectivityRepairing = false;
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
