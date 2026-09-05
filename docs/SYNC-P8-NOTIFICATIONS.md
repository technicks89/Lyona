# Sync Phase 8 — managed notification policy

Upstream: [`#204`](https://github.com/ChrisTitusTech/dwm-titus/pull/204)
`feat: add managed notification policy` (`ad47c20`, +1239 / -86).
Depends on [Phase 4](SYNC-P4-A11Y-CAPABILITIES.md).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Do-not-disturb, popup timeout, and per-urgency suppression — while preserving the
existing D-Bus notification owner.

## Context

Lyona's `config/quickshell/notifications/NotificationModel.qml` has **no policy layer
at all**: no do-not-disturb, no timeout control, no suppression. Popups fire
unconditionally. This phase is purely additive to that file.

`TASKS.md:96` is the open checkbox:

> - [ ] Add notification behavior controls that preserve the existing D-Bus owner, …

The "preserve the existing D-Bus owner" clause is the constraint that shapes the
whole change. Quickshell claims `org.freedesktop.Notifications` at startup; a policy
that required re-registering would drop notifications during every save. Upstream's
design keeps the owner untouched and gates *display*, not *reception*.

## Files

| File | Upstream | Note |
| --- | --- | --- |
| `config/quickshell/notifications/NotificationModel.qml` | +185 | The policy layer |
| `config/quickshell/settings/AppearanceSettingsPane.qml` | +165 | New "Notifications" group |
| `config/quickshell/settings/SettingsModel.qml` | +19 | Owner watch + section wiring |
| `config/quickshell/settings/SettingsWindow.qml` | +4 | Pane wiring |
| `config/quickshell/shell.qml` | +29 | IPC probes for the xvfb tests |
| `scripts/dwm-settings-provider` | +118 | `watch-notifications`, owner capability |
| `scripts/autostart.sh` | +6 | Seed the policy directory before the shell starts |
| `tests/test-quickshell-notifications.sh` | +42 | Rewrite onto `tests/lib.sh` |
| `tests/test-autostart.sh` | +27 | Rewrite onto `tests/lib.sh` |
| `tests/test-quickshell-large-surfaces-xvfb.sh` | +254 | Rewrite onto `tests/lib.sh` |
| `docs/P5-NOTIFICATION-POLICY.md` | 78 new | Rewrite for Lyona paths |
| `docs/src/configuration.md`, `docs/src/settings.md` | +15 | mdBook paths, not `docs/src/content/` |

## `config/quickshell/notifications/NotificationModel.qml`

The new state, with the `configDir` adapted to Lyona:

```qml
    property bool doNotDisturb: false
    property int popupTimeoutMs: 6000
    property string policyState: "loading"
    property string policyDetail: "Loading notification policy"
    property bool policySaving: false
    property bool policyReloadPending: false
    property bool confirmedDoNotDisturb: false
    property int confirmedPopupTimeoutMs: 6000
    readonly property var popupTimeoutOptions: [4000, 6000, 10000]
    readonly property bool popupSuppressed: root.policyState === "loading"
        || root.policyState === "partial"
        || root.policyState === "unavailable"
        || root.policySaving || root.doNotDisturb
    readonly property bool policyMutationReady: !root.policySaving
        && (root.policyState === "available" || root.policyState === "defaults")
    readonly property bool policyResetReady: !root.policySaving
        && root.policyState !== "loading"
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configuredConfigHome: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: root.configuredConfigHome.startsWith("/")
        ? root.configuredConfigHome : root.homeDir + "/.config"
    readonly property string configDir: root.configHome + "/lyona"
    readonly property string policyPath: root.configDir + "/notification-settings.json"
```

> The only change from upstream is `"/lyona"` in place of `"/dwm-titus"`, matching
> `AppearanceModel.qml:165-187`.

`popupSuppressed` is the fail-closed decision and the reason this is worth porting
rather than reimplementing: **`loading`, `partial` and `unavailable` all suppress**.
An unreadable or half-written policy file shows no popups rather than defaulting to
"show everything" — which is what a user who set do-not-disturb and then hit a
corrupt file would otherwise get.

The behaviour functions:

```qml
    function validPopupTimeout(value) {
        return root.popupTimeoutOptions.indexOf(value) >= 0;
    }

    function usePolicyDefaults() {
        root.doNotDisturb = false;
        root.popupTimeoutMs = 6000;
    }

    function dismissNonCriticalPopups() {
        const current = root.notifications.slice();
        for (const item of current) {
            if (item.urgencyName !== "critical") root.closeItem(item, false);
        }
    }

    function applyDoNotDisturb(enabled) {
        root.doNotDisturb = enabled;
        if (enabled) root.dismissNonCriticalPopups();
        // … persist, then confirm
    }
```

`dismissNonCriticalPopups` copies with `.slice()` before iterating because
`closeItem` mutates `root.notifications`; iterating the live list skips every other
element. `urgencyName !== "critical"` is the exemption — a critical notification
survives do-not-disturb, which is the whole point of the urgency level.

`popupTimeoutOptions` is a fixed whitelist, and `validPopupTimeout` gates every
write. An arbitrary integer from a hand-edited JSON file cannot become a popup
timeout.

## `config/quickshell/settings/SettingsModel.qml`

Owner-state watch, wired to the `appearance` section only — it runs while that pane
is open and stops when it closes:

```diff
     function activateSection(id) {
         displayWatchProcess.running = id === "displays" && root.visible;
         inputWatchProcess.running = id === "input" && root.visible;
+        notificationOwnerWatchProcess.running = id === "appearance" && root.visible;
```

```diff
+        if (id === "appearance") root.refreshCapabilities();
         if (id === "appearance" && root.accessibilityModel) root.accessibilityModel.refresh();
```

```diff
         displayWatchProcess.running = false;
         inputWatchProcess.running = false;
+        notificationOwnerWatchProcess.running = false;
```

```diff
+    Process {
+        id: notificationOwnerWatchProcess
+        command: Commands.settingsProviderCommand("watch-notifications", [])
+        running: false
+        stdout: SplitParser { onRead: notificationOwnerSettleTimer.restart() }
+    }
```

> **Deviation from upstream (reuse).** Upstream adds this as a raw `Process` plus a
> settle `Timer`, matching the `displayWatchProcess` / `inputWatchProcess` pairs
> already in the file. Lyona has `core/WatchedProcess.qml` for exactly this shape.
> Two options, and the choice belongs to whoever implements the phase:
>
> - **Match the file** — port as written. `SettingsModel.qml` already has two
>   hand-rolled watch pairs; a third is locally consistent and the diff stays
>   reviewable against upstream.
> - **Convert all three** in a separate follow-up commit, so the conversion is
>   reviewed as a refactor rather than smuggled into a feature.
>
> Do not do both in one commit. The recommendation is to port as written here and
> open the conversion separately.

## `scripts/dwm-settings-provider`

Adds `watch-notifications` (the D-Bus owner watch backing the `Process` above) and
folds notification-owner state into the capability records from
[Phase 4](SYNC-P4-A11Y-CAPABILITIES.md). Keep the field validation established
there — bounded lengths, whitelisted states, reject on any malformed row.

## `scripts/autostart.sh`

Six lines: create `~/.config/lyona` before the shell starts, so a first-run session
does not race `Component.onCompleted`'s `mkdir -p`. Lyona's `autostart.sh` already
seeds other config directories; extend that block rather than adding a new one.

## Verification

```bash
scripts/run-tests make check-quickshell-qml
scripts/run-tests make check-quickshell-notifications
scripts/run-tests make check-session-guards
scripts/run-tests make check-quickshell-large-surfaces-xvfb
scripts/run-tests make check-settings
```

Manual, in a live session:

1. `notify-send "test"` — popup appears.
2. Enable do-not-disturb in Settings → Appearance → Notifications. `notify-send`
   again: no popup, but the notification is still in history — the D-Bus owner never
   stopped receiving.
3. `notify-send -u critical "urgent"` with do-not-disturb on — **must still appear**.
4. Enable do-not-disturb while three popups are on screen: the non-critical ones
   dismiss, a critical one stays.
5. Change the popup timeout to 4000 ms and confirm the next popup dismisses sooner.
6. Corrupt `~/.config/lyona/notification-settings.json` (write `{`), reopen
   Settings: the policy reports `partial`, popups are suppressed, and the pane
   offers a reset that repairs the file.
7. Restart Quickshell and confirm the policy survives.
8. Closed-CPU baseline with Settings → Appearance open — the owner watch must not
   spin.

## Closes

`TASKS.md:96` — *Add notification behavior controls that preserve the existing D-Bus
owner, …*
