# Sync Phase 0 — DPI hot-reload test gate

Prerequisite for [`SYNC-P9-DISPLAY-APPLY.md`](SYNC-P9-DISPLAY-APPLY.md), Phase 3
(settings layout), and [`SYNC-P5-CONTRAST-MOTION.md`](SYNC-P5-CONTRAST-MOTION.md).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

No upstream commit — this is Lyona's own gate, made necessary by `2a49ffd Fixed DPI
settings`, which upstream does not have.

## Context

`docs/P5-SETTINGS-LAYOUT-PORT.md` already establishes that the DPI path is
**untested end to end**:

```
dwm-settings-display  →  dpi.current  →  shell.qml dpiStateWatch
                      →  Theme.applyDisplayDpi  →  Theme.uiScale  →  Theme.dp()
```

- `tests/test-quickshell-settings-xvfb.sh:727-732` is the only DPI assertion under a
  running shell, and it reads `settingsModel.displayDpi` — the value parsed from
  `dwm-settings-display discover`. It proves the Settings pane *reports* DPI. It
  never reaches `Theme.displayDpi`, `Theme.uiScale`, or the `dpiStateWatch`
  `FileView`.
- `tests/test-settings.sh:333-399` covers the helper thoroughly (`dpi-set`,
  `dpi-apply-saved`, `dpi-reset`, rejection, Xresources, `xrdb`) but never starts
  Quickshell.
- Nothing writes `dpi.current` at runtime and asserts the shell reacted.
  `publish_dpi_state()` (`scripts/dwm-settings-display:282`) has no end-to-end cover,
  and no IPC exposes `Theme.uiScale`.

Phases 3, 5, 6 and 9 all resize or recolour DPI-scaled geometry. Land this gate on
the **unmodified** tree first, so a later regression is attributable to the phase
that caused it.

## Files

- `config/quickshell/shell.qml`
- `tests/test-quickshell-settings-xvfb.sh`

## Changes

### `config/quickshell/shell.qml`

Two additive IPC probes in the existing `settings` IPC handler. Pure reads; no
behaviour change, nothing new allocated, nothing new watched.

```qml
        function themeDisplayDpi(): int {
            return Theme.displayDpi;
        }

        function themeUiScale(): string {
            return Theme.uiScale.toFixed(4);
        }
```

`toFixed(4)` rather than returning a `real`: the IPC surface is line-oriented text,
and a fixed-width decimal compares exactly in shell without floating-point
formatting drift between Qt versions.

### `tests/test-quickshell-settings-xvfb.sh`

Add one case to the existing nested-X11 shell fixture. It must run *after* the shell
is up and *before* any test that mutates display state, so it observes a known
starting scale.

```sh
# Prove the DPI hot-reload path end to end: writing dpi.current must reach
# Theme.uiScale without a shell restart. Every later layout change relies on
# this, so it is asserted on the unmodified tree first.
initial_scale=$(quickshell_ipc settings themeUiScale) ||
	fail "could not read themeUiScale"

printf '192\n' >"$XDG_STATE_HOME/lyona/dpi.current"

# dpiStateWatch coalesces, so poll rather than sleeping a fixed interval.
scale=
for _ in $(seq 1 50); do
	scale=$(quickshell_ipc settings themeUiScale) || continue
	[ "$scale" != "$initial_scale" ] && break
	sleep 0.1
done

[ "$(quickshell_ipc settings themeDisplayDpi)" = 192 ] ||
	fail "themeDisplayDpi did not follow dpi.current"
[ "$scale" = "2.0000" ] ||
	fail "expected uiScale 2.0000 after a 192 DPI reload, got: $scale"
```

`192 / 96 = 2.0`, inside the `Math.max(0.75, Math.min(3.0, …))` clamp at
`config/quickshell/core/Theme.qml:90`, so the expected value is exact.

Reuse the file's existing IPC helper and `XDG_STATE_HOME` fixture rather than
introducing new ones; the surrounding cases already establish both.

## Exit criteria

```bash
scripts/run-tests make check-quickshell-settings-xvfb
```

Green on an otherwise unmodified tree. If it is not, the bug it found belongs to
`2a49ffd`, not to any later phase — fix it here before continuing.

## Closes

Nothing in `TASKS.md` directly. It is the evidence that `TASKS.md:135` (the closed-CPU
and reversible-change qualification) can be trusted for Phases 3, 5, 6 and 9.
