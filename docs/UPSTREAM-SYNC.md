# Upstream Sync — ChrisTitusTech/dwm-titus → Lyona

Index for the phased port of upstream work landed since the fork. Each phase has
its own document with literal code; this file carries the survey, the exclusions,
the rules that apply everywhere, and the phase order.

Surveyed at upstream `94ca1a4` (2026-09-05) plus open PR #229.

---

## Context

Lyona forked `ChrisTitusTech/dwm-titus` on **2026-08-27** (`53b8dd2 Initial Commit`)
and rebranded it from a Fedora-targeted dwm distribution to an Arch/CachyOS one:
`archiso/`, `lyona-*` helpers, `~/.config/lyona`, tokyonight terminal themes, a GRUB
and Plymouth theme, and a `dwm-settings-toolkit` in place of upstream's
`dwm-settings-personalization`.

The two histories are unrelated — nothing can be pulled by merge. Since the fork
point upstream has landed **49 commits** and opened **1 PR**. A few of those were
already reproduced in Lyona by hand; the rest are the work planned here.

## Decisions taken up front

- **Upstream's Phase 6** (PackageKit system-package updates plus, as of the
  2026-09-06 re-survey, a second "regional services" domain — timezone, NTP,
  locale, accounts, printers, repositories — `#207`–`#253`, **over 26,800 lines**)
  is **planned as a later phase**, scheduled after Lyona's own Phase 6 —
  `lyona-update`, designed in `docs/P6-UPDATE-*.md` — which solves a different
  problem and lands first. The Arch port is planned in
  [`SYNC-P10-SYSTEM-MANAGEMENT.md`](SYNC-P10-SYSTEM-MANAGEMENT.md), sequenced into
  ten boundaries (SM-001…SM-010) around upstream's own `UpdateBackend` seam. See
  that document's "Re-survey before starting" section for what changed between the
  two surveys — upstream merged 25 commits in the 33 hours between them.
- **Docs site**: keep mdBook (`docs/book.toml`, `docs/theme/catppuccin.css`).
  Upstream's Astro rebuild (`#194`) is **not** ported. Only the prose that rides
  along in later commits is folded into the existing `docs/src/*.md`.
- **Security hardening** (2026-09-06): a read-only audit of Lyona's own
  scripts, config, and build found real findings independent of anything upstream
  — two of them (a `curl | sudo sh` fallback reachable in the *default* install
  profile, and a shipped lock-screen setup script that doesn't lock) lived in the
  default or a plausible path. **Done** — see `CHANGELOG.md`'s "Security" section
  and `TASKS.md`'s `SECURITY-001`.

---

## Already in Lyona — excluded from every phase

These upstream changes are **done or declined**. Recorded so they are not re-applied.

| Upstream | Lyona equivalent | Notes |
| --- | --- | --- |
| `1c16634` *Prefer ChatGPT desktop app when installed* | `7bd6a54 Prefer ChatGPT Desktop` (2026-08-28) | Ported: `config/hotkeys.toml`, `scripts/dwm-quickshell-launcher` `launch_chatgpt()`, `tests/test-quickshell-launcher.sh`. **Launcher half only** — the `webapp-launch` half (`#197`) is still missing; see Phase 1. |
| `d15432c` *fix: keep floating windows above tiled clients (#196)* | `809f456` + `8adfa21` (2026-08-29) | **Superseded, not merely ported.** Upstream adds a 5-line pre-pass in `restack()`. Lyona instead added `restackprioritywindows()` (`dwm.c:2675`), called from `restack()`, `arrange()`, `togglefloating()` and the client-message path, with `tests/test-dwm-x-roundtrips.sh` coverage. Lyona's is the stronger implementation — **do not** apply upstream's hunk; it would double-stack. |
| `e2137c2` *ci: bump github/codeql-action (#193)* | n/a | Lyona removed `.github/workflows/codeql.yml` and `c-cpp.yml` in `809f456`. Nothing to bump. |
| `d03531a`, `52e51c4` *Astro docs site* | n/a — declined | Lyona keeps mdBook by decision. |
| `edb5478` *docs: automate small ready PR workflow* | n/a | Upstream `AGENTS.md` bot-workflow section. |
| `46837e5` *Change logo image / README heading* | `b85539b Update README.md` | Lyona has its own branding and `lyona-qs-4x.webp`. |
| `5f806af`, `3770b04`, `ce7fbbb` *Phase 5 status / qualification docs* | n/a | Upstream evidence records against Fedora 44. Lyona records its own under `docs/evidence/`. |
| `b0e9b0e`, `46991ca` *personalization backend*; `scripts/dwm-xsettings` | `scripts/dwm-settings-toolkit`, `scripts/dwm-settings-display` | **Pre-fork divergence.** Lyona renamed `dwm-settings-personalization` → `dwm-settings-toolkit` (writes `~/.config/lyona/personalization.conf`) and folded the xsettingsd job into `dwm-settings-display`'s `write_xsettings_dpi()`. Every later upstream hunk touching `dwm-xsettings` is therefore N/A. |
| `f4f477c` *stabilize appearance watcher lifecycle* | `config/quickshell/core/WatchedProcess.qml` | Lyona already extracted the watch-process + settle-timer + restart-timer trio into a reusable component. Upstream's fix hardens their inline copy. **Verify only** (Phase 1c). |
| DPI hot reload | `2a49ffd Fixed DPI settings` | Lyona-only. `Theme.uiScale`, `Theme.dp()` and `dpiStateWatch` do not exist upstream — which is why several upstream hunks below need adaptation rather than a straight copy. |
| `#207`–`#229` upstream Phase 6 | — | Not excluded — **planned** as Phase 10, after Lyona's own Phase 6. See [`SYNC-P10-SYSTEM-MANAGEMENT.md`](SYNC-P10-SYSTEM-MANAGEMENT.md). |

### Lyona-only assets the port must reuse rather than duplicate

| Component | Path | Replaces upstream's |
| --- | --- | --- |
| `WatchedProcess` | `config/quickshell/core/WatchedProcess.qml` | Inline `Process` + `settleTimer` + `restartTimer` in `AccessibilityModel.qml:131-182` and `PanelSettingsModel.qml:144-172` |
| `StatusCard` | `config/quickshell/core/StatusCard.qml` | Inline `component StatusCard` repeated in each upstream pane |
| `Theme.dp()` / `Theme.uiScale` | `config/quickshell/core/Theme.qml:90-102` | Upstream's raw pixel constants |
| `tests/lib.sh`, `tests/test-lib.sh` | `tests/` | Upstream tests have no shared assertion library — every ported test is rewritten onto `fail()` / `assert_*` |
| `flock -w 5 -x 9` under `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}` | `dwm-settings-font:738`, `dwm-settings-toolkit:814` | Upstream's identical convention under `/tmp/dwm-titus-$UID` |

---

## Global adaptation rules

Apply to **every** phase; not repeated in the per-phase documents.

| Upstream | Lyona |
| --- | --- |
| `~/.config/dwm-titus/…` | `~/.config/lyona/…` |
| `${XDG_RUNTIME_DIR:-/tmp/dwm-titus-$UID}` | `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}` |
| `scripts/dwm-settings-personalization`, `scripts/dwm-xsettings` | `scripts/dwm-settings-toolkit`, `scripts/dwm-settings-display` |
| `fedora:*` package profiles, `dwm-fedora*.ks`, `tests/test-fedora-*` | `arch:*` profiles in `scripts/dwm-packages.sh`, `archiso/packages.x86_64`, `tests/test-arch-*` |
| Raw pixel constants in QML | Wrap in `Theme.dp(...)` — Lyona scales the whole shell |
| Bare `grep`/`test` assertions in ported tests | `. "$(…)/lib.sh"`, then `fail` / `assert_*` |
| Helper name `dwm-*` | **Keep unchanged** — matches the existing `dwm-settings-*` family and keeps future upstream diffs clean |

Every new helper must be registered in **three** places or it will not ship:
`Makefile` `INSTALL_COMMANDS`, `Makefile` `check-shell`, `Makefile` `check-format`.

---

## Phase order

| Phase | Document | Upstream | Depends on |
| --- | --- | --- | --- |
| 0 | **Done** — see `CHANGELOG.md`, `TASKS.md` | — (Lyona prerequisite) | — |
| 1 | **Done** — see `CHANGELOG.md`, `TASKS.md` | `#197`, `f4f477c` | — |
| 2 | **Done** — see `CHANGELOG.md`, `TASKS.md` | `#186` part 1 | — |
| 3 | **Done** — see `CHANGELOG.md`, `TASKS.md` | `#186` part 2, `c3e9a18`* | 0, 2 |
| 4 | **Done** — see `CHANGELOG.md`, `TASKS.md` | `#190` | — |
| 5 | **Done** — see `CHANGELOG.md`, `TASKS.md` | `#201` | 4 |
| 6 | **Done** — see `CHANGELOG.md`, `TASKS.md` | `#202` | 4, 5 |
| 7 | **Done** — see `CHANGELOG.md` | `#203` | 4 |
| 8 | **Done** — see `CHANGELOG.md` | `#204` | 4 |
| 9 | **Done** — see `CHANGELOG.md` | `#198`, `#200`, `f558c77` | 0, 3 |
| 10 | [`SYNC-P10-SYSTEM-MANAGEMENT.md`](SYNC-P10-SYSTEM-MANAGEMENT.md) | `#207`–`#253` | Lyona UPDATE-001…003 |
| 11 | **Done** — see `CHANGELOG.md`, `TASKS.md` | — (Lyona's own audit) | — |

File numbers above are **not** the recommended run order — see
[Recommended execution order](#recommended-execution-order) below.

Phases 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, and 11 are **done** — implemented,
verified (`make check-shell`, `make check-format`, `make check-quickshell-qml`,
and the relevant functional tests all pass), and their planning documents
(`SYNC-P0-DPI-GATE.md`, `SYNC-P1-STANDALONE.md`, `P5-PANEL-WIDGETS-PORT.md`,
`P5-SETTINGS-LAYOUT-PORT.md`, `SYNC-P4-A11Y-CAPABILITIES.md`,
`SYNC-P11-SECURITY-HARDENING.md`, `SYNC-P5-CONTRAST-MOTION.md`,
`SYNC-P6-A11Y-CONTROLS.md`, `SYNC-P7-XKB-INPUT.md`, `SYNC-P8-NOTIFICATIONS.md`,
`SYNC-P9-DISPLAY-APPLY.md`)
have been removed — the record of what changed now lives in `CHANGELOG.md`
(Phase 2, 4, 6, and 11's `TASKS.md` checkboxes are also ticked, and Phase 5's
`TASKS.md:93` and Phase 8's `TASKS.md:96` checkboxes too; Phase 7 closed the
same `TASKS.md:88`/`:91` items Phases 4 and 6 already checked, so it ticks
nothing new; Phases 0, 1, 3, and 9 never had one) and git history, not in a plan
for work still to do. Phase 9's own doc pointed its "Closes" section at
`TASKS.md:133`, which by the time of implementation was a `SECURITY-001`
acceptance line, not the `P5-VALIDATE` "Exercise reversible appearance and
accessibility changes on Arch" item it meant — a line-number drift from an
earlier phase's insertion into this same file, not a content error. That
`P5-VALIDATE` item stays unchecked: it covers all of Phase 5's reversible
appearance/accessibility work, most of it needs real multi-monitor hardware,
and this phase's own manual-verification checklist (also in the removed doc)
was written for exactly that reason. Phase 9's "Lyona adaptation" section
also proposed a DPI-revert-on-abandoned-preview test
(`dwm-settings-display → publish_dpi_state() → dpi.current → Theme.uiScale`
reverting when a resolution preview's countdown lapses) that doesn't
correspond to real behavior: `scripts/dwm-settings-display`'s resolution
preview/revert/watchdog paths never call `publish_dpi_state()` at all — DPI
and resolution are entirely decoupled in the current implementation, so
there's nothing for a countdown lapse to leave stale. Confirmed against the
real upstream diff too: `65fd1a6`'s actual `tests/test-quickshell-settings-xvfb.sh`
hunk (+95/-21) has nothing to do with display resolution — it exercises
`AppearanceModel.qml`'s new `mutationReadinessPending` queueing (a `dwm-settings-theme
mutation-ready` fixture stub that stalls until released), which is real and
was ported (see the "validating queued theme readiness" stage in that file).
No DPI-revert wiring or test was added; documented here instead of forced in
speculatively. Phase 8's own doc undercounted the real scope — it
missed `tests/test-quickshell-settings-xvfb.sh` entirely (a +167/-13 hunk)
and its `scripts/autostart.sh` claim ("create `~/.config/lyona` before the
shell starts") didn't match the real commit at all, which only hardens
`QUICKSHELL_CONFIG`'s path against a relative `XDG_CONFIG_HOME` — ported the
real diff, not the doc's claim. Also **deliberately scoped out**: the
`test-quickshell-settings-xvfb.sh` restart-based persistence assertions
(load/reset/Do-Not-Disturb/malformed-JSON survive a fresh Quickshell
process, not just a live file change) — building a `restart_quickshell`
helper in an unfamiliar 2700-line file carried real risk for marginal
additional coverage, given the same policy behavior (including on-disk
persistence, verified by reading the actual JSON file) is already fully
exercised end-to-end by `test-quickshell-large-surfaces-xvfb.sh`, which
passes. `SYNC-P7-XKB-INPUT.md`'s claim
that `xkbset` "is in the Arch extra repository, so no AUR handling is
needed" was wrong — confirmed against a live `pacman -Ss`/AUR RPC query,
it is AUR-only. Shipped as an `arch:desktop-optional` entry instead of
`arch:desktop`, so the availability pre-check skips it silently rather than
failing the required-package transaction. Phase 4's
own doc had drifted from what upstream actually shipped by the time it was
implemented (wrong emitter count, wrong helper for text-scale, an
undocumented notifications capability) — corrected in place before removal,
and the corrections are reflected in the Phase 5/6/7/8 documents that
referenced it. Phase 5's own doc adapted upstream's inline appearance
watcher onto Lyona's shared `WatchedProcess` component — verified against
`AppearanceModel.qml`'s existing compositor-watcher substitution rather than
porting upstream's `watchReady`/`watchSetupFailures` bookkeeping. Phase 6's
`AppearanceSettingsPane.qml` change diverged from upstream's structure too:
Lyona never ported upstream's `accessibilityCapabilities`/
`PersonalizationControl` text-scale split, so the new high-contrast/
reduced-motion toggles were added as their own section alongside Lyona's
existing generic "Additional capabilities" list, filtering only the two
capability IDs the new controls make redundant.

**`*` Phase 3 exception — `c3e9a18` was not ported.** `P5-SETTINGS-LAYOUT-PORT.md`
(now removed) fully specified the Settings-window enlargement and compaction, and
that half is done. Upstream's `c3e9a18` `ControlCenterWindow.qml` tightening — section
headers removed, a `compactRowHeight` token, `Theme.compactSpacing` throughout — was
never part of that document; it was noted here as supplementary scope and remains
**open**. It's independent (same file Phase 2 already touched for `pageMessage()`,
no shared dependency), small, and can land as its own commit whenever it's picked up.

---

## Recommended execution order

**This is the authoritative sequence — it is not the same as ascending file
number, and that's intentional.** Phase 11's file number reflected when it was
added to this plan (2026-09-06, after a security audit run alongside a routine
upstream re-survey), not when it ran — it's done now, out of file-number order,
as originally recommended.

| Order | Phase | Why here |
| --- | --- | --- |
| ✅ | **Phase 0** — DPI gate | **Done.** The remaining item at completion was environmental (no working PipeWire/`gvfs` session on the test machine, not a defect in the phase's own code) — see `CHANGELOG.md`. |
| ✅ | **Phase 1** — Standalone fixes | **Done**, including item 1d (`#246`'s incidental `dwm-settings-appearance` coprocess-race fix, found during the 2026-09-06 re-survey) — see `CHANGELOG.md`. |
| ✅ | **Phase 11** — Security hardening | **Done.** See `CHANGELOG.md`'s "Security" section, `TASKS.md`'s `SECURITY-001`. Zero file overlap with any other phase; contained two P0 findings live in the *default recommended install path* and in an *opt-in but misleadingly-named lock script*. |
| ✅ | **Phase 2** — Panel-widget persistence | **Done.** See `CHANGELOG.md`. |
| ✅ | **Phase 3** — Settings layout compaction | **Done**, except the `c3e9a18` `ControlCenterWindow.qml` tightening noted above, which remains open. |
| ✅ | **Phase 4** — Accessibility capability records | **Done.** See `CHANGELOG.md`, `TASKS.md`. Foundation for 5/6/7/8 — touched only `dwm-settings-provider`/`dwm-settings-input`, no conflict with the already-done Phase 2/3 Settings-pane work. |
| ✅ | **Phase 5** — Contrast and motion policy | **Done.** See `CHANGELOG.md`, `TASKS.md`. Depends on Phase 4 (done). |
| ✅ | **Phase 6** — Accessibility Settings controls | **Done.** See `CHANGELOG.md`, `TASKS.md`. Depends on Phases 4 and 5 (both done). |
| ✅ | **Phase 7** — XKB input accessibility | **Done.** See `CHANGELOG.md`. Depends on Phase 4 (done) only; independent of 5/6. |
| ✅ | **Phase 8** — Managed notification policy | **Done.** See `CHANGELOG.md`. Depends on Phase 4 (done) only; independent of 5/6/7. |
| ✅ | **Phase 9** — Display resolution and apply workflow | **Done.** See `CHANGELOG.md`. Depended on Phase 0 (DPI interaction, done) and Phase 3 (final geometry, done); also touched the same `ShellButton.qml` Phase 6 extended, for the new Apply button's primary/pending states. |
| — | **Phase 10** — System management | **Still deferred**, not part of the near-term order at all. Gated on Lyona's own `UPDATE-001…003` landing and on re-surveying upstream *again* immediately before starting — see that document's own "Re-survey before starting," which now has real teeth: 25 commits landed in the 33 hours between this plan's two surveys. |

**Net effect:** with Phases 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, and 11 done, the only
work left in this document is Phase 10, and that stays deliberately deferred.
Nothing about that
remaining order changed from the original survey — the two pieces of new work
found on 2026-09-06 both slotted in without disturbing it: Phase 11 because it
shared no files with anything else, and the regional-services scope because it
extends a phase (10) that's already deferred rather than needing a phase of
its own.

---

## Verification

Run before every phase is considered done:

```bash
scripts/run-tests make clean all             # C build stays clean
scripts/run-tests make check-shell           # shellcheck, incl. every new helper
scripts/run-tests make check-format          # shfmt
scripts/run-tests make check-quickshell-qml  # configured QML lint
```

Phase-specific gates:

| Phase | Command |
| --- | --- |
| 0 | `make check-quickshell-settings-xvfb` |
| 1 | `make check-webapp-launch`, `make check-quickshell-launcher` |
| 2 | `make check-quickshell-panel-settings`, `make check-quickshell-controlcenter` |
| 3 | `make check-quickshell-settings-xvfb`, `make check-quickshell-large-surfaces-xvfb`, `make check-quickshell-controlcenter` |
| 4 | `make check-settings` |
| 5 | `make check-accessibility`, `make check-quickshell-design-system` |
| 6 | `make check-accessibility`, `make check-quickshell-settings-xvfb` |
| 7 | `make check-settings`, `make check-arch-packages` |
| 8 | `make check-quickshell-notifications`, `make check-session-guards` |
| 9 | `make check-settings`, `make check-quickshell-appearance-model` |
| 10 | `scripts/run-tests /usr/bin/python3 tests/test-system-management.py`, `make check-quickshell-system-management` |
| 11 | `make clean all` (compiler-flag change), `make check-shell`, `make check-format`, `make check-lock`, `make check-cachyos`, `make check-install` — **done**, see `CHANGELOG.md` |

Full suite before the last phase merges:

```bash
scripts/run-tests make check
```

### Manual qualification

Matches `TASKS.md:131-141`, and is the only way to catch the DPI interactions.

1. Fresh LightDM login on Arch/CachyOS, then a `startx` session.
2. Multi-monitor with mismatched DPI — change DPI in Settings, confirm the shell
   rescales without a restart. Phase 0 automates the assertion; do it by hand once
   per phase that touches geometry.
3. Toggle high contrast and reduced motion (Phases 5–6): borders thicken, muted text
   collapses to full-strength text, animations stop. Then hot-reload a theme and
   confirm the palette changes **and** the override survives — theme hot reload
   staying functional is a named invariant of Phase 5, not a side effect.
4. 30-second closed CPU baseline vs. 30 seconds with Settings open and with the
   Control Center open. The `WatchedProcess` substitutions in Phases 2 and 5 should
   leave this flat; a regression means a watcher is restarting in a loop.
5. `make install` / `make uninstall` round-trip — proves every new helper reached
   `INSTALL_COMMANDS`.

## Commit and tracking

One commit per phase (Phase 1 is three). Each phase closes named `TASKS.md`
checkboxes — update `TASKS.md`, `CHANGELOG.md` and `docs/evidence/` in the same
commit that delivers the behaviour, per `AGENTS.md`.
