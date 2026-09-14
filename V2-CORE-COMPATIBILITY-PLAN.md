# Aether Core v2 Compatibility Update Plan

## 1. Purpose and scope

This plan describes how to add compatibility for Aether Core v2 to the
OpenWrt client without breaking existing v1.5-v1.9 installations, UCI
configuration, identity files, LuCI behavior, or the security boundary around
Zero Trust credentials.

The repository already contains the v2 reference documents:

- `2.0.0CORE-DOCS.en.md` — command/environment reference and identity behavior.
- `2.0.0CORE-GUIDE.en.md` — operational behavior and recommended usage.

The current client is capability-gated through v1.6, v1.7, v1.8, and v1.9
helpers. It currently launches one of `masque`, `wg`, or `gool`, stores one
base `config_path`, and passes selected settings as CLI flags from
`files/etc/init.d/aether`.

The supported v2 baseline is **Core `v2.0.0`**. The documented lab router
(`192.168.1.15`) was inspected with that binary: it reports `aether 2.0.0`,
accepts every CLI flag emitted by the existing v1.9 client, and is running the
existing generic `--config /etc/aether/aether.toml` invocation. The v2 help
also confirms `--mim`, `--no-quic-v2`, `--ech`, and the Tor controls.

Implementation must still test every new v2 mode before release. The v2
reference documents and `--help` output do not replace runtime data-plane and
packaging tests.

## 2. v2 changes identified from the project documents

### 2.1 New transport: MASQUE-in-MASQUE

Core v2 adds `--mim`, a MASQUE tunnel inside another MASQUE tunnel. It has:

- `--mim-outer` and `--mim-inner` endpoint overrides.
- `--mim-peers` for both endpoints.
- A secondary identity file derived from the MASQUE config path.
- The same h3/h2 carrier choice on both hops.

This requires a new UCI protocol value and must not be conflated with `gool`.

### 2.2 Protocol-specific identity/config paths

The v2 documents describe:

- `--config` / `AETHER_CONFIG` for the base identity path.
- `--wg-config` / `AETHER_WG_CONFIG` for WireGuard identity.
- `--masque-config` / `AETHER_MASQUE_CONFIG` for MASQUE identity.
- `aether-team-<name>.toml` for team-specific identity files.
- `*-lastconn.toml` endpoint cache files.

The current service passes only `--config` and derives sibling files itself.
That is the intended integration model and Core `2.0.0` accepts it on the lab
router. Do **not** add `wg_config_path` or `masque_config_path` UCI options,
and do not add an identity migration. Revisit this only if a v2 protocol fails
specifically because the generic config path is insufficient.

### 2.3 QUIC v2 opener

Core v2 enables a QUIC v2 opener for HTTP/3 by default and exposes:

- `--no-quic-v2`.
- `AETHER_QUIC_V2=0`.

The client should expose this as an explicit opt-out, not silently force a
value. The default should follow core behavior unless field testing shows a
compatibility problem.

### 2.4 New identity lifecycle behavior

Core v2 checks whether Cloudflare still accepts a saved identity and can
reprovision it. The relevant controls are:

- `AETHER_REPROVISION`.
- Team identity files.
- Owner-readable identity files.

Core v2 already owns reprovisioning. The OpenWrt client must preserve identity
files during update and restart, detect and remove only invalid/empty stubs,
and avoid deleting a valid identity as part of a normal migration. It does
not need a UCI, CLI, or LuCI reprovisioning control; it only needs to avoid
interfering with the core's automatic behavior.

### 2.5 Additional v2 capabilities

The v2 documents also describe these capabilities, which should be evaluated
individually rather than exposed all at once:

- ECH (`--ech`, `AETHER_ECH`).
- In-tunnel DNS (`AETHER_DNS`).
- Routing rules (`--route-block`, `--route-direct`, `--routes`, and related
  environment variables).
- Firewall mark (`--mark`, `AETHER_MARK`).
- Tor modes, bridge configuration, and an additional Tor proxy listener.
- Proxy/resource controls such as max clients, TCP connect timeout, and
  keepalive settings.
- MASQUE h2 keepalive settings and WireGuard stale/endpoint cooldown settings.
- v2-specific protocol validation and reconnect behavior.

Initial scope is deliberately limited:

- **Include:** MIM, a user-selectable QUIC v2 option, ECH for Core v1.9+,
  and Tor capability for Core v2.
- **Exclude:** routing rules, in-tunnel DNS, firewall marks, resource limits,
  and other advanced network controls.

Tor is included because it is an explicit product requirement, but it must be
shown only when the installed/packaged Core v2 build actually supports it and
ships or can locate its required pluggable-transport assets.

## 3. Compatibility policy

### 3.1 Version profiles

Add a `core_supports_v20()` helper in every place that currently has version
capability logic:

- `files/etc/init.d/aether`
- `files/usr/bin/aether-ctl`
- `files/www/luci-static/resources/view/aether.js`
- `files/usr/libexec/rpcd/luci-app-aether` if the legacy handler remains
  supported

Use numeric major/minor comparison, as the existing helpers do. Do not
replace the existing v1.6-v1.9 helpers with a blanket `major > 1` rule until
all v2 flag semantics have been verified.

Use an explicit v2 capability profile for flags whose behavior is new or
changed. Keep the existing “newer versions inherit the latest known profile”
behavior only for flags confirmed unchanged by `--help` and runtime tests.

### 3.2 Minimum supported version and downgrade behavior

Keep v1.5.0 as the minimum supported release. Cores v1.5-v1.9 remain
selectable and retain their current capability behavior. The installer will
default to `v2.0.0` as the final installer step after all v2 implementation
and router tests pass.

For a downgrade from v2 to v1.x:

- Preserve unknown/new UCI options rather than deleting them.
- Do not pass v2-only flags to v1 cores.
- Show stored-but-inactive values in `aether-ctl show` where practical.
- Keep v2 identity files intact; do not rewrite them into an older format.
- Warn that a v1 core may not understand v2-created identity/config files if
  binary testing confirms that risk.

## 4. Proposed UCI model

Keep the existing `config aether 'main'` section and add fields with safe
empty/default values so existing configurations remain valid.

### Required compatibility fields

Use the existing generic `config_path` as the only identity-path setting. Add
only the settings required by the approved feature scope:

- `protocol`: add `mim`, mapped to `--mim` and gated to Core v2.0.0+.
- `mim_outer`, `mim_inner`, and `mim_peers`: MIM-only endpoint overrides,
  mapped to their corresponding flags and gated to Core v2.0.0+.
- `quic_v2`: user selection for Core v2 MASQUE/MIM HTTP/3. Preserve the core
  default when enabled/unset; append `--no-quic-v2` only when disabled.
- `ech`: an optional `auto` or base64 ECH configuration mapped to `--ech`,
  gated to Core v1.9.0+ as requested.
- Tor settings, gated to Core v2 and a Tor-enabled packaged binary: `tor_mode`
  (`off`, `tunnel`, `reverse`, `only`), `tor_bind`, `tor_dir`, bridge policy,
  bridge entries, and transport paths/directories. Secret-bearing bridge data
  must be redacted in CLI output.

Do not add protocol-specific config paths, a reprovision option, DNS, routes,
firewall marks, or resource controls. Every added setting needs defined
serialization, validation, redaction, downgrade behavior, and test coverage.

## 5. Implementation work packages

### WP1 — Establish a v2 compatibility fixture and capability contract

1. Obtain the exact supported v2 release binaries for x86_64, arm64, and
   armv7, or at minimum x86_64 plus one ARM target.
2. Record output from:
   - `aether --version`
   - `aether --help`
   - `aether --masque --help` if supported
   - `aether --wg --help` if supported
3. Build a capability table for every currently emitted flag:
   `--bind`, `--config`, `--masque`, `--wg`, `--gool`, `--scan`, `--noize`,
   `--h2`, `--h2-peer`, `--fragment*`, `--peer`, `--keepalive`, reconnect /
   validation flags, `--startup-secs`, `--log-level`, `--upstream`, `--perf`,
   and `--wiw-*`.
4. Record whether v2 accepts the current identity path layout and whether
   `--config` is still the correct generic option.
5. Add fixture-based shell tests for version parsing, including `v2.0.0`,
   `v2.1.x`, a `v1.9.x` version, and malformed output.

Deliverable: a checked-in compatibility matrix or test fixture that becomes
the source of truth for later code changes.

### WP2 — Refactor version/capability detection

1. Add `core_supports_v20()` to the init script and CLI.
2. Add the equivalent JavaScript helper and legacy RPC helper if needed.
3. Centralize parsing rules conceptually: accept `v2.0.0`, `2.0.0`, and
   version strings with surrounding text; reject empty/malformed output.
4. Add `core_version` failure handling before constructing a service command.
5. Replace user-facing messages that currently imply v1.9 is the newest
   capability profile.

Avoid duplicating v2 feature checks in unrelated branches. A feature should
have one clearly named capability predicate and one documented minimum core
version.

### WP3 — Add protocol-specific service command construction

Update `files/etc/init.d/aether`:

1. Extend the protocol case with `mim`.
2. Keep the existing generic `--config "$config_path"` invocation. Do not
   pass `--wg-config` or `--masque-config` and do not migrate identities unless
   a verified Core v2 failure makes that necessary.
3. Add MIM endpoint flags only for the `mim` protocol.
4. Reuse the MASQUE-only h2, h2 peer, fragmentation, startup, validation,
   reconnect, no-data-check, ECH, and QUIC-v2 behavior for MIM after verifying
   which controls v2 applies to both hops.
5. Append `--no-quic-v2` only for an explicit disabled UCI value and only to a
   Core v2 MASQUE/MIM command.
6. Map `ech` to `--ech` only for Core v1.9+ and MASQUE/MIM. Preserve the core
   default when it is unset.
7. Map the approved Tor UCI options only for Core v2 and only after the build
   capability check passes. Enforce the core's valid mode combinations, in
   particular that `tor-reverse` cannot use WireGuard/gool.
8. Continue sanitizing the existing base, MASQUE sibling, and secondary
   identity paths, but do not add identity migrations or reprovision logic.
9. Log the selected protocol and capability profile without logging secrets,
   full proxy credentials, or private bridge lines.

Important: do not infer that `mim` can reuse the `gool` `wiw_*` fields. Keep
separate UCI fields and validation so an old gool endpoint cannot accidentally
be sent to a MASQUE endpoint.

### WP4 — Update the credential runner and identity handling

Update `files/usr/bin/aether-run` and related service logic:

1. Confirm v2 environment names against the binary/docs. Preserve the current
   `AETHER_TEAM`, `AETHER_ACCESS_CLIENT_ID`, `AETHER_ACCESS_CLIENT_SECRET`,
   `AETHER_ACCESS_TOKEN`, and `AETHER_GATEWAY` exports unless v2 changes them.
2. Add any required v2 environment-only settings, especially reprovisioning,
   without putting secrets in CLI arguments.
3. Derive team identity paths safely from the team name only if core does not
   do so internally. Sanitize the name before using it in a path; never allow
   `/`, `..`, or shell metacharacters to escape `/etc/aether`.
4. Preserve owner-only permissions (`600`) on identity and UCI files.
5. Update recovery cleanup in `aether-watchdog` so it removes only recognized
   `*-lastconn.toml` cache files, not team identities or primary identities.
6. Verify that MIM secondary identity cleanup/provisioning cannot remove the
   outer MASQUE identity.

### WP5 — Extend `aether-ctl`

Update `files/usr/bin/aether-ctl`:

1. Add v2 capability checks and v2-aware `show` output.
2. Extend `set` validation for `protocol mim`, `mim_outer`, `mim_inner`,
   `mim_peers`, QUIC v2, ECH, and the approved Tor options.
3. Gate ECH to Core v1.9.0+ and MIM/QUIC-v2/Tor options to Core v2.0.0+.
4. Reject unsupported options using a precise minimum-core error.
5. Redact Tor bridge lines and any other credential-bearing value.
6. Keep secrets and identity contents out of `show`, status, logs, and error
   messages.
7. Display the detected core version and active capability profile in existing
   `status`/`show` output; no identity migration command is required.
8. Update usage text and the command dispatch list.

While touching this file, avoid introducing new non-POSIX shell behavior and
avoid one-line `local value=$(...)` assignments where exit status matters.

### WP6 — Extend LuCI

Update `files/www/luci-static/resources/view/aether.js`:

1. Add v2 capability detection and display `Core v2 compatibility` status.
2. Add `MASQUE-in-MASQUE` to the protocol list only when core v2 is present;
   otherwise hide or disable it with an explanatory message.
3. Add MIM outer/inner/both endpoint fields and show them only for `mim`.
4. Add a QUIC v2 toggle with help text explaining that disabling it affects
   HTTP/3 only.
5. Add ECH for Core v1.9+ and MASQUE/MIM, with `auto` and validated base64
   values. Do not alter the existing default when the setting is empty.
6. Add Tor controls for Core v2 only after the binary/package support check:
   mode, listener, state directory, bridge policy/entries, and transport
   paths. Explain that Tor bootstrap may be slow and that `tor-only` does not
   establish a WARP tunnel.
7. Add warnings for stored-but-inactive v2 options when a v1 core is installed.
8. Update dynamic option enable/disable logic so:
   - MASQUE and MIM share MASQUE-only controls;
   - WireGuard/gool show WireGuard controls;
   - `wiw_*` fields are limited to gool;
   - `mim_*` fields are limited to mim;
   - Tor-reverse is available only with MASQUE/MIM HTTP/2 as permitted by the
     verified core behavior.
9. Update status log parsing for any v2 log wording changes. Prefer stable
   service/ubus state and explicit CLI output over brittle log regexes.
10. Keep using built-in ubus RPCs (`service.list`, `rc.init`, `uci.get`,
    `file.exec`); do not make the v2 work depend on the legacy rpcd shell
    handler.

### WP7 — Installer, updater, and release policy

Update `install.sh` and `update.sh`:

1. Make `v2.0.0` the installer default as the final implementation step, after
   its router smoke tests pass.
2. Keep v1.5-v1.9 selectable and preserve their exact existing capability
   gates and downgrade behavior.
3. Update help text and minimum/available-release wording.
4. Keep config and identity preservation as the default.
5. Ensure staged config files are `600`, scripts are executable, and the
   installer never creates empty identity TOML files.
6. Add a preflight check that reports the installed core version and warns if
   an existing configuration contains options unsupported by the selected
   release.
7. Validate that release archives retain the existing static-musl asset names
   and contain the expected `aether` binary. For Tor, verify both a
   Tor-enabled Core v2 binary and the required `pt/` assets; do not expose Tor
   controls in LuCI when the selected release cannot support them.
8. Update client version and release notes separately from the core version;
   do not use the same version variable for both.

### WP8 — Documentation and operational migration guide

Update:

- `README.md`
- `README-fa.md`
- `CLIENT-GUIDE.en.md`
- `AGENTS.md`
- `ARCHITECTURE.md`
- `MEMORY.md`
- `TASKS.md`

Document:

- supported core ranges and capability matrix;
- MIM setup and the two-hop identity behavior;
- v2-only settings and downgrade behavior;
- Core-managed identity reprovisioning and the client's non-interference rule;
- QUIC v2 opener and user-selectable opt-out behavior;
- ECH availability on Core v1.9+;
- Tor modes, packaging requirements, and traffic/identity implications;
- excluded v2 features: routing rules, DNS, firewall marks, and resource
  controls;
- exact router deployment and rollback procedure.

Do not document a feature as supported until it has passed the runtime matrix.

## 6. Test plan

### 6.1 Static contract tests

Extend `tests/test-static.sh` to assert:

- v2 version/default strings and `core_supports_v20()` in all relevant files;
- `mim` protocol handling in config, init, CLI, and LuCI;
- `mim_outer`/`mim_inner`/`mim_peers` mappings;
- retained generic `--config` mapping (and no protocol-specific config flags);
- MIM endpoint, QUIC v2 opt-out, and ECH mappings;
- v2-only Tor mappings and exclusion from unsupported builds;
- v1.9 ECH and v2-specific rejection messages on older cores;
- identity sanitization for the existing supported paths;
- secret redaction remains present;
- no legacy custom RPC dependency is introduced.

Static assertions should check contracts, not just the presence of a token.
Where possible, add shell tests that execute functions with mocked `aether`,
`uci`, `procd_*`, and `jsonfilter` commands.

### 6.2 Compatibility matrix

Run at least these combinations:

| Core | Protocol | Expected result |
|---|---|---|
| v1.5.x | masque/wg/gool | Existing v1.5 behavior; no v2 flags. |
| v1.9.x | masque/wg/gool | Existing v1.9 behavior; no MIM. |
| v2.0.x | masque | Existing MASQUE settings and identity path work. |
| v2.0.x | wg | WireGuard identity/config and reconnect work. |
| v2.0.x | gool | Existing `wiw_*` behavior works. |
| v2.0.0 | mim | Both hops, h2/h3, endpoint overrides, and identity files work. |
| v1.9.x | masque | ECH unset and configured behavior works without affecting existing users. |
| v2.0.0 | masque/mim | QUIC v2 default and explicit opt-out behave as intended. |
| v2.0.0 | Tor-enabled build | Each approved Tor mode follows its valid protocol constraints. |
| v2.0.0 | any | Missing, empty, malformed, and valid identity files are handled safely. |

For each case verify service command construction, process state, logs, SOCKS5
traffic, watchdog recovery, and UCI persistence.

### 6.3 Router smoke tests

On the documented lab router:

1. Install v2 without `--force-config`; verify config and identities remain.
2. Start MASQUE, WireGuard, gool, and MIM separately.
3. Run `aether-ctl status`, `show`, `test google.com`, and `check-ip` only
   after the tunnel has opened its SOCKS listener.
4. Verify MIM h3/h2 and automatic/manual endpoint behavior.
5. Verify ECH on Core v1.9+ without a configured value, with `auto`, and with
   a valid explicit configuration.
6. Verify command lines do not contain Zero Trust secrets, proxy passwords, or
   private Tor bridge data.
7. Verify LuCI protocol-dependent fields and compatibility banners.
8. Verify all Tor modes only with a confirmed Tor-enabled v2 build; confirm
   expected proxy listeners and mode/protocol rejection behavior.
9. Simulate repeated data-plane failure and verify watchdog removes only the
   intended last-connection cache and procd restarts the core.
10. Downgrade to v1.9 and verify v2-only flags are omitted and configuration is
    not destroyed.
11. Restore v2 and verify identities/configuration still behave correctly.

## 7. Rollout order

1. **Discovery gate:** validate the actual v2 binary and complete the flag /
   identity matrix.
2. **Compatibility foundation:** version helpers, test fixtures, and static
   contracts.
3. **Safe service support:** retain generic config paths and add v2 command
   construction for MIM, QUIC v2, ECH, and Tor.
4. **CLI support:** validation, redaction, and diagnostics.
5. **LuCI support:** gated MIM, QUIC v2, ECH, and Tor controls.
6. **Runtime verification:** install/update/rollback and all approved protocol
   tests; resolve the current lab-router gool data-plane failure separately.
7. **Documentation/release:** make v2.0.0 the default only after the matrix
   passes.

## 8. Acceptance criteria

The v2 compatibility release is ready when:

- A v2 core starts successfully with preserved existing UCI and identities.
- Existing v1.5-v1.9 cores still start without receiving unsupported v2 flags.
- MIM works with automatic endpoints and explicit outer/inner endpoints.
- MIM and gool use distinct endpoint configuration fields while retaining the
  current generic identity path.
- QUIC v2 behavior follows the documented default and user-selectable opt-out
  semantics.
- ECH works on Core v1.9+ without affecting users who leave it unset.
- Tor is exposed only when its Core v2 binary and required assets are present.
- `aether-ctl` and LuCI never expose Zero Trust secrets, proxy credentials, or
  private Tor bridge data.
- Watchdog recovery does not delete primary, secondary, or team identities.
- `sh tests/test-static.sh` passes, and router smoke tests pass on supported
  architectures.
- Downgrade to the last supported v1 release is reversible without destructive
  config or identity migration.

## 9. Confirmed decisions and remaining verification

### Confirmed decisions

1. Core `v2.0.0` is the compatibility baseline and final installer default.
2. The existing generic `--config` approach remains the only identity path
   model; no protocol-specific UCI paths or migrations will be added unless a
   verified v2 failure requires them.
3. Core owns identity reprovisioning. The client does not need a reprovision
   setting, but must retain its non-destructive identity handling.
4. Preserve every v1.5-v1.9 version gate and keep those releases selectable.
5. Add MIM, user-selectable QUIC v2 behavior, ECH for v1.9+, and Tor for v2.
6. Do not implement routes, DNS, firewall marks, resource controls, or other
   v2 advanced networking controls in this release.
7. The release archive naming/static-musl packaging is expected to match v1.9;
   the installer default changes last.

### Remaining verification

1. Confirm the v2 release archive is Tor-enabled and includes/locates the
   required `pt/` assets on every supported architecture.
2. Run controlled MIM, ECH, QUIC-v2, and Tor data-plane tests before exposing
   the settings.
3. Confirm v2 log wording used by the LuCI status parser.
4. Resolve the current lab-router runtime state before using it as a passing
   smoke-test result: Core `2.0.0` accepts the v1.9 command line, but its
   active gool connection repeatedly fails inner-hop data-plane validation and
   has not opened SOCKS5 port `1819`.
