# Sync Phase 9 — display resolution and apply workflow

Upstream: [`#198`](https://github.com/ChrisTitusTech/dwm-titus/pull/198)
`Settings: add display resolution dropdown` (`c9389ad`),
[`#200`](https://github.com/ChrisTitusTech/dwm-titus/pull/200)
`Settings: clarify display apply workflow` (`65fd1a6`), and `f558c77`
`Stabilize Settings preview countdown validation`.
Depends on [Phase 0](SYNC-P0-DPI-GATE.md) and Phase 3.
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Last of the Phase-5 parity work. Deliberately sequenced **after** the layout
compaction (Phase 3) so the resolution dropdown is added into the final geometry
rather than into the old 980×620 window and then re-laid-out.

`f558c77` is test-only stabilisation of `#200`'s countdown. Fold it in rather than
porting it as a separate commit.

## Files

| File | Upstream | Note |
| --- | --- | --- |
| `config/quickshell/settings/SettingsModel.qml` | +82, then +39 | Mode grouping, then apply/revert |
| `config/quickshell/settings/DisplaySettingsPane.qml` | +102, then +55 | Dropdowns, then Apply UI |
| `config/quickshell/appearance/AppearanceModel.qml` | +42 | Preview lifecycle |
| `config/quickshell/core/ShellButton.qml` | +7 | Primary/pending states |
| `config/quickshell/settings/InputSettingsPane.qml` | +2 | Shared control tidy |
| `tests/test-settings.sh` | +83 | Rewrite onto `tests/lib.sh` |
| `tests/test-quickshell-settings-xvfb.sh` | +165 | Rewrite onto `tests/lib.sh` |
| `tests/test-quickshell-appearance-model.sh` | +10 | Rewrite onto `tests/lib.sh` |
| `docs/src/settings.md` | +21 / -9 | mdBook path, not `docs/src/content/` |

## Part 1 — `#198` resolution dropdown

Lyona's display card currently exposes only `cycleDisplayMode(index)` — a single
button that walks the whole mode list. On a monitor advertising thirty modes that is
unusable. `#198` replaces it with two dependent dropdowns: resolution, then the
refresh rates available *at* that resolution.

The mode-grouping helpers in `config/quickshell/settings/SettingsModel.qml`:

```qml
    function displaySizeLabel(modeName) {
        const match = /^(\d+)x(\d+)(.*)$/.exec(modeName);
        if (!match) return modeName;
        const scanVariant = /^([ip])/i.exec(match[3]);
        return match[1] + " x " + match[2]
            + (scanVariant ? scanVariant[1].toLowerCase() : "");
    }

    function displayResolutionChoices(index) {
        const output = root.displayOutputs[index];
        if (!output) return [];
        const choices = [];
        for (const mode of root.displayModes) {
            if (mode.output !== output.name) continue;
            const label = root.displaySizeLabel(mode.mode);
            if (label.length > 0 && choices.indexOf(label) < 0) choices.push(label);
        }
        return choices;
    }

    function displayResolutionIndex(index) {
        const output = root.displayOutputs[index];
        if (!output) return -1;
        return root.displayResolutionChoices(index).indexOf(root.displaySizeLabel(output.mode));
    }

    function displayRefreshRateChoices(index) {
        const output = root.displayOutputs[index];
        if (!output) return [];
        const size = root.displaySizeLabel(output.mode);
        const choices = [];
        for (const mode of root.displayModes) {
            if (mode.output !== output.name || root.displaySizeLabel(mode.mode) !== size) continue;
            if (choices.indexOf(mode.rate) < 0) choices.push(mode.rate);
        }
        return choices;
    }

    function displayRefreshRateIndex(index) {
        const output = root.displayOutputs[index];
        if (!output) return -1;
        return root.displayRefreshRateChoices(index).indexOf(output.rate);
    }

    function updateDisplayMode(index, mode) {
        if (!mode) return;
        const outputs = root.displayOutputs.slice();
        const changed = Object.assign({}, outputs[index]);
        changed.mode = mode.mode;
        changed.rate = mode.rate;
        outputs[index] = changed;
        root.displayOutputs = outputs;
    }
```

`displaySizeLabel` normalises `1920x1080i` and `1920x1080` to distinct labels
(`1920 x 1080i`, `1920 x 1080`) so an interlaced mode is never silently substituted
for a progressive one at the same size.

`updateDisplayMode` copies the outputs array and the changed element with
`Object.assign` rather than mutating in place. That is not ceremony: QML property
bindings on `displayOutputs` only re-evaluate on assignment, so an in-place mutation
would change the data without repainting the card.

> **Note on cost.** `displayResolutionChoices` and `displayRefreshRateChoices` are
> O(modes × choices) via `indexOf`. With a typical 20–40 modes per output that is a
> few hundred comparisons per repaint — fine as written, and worth leaving alone
> rather than introducing a `Set` for a list this size. Revisit only if a monitor
> with a pathological mode list shows up.

`cycleDisplayMode` is removed; check for stale callers:

```bash
grep -rn "cycleDisplayMode" config/quickshell tests
```

## Part 2 — `#200` apply workflow

Replaces immediate-apply with explicit **Apply**, a countdown, and automatic revert
if the user does not confirm — the standard protection against a mode that leaves the
screen unreadable.

`config/quickshell/core/ShellButton.qml` gains the primary/pending visual states the
Apply button needs. This is the same file
[Phase 6](SYNC-P6-A11Y-CONTROLS.md) touched; land Phase 6 first so the
`Accessible.*` block and `requestActivation()` are already in place and this is a
clean additive hunk.

`config/quickshell/appearance/AppearanceModel.qml` (+42) manages the preview
lifecycle — start, countdown, confirm, revert.

## Lyona adaptation — the DPI interaction

Upstream has no DPI hot reload, so its revert path only has to restore the mode.
Lyona's does:

```
dwm-settings-display  →  publish_dpi_state()  →  dpi.current
                      →  dpiStateWatch  →  Theme.applyDisplayDpi  →  Theme.uiScale
```

`publish_dpi_state()` is at `scripts/dwm-settings-display:282`. **A reverted
resolution must also revert the published DPI**, or the shell is left scaled for a
resolution that is no longer active — every surface mis-sized, with no visible cause.

Assert it in `tests/test-quickshell-settings-xvfb.sh`, building on
[Phase 0](SYNC-P0-DPI-GATE.md)'s probes:

```sh
# Apply a mode, let the countdown lapse without confirming, and require that
# both the mode and the published DPI return to where they started.
before_dpi=$(quickshell_ipc settings themeDisplayDpi)
before_scale=$(quickshell_ipc settings themeUiScale)

quickshell_ipc settings applyDisplayPreview
# … wait out the countdown without confirming …

[ "$(quickshell_ipc settings themeDisplayDpi)" = "$before_dpi" ] ||
	fail "auto-revert left the published DPI at the previewed value"
[ "$(quickshell_ipc settings themeUiScale)" = "$before_scale" ] ||
	fail "auto-revert left Theme.uiScale at the previewed value"
```

This is precisely why Phase 0 is a prerequisite: without `themeUiScale`, the revert
can only be checked by eye.

## `f558c77` — countdown test stabilisation

Upstream's countdown assertions raced the timer. The fix polls for the state
transition instead of sleeping a fixed interval. Carry that shape into the rewritten
test — Lyona's `tests/lib.sh` has the helpers for it, and a fixed `sleep` here is the
most likely source of a flaky suite.

## Verification

```bash
scripts/run-tests make check-quickshell-qml
scripts/run-tests make check-settings
scripts/run-tests make check-quickshell-appearance-model
scripts/run-tests make check-quickshell-settings-xvfb
```

Manual, on real hardware with at least two monitors:

1. Open Settings → Displays. Each output shows a resolution dropdown listing distinct
   sizes only, and a refresh-rate dropdown scoped to the selected size.
2. Pick a lower resolution, press Apply, and **let the countdown lapse**. The mode
   reverts, and the shell's scale returns with it — no mis-sized panel.
3. Repeat and confirm within the countdown. The mode sticks and survives a shell
   restart.
4. Pick a resolution whose DPI differs materially (e.g. 4K → 1080p on the same
   panel), confirm, and check the whole shell rescales — the `Theme.uiScale` path.
5. On a monitor advertising an interlaced mode, confirm the progressive and
   interlaced entries at the same size are separately selectable.
6. Unplug a monitor while the pane is open; the card disappears without leaving a
   pending preview behind.

## Closes

The display half of `TASKS.md:133` — *Exercise reversible appearance and
accessibility changes on Arch*. The auto-revert path is what makes "reversible"
literal.
