# Aether OpenWrt Client Guide

This client integrates the Aether core with OpenWrt. It installs the Aether
binary, a procd service, the `aether-ctl` command, and a LuCI page under
**Services -> Aether**.

## What it does

Aether creates a local SOCKS5 proxy and sends traffic through a censorship-
circumvention tunnel. The OpenWrt integration:

- starts and supervises the core with procd;
- stores identities under `/etc/aether`;
- exposes start, stop, restart, status, logs, and connection tests;
- provides a LuCI configuration page;
- checks the data plane and restarts a stuck core after repeated failures.

The default proxy is `0.0.0.0:1819`. Change it to `127.0.0.1:1819` when the
proxy should be available only on the router itself.

## Protocols

- **MASQUE**: modern HTTP/3/QUIC by default. Enable **HTTP/2** when UDP or
  QUIC is blocked. `firewall` is the recommended MASQUE profile.
- **WireGuard**: usually fast on networks where WireGuard traffic is allowed.
  Use `balanced`, `aggressive`, `light`, or `off`.
- **WARP-in-WARP (gool)**: two WireGuard layers. It can work on stricter
  networks, but has more overhead. Start with the `balanced` profile.
- **MASQUE-in-MASQUE (mim, core v2+)**: two MASQUE hops that can produce a
  different exit address. It supports automatic discovery or explicit outer /
  inner endpoints and shares the MASQUE HTTP/2, fragmentation, ECH, and QUIC
  v2 settings. The two fixed endpoints must be different; MIM also needs a
  second identity registration and adds another round trip.

The client scans candidate endpoints and validates real data flow before
exposing SOCKS5. **Quick Reconnect** first verifies the last successful
endpoint and avoids a full scan when possible.

## Settings

### Basic and network settings

- **Enable on Boot** controls automatic startup after a router reboot. It does
  not prevent the Start and Stop buttons or CLI commands from controlling the
  current runtime.
- **Scan Mode**: `turbo` is fastest; `balanced` is the normal choice;
  `thorough`, `stealth`, and `ironclad` trade time for discovery or validation.
  `verified` (core v2.1+) dials only edges measured to answer connect-ip.
- **IP Version**: use IPv4 unless the router has working IPv6.
- **Force Peer**: optionally skip scanning and use a known `ip:port`.
- **Exit Location Policy** (core v2.1+): refuse tunnels whose exit country is
  not wanted (e.g. `!IR,AZ,RU`); rechecked every minute through the tunnel.
- **Traffic Stats Logging** (core v2.1+): log uploaded/downloaded bytes and
  tunnel uptime every 60 seconds.
- **HTTP/2 Mode** and **H2 Peer** apply to MASQUE and MIM. Use HTTP/2 when
  UDP/QUIC is blocked.
- **TLS Fragmentation** applies to MASQUE/MIM HTTP/2 when its handshake is blocked.
- **QUIC v2 Opener** (core v2+) is enabled by default for MASQUE/MIM HTTP/3;
  it can be disabled for networks where it causes a problem.
- **Encrypted Client Hello (ECH)** (core v1.9+) accepts `auto` or a base64
  configuration. Leave it empty to preserve the core default.
- **HTTP CONNECT Proxy** optionally exposes the same tunnel for applications
  that do not support SOCKS5.
- **Upstream Proxy** (requires core v1.7+) chains the tunnel behind another
  proxy. Accepts `socks5://[user:pass@]host:port`, `http://host:port`, or a
  bare `host:port` (read as SOCKS5). A SOCKS5 upstream carries every
  transport; an HTTP CONNECT upstream requires HTTP/2 mode. The URL is passed
  to the core via `--upstream`, and credentials are redacted in `aether-ctl show`.
- **MASQUE Startup Deadline** bounds connection and first data validation for
  MASQUE/MIM; its default is 30 seconds.
- **Disable Profile Retry** applies to WireGuard/gool/MIM and prevents retrying
  alternate noise profiles after a failed scan.

### Reliability settings

- **Keepalive** applies to WireGuard, gool, and MIM.
- **Reconnect Delay** controls the core retry delay.
- **Validation Timeout** controls the data-plane validation wait.
- **Quick Reconnect** rechecks the cached endpoint before scanning.
- **Data-plane Watchdog** periodically tests traffic through SOCKS5. After
  repeated failures it terminates the stuck core and lets procd start a clean
  instance. Install `curl` to enable it.

## Zero Trust

The LuCI **Zero Trust** section supports headless Cloudflare organization
enrollment with:

- Team name;
- Access client ID;
- Access client secret;
- Existing access token (for headless deployments);
- optional organization Gateway mode.

The secret is stored in `/etc/config/aether`, protected as a root-only file,
and redacted from CLI output and service command listings. Gateway mode is
off by default because organization filtering and logging are opt-in.

Interactive email-code enrollment should be performed with the Aether core
directly from an interactive terminal, not from the boot service.

## Passwall2 Integration

If you run Passwall 2 to transparently proxy LAN clients through Aether, the
client can manage the required setup for you. Use the **Passwall2 Integration**
section on the LuCI page (below *Advanced settings*) or the CLI:

```sh
aether-ctl passwall status            # state, localhost_proxy, matching nodes
aether-ctl passwall localhost off     # stop Passwall2 proxying router-local traffic
aether-ctl passwall localhost on      # re-enable it
aether-ctl passwall add-node          # create the one canonical node: aether_node
```

Behavior:

- `status` inspects every loopback SOCKS node whose section name or remarks
  mention "aether". An exact address/port match with Aether's listener is
  reported as configured; anything else is reported as a conflict.
- Disabling Localhost Proxy prevents a routing loop: while it is enabled,
  Passwall2 intercepts the Aether core's own handshake traffic and the tunnel
  never comes up. When Passwall2's global switch is on, the change restarts it
  automatically.
- `add-node` creates exactly one node named `aether_node` (Xray, socks,
  raw transport) pointing at Aether's current listen address. It never creates
  a second entry.
- If an existing Aether-related node points at a different address/port,
  nothing is changed: the CLI and LuCI print repair instructions instead
  (edit that node's Address/Port under Services -> Passwall2 -> Nodes, or
  delete it and run `add-node` again).

## Performance Profile (core v1.8+)

Core v1.8 introduced a resource profile (`--perf low|medium|high`). During installation,
`install.sh` inspects the router's total RAM and sets the initial value in
`/etc/config/aether`. Operators can adjust it at any time in LuCI (Advanced section
-> **Performance Profile**: `Low`, `Medium`, `High`) or via
`aether-ctl set perf_profile low|medium|high`. To re-detect automatically based on RAM,
run `aether-ctl auto-perf`:
| Total RAM | Profile |
| --- | --- |
| < 256 MB | `low` |
| 256 MB – 768 MB | `medium` |
| > 768 MB | `high` |

Measured on core v1.9.0 (x86_64, peak VmRSS sampled every second; 50 MB
download plus a 5 MB PUT upload per run — the shared `__up` endpoint resets
the upload after part of the body, which does not affect the buffer-driven
peak; MB ≈ peak_kb/1024):

| Protocol | Profile | Download peak | Upload peak |
| --- | --- | --- | --- |
| MASQUE | low | 10.2 MB | 9.8 MB |
| MASQUE | medium | 15.9 MB | 12.6 MB |
| MASQUE | high | 22.6 MB | 12.3 MB |
| WireGuard | low | 7.9 MB | 7.6 MB |
| WireGuard | medium | 12.9 MB | 11.2 MB |
| WireGuard | high | 20.0 MB | 10.7 MB |
| gool | low | 7.8 MB | 7.7 MB |
| gool | medium | 13.4 MB | 11.2 MB |
| gool | high | 20.9 MB | 10.9 MB |

Peak memory scales with the profile, not the protocol; idle RSS is ~5.6–7.1 MB
across the board. The thresholds above leave headroom below the measured peaks
for routers with less RAM.

Routing rules (`--route-block`, `--route-direct`), custom in-tunnel DNS,
firewall marks, and TLS key-share groups remain deliberately unexposed by this
client. Transparent-proxy tools such as Passwall2 handle traffic splitting
better on this router; the remaining controls retain their core defaults.

## Dual-Hop gool Endpoints (core v1.9+)

Core v1.9 lets you pin each WARP-in-WARP hop independently. In LuCI the
**gool Outer Hop** / **gool Inner Hop** fields appear when the protocol is
`gool` (Advanced section); on the CLI:

```sh
aether-ctl set wiw_outer 162.159.192.1:2408
aether-ctl set wiw_inner 188.114.96.1:2408
aether-ctl set wiw_outer auto   # clear back to auto-scan
```

Set one hop and the core scans only for the other; set both and no scan runs.
`auto` (or an empty value) restores the default behaviour where the core scans
both hops. A named hop is retried on reconnect instead of being replaced.

## MASQUE-in-MASQUE, QUIC v2, and Tor (core v2+)

Core v2 adds `mim`, a second MASQUE tunnel inside the first. Set `mim_outer`,
`mim_inner`, or `mim_peers` when you need fixed endpoints; otherwise the core
selects them. `quic_v2` is enabled by default and maps to `--no-quic-v2` only
when disabled.

Tor is available through `tor_mode`:

- `tunnel` keeps the normal WARP SOCKS5 listener and adds a Tor listener; Tor
  traffic travels through WARP.
- `reverse` reaches MASQUE through Tor and leaves through WARP; it requires
  MASQUE and HTTP/2.
- `only` serves Tor from the main SOCKS5 listener and does not establish WARP.

The control appears only on Core v2; it requires a Core package built with Tor
support and any required pluggable transports. The client gates the controls by
version, not by inspecting whether the installed Core package has that build
feature. `reverse` additionally requires the MASQUE protocol — the CLI rejects
it against other protocols in both directions at set time.

The Status panel shows the configured `Tor` state (`Enabled at <bind>`,
`Disabled`, or `Needs core v2.0+`); it is not proof that Tor has bootstrapped.
A **Check Tor IP** button verifies the exit
(`Tor ✓ <ip> — <ms>ms`) via `https://check.torproject.org/api/ip`. The same
check exists on the CLI:

```sh
aether-ctl check-tor        # Tor exit IP and IsTor status (alias: tor-ip)
```

`tor_bind` (default `127.0.0.1:1820`) and `tor_dir` tune the listener and
state directory; `tor_bridges` (`auto`/`on`/`off`) controls bridge fallback
for blocked networks. The CLI check is bounded (8s connect / 22s max) so the
LuCI button stays under the ubus RPC timeout — slow circuits report `FAILED`,
never a transport error. In manual command mode without `--tor` in the
arguments, `check-tor` refuses instantly instead of timing out.

If the Tor listener accepts connections but bootstrap never completes, look
for `problem with filesystem permissions` in `logread -e aether`: Arti
refuses state whose ancestor directories are not root-owned or are
group/world-writable (stock OpenWrt images and tar overlays both break this).
The service repairs `/` and `/etc` automatically on every Tor-enabled start.

### Tor additions on core v2.1+

Two extra controls appear next to the Tor settings when the installed core is
v2.1.0 or newer:

- `tor_http` also serves Tor as an HTTP/CONNECT proxy on the given address,
  for clients that cannot speak SOCKS5.
- `tor_relays` selects where bridges come from: `auto` (default) fetches
  bridgedb bridges and onionoo relays together, `only` uses onionoo relays
  alone, `off` disables relays, and a number (e.g. `80`) sets how many relays
  to measure. On a network that blocks Tor, core v2.1+ also fetches its
  bridges through the finished tunnel, which is what makes Tor work there at
  all.

## Psiphon (core v2.1+)

Core v2.1 embeds Psiphon the same way it embeds Tor, with three modes in
`psiphon_mode`:

- `tunnel` carries Psiphon inside WARP: the normal SOCKS5 listener keeps the
  WARP exit and a second listener on `psiphon_bind` (default
  `127.0.0.1:1821`) exits through Psiphon.
- `reverse` dials the tunnel through Psiphon so WARP is reached from a
  Psiphon exit; it requires the MASQUE protocol (Psiphon carries TCP only, so
  the core runs MASQUE over HTTP/2) and is rejected against other protocols
  in both directions at set time, like Tor reverse.
- `only` serves plain Psiphon from the main SOCKS5 listener and does not
  establish a WARP tunnel.

Nothing else is required: credentials and the server list are built into the
core, and the official release archives ship the `psiphon-tunnel-core` helper
in the `pt/` folder next to the binary (the installer keeps it at
`/usr/bin/pt`). Optional tuning: `psiphon_region` asks for an exit in a
two-letter country (e.g. `DE`), `psiphon_shape` maps to `--psiphon-mode`
(`auto` default, `cdn` limits to fronted meek through a CDN, `direct` turns
fronting off), and `psiphon_http` also serves Psiphon as an HTTP/CONNECT
proxy. Verify the exit with the LuCI **Check Psiphon IP** button or:

```sh
aether-ctl set psiphon_mode tunnel
aether-ctl restart
aether-ctl check-psiphon   # Psiphon exit IP (alias: psiphon-ip)
```

## Exit-location pinning and traffic stats (core v2.1+)

`exit_loc` refuses tunnels whose exit country is not wanted: `!IR,AZ,RU`
blocks those countries, `DE,SE` allows only those. The check runs through the
finished tunnel before SOCKS5 opens and again every minute, so a tunnel that
moves is dropped and replaced. Leave it empty (the default) and nothing is
looked up.

`stats` (off by default) logs uploaded/downloaded bytes and tunnel uptime to
the service log every 60 seconds — watch with `logread -f -e aether`.

## gool carrier choice (core v2.3+)

Core v2.3 changed what `--gool` means: it now carries the WireGuard WARP
tunnel inside MASQUE and registers its identity through the tunnel, so the
exit address is foreign rather than local. The older WireGuard-in-WireGuard
transport stays available as the classic carrier:

- `gool_carrier=masque` (default) uses the new `--gool`; `gool_peer` can pin
  the inner WireGuard endpoint.
- `gool_carrier=classic` passes `--gool-classic` and uses the classic
  `wiw_outer`/`wiw_inner` WARP-in-WARP endpoints.

On cores older than v2.3 the carrier choice is ignored and gool stays classic.
Because naming any `wiw_*` endpoint would make a v2.3+ core select the classic
carrier on its own, the client passes stored `wiw_*` values only when the
classic carrier is selected; with the MASQUE carrier they are reported as
ignored in the service log.

## Custom Command Line

The **Custom Command** section (last on the LuCI page) hands you the core
command line. In **Generated** mode (default) it shows the current command
reported by procd, read-only. Refresh the page after a restart to see the new
generated command. In **Manual** mode a large text box accepts your own
arguments:

- space-separated, no quotes or shell features;
- a leading `/usr/bin/aether` or `/usr/bin/aether-run` is stripped
  automatically, so pasting the whole shown command works;
- empty input falls back to generated flags with a log line;
- still launched through `aether-run`, so Zero Trust secrets stay in the
  environment and out of process listings;
- applies on restart and is remembered in UCI (`command_mode`,
  `custom_command`; `auto` clears the latter on the CLI).

Manual mode bypasses **every** UCI option — protocol, Tor, binds, everything.
The `test`, `check-ip`, and `check-tor` probes read the manual binds instead
(`check-tor` refuses immediately when `--tor` is absent rather than timing
out). The CLI validates `set` values up front (`tor_bind` as `ip:port`,
`tor_dir` as an absolute path, `reverse` only with MASQUE) and `status`/`show`
show
the effective obfuscation profile, e.g. `balanced (stored firewall)` when the
stored value is remapped for the protocol family.

## CLI

```sh
aether-ctl start
aether-ctl stop
aether-ctl restart
aether-ctl status
aether-ctl show
aether-ctl log 100
aether-ctl test google.com
aether-ctl check-ip                     # public IP, country, latency
aether-ctl check-tor                    # Tor exit IP and IsTor status (v2+ Tor modes)
aether-ctl check-psiphon                # Psiphon exit IP (v2.1+ Psiphon modes)
aether-ctl passwall status            # Passwall2 bridge status
aether-ctl passwall localhost off     # disable Passwall2 router-local proxying
aether-ctl set protocol wg
aether-ctl auto-perf                      # auto-detect RAM and set recommended profile (v1.8+)
aether-ctl set perf_profile medium       # or set explicitly: low / medium / high (v1.8+)
aether-ctl set wiw_outer 162.159.192.1:2408   # gool outer hop (v1.9+; classic carrier on v2.3+)
aether-ctl set wiw_inner 188.114.96.1:2408    # gool inner hop (v1.9+; classic carrier on v2.3+)
aether-ctl set protocol mim                     # MASQUE-in-MASQUE (v2+)
aether-ctl set quic_v2 off                      # disable v2 QUIC opener (v2+)
aether-ctl set ech auto                         # enable ECH discovery (v1.9+)
aether-ctl set tor_mode tunnel                  # Tor through WARP (v2+)
aether-ctl set tor_relays only                  # onionoo relays as bridges (v2.1+)
aether-ctl set psiphon_mode tunnel              # Psiphon through WARP (v2.1+)
aether-ctl set psiphon_region DE                # ask for a DE Psiphon exit (v2.1+)
aether-ctl set exit_loc '!IR,AZ,RU'             # refuse exits in those countries (v2.1+)
aether-ctl set stats 1                          # log traffic totals (v2.1+)
aether-ctl set gool_carrier classic             # classic WARP-in-WARP gool (v2.3+)
aether-ctl set gool_peer 188.114.97.1:2408      # inner endpoint of MASQUE-carried gool (v2.3+)
aether-ctl set command_mode manual               # custom core arguments
aether-ctl set custom_command '--bind 0.0.0.0:1819 --wg'  # space-separated
aether-ctl passwall add-node          # create a socks node pointing at Aether
aether-ctl set upstream_proxy socks5://192.168.1.9:1082
aether-ctl update
aether-ctl change-version v1.5.0 --start
aether-ctl update --version v1.5.0 --start
```

`Enable on Boot` is separate from runtime control:

```sh
aether-ctl set enabled yes   # enable startup after reboot
aether-ctl set enabled no    # disable startup after reboot
aether-ctl start             # start now, regardless of boot setting
aether-ctl stop              # stop now, regardless of boot setting
```

## Install and update

Run the installer as root on the router. It downloads the matching musl
binary, verifies its SHA-256 checksum, stages all support files, preserves
existing configuration by default, refreshes LuCI caches, and restarts the
required web services.

```sh
wget -qO /tmp/aether-install.sh https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main/install.sh
chmod +x /tmp/aether-install.sh
/tmp/aether-install.sh --start
```

The installer lists up to five newest stable core releases from v1.5.0 onward
and defaults to v2.3.0. For automation use `--non-interactive`; add
`--version vX.Y.Z` to choose a valid published release from v1.5.0 onward.
`aether-ctl update` fetches the latest repository updater and runs the same
installer flow; `aether-ctl change-version vX.Y.Z` is the explicit shortcut for
switching core versions. Before starting and before LuCI renders its form, the
client detects the installed core. v1.5 hides and does not pass the v1.6-only
HTTP CONNECT proxy, MASQUE startup deadline, and core log-level options. v1.6
uses the v1.6 capability set, and v1.7 or newer adds upstream proxy chaining
(the `upstream_proxy` option). Updates preserve the UCI configuration and
identities unless `--force-config` is specified.

Fresh installs listen on `0.0.0.0:1819` for LAN clients. Because SOCKS5 has no
authentication, protect the port with firewall rules or change it to
`127.0.0.1:1819` for router-local use.

If the new LuCI page does not appear after an update, sign out and back in,
use `Ctrl+F5`, or open LuCI in an incognito/private window or a different
browser. Browser JavaScript caches can keep the previous page.

## Uninstall

Normal removal keeps configuration and identities:

```sh
wget -qO /tmp/aether-uninstall.sh https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main/uninstall.sh
chmod +x /tmp/aether-uninstall.sh
/tmp/aether-uninstall.sh
```

Use `--purge` only when you also want to delete `/etc/config/aether` and
`/etc/aether`, including registered identities.

## Troubleshooting

- Check service state: `aether-ctl status`.
- Read recent logs: `aether-ctl log 100`.
- Test through the tunnel: `aether-ctl test google.com`.
- Check the exit: `aether-ctl check-ip`; for Tor: `aether-ctl check-tor`.
- If the service is running but traffic fails, wait for the watchdog or use
  `aether-ctl restart`.
- Tor listening on `:1820` but never connecting: look for `problem with
  filesystem permissions` in the log. The service self-repairs `/` and
  `/etc` ownership/modes on Tor-enabled starts; then Tor still needs minutes
  to bootstrap (longer over multi-hop tunnels).
- Manual command mode: the core runs exactly your arguments — a missing
  `--tor` means no Tor even with `tor_mode=tunnel` set, and a pasted binary
  path is stripped, not duplicated. Pasting the full shown command used to
  crash-loop the core (fixed: leading `/usr/bin/aether(-run)` is dropped).
- `aether-ctl test <host>` printing the help page means the installed
  `aether-ctl` predates the `test` dispatch (update the client files); the
  tunnel itself is unaffected — `check-ip` still proves it.
- Deploying the `files/` overlay as root resets `/` and `/etc` to the
  archived mode (Windows tars store `0777`), which re-breaks Tor's
  permission check — restart the service afterwards so the self-repair runs.
- A blank LuCI page with `TypeError: Class must be a descendant of
  CBIAbstractValue` means a cached page referencing a widget your form.js
  lacks — hard-refresh (`Ctrl+F5`).
- If LuCI is stale, use a private window or a fresh browser before reinstalling.
