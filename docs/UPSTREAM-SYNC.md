# Upstream Sync — ChrisTitusTech/dwm-titus → Lyona

Index for the phased port of upstream work landed since the fork. Each phase has
its own document with literal code; this file carries the survey, the exclusions,
the rules that apply everywhere, and the phase order.

Surveyed at upstream `94ca1a4` (2026-09-05); re-surveyed at `03b2195`
(2026-09-06); re-surveyed again at `dd55e58` (2026-09-07) — see
[The system-management port](#the-system-management-port) below for what the
third survey changed and why it replaces the former single
`SYNC-P10-SYSTEM-MANAGEMENT.md` (now removed) with a fresh nine-phase
sequence.

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

- **Upstream's Phase 6** (PackageKit system-package updates plus a "regional
  services" domain — timezone, NTP, locale, accounts, printers, repositories —
  `#207`–`#265`, a single **8,946-line Python 3 program** at `dd55e58`) is
  **planned as a later phase**, scheduled after Lyona's own Phase 6 —
  `lyona-update`, designed in `docs/P6-UPDATE-*.md` — which solves a different
  problem and lands first. The Arch port is now planned as its own nine-phase
  sequence — see [The system-management port](#the-system-management-port) —
  which **replaced** an earlier single `SYNC-P10-SYSTEM-MANAGEMENT.md` plan
  after a 2026-09-07 re-survey found two things that plan got wrong: the
  provider is not a PackageKit-only Fedora artefact that needs replacing (it
  is already a working Arch/alpm frontend — see
  [Position in the sequence](#position-in-the-sequence)), and the regional
  scope alone had grown past what one document could track. This is a
  **restructuring, not new upstream scope** — the total line count and PR
  range are the same drift already noted; only the plan's shape changed.
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
| `e2137c2` *ci: bump github/codeql-action (#193)* | n/a | Lyona removed `.github/workflows/codeql.yml` and `c-cpp.yml` in `809f456`; nothing to bump there. `c-cpp.yml` was reintroduced from scratch as an Arch/pacman adaptation (2026-09-12) — see the current `.github/workflows/c-cpp.yml`, not upstream's Fedora/dnf version. `codeql.yml` remains removed. |
| `d03531a`, `52e51c4` *Astro docs site* | n/a — declined | Lyona keeps mdBook by decision. |
| `edb5478` *docs: automate small ready PR workflow* | n/a | Upstream `AGENTS.md` bot-workflow section. |
| `46837e5` *Change logo image / README heading* | `b85539b Update README.md` | Lyona has its own branding and `lyona-qs-4x.webp`. |
| `5f806af`, `3770b04`, `ce7fbbb` *Phase 5 status / qualification docs* | n/a | Upstream evidence records against Fedora 44. Lyona records its own under `docs/evidence/`. |
| `b0e9b0e`, `46991ca` *personalization backend*; `scripts/dwm-xsettings` | `scripts/dwm-settings-toolkit`, `scripts/dwm-settings-display` | **Pre-fork divergence.** Lyona renamed `dwm-settings-personalization` → `dwm-settings-toolkit` (writes `~/.config/lyona/personalization.conf`) and folded the xsettingsd job into `dwm-settings-display`'s `write_xsettings_dpi()`. Every later upstream hunk touching `dwm-xsettings` is therefore N/A. |
| `f4f477c` *stabilize appearance watcher lifecycle* | `config/quickshell/core/WatchedProcess.qml` | Lyona already extracted the watch-process + settle-timer + restart-timer trio into a reusable component. Upstream's fix hardens their inline copy. **Verify only** (Phase 1c). |
| DPI hot reload | `2a49ffd Fixed DPI settings` | Lyona-only. `Theme.uiScale`, `Theme.dp()` and `dpiStateWatch` do not exist upstream — which is why several upstream hunks below need adaptation rather than a straight copy. |
| `#207`–`#265` upstream Phase 6 | — | Not excluded — **planned**, after Lyona's own Phase 6. See [The system-management port](#the-system-management-port). |

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

**Exception**: `scripts/dwm-system-management`
([the system-management port](#the-system-management-port)) is Python, not
POSIX shell. `check-shell` (shellcheck) and `check-format` (shfmt) do not
read it and must not be made to. It still registers in `INSTALL_COMMANDS`,
and gets its own Python-run test gate (`check-system-management`) instead of
the shell two — see
[Phase 1 of that sequence](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#6-makefile-registration).
This is the only helper in the tree with this exception; do not generalize it
without a matching decision recorded here.

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
| 10 | **Superseded** — see [The system-management port](#the-system-management-port) | `#207`–`#265` | Lyona UPDATE-001…003 |
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

**Phase 10 is superseded, not done.** The single `SYNC-P10-SYSTEM-MANAGEMENT.md`
document that used to occupy this slot (sequenced as ten boundaries,
SM-001…SM-010) was replaced on 2026-09-07 by
[a fresh nine-phase sequence](#the-system-management-port) after a re-survey
found its central premise wrong (see below) and its regional-services scope
had grown too large for one document. None of the underlying work is done —
this is a planning restructure, recorded here so a future reader does not
go looking for a "Phase 10" that no longer exists as a single unit.

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
| — | **Phase 10 (superseded)** — System management | **Still deferred**, not part of the near-term order at all. Gated on Lyona's own `UPDATE-001…003` landing and on re-surveying upstream *again* immediately before starting — the 2026-09-07 re-survey did exactly that and replaced this single slot with [a nine-phase sequence](#the-system-management-port), whose own internal order is fixed (1→9, linearly dependent) and does not interleave with the rest of this table. |

**Net effect:** with Phases 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, and 11 done, the only
work left in this document is the system-management port, and that stays
deliberately deferred as a whole — gated on Lyona's own `UPDATE-001…003`,
unaffected by this restructuring. Nothing about the rest of this table's
order changed from the original survey — every piece of new work found in
later re-surveys (Phase 11's security audit, the regional-services growth)
slotted in without disturbing Phases 0–9's already-settled order.

---

## The system-management port

Nine documents, `docs/SYNC-P1-SYSTEM-PROVIDER-DECISION.md` through
`docs/SYNC-P9-REGIONAL-MUTATION.md`, replacing the single
`SYNC-P10-SYSTEM-MANAGEMENT.md` (SM-001…SM-010) that occupied this slot
between 2026-09-05 and 2026-09-07. **This numbering restarts at 1 and is its
own sequence** — it does not renumber, does not replace, and shares no file
with the completed Phases 0–9 and 11 above. Where a cross-reference is
ambiguous, the documents below say "the earlier sync work's Phase *N*"
explicitly (for example,
[Phase 7](SYNC-P7-OPERATION-SURFACE.md#lyona-adaptations) does, for the
`ShellButton` primary/pending states the completed display-apply phase
added). Read `Phase 1` through `Phase 9` below as belonging to this section
only.

**The whole sequence is still gated on Lyona's own `UPDATE-001…003`**
(`docs/P6-UPDATE-*.md`, `lyona-update`) **landing first**, exactly as it was
under the old numbering — restructuring the plan did not change that
dependency. Nothing in this section is scheduled; it exists so the next
person who picks this up starts from an accurate plan instead of a stale one.

### Why the old plan was replaced, not just updated

Two independent findings from the 2026-09-07 re-survey, both verified
against the live `dd55e58` source and the live Arch package databases, made
`SYNC-P10-SYSTEM-MANAGEMENT.md`'s foundation unsound rather than merely
out of date:

1. **The old plan's central premise — "the whole thing is written against
   PackageKit on Fedora and the provider layer must be replaced by a
   `PacmanBackend`" — is wrong.** `packagekit` on Arch ships
   `usr/lib/packagekit-backend/libpk_backend_alpm.so`: PackageKit is already
   a first-class `alpm`/`pacman` frontend on Arch, not a Fedora-only
   artefact. The genuinely Fedora-specific code (`read_fedora_identity()`,
   an RPM-database version gate, three delegated-tool paths) is small and
   localized. See
   [Phase 1's "second finding"](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#the-second-finding-that-reframes-the-whole-port)
   for the verified package table. This changes the entire port from "a
   from-scratch reimplementation of a Fedora subsystem" to either "adopt a
   working Python helper with small Arch substitutions" or "a deliberate,
   scoped decision not to" — see [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md)
   for the full option analysis and the recommendation.
2. **The `*-bus.py`/`*-provider.py` files earlier notes described as a
   shipped "Python D-Bus daemon architecture" are test fixtures.** They live
   under `tests/fixtures/`, not `scripts/`. The real shipped surface is one
   8,946-line `scripts/dwm-system-management` plus a handful of
   `config/quickshell/systemmanagement/*.qml` files — see the file table in
   [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#what-upstream-actually-built-verified-at-dd55e58-2026-09-07).
   There is no daemon and nothing Lyona would need to reach over a socket.

Independent of both findings, the regional-services scope
(`#242`–`#265`) alone had grown to a size that did not fit one document
alongside the update-journal half — hence the split into nine phases rather
than one restructured document.

### Position in the sequence

This whole port sits **after** every phase in the "Phase order" table above
(0–9, 11, all done) and **after** Lyona's own `ROADMAP.md` Phase 6 lands.
That prerequisite is not just a phase number — it is three concrete,
already-written design documents, none of them upstream-sync work (nothing
here ports code from `ChrisTitusTech/dwm-titus`; `lyona-update` is
Lyona-native, updating Lyona itself rather than Arch packages), tracked as
their own boundary group:

| Prerequisite | Document | Delivers | Status |
| --- | --- | --- | --- |
| UPDATE-001 | **Done** — see `CHANGELOG.md`, `TASKS.md` | An installed system that can state what it is running | Done (2026-09-08) |
| UPDATE-002 | [`P6-UPDATE-HELPER.md`](P6-UPDATE-HELPER.md) | `lyona-update` — check, stage, apply, roll back | Done (2026-09-08) |
| UPDATE-003 | [`P6-UPDATE-SURFACE.md`](P6-UPDATE-SURFACE.md) | Settings and Control Center surfaces over that helper | Done (2026-09-08) |

(`P6-UPDATE-OVERVIEW.md` indexes all three plus the architecture decisions
behind them; it is not its own boundary.) All three are implemented and
merged (`3c8adb2`, `d489f1f`, `fdb0995`) — the currently active `TASKS.md`
phase is now this section's own nine-phase sequence, starting with
[Sync Phase 1](#the-system-management-port). `P6-UPDATE-PROVENANCE.md` was
removed once implemented, per this project's plan-doc-retirement convention;
`P6-UPDATE-HELPER.md` and `P6-UPDATE-SURFACE.md` are kept despite being done
— [Sync Phase 3](SYNC-P3-SYSTEM-PANE.md) and
[Sync Phase 7](SYNC-P7-OPERATION-SURFACE.md) below cite `P6-UPDATE-SURFACE.md`'s
pane layout directly as design material for work that has not landed yet.

**The two efforts meet at exactly one point**, and it is worth naming
precisely rather than leaving as a vague "later": `P6-UPDATE-SURFACE.md`'s
Settings → System pane is explicitly laid out so an "Arch packages" group can
be added beside the "lyona" group **later, without rework** — that later is
[Phase 3](SYNC-P3-SYSTEM-PANE.md) (the pane itself) and
[Phase 7](SYNC-P7-OPERATION-SURFACE.md) (its confirm/cancel operation
surface) of this port. Outside that one shared pane, the two efforts share no
file and no helper — `lyona-update` never touches `dwm-system-management` or
PackageKit, and this port never touches release tarballs or `lyona-update`'s
own provenance stamp.

Within the nine-phase sequence itself the phases are linearly dependent —
each depends on the previous one's files existing — with one branch point:
Phases 5–7 (the update-mutation half) and Phases 8–9 (the regional half) do
not depend on each other and could in principle be worked in either order
once Phase 4 is done, but Phase 9 reuses Phase 5's journal directly, so
**Phase 5 must land before Phase 9 regardless of which half is tackled
first**.

| Phase | Document | Upstream | Depends on |
| --- | --- | --- | --- |
| 1 | [`SYNC-P1-SYSTEM-PROVIDER-DECISION.md`](SYNC-P1-SYSTEM-PROVIDER-DECISION.md) | `#207`, `#209`, `#265` | UPDATE-001…003 |
| 2 | [`SYNC-P2-UPDATE-SNAPSHOT.md`](SYNC-P2-UPDATE-SNAPSHOT.md) | `#208`, `#232`, `#241` | 1 |
| 3 | [`SYNC-P3-SYSTEM-PANE.md`](SYNC-P3-SYSTEM-PANE.md) | `#209`, `#210` | 2, [`P6-UPDATE-SURFACE.md`](P6-UPDATE-SURFACE.md)'s pane layout |
| 4 | [`SYNC-P4-DISCOVERY-EVENTS.md`](SYNC-P4-DISCOVERY-EVENTS.md) | `#237`, `#238`, `#260` | 3 |
| 5 | [`SYNC-P5-OPERATION-JOURNAL.md`](SYNC-P5-OPERATION-JOURNAL.md) | `#211`–`#225` | 2, [the decision point below](#the-decision-point-after-phase-4) |
| 6 | [`SYNC-P6-UPDATE-EXECUTION.md`](SYNC-P6-UPDATE-EXECUTION.md) | `#226`–`#234`, `#231` | 5 |
| 7 | [`SYNC-P7-OPERATION-SURFACE.md`](SYNC-P7-OPERATION-SURFACE.md) | `#235`, `#236`, `#239`–`#241`, `#262` | 6, [`P6-UPDATE-SURFACE.md`](P6-UPDATE-SURFACE.md)'s pane layout |
| 8 | [`SYNC-P8-REGIONAL-READERS.md`](SYNC-P8-REGIONAL-READERS.md) | `#242`–`#246`, `#248` | 4 |
| 9 | [`SYNC-P9-REGIONAL-MUTATION.md`](SYNC-P9-REGIONAL-MUTATION.md) | `#247`, `#249`, `#252`–`#254`, `#256`–`#258`, `#263`, `#264` | 5, 8, [**D-3**](#open-decisions) |

### The decision point after Phase 4

[Phase 4](SYNC-P4-DISCOVERY-EVENTS.md) completes everything upstream's
system-update feature can do **without** a durable journal — discovery,
live-watch, the Settings pane, all read-only. The journal
([Phase 5](SYNC-P5-OPERATION-JOURNAL.md), ~2,800 helper lines plus ~4,000
test lines) exists because a PackageKit D-Bus transaction leaves no evidence
once the daemon is gone. The question worth deciding explicitly before
starting Phase 5, rather than discovering the cost partway through: does
`/var/log/pacman.log`, `/var/cache/pacman/pkg`, and `pacman -Qu` already
answer "did that commit, and can I recover from a crash mid-transaction"
well enough that 2,800 lines are not worth it?

[Phase 5's own document](SYNC-P5-OPERATION-JOURNAL.md#read-this-before-starting)
lays out exactly what `pacman.log` can and cannot answer, and is explicit
that the journal is not optional if [Phase 9](SYNC-P9-REGIONAL-MUTATION.md)'s
regional mutations are wanted — a "did a `timezone-set` I dispatched but
never confirmed actually take effect" question has no package-manager log to
fall back on at all. **If the answer is "the journal is not worth it,"** the
honest outcome recorded here is: close Phases 5–7 as declined, keep Phases
8's read-only half only, and drop Phase 9 down to delegated-tool launches
without the timezone/NTP/locale mutation half (which needs the same
crash-durability guarantee the journal provides). This decision has **not**
been made — it is deferred to whoever picks Phase 5 up, with this section as
the record of what was already considered.

### Open decisions

Every phase above that depends on an unresolved choice names it here rather
than silently picking one. None of these block writing further plan
documents; all of them block **implementation**.

| ID | Question | Where it matters | Status |
| --- | --- | --- | --- |
| — | **The core decision**: adopt upstream's Python helper largely as-is (Option A), rewrite it in POSIX shell (Option B), or stop at a read-only shell-only subset (Option C)? | Every phase from [2](SYNC-P2-UPDATE-SNAPSHOT.md) onward changes shape depending on the answer | **Open.** [Phase 1](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#recommendation) recommends Option A with Option C as the fallback; recorded in that document's own `Decision:` line, not here, because it is a single project-owner call, not a per-item checklist. |
| **D-3** | Arch delegated-tool targets for `accounts-open` and `sources-open` — neither `lxqt-admin-user` nor `dnfdragora` exists in Arch's official repositories; `system-config-printer` (`printers-open`) does. | [Phase 9 §3](SYNC-P9-REGIONAL-MUTATION.md#open-decision-d-3-arch-targets-for-accounts-open-and-sources-open) | **Open.** Candidates: ship `unavailable` with an honest detail string, or an AUR-packaged equivalent behind `arch:system-management-optional` (the `xkbset` precedent). Phase 9's document is written either way; this decision must be settled before its delegated-launch buttons are implemented. |
| **D-4** | Does `pacman -Sup --print-format ... --dbpath "$CHECKUPDATES_DB"` genuinely stay read-only (no root, no live pacman lock) on a real CachyOS install? | [Phase 2, "If Option C was chosen"](SYNC-P2-UPDATE-SNAPSHOT.md) (§6) | **Open — unverified against a live system.** If it does not, the fallback (a polkit-mediated read-only helper) changes the privilege model for the whole update-read half and must be settled before Phase 2 is implemented, not discovered mid-implementation. |

### Verification

Each phase's own document has its exact commands; the summary:

| Phase | Command |
| --- | --- |
| 1 | `make check-arch-packages`, `make check-install`, `make check-settings` |
| 2 | `scripts/run-tests /usr/bin/python3 tests/test-system-management.py` |
| 3 | `make check-quickshell-system-management`, `make check-quickshell-qml` |
| 4 | `make check-quickshell-system-management`, `make check-quickshell-qml` |
| 5 | `scripts/run-tests /usr/bin/python3 tests/test-system-management.py` |
| 6 | `scripts/run-tests /usr/bin/python3 tests/test-system-management.py` |
| 7 | `make check-quickshell-system-management`, `make check-quickshell-qml` |
| 8 | `scripts/run-tests /usr/bin/python3 tests/test-system-management.py`, `make check-quickshell-system-management` |
| 9 | `scripts/run-tests /usr/bin/python3 tests/test-system-management.py`, `make check-quickshell-system-management` |

`check-system-management` (the Python gate registered in
[Phase 1 §6](SYNC-P1-SYSTEM-PROVIDER-DECISION.md#6-makefile-registration)) is
the `Makefile` target; the table above shows the underlying command for
direct use.

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
| — | System-management port: see [its own verification table](#the-system-management-port) — each of its nine phases has its own gate. |
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
