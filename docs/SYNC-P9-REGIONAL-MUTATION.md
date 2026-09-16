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

**Landed in PR #32** (`sync-p7-mutation-fix-v2`, backend + read-only QML):

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | `RegionalPreview`, `RegionalMutation`, `regional_preflight_output`, `delegated_command`, `trusted_delegated_executable`, `launch_delegated_tool`, `RegionalEventMonitor`, `AccountEventMonitor`; the `regional-choices`, `regional-preview`, `timezone-set`, `ntp-set`, `locale-set`, `accounts-open`, `password-open`, `printers-open`, `sources-open`, `watch-regional`, `watch-accounts`, `watch-units` commands |
| `docs/P6-SYSTEM-MANAGEMENT.md` | Regional mutation and delegated-administration sections |
| `config/quickshell/systemmanagement/SystemRegionalPreflightModel.qml` | **New**, ~178 lines |
| `config/quickshell/systemmanagement/SystemRegionalPreflightProtocol.js` | **New**, ~158 lines |
| `config/quickshell/systemmanagement/SystemProviderDiscovery.qml` | **Already done, turns out — no change needed.** `domainDefinition()` (`:40`) already returns full `time`/`locale`/`accounts`/`printers` entries; Phase 4 built it generically and Checkpoint 2's `watch-regional`/`watch-accounts`/`watch-units` commands are all `domainDefinition()` needed to become real. Confirmed by reading the shipped file, not assumed. |

**Follow-up, planned below, its own branch (`sync-p9-settings-ui`) and PR** — the
Settings UI surface. None of this phase's own cited upstream PRs touch any of
these files (confirmed by diffing each one), so none of it shipped in PR #32:

| File | Change |
| --- | --- |
| `config/quickshell/systemmanagement/SystemOperationModel.qml` | Add `startRegional()`/`startDelegated()` dispatch entry points beside the existing `startUpdate()` |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | Own an instance of `SystemRegionalPreflightModel`; add `regionalActionReason()`/`prepareRegional()`/`confirmRegional()`/`discardRegional()`/`launchDelegated()` mirroring the existing `updateActionReason()`/`prepareUpdate()`/`confirmUpdate()`/`discardUpdate()` family |
| `config/quickshell/settings/SystemRegionalControls.qml` | **New** — timezone/locale pickers, NTP toggle, delegated-launch buttons, and the preview confirmation card, mirroring `SystemUpdateControls.qml`'s shape |
| `config/quickshell/settings/SystemSettingsPane.qml` | Mount `SystemRegionalControls` |
| `config/quickshell/shell.qml` | `systemManagementRegionalPreview()`, `systemManagementRegionalConfirm()`, `systemManagementDelegatedLaunch()` probes (and a couple more state probes than the original sketch had — see §5.6) |
| `tests/test-quickshell-system-management-xvfb.sh` | Extend the stub `dwm-system-management` to emit protocol minor `1` native rows and answer `timezone-set`/`ntp-set`/`locale-set`/`*-open`, so the new controls have real content to assert against |

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

Both ported unchanged from upstream's `0eae066d` (PRs #263/#264) — neither
file is distro- or Fedora-specific, and `Commands.systemManagementCommand()`
already dispatches arbitrary actions generically, so no adaptation was
needed. The pure parser is covered directly, translated into this repo's
`QtTest`/`TestCase` convention rather than upstream's bespoke `ShellRoot`
harness: `tests/qml/tst_system_regional_preflight_protocol.qml` (picked up
automatically by `qmltestrunner -input tests/qml`, run via the existing
`check-quickshell-system-discovery-cycle` target — no new Makefile wiring
needed). Verified with `qmltestrunner` directly (39/39 passed, including the
pre-existing `SystemDiscoveryCycle` suite) since `scripts/quickshell-qmllint`
alone cannot execute JS logic.

> **Known automated-coverage gap**, matching [Phase 7's own precedent for
> `SystemOperationParser.qml`](SYNC-P7-OPERATION-SURFACE.md#5-shellqml-probes):
> upstream's `tests/qml/SystemRegionalPreflightOwner.qml` and
> `tests/qml/SystemNativeDiscovery.qml` (PR #264) exercise
> `SystemRegionalPreflightModel`/`SystemProviderDiscovery` as live Quickshell
> processes against a real private-bus provider stub
> (`tests/fixtures/system-regional-preflight-provider.py`) — comparable in
> complexity to `tests/test-system-management.py`'s own fixtures, and out of
> scope for this pass. Deferred, not forgotten; the parser itself (the part
> most likely to have a subtle byte-level bug) has full coverage above.

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

## 5. Settings pane surface (follow-up: `sync-p9-settings-ui`)

Everything below is **plan, not yet implemented** — written after PR #32
landed the backend and the read-only QML preflight model, against the
actual shipped code (not the aspirational sketch this section used to be).
Two things already fully exist and need no new code, confirmed by reading
the shipped files rather than assumed:

- `SystemRegionalPreflightModel.qml`/`SystemRegionalPreflightProtocol.js`
  (Checkpoint 3) already own the async `regional-choices`/`regional-preview`
  read: `requestChoices(kind)`, `requestPreview(action, argument)`, and a
  `completed(outcome)` signal carrying `{ status, error, choices, preview }`
  where `preview` is `{ actionId, argument, generation, current, target,
  detail }`. This is the thing to instantiate and drive below, not
  reinvent.
- `SystemOperationProtocol.js`'s `actionKind()`/`owner()` (`:35`, `:47`) and
  `SystemManagementModel.qml`'s `active-operation`/`terminal-handoff`
  snapshot parsing (via `operationActionKind()` → `regionalActionKind()`/
  `delegatedActionKind()`) already classify `timezone-set`/`ntp-set`/
  `locale-set`/`accounts-open`/`password-open`/`printers-open`/
  `sources-open` correctly — both were pre-extended during Checkpoint 1/2
  specifically so this follow-up would not need a second parser revision.
  A regional or delegated operation dispatched through `native_command()`
  lands in the **same journal** `watch-operation`/`ack-operation` already
  serve, so `SystemOperationModel`'s existing recovery/watch/acknowledge
  machinery — and `SystemSettingsPane.qml`'s existing `operationCard`/
  `resultCard` (`:323`–`:347`) — already display it generically. The only
  gap is a way to **start** one.

### 5.1 `SystemOperationModel.qml`: two new dispatch entry points

`startUpdate(action, generation)` (`:142`) hardcodes its action allowlist
and each action's own generation shape (empty for `updates-refresh`, 64-hex
for `updates-install-all`) — regional/delegated actions don't fit that one
signature cleanly (three regional actions always take a 64-hex generation
*and* an argument; four delegated actions take neither). Add two siblings
that share the same "claim ownership, build the command, launch
`watchProcess`" shape `startUpdate` already uses, rather than overloading
its signature:

```qml
    // Regional actions always carry a 64-hex generation (RegionalMutation
    // re-validates it against a fresh read before dispatch; the QML layer
    // does not need to re-derive package-change-style state the way
    // startUpdate does). Argument shape matches validate_regional_argument()
    // in scripts/dwm-system-management: a timezone name, "enabled"/
    // "disabled", or "LANG=...".
    function startRegional(action, argument, generation) {
        if (!root.snapshotKnown || root.streamOwned || root.controlOwned || root.waitingSnapshot
                || root.blocked || retryTimer.running || root.snapshotActive !== null || root.handoff !== null
                || ["timezone-set", "ntp-set", "locale-set"].indexOf(action) < 0
                || typeof argument !== "string" || !/^[0-9a-f]{64}$/.test(generation))
            return false;
        return root.dispatch(action, [action, argument, generation]);
    }

    // Delegated actions take no argument and no generation -- the helper
    // resolves and launches a fixed tool, or reports it unsupported/
    // unavailable. No package-change-style preview applies.
    function startDelegated(action) {
        if (!root.snapshotKnown || root.streamOwned || root.controlOwned || root.waitingSnapshot
                || root.blocked || retryTimer.running || root.snapshotActive !== null || root.handoff !== null
                || ["accounts-open", "password-open", "printers-open", "sources-open"].indexOf(action) < 0)
            return false;
        return root.dispatch(action, [action]);
    }

    // Shared tail of startUpdate/startRegional/startDelegated: claim
    // ownership and launch the watch process. Factored out here rather than
    // duplicated a third time; startUpdate keeps its own body unchanged
    // (touching already-tested Sync Phase 6/7 code is out of scope) but
    // could be folded into this too in a later cleanup pass.
    function dispatch(action, args) {
        const command = Commands.systemManagementCommand(args[0], args.slice(1));
        root.snapshotKnown = false;
        root.parser = Protocol.create("", action);
        root.progress = null;
        root.log = [];
        root.streamOwned = true;
        root.streamReplay = false;
        root.streamFailed = false;
        root.terminalPending = false;
        root.result = null;
        root.audit = null;
        root.operationError = null;
        root.cancelRequestedId = "";
        root.cancelUncertainId = "";
        root.cancelConflictId = "";
        root.cancelDetail = "";
        root.state = "observing";
        root.detail = "Starting " + action;
        watchProcess.command = command;
        root.discoveryInvalidated();
        Qt.callLater(function() { if (root.streamOwned) watchProcess.running = true; });
        return true;
    }
```

`canStart`, `canCancel`, `finishWatch`, `consume` — all already generic
(action-kind-agnostic), confirmed by reading them; **no other change to this
file**. Note regional/delegated operations are never cancelable
(`RegionalMutation`/`run_delegated_launch` have no `cancel-requested`
transition — `cancelTarget()` already excludes anything whose `kind` isn't
`update`/`refresh`, so `canCancel` correctly stays `false` for these without
any change).

### 5.2 `SystemManagementModel.qml`: own the preview lifecycle

Instantiate `SystemRegionalPreflightModel` beside `discoveryModel`/
`operationModel` (`:702`–`:719`), gated on `settingsVisible` the same way:

```qml
    SystemRegionalPreflightModel {
        id: regionalPreflightModel
        active: root.settingsVisible
        onCompleted: outcome => root.regionalPreviewReceived(outcome)
    }
```

Add state and functions mirroring `updateActionReason()`/`prepareUpdate()`/
`confirmUpdate()`/`discardUpdate()` (`:182`–`:246`) exactly — same captured-
snapshot discipline, adapted for the fact that RegionalMutation re-validates
its own generation server-side (see the family doc-comment at `:201`) so the
QML side only needs to guard *dispatch eligibility*, not re-derive plan
content the way `updates-install-all`'s package-change list does:

```qml
    property var regionalPreview: null       // { actionId, argument, generation, current, target, detail }
    property string regionalPreviewError: "" // set on a failed preflight read
    property bool regionalPreviewPending: false
    property string regionalConfirmMessage: ""
    property bool dispatchingRegional: false

    function nativeActionReason(actionId) {
        if (root.validNativeActionIds.indexOf(actionId) < 0)
            return "This administration action is not supported.";
        if (!root.settingsVisible || root.dispatchingRegional)
            return "Open System Settings to prepare this action.";
        if (root.snapshotOwned || root.snapshotPending || root.requiredPending || !discoveryModel.fresh)
            return "Wait for fresh status, or reload status to retry.";
        if (!operationModel.canStart)
            return "An operation or its recovery still owns the update workflow.";
        // Confirmed by reading parseSnapshot() (:660-662): every valid native
        // action record is already merged into the same flat root.actions
        // updateActionReason() searches (actions.push(nativeActions[actionId])
        // for each non-invalid owner) -- no separate nativeActions accessor
        // is needed, this is a straight copy of updateActionReason()'s own
        // lookup shape.
        const action = root.actions.find(item => item.id === actionId);
        if (!action || action.status !== "available")
            return action && action.detail.length > 0 ? action.detail : "This action is not currently offered.";
        return "";
    }

    // Regional (timezone-set/ntp-set/locale-set): fetch a fresh preview
    // before showing a confirmation card. Unlike prepareUpdate(), there is
    // no synchronous "reason" to check up front beyond nativeActionReason --
    // the preview read itself is the validity check.
    function prepareRegional(action, argument) {
        const reason = root.nativeActionReason(action);
        if (reason.length > 0) {
            root.regionalConfirmMessage = reason;
            return false;
        }
        root.regionalConfirmMessage = "";
        root.regionalPreviewError = "";
        root.regionalPreview = null;
        root.regionalPreviewPending = true;
        return regionalPreflightModel.requestPreview(action, argument);
    }

    function regionalPreviewReceived(outcome) {
        root.regionalPreviewPending = false;
        if (outcome.command !== "regional-preview") return; // a choices read, not a preview
        if (outcome.status !== "available") {
            root.regionalPreviewError = outcome.error.detail;
            return;
        }
        root.regionalPreview = outcome.preview;
    }

    function discardRegional() {
        regionalPreflightModel.cancel();
        root.regionalPreview = null;
        root.regionalPreviewPending = false;
        root.regionalPreviewError = "";
        root.regionalConfirmMessage = "";
    }

    function confirmRegional() {
        const pending = root.regionalPreview;
        if (pending === null || root.dispatchingRegional) return false;
        const reason = root.nativeActionReason(pending.actionId);
        if (reason.length > 0) {
            root.regionalConfirmMessage = reason;
            root.regionalPreview = null;
            return false;
        }
        root.dispatchingRegional = true;
        root.regionalPreview = null;
        const started = operationModel.startRegional(pending.actionId, pending.argument, pending.generation);
        // A false return here means RegionalMutation itself will reject the
        // stale generation server-side -- startRegional's own precondition
        // check is a QML-side fast path, not the authority. Either way,
        // never claim success; tell the user to look again.
        root.regionalConfirmMessage = started ? "" : "Regional state changed. Review a fresh preview and confirm again.";
        root.dispatchingRegional = false;
        return started;
    }

    // Delegated actions (accounts-open/password-open/printers-open/
    // sources-open) have no preview step -- launch_delegated_tool() either
    // starts a fixed, already-trusted executable or the action was already
    // reported unavailable/unsupported by nativeActionReason(). Whether this
    // still deserves a lightweight "Open <tool>?" confirmation before
    // dispatch is an open question -- see 5.8.
    function launchDelegated(action) {
        const reason = root.nativeActionReason(action);
        if (reason.length > 0) {
            root.regionalConfirmMessage = reason;
            return false;
        }
        return operationModel.startDelegated(action);
    }

    onConfirmationInvalidated: {
        // discoveryModel/operationModel signals already invalidate the
        // update confirmation (:248); extend the same handler rather than
        // add a second signal, since both share one invalidation source.
        if (root.regionalPreview !== null)
            root.regionalConfirmMessage = "State changed. Review a fresh preview and confirm again.";
        root.regionalPreview = null;
    }
```

### 5.3 New `SystemRegionalControls.qml`

Mirror `SystemUpdateControls.qml`'s shape exactly (`PlainText`/`ActionButton`
local components, a `confirmationCard` `Rectangle` with the same
`onVisibleChanged: if (visible) root.revealRequested(...)` pattern from the
`onVisibleChanged` fix already applied to `SystemUpdateControls.qml`) rather
than inventing a second confirmation-card style. One thing `SystemUpdateControls.qml`
never needed that this file does: `import qs.systemmanagement` — every
`settings/` pane so far only imports `qs.core` because its model is handed
in as a `required property var`, but this file instantiates
`SystemRegionalPreflightModel` (a `qs.systemmanagement` type) directly for
its own picker choice reads, and implicit same-directory lookup does not
cross the `settings/`/`systemmanagement/` directory boundary. Structure:

- A local inline `component RegionalComboBox: Controls.ComboBox { ... }`,
  copying `DisplaySettingsPane.qml`'s `DisplayComboBox` (`:15`–`:45`)
  verbatim (same `palette.*`/`Theme.*` bindings) — it is a local inline
  component there too, not a shared one, so this follows the existing
  precedent rather than breaking it by promoting one file's private
  component into `qs.core` unasked.
- Timezone picker: `model: timezoneChoicesModel.result === null ? [] : timezoneChoicesModel.result.choices`,
  populated by a second `SystemRegionalPreflightModel { requestChoices("timezone") }`
  instance (or reuse `regionalPreflightModel` for both choices and preview —
  decide in 5.8, since driving both from one instance means a choices
  request and a preview request can race for ownership; a dedicated
  instance per concern is probably simpler and matches how `discoveryModel`
  and `operationModel` are already two separate model instances rather than
  one doing double duty).
- Locale picker: same shape, `requestChoices("locale")`.
- NTP toggle: `PanelToggleSwitch { checked: <current NTP state from
  nativeStates>; onToggled: root.model.prepareRegional("ntp-set",
  checked ? "disabled" : "enabled") }` — reads current state from
  `root.model.nativeStates["ntp-enabled"]` (already parsed and published by
  Checkpoint 1; `value` is `"yes"`/`"no"`/`"unknown"`).
- Confirmation card: shows `root.model.regionalPreview.current` →
  `.target`, `.detail` verbatim (per the original design note, still
  correct: "here is exactly what will change," not a generic "are you
  sure"), with Confirm/Not now buttons calling
  `root.model.confirmRegional()`/`root.model.discardRegional()`.
- Delegated-launch buttons: four `ActionButton`s, `enabled:
  root.model.nativeActionReason(actionId) === ""`, `onActivated:
  root.model.launchDelegated(actionId)`. Per **D-3**, `accounts-open`/
  `sources-open` are permanently `unsupported` on Arch — the button stays
  visible but disabled, with the `unsupported` detail text shown beside it
  (matching `SystemUpdateControls.qml`'s `refreshReason`/`installReason`
  pattern at `:82`–`:95`), never hidden with no explanation.
- Every constant through `Theme.dp()`, matching every other pane file.

### 5.4 `SystemSettingsPane.qml`

Add a `SectionLabel { label: "Regional & administration" }` and mount
`SystemRegionalControls { model: root.systemManagementModel; onRevealRequested:
target => root.reveal(target) }`, in the same position `SystemUpdateControls`
occupies relative to its own section (`:283`–`:288`) — directly after it,
before the pending-updates `GridLayout`, since both are Settings → System
confirm-surfaces and belong adjacent to each other rather than interleaved
with the read-only status cards below.

### 5.5 `SystemProviderDiscovery.qml` consumers

`domainDefinition()` already answers for `time`/`locale`/`accounts`/
`printers` (§4, already shipped) but nothing currently instantiates
`SystemProviderDiscovery { domain: "time" }` etc. — `SystemUpdateDiscovery.qml`
is the only consumer today, hardcoded to the update domain. Decide during
implementation whether `SystemRegionalControls.qml` needs its own live
discovery subscriptions at all for this first pass (a manual "Reload status"
covers the pickers/toggle/buttons adequately, matching how
`updateActionReason()` already requires `discoveryModel.fresh` before
allowing a *dispatch*, without every read-only field needing its own push
subscription) — wiring live regional/account/printer discovery pushes can be
a later, separate enhancement if the manual-reload UX proves insufficient in
practice, rather than required scope for this follow-up.

### 5.6 `shell.qml` IPC probes

```qml
        function systemManagementRegionalPreviewPending(): bool {
            return systemManagementModel.regionalPreviewPending;
        }

        function systemManagementRegionalPreview(action: string, argument: string): bool {
            return systemManagementModel.prepareRegional(action, argument);
        }

        function systemManagementRegionalPreviewResult(): string {
            const preview = systemManagementModel.regionalPreview;
            return preview === null ? "" : preview.actionId + ":" + preview.current + ":" + preview.target;
        }

        function systemManagementRegionalConfirm(): bool {
            return systemManagementModel.confirmRegional();
        }

        function systemManagementRegionalDiscard(): void {
            systemManagementModel.discardRegional();
        }

        function systemManagementDelegatedLaunch(action: string): bool {
            return systemManagementModel.launchDelegated(action);
        }
```

The original sketch's `systemManagementRegionalPreview(action, value):
string` returning a value synchronously does not match the real, async
`Process`-backed preview read — corrected here to return a `bool` (request
accepted or not, matching `updateApply`'s own fire-and-forget shape) with a
separate `systemManagementRegionalPreviewResult()` probe to poll, the same
two-probe split `systemManagementOperationState()`/
`systemManagementOperationResult()` (`:958`–`:965`) already establishes for
async state.

### 5.7 Test plan

- `tests/test-quickshell-system-management-xvfb.sh`: extend the stub
  `dwm-system-management` (`:113`–`:145`) to also answer `regional-choices`,
  `regional-preview`, `timezone-set`/`ntp-set`/`locale-set`, and
  `accounts-open`/`password-open`/`printers-open`/`sources-open` with fixed,
  deterministic output (mirroring the existing `snapshot`/`watch-updates`
  cases), and emit protocol minor `1` native rows from `snapshot` so
  `nativeProviders`/`nativeStates` are populated for the new controls to
  read. New assertions: a picker's `model` is non-empty once
  `regional-choices` completes, `systemManagementRegionalPreview()` +
  `systemManagementRegionalPreviewResult()` round-trip a fixed timezone
  change, `systemManagementRegionalConfirm()` dispatches and
  `systemManagementOperationResult()` eventually reports
  `timezone-set:succeeded`, and each delegated-launch button's `enabled`
  state matches **D-3** (`accounts-open`/`sources-open` always disabled,
  `printers-open` enabled against the stub).
- `tests/test-system-management.py`: unaffected — this follow-up is QML-only,
  the Python backend is already fully covered.
- `scripts/quickshell-qmllint --root config/quickshell`: run as always: the
  only way to catch a binding-loop or unqualified-access mistake in the new
  files before a live run.

### 5.8 Open questions to resolve during implementation, not before

- Does `launchDelegated()` need its own confirmation card (matching
  regional's "here is exactly what will change"), or is enabling the button
  only when available, plus the result card after dispatch, enough? The
  action itself is irreversible-ish (it opens a privileged tool) but
  `run_delegated_launch()`'s own docstring already frames it as "launch
  accepted; continue in the tool" — leaning toward *no* extra confirmation
  card, just the button, but this is a UX call worth a second opinion before
  building it.
- One `SystemRegionalPreflightModel` instance shared by choices+preview
  requests, or one per concern (two or three instances total) — the model's
  own doc comment says "one request at a time; a new request cancels
  whatever is in flight," which is wrong for driving two independent
  pickers simultaneously from one instance.
- Whether to split this into two checkpoints the way Phase 9's backend was
  (Checkpoint A: `SystemOperationModel`/`SystemManagementModel`/`shell.qml`
  wiring, verified via `qmllint`; Checkpoint B: `SystemRegionalControls.qml`
  + pane mounting + the xvfb test extension) — recommended, given how much
  is genuinely new here, but not mandatory if it turns out smaller in
  practice than this plan estimates.

---

## Verification

```bash
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-quickshell-system-management
scripts/run-tests make check-quickshell-qml
```

Manual, on a real CachyOS install — **do these on a machine you can afford to
have its timezone/locale/NTP setting changed on**. Every item below exercises
the Settings pane (pickers, confirm card, delegated-launch buttons), so none
of it is runnable against PR #32's backend-only scope alone — this is the
follow-up's (`sync-p9-settings-ui`, §5) own manual verification, listed here
because it was already written before the two-PR split and stays accurate
for what that follow-up needs to prove:

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
of the nine, but landed across two PRs: PR #32 closes the backend
(`RegionalMutation`, delegated administration, native journal watch, live
watch, the QML preflight parser/model) and every one of this phase's own
cited upstream PRs. §5's Settings UI surface is genuinely required for the
exit criterion above — "confirmed" means a user can see and act on a
confirmation, not just that the backend refuses to dispatch without one —
so Phase 6's system-management scope is **not yet** complete until §5 also
lands, on its own branch (`sync-p9-settings-ui`) and PR, planned in detail
above.
