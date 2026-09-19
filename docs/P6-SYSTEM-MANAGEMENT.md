# System Management Contract

<!-- markdownlint-disable MD013 -->

Date: 2026-09-08

Lyona's own contract for the upstream-ported system-management subsystem
(`scripts/dwm-system-management`), adapted from upstream's real
`docs/P6-SYSTEM-MANAGEMENT.md` at `dd55e58` (2,492 lines, Fedora-scoped) for
Arch/CachyOS, per
[Sync Phase 1's decision](SYNC-P1-SYSTEM-PROVIDER-DECISION.md): **Option A —
adopt the upstream Python helper**, with Arch substitutions for the
Fedora-specific fraction of it. Index:
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#the-system-management-port).

This document establishes the contract before any of it is implemented — the
same ordering upstream itself used, and the same reason: the journal, the
protocol grammar, and the confirmation model all depend on decisions made
here, and rewriting them mid-port costs more than deciding once. It is
deliberately not a line-by-line reproduction of upstream's document.
Upstream's own text runs to hundreds of lines per subsystem describing exact
D-Bus retry counts, byte budgets, and private-fixture catalogs — that level
of detail belongs to the Sync Phase document that actually implements each
piece (`SYNC-P2` through `SYNC-P9`), not to this contract, which exists to
fix the shape everything else is built against.

## Scope and Ownership

The system-management port adds bounded Arch package-update and regional
(timezone/NTP/locale/accounts/printers/sources) management without making
Quickshell an administration shell. Settings and all QML remain unprivileged.
Each operation has one fixed owner, and system policy and authorization stay
with the systemd/D-Bus service or trusted tool that already owns them —
never with a project-invented privileged path.

The implementation boundaries, mapped onto this project's own phase numbers
(not upstream's — see [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#the-system-management-port)
for the full dependency table):

1. PackageKit-backed Arch update status and transactions — `SYNC-P2` through
   `SYNC-P7`.
2. Regional state plus trusted account, printer, and software-source entry
   points — `SYNC-P8` and `SYNC-P9`.
3. System information, storage, and security status — **not implemented
   upstream either**; see the protocol-minor table below. Out of scope for
   this port.

No operation in this port expands the project-owned privileged helper
allowlist (`PRIVILEGED_HELPERS` in `Makefile`, currently
`dwm-settings-display-root` and `lyona-update-root`). An operation that
cannot satisfy Lyona's existing privilege contract — a fixed, allowlisted,
polkit-authenticated helper reached through `pkexec`/`sudo` — stays
delegated to an existing trusted tool or is reported `unsupported`.

## Capability and Mutation Inventory

| Capability | Read owner | Mutation owner | Class | Cancellation and denial | Status |
| --- | --- | --- | --- | --- | --- |
| Update status and available packages | PackageKit system D-Bus API over the Arch alpm backend (`libpk_backend_alpm.so`) | PackageKit `UpdatePackages` with the fixed `ONLY_TRUSTED` transaction flag and PackageKit's own polkit policy | Read-only and delegated | Mutation requires PackageKit >= 1.3.5 (Arch ships 1.3.6, already above the floor — no distro-package version query needed). Blocked updates stay visible but are excluded from installation. The transaction's `AllowCancel` property is authoritative; cancel is offered only while true. Authorization denial ends the operation without hiding the last readable snapshot. | Planned |
| Package metadata refresh | PackageKit transaction | PackageKit `RefreshCache` transaction | Delegated | Starts only from an explicit Refresh action. PackageKit owns cancellation and repository/network errors. | Planned |
| Update interruption and history | PackageKit active transaction list, transaction signals, and transaction history | None | Read-only | An operation journal identifies incomplete local operations; PackageKit remains the source of truth for transaction completion. | Planned |
| Date, timezone, and NTP | `org.freedesktop.timedate1` properties | `SetTimezone` and `SetNTP`, interactive authorization | Read-only and delegated | A pending confirmation can be canceled before the D-Bus call; a sent one cannot. Denial preserves properties and reports no change. Manual clock setting is not exposed. | Planned |
| System locale | `org.freedesktop.locale1` properties | `SetLocale`, interactive authorization | Read-only and delegated | Same cancellation/denial shape as timezone. Success includes new-login guidance. Keyboard layout stays owned by Input Settings, not this subsystem. | Planned |
| User accounts | `org.freedesktop.Accounts` object and user properties | Delegated tool — **Arch target open, see D-3** | Read-only and delegated | Settings never accepts usernames, passwords, group names, or arbitrary account commands. Missing tools leave the account summary readable. The current user's own password change opens `passwd` in the configured terminal, transporting nothing through QML. | Planned, D-3 open |
| Printers | `cups.service`/`cups.socket` systemd unit state | `system-config-printer` (Arch `extra`, unchanged from upstream) | Read-only and delegated | The trusted tool and CUPS own discovery, authentication, cancellation, and device policy. Missing CUPS or tool state is capability-scoped. | Planned |
| Software sources | PackageKit repository records (`GetRepoList`) | Delegated tool — **Arch target open, see D-3** | Read-only and delegated | Settings does not accept repository identifiers for mutation; the delegated tool owns confirmation and authorization. | Planned, D-3 open |
| System identity and resources | `/etc/os-release`, `uname(2)`, `org.freedesktop.hostname1`, `/proc/cpuinfo`, `/proc/meminfo`, `findmnt --json` | None | Read-only | Not implemented upstream (see the protocol-minor table). Out of scope for this port. | Out of scope |
| Storage overview | Existing `dwm-system-health` snapshot | Existing fixed user/installed-helper repairs | Read-only, user-session, privileged | Already shipped; this port reuses it rather than duplicating it. | Reuse, unchanged |
| Privacy and security status | Fixed kernel/D-Bus/file sources | Trusted tools or documented recovery guidance | Read-only and delegated | Not implemented upstream. Out of scope. | Out of scope |
| Diagnostics and recovery | Existing `dwm-system-health`/`dwm-diagnostics` | Existing fixed repairs and exported evidence | Read-only, user-session, privileged | Already shipped; reused, not duplicated. | Reuse, unchanged |
| Advanced storage, firewall policy, general services, encryption setup, factory reset | No narrow provider | Trusted external administration | Delegated | No generic elevation, command runner, device path, service name, or arbitrary file path crosses QML — same rule Lyona already applies everywhere else. | Explicitly excluded |

## Selected Arch Interfaces

Verified against Arch's live package databases during Sync Phase 1 (see
[that document's package table](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#the-second-finding-that-reframes-the-whole-port)
for the exact versions/repos): `packagekit`, `python-gobject`, `python`,
`accountsservice`, `cups`, and `system-config-printer` are all in Arch's
official `core`/`extra` repositories — none AUR-only.

### Package updates

PackageKit is the update owner, reached through PyGObject's `Gio` D-Bus
binding rather than by parsing `pacman`/`checkupdates` text. Discovery always
calls `SetHints` with `background=true`, `interactive=false`,
`cache-age=4294967295` before `GetUpdates(NONE)` — the maximum unsigned cache
age tells PackageKit to reuse existing metadata rather than treat passive
discovery as a user-requested refresh. `RefreshCache(force=true)` runs only
from the explicit Refresh action.

Before offering an install, a separate unjournaled `SIMULATE|ONLY_TRUSTED`
transaction resolves the exact dependency set for the currently discovered
installable updates and produces a SHA-256 "generation" over that resolved
set. The confirmation shows this preview and captures the generation;
accepting it re-runs discovery and the simulation, recomputes the
generation, and only proceeds to the real `UpdatePackages(ONLY_TRUSTED, ...)`
if the generation still matches — otherwise it fails closed as
`conflict` and asks for fresh confirmation. PackageKit exposes no
prepare/commit token that can bind a completed simulation to a later
mutating transaction, so this is a freshness guard against the common case
(nothing changed underneath), not an atomic frozen plan; the confirmation UI
must say so.

The command grammar (fixed, no other options or trailing arguments):

```text
dwm-system-management snapshot
dwm-system-management watch-updates
dwm-system-management watch-operation OPERATION_ID
dwm-system-management ack-operation OPERATION_ID
dwm-system-management updates-refresh
dwm-system-management updates-install-all GENERATION
dwm-system-management updates-cancel OPERATION_ID
```

`GENERATION` is the exact 64-character lowercase-hex value emitted with the
confirmed snapshot — an opaque, provider-generated freshness token, never a
package ID or caller-chosen value. `OPERATION_ID` is `op-` followed by 32
lowercase hex digits, generated under an exclusive journal lock using the
kernel CSPRNG. A cancel request is honored only while the exact matching
transaction's `AllowCancel` is currently `true`; a stale, unknown, terminal,
or non-cancelable ID is a command-level rejection (exit 3, no operation
stream), never a silent no-op.

The whole update-discovery-through-install path has a bounded aggregate
deadline (120 seconds for the discovery/simulate path, matching a
`Cancel`-then-five-second-grace-then-detach sequence on timeout) — nothing
here waits indefinitely on PackageKit.

**Deliberate exclusions from the ported snapshot layer** (Sync Phase 2,
`docs/SYNC-P2-UPDATE-SNAPSHOT.md`):

- **DNF5 install-preview preservation.** Upstream's `#232` widens
  `normalize_plan()`'s requested/represented reconciliation so a DNF5
  `SIMULATE` that reports an install action (not just an upgrade action) for
  a new dependency is still accepted. Whether `libpk_backend_alpm.so` ever
  does the same is unverified — there is no live PackageKit daemon available
  to check against yet. Left unported; the snapshot layer keeps the stricter
  pre-`#232` reconciliation (every requested package ID must resolve to
  exactly one `update` action) until this is confirmed on a real install.
  A `SIMULATE` plan the alpm backend represents differently will surface as
  a `malformed`/`"PackageKit returned an incomplete update plan"` error
  rather than silently mis-porting DNF5-specific behavior.
- **Security severity is always `unknown`.** The alpm sync databases carry no
  CVE/security classification, so every `update` record's severity field
  reads `unknown` — this is accurate, not a gap. `arch-audit` (shipped as
  `arch:system-management-optional`) could add this later behind its own
  capability, but it needs the network, must never block this bounded
  snapshot, and does not cover CachyOS's own packages — out of scope here.
- **Restart-requirement heuristic (an addition, not an exclusion).** Whether
  the alpm backend populates PackageKit's `RequireRestart` signal at all is
  unverified for the same reason. Rather than silently reporting `none`
  whenever the backend stays silent — which would tell a user it is safe to
  skip a reboot after a kernel or glibc update — `dwm-system-management`
  falls back to a name-based heuristic over the pending update set
  (`linux`/`linux-*`/`linux-cachyos*`, `systemd`, `glibc`, `dbus` → the
  existing `system` restart value; anything else → `unknown`, never a
  fabricated `none`) whenever a transaction succeeds with pending updates but
  zero `RequireRestart` signals were seen.

### Regional state (timezone, NTP, locale)

`org.freedesktop.timedate1` and `org.freedesktop.locale1` are the stable
systemd D-Bus owners, unchanged from upstream — these are core systemd
interfaces, not distro-specific. Settings reads their properties directly
and calls only the fixed `SetTimezone`, `SetNTP`, or `SetLocale` methods
after a visible confirmation, with interactive authorization enabled so
systemd/polkit own the decision. No arbitrary environment variable, keymap,
NTP server, RTC mode, or manual timestamp is accepted.

Command grammar:

```text
dwm-system-management timezone-set ZONE GENERATION
dwm-system-management ntp-set enabled|disabled GENERATION
dwm-system-management locale-set LANG=LOCALE GENERATION
dwm-system-management accounts-open
dwm-system-management password-open
dwm-system-management printers-open
dwm-system-management sources-open
```

Each mutation uses a 60-second monotonic aggregate deadline starting
immediately before the D-Bus call and covering the reply plus a verification
read; an ambiguous post-dispatch failure durably terminalizes as
`interrupted`, never a fabricated success or fabricated failure. `ZONE` must
exactly match a value from `timedate1.ListTimezones`; `LOCALE` must exactly
match a name from a bounded `locale -a` enumeration, since `locale1` exposes
no enumeration method of its own. Locale mutation preserves every existing
`LANGUAGE`/`LC_*` override it can validate and only replaces `LANG` —
`locale1` merges omitted keys itself and applies its own fallback policy
(see the systemd reference below), so the provider's job is validating and
re-reading, not constructing a full replacement array.

`GENERATION` here is a separate SHA-256 freshness token over the specific
regional action, its argument, and the current source state at preflight
time — same purpose as the update generation, same "revalidate immediately
before the real call" rule, same fail-closed-as-`conflict` behavior on
mismatch.

### Accounts, printers, and sources

`org.freedesktop.Accounts` (`ListCachedUsers` plus a bounded
`FindUserById(os.getuid())` lookup) is the read owner for account rows;
account creation, deletion, group membership, and administrator changes stay
in a delegated tool — Arch's target is **open, see D-3** below. The current
user's own password change opens `passwd` in the user's configured terminal
(`dwm-terminal --print-command`'s existing selection contract), never
transporting a password through QML or the provider.

`cups.service`/`cups.socket` systemd unit state is the printer read owner;
`system-config-printer` (Arch `extra`, package name unchanged from upstream)
is the delegated mutation tool.

PackageKit's `GetRepoList(NONE)` is the software-sources read owner;
mutation stays with a delegated tool — Arch's target is **open, see D-3**.

Every delegated launch (`accounts-open`, `printers-open`, `sources-open`,
`password-open`) resolves a fixed, allowlisted executable path, requires that
path and every parent directory to be root-owned and not group/other-writable
(the same `trusted_file`/`trusted_parent_chain` shape Lyona's own privileged
helpers already use — see `scripts/lyona-update-root`), and execs it directly
with no shell interpreting the argv. **Delegate, don't reimplement**: these
actions launch an existing trusted privileged tool; they do not rebuild
account, printer, or repository administration inside
`dwm-system-management`. This is privilege minimization, not a shortcut, and
carries over from upstream unchanged.

### System information, storage, and security

Every source below is a fixed, bounded, read-only probe; none starts a
service, holds a lock, or polls. Each source degrades independently —
a missing or malformed one never invalidates its peers — and reports one of
five statuses: `available` (a known value), `partial` (accessible but
incomplete or malformed evidence), `restricted` (read denied), `unavailable`
(an expected command/service could not be reached), or `unsupported` (the
capability or its platform source does not exist). Every status other than
`available` carries value `unknown`.

Information (`INFORMATION_LOCAL_IDS`/`HARDWARE_INFORMATION_FIELDS`,
`scripts/dwm-system-management`):

- `os-name`/`os-version` — `/etc/os-release`'s `PRETTY_NAME`/`VERSION_ID`,
  capped at 64 KiB. `os-version` falls back to `BUILD_ID` only when
  `VERSION_ID` itself is not available (missing or malformed), never
  overriding a real value — Arch/CachyOS omit `VERSION_ID` entirely and set
  `BUILD_ID=rolling`, so this is the only place the port diverges from
  upstream's own field selection (verified against this sandbox's real
  `/etc/os-release`).
- `kernel-release`/`architecture` — `os.uname()`. `hardware-vendor`/
  `hardware-model` — `org.freedesktop.hostname1`'s `HardwareVendor`/
  `HardwareModel` properties, one ten-second aggregate deadline for both.
- `cpu-model` — `/proc/cpuinfo`'s first `model name` field, capped at 4 MiB.
  `logical-cpus` — `os.cpu_count()`.
- `memory-total-bytes`/`memory-available-bytes`/`swap-total-bytes`/
  `swap-free-bytes` — `/proc/meminfo`'s `MemTotal`/`MemAvailable`/
  `SwapTotal`/`SwapFree`, capped at 1 MiB, each a checked `kB`→bytes
  conversion. `uptime-seconds` — `clock_gettime(CLOCK_BOOTTIME)`.

Storage (`FilesystemInformation`, `read_filesystem_information()`): bounded
`findmnt --json --bytes --real --uniq --output ID,SOURCE,TARGET,FSTYPE,SIZE,USED,AVAIL`
in its own process group, a three-second deadline, a 384 KiB output cap, and
at most 256 unique mount-ID records (`--uniq` collapses an over-mounted
target to one row; the kernel mount ID is the record key). `filesystem-summary`
is always exactly one state: `available` carries the emitted row count,
`partial`/`unknown` accompanies a usable subset, anything else carries no
rows. `watch-mounts` ([S2-04](SYNC-SPRINT-2-SYSTEM-INFORMATION.md#s2-04-mount-change-monitor))
is the separate live-invalidation source; the reader above never polls.

Security (`INFORMATION_SECURITY_IDS`, `read_selinux_status()`/
`read_secure_boot_status()`/`read_firewall_status(kind)`/
`read_root_encryption()`/`read_screen_lock()`):

- `selinux` — the single-byte `/sys/fs/selinux/enforce` kernel interface when
  present (`1` enforcing, `0` permissive); otherwise the allowlisted
  `SELINUX` key in `/etc/selinux/config` (64 KiB cap), where only the literal
  value `disabled` is trusted — `enforcing`/`permissive` without the runtime
  interface is inconsistent and reported `partial`, never guessed. Absent
  everywhere is `unsupported` (verified against this sandbox: `unsupported`,
  no `selinux` package installed).
- `secure-boot` — only the EFI global variable
  `/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c`;
  never a directory enumeration. The one-byte payload after the attributes
  prefix must be `0`/`1`. No EFI variables filesystem is `unsupported`
  (verified: this sandbox's real EFI variable read as `available`/`disabled`).
- `firewalld`/`ufw`/`nftables` — **D-5** (decided 2026-09-16): upstream only
  ever asks about `firewalld.service`; a default Arch/CachyOS install runs
  none of the three real, distinct firewall managers a package might ship, so
  this port generalizes to `FirewallUnitRead`/`FIREWALL_UNITS`/
  `read_firewall_status(kind)` over all three, each its own independent
  `ActiveState` read on `org.freedesktop.systemd1`, an absent unit reporting
  `unsupported` rather than assuming firewalld is the only possibility.
  Verified against this sandbox: firewalld/ufw `unsupported` (not installed),
  nftables `available`/`disabled` (installed, inactive). This state describes
  only the named service, never firewall rule content, and never implies the
  other two managers are absent.
- `root-encryption` — bounded `lsblk --json` (`NAME,TYPE,FSTYPE,MOUNTPOINTS,PKNAME`),
  same process-group/three-second-deadline/384 KiB-cap shape as `findmnt`,
  at most 1024 unique block-device records. A root mount with `crypt`/
  `crypto_LUKS` ancestry is `encrypted`; a fully resolved ancestry without
  either is `unencrypted`; incomplete or inconsistent topology is `partial`,
  never guessed either way. Verified against this sandbox's real block-device
  topology: `available`/`unencrypted`.
- `screen-lock` — reuses `dwm-quickshell-controlcenter power-lock-snapshot`
  ([`POWER-PROTOCOL.md`](POWER-PROTOCOL.md), [S2-03](SYNC-SPRINT-2-SYSTEM-INFORMATION.md#s2-03-automatic-screen-lock-evidence)),
  never a second locker or GSettings probe. Lyona additionally autostarts
  `dwm-lock-watch` alongside `light-locker`; `configured_lock_running()`
  recognizes either as "running" evidence when `power_lock_managed=1`.
  `available`/`enabled` requires both `ENABLED=yes` and `RUNNING=yes`;
  `ENABLED=yes` with `RUNNING=no` (configured but not actually running) is
  `partial`, not a false `enabled`.

### Not implemented upstream — out of scope (superseded, see below)

This section described upstream's state as surveyed before Sync Sprint 2:
upstream's own document listed "System Information and Filesystems" and
"Security Status" sections (`os-release`/`uname`/`hostname1`/`/proc`
identity data; SELinux/Secure Boot/firewalld/root-encryption/screen-lock
status), but the protocol-minor table below showed these were never actually
shipped at that time.

**That has since changed.** Upstream did ship this scope (`#277`–`#288`),
and [Sync Sprint 2](SYNC-SPRINT-2-SYSTEM-INFORMATION.md) is porting it —
S2-01 through S2-06 (readers: local/hardware/filesystem information,
SELinux, Secure Boot, firewall status extended to `ufw`/`nftables` per D-5,
root encryption, automatic screen-lock evidence reused from the shared power
helper, and a bounded `watch-mounts` mount-change monitor) are done as of
this note. `watch-mounts` supervises one fixed `findmnt --poll` child with a
pidfd and a signal-wakeup pipe alongside its output, so no idle timer remains
once the baseline `/proc/PID/fd` probe confirms the child's own `mountinfo`
descriptor is open; it requires write-only pipe output (as Quickshell
supplies) so losing its reader is itself an event.

S2-05 wires all of this into the snapshot protocol as minor `2`:
`InformationSnapshotSources`/`build_information_snapshot()` on the Python
side, and the new `config/quickshell/systemmanagement/SystemInformationProtocol.js`
plus matching `SystemManagementModel.qml`/`SystemProviderDiscovery.qml`
changes on the QML side (two new discovery domains, `storage` and
`security`, join the existing four). `snapshot`/`snapshot-core`/
`snapshot-without-storage` are now three distinct fixed CLI commands: a
required (recovery-only) read always asks for `snapshot-core` (minor `1`,
no information block, since it must not open the filesystem inventory's
unmonitored initialization gap or falsely mark storage/security as freshly
re-verified when it didn't actually probe them); an optional read asks for
`snapshot-without-storage` until the `storage` domain's own `watch-mounts`
subscription is actually ready, then `snapshot` (minor `2`, complete).

S2-06 gives minor `2` its visible surface: the new
`config/quickshell/settings/SystemInformationControls.qml` card in System
Settings' System pane (system information, storage overview, privacy/
security status, and diagnostics/recovery guidance), plus Health navigation
(`SystemManagementModel.openHealth()`, wired through `shell.qml`'s
`healthModel`/`targetScreen`/`onHealthOpened`) that opens the existing
`dwm-system-health` full-screen window on the Settings window's own current
screen and closes Settings on the way there. See "Information and recovery
view qualification" below. S2-07 still closes this `ROADMAP.md` Phase 6 item
and this document's own remaining open questions.

## Provider Protocol

`dwm-system-management` owns one append-only, tab-separated protocol,
already compatible with Lyona's existing helper-protocol convention (see
[`SETTINGS-PLATFORM.md`](SETTINGS-PLATFORM.md)'s "Helper Protocol" section).
Starts at minor version `0`; the record field order becomes append-only once
the first implementation boundary (`SYNC-P2`) lands.

```text
system-management-protocol<TAB>1<TAB>0
snapshot-generation<TAB>lowercase-sha256
provider<TAB>id<TAB>status<TAB>class<TAB>owner<TAB>detail
state<TAB>id<TAB>status<TAB>value<TAB>detail
update<TAB>package-id<TAB>severity<TAB>installable|blocked<TAB>name<TAB>version<TAB>summary
package-change<TAB>package-id<TAB>install|update|remove|obsolete|reinstall|downgrade<TAB>name<TAB>version<TAB>summary
repository<TAB>id<TAB>enabled|disabled<TAB>description
account<TAB>object-path<TAB>current|other<TAB>display-name<TAB>login-name
filesystem<TAB>mount-id<TAB>status<TAB>source<TAB>target<TAB>fstype<TAB>size-bytes<TAB>used-bytes<TAB>available-bytes<TAB>detail
action<TAB>id<TAB>available|unavailable<TAB>class<TAB>owner<TAB>label<TAB>detail
active-operation<TAB>id<TAB>action-id<TAB>kind<TAB>state<TAB>percent<TAB>cancelable<TAB>detail
terminal-handoff<TAB>id<TAB>action-id<TAB>kind
operation<TAB>id<TAB>action-id<TAB>kind<TAB>state<TAB>percent<TAB>cancelable<TAB>detail
audit<TAB>id<TAB>action-id<TAB>kind<TAB>result<TAB>started<TAB>finished<TAB>detail
error<TAB>capability<TAB>code<TAB>detail
complete<TAB>snapshot|operation
```

`filesystem` mirrors upstream's grammar exactly; minor `2` (S2-05) emits it
for each mounted real filesystem the bounded, one-shot `findmnt --json`
reader (`read_filesystem_information()`) observes at snapshot time.
`watch-mounts` (`findmnt --poll`, [S2-04](SYNC-SPRINT-2-SYSTEM-INFORMATION.md#s2-04-mount-change-monitor))
is the separate live-invalidation source that triggers a fresh snapshot; it
never supplies filesystem rows itself — see "Not implemented upstream" above.

The protocol minor selects a cumulative active-ID set so each Sync Phase can
produce a *truthful complete* snapshot rather than a half-populated one — a
producer emits the highest minor whose entire active set it implements, and
never advertises a later planned ID as `unsupported`:

| Minor | Providers | States | Actions | Lists | Lyona phase |
| --- | --- | --- | --- | --- | --- |
| `0` | `updates`, `recovery` | `update-summary`, `update-last-refresh`, `update-restart` | `updates-refresh`, `updates-install-all`, `updates-cancel` | `update`, `package-change` | `SYNC-P2` through `SYNC-P7` |
| `1` | `regional`, `accounts`, `printers`, `sources` | `timezone`, `ntp-enabled`, `ntp-synchronized`, `locale`, `accounts-count`, `cups-service` | `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`, `password-open`, `printers-open`, `sources-open` | `account`, `repository` | `SYNC-P8` and `SYNC-P9` |
| `2` | `information`, `storage`, `security`, `diagnostics` | filesystem-summary/SELinux/secure-boot/firewalld/ufw/nftables/encryption/lock states | `health-open` | `filesystem` | `SYNC-SPRINT-2` (readers ported S2-01–S2-04; wired into the snapshot and QML consumer at S2-05; visible Settings card and Health navigation at S2-06) |

The `recovery` provider is intentionally status-only from minor `0`: it owns
journal-integrity errors that have no trustworthy operation kind of their
own, exposing no section, state, list, or action. Removing it would leave a
malformed-journal error with no valid protocol owner to report it under.

## Operation Lifecycle and Audit

The core rules every mutating action follows, carried over from upstream
because they are correct independent of distro:

- Every mutation begins from a visible confirmation naming owner, impact,
  authorization requirement, cancellation limit, and recovery behavior.
- Passive discovery never mutates. The only transaction discovery may create
  beyond the required read-only `GetUpdates` call is the unjournaled
  `SIMULATE|ONLY_TRUSTED` preview described above.
- A confirmed mutation revalidates its captured generation immediately
  before the real call and fails closed as `conflict` on mismatch, rather
  than trusting a preview that may be stale by the time the user accepts it.
- A completed update reports restart guidance sourced from PackageKit's own
  restart data. It never initiates a reboot itself — the existing confirmed
  session-action model (`Commands.qml`'s `sessionActionCommand`) owns that,
  unchanged by this port.
- **Never fabricate a terminal state.** An ambiguous post-dispatch result
  (deadline expired after the mutating call was sent, before verification
  could complete) is `interrupted` — never success, never cancellation. This
  becomes a named contract exception in
  [`SYNC-P9-REGIONAL-MUTATION.md`](SYNC-P9-REGIONAL-MUTATION.md), where it
  matters most (there is no `pacman.log`-equivalent for a `timedate1` call to
  fall back on).

The journal that makes crash-mid-transaction recovery possible, and the
exact D-Bus retry/timeout/byte-budget parameters for each subsystem, are
each Sync Phase's own concern — `SYNC-P5-OPERATION-JOURNAL.md` for the
journal itself, and each of `SYNC-P2` through `SYNC-P9` for their own
subsystem's exact bounds. This document fixes the shape; it does not
pre-specify every deadline.

## Authorization and Recovery Rules

- PackageKit, systemd, AccountsService, CUPS, and delegated tools keep their
  own polkit or authentication policy. QML is never elevated, and this port
  adds nothing to `PRIVILEGED_HELPERS`.
- An authorization denial is `permission-denied`, not `unavailable`, and
  keeps the last validated read-only state visible.
- Network, metadata, repository, dependency, package, and signature failures
  remain distinct typed errors with the owning provider named.
- High-risk storage, firewall, service, encryption, account, and repository
  *mutation* operations remain delegated or unsupported until a separate
  specification defines a narrow interface — this port does not attempt
  them.

## Validation and Rollback

Every implementation boundary in this port must cover valid, malformed,
missing-provider, authorization-denied, canceled, interrupted, overlapping,
and failed states for whatever it adds — matching the class of coverage
`tests/lib.sh`'s `assert_*` idiom already expects from every other Lyona
helper, and matching upstream's own much more exhaustive fixture catalog in
spirit if not in literal line count. Each Sync Phase document
(`SYNC-P2` through `SYNC-P9`) specifies its own exact test scenarios; they
are not repeated here.

Rollback for this contract document itself is deleting it and its package
profile/`INSTALL_COMMANDS` entries together — it does not retroactively
remove packages an image or the recommended installer already installed.
Each later phase's own rollback removes its provider, model, and pane
together, without touching the existing `dwm-system-health`/session-action
contracts this port reuses rather than duplicates.

## Settings Information Card and Health Navigation

[Sync Sprint 2 S2-06](SYNC-SPRINT-2-SYSTEM-INFORMATION.md#s2-06-settings-information-card-and-health-navigation)
gives minor `2` its visible surface:
`config/quickshell/settings/SystemInformationControls.qml` renders the
thirteen system-information values, bounded mounted-filesystem usage (a
virtualized 240-pixel-tall list, so a full 256-row inventory never expands
the pane itself), and the seven security indicators (D-5's `firewalld`/
`ufw`/`nftables` split, plus `selinux`/`secure-boot`/`root-encryption`/
`screen-lock`) minor `2` supplies. Byte counters keep their exact decimal
string alongside an approximate human unit; a value that never reads
(`unknown`, or a non-`available` status) always renders "Unknown", never a
guessed state. A retained (stale) filesystem list is labeled explicitly,
with Reload status as the retry path.

The fixed "Open System Health" button reads `health-open`'s own availability
and calls `SystemManagementModel.openHealth()`, which opens the existing
`dwm-system-health` full-screen window
([`SPEC.md` §5.9](../SPEC.md)) and closes Settings — `shell.qml` wires
`healthModel`/`onHealthOpened` for this and resolves `targetScreen` through
a three-way fallback (the Settings window's own current screen, then a
requested screen, then the active panel's screen), so Health always opens on
the screen Settings was actually showing on, including after the window
moved. Reset guidance names `lyona-update rollback` (Lyona-managed
configuration) and `arch-chroot` from the Lyona installation media (system
rescue) in place of upstream's Fedora-specific tooling; System Health owns
its own listed, separately confirmed repairs and `pacman -Qkk` verifies
installed package files. No factory reset, disk, firewall, encryption, or
general service mutation is introduced.

Verified: `tests/qml/SystemInformationUi.qml` (run at 640×480, 780×580, and
1000×740 by `tests/test-quickshell-information-ui-xvfb.sh`) covers the exact
uint64 display, the 256-row virtualized inventory, unavailable/unknown
security state with readable independent peers (including that firewalld/
ufw/nftables read independently per D-5), explicit stale-data labeling,
keyboard-focus reveal, one fixed health callback, and disabled navigation
when the capability is absent. `tests/qml/SystemHealthNavigation.qml`
(`tests/test-quickshell-health-navigation-xvfb.sh`) exercises the real
`targetScreen` fallback expression extracted programmatically from
`shell.qml`, so this test cannot silently drift out of sync with the actual
production binding.

## Authoritative Interface References

- PackageKit D-Bus API: <https://packagekit.freedesktop.org/gtk-doc/api-reference.html>
- PackageKit transaction API: <https://packagekit.freedesktop.org/gtk-doc/Transaction.html>
- systemd timedate1 API: <https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.timedate1.html>
- systemd locale1 API: <https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.locale1.html>
- systemd manager implementation (GetUnit, ListUnitsByNames, Subscribe): <https://github.com/systemd/systemd/blob/v259/src/core/dbus-manager.c>
- Gio private connection lifecycle: <https://docs.gtk.org/gio/method.DBusConnection.close.html>
- AccountsService manager D-Bus XML: <https://gitlab.freedesktop.org/accountsservice/accountsservice/-/raw/main/data/org.freedesktop.Accounts.xml>
- AccountsService user D-Bus XML: <https://gitlab.freedesktop.org/accountsservice/accountsservice/-/raw/main/data/org.freedesktop.Accounts.User.xml>
- CUPS administration guidance: <https://openprinting.github.io/cups/doc/admin.html>

## Open decisions

Two decisions from [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#open-decisions):

- **D-3** — Arch delegated-tool targets for `accounts-open` and
  `sources-open`. Neither `lxqt-admin-user` nor `dnfdragora` exists in
  Arch's official repositories; `system-config-printer` (`printers-open`)
  does and needs no substitute. **Decided (2026-09-15):** both ship
  permanent `unsupported` (`delegated_command()` in
  `scripts/dwm-system-management`); the Settings UI implementing this —
  `SystemDelegateControls.qml`'s confirmed launch surface — is
  [Sync Sprint 1 S1-04](SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md#s1-04-confirmed-delegated-administration).
- **D-4** — whether a read-only `pacman -Sup --dbpath`-style query genuinely
  stays lock-free/root-free on a live CachyOS install. Not relevant to the
  shipped PackageKit read path directly; recorded here only because it was
  raised alongside this decision. **Still open** — see
  [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#open-decisions).
