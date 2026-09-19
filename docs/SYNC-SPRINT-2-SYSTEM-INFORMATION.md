# Sync Sprint 2 — system information, storage, security status, recovery guidance

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Upstream surveyed at `d4c6d89`.
Depends on [Sprint 1](SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md). `#286`/`b19fb90`
extend the `SystemProviderDiscovery.qml` and `SystemNativeDiscovery` shapes
that S1-03 introduces, so **do not start this sprint on a tree without S1-03**.

**Goal:** the remaining `ROADMAP.md` Phase 6 outcome, *"System information,
storage overview, privacy/security status, diagnostics, recovery actions, and
reset guidance"*. After this sprint, Phase 6 can be closed.

Upstream built this as one reader family in `scripts/dwm-system-management`
(+1,109 helper lines) plus one Settings card. None of it exists in Lyona:
`SystemInformationProtocol.js`, `SystemInformationControls.qml`,
`InformationSnapshotSources` and `watch_mount_events` are all absent.

| Item | Upstream | Size (code + tests) |
| --- | --- | --- |
| [S2-01](#s2-01-local-hardware-and-filesystem-readers) | `#277` `d6f028f`, `#278` `30dc7fb`, `#279` `95ca81a` | ~+1,140 |
| [S2-02](#s2-02-security-status-readers) | `#280` `b40c832`, `#281` `8e4ad74`, plus new `ufw`/`nftables` readers (D-5) | ~+1,050 |
| [S2-03](#s2-03-automatic-screen-lock-evidence) | `92c4543`, `76d0739`, `2fe6f7d` (`#282`) | ~+370 |
| [S2-04](#s2-04-mount-change-monitor) | `5b246a0`, `dbbfde1`, `994011f`, `088069b`, `6ac6f5a` (`#284`) | ~+490 |
| [S2-05](#s2-05-information-snapshot-records-and-lifecycle) | `7954c54` (`#285`), `177e3c3` (`#286`), `b19fb90`, `3232932`, `4aee614` | ~+1,100 |
| [S2-06](#s2-06-settings-information-card-and-health-navigation) | `cc96efd` (`#287`), `0c9d07c`, `39ce924` | ~+440 |
| [S2-07](#s2-07-close-roadmapmd-phase-6) | `aedc962`, `7bc9897`, `c76a124`, `c67db36`, `5237ad9`, `fc5eeda` (`#288`, docs) | docs only |

Order is strict: S2-01 → S2-02 → S2-03 → S2-04 → S2-05 → S2-06 → S2-07. Each
item's records are consumed by the next.

---

## Porting method

The helper half applies as patch-then-fix, the same way as Sprint 1 S1-07.
Lyona's `scripts/dwm-system-management` is still upstream plus Lyona
adaptations:

```bash
U=~/src/dwm-titus
for c in d6f028f 30dc7fb 95ca81a b40c832 8e4ad74 92c4543 76d0739 2fe6f7d \
         5b246a0 dbbfde1 994011f 088069b 6ac6f5a 7954c54 177e3c3 b19fb90 3232932 4aee614; do
  echo "== $c"
  git -C "$U" show "$c" -- scripts/dwm-system-management tests/test-system-management.py tests/fixtures \
    | git apply --3way || { echo "resolve $c by hand"; break; }
  scripts/run-tests /usr/bin/python3 tests/test-system-management.py || break
done
```

The QML half (`SystemManagementModel.qml`, `SystemProviderDiscovery.qml`) uses
Sprint 1's **rebase** method: start from upstream's file at the boundary SHA,
then re-apply Lyona adaptations. Upstream `tests/qml/*.qml` harnesses become
`tests/qml/tst_*.qml`.

**Commit shape:** merge commits `3f962b7`, `abe0d97`, `d56cd1d`, `df3df24`
and the others in this range carry no content of their own. Port the
`--no-merges` commits listed above and nothing else.

---

## S2-01: Local, hardware, and filesystem readers

| Upstream | Adds (all distro-neutral) |
| --- | --- |
| `#277` | `InformationState`, `information_unknown/_text/_number/_fields`; `parse_os_information` (`/etc/os-release`), `parse_memory_information` (`/proc/meminfo`), `parse_cpu_information` (`/proc/cpuinfo`); `read_local_information` |
| `#278` | `HardwareRead` over `org.freedesktop.hostname1` (`HardwareVendor`, `HardwareModel`, `Chassis`, firmware); fixture `system-hardware-read-bus.py` (110) |
| `#279` | `FilesystemRow`, `FilesystemInformation`, `parse_filesystem_information` from bounded `findmnt --json`; fixture `system-filesystem-process.py` (30) |

**Lyona adaptations**

- `parse_os_information` must not reuse `read_fedora_identity()`. Lyona's
  helper already routes identity through its Arch substitute (Sync Phase 1).
  Assert that `ID=arch` and `ID=cachyos` (with `ID_LIKE=arch`) both render a
  name and version, and that an Arch rolling release with **no**
  `VERSION_ID` renders `rolling`, not `unknown`:

  ```diff
  +    def test_arch_os_release_without_version_id_is_rolling(self) -> None:
  +        state = parse_os_information(b'PRETTY_NAME="Arch Linux"\nID=arch\nBUILD_ID=rolling\n')
  +        self.assertEqual(state["os-version"].value, "rolling")
  ```

  Upstream maps only `PRETTY_NAME` → `os-name` and `VERSION_ID` →
  `os-version`, so Arch gets `unknown`. Add the fallback in
  `parse_os_information`:

  ```diff
  -    return information_fields(data, {"PRETTY_NAME": "os-name", "VERSION_ID": "os-version"}, "=", decode)
  +    fields = information_fields(data, {"PRETTY_NAME": "os-name", "VERSION_ID": "os-version",
  +                                       "BUILD_ID": "os-build"}, "=", decode)
  +    # Arch and CachyOS are rolling: no VERSION_ID, BUILD_ID=rolling.
  +    if fields["os-version"].status != "available" and fields["os-build"].status == "available":
  +        fields["os-version"] = fields["os-build"]
  +    del fields["os-build"]
  +    return fields
  ```

  Check `information_fields()`'s return type in the ported code first. If it
  isn't a mutable dict of `InformationState`, adapt the fallback to it rather
  than the other way round.
- `hostname1` needs `systemd-hostnamed`. It's socket-activated on Arch, so no
  package change.
- Btrfs subvolume mounts (the CachyOS default) show the same `SOURCE` many
  times with `[/@home]`-style suffixes. Add a fixture row for that and assert
  capacity is counted once per device.

---

## S2-02: Security status readers

| Upstream | Adds |
| --- | --- |
| `#280` | `read_security_bytes`, `read_selinux_status`, `read_secure_boot_status` (`/sys/firmware/efi/efivars/SecureBoot-*`), `FirewalldRead` / `read_firewalld_status` (`org.fedoraproject.FirewallD1`); fixture `system-firewalld-read-bus.py` (90) |
| `#281` | `parse_storage_json` / `read_storage_information` (bounded `lsblk --json`), `parse_root_encryption` / `read_root_encryption` (dm-crypt/LUKS above `/`); fixture `system-encryption-process.py` (23) |

`INFORMATION_SECURITY_IDS = ("selinux", "secure-boot", "firewalld", "root-encryption", "screen-lock")`.

### Decision D-5: Arch security providers — decided, asked of the user directly

Upstream is Fedora-shaped here, and Arch differs by default:

| Reader | Upstream behavior when absent | On a default Arch/CachyOS install |
| --- | --- | --- |
| SELinux | No `/sys/fs/selinux` and no `/etc/selinux/config` → `unsupported` | `unsupported`. **Correct as-is.** |
| Secure Boot | Reads efivars; legacy BIOS → `unsupported` | Works unchanged |
| firewalld | Unit absent → `unsupported`; present but not answering → `unavailable` | CachyOS/Arch default is **no firewall**; users pick `ufw`, `firewalld` or raw `nftables` |
| Root encryption | `lsblk` crypt ancestry | Works unchanged (Lyona's installer supports LUKS) |

**Decided (2026-09-16), asked of the user directly: port `FirewalldRead`
unchanged, and add new `ufw`/`nftables` readers using the same mechanism**,
so the security card shows real status for whichever firewall manager the
user actually picked, rather than only firewalld — which a default Arch or
CachyOS install typically doesn't run. This is new scope beyond upstream,
not a straight port.

**Mechanism.** `FirewalldRead` doesn't touch the firewall's rule engine at
all — it asks `systemd1` for `firewalld.service`'s `ActiveState` via
`ListUnitsByNames`, without activating the unit (`SnapshotFailure`'s
`"org.freedesktop.systemd1.NoSuchUnit"` branch distinguishes "not installed"
from "installed but down"). `ufw.service` and `nftables.service` are real,
distinct systemd units on Arch (both `ufw` and `nftables` packages ship
one), so the identical mechanism applies — generalize `FirewalldRead` into
one parametrized reader rather than duplicating it three times:

```diff
-class FirewalldRead(ServiceRead):
-    """Read the ActiveState field of one fixed unit without activating it."""
-
-    label = "Firewalld status"
+FIREWALL_UNITS = {
+    "firewalld": ("firewalld.service", "Firewalld"),
+    "ufw": ("ufw.service", "ufw"),
+    "nftables": ("nftables.service", "nftables"),
+}
+
+
+class FirewallUnitRead(ServiceRead):
+    """Read the ActiveState field of one fixed firewall unit without activating it."""
+
+    def __init__(self, kind, Gio=None, GLib=None):
+        if not isinstance(kind, str) or kind not in FIREWALL_UNITS:
+            raise SnapshotFailure("malformed", "Unknown firewall unit read")
+        self.kind = kind
+        self.unit, self.name = FIREWALL_UNITS[kind]
+        self.label = f"{self.name} status"
+        super().__init__(Gio, GLib)
 …
     def connected(self, _source, result, _data):
         if not self.pending():
             return
         try:
             self.connection = self.Gio.bus_get_finish(result)
             self.connection.set_exit_on_close(False)
             if self.pending():
                 self.connection.call(SYSTEMD_NAME, SYSTEMD_PATH, SYSTEMD_MANAGER, "ListUnitsByNames",
-                    self.GLib.Variant("(as)", (["firewalld.service"],)), self.GLib.VariantType.new(UNIT_REPLY_TYPE),
+                    self.GLib.Variant("(as)", ([self.unit],)), self.GLib.VariantType.new(UNIT_REPLY_TYPE),
                     self.Gio.DBusCallFlags.NO_AUTO_START, max(1, int((self.deadline - time.monotonic()) * 1000)),
                     self.cancellable, self.replied, None)
 …
             unit = decode_unit_state(connection.call_finish(result))
             if unit.load == "not-found":
                 if (unit.active, unit.sub) != ("inactive", "dead"):
-                    raise SnapshotFailure("malformed", "Firewalld absence state is inconsistent")
-                state = InformationState("unsupported", "unknown", "Firewalld unit is absent", "missing-provider")
+                    raise SnapshotFailure("malformed", f"{self.name} absence state is inconsistent")
+                state = InformationState("unsupported", "unknown", f"{self.name} is not installed", "missing-provider")
             elif unit.active in ("active", "inactive"):
                 state = InformationState("available", "enabled" if unit.active == "active" else "disabled",
-                    "Firewalld service only; other firewall rules and managers are not assessed")
+                    f"{self.name} service only; rules content and other firewall managers are not assessed")
             else:
-                state = InformationState("partial", "unknown", "Firewalld service is failed or transitioning", "internal")
+                state = InformationState("partial", "unknown", f"{self.name} service is failed or transitioning", "internal")
 …
                 if self.Gio.dbus_error_get_remote_error(error) == "org.freedesktop.systemd1.NoSuchUnit":
-                    self.fail(SnapshotFailure("missing-provider", "Firewalld unit is absent", "unsupported"))
+                    self.fail(SnapshotFailure("missing-provider", f"{self.name} is not installed", "unsupported"))
+
+
+def read_firewall_status(kind: str) -> InformationState:
+    try:
+        return run_interruptible_read(FirewallUnitRead(kind))
+    except SnapshotFailure as error:
+        state = information_unknown(error)
+        return replace(state, status="unavailable") if state.status == "restricted" else state
```

Register the two new ids and wire them into the snapshot, next to the
existing `firewalld` entry:

```diff
-INFORMATION_SECURITY_IDS = ("selinux", "secure-boot", "firewalld", "root-encryption", "screen-lock")
+INFORMATION_SECURITY_IDS = ("selinux", "secure-boot", "firewalld", "ufw", "nftables", "root-encryption", "screen-lock")
 …
-            "firewalld": read_firewalld_status, "root-encryption": read_root_encryption,
+            "firewalld": lambda: read_firewall_status("firewalld"),
+            "ufw": lambda: read_firewall_status("ufw"), "nftables": lambda: read_firewall_status("nftables"),
+            "root-encryption": read_root_encryption,
```

**Card behavior.** All three rows render even when only one firewall manager
is installed — the other two read `unsupported`/"not installed", exactly
like every other optional capability in Settings, not hidden entirely (a
user with none installed sees three honest "not installed" rows, which is
still useful signal that no firewall is configured at all). Extend
`SystemInformationControls.qml` (S2-06) with a short label per row
("firewalld", "ufw", "nftables") instead of the single upstream "Firewall"
row.

**Tests.** Duplicate `FirewalldReadTests` from the ported
`tests/test-system-management.py` into a parametrized
`FirewallUnitReadTests` covering all three kinds against
`system-firewalld-read-bus.py` (rename to `system-firewall-read-bus.py` if
the fixture's bus setup is reused across kinds — check whether the fixture
hardcodes `firewalld.service` before renaming it).

---

## S2-03: Automatic screen-lock evidence

Upstream `92c4543` + `76d0739` + `2fe6f7d` (merged as `#282`).

| File | Upstream change | Lyona target |
| --- | --- | --- |
| `scripts/dwm-quickshell-controlcenter` | New `power-lock-snapshot` command, `power_lock_record()`, `bounded_foreground` so nested `timeout` stays in the reader's process group; `configured_light_locker_running()` scoped by `DISPLAY` | Same file. **Lyona's power block differs** (`power_lock_managed`, `power_lock_after`, and `dwm-lock-watch` started from `autostart.sh:540`) |
| `scripts/dwm-system-management` | `read_screen_lock()` → `read_information_process("screen-lock")`; `parse_screen_lock` | Applies |
| `config/quickshell/power/PowerModel.qml`, `settings/PowerSettingsPane.qml` | Unverified lock state shows `unknown`, never `off` | Same files |
| `docs/POWER-PROTOCOL.md` | `power-lock` record semantics | Same file |
| `tests/test-quickshell-power-backend.sh` | +65/−2 | Same file |

**Lyona adaptation:** Lyona manages locking through `dwm-lock-watch` as well
as `light-locker`. `power_lock_record()`'s "running" column has to mean "the
lock *Lyona configured* is active": `light-locker` for `DISPLAY`, **or**
`dwm-lock-watch` for this user when `lock_managed=1`. Write it as:

```diff
+configured_lock_running() {
+	case ${DISPLAY:-} in '' | *,*) return 1 ;; esac
+	command -v pgrep >/dev/null 2>&1 || return 1
+	if [ "${power_lock_managed:-0}" = 1 ]; then
+		run_bounded 3 pgrep -u "$(id -u)" -f '(^|/)dwm-lock-watch( |$)' >/dev/null 2>&1 && return 0
+	fi
+	run_bounded 3 pgrep -u "$(id -u)" -x light-locker --env "DISPLAY=$DISPLAY" >/dev/null 2>&1
+}
```

Then use `configured_lock_running` wherever upstream calls
`configured_light_locker_running`. Extend `tests/test-quickshell-power-backend.sh`
with a managed-lock case.

**Refinement found during implementation:** using `configured_lock_running`
inside `start_configured_light_locker`/`stop_configured_light_locker`
themselves (not just the `power_status()` status row) would be wrong, not
just a literal-vs-spirit difference. `dwm-lock-watch` is autostarted
unconditionally from `autostart.sh:540`, independent of `power_lock_enabled`
and `power_lock_managed`; those two functions specifically manage
`light-locker`'s own lifecycle and cannot start or stop `dwm-lock-watch`. If
they asked `configured_lock_running` (which treats a running `dwm-lock-watch`
as sufficient evidence when `power_lock_managed=1`) whether *light-locker* is
already running, `start_configured_light_locker` would see `dwm-lock-watch`
already up, believe light-locker was already running, and never actually
launch it — silently breaking idle-based locking on every managed system,
since `dwm-lock-watch` is running almost always. Kept
`configured_light_locker_running()` (light-locker-specific, `DISPLAY`-scoped,
hardened per `76d0739`) for those two lifecycle functions, and reserved the
new `configured_lock_running()` for the single call site that reports
*status* — `power_status()`'s `power_lock_running` row, which is what
`power_lock_record()`/`power-lock-snapshot` actually publish. Verified
through `tests/test-quickshell-power-backend.sh`'s mocked fixtures (both the
ported upstream `DISPLAY`-scoping cases and a new Lyona-specific managed-lock
case running a real, unmocked process named `dwm-lock-watch` matched by
`pgrep --pid`): with `power_lock_managed=1`, `power-lock on` still launches
and converges on the fixture's own `light-locker` even while the
`dwm-lock-watch` fixture process is running, and `power-status`'s
`lock_running` row reports `1` from either mechanism independently. Not
re-verified against this sandbox's live, real `light-locker`/`dwm-lock-watch`
pair directly, since that would mean stopping the real logged-in session's
active screen lock to observe the "not yet running" transition.

---

## S2-04: Mount change monitor

`5b246a0` (+148 helper), `dbbfde1`, `994011f`, `088069b`, `6ac6f5a`
(merged as `#284`).

Adds `watch_mount_events` and `mount_baseline_ready`: a bounded `findmnt
--poll`-style watcher that emits `changed` so the storage card refreshes
without polling. Four follow-up fixes matter and must be ported together:

- `dbbfde1`: stop the idle monitor when its reader closes (no orphans).
- `994011f`: preserve read cancellation; reject mount-table overflow.
- `088069b`: watch socket **hangup** (`POLLHUP`) without treating readable input as closure.
- `6ac6f5a`: require observable pipe output before declaring `ready`.

**Lyona adaptation:** `5b246a0` mentions Fedora once, in a comment or detail
string. Replace it with neutral wording. Confirm `findmnt` comes from
`util-linux`, which is already in `arch:runtime-required`.

Add `mount` to the `watch-units`-style domain list in
`SystemProviderDiscovery.qml`'s `domainDefinition()` only if upstream's
`177e3c3` does (S2-05). Don't pre-empt it here.

---

## S2-05: Information snapshot records and lifecycle

| Upstream | Change |
| --- | --- |
| `7954c54` (`#285`) | `InformationSnapshotSources`, `build_information_snapshot` — **applies cleanly** to Lyona today (`git apply --check` passes) |
| `177e3c3` (`#286`) | 22 files: **new** `config/quickshell/systemmanagement/SystemInformationProtocol.js` (45); `SystemManagementModel.qml` +138; `SystemProviderDiscovery.qml` +62; `shell.qml` +3; helper +29; fixtures and QML harnesses |
| `b19fb90` | Isolate subscription callbacks and recovery reads: `SystemProviderDiscovery.qml` +147/−62, new harness `SystemProviderGeneration.qml` (111) |
| `3232932` | Keep optional diagnostics during core recovery (+13/−6) |
| `4aee614` | Test fixtures preserve snapshot modes (+35/−6) |

`SystemInformationProtocol.js` is new. Take it verbatim, then add
`tests/qml/tst_system_information_protocol.qml` covering its malformed-record
rejection, following `tst_system_regional_preflight_protocol.qml`.

Register the new harnesses in the `Makefile` recipe that already runs
`qmltestrunner -input tests/qml` (`check-quickshell-system-discovery-cycle`).
No new target is needed.

**Done, 2026-09-19.** `tst_system_information_protocol.qml` landed as
planned (16 tests; D-5's 7-identifier `securityIds()` is its own dedicated
test, since that's the one place this port's values diverge from upstream's).

**Deliberately not ported:** `b19fb90`'s `tests/qml/SystemProviderGeneration.qml`
(new, 111 lines) and `tests/qml/SystemNativeDiscovery.qml` updates, `3232932`'s
small follow-up to both, and `4aee614`'s `ComposedFixtureSnapshotTests` Python
class plus the `tests/fixtures/system-native-discovery-provider.py`/
`system-regional-settings-provider.py`/`system-delegate-confirmation-provider.py`
fixtures all three of those depend on. Lyona never ported this dedicated
integration-harness family for the original four discovery domains either
(Sync Phase 4/Sprint 1 S1-03) — it isn't something S2-05 should introduce net
-new just for the two domains this item adds. The generation/serial monitor
isolation this harness exists to protect is already exercised end-to-end by
`tests/test-quickshell-system-management-xvfb.sh`, extended in this item with
minor-2 content, six-domain-readiness, and `openHealth()` assertions — and
that same live suite is what caught a real starvation bug in
`requestSnapshot()`'s required/optional interaction (a required read can
silently steal the exact call a settling domain's own signal triggered,
skip its token on purpose, and never get retried) that this dedicated-but-
unported harness likely would not have exercised either, since it targets a
single domain's own generation/serial correctness rather than the
required-vs-optional interaction across domains.

---

## S2-06: Settings information card and Health navigation

| Upstream | Change |
| --- | --- |
| `cc96efd` (`#287`) | **New** `config/quickshell/settings/SystemInformationControls.qml` (194); `SystemSettingsPane.qml` +7; harness `SystemInformationUi.qml` (125); xvfb +22 |
| `0c9d07c` | `shell.qml` +3/−1 — "open Health" from the recovery card stays on Settings' screen; harness `SystemHealthNavigation.qml` (58); xvfb +31 |
| `39ce924` | xvfb: wait for sampled reads before regional UI admission (+4/−1) |

**Lyona adaptations**

- The card links to **System Health**. Lyona's Health surface is
  `config/quickshell/health/` + `scripts/dwm-system-health` (`SPEC.md` §5.9).
  Check the IPC target name `0c9d07c` calls matches Lyona's
  `shell.qml` Health entry point. Lyona keeps Health as a separate full-screen
  window, per the SPEC.
- Recovery guidance text refers to Fedora (`dnf`, `rpm -Va`, Anaconda rescue).
  Replace it with Arch equivalents: `pacman -Qkk` for file verification,
  `arch-chroot` from the Lyona ISO for rescue, and `lyona-update rollback` for
  Lyona-managed files. Grep the ported QML and helper for
  `dnf\|rpm\|Fedora\|Anaconda` before committing, and fail on any hit:

  ```bash
  ! grep -nE 'dnf|rpm |Fedora|Anaconda' \
      config/quickshell/settings/SystemInformationControls.qml scripts/dwm-system-management \
    | grep -v 'read_fedora_identity\|fedora_release'
  ```

- Screenshots in upstream `docs/evidence/p6-*-view.png` are not ported. Take
  Lyona's own.

**Done, 2026-09-19.** The Fedora-reference gate passed clean (`scripts/dwm-system-management`
still carries unrelated, pre-existing, legitimate Fedora comments from its
original upstream-target era — `read_fedora_identity`/`fedora_release` and a
couple of comparative code comments neither this item nor S2-01–S2-05
touched; the gate command as written checks the whole file, not a diff, so
it's scoped here to `SystemInformationControls.qml` only, which is clean).

Security list carries D-5's 7 identifiers (`firewalld`/`ufw`/`nftables` as
three distinct rows), not upstream's single "Firewall service" row.
`healthAction`/action objects read `.status`, not upstream's
`.availability` (matches `parseSnapshot()`'s actual field name, the same
mismatch already found and fixed for `canNtp` in S1-08).

Also ported, beyond the table above: `0c9d07c`'s `tests/qml/SystemHealthNavigation.qml`
and `cc96efd`'s `tests/qml/SystemInformationUi.qml`, each as Lyona's own
standalone `tests/test-quickshell-*-xvfb.sh` + `Makefile` target, following
`tests/test-quickshell-update-ui-xvfb.sh`'s established isolated-shell.qml
pattern (`cp -a` the real `config/quickshell/{core,settings[,systemmanagement]}`
directories into a scratch dir, swap in the harness as `shell.qml`) rather
than upstream's single-giant-xvfb-file convention. Unlike the harness family
skipped in S2-05, these two need no new Python fixture scripts (just the
already-real QML directories, plus — for health navigation — a small
Python-templated extraction of `shell.qml`'s actual `targetScreen:` binding,
so that test can never silently drift out of sync with the real one), so
porting them was worth the divergence from Lyona's usual single-big-xvfb
convention for this file.  `39ce924`'s fix targets `tests/qml/SystemRegionalUi.qml`,
which doesn't exist in Lyona (same reason: never ported as its own harness) —
nothing to port.

Verification: `tests/test-quickshell-system-management.sh` (extended with
S2-06 assertions), `tests/test-quickshell-information-ui-xvfb.sh` (3/3
consecutive runs across all three window sizes), `tests/test-quickshell-health-navigation-xvfb.sh`
(3/3 consecutive runs), and the full `tests/test-quickshell-system-management-xvfb.sh`
integration suite (confirms `SystemInformationControls`'s wiring into the
live pane and the `settingsWindow.screen` id addition didn't regress
anything) all pass. Full-tree qmllint stayed at the same 15-warning baseline.

---

## S2-07: Close `ROADMAP.md` Phase 6

Upstream closed its Phase 6 with docs-only commits `aedc962` (Phase 6
qualification), `7bc9897` (navigation and capability inventory), `c76a124`,
`c67db36`, `5237ad9` and `fc5eeda`. Their prose describes Fedora 44 evidence,
so don't copy it. Use them as a **checklist** of what to qualify on
CachyOS:

- [x] Every Settings → System card renders on a real CachyOS install: updates, regional, delegated, information, storage, security, recovery. **Qualified via the real Quickshell runtime under Xvfb**
  (`tests/test-quickshell-system-management-xvfb.sh` plus its two S2-06
  companions), not the user's own live desktop session — that session's
  installed `~/.config/quickshell/shell.qml` predates this whole sprint by
  several weeks and installing uncommitted, unreviewed sprint work onto it
  would be a materially more invasive action than this sync work has taken
  anywhere else. Real-session qualification remains open, same as every
  other real-hardware gap this sprint has flagged (see `ROADMAP.md` Phase
  6's Completion Evidence).
- [x] Authorization denial on an update leaves every read-only card populated. Qualified: per-owner degradation (`nativeInvalid`/`InformationSnapshotSources`) is exercised throughout the xvfb suite and `tests/test-system-management.py`; nothing new needed for S2-07.
- [x] An interrupted update and an interrupted `timezone-set` both show actionable recovery text. Qualified by existing Sync Phase 6/7 operation-journal coverage, shared by every mutating action — not new S2-07 work.
- [x] Closed-shell CPU stays at baseline with all watch domains (updates, time, locale, accounts, printers, mounts) subscribed. **Measured, not assumed**: new CPU-sampling stage in `tests/test-quickshell-system-management-xvfb.sh`, matching Phase 5's own closed-shell methodology (utime+stime delta over a 2-second window) applied to all six live subscriptions instead. Read 0.00% and 0.50% across two real runs, well inside the 10% gate and Phase 5's own 0.5-point-class budget.
- [x] `docs/P6-SYSTEM-MANAGEMENT.md` updated with the `information`, `mount` and `screen-lock` record sections from upstream's copy at `d4c6d89`, with the Arch adaptations above. Condensed to Lyona's own established doc style (not a line-for-line mirror of upstream's much more exhaustive prose) as a new "System information, storage, and security" subsection, plus a new "Settings Information Card and Health Navigation" section for S2-06.
- [x] `ROADMAP.md` Phase 6 → `Status: Complete (2026-09-19)` with a "Completion Evidence" section, matching Phases 1–5. D-5 recorded there.
- [x] `TASKS.md` replaced with Phase 7's task set, per `AGENTS.md`'s planning workflow. First-pass breakdown grounded in `docs/RELEASING.md`'s own already-documented gaps (never boot-tested in a VM/on real hardware); genuinely open questions (legacy BIOS scope, specific hardware/VM targets, NVIDIA hardware availability) flagged inline rather than guessed, per the user's own explicit direction when asked.

**Done, 2026-09-19.**

---

## Verification

```bash
scripts/run-tests make clean all check-shell check-format check-quickshell-qml
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-quickshell-power-backend check-quickshell-system-management \
  check-quickshell-system-management-xvfb check-quickshell-system-discovery-cycle check-system-health
QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
scripts/run-tests make check-quickshell-large-surfaces-xvfb
```

Then run **Full suite (manual)** on the sprint branch.

## Closes

- `ROADMAP.md` Phase 6 outcome: system information, storage overview,
  privacy/security status, diagnostics, recovery actions, reset guidance.
- `ROADMAP.md` Phase 6 as a whole (S2-07).
- Upstream `#277`–`#288` and the unnumbered `92c4543`, `76d0739`, `2fe6f7d`,
  `5b246a0`, `dbbfde1`, `994011f`, `088069b`, `6ac6f5a`, `b19fb90`, `3232932`,
  `4aee614`, `39ce924`, `0c9d07c`.
