# Sync Phase 9 — regional mutation, delegated administration, and live watch

Upstream: [`#247`](https://github.com/ChrisTitusTech/dwm-titus/pull/247)
(`2ff757fa`), [`#249`](https://github.com/ChrisTitusTech/dwm-titus/pull/249)
(`e16d4720`), [`#252`](https://github.com/ChrisTitusTech/dwm-titus/pull/252)
(`327ca20a`), [`#253`](https://github.com/ChrisTitusTech/dwm-titus/pull/253)
(`03b21955`), [`#254`](https://github.com/ChrisTitusTech/dwm-titus/pull/254)
(`8b2479bf`), [`#256`](https://github.com/ChrisTitusTech/dwm-titus/pull/256)
(`e6ea0639`), [`#257`](https://github.com/ChrisTitusTech/dwm-titus/pull/257)
(`59e599b1`), [`#258`](https://github.com/ChrisTitusTech/dwm-titus/pull/258)
(`e68be1ae`), [`#263`](https://github.com/ChrisTitusTech/dwm-titus/pull/263)
(`ba21aa0d`), [`#264`](https://github.com/ChrisTitusTech/dwm-titus/pull/264)
(`0eae066d`). Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Depends on [Phase 8](SYNC-P8-REGIONAL-READERS.md) for every reader this phase
confirms against, on [Phase 5](SYNC-P5-OPERATION-JOURNAL.md) for the durable
journal these mutations checkpoint into, and on the
[delegated-tool-target decision **D-3**](UPSTREAM-SYNC.md#open-decisions).

This is the mutation quarter of Phase 6's regional scope: changing the
timezone, toggling network time, changing the system locale, and launching
delegated tools for accounts/printers/software-sources/password. It also
wires the live-watch domains [Phase 4](SYNC-P4-DISCOVERY-EVENTS.md)'s
`domainDefinition` left as placeholders. **Every one of these mutations
follows the same rule, worth stating before anything else:** a confirmed
regional change is durable and its result is real — but the confirmation
step itself is freely cancelable, and a failure *after* dispatch is reported
as `interrupted`, never as fabricated success or fabricated failure. See
[`#247`](https://github.com/ChrisTitusTech/dwm-titus/pull/247), which exists
purely to document and approve this asymmetry before the code that implements
it landed.

---

## Files

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | `RegionalPreview`, `RegionalMutation`, `regional_preflight_output`, `delegated_command`, `trusted_delegated_executable`, `launch_delegated_tool`, `RegionalEventMonitor`, `AccountEventMonitor`; the `regional-choices`, `regional-preview`, `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`, `password-open`, `printers-open`, `sources-open`, `watch-regional`, `watch-accounts`, `watch-units` commands |
| `docs/P6-SYSTEM-MANAGEMENT.md` | Regional mutation and delegated-administration sections |
| `config/quickshell/systemmanagement/SystemRegionalPreflightModel.qml` | **New**, ~173 lines |
| `config/quickshell/systemmanagement/SystemRegionalPreflightProtocol.js` | **New**, ~153 lines |
| `config/quickshell/systemmanagement/SystemProviderDiscovery.qml` | Add `time`/`locale`/`accounts`/`printers` to `domainDefinition` (placeholders since [Phase 4](SYNC-P4-DISCOVERY-EVENTS.md#3-systemproviderdiscoveryqml-is-generic-from-the-start)) |
| `config/quickshell/settings/SystemSettingsPane.qml` | Timezone/locale pickers, NTP toggle, delegated-launch buttons |
| `config/quickshell/shell.qml` | `systemManagementRegionalPreview()`, `systemManagementRegionalConfirm()`, `systemManagementDelegatedLaunch()` probes |

---

## 1. The preflight: a content hash, not a random token

Every other timed-preview mechanism in this codebase (display apply, theme
preview, input preview — all from earlier phases) uses a **random token**
plus a **countdown timer**. Regional preflight uses neither. `RegionalPreview`
(`:486`) binds a proposed change to the *exact* state it was computed
against, and its `generation` is a **deterministic SHA-256 digest**:

```python
digest = hashlib.sha256(b"dwm-titus-regional-preview-v1")
for field in (action, argument, *source_fields):
    encoded = field.encode("utf-8")
    digest.update(len(encoded).to_bytes(8, "big"))
    digest.update(encoded)
return RegionalPreview(action, argument, digest.hexdigest(), current_value, target, detail)
```

`source_fields` is the *current observed state* the change would apply
against (the current timezone for `timezone-set`, the current NTP flag pair
for `ntp-set`, the full current locale assignment set for `locale-set`) — not
a nonce, not a timestamp. This means: **if the state a preview was computed
against has changed by the time the confirmation arrives, the hash the
client echoes back will not match a freshly recomputed one, and the mutation
is refused as a `conflict`** — optimistic concurrency, not a countdown.
`require_regional_generation()` (`:546`) is the check on the way in; the
`RegionalMutation` class below re-derives and re-checks it a **second time**
immediately before dispatch, because state can drift in the gap between the
preflight read finishing and the confirmation arriving.

`Lyona rename note`: rename this constant's domain-separation prefix
(`b"dwm-titus-regional-preview-v1"`) to a Lyona-specific string when porting
— it is a length-prefixed domain separator, not a literal upstream string
that must be preserved for interoperability. Bump the version suffix if the
field list ever changes shape.

Two read-only CLI commands expose this without any write:

```text
regional-choices timezone|locale      # -> choice<TAB>value, one per line
regional-preview ACTION VALUE         # -> preview<TAB>action<TAB>argument<TAB>generation<TAB>current<TAB>target<TAB>detail
```

`regional_preflight_output()` (`:569`) fully buffers the stream before
writing anything — a failure never leaks a partial row, matching the
"complete or nothing" rule the update snapshot protocol already established.
Port `SystemRegionalPreflightProtocol.js`/`SystemRegionalPreflightModel.qml`
as the QML-side parser and lifecycle for this pair of commands; they are pure
request/response, no watch involved.

## 2. `RegionalMutation`: what "never fabricate a terminal state" means in code

`RegionalMutation` (`:1153`) is the client for `timezone-set`/`ntp-set`/
`locale-set`. Port its lifecycle exactly — this is the highest-consequence
code in the whole subsystem and the shape is not incidental:

1. **Resolve and pin the service owner**, subscribe to its
   `PropertiesChanged` and `NameOwnerChanged` signals *before* doing anything
   else, so a change during the window between preflight and dispatch is
   observable rather than silently missed.
2. **Re-run the preflight read** against the pinned owner and **re-validate
   the caller's generation against it** (`preflight_read`, `:1353`) — this is
   the second check mentioned above.
3. **Drain the event loop** (`drain()`, `:1000`ish) to flush any signal that
   arrived concurrently, bounded by `REGIONAL_CALLBACK_LIMIT` — never let a
   signal flood turn into an unbounded nested loop.
4. **Call the caller's `before_send` hook** — this is where
   [Phase 5](SYNC-P5-OPERATION-JOURNAL.md)'s journal records "about to
   dispatch" durably, *before* the D-Bus call is made. If this hook raises,
   the mutation fails as `interrupted` and nothing is sent.
5. **Re-check drift and re-validate the generation a third time**, then
   dispatch the actual D-Bus method
   (`SetTimezone(zone, bool)`/`SetNTP(enabled, bool)`/`SetLocale([...], bool)`)
   with `ALLOW_INTERACTIVE_AUTHORIZATION` — this is the polkit prompt.
6. **From this point on (`self.sent = True`), a failure is never reported as
   plain failure or timeout — it becomes `interrupted`.** See `bus_failure()`:

```python
if self.sent and name is None:
    return SnapshotFailure("interrupted",
        "Regional transport failed after dispatch; the outcome is unknown. "
        "Refresh state before a new confirmation")
```

7. **Call `after_reply`** (the journal's "dispatched, awaiting confirmation"
   checkpoint), then **re-read state and verify it actually matches the
   expected outcome** (`verified`/`matches`) before reporting success. A
   mismatch — someone else changed it concurrently, or the daemon silently
   no-opped — is `conflict`, not success.

The `before_send`/`after_reply` hooks are how this phase **reuses
[Phase 5](SYNC-P5-OPERATION-JOURNAL.md)'s journal rather than building a
second one**: the CLI's `run_regional_mutation()` wrapper (`:6113`) supplies
journal-write closures as those two callables. Port the journal integration
as an extension of Phase 5's existing writer, not a parallel code path.

**Contract exception, stated plainly for `UPSTREAM-SYNC.md`'s decision log:**
confirmation (the Settings-side "are you sure" step, and the choice of
*when* to call `timezone-set`) is freely cancelable — closing the pane or
clicking away before confirming leaves nothing dispatched. Once dispatched,
though, `SetTimezone`/`SetNTP`/`SetLocale` are **not** cancelable calls (there
is no polkit "cancel this in-flight authorization" primitive), and an
ambiguous outcome after that point is always `interrupted`, reported to the
user as "the outcome is unknown, refresh before retrying" — never silently
retried, never assumed to have succeeded or failed.

## 3. Delegated administration: dynamic terminal resolution for `password-open`

`DELEGATED_TOOLS` (`:47`) is fixed and small:

```python
DELEGATED_TOOLS = {
    "accounts-open": ("/usr/bin/lxqt-admin-user", "User accounts"),
    "printers-open": ("/usr/bin/system-config-printer", "Printers"),
    "sources-open": ("/usr/bin/dnfdragora", "Software sources"),
}
DELEGATED_ACTIONS = frozenset((*DELEGATED_TOOLS, "password-open"))
```

`password-open` is **not** in `DELEGATED_TOOLS` — it has no fixed executable.
`delegated_command()` (`:1964`) resolves it dynamically: it asks the user's
already-configured terminal selector (`dwm-terminal --print-command`,
sandboxed with a fixed 3-second deadline and a restricted environment —
`terminal_selection_environment()`/`read_terminal_selection()`, `:1861`\
onward) which terminal is selected, matches it against
`PASSWORD_TERMINALS = {"alacritty": ("-e",), "kitty": (), "st": ("-e",), "xterm": ("-e",)}`,
and launches `<terminal> <exec-flag-if-any> passwd`.

**Lyona already has the exact hook this needs**: `scripts/dwm-terminal
--print-command` (confirmed present, `scripts/dwm-terminal:13`) is the same
contract upstream's `read_terminal_selection()` calls. Port
`delegated_command()`'s `password-open` branch against Lyona's own
`dwm-terminal`, unchanged in shape — this is one of the few places upstream
and Lyona already agree on the helper interface without adaptation.

Every resolved executable — fixed or dynamic — passes through
`trusted_delegated_executable()` (`:1840`) before it is ever passed to
`posix_spawn`: canonicalize the path, require the resolved basename to match
what was expected, then walk every parent directory up to `/` requiring
root ownership and no group/other write bit. This is the same
root-owned/non-writable-parent-chain discipline
[the security-hardening phase](UPSTREAM-SYNC.md#position-in-the-sequence)
already established elsewhere in Lyona (`dwm-settings-display-root`,
`dwm-system-health`) — port the check, don't re-derive it.

`launch_delegated_tool()` (`:1988`) uses `posix_spawn` with
`POSIX_SPAWN_CLOSEFROM` (fd 3+) and stdio redirected to `/dev/null` — it
launches and returns immediately, it does not wait for or supervise the
tool's own internal privilege escalation (the tool itself, e.g.
`system-config-printer`, is responsible for its own polkit prompt). `#254`
wraps this launch in a fixed journal record so "a delegated tool was
launched" is itself durable and auditable, even though the tool's own
outcome is opaque to `dwm-system-management`.

### Open decision D-3: Arch targets for `accounts-open` and `sources-open`

Confirmed this session: `system-config-printer` (→ `printers-open`) exists in
Arch `extra` unchanged. **Neither `lxqt-admin-user` nor `dnfdragora` exists in
Arch's official repositories.** Options, to be settled before this phase is
implemented (tracked as **D-3** in
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#open-decisions)):

- **`accounts-open`** — candidates: ship no default and report
  `unavailable` with an honest detail string (`accounts-open` degrades
  gracefully by design — this is exactly the "capability, not a hole" pattern
  `SETTINGS-CAPABILITIES.md` already uses everywhere); or point at an
  AUR-packaged equivalent (e.g. `lxqt-admin-user` itself is AUR-available)
  behind the same `arch:system-management-optional` profile
  [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#2-package-profiles)
  established, matching the `xkbset` precedent (AUR-only, optional profile,
  no hard failure).
- **`sources-open`** — no Arch tool edits `pacman.conf` interactively the way
  `dnfdragora` edits DNF repo files. The honest answer may be permanent
  `unavailable` with a detail pointing at `/etc/pacman.conf` and
  `docs/src/settings.md`'s existing guidance, rather than inventing a new
  privileged repo-editing surface this project has not designed or reviewed.

Whichever is chosen, `trusted_delegated_executable()`'s root-owned-chain
check applies unchanged — an AUR package installed by `makepkg` into
`/usr/bin` satisfies it exactly as a distro package would.

## 4. Live watch: extending Phase 4's generic monitor to four more domains

[Phase 4](SYNC-P4-DISCOVERY-EVENTS.md#3-systemproviderdiscoveryqml-is-generic-from-the-start)
already ported `SystemProviderDiscovery.qml` generically, with `time`/
`locale`/`accounts`/`printers` domains defined but unreachable (no backing
helper command existed yet). This phase makes them real:

```text
watch-regional time|locale    # -> regional-event<TAB>ready|changed
watch-accounts                # -> accounts-event<TAB>ready|changed
watch-units printers|security # -> units-event<TAB>ready|changed
```

`RegionalEventMonitor`/`AccountEventMonitor` (`:8365`, `:8407`) both extend
`AuthenticatedEventMonitor(UpdateEventMonitor)` — the same bounded-setup,
`NameOwnerChanged`-aware, dirty-flag pattern
[Phase 4](SYNC-P4-DISCOVERY-EVENTS.md#1-the-event-stream-is-a-child-process-not-a-daemon)
already described for updates, subscribing to `PropertiesChanged` on
`timedate1`/`locale1`/`Accounts` instead of PackageKit's manager signals.
Wire them into `SystemProviderDiscovery`'s existing `domainDefinition` table
— no new QML lifecycle component is needed, only the four new
`Commands.systemManagementCommand()` action strings the table already
reserved slots for.

**`watch-units security` (`firewalld.service`) is deliberately not wired up
by this phase.** `WATCH_UNIT_SETS` (`:215`) defines it upstream, but no
provider, state, or action for a `security` domain exists anywhere in the
protocol-minor table
([Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#1-the-contract-document)'s
minor `2` row: "information, storage, security, diagnostics... **Not
implemented upstream. Out of scope**"). Porting the watch half of a domain
with no corresponding read or protocol record would ship a monitor for state
Settings never displays. Leave `security` out of `domainDefinition` until (if
ever) upstream ships the read side too, and note this explicitly rather than
silently matching upstream's dict.

## 5. Settings pane surface

Add to `SystemSettingsPane.qml`, reusing exactly the primitives
[Phase 7](SYNC-P7-OPERATION-SURFACE.md#lyona-adaptations) already named:

- A timezone picker and locale picker (`Controls.ComboBox`, the same
  `DisplayComboBox`-style component the
  [old sync work's display-resolution phase](UPSTREAM-SYNC.md#recommended-execution-order)
  introduced for resolution/refresh-rate — reuse that component shape rather
  than inventing a second combo-box style), populated from
  `regional-choices` and gated on a `StatusCard` while unavailable.
- An NTP toggle using the same primary/pending `ShellButton` states
  [Phase 7](SYNC-P7-OPERATION-SURFACE.md) already wired for confirm/cancel.
- A confirmation step between "pick a value" and "dispatch" that shows the
  `RegionalPreview`'s `current`/`target`/`detail` fields verbatim — this is
  the user-visible form of the generation check, and it must read as "here
  is exactly what will change," not a generic "are you sure."
- Delegated-launch buttons (`accounts-open`/`password-open`/`printers-open`/
  `sources-open`), each independently `unavailable` per **D-3**'s outcome,
  with the `unavailable` detail string shown rather than a disabled button
  with no explanation.
- Every constant through `Theme.dp()`.

```qml
        function systemManagementRegionalPreview(action: string, value: string): string {
            return systemManagementModel.regionalPreflight(action, value);
        }

        function systemManagementRegionalConfirm(action: string, generation: string): void {
            systemManagementModel.confirmRegional(action, generation);
        }

        function systemManagementDelegatedLaunch(action: string): void {
            systemManagementModel.launchDelegated(action);
        }
```

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-quickshell-system-management
scripts/run-tests make check-quickshell-qml
```

Manual, on a real CachyOS install — **do these on a machine you can afford to
have its timezone/locale/NTP setting changed on**:

- Preview a timezone change, confirm it, verify `timedatectl status` reflects
  it, then verify the pane's own state (not just the raw D-Bus property)
  agrees after a Reload.
- Preview a timezone change, then in a separate terminal run
  `timedatectl set-timezone <different-zone>` before confirming in the pane.
  The confirmation must be refused as a conflict — the generation no longer
  matches.
- Toggle NTP off then back on; confirm `timedatectl show -p NTP` matches at
  each step.
- Change locale, confirm `localectl status` matches, and confirm a
  `LANG=` value the running session actually needs is not silently dropped.
- **The interrupted case, verified deliberately**: preview a timezone change,
  confirm it, and kill `dwm-system-management`'s dispatch process (or block
  system-bus access) between dispatch and verification. The pane must show
  "outcome unknown, refresh before retrying" — never "success," never a
  silent retry.
- Each delegated-launch button, per whatever **D-3** settles on: confirm it
  either launches the expected tool or shows an honest `unavailable` detail,
  never a silent no-op.
- Open Settings → System, then externally run
  `timedatectl set-ntp false` / `true`. The pane's regional summary updates
  without a manual Reload — this is the watch wiring from §4.
- Closed-CPU baseline again with all four new watch domains subscribed at
  once (not just `updates`) — confirm the added monitors do not measurably
  move the idle delta.

## Closes

The mutation quarter of Phase 6's regional/account/printer/software-sources
scope in `ROADMAP.md`, and the `ROADMAP.md` exit criterion *"Every privileged
action is allowlisted, confirmed, auditable, and cancelable"* for the
regional half — the update half was
[Phase 7](SYNC-P7-OPERATION-SURFACE.md#closes)'s. This is also the last phase
of the nine; once it lands, Phase 6's system-management scope (as currently
understood — see the decisions logged in
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#open-decisions)) is complete.
