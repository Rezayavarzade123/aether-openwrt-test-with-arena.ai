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
- **IP Version**: use IPv4 unless the router has working IPv6.
- **Force Peer**: optionally skip scanning and use a known `ip:port`.
- **HTTP/2 Mode** and **H2 Peer** apply only to MASQUE.
- **TLS Fragmentation** applies to MASQUE HTTP/2 when its handshake is blocked.
- **HTTP CONNECT Proxy** optionally exposes the same tunnel for applications
  that do not support SOCKS5.
- **Upstream Proxy** (requires core v1.7+) chains the tunnel behind another
  proxy. Accepts `socks5://[user:pass@]host:port`, `http://host:port`, or a
  bare `host:port` (read as SOCKS5). A SOCKS5 upstream carries every
  transport; an HTTP CONNECT upstream requires HTTP/2 mode. The URL is passed
  to the core via `--upstream`, and credentials are redacted in `aether-ctl show`.
- **MASQUE Startup Deadline** bounds connection and first data validation;
  its default is 30 seconds.
- **Disable Profile Retry** applies to WireGuard/gool and prevents retrying
  alternate noise profiles after a failed scan.

### Reliability settings

- **Keepalive** applies to WireGuard and gool.
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

Core v1.8 introduced a resource profile (`--perf low|medium|high`). The client
exposes it as the **Performance Profile** field in LuCI (Advanced section) and
via `aether-ctl set perf_profile low|medium|high|auto`. When set to **Auto (by
RAM)** — the default — the service picks the profile from total router memory
at every start:

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

Two other v1.8 core features — **routing rules** (`--route-block`,
`--route-direct`) and **TLS key-share groups** (`--tls-groups`) — are
deliberately not exposed by this client: transparent-proxy tools such as
Passwall2 on the same router split traffic better than in-tunnel rules, and
the default TLS groups match modern browsers. In-tunnel DNS and ECH also stay
at their core defaults. The client passes no `--ech` flag either — the core's
own default applies; the core docs only document the explicit `--ech auto`
mode.

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

## CLI

```sh
aether-ctl start
aether-ctl stop
aether-ctl restart
aether-ctl status
aether-ctl show
aether-ctl log 100
aether-ctl test google.com
aether-ctl passwall status            # Passwall2 bridge status
aether-ctl passwall localhost off     # disable Passwall2 router-local proxying
aether-ctl set protocol wg
aether-ctl set perf_profile auto       # or low / medium / high (v1.8+)
aether-ctl set wiw_outer 162.159.192.1:2408   # gool outer hop (v1.9+)
aether-ctl set wiw_inner 188.114.96.1:2408    # gool inner hop (v1.9+)
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
and defaults to v1.7.0. For automation use `--non-interactive`; add
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
- If the service is running but traffic fails, wait for the watchdog or use
  `aether-ctl restart`.
- If LuCI is stale, use a private window or a fresh browser before reinstalling.
