# Sync Sprint 1 — finish system management, add the manual full-suite CI

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Surveyed against upstream
`ChrisTitusTech/dwm-titus` at **`d4c6d89`** (2026-09-16).

**Goal:** close Lyona's `ROADMAP.md` Phase 6 exit criteria for everything
upstream shipped under "system management" *except* the system-information
half (that is [Sprint 2](SYNC-SPRINT-2-SYSTEM-INFORMATION.md)), and give the
project a hosted full-suite check that can be started by hand.

| Item | Upstream | Kind | Size (code + tests) |
| --- | --- | --- | --- |
| [S1-01](#s1-01-manual-full-suite-ci-workflow) | — (Lyona request; shape from upstream `82abbf9^`) | CI | ~110 lines, literal below |
| [S1-02](#s1-02-close-the-sync-phase-9-tracking-gap) | — (Lyona `#33`) | Tracking | docs only |
| [S1-03](#s1-03-native-discovery-and-native-origins-in-qml) | `#251` (QML hunk), `#259` (QML hunk), `#261`, `#262` | Port — **never tracked before** | ~+1,300 |
| [S1-04](#s1-04-confirmed-delegated-administration) | `#266`, `#267` | Port + converge Lyona `#33` | ~+720 |
| [S1-05](#s1-05-regional-settings-model-and-controls) | `#268`, `#269` | Port + converge Lyona `#33` | ~+1,300 |
| [S1-06](#s1-06-shared-timezone-aware-minute-clock) | `#270` | Port | ~+200 |
| [S1-07](#s1-07-helper-ntp-sample-interruption-recovery-watch-time) | `#271`, `#272`, `#273` | Port (Python) | ~+1,170 |
| [S1-08](#s1-08-qml-time-observations-owner-arrivals-ntp-sampling) | `#274`, `#275`, `#276` | Port (QML) | ~+1,070 |
| [S1-09](#s1-09-package-progress-and-user-service-session-evidence) | `#291` (system-management half) | Port | ~+300 |
| [S1-10](#s1-10-carried-over-open-items) | — | Carry-over from SYNC-P5/P7/P9 | varies |

Order: S1-01 → S1-02 first (small, unblock everything). S1-03 **must** land
before S1-04/S1-05, which depend on its per-domain discovery models. S1-07
before S1-08. S1-06 and S1-09 are independent.

---

## Why this sprint rewrites part of Lyona's own `#33`

Lyona's PR `#33` (`92ec6e2`) shipped the Sync Phase 9 Settings UI from
Lyona's *own* plan (`SYNC-P9-REGIONAL-MUTATION.md` §5, now retired). Upstream
built the same feature **differently**, in `#266`–`#269`, *on top of* three
PRs Lyona never ported (`#259`, `#261`, `#262`) — and every later upstream
change in this area (`#270`–`#276`, then Sprint 2's `#277`–`#287`) builds on
upstream's shape, not Lyona's:

| Concern | Lyona `#33` | Upstream `#261`–`#269` |
| --- | --- | --- |
| Live watch owners | one `discoveryModel` | `discoveryModel`, `timeDiscoveryModel`, `localeDiscoveryModel`, `accountDiscoveryModel`, `printerDiscoveryModel` |
| Dispatch entry | `startRegional()` / `startDelegated()` | one `startNative(actionId, argument, generation)` over `startOperation()` + `originArguments()` |
| Delegated launch | `launchDelegated(action)` — **fires immediately, no confirmation** | `prepareDelegate()` → `confirmDelegate()` / `discardDelegate()`, invalidated by discovery epoch |
| Regional preview | fields on `SystemManagementModel` | separate `SystemRegionalSettingsModel.qml` |
| Controls | one `SystemRegionalControls.qml` (308 lines) | `SystemDelegateControls.qml` + `SystemRegionalControls.qml` |

The delegated-launch row is a real behavioral gap, not only structure:
`ROADMAP.md` Phase 6's exit criterion says *every privileged action is
allowlisted, **confirmed**, auditable, and cancelable*. Lyona's
`launchDelegated()` (`config/quickshell/systemmanagement/SystemManagementModel.qml:358`)
skips confirmation.

**Decision taken in this plan: converge on upstream's structure.** Keeping
Lyona's shape would mean hand-translating every one of the ~15 later upstream
PRs in this area onto a model upstream doesn't have. Converging costs one
rewrite now. Keep Lyona's `shell.qml` probe *names* where tests already use
them; add upstream's probes beside them.

### Porting method for heavily diverged QML (use for S1-03…S1-08)

`SystemManagementModel.qml` is 870 lines in Lyona and 1,501 changed lines
away from upstream `dd55e58`. Don't hand-merge hunks into it. Rebase it:

```bash
U=~/src/dwm-titus   # a clone of ChrisTitusTech/dwm-titus
F=config/quickshell/systemmanagement/SystemManagementModel.qml

# 1. What Lyona changed relative to the upstream it was ported from.
git -C "$U" show dd55e58:"$F" > /tmp/upstream-base.qml
diff -u /tmp/upstream-base.qml "$F" > /tmp/lyona-adaptations.diff

# 2. Start from upstream at the end of the item being ported, e.g. #262:
git -C "$U" show 05b74e0:"$F" > "$F"

# 3. Re-apply only the Lyona-owned adaptations from step 1, by hand:
#    Theme.dp() wrapping, `lyona` paths, the Sync Phase 3/4 corrections
#    (unwrapped monitor.command, onRunningChanged ownership clearing), the
#    Sync Phase 7 reveal()/contentY substitution. Drop the #33-only
#    startRegional/startDelegated/launchDelegated family — S1-04/S1-05
#    replace it.
```

Repeat per upstream boundary SHA (`05b74e0` → `826760a` → `08e97d3` →
`38eef6a` → `3c9f0fe`), running `make check-quickshell-system-management
check-quickshell-system-management-xvfb` at each. The lesson from Sync
Phase 7/8 still applies: **diff each cited PR on its own, both Python and
QML**, before calling an item's scope complete.

---

## S1-01: Manual full-suite CI workflow

Lyona's `c-cpp.yml` runs only the desktop smoke job — see `CHANGELOG.md`'s
"Reduce hosted CI to one Arch build and desktop smoke job" entry. Upstream
made the same cut in `#326` (already mirrored in Lyona, nothing to port). Before
that cut, upstream's `c-cpp.yml` had a `workflow_dispatch` input,
`full_validation`, that ran the whole suite on request. This item brings that
back for Lyona as its **own** workflow, so the smoke job keeps its 10-minute
budget and push/PR triggers.

**New file: `.github/workflows/full-suite.yml`**

```yaml
name: Full suite (manual)

# Manual only. The smoke job in c-cpp.yml stays the per-push gate; this is the
# occasional "run everything on a clean Arch container" check that replaced
# nothing and blocks nothing.
on:
  workflow_dispatch:
    inputs:
      target:
        description: "make target to run (default: the whole suite)"
        type: string
        default: check
      clang:
        description: "Also build dwm with clang"
        type: boolean
        default: true

permissions:
  contents: read

concurrency:
  group: full-suite-${{ github.ref }}
  cancel-in-progress: false

jobs:
  full-suite:
    name: make ${{ inputs.target }}
    runs-on: ubuntu-latest
    timeout-minutes: 90
    container:
      image: archlinux:base-devel
      # Several acceptance tests create private namespaces, a private system
      # bus, and nested Xvfb displays.
      options: >-
        --security-opt seccomp=unconfined
        --security-opt apparmor=unconfined
    defaults:
      run:
        shell: bash
    env:
      DWM_TEST_TMP_ROOT: /var/tmp/lyona-ci

    steps:
      - name: Install checkout dependency
        run: pacman -Syu --noconfirm --needed git

      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Trust the container checkout
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"

      - name: Validate the target name
        env:
          TARGET: ${{ inputs.target }}
        run: |
          # Keep workflow input out of the shell grammar: one make target name.
          [[ $TARGET =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "invalid target: $TARGET" >&2; exit 2; }

      - name: Install full validation dependencies
        run: |
          source scripts/dwm-packages.sh
          mapfile -t packages < <(
            {
              dwm_packages arch full
              dwm_packages arch ci-smoke
              dwm_packages arch qml-validation
              printf '%s\n' shellcheck shfmt archiso python-dbus \
                xorg-server-xvfb xorg-xauth xdotool dbus inotify-tools jq
            } | awk 'NF' | sort -u
          )
          # desktop-optional/gaming entries may be AUR-only; install what the
          # repositories have and let the owning tests skip the rest.
          available=()
          for package in "${packages[@]}"; do
            pacman -Si -- "$package" >/dev/null 2>&1 && available+=("$package")
          done
          pacman -S --noconfirm --needed "${available[@]}"

      - name: Prepare unprivileged runner
        run: |
          install -d -m 0700 -o nobody -g nobody /home/dwm-ci /run/dwm-ci "$DWM_TEST_TMP_ROOT"
          chown -R nobody:nobody "$GITHUB_WORKSPACE" "$DWM_TEST_TMP_ROOT"

      - name: Run make ${{ inputs.target }}
        env:
          TARGET: ${{ inputs.target }}
        run: |
          runuser -u nobody -- env HOME=/home/dwm-ci XDG_RUNTIME_DIR=/run/dwm-ci \
            scripts/run-tests make "$TARGET" 2>&1 | tee /var/tmp/lyona-ci/full-suite.log
          exit "${PIPESTATUS[0]}"

      - name: Upload log
        if: always()
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: full-suite-log
          path: /var/tmp/lyona-ci/full-suite.log
          if-no-files-found: ignore

  clang-build:
    name: clang build
    if: inputs.clang
    runs-on: ubuntu-latest
    timeout-minutes: 15
    container: archlinux:base-devel
    steps:
      - name: Install checkout dependency
        run: pacman -Syu --noconfirm --needed git

      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Install clang and build dependencies
        run: |
          source scripts/dwm-packages.sh
          mapfile -t packages < <(dwm_packages arch build | awk 'NF' | sort -u)
          pacman -S --noconfirm --needed clang "${packages[@]}"

      - name: Build with clang
        run: make clean all CC=clang
```

**`CONTRIBUTING.md`** — add under the existing CI/validation guidance:

```diff
+### Manual full-suite run
+
+Hosted CI runs only the desktop smoke job on every push. To run the whole
+suite on a clean Arch container, open **Actions → Full suite (manual) → Run
+workflow**. Leave `target` as `check` for everything, or name one `make`
+target (for example `check-system-management`) to rerun a single gate. The
+log is attached to the run as `full-suite-log`. A passing manual run does not
+replace local `scripts/run-tests make check` before merge.
```

**`CHANGELOG.md`** (`### Added`):

```diff
+- Add a manual `Full suite (manual)` GitHub Actions workflow
+  (`.github/workflows/full-suite.yml`) that runs `scripts/run-tests make
+  check` (or one named target) as an unprivileged user in an
+  `archlinux:base-devel` container, uploads the log, and optionally builds
+  dwm with clang. Push and pull-request CI is unchanged.
```

Expect the first run to find environment gaps (tests that assume a real
logind seat, `check-archiso` needing loop devices). Fix by making the owning
test **skip with exit 77** when its prerequisite is missing, the convention
`check-quickshell-large-surfaces-xvfb` already uses, rather than by pruning
`make check`. Record the first green run's URL in `docs/evidence/`.

---

## S1-02: Close the Sync Phase 9 tracking gap

`#33` merged the Settings UI, but `TASKS.md`'s Sync Phase 9 section still
reads `- [ ] **Follow-up: Sync Phase 9 Settings UI wiring** … Not started.`,
and `CHANGELOG.md` has no entry. That's the same gap Sync Phase 5 had.

```diff
-- [ ] **Follow-up: Sync Phase 9 Settings UI wiring** (`sync-p9-settings-ui`,
-  plan in `SYNC-P9-REGIONAL-MUTATION.md` §5) — `SystemOperationModel.
+- [x] **Follow-up: Sync Phase 9 Settings UI wiring** (`sync-p9-settings-ui`,
+  plan in `SYNC-P9-REGIONAL-MUTATION.md` §5, retired) — `SystemOperationModel.
 …
-  exercise all of it. Not started.
+  exercise all of it. — **Landed in `92ec6e2` (PR #33).** Superseded in
+  structure by Sync Sprint 1 S1-03…S1-05 (`docs/SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`),
+  which converges it onto upstream `#261`–`#269`.
```

Verify against the shipped code before ticking the box: confirm
`startRegional`, `prepareRegional` and `SystemRegionalControls` exist, and that
`scripts/run-tests make check-quickshell-system-management-xvfb` passes. Don't
rely on this doc.

### Manual real-system checklist (moved from the retired SYNC-P9 doc)

Run on a CachyOS machine whose timezone, locale and NTP settings you can
afford to change. Run it again after S1-05/S1-08 land, because they change the
surface.

- Preview a timezone change, confirm it, and check `timedatectl status`. The pane agrees after Reload.
- Preview a change, run `timedatectl set-timezone <other>` in a terminal, then confirm. It must be refused as a conflict.
- Toggle NTP off/on. `timedatectl show -p NTP` matches at each step.
- Change locale. `localectl status` matches, and no `LANG=` the session needs is dropped.
- Kill `dwm-system-management` between dispatch and verification. The pane shows "outcome unknown, refresh before retrying", never success.
- Each delegated button either launches its tool or shows an honest `unsupported`/`unavailable` (D-3).
- With Settings → System open, run `timedatectl set-ntp false`/`true` externally. The pane updates without Reload.
- Closed-CPU baseline with all watch domains subscribed stays flat.

---

## S1-03: Native discovery and native origins in QML

**Never assigned to a sync phase.** The Python halves of `#250`, `#251` and
`#259` were ported inside Sync Phase 9 (`retain_native_journal_owner`,
`NativeJournalEvents`, `watch_native_journal_operation`,
`NativeSnapshotSources`, `build_native_snapshot` all exist). Their **QML
halves**, and all of `#261`/`#262`, are missing. Verified by symbol:

| Upstream | Missing in Lyona |
| --- | --- |
| `#251` `4b786b8` | `SystemManagementModel.qml` +4/−3 (native journal lifecycle); `run_operation_control` (Python — confirm renamed vs missing) |
| `#259` `bc673eb` | `SystemManagementModel.qml` +199/−10; `tests/qml/SystemNativeSnapshot.qml` (new, 206) |
| `#261` `5192813` | `discoveryModels`, `discoveryReady`, `nativeProviderView`, `nativeStateView`, `stateDiscovery`; `tests/qml/SystemNativeDiscovery.qml` (new, 248); fixtures `system-discovery-provider.py`, `system-native-discovery-provider.py`, `system-update-ui-provider.py` |
| `#262` `05b74e0` | `startNative`, `startOperation`, `originArguments`, `invalidateActionDiscovery`; `SystemOperationProtocol.js` +3/−1; `tests/qml/SystemNativeActionOwner.qml`, `SystemOperationParser.qml`, `SystemOperationOwner.qml`; fixture `system-native-action-provider.py` |

```bash
for c in 4b786b8 bc673eb 5192813 05b74e0; do
  git -C "$U" show "$c" -- config/quickshell tests/qml tests/fixtures \
    tests/test-quickshell-system-management-xvfb.sh tests/test-quickshell-system-management.sh
done > /tmp/s1-03.diff
```

**Lyona adaptations**

- Upstream's `tests/qml/*.qml` are bespoke `ShellRoot` harnesses. Lyona's
  convention is `tests/qml/tst_*.qml` under `qmltestrunner`, as in
  `tst_system_regional_preflight_protocol.qml`. Port the *assertions* into
  `tst_system_native_snapshot.qml`, `tst_system_native_discovery.qml`,
  `tst_system_native_action_owner.qml` and `tst_system_operation_parser.qml`.
  Where a harness needs a live process (the `*-provider.py` fixtures), keep it
  in `test-quickshell-system-management-xvfb.sh` instead.
- Fixture XDG paths: `dwm-titus` → `lyona` (Sync Phase 9 already hit this in
  `system-regional-owner-bus.py`).
- `SystemOperationModel.startRegional()`/`startDelegated()` from `#33` become
  thin wrappers over `startNative()` for one commit, then are removed in S1-05
  once no caller remains.

This also closes the **`SystemOperationParser.qml` coverage gap** Sync Phase 7
deferred.

---

## S1-04: Confirmed delegated administration

Upstream `#266` (`826760a`), `#267` (`c63d525`).

| File | Change |
| --- | --- |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | `nativeConfirmation`, `nativeConfirmationMessage`, `dispatchingNative`; `delegateDiscovery()`, `delegateContextReason()`, `delegateActionReason()`, `prepareDelegate()`, `discardDelegate()`, `invalidateNativeConfirmation()`, `confirmDelegate()`; `onInvalidated` hooks on the account/printer discovery models |
| `config/quickshell/settings/SystemDelegateControls.qml` | **New** (221) |
| `config/quickshell/settings/SystemSettingsPane.qml` | Mount `SystemDelegateControls` |
| `config/quickshell/settings/SystemUpdateControls.qml` | +6/−3 (mutual exclusion with native confirmation) |
| `config/quickshell/settings/SystemRegionalControls.qml` | **Remove** Lyona's delegated-launch `Repeater` (the `required property string modelData` / `nativeActionReason(modelData)` block, around `:301`) |
| `tests/fixtures/system-delegate-confirmation-provider.py` | **New** |
| `tests/qml/SystemDelegateConfirmation.qml`, `SystemDelegateUi.qml` | **New** → `tst_*` form |
| `docs/src/settings.md` | Upstream's `docs/src/content/settings.md` +10 → Lyona's mdBook page |

Core of the model change (from `826760a`), replacing Lyona's
`launchDelegated()`:

```diff
-    // Delegated actions (accounts-open/password-open/printers-open/
-    // sources-open) have no preview step -- launch_delegated_tool() either
-    // starts a fixed, already-trusted executable or the action was already
-    // reported unavailable/unsupported by nativeActionReason().
-    function launchDelegated(action) {
-        const reason = root.nativeActionReason(action);
-        if (reason.length > 0) {
-            root.regionalConfirmMessage = reason;
-            return false;
-        }
-        return operationModel.startDelegated(action);
-    }
+    function delegateDiscovery(actionId) {
+        if (actionId === "accounts-open" || actionId === "password-open") return accountDiscoveryModel;
+        if (actionId === "printers-open") return printerDiscoveryModel;
+        if (actionId === "sources-open") return discoveryModel;
+        return null;
+    }
+
+    function delegateContextReason(actionId) {
+        const monitor = root.delegateDiscovery(actionId);
+        if (monitor === null) return "This delegated action is not supported.";
+        if (!root.settingsVisible) return "Open System Settings to prepare this action.";
+        if (root.snapshotOwned || root.snapshotPending || root.requiredPending || root.discoveryBatch
+                || !monitor.visible || !monitor.ready || monitor.failed || !monitor.cycle.enabled
+                || monitor.cycle.phase !== "idle" || monitor.cycle.unresolved)
+            return "Wait for fresh provider status, or reload status to retry.";
+        if (!root.validGeneration(root.generation) || !operationModel.canStart)
+            return "An operation or its recovery still owns the system workflow.";
+        const action = root.actions.find(item => item.id === actionId);
+        if (!action || action.availability !== "available")
+            return action && action.detail.length > 0 ? action.detail : "The provider did not offer this action.";
+        return "";
+    }
+
+    function delegateActionReason(actionId) {
+        if (root.dispatchingUpdate || root.dispatchingNative || root.updateConfirmation !== null)
+            return "Finish or dismiss the current confirmation first.";
+        return root.delegateContextReason(actionId);
+    }
+
+    function prepareDelegate(actionId) {
+        if (root.nativeConfirmation !== null) return false;
+        const reason = root.delegateActionReason(actionId);
+        if (reason.length > 0) {
+            root.nativeConfirmationMessage = reason;
+            return false;
+        }
+        const pending = { actionId: actionId, generation: root.generation,
+            requestGeneration: root.requestGeneration, epoch: root.delegateDiscovery(actionId).cycle.epoch };
+        root.dispatchingNative = true;
+        root.nativeConfirmationMessage = "";
+        // Reentrant closure or discovery callbacks may retire this preparation.
+        if (root.delegateContextReason(actionId) === "" && pending.generation === root.generation
+                && pending.requestGeneration === root.requestGeneration
+                && pending.epoch === root.delegateDiscovery(actionId).cycle.epoch)
+            root.nativeConfirmation = pending;
+        root.dispatchingNative = false;
+        return root.nativeConfirmation === pending;
+    }
+
+    function discardDelegate() {
+        root.nativeConfirmation = null;
+        root.nativeConfirmationMessage = "";
+    }
+
+    function invalidateNativeConfirmation(domain) {
+        const pending = root.nativeConfirmation;
+        if (pending === null) return;
+        const monitor = root.delegateDiscovery(pending.actionId);
+        if (domain !== "" && (monitor === null || monitor.domain !== domain)) return;
+        root.nativeConfirmationMessage = "Provider state changed. Reload status and confirm again.";
+        root.nativeConfirmation = null;
+    }
+
+    function confirmDelegate() {
+        const pending = root.nativeConfirmation;
+        if (pending === null || root.dispatchingUpdate || root.dispatchingNative) return false;
+        if (root.delegateActionReason(pending.actionId) !== "") {
+            root.invalidateNativeConfirmation("");
+            return false;
+        }
+        root.dispatchingNative = true;
+        root.nativeConfirmation = null;
+        // Recheck after prompt callbacks; the operation owner checks its own
+        // source ownership again before constructing the fixed empty argv.
+        const monitor = root.delegateDiscovery(pending.actionId);
+        const current = root.delegateContextReason(pending.actionId) === ""
+            && pending.generation === root.generation && pending.requestGeneration === root.requestGeneration
+            && monitor !== null && pending.epoch === monitor.cycle.epoch;
+        const started = current && operationModel.startNative(pending.actionId, "", "");
+        root.nativeConfirmationMessage = started ? "" : "Provider state changed. Reload status and confirm again.";
+        root.dispatchingNative = false;
+        return started;
+    }
```

**D-3 still holds:** `accounts-open` and `sources-open` stay permanently
`unsupported` on Arch. `SystemDelegateControls.qml` must render the helper's
`detail`, so those two show *why* rather than a disabled button with no
explanation. Add an xvfb assertion for that text.

---

## S1-05: Regional settings model and controls

Upstream `#268` (`08e97d3`), `#269` (`2b94db9`).

| File | Change |
| --- | --- |
| `config/quickshell/systemmanagement/SystemRegionalSettingsModel.qml` | **New** (182). Takes over preview/confirm state from `SystemManagementModel` |
| `config/quickshell/systemmanagement/SystemManagementModel.qml` | +25/−2; **remove** `#33`'s `regionalPreview`, `regionalPreviewError`, `regionalPreviewPending`, `regionalConfirmMessage`, `dispatchingRegional`, `prepareRegional()`, `regionalPreviewReceived()`, `discardRegional()`, `confirmRegional()` |
| `config/quickshell/settings/SystemRegionalControls.qml` | Replace Lyona's 308-line version with upstream's 354-line one, then re-apply `Theme.dp()` wrapping |
| `config/quickshell/systemmanagement/SystemOperationModel.qml` | Remove `startRegional()`/`startDelegated()` wrappers left by S1-03 |
| `config/quickshell/shell.qml` | Keep `systemManagementRegionalPreview()`/`Confirm()` probe names (tests use them) but route them to `SystemRegionalSettingsModel`; add upstream's probes |
| `scripts/dwm-system-management` | `#269`'s +12/−1 in `tests/test-system-management.py` only; confirm no helper change |
| `tests/fixtures/system-regional-settings-provider.py` | **New** (102 + 13) |
| `tests/qml/SystemRegionalSettings.qml`, `SystemRegionalUi.qml` | **New** → `tst_*` |
| `tests/test-quickshell-system-management-xvfb.sh` | Replace `#33`'s regional stub assertions with upstream's `#268`/`#269` blocks (+59, +42) |

`docs/P6-REGIONAL-UI-EVIDENCE.md` from upstream isn't ported. Record Lyona's
own evidence under `docs/evidence/` instead.

---

## S1-06: Shared timezone-aware minute clock

Upstream `#270` (`f69a38e`). Clean shape, small.

| File | Change |
| --- | --- |
| `config/quickshell/core/ClockModel.qml` | **New** (54) — one minute-aligned timer, timezone-aware, shared |
| `config/quickshell/panel/DwmPanel.qml` | Use the shared clock (+1/−1) |
| `config/quickshell/settings/SettingsWindow.qml` | +2 |
| `config/quickshell/settings/SystemSettingsPane.qml` | +9 (show current time beside the timezone row) |
| `config/quickshell/shell.qml` | +4/−3 (own the singleton instance) |
| `tests/qml/SharedClock.qml` | **New** → `tests/qml/tst_shared_clock.qml` |

```bash
git -C "$U" show f69a38e -- config/quickshell tests/qml tests/test-quickshell-system-management*.sh
```

Check first whether Lyona's panel clock already uses a format from
`config/*.toml` that the shared model must keep honoring. Grep `DwmPanel.qml`
for the current `Timer`.

---

## S1-07: Helper NTP sample, interruption recovery, watch-time

Upstream `#271` (`ebf7a31`), `#272` (`3bef09c`), `#273` (`75ca9c2`). Python
only. Lyona's helper is exactly upstream `dd55e58` plus 1,176 lines of Lyona
adaptation, so these three apply as **patch-then-fix**:

```bash
for c in ebf7a31 3bef09c 75ca9c2; do
  git -C "$U" show "$c" -- scripts/dwm-system-management tests/test-system-management.py tests/fixtures \
    | git apply --3way
  scripts/run-tests /usr/bin/python3 tests/test-system-management.py || break
done
```

| Upstream | Adds |
| --- | --- |
| `#271` | `read_ntp_sample()`, `ntp_sample_output()`, `ntp_sample_command()`; `ntp-sample` CLI (`ntp-sample-protocol\t1\t0`); `system-regional-read-bus.py` +73 |
| `#272` | Regional recovery keeps `interrupted` evidence across restart; new `tests/fixtures/system-regional-interruption-bus.py` (192) |
| `#273` | `time-discovery` service kind; `watch-time` CLI; fixtures `system-regional-read-bus.py` +30, `system-update-events-bus.py` +9 |

**Lyona adaptation:** `timedate1` NTP properties on Arch come from
`systemd-timesyncd` unless the user installed `chrony`/`ntpd`.
`read_ntp_sample()` reads `org.freedesktop.timesync1`. If that's absent, the
sample must return `unavailable`, not `failed`. Add one test that runs with no
`timesync1` name on the private bus.

---

## S1-08: QML time observations, owner arrivals, NTP sampling

Upstream `#274` (`0c97c83`), `#275` (`38eef6a`), `#276` (`3c9f0fe`). Depends
on S1-05 (`SystemRegionalSettingsModel`) and S1-07 (`watch-time`,
`ntp-sample`).

| File | Change |
| --- | --- |
| `config/quickshell/systemmanagement/SystemRegionalPreflightProtocol.js` | `#274` +23/−8 — reject non-finite time observations |
| `config/quickshell/systemmanagement/SystemRegionalPreflightModel.qml` | `#274` +9/−1 |
| `config/quickshell/systemmanagement/SystemTimeReconciliationModel.qml` | **New** `#275` (186) + `#276` (+90/−5) |
| `config/quickshell/systemmanagement/SystemProviderDiscovery.qml` | `#275` +7/−3 — owner-arrival reconciliation |
| `config/quickshell/systemmanagement/SystemRegionalSettingsModel.qml` | `#275` +47, `#276` +1 |
| `config/quickshell/settings/SystemRegionalControls.qml` | `#275` +44/−2, `#276` +2/−1 |
| `tests/qml/tst_system_regional_preflight_protocol.qml` | Extend with `#274`'s `SystemRegionalPreflightParser.qml` cases (+56) |
| `tests/qml/SystemTimeReconciliation.qml`, `SystemNtpSampling.qml` | **New** → `tst_*` |
| `tests/fixtures/system-native-discovery-provider.py` | `#275` +29/−3, `#276` +19/−1 |

This also closes the **`SystemRegionalPreflightOwner.qml` coverage gap** Sync
Phase 9 deferred: `#274` modifies that harness, so port it now as
`tst_system_regional_preflight_owner.qml` with its provider fixture.

### Implementation notes (as actually built, correcting the two items above)

`SystemRegionalPreflightModel`/`SystemTimeReconciliationModel`/`SystemManagementModel`
all import `qs.core`/instantiate Quickshell-provided types (`Scope`, `Process`,
`SystemClock`, etc.) — confirmed empirically (S1-03, re-confirmed here) that
these **cannot** be instantiated under bare `qmltestrunner`
(`module "qs.systemmanagement" is not installed` outside a real Quickshell
process). Two corrections to the table above:

- `tests/qml/SystemRegionalPreflightOwner.qml` (ported from upstream
  essentially unchanged, plus the new `time-status`/`ntp-sample` modes) is
  **not** translated into `tst_system_regional_preflight_owner.qml` for
  qmltestrunner. It stays a bespoke harness, spawned directly via
  `quickshell --no-duplicate --path .../shell.qml` from
  `tests/test-quickshell-system-management-xvfb.sh` (the *same* mechanism
  upstream's own xvfb script uses for this exact file) alongside its new
  `tests/fixtures/system-regional-preflight-provider.py`. Only the parser-level
  cases (pure `.js`, no Quickshell types) go into
  `tst_system_regional_preflight_protocol.qml`.
- `SystemTimeReconciliation.qml`/`SystemNtpSampling.qml`/`SystemRegionalUi.qml`
  are upstream's own bespoke per-scenario harnesses, each paired with its own
  Python fixture (`system-discovery-provider.py`,
  `system-native-discovery-provider.py`, `system-provider-discovery.py`,
  `system-regional-settings-provider.py`, `system-update-ui-provider.py`) that
  do not exist in Lyona and were not ported — Lyona's xvfb test already
  exercises the equivalent behavior (owner-arrival reconciliation, on-demand
  and periodic NTP sampling) against the *real* `SystemManagementModel`
  mounted in `shell.qml`, via new `systemManagementTimeReconciliationBlocked`/
  `Detail`/`systemManagementTimeSampleNow` IPC probes and a `watch-time` stub
  case that emits one deterministic `owner-arrived` record.

**Bug found by `SystemRegionalPreflightOwner.qml`'s own port** (the coverage
gap it was meant to close): `SystemRegionalPreflightProtocol.js`'s
`consume()` threw a `TypeError` on an empty (`byteLength === 0`)
`StdioCollector` buffer — a real delivery a reused collector can produce when
its process restarts or fails to start (exit 127), never previously exercised
against a real Quickshell process. Fixed by treating a `0`-byte buffer as a
no-op; regression-covered by
`test_empty_buffer_is_a_no_op` in `tst_system_regional_preflight_protocol.qml`.

---

## S1-09: Package progress and user-service session evidence

The system-management half of upstream `#291` (`d359a4f`). The Settings and
autostart half goes to [Sprint 3](SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md#s3-05-settings-readiness-and-startup-work).

| File | Change |
| --- | --- |
| `scripts/dwm-system-management` | +92/−5: `PACKAGEKIT_INFO_PHASE`/`PACKAGEKIT_STATUS_PHASE`; `OperationStream.item_progress()` (bounded at 4,096 records, ephemeral, never journaled); `on_item_progress()`; the terminal `error` record carries `operation.detail`; logind `display_session()` fallback so user-service launches (`systemd --user`) still get restart evidence when `NoSessionForPID` |
| `config/quickshell/systemmanagement/SystemOperationProtocol.js` | +9/−1: `package-progress` record parser (`item`, `itemRecords`, ≤ 4,097) |
| `config/quickshell/systemmanagement/SystemOperationModel.qml` | +5 |
| `config/quickshell/settings/SystemUpdateControls.qml` | +37/−24: show current package + phase; keep acknowledgment-failure recovery text visible |
| `config/quickshell/settings/SystemSettingsPane.qml` | +20/−5 |
| `tests/test-system-management.py` | +98/−1 |
| `tests/qml/SystemOperationParser.qml`, `SystemUpdateUi.qml` | +14, +43 → fold into S1-03's `tst_system_operation_parser.qml` and a new `tst_system_update_ui.qml` |
| `tests/test-quickshell-update-ui-xvfb.sh` | **New** (65) → register `check-quickshell-update-ui-xvfb` in `Makefile` (`check:` list, `.PHONY`) |

**Lyona adaptation:** the PackageKit `alpm` backend emits `Package` signals
with `info` codes. Whether it emits `ItemProgress` at all is **unverified**. If
it doesn't, the UI shows the package name with `percent: unknown`, which is
the designed fallback. Record which one a real `pkcon update` produces on
CachyOS, in `docs/evidence/`.

---

## S1-10: Carried-over open items

Carried from the retired SYNC-P5/P7/P9 documents so they aren't lost:

| Item | Origin | Action this sprint |
| --- | --- | --- |
| **D-4** — does `pacman -Sup --dbpath "$CHECKUPDATES_DB"` stay read-only (no root, no live lock) on CachyOS? | SYNC-P2 §6 | Run on a real install: `strace -f -e trace=openat,flock` and a `pacman.lck` watch. Record the result in `UPSTREAM-SYNC.md` Open decisions. |
| `JOURNAL_RESTART_SESSION_STRENGTH` lacks `unknown` | SYNC-P5 | **Close as not-a-gap.** Upstream `d4c6d89` still has only `none`/`session`/`security-session`. Nothing in Lyona or upstream sets session `unknown`. Remove the note from `UPSTREAM-SYNC.md`. |
| `SystemOperationParser.qml` harness not ported | SYNC-P7 | Closed by S1-03 |
| `SystemRegionalPreflightOwner.qml` / `SystemNativeDiscovery.qml` live-process tests not ported | SYNC-P9 | Closed by S1-08 / S1-03 |
| Live PackageKit / `timedate1` / `locale1` manual checks | SYNC-P1…P9 | S1-02 checklist + S1-09 evidence |

---

## Verification

```bash
scripts/run-tests make clean all check-shell check-format check-quickshell-qml
scripts/run-tests /usr/bin/python3 tests/test-system-management.py
scripts/run-tests make check-quickshell-system-management \
  check-quickshell-system-management-xvfb check-quickshell-system-discovery-cycle \
  check-quickshell-update-ui-xvfb
QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
scripts/run-tests make check-quickshell-large-surfaces-xvfb   # closed-CPU baseline stays flat
```

Then start **Full suite (manual)** from S1-01 on the sprint branch.

## Closes

- `ROADMAP.md` Phase 6: "Every privileged action is allowlisted, **confirmed**,
  auditable, and cancelable" — for delegated administration (S1-04).
- `ROADMAP.md` Phase 6 outcome: "Date, time, timezone, locale, user-account,
  printer, and software-source entry points".
- Upstream `#251`(QML), `#259`(QML), `#261`, `#262`, `#266`–`#276`, `#291`(system half).
