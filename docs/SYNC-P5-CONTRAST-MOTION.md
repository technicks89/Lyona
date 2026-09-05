# Sync Phase 5 — contrast and motion policy

Upstream: [`#201`](https://github.com/ChrisTitusTech/dwm-titus/pull/201)
`Phase 5: add contrast and motion policy` (`eed7625`, +1138 / -48).
Depends on [Phase 4](SYNC-P4-A11Y-CAPABILITIES.md).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

This is the phase with the largest Lyona-specific adaptation, because it edits
`Theme.qml` — the one file `2a49ffd Fixed DPI settings` rewrote.

## Files

| File | Upstream | Status |
| --- | --- | --- |
| `scripts/dwm-accessibility-settings` | 566 new | New; ports near-verbatim |
| `config/quickshell/accessibility/AccessibilityModel.qml` | 222 new | New; watcher replaced with `WatchedProcess` |
| `config/quickshell/core/Theme.qml` | +32 / -14 | **Adapted** — see below |
| `config/quickshell/core/Commands.qml` | +4 | Straight add |
| `config/quickshell/shell.qml` | +5 | Straight add |
| `Makefile` | +12 | Three registration points plus a check target |
| `tests/test-dwm-accessibility-settings.sh` | 250 new | Rewrite onto `tests/lib.sh` |
| `tests/test-quickshell-accessibility.sh` | 51 new | Rewrite onto `tests/lib.sh` |
| `docs/P5-ACCESSIBILITY-POLICY.md` | 60 new | Rewrite for Lyona paths |

## `scripts/dwm-accessibility-settings`

Ports near-verbatim; only the global path/name rules apply.

| Property | Value |
| --- | --- |
| Config file | `~/.config/lyona/accessibility.conf` (upstream: `~/.config/dwm-titus/`) |
| Lock | `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}/dwm-accessibility-settings.lock` |
| Protocol header | `accessibility-settings-protocol\t1\t0` |
| Actions | `status \| watch \| set {contrast\|motion} VALUE \| reset` |
| Values | `contrast:{standard,high}`, `motion:{full,reduced}` |
| Bounds | `max_config_size=4096`, `max_restore_attempts=8` |

The header block ports as:

```bash
config_home=${XDG_CONFIG_HOME:-}
[[ $config_home == /* ]] || config_home=${HOME:?HOME is required for XDG_CONFIG_HOME fallback}/.config
config_dir=$config_home/lyona
config_file=$config_dir/accessibility.conf
runtime_base=${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}
[[ $runtime_base == /* ]] || {
	printf 'dwm-accessibility-settings: XDG_RUNTIME_DIR must be absolute\n' >&2
	exit 1
}
lock_file=$runtime_base/dwm-accessibility-settings.lock
```

Keep `config_dir_safe()` — the `stat` ownership and `022`-mode check — unchanged.
It is the reason a world-writable config directory cannot make the shell render an
attacker's contrast policy, and it matches the convention already in
`dwm-settings-font:738` and `dwm-settings-toolkit:814`.

## `config/quickshell/core/Commands.qml`

Add next to `settingsToolkitCommand`:

```qml
    function accessibilitySettingsCommand(action, args) {
        return helperCommand("dwm-accessibility-settings", action, args, true);
    }
```

`preferManaged: true`, matching every other settings helper — the installed tree
under `$XDG_DATA_HOME/lyona/scripts` wins over anything on `PATH`.

## `config/quickshell/core/Theme.qml` — the adapted hunk

### Invariant: theme hot reload keeps working

**Non-negotiable for this phase.** `applyAppearanceColors()` (`Theme.qml:58-88`) is
the entry point for every live theme change — `dwm-settings-theme apply`, the
Control Center theme switcher, and the `themes.toml` watcher. It assigns fifteen
palette properties, `root.textMuted` among them at `Theme.qml:69`.

Upstream's `#201` converts `textMuted` into a `readonly` derived property. QML
cannot assign to `readonly`, so a straight port makes `applyAppearanceColors()`
throw on its tenth assignment — every theme change after this lands would fail
part-way, leaving the palette half-updated and the shell in a mixed colour state.

The rule for this phase, and for anything later that adds a derived colour:

> An accessibility override never replaces a palette property. It reads one and
> derives a new value beside it. `applyAppearanceColors()` must keep a writable
> slot for every colour the theme file supplies.

That is what the `paletteTextMuted` split below implements. Apply the same shape to
any future override rather than making another palette property `readonly`.

### The change

Rename the palette slot and derive on top of it, so the palette stays writable and
the accessibility override composes over it:

```diff
     property bool dark: true
+    property bool highContrast: false
+    property bool reducedMotion: false
```

```diff
-    property string textMuted: "#D8DEE9"
+    property string paletteTextMuted: "#D8DEE9"
+    readonly property string textMuted: highContrast ? text : paletteTextMuted
```

```diff
-    readonly property string popupBorder: borderStrong
+    readonly property string popupBorder: highContrast ? textStrong : borderStrong
```

```diff
-    readonly property string controlNormalBorder: border
+    readonly property string controlNormalBorder: highContrast ? textStrong : border
-    readonly property string controlHoverBorder: borderStrong
+    readonly property string controlHoverBorder: highContrast ? textStrong : borderStrong
-    readonly property string controlFocusBorder: accent
+    readonly property string controlFocusBorder: highContrast ? textStrong : accent
-    readonly property string controlSelectedBorder: accentSecondary
+    readonly property string controlSelectedBorder: highContrast ? textStrong : accentSecondary
-    readonly property string controlDisabledBorder: border
+    readonly property string controlDisabledBorder: highContrast ? textStrong : border
```

In `applyAppearanceColors()` (`Theme.qml:69`), write the palette slot instead —
this one line is what keeps hot reload working:

```diff
-        root.textMuted = colors["text-muted"];
+        root.paletteTextMuted = colors["text-muted"];
```

`menuMutedText` (`Theme.qml:36`) and `controlDisabledText` (`Theme.qml:56`) already
alias `textMuted`, so they inherit the override with no further edit.

Before committing, confirm nothing else still writes the derived property:

```bash
grep -rn "\.textMuted\s*=" config/quickshell
```

That must return nothing. `applyAppearanceColors()` is the only writer today; a hit
anywhere else is a second hot-reload path that would throw the same way.

### Regression test — hot reload under an active override

Add to `tests/test-quickshell-settings-xvfb.sh`. This is the assertion that the
invariant above is real, and it must fail if `paletteTextMuted` is ever collapsed
back into `textMuted`:

```sh
# A theme change must still apply while a contrast override is active, and must
# not clear the override. This is the whole reason for the paletteTextMuted split.
dwm-accessibility-settings set contrast high
wait_for_ipc settings themeHighContrast true ||
	fail "contrast override did not reach the shell"

before_text=$(quickshell_ipc settings themeColor text)

# Apply a theme with a demonstrably different palette and require that the
# palette moved, the override survived, and muted text stayed pinned to text.
dwm-settings-theme apply "$alternate_theme"
wait_for_ipc_change settings themeColor text "$before_text" ||
	fail "theme hot reload did not repaint while contrast was active"

[ "$(quickshell_ipc settings themeHighContrast)" = true ] ||
	fail "theme hot reload cleared the contrast override"
[ "$(quickshell_ipc settings themeColor textMuted)" \
	= "$(quickshell_ipc settings themeColor text)" ] ||
	fail "high contrast stopped pinning textMuted after a theme reload"

# And with the override off, muted text must follow the theme again.
dwm-accessibility-settings set contrast standard
[ "$(quickshell_ipc settings themeColor textMuted)" \
	!= "$(quickshell_ipc settings themeColor text)" ] ||
	fail "textMuted stayed pinned after contrast returned to standard"
```

`themeColor(role)` and `themeHighContrast` are two more pure-read IPC probes in the
same `settings` handler [Phase 0](SYNC-P0-DPI-GATE.md) extended; add them alongside
`themeUiScale`.

Add the setter beside `applyDisplayDpi` (`Theme.qml:92`):

```qml
    function applyAccessibility(highContrastEnabled, reducedMotionEnabled) {
        root.highContrast = highContrastEnabled;
        root.reducedMotion = reducedMotionEnabled;
    }
```

Border widths — note the `dp()` composition. Upstream writes bare `1`/`2`/`3`
because it has no `uiScale`; in Lyona a bare `2` is a hairline at 2× DPI, which is
the opposite of what high contrast is for:

```diff
-    readonly property int controlBorderWidth: dp(1)
-    readonly property int controlFocusBorderWidth: dp(2)
+    readonly property int controlBorderWidth: dp(highContrast ? 2 : 1)
+    readonly property int controlFocusBorderWidth: dp(highContrast ? 3 : 2)
```

Animation durations:

```diff
-    readonly property int animationFast: 120
-    readonly property int animationNormal: 180
+    readonly property int animationFast: reducedMotion ? 0 : 120
+    readonly property int animationNormal: reducedMotion ? 0 : 180
```

> A zero-duration animation still schedules one frame. Gating each `Behavior` on an
> `enabled` flag would skip even that, but it touches every animated surface in the
> shell and cannot be reviewed as one hunk. Duration `0` is the correct trade here:
> one file, and the visible result — no motion — is identical. Revisit only if the
> closed-CPU measurement in the qualification below moves.

## `config/quickshell/accessibility/AccessibilityModel.qml`

Port upstream's model with **one substitution**. Upstream carries an inline
`watchProcess`, a `settleTimer` and a `watchRestartTimer`
(`AccessibilityModel.qml:131-182`). Lyona has that as a component:

```qml
    WatchedProcess {
        id: accessibilityWatcher

        command: Commands.accessibilitySettingsCommand("watch", [])
        active: root.watchReady
        settleInterval: 100
        onSettled: root.refresh()
    }
```

That deletes ~50 lines and the `watchSetupFailures` / `maxWatchSetupFailures`
bookkeeping, because `WatchedProcess` already gates restarts on `active` and backs
off on `restartInterval`. It is the same substitution `AppearanceModel.qml:1693`
makes for the compositor watcher.

**Port `parseStatus()` unchanged.** The protocol-version check, the duplicate-field
rejection, the enum whitelists and the `complete\tstatus` terminator are the
security boundary between an unprivileged helper's stdout and the shell's render
state. Paraphrasing it is how a validation gap gets introduced.

`useDefaults()` must call `Theme.applyAccessibility(false, false)` so a missing or
unreadable config lands on standard contrast and full motion rather than leaving the
previous session's override in place.

## `config/quickshell/shell.qml`

```diff
 import Quickshell.Services.SystemTray
+import qs.accessibility
 import qs.appearance
```

```diff
     AppearanceModel {
         id: appearanceModel
     }
+
+    AccessibilityModel {
+        id: accessibilityModel
+    }
```

Lyona's import block is alphabetical after `qs.core`; place `qs.accessibility`
accordingly.

## `Makefile`

```diff
 INSTALL_COMMANDS = \
 	scripts/active-audio \
+	scripts/dwm-accessibility-settings \
 	scripts/check-deps.sh \
```

```diff
+check-accessibility:
+	tests/test-dwm-accessibility-settings.sh
+	tests/test-quickshell-accessibility.sh
```

Then: `scripts/dwm-accessibility-settings` into the `check-shell` and `check-format`
file lists, `$(MAKE) check-accessibility` into the `check:` recipe, and
`check-accessibility` into `.PHONY`.

## Verification

```bash
scripts/run-tests make check-shell
scripts/run-tests make check-format
scripts/run-tests make check-quickshell-qml
scripts/run-tests make check-accessibility
scripts/run-tests make check-quickshell-design-system
scripts/run-tests make check-quickshell-settings-xvfb
```

`check-quickshell-design-system` matters here: it is the test that pins the semantic
colour roles, and the `paletteTextMuted` split changes how they are derived.

Manual, in a live session:

1. `dwm-accessibility-settings set contrast high` — borders thicken, muted text
   collapses to full-strength `text`, focus rings widen.
2. With high contrast still on, hot-reload a theme
   (`dwm-settings-theme apply <name>`). **Three things must all hold:** the palette
   visibly changes, the contrast override survives, and no error appears in the
   Quickshell log. If the theme only half-applies, `applyAppearanceColors()` is
   still writing a `readonly` property and threw part-way through.
3. Switch themes several times with contrast on, then turn contrast off. Muted text
   must return to the new theme's `text-muted`, not to the theme that was active
   when contrast was first enabled.
4. `dwm-accessibility-settings set motion reduced` — panel and popup transitions
   stop.
5. `dwm-accessibility-settings reset` — both return to defaults.
6. Delete `~/.config/lyona/accessibility.conf` while the shell is running; the
   watcher must fire and land on defaults, not on the last override.
7. 30-second closed CPU baseline vs. 30 seconds with the Control Center open. The
   `WatchedProcess` substitution should leave this flat.

## Closes

`TASKS.md:93` — *Apply reduced-motion and contrast choices consistently to managed
[surfaces]*.

Also flips the contrast and reduced-motion capability records added in
[Phase 4](SYNC-P4-A11Y-CAPABILITIES.md) from `unavailable` to `available`; assert
that transition in `tests/test-settings.sh`.
