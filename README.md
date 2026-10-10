# Devices

A Caelestia hub for discovering, monitoring, and controlling connected devices
through Tailscale, Moonlight/Sunshine, SSH, Wake-on-LAN, and optional integrations.
The bar icon lives **inside the rounded status-icons group, immediately under
Wi-Fi**, when using the companion [kagami-caelestia](https://github.com/dcqwqc/kagami-caelestia) fork.

The repository retains its historical `CaelestiaPlugin-RemoteDesktop` URL and
`remote-desktop` installation path so existing integrations and scripts keep working.

Both machines serve and both consume, so the panel asks "is this the other one?"
rather than "is this the machine that streams?". Each host row reports whether a
session is up and which way it points — *connected* when your client is on their
screen, *viewing this screen* when theirs is on yours — and offers connect,
leave, wake and SSH exactly where each is possible.

Hosts come from `~/.config/kagami/hosts.conf`, never from a list in the code, and
Wake appears only where a MAC is configured, because Tailscale does not expose
them.

## Requires

`moonlight-qt` and `sunshine` on both ends, `tailscale`, `jq`, and the
`kagami-remote` helper from [kagami](https://github.com/dcqwqc/CaelestiaPlugin-Kagami).

## Settings

From the Plugins page: bitrate (zero derives it from the streamed resolution),
frame rate, how long the remote workspace may sit unwatched before the client is
dropped, whether the streamed host adopts your keyboard layout, and whether
system shortcuts are sent to the remote.

That last one matters more than it looks. Moonlight locks the pointer while its
window has focus, so a focus change is the only way out of a session — capturing
shortcuts takes away the keys that do it. `never` is the default for that reason.

`kagami-remote` reads the same settings, so a session started from the bar and
one started from a keybind behave identically.

## Status

Caelestia's plugin loader is not released yet — it lives on upstream's unmerged
`feat/plugins` branch, and the Plugins page there is a mockup rendering four
fake cards. So this needs a shell that carries the loader:

- **On upstream Caelestia**, wait for that branch to merge.
- **On a fork that has cherry-picked it** (`plugin/src/Caelestia/Plugins`, plus a
  Plugins page and the quick-toggle / bar-entry hooks), it loads and is managed
  from Nexus → Plugins today.

The manifest and entry points are built against that branch's own parser rather
than a guess at it, so the shape is the real one.

## Install

Clone into Caelestia's plugin directory:

    git clone https://github.com/dcqwqc/CaelestiaPlugin-RemoteDesktop ~/.local/share/caelestia/plugins/remote-desktop

Or clone anywhere and add the parent to `path` in
`~/.config/caelestia/plugins.json`.

## Upgrade from RemoteDesktop

The visible plugin name and generated plugin ID changed to **Devices**.
After upgrading, change `dcqwqc/remotedesktop` to `dcqwqc/devices` in both
`enabled` and `settings` in `~/.config/caelestia/plugins.json`, retaining
all the values under the settings key. The bar entry point remains named
`remoteDesktop` internally for compatibility; it is now rendered inside
`StatusIcons.qml` instead of being a separate item in `bar.entries`.
Remove the standalone `remoteDesktop` bar entry from `shell.json` to
avoid duplicates.

The Devices popout continues to provide remote desktop, SSH, wake, routes,
connectivity checks, and device-specific overrides.

## Licence

GPL-3.0-or-later, matching Caelestia.

## MCP tunnel health

The bar status light now includes the OpenAI MCP tunnel used by Philipedia Terminal. Green means the local remote path and tunnel are healthy, amber means a dependency is degraded, red means a dependency is offline, and gray means a probe is still unknown. The popout also shows the tunnel state and the server that answered the health probe.

Server discovery uses `device-types.conf`; it probes server-class peers and uses the first one that exposes the Philipedia tunnel watchdog, so the UI does not need a hard-coded Tailscale hostname.

## Why a status light is not green

A non-green light always has a diagnosis in the Devices popout. The bar
shows a compact status dot; open the panel for details instead of a giant tooltip. This includes each listed device, the
local remote/SSH path, and the Philipedia MCP tunnel. Red means reported offline,
amber means a reachable device has a failed dependency, and gray means a probe
has not yet finished or failed without a usable reading. Status checks refresh
automatically; errors clear when the corresponding check succeeds.

- **Tailscale offline:** shows the backend state or the peer's reported offline
  state plus last-seen timestamp when available. Tailscale does not reveal
  whether a remote device is powered off, asleep, or lacking connectivity, so
  the UI does not invent that root cause.
- **SSH degraded:** the TCP/22 diagnostic exposes the actual socket error,
  e.g. connection refused, timed out, or DNS resolution failed. It does not
  mistake TCP reachability for proof that SSH authentication will succeed.
- **MCP tunnel degraded/offline:** the checker exposes the inactive service,
  failed readiness request, stale command poll, missing watchdog, or SSH error
  observed on the server, rather than just showing a generic degraded label.
  If every configured server is already offline in the latest Tailscale
  snapshot, the panel reports that immediately instead of waiting for an SSH
  timeout; it resumes watchdog probing as soon as a server comes online.
- **Probe unknown/error:** the status explains which probe could not run or
  which result was missing; it never displays green using stale data.

Run `python3 -m unittest discover -s tests -v` to test diagnostic scenarios.

### Compact, local-first Devices popout

The **current machine** is always pinned at the top, regardless of per-device
visibility overrides. Its status dot summarizes local connectivity and MCP
health, and its error explanation is **always visible** when not green (no
collapse control). Each remote device occupies only a compact name/status row
until its downward chevron is selected. Expanding a peer reveals its diagnostic
reason; remote-control actions remain on the compact row, and refreshes do not close expanded panels.
The popout has a bounded height and scrolls within the screen if necessary.

### Compact controls and status dots

Connection actions (Connect, Wake, SSH Terminal, mirroring, Disconnect) always
remain on the same row as the device name, even when diagnostics are collapsed.
The small name-sized chevron sits immediately after remote device names, and
only expands the diagnostics. Current-device diagnostics remain non-collapsible.
Only the status dot carries the at-a-glance health state (green for ready, amber
for checking/degraded, red for offline); word labels are hidden.


### Safe refresh

The Devices header refresh button is read-only: it rechecks Tailscale,
connectivity, SSH/TCP reachability, tunnel and remote-desktop session state.
It never restarts Tailscale, sshd or streaming services. Polling continues
automatically every five seconds (connectivity/Tailscale) and ten seconds
(tunnel). Red diagnostics stay visible inline, without global tooltips.
Do not reintroduce network-service restarts behind the refresh icon.

### Generic loopback peer cleanup

A peer named localhost is hidden from the Devices list by default. This does not disconnect it from Tailscale. A per-device explicit enabled override can show it again. The current device always remains visible.
