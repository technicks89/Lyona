# Sync Phase 1 — system-management provider decision, contract, and packaging

Upstream: [`#207`](https://github.com/ChrisTitusTech/dwm-titus/pull/207)
(`1cb6392a`), plus the `Commands.qml` plumbing later commits depend on
([`#209`](https://github.com/ChrisTitusTech/dwm-titus/pull/209) `27ab809a`,
[`#265`](https://github.com/ChrisTitusTech/dwm-titus/pull/265) `dd55e585`).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

This is the first of nine phases porting upstream's system-management
subsystem. It lands no user-visible behaviour. It exists because **the
subsystem cannot be ported until one question is answered**, and answering it
in a later phase would mean rewriting whatever came before.

---

## The decision: what language owns `dwm-system-management`

### What upstream actually built (verified at `dd55e58`, 2026-09-07)

`scripts/dwm-system-management` is a **single 8,946-line Python 3 program**
with a `#!/usr/bin/python3` shebang. It has been Python since its first commit
(`bd87fd3c`, `#208`) — there was no "switch to Python"; the earlier
`SYNC-P10-SYSTEM-MANAGEMENT.md` correctly quoted Python from it.

Its module-level imports are **stdlib only**:

```python
import bisect, contextlib, ctypes, errno, fcntl, hashlib, io, os, re, selectors
import shlex, shutil, signal, socket, stat, struct, subprocess, sys, threading, time
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from typing import Callable, Iterable, Iterator, Mapping, Protocol, Sequence
```

Every non-stdlib import is **lazy, inside a function, and guarded**:

| Line | Import | Used by |
| --- | --- | --- |
| `:608` | `gi`, `Gio`, `GLib` | `ServiceRead` — bounded async system-bus reads |
| `:737` | `gi`, `PackageKitGlib` | PackageKit enum vocabulary |
| `:6466` | `gi`, `Gio`, `GLib`, `PackageKitGlib` | `PackageKitBackend` |
| `:6634` | `rpm` | `require_mutation_safe()` — Fedora RPM version gate |
| `:8818` | `gi`, `Gio`, `GLib`, `GLibUnix` | `UpdateEventMonitor` and its subclasses |

There is **no `pydbus`, no `dbus-python`, and no daemon**. D-Bus is reached
through **PyGObject's `Gio`** — the same GLib bus API Quickshell itself links.
The failure mode is already a first-class protocol value:

```python
except (ImportError, ValueError) as error:
    raise SnapshotFailure("missing-provider", "System Python GObject bindings are unavailable",
                          "unavailable") from error
```

The `*-bus.py` / `*-provider.py` files listed in earlier notes
(`system-update-events-bus.py`, `system-regional-mutation-bus.py`,
`system-provider-discovery.py`, `checked-command-provider.py`, …) are **all
under `tests/fixtures/`** — fake buses and stub providers for the test suite,
not shipped code. Likewise every `System*.qml` outside
`config/quickshell/systemmanagement/` lives in `tests/qml/`. The shipped
surface is exactly:

| Shipped file | Lines at `dd55e58` |
| --- | --- |
| `scripts/dwm-system-management` | 8,946 |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | ~1,055 |
| `config/quickshell/systemmanagement/SystemOperationModel.qml` | ~424 |
| `config/quickshell/systemmanagement/SystemOperationProtocol.js` | ~197 |
| `config/quickshell/systemmanagement/SystemProviderDiscovery.qml` | ~198 |
| `config/quickshell/systemmanagement/SystemRegionalPreflightModel.qml` | ~173 |
| `config/quickshell/systemmanagement/SystemRegionalPreflightProtocol.js` | ~153 |
| `config/quickshell/systemmanagement/SystemDiscoveryCycle.js` | ~71 |
| `config/quickshell/systemmanagement/SystemUpdateDiscovery.qml` | 3 |
| `config/quickshell/settings/SystemUpdateControls.qml` | ~215 |
| `config/quickshell/settings/SystemSettingsPane.qml` | ~426 |

Nothing is a resident daemon. Every `watch-*` subcommand is an ordinary child
process of Quickshell's `Process`, writing a tab-separated line protocol on
stdout and terminated with `SIGTERM` when the pane closes.

### The second finding that reframes the whole port

`SYNC-P10-SYSTEM-MANAGEMENT.md` was built on the premise that *"the whole thing
is written against PackageKit on Fedora"* and that the provider layer must be
**replaced entirely** by a `PacmanBackend`. That premise is wrong.

Verified this session against the live package databases:

| Package | Repository | Version | Relevance |
| --- | --- | --- | --- |
| `packagekit` | `extra` (and `cachyos-extra-v3`) | 1.3.6-1 | Depends on `pacman` and `libalpm.so=16-64` |
| `libpackagekit-glib` | `extra` | — | ships `usr/lib/girepository-1.0/PackageKitGlib-1.0.typelib` |
| `python-gobject` | `extra` | 3.56.3-1 | `gi.repository.Gio` / `GLib` |
| `python` | `core` | 3.14.7-1 | — |
| `pacman-contrib` | `extra` | 1.13.1-1 | `checkupdates(8)`, if a native backend is ever wanted |
| `arch-audit` | `extra` | 0.2.0-5 | CVE severity, if wanted |
| `accountsservice` | `extra` | 26.27.3-1 | `org.freedesktop.Accounts` |
| `cups` | `extra` | 2.x | `cups.service` / `cups.socket` |
| `system-config-printer` | `extra` | 1.5.18-7 | delegated printer tool |

Arch's `packagekit` package file list contains
`usr/lib/packagekit-backend/libpk_backend_alpm.so` and
`etc/PackageKit/alpm.d/{pacman.conf,repos.list,groups.list}`. **PackageKit on
Arch is a first-class alpm frontend, not a Fedora artefact.** The `#207`–`#241`
update half is therefore a *port*, not a rewrite — the D-Bus interface
(`org.freedesktop.PackageKit`) is identical.

The genuinely Fedora-specific code is much smaller than the old plan assumed:

- `read_fedora_identity()` (`:5851`) — rejects any `/etc/os-release` whose `ID`
  is not `fedora`.
- `require_mutation_safe()` (`:6630`) — imports `rpm`, queries the RPM database
  for the installed PackageKit NEVR, and requires ≥ 1.3.5 (or Fedora 44's
  `1.3.4-3.fc44` backport) via `rpm.labelCompare`.
- `packagekit_security_floor()` (`:5826`) — the RPM-ordering comparison above.
- `DELEGATED_TOOLS` (`:45`) — `lxqt-admin-user`, `system-config-printer`,
  `dnfdragora`.
- `0fa2ef41` (`#232`) — a DNF5-specific install-preview correction.

Everything else — the journal, the snapshot codec, the operation protocol,
`timedate1`/`locale1`/`Accounts`/`systemd1` reads, the event monitors — is
distro-neutral.

### The three options

**Option A — adopt the Python helper.** Port `scripts/dwm-system-management`
largely as-is. Add `python` (core) and `python-gobject` (extra) to a new
`arch:system-management` profile alongside `packagekit`. Replace
`read_fedora_identity()` with an Arch/CachyOS identity read, and replace the
RPM-database version gate with the daemon's own D-Bus
`VersionMajor/Minor/Micro` properties (Arch ships 1.3.6, already above the
1.3.5 floor, so no distro-package query is needed at all).

*Cost:* two new required packages; a second helper language and a second test
idiom in a tree that is otherwise POSIX shell plus `tests/lib.sh`.
*Benefit:* upstream diffs stay applicable; the hard parts arrive already
written and already tested.

**Option B — rewrite in POSIX shell.** Match the `dwm-settings-*` convention:
`pacman`/`checkupdates` for updates, `timedatectl`/`localectl`/`busctl` for
regional state, `loginctl` for sessions, `tests/lib.sh` for tests.

*Cost:* this is not 200 lines of D-Bus glue. It is a reimplementation of a
program whose hardest components are exactly the ones shell is worst at — a
length-prefixed frame codec with atomic double-buffered commit, an fd-chain
directory validator that refuses symlinks and group-writable components at
every level, `flock`-based ownership leases with liveness probing, and bounded
*asynchronous* D-Bus reads with per-call deadlines and remote-error
classification. Lyona's largest existing shell helper is
`scripts/dwm-settings-wallpaper` at 2,432 lines. Subscribing to D-Bus signals
from shell means parsing `busctl monitor`'s free-form output, which is *less*
auditable than a typed `Gio` subscription, not more. And every future upstream
change to this subsystem must be re-derived by hand.
*Benefit:* one language, one test idiom, zero new runtime packages.

**Option C — stop at read-only, in shell.** Phases 2–4 (the read-only update
snapshot, the Settings pane, and live discovery) need **no D-Bus at all** if
they are backed by `checkupdates` and `pacman` instead of PackageKit. Deliver
those three phases in shell, do not port the journal or any mutation, and
leave installation to a terminal or to `lyona-update`
([`P6-UPDATE-HELPER.md`](P6-UPDATE-HELPER.md)).

*Cost:* Settings can report updates but never apply them; Phases 5–9 are
dropped, including timezone/locale/account/printer surfaces.
*Benefit:* smallest possible surface, no new packages, no new language, no
root path, no journal.

### Recommendation

**Option A, with Option C as the documented fallback if the dependency is
refused.**

The reasoning, in order of weight:

1. **The dependency is cheap and verifiable.** `python` is in `core`,
   `python-gobject` and `packagekit` in `extra`. None is AUR-only — unlike
   `xkbset`, whose AUR-only status `SYNC-P7-XKB-INPUT.md` got wrong and which
   had to ship as `arch:desktop-optional`. All three were confirmed this
   session with `pacman -Si` and the Arch package file listing.
2. **Precedent already exists, narrowly.** `scripts/pkg-scan.py` is a Python 3
   script already listed in `Makefile` `INSTALL_COMMANDS` (line 80). What is
   new is *depending* on Python at runtime — `python` appears in no
   `dwm-packages.sh` profile and in no `archiso/packages.x86_64` entry today.
   That is an honest new dependency, but a small and explicit one.
3. **Option B's risk is concentrated in the safety-critical code.** The journal
   exists to make a crash mid-transaction recoverable. A shell reimplementation
   of atomic frame commit and descriptor-chain validation is the most likely
   place in this entire port to introduce a defect that only appears after a
   power loss. Porting reviewed, tested Python is materially safer than
   re-deriving it in shell.
4. **Convention cost is bounded and one-directional.** It is one helper and one
   test file. It does not change how any other provider works, and Lyona's
   existing tab-separated helper protocol
   ([`SETTINGS-PLATFORM.md`](SETTINGS-PLATFORM.md) "Helper Protocol") already
   describes the exact record shape this helper emits.

**This remains a decision for the project owner, not a settled fact.** It adds
a runtime language to a distribution that has deliberately been one language
plus QML. Record the answer in this document's "Decision" line below before
Phase 2 starts; every later phase's shape depends on it.

```text
Decision: ____________________   Date: __________   Recorded by: __________
```

If Option B is chosen, Phases 5–7 must be rescoped before they are started —
their line estimates assume a port, not a reimplementation. If Option C is
chosen, Phases 5–9 are closed as declined and this document records why.

---

## Files

Everything below assumes Option A. Marked `(A)` items disappear under Option C.

| File | Change |
| --- | --- |
| `docs/P6-SYSTEM-MANAGEMENT.md` | **New.** Lyona's Arch contract, adapted from upstream's 2,492-line Fedora one |
| `scripts/dwm-packages.sh` | New `arch:system-management` / `arch:system-management-optional` profiles |
| `install.sh` | Install the new profile with the recommended set |
| `archiso/packages.x86_64` | Same packages on the live medium |
| `scripts/check-deps.sh` | Report the new packages |
| `tests/test-arch-packages.sh` | Assert the new profiles |
| `config/quickshell/core/Commands.qml` | `systemManagementCommand()`, `terminatingCheckedCommand()` |
| `scripts/dwm-settings-provider` | Replace the placeholder `system administration` record |
| `docs/SETTINGS-CAPABILITIES.md` | Row for the new operations; `unsupported` is a status, not a class |
| `Makefile` | `INSTALL_COMMANDS`, `check-system-management`, `check-quickshell-system-management` |

---

## 1. The contract document

Upstream's `docs/P6-SYSTEM-MANAGEMENT.md` is 2,492 lines and is *the* reason
the journal has the shape it does. Write Lyona's before writing any code, and
carry these sections over with Arch substitutions:

- **Provider Protocol** (`:905`) — carry the record grammar verbatim. It is
  append-only and already compatible with Lyona's tab-separated helper
  protocol:

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

- **The protocol-minor staging table.** This is the mechanism that lets each
  phase below ship a *truthful complete* snapshot rather than a half-populated
  one, and it maps one-to-one onto this project's phases:

| Minor | Providers | States | Actions | Lists | Lyona phase |
| --- | --- | --- | --- | --- | --- |
| `0` | `updates`, `recovery` | `update-summary`, `update-last-refresh`, `update-restart` | `updates-refresh`, `updates-install-all`, `updates-cancel` | `update`, `package-change` | Phases 2–7 |
| `1` | `regional`, `accounts`, `printers`, `sources` | `timezone`, `ntp-enabled`, `ntp-synchronized`, `locale`, `accounts-count`, `cups-service` | `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`, `password-open`, `printers-open`, `sources-open` | `account`, `repository` | Phases 8–9 |
| `2` | `information`, `storage`, `security`, `diagnostics` | filesystem/SELinux/secure-boot/firewall/encryption/lock states | `health-open` | `filesystem` | **Not implemented upstream.** Out of scope |

  A producer emits the highest minor whose *entire* active set it implements,
  and never advertises a later planned ID as `unsupported`.

- **Authorization and Recovery Rules** (`:2297`) and **Operation Lifecycle and
  Audit** (`:1305`) — carry the rules; rewrite the interface list.

Arch substitutions for the "Selected Fedora Interfaces" section (`:45`):

| Upstream | Lyona |
| --- | --- |
| PackageKit over the DNF backend | PackageKit over `libpk_backend_alpm.so` (`packagekit`, `extra`) |
| RPM database version gate | `org.freedesktop.PackageKit` `VersionMajor/Minor/Micro` ≥ (1, 3, 5) |
| `/etc/os-release` `ID=fedora` | `ID=arch` or `ID_LIKE` containing `arch` (covers CachyOS) |
| `dnfdragora` (software sources) | *No Arch equivalent ships a repository editor.* See §5 |
| `lxqt-admin-user` (accounts) | Same package name is not in Arch `extra`; see §5 |
| `system-config-printer` (printers) | `system-config-printer`, `extra` — unchanged |

Also carry over, unchanged, the two principles that survive from
`SYNC-P10-SYSTEM-MANAGEMENT.md` because they are correct and hard-won:

- **Delegate, don't reimplement.** `accounts-open` / `printers-open` /
  `sources-open` / `password-open` launch an existing trusted privileged tool.
  They do not rebuild account, printer, or repository administration inside
  `dwm-system-management`. This is privilege minimisation, not a shortcut.
- **Never fabricate a terminal state.** An ambiguous post-dispatch result is
  `interrupted` — never success, never cancellation. See
  [`SYNC-P9-REGIONAL-MUTATION.md`](SYNC-P9-REGIONAL-MUTATION.md), where this
  becomes a named contract exception.

## 2. Package profiles

`scripts/dwm-packages.sh`. Upstream's `fedora:system-management` pulls
`PackageKit PackageKit-glib python3-gobject python3-rpm accountsservice cups
system-config-printer`, with `lxqt-admin dnfdragora` optional. The Arch
equivalents, all verified present in `extra` this session:

```diff
 	arch:desktop-optional)
```
```diff
+	arch:system-management)
+		# PackageKit on Arch is a first-class alpm frontend: the `packagekit`
+		# package depends on `pacman` and `libalpm.so` and ships
+		# `usr/lib/packagekit-backend/libpk_backend_alpm.so`. python-gobject
+		# supplies gi.repository.Gio/GLib and the PackageKitGlib typelib comes
+		# from libpackagekit-glib, which `packagekit` already depends on.
+		printf '%s\n' \
+			python python-gobject packagekit accountsservice cups
+		;;
+	arch:system-management-optional)
+		# Delegated administration targets. Each one missing disables only its
+		# own `*-open` action; readable state is unaffected.
+		# arch-audit adds CVE severity that the alpm sync database does not
+		# carry; it needs the network and does not cover CachyOS packages.
+		printf '%s\n' \
+			system-config-printer arch-audit
+		;;
```
```diff
 	arch:recommended)
 		dwm_packages "$family" desktop
+		dwm_packages "$family" system-management
 		dwm_packages "$family" screenshot-optional
```
```diff
 	arch:optional)
 		dwm_packages "$family" theme-optional
 		dwm_packages "$family" desktop-optional
+		dwm_packages "$family" system-management-optional
 		;;
```

`install.sh`, matching upstream's `#207` hunk against Lyona's line 758:

```diff
 if install_recommended_profile; then
 	info "Installing recommended desktop dependencies..."
 	dwm_install_package_profile desktop
+	dwm_install_package_profile system-management
```

Mirror the required half into `archiso/packages.x86_64`, add the new names to
`scripts/check-deps.sh`, and assert both profiles in
`tests/test-arch-packages.sh`.

> **`python3-rpm` has no Arch counterpart and must not be sought.** Its only
> use upstream is `require_mutation_safe()`'s NEVR comparison. Phase 6 replaces
> that with the daemon's own D-Bus version properties.

## 3. `Commands.qml`

Two additive functions. Lyona's existing `checkedCommand()` is byte-identical
to upstream's and must not change.

```diff
     function checkedCommand(command) {
 
         const script = 'output=$("$@"); status=$?; [ "$status" -eq 0 ] || exit "$status"; printf "%s\\n" "$output"';
         return ["sh", "-c", script, "dwm-checked-command"].concat(command);
     }
 
+    function terminatingCheckedCommand(command) {
+        // Preserve checkedCommand's success gate while forwarding surface-close
+        // signals to a long-running helper instead of orphaning it.
+        const script = [
+            'runtime_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}',
+            'output_file=',
+            'error_file=',
+            'child=',
+            'terminate_requested=0',
+            'cleanup() { status=$?; trap - EXIT; rm -f -- "$output_file" "$error_file"; exit "$status"; }',
+            'terminate() { terminate_requested=1; if [ -n "$child" ]; then trap - HUP INT TERM; kill -TERM "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; exit 143; fi; }',
+            'trap cleanup EXIT',
+            'trap terminate HUP INT TERM',
+            'output_file=$(mktemp "$runtime_dir/dwm-checked-command.XXXXXX") || exit 1',
+            '[ "$terminate_requested" -eq 0 ] || exit 143',
+            'error_file=$(mktemp "$runtime_dir/dwm-checked-command-error.XXXXXX") || exit 1',
+            '[ "$terminate_requested" -eq 0 ] || exit 143',
+            'file_limit=$(ulimit -f)',
+            'if [ "$file_limit" = unlimited ] || [ "$file_limit" -gt 16384 ]; then ulimit -f 16384 || exit 1; fi',
+            '[ "$terminate_requested" -eq 0 ] || exit 143',
+            '"$@" >"$output_file" 2>"$error_file" &',
+            'child=$!',
+            '[ "$terminate_requested" -eq 0 ] || terminate',
+            'wait "$child"',
+            'status=$?',
+            'child=',
+            'head -c 512 "$error_file" >&2 || :',
+            '[ "$status" -eq 0 ] || exit "$status"',
+            'cat "$output_file"'
+        ].join("\n");
+        return ["sh", "-c", script, "dwm-terminating-checked-command"].concat(command);
+    }
```

The interleaving above is not cosmetic. `dd55e585` (`#265`) moved both
`mktemp` calls *after* `trap terminate` and added a `terminate_requested`
re-check after each blocking step, because a `SIGTERM` arriving between the
first `mktemp` and the trap installation left the temporary file behind. Port
the corrected ordering, not the original.

```diff
+    function systemManagementCommand(action, args) {
+        return helperCommand("dwm-system-management", action, args, true);
+    }
+
     function settingsProviderCommand(action, args) {
         return helperCommand("dwm-settings-provider", action, args, true);
     }
```

## 4. Capability records

`scripts/dwm-settings-provider` already emits a `system` section — Lyona has
had `{ "id": "system", "label": "System", "description": "Health and
administration" }` in `SettingsModel.qml:108` since before this port began,
rendered through `SettingsWindow.qml`'s generic capability-list fallback. Its
third record is a placeholder:

```diff
-	emit_capability system administration 'Advanced administration' unsupported delegated arch-tools \
-		'High-risk administration remains delegated to trusted tools'
+	if provider_available dwm-system-management; then
+		emit_capability system updates 'System updates' available read-only dwm-system-management \
+			'Update discovery is available; installation requires explicit confirmation'
+	else
+		emit_capability system updates 'System updates' unavailable read-only dwm-system-management \
+			'Install the dwm-system-management helper'
+	fi
+	emit_capability system administration 'Advanced administration' unsupported delegated arch-tools \
+		'High-risk administration remains delegated to trusted tools'
 }
```

Keep the existing `system health` and `system authorization` records unchanged
— they belong to `dwm-system-health` and polkit, not to this subsystem.

`docs/SETTINGS-CAPABILITIES.md` needs a row in its operations table (owner
`dwm-system-management`, class read-only plus one confirmed privileged step)
and one correction upstream made in `#207` that applies to Lyona verbatim:
**`unsupported` is a capability status, not an operation class.** Remove it
from the class table, and state that a planned-but-unimplemented provider is
*omitted* from records by selecting the highest fully implemented protocol
minor — never advertised as `unsupported`.

## 5. Delegated tool targets — settle before Phase 9

Upstream's `DELEGATED_TOOLS` (`dwm-system-management:45`) hard-codes absolute
paths:

```python
DELEGATED_TOOLS = {
    "accounts-open": ("/usr/bin/lxqt-admin-user", "User accounts"),
    "printers-open": ("/usr/bin/system-config-printer", "Printers"),
    "sources-open": ("/usr/bin/dnfdragora", "Software sources"),
}
```

Only `system-config-printer` exists in Arch `extra` under the same name.
Lyona must choose Arch targets for the other two, or emit them permanently
`unavailable` with an honest detail string. The paths are validated by
`trusted_delegated_executable()` (`:1840`), which requires a non-symlinked,
root-owned, non-group/other-writable file outside user-writable paths — so
whatever is chosen must satisfy that, and an AUR package installed into
`/usr/bin` by `makepkg` does satisfy it.

Phase 9 cannot be written until this is decided. It is listed as open decision
**D-3** in [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#open-decisions).

## 6. Makefile registration

A Python helper does **not** enter `check-shell` or `check-format` — shellcheck
and shfmt do not read it. The "three places" rule in
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#global-adaptation-rules) therefore reads
differently here: `INSTALL_COMMANDS` plus a Python gate.

```diff
 	scripts/dwm-system-health \
+	scripts/dwm-system-management \
 	scripts/dwm-polkit \
```

```diff
 check-system-health:
 	tests/test-system-health.sh
 
+check-system-management:
+	/usr/bin/python3 tests/test-system-management.py
+
+check-quickshell-system-management: all
+	tests/test-quickshell-system-management.sh
+	status=0; tests/test-quickshell-system-management-xvfb.sh || status=$$?; \
+		if [ "$$status" -eq 77 ]; then exit 0; fi; \
+		exit "$$status"
+
 check-settings:
```

Add both to the `check:` recipe after `check-system-health`, and to `.PHONY`.
Upstream runs the Python suite through the interpreter directly rather than
relying on the shebang; keep that, and keep `scripts/run-tests` as the wrapper
in Lyona's own verification commands.

---

## Verification

```bash
scripts/run-tests make check-shell           # unchanged helpers still pass
scripts/run-tests make check-format
scripts/run-tests make check-quickshell-qml  # Commands.qml additions
scripts/run-tests make check-arch-packages   # new profiles
scripts/run-tests make check-install         # INSTALL_COMMANDS round-trip
scripts/run-tests make check-settings        # new system capability record
```

Manual, on a real CachyOS install, before Phase 2 starts:

```bash
pacman -Si packagekit | grep -E 'Repository|Depends'   # expect libalpm.so
sudo pacman -S --needed packagekit python-gobject
systemctl status packagekit                            # dbus-activated, idle
busctl --system introspect org.freedesktop.PackageKit /org/freedesktop/PackageKit \
  | grep -E 'VersionM'                                 # expect ≥ 1.3.5
python3 -c "import gi; gi.require_version('PackageKitGlib','1.0'); \
  from gi.repository import PackageKitGlib; print('ok')"
```

If the last two fail, **stop** — Option A's premise is broken and the decision
above must be revisited before any code is written.

## Closes

Opens `TASKS.md`'s Phase 6 `SYSTEM-001` group (which does not exist yet —
Phase 5 is still active; see
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#position-in-the-sequence)). Nothing in
this phase can be committed while `TASKS.md`'s active phase is Phase 5.
