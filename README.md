# RemoteDesktop

A two-way Moonlight/Sunshine desktop link between configured hosts, in the
Caelestia bar.

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

## Licence

GPL-3.0-or-later, matching Caelestia.

## MCP tunnel health

The bar status light now includes the OpenAI MCP tunnel used by Philipedia Terminal. Green means the local remote path and tunnel are healthy, amber means a dependency is degraded, red means a dependency is offline, and gray means a probe is still unknown. The popout also shows the tunnel state and the server that answered the health probe.

Server discovery uses `device-types.conf`; it probes server-class peers and uses the first one that exposes the Philipedia tunnel watchdog, so the UI does not need a hard-coded Tailscale hostname.
