# Upstream Sync — ChrisTitusTech/dwm-titus → Lyona

Index for porting upstream work into Lyona. Upstream history is unrelated to
Lyona's (nothing can be merged), so every change is ported by hand. This file
carries the survey, the exclusions, the rules that apply everywhere, the open
decisions, and the **sprint plan**. Each sprint has its own document with
literal code.

**Current survey:** upstream `d155edc` (2026-09-18), found by Sprint 4's S4-08
re-survey. Earlier survey points: `94ca1a4` (2026-09-05), `03b2195`
(2026-09-06), `dd55e58` (2026-09-07), `d4c6d89` (2026-09-16).

---

## Where things stand

| Work | Status |
| --- | --- |
| Fork-era sync Phases 0–9 and 11 (DPI gate, standalone fixes, panel widgets, Settings layout, accessibility capabilities/contrast/motion/controls, XKB input, notifications, display apply, security hardening) | ✅ Done. Record in `CHANGELOG.md` and git history |
| Lyona's own `UPDATE-001…003` (`lyona-update`) | ✅ Done (`3c8adb2`, `d489f1f`, `fdb0995`) |
| System-management Sync Phases 1–9 (upstream `#207`–`#265`) | ✅ Done, through `92ec6e2` (PR #33). Tracking for #33 closes in [Sprint 1 S1-02](SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md#s1-02-close-the-sync-phase-9-tracking-gap) |
| **Sprint 1** ([`SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`](SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md)) | ✅ Done, merged `e947fa7` (#68) |
| **Sprint 2** ([`SYNC-SPRINT-2-SYSTEM-INFORMATION.md`](SYNC-SPRINT-2-SYSTEM-INFORMATION.md)) | ✅ Done (2026-09-19) — closes `ROADMAP.md` Phase 6, see its own "Completion Evidence" |
| **Sprint 3** ([`SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`](SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md)) | ✅ Done, merged to `main` (through `ed5ba44`) |
| **Sprint 4** ([`SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`](SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md)) | 🚧 **Code complete; qualification open.** S4-01 to S4-07 done, and S4-08's re-survey done (2026-09-20). Left, none of which can run in a sandbox: the manual **Full suite** workflow (sprint branch and `main`), and checks that need real hardware or installs: the Picom NVIDIA backend (S4-01), the fresh-install media defaults on both ISOs (S4-02), and a full privileged `lyona-update` run (S4-06) |
| **Sprint 5** ([`SYNC-SPRINT-5-SETTINGS-LOADING-FLATHUB-FLOATING.md`](SYNC-SPRINT-5-SETTINGS-LOADING-FLATHUB-FLOATING.md)) | 🚧 **Code complete; qualification open.** From S4-08's re-survey (`d4c6d89..d155edc`, 12 commits): S5-01 (Settings panes stay hidden until their data loads, completes `#315`), S5-02 (verified Flathub before Flatpak installs) and S5-03 (floating-toggle shrink, decision D-9: port as upstream) are done. Left, none of which can run in a sandbox: the manual **Full suite** workflow on the sprint branch and on `main`, and a hands-on check of the floating toggles and Settings panes on a real desktop (S5-01, S5-03) |
| Upstream since `dd55e58`: 98 commits (78 non-merge, ~22k lines of applicable code and tests), Chris's issues `#302`–`#315`, plus 7 older PRs found unported | 📋 Ported through Sprint 3 and Sprint 4 S4-01…S4-07 |

## Sprint plan

Five sprints (Sprint 5 came from Sprint 4's re-survey). The request was 3 if
possible and 5 at most. Three was ruled out
by size: after declining the Fedora-only work and the git-based desktop
updater (D-8), about 16k lines of port remain, and three sprints would put
more than 5k lines of heavily diverged QML into each. Each sprint below is
sized to one reviewable branch per item.

| Sprint | Document | Scope | Upstream | Depends on |
| --- | --- | --- | --- | --- |
| **1** | [`SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md`](SYNC-SPRINT-1-SYSTEM-MANAGEMENT.md) | **Manual full-suite CI workflow**; close #33 tracking; native discovery/origins QML; confirmed delegated admin; regional settings model; shared clock; NTP sample, interruption recovery, `watch-time`; package progress; carried-over gaps (D-4, parser/owner harnesses) | `#251`Q, `#259`Q, `#261`, `#262`, `#266`–`#276`, `#291` (system) | — |
| **2** | [`SYNC-SPRINT-2-SYSTEM-INFORMATION.md`](SYNC-SPRINT-2-SYSTEM-INFORMATION.md) | System information, hardware, filesystems, security status, root encryption, screen-lock evidence, mount monitor, information card, Health navigation; **close `ROADMAP.md` Phase 6** | `#277`–`#288` + fixes | Sprint 1 (S1-03) |
| **3** | [`SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md`](SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md) | Relative monitor placement, docked/undocked profiles, **`#310` battery gating (new)**, Control Center compaction, Settings readiness and lazy panes, **`#315` layout stability (new)**, Power menu / full-screen Settings / cursor reload / Blueman / Self-Heal, Appearance and typography, popup blur fix, pre-survey gaps | `#289`, `#290`, `c3e9a18`, `#291` (Settings), `#294`, `#295`, `#307`, `#324`, `#327`, `68a0d1f`, `#183`, `#188`, `#191` | — (one hunk touches Sprint 1's `SystemRegionalControls.qml`) |
| **5** | [`SYNC-SPRINT-5-SETTINGS-LOADING-FLATHUB-FLOATING.md`](SYNC-SPRINT-5-SETTINGS-LOADING-FLATHUB-FLOATING.md) | Settings panes stay hidden until data loads (`#335`, completes `#315`), verified Flathub before Flatpak installs (`#334`), floating-toggle shrink (`#331`/`#333`, decision D-9) | `#329`–`#339` (issues `#330`, `#332`) | Sprint 3 (S5-01 replaces S3-05's placeholder) |
| **4** | [`SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md`](SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md) | Configuration-backed Picom controls, **`#308` media/image defaults**, icon themes + theme convergence (the XSETTINGS lock fix, `#328`, turned out not to apply to Lyona), installer/session fixes, dwmterm (declined), desktop-update UX (D-8), N/A record, re-survey and qualification | `#312`–`#314`, `3d982b8`, `#317`, `#301`, `#328`, `#283`, `#255`, `#318`–`#323`, Fedora-only commits | Sprint 3 (S3-07) for S4-01 |

Sprints 1→2 and 3→4 are ordered. **The two pairs are independent**, so
Sprint 3 can run before or alongside Sprint 2. **Sprint 5** exists because
S4-08's re-survey found new upstream work; it follows Sprint 3 and is
independent of the rest of Sprint 4. A **Sprint 6** is only needed if a later
re-survey finds more.

The GitHub milestones and issues for these sprints are created by
[`sync-sprints-github.sh`](sync-sprints-github.sh). See its header for usage.

---

## Open decisions

Every open item blocks **implementation** of the listed item, not the plan.

| ID | Question | Blocks | Recommendation | Status |
| --- | --- | --- | --- | --- |
| **D-4** | Does `pacman -Sup --dbpath "$CHECKUPDATES_DB"` stay read-only (no root, no live `pacman.lck`) on real CachyOS? | Confidence in the update-read half (already shipped) | Verify with `strace` on a real install | **Open**. S1-10 |
| **D-5** | Security readers on Arch: SELinux and firewalld are Fedora defaults | S2-02 | — | **Decided (2026-09-16), asked of the user directly**: port `FirewalldRead` unchanged (reword "unit absent" for Arch), keep SELinux `unsupported` as-is, **and build new `ufw`/`nftables` readers** so most real Arch firewall setups show status, not just firewalld. New scope beyond upstream; see S2-02 |
| **D-6** | Self-Heal default when `~/.config/lyona/self-heal.path` is unset | S3-06 | — | **Decided (2026-09-16), asked of the user directly**: upstream parity — stays user-configured only, no default script. No `dwm-system-health` auto-wiring |
| **D-7** | Upstream `#327` scales spacing by font scale and divides by `devicePixelRatio`; Lyona scales geometry by DPI through `Theme.dp()` | S3-07 | — | **Decided (2026-09-16), asked of the user directly**: port desktop typography and font-size scaling (`scaledFontSize()`) only; `Theme.dp()` stays the one geometry scale, `scaledSize()` is not ported. Verify `devicePixelRatio == 1.0` at 144 DPI before starting, as originally planned. **Amended (2026-09-20), asked of the user directly, when the port reached `AppearanceModel.qml`:** `applySharedTypography()`/`desktopFont*` read `font` and `text-size` selections from upstream's personalization provider, and Lyona's `dwm-settings-toolkit` only has `cursor icon gtk qt` (typography lives in the separate `dwm-settings-font` managed-shell backend, GTK/Qt font policy out of scope). Decision: **keep the managed shell font and text scale**; don't port `desktopFont*`/`applySharedTypography()`, the `personalization.conf`/`gsettings monitor` watchers, or upstream's removal of the "duplicate" font controls (in Lyona they are the only font controls). Still ported: `scaledFontSize()` and the 0.75–2.0 clamp, every per-surface fix (`Theme.dp()` in place of `scaledSize()`), the wallpaper hunks. `devicePixelRatio` was verified to be 1.0 at 144 DPI under Lyona's `QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1` launch |
| **D-8** | Upstream's git-`main` desktop updater (`#318`–`#323`, issue `#311`) vs Lyona's release-tarball `lyona-update` | S4-06 | — | **Decided (2026-09-16), asked of the user directly**: decline the mechanism; port the four UX ideas (restart-surviving progress window, panel indicator, completion notification, bounded log viewer) onto `UpdateModel.qml` against `lyona-update`'s existing status file |
| **D-9** | Upstream `#331`/`#333` make toggling floating (and switching to the floating layout) shrink the window to 85% and center it; Lyona floats at the current tile size, so nothing visibly happens | S5-03 | 2026-09-20 | **Decided: port as upstream** (85%, centered, clamped to the work area as far as the window's size hints allow, on explicit toggles and on entering the floating layout). Lyona had upstream's exact pre-fix `dwm.c`, so it applied cleanly |
| — | Converge Lyona's #33 regional/delegated UI onto upstream's `#261`–`#269` structure | S1-03…S1-05 | — | **Decided in the Sprint 1 plan** (2026-09-16): converge. Lyona's `launchDelegated()` skips the confirmation `ROADMAP.md` Phase 6 requires, and every later upstream PR builds on upstream's shape |
| D-3 | Arch targets for `accounts-open`/`sources-open` | — | — | **Decided** 2026-09-15: permanent `unsupported` |
| — | Option A/B/C for the system-management helper | — | — | **Decided** 2026-09-08: Option A (adopt upstream's Python helper) |
| — | `JOURNAL_RESTART_SESSION_STRENGTH` lacks `unknown` | — | — | **Closed as not-a-gap** (S1-10): upstream `d4c6d89` has the same three members, and nothing sets session `unknown` |

---

## Already in Lyona — excluded from every sprint

These upstream changes are **done, superseded or declined**. They're recorded
so they aren't re-applied.

| Upstream | Lyona equivalent | Notes |
| --- | --- | --- |
| `1c16634` *Prefer ChatGPT desktop app* | `7bd6a54` | Launcher half; `webapp-launch` half (`#197`) done in sync Phase 1 |
| `d15432c` *keep floating windows above tiled (#196)*, issue `#185` | `809f456` + `8adfa21` | **Superseded.** Lyona's `restackprioritywindows()` is stronger. **Don't** apply upstream's hunk; it would double-stack |
| `e2137c2`, `2dec690` (`#320`) *codeql-action bumps* | n/a | Lyona has no `codeql.yml` |
| `d03531a`, `52e51c4` (`#194`) *Astro docs site* | n/a | **Declined.** Lyona keeps mdBook |
| `edb5478` (`#189`), and the AGENTS/CONTRIBUTING/PR-template hunks of `d359a4f`, `080b39e` | n/a | Upstream's own agent review workflow |
| `46837e5`, `a1cb86c` (`#316`) *README* | `b85539b` | Lyona branding |
| `5f806af`, `3770b04` (`#205`), `ce7fbbb` (`#206`), `aedc962`, `7bc9897`, `c76a124`, `c67db36`, `5237ad9`, `fc5eeda` *qualification docs* | `docs/evidence/` | Fedora evidence. Sprint 2's S2-07 uses the Phase 6 ones as a checklist |
| `b0e9b0e` (`#182`), `46991ca` (`#184`) *personalization backend*; `scripts/dwm-xsettings` | `dwm-settings-toolkit`, `dwm-settings-display` | **Pre-fork divergence.** Every later `dwm-xsettings` hunk is retargeted (S3-06, S4-03) |
| `7eafe40` (`#180`), `097a205` (`#181`) | present | Checked 2026-09-16: reverse-apply shows the content with later Lyona edits |
| `f4f477c` *appearance watcher lifecycle* | `core/WatchedProcess.qml` | Lyona's reusable component |
| `68a0d1f` *avoid decoding the full wallpaper collection on reload* | `scripts/dwm-settings-wallpaper` `choose_default_wallpapers()` | **Already solved differently.** Lyona reservoir-samples names and decodes only the sample; upstream's `find` + draw-without-replacement rewrite isn't taken. `#327`'s status/rollback hunk (metadata-only listing) is ported in S3-07 |
| DPI hot reload | `2a49ffd` | Lyona-only. `Theme.uiScale`/`Theme.dp()` don't exist upstream. See D-7 |
| `82abbf9` (`#326`) *CI: desktop smoke only* | `CHANGELOG.md` "Reduce hosted CI to one Arch build and desktop smoke job" | **Done.** Sprint 1 S1-01 adds the manual full-suite workflow beside it |
| `4d776bc` (`#191`) *group accessibility settings* | — | Grouping **diverged by decision** (sync Phase 6). Refresh coalescing ported in S3-09 |
| `c8f574b` (`#188`) *qualify optional component isolation* | `check-phase5-optional-components`, `tests/test-quickshell-settings-xvfb.sh` | **Ported in S3-09, adapted.** `dwm-settings-personalization` maps to `dwm-settings-toolkit` (no delegate or text-size records in Lyona), so the qualification compares the toolkit and managed-font providers instead; `docs/P5-OPTIONAL-COMPONENTS.md` and `docs/P5-STATUS.md` are not ported |
| Fedora image, kickstart, Anaconda, offline-image, release commits: `40cbdc8` (`#293`), `0c5daf0` (`#292`), `44800ba` (Fedora half), `a218d63`, `536e4a5`, `975174d`, `c679937` (image half), `f956582` (`#325`), `c2a98ae`, `5c875cc` | archiso, `build-iso.yml` | **N/A.** Reasons and evidence: [Declined Fedora, image and release work](#declined-fedora-image-and-release-work-s4-07) |
| `45063de`, `a08985a`, `639c5b4` | — | Empty chore commits |

### Declined Fedora, image and release work (S4-07)

Recorded with reasons so the decisions outlive the sprint plan. Every claim
about Lyona below was re-checked on 2026-09-20; none of this is code.

| Upstream | Why it is not taken | Evidence in Lyona |
| --- | --- | --- |
| `0c5daf0` (`#292`) | Fedora kickstart `%post` only | Lyona installs through `install.sh`; there is no kickstart |
| `40cbdc8` (`#293`) | Anaconda installer branding | The ISO is built on archiso with Lyona's own themes: `scripts/lyona-grub-theme`, `scripts/lyona-plymouth-theme`, layered onto the releng profile by `scripts/build-lyona-arch-iso.sh` |
| `44800ba` | Fedora 44 image qualification | Its non-Fedora hunks were ported: focused-screen Settings in S3-06, the `daemon-reload` before the graphical session in S4-04 |
| `a218d63`, `536e4a5` | Upstream v0.7.0 release notes and source-upgrade pinning | Lyona has its own calendar versions, `docs/RELEASING.md` and `docs/RELEASE-NOTES-*.md` |
| `975174d`, `f956582` (`#325`) | Offline Fedora system images on Cloudflare downloads | `.github/workflows/build-iso.yml` attaches the ISO and `SHA256SUMS` to a GitHub release (`gh release upload` / `gh release create`) |
| `c679937` (`#300`), image half | `scripts/image/*`, `build-dwm-fedora-*`, PackageKit image checks, `docs/P8-*` | Fedora image tooling. The MIME hunk went to S4-02 |
| `a1cb86c` (`#316`), `46837e5` | Upstream README | Lyona's own README (`b85539b`) |
| `e2137c2`, `2dec690` (`#320`) | `codeql-action` bumps | No CodeQL workflow exists: `.github/workflows/` holds `build-iso.yml`, `c-cpp.yml`, `docs.yaml` and `full-suite.yml`, and `.github/` only `dependabot.yml` |
| `c2a98ae`, `5c875cc` | Fedora CI job and hosted QML-job assertions | Lyona's CI is its own (`c-cpp.yml`, `full-suite.yml`) |
| `82abbf9` (`#326`) | Hosted CI reduced to a desktop smoke job | **Already done**: `CHANGELOG.md` "Reduce hosted CI to one Arch build and desktop smoke job" |
| `45063de`, `a08985a`, `639c5b4` | "trigger desktop update button test" chores | Verified empty: no files changed in any of the three |
| AGENTS / CONTRIBUTING / PR-template hunks of `d359a4f`, `080b39e` | Upstream's own agent review workflow | Lyona has its own review process |

**`config/starship/starship.toml` (+18, from `c679937`): reviewed, not taken.**
The rule was to take it only if Lyona's prompt lacked the same modules. It has
them: `mybash`'s `starship.toml` (the shell profile `install-mybash` installs)
already configures `directory`, `git_branch` and `git_status`, in a fuller
powerline layout. The one real difference is how colors are chosen. Upstream's
file uses named terminal colors, so the prompt follows the terminal theme by
itself; `mybash` uses hex palettes picked with its `starship-theme` helper (13
of them, including `nord`, `dracula` and `tokyonight`), which do not follow
Lyona's active theme automatically. Making the prompt follow the theme is a
change to `technicks89/mybash`, not a port, so it is left there.

### Lyona-only assets the port must reuse rather than duplicate

| Component | Path | Replaces upstream's |
| --- | --- | --- |
| `WatchedProcess` | `config/quickshell/core/WatchedProcess.qml` | Inline `Process` + settle and restart timers |
| `StatusCard` | `config/quickshell/core/StatusCard.qml` | Inline `component StatusCard` per pane |
| `Theme.dp()` / `Theme.uiScale` | `config/quickshell/core/Theme.qml` | Raw pixel constants, and upstream `#327`'s `scaledSize()` (D-7) |
| `tests/lib.sh`, `tests/test-lib.sh` | `tests/` | Bare `grep`/`test` assertions |
| `tests/qml/tst_*.qml` under `qmltestrunner` | `tests/qml/` | Upstream's bespoke `ShellRoot` harnesses in `tests/qml/*.qml` |
| `lyona-update` | `scripts/lyona-update`, `config/quickshell/system/UpdateModel.qml` | Upstream's desktop updater (D-8) |
| `dwm-display-profile` | `scripts/dwm-display-profile` | Coexists with upstream's autorandr profiles (S3-02) |
| `flock -w 5 -x 9` under `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}` | `dwm-settings-font`, `dwm-settings-toolkit` | Upstream's `/tmp/dwm-titus-$UID` |

---

## Global adaptation rules

Apply to **every** sprint item; they aren't repeated in the sprint documents.

| Upstream | Lyona |
| --- | --- |
| `~/.config/dwm-titus/…`, `dwm-titus/…` path segments, `# dwm-titus …` markers | `~/.config/lyona/…`, `lyona/…`, `# lyona …` |
| `${XDG_RUNTIME_DIR:-/tmp/dwm-titus-$UID}` | `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}` |
| `scripts/dwm-settings-personalization`, `scripts/dwm-xsettings` | `scripts/dwm-settings-toolkit`, `scripts/dwm-settings-display` |
| `fedora:*` package profiles, `*.ks`, `tests/test-fedora-*`, `scripts/image/*` | `arch:*` in `scripts/dwm-packages.sh`, `archiso/packages.x86_64`, `tests/test-arch-*` |
| "Fedora", `dnf`, `rpm`, Anaconda in user-facing text | Arch/CachyOS, `pacman`, the Lyona ISO |
| Raw pixel constants in QML | `Theme.dp(...)` |
| Upstream `tests/qml/Foo.qml` harness | `tests/qml/tst_foo.qml` (`TestCase`), or an xvfb shell test when a live process is needed |
| `docs/src/content/*.md` (Astro) | `docs/src/*.md` (mdBook) |
| `make` target `dwm` | `all` |
| Helper name `dwm-*` | **Keep unchanged**, to keep future diffs clean |

Every new **shell** helper registers in three places: `Makefile`
`INSTALL_COMMANDS`, `check-shell`, `check-format`. (Sprint 5 S5-02's
`scripts/dwm-flatpak-setup` is the latest; its test is `check-gearlever-install`.)

**Python helpers** register in `INSTALL_COMMANDS` only, plus their own
Python test target. `check-shell`/`check-format` don't read them. The
complete list, including planned ones:

| Helper | Test target | Since |
| --- | --- | --- |
| `scripts/dwm-system-management` | `check-system-management` | Sync Phase 1 |
| `scripts/dwm-settings-display-profiles` | `check-display-profiles` | Sprint 3 S3-02 |
| `scripts/dwm-cursor-reload` | `check-cursor-reload` | Sprint 3 S3-06 |
| `scripts/dwm-xkbset` | `check-xkbset` | AUR removal (`docs/AUR-PACKAGES.md`); replaces the AUR-only `xkbset` |
| `scripts/dwm-settings-picom` | `check-picom`, `check-picom-xvfb` | Sprint 4 S4-01 |

Don't add another without a row here.

### Porting method (lessons from Sync Phases 7–9)

1. **Diff every cited upstream PR on its own**, Python *and* QML. A
   QML-only fetch of a multi-PR phase dropped `#241`'s Python half, and every
   confirm control shipped permanently disabled until it was found.
2. **Diff against upstream's actual end state for the item, never against a
   previous phase's boundary SHA.** Lyona's order isn't upstream's
   chronological order.
3. **Helper (`scripts/dwm-system-management`)**: Lyona's copy is upstream
   `dd55e58` + 1,176 lines of adaptation, so upstream commits apply
   patch-then-fix (`git apply --3way`, then run the Python suite).
4. **Heavily diverged QML** (`SystemManagementModel.qml`,
   `AppearanceSettingsPane.qml`, `DisplaySettingsPane.qml`): rebase rather
   than hand-merge. Take upstream's file at the item's boundary SHA and
   re-apply Lyona's recorded adaptations. The exceptions, where Lyona's file
   must win, are named in each sprint item.
5. **Verify claims in plan docs against shipped code** before relying on
   them. Several earlier phase docs were wrong about scope; each sprint doc
   names what it checked.

---

## Chris Titus issues and PRs

Every issue and PR opened by `ChrisTitusTech` on `ChrisTitusTech/dwm-titus`
since the fork (2026-08-27) is accounted for. All his PRs are merged; none
are open.

### Issues

| Issue | Upstream state | Lyona |
| --- | --- | --- |
| `#185` Keep floating windows above tiled | closed | Done (superseded, see exclusions) |
| `#195` Resolution size dropdown | closed | Done (sync Phase 9: `#198`, `#200`) |
| `#302` Settings full screen like System Health | closed by `#307` | Sprint 3 S3-06 |
| `#303` Appearance scroll glitches | closed by `#307` | Sprint 3 S3-06 |
| `#304` Cursor not uniform until reboot | closed by `#307` | Sprint 3 S3-06 |
| `#305` Hide Blueman icon | closed by `#307` | Sprint 3 S3-06 |
| `#306` Self-Heal in Quick Actions | closed by `#307` | Sprint 3 S3-06 (D-6) |
| `#308` Celluloid, mpv, sxiv + media defaults | **open** (Fedora-only fix `3d982b8`) | Sprint 4 S4-02 |
| `#309` Config-based Picom opacity + GPU-aware backend | closed by `#312`–`#314` | Sprint 4 S4-01 |
| `#310` Hide dock profiles without a battery | **open, no upstream code** | Sprint 3 S3-03, Lyona's own implementation |
| `#311` Configuration update detection and sync | closed by `#318`–`#323` | Sprint 4 S4-06 (D-8); `lyona-update` covers it. Acceptance re-verified 2026-09-20 in `tests/test-lyona-update.sh`: up to date reports `current`; outdated reports `behind` and offers it; **deferring (answering no) leaves the install record, backups and `update.conf` unchanged (this had no test; added)**; an unreachable network reports `offline` without failing |
| `#315` No layout shift while Settings panels load | closed by `#335` (2026-09-19) | Sprint 3 S3-05 covered only the component load, Lyona's own implementation; upstream's data-load fix ported in **Sprint 5 S5-01** |
| `#330` Kickstart: default boot partitions, one partition for `/` and `/home` | closed | N/A (Fedora kickstart) |
| `#332` Flatpak and Flathub before any Flatpak install | closed by `#334` | Sprint 5 S5-02 |

Earlier issues (`#73`, `#142`–`#147`, `#150`) predate the fork.

### PRs

| PRs | Lyona |
| --- | --- |
| `#180`–`#184` | Pre-fork, present, or pre-fork divergence (exclusions); `#183` → Sprint 3 S3-09 |
| `#186`, `#190`, `#196`–`#204` | Done (fork-era sync Phases 1–9) |
| `#188`, `#191` | Sprint 3 S3-09 |
| `#189`, `#194`, `#205`, `#206` | Excluded |
| `#207`–`#249`, `#252`–`#258`, `#260`, `#263`–`#265` | Done (system-management Sync Phases 1–9) |
| `#250`, `#251`, `#259` | Python halves done in Sync Phase 9; QML halves → Sprint 1 S1-03 |
| `#261`, `#262` | Sprint 1 S1-03 |
| `#266`–`#276` | Sprint 1 S1-04…S1-08 |
| `#277`–`#288` | Sprint 2 |
| `#289`, `#290`, `#291`, `#294`, `#295`, `#307`, `#324`, `#327` | Sprint 3 (`#291`'s system half → S1-09) |
| `#296`, `#299`, `#300` | Merge PRs for `44800ba`/`a218d63`/`536e4a5`, `975174d`, `c679937`: N/A except the hunks named in S3-06, S4-02 and S4-04 |
| `#312`–`#314`, `#317`, `#318`–`#319`, `#321`–`#323`, `#325`, `#326`, `#328` | Sprint 4, or excluded/done as listed |
| `#329` | N/A: upstream's git-`main` desktop updater (D-8) |
| `#331`, `#333` | Sprint 5 S5-03 (decision D-9) |
| `#334` | Sprint 5 S5-02 |
| `#335` | Sprint 5 S5-01 |
| `#336`, `#337`, `#338`, `#339` | N/A: Fedora installer defaults, Cloudflare ISO links, 0.7.1 changelog and docs |

---

## Commit coverage since `dd55e58`

Every non-merge upstream commit from `dd55e58..d155edc`, and where it goes.
The 20 merge commits in the first range (`3f962b7`, `abe0d97`, …) and the 8
in `d4c6d89..d155edc` carry no content of their own. To list anything newer
than this survey:

```bash
git -C "$U" fetch && git -C "$U" log --no-merges --reverse --format='%h %ad %s' --date=short d155edc..origin/main
```

| Upstream | Date | Subject | Lyona |
| --- | --- | --- | --- |
| `826760a` | 2026-09-07 | feat(system): guard delegated action confirmations (#266) | S1-04 |
| `c63d525` | 2026-09-07 | feat(settings): expose confirmed delegated administration controls (#… | S1-04 |
| `08e97d3` | 2026-09-07 | feat(system): coordinate regional preparation and confirmation (#268) | S1-05 |
| `2b94db9` | 2026-09-07 | feat(settings): expose confirmed regional controls (#269) | S1-05 |
| `f69a38e` | 2026-09-07 | feat(settings): share timezone-aware minute clock (#270) | S1-06 |
| `ebf7a31` | 2026-09-08 | feat(settings): expose bounded NTP sample command (#271) | S1-07 |
| `3bef09c` | 2026-09-08 | fix(settings): preserve regional recovery on interruption (#272) | S1-07 |
| `75ca9c2` | 2026-09-08 | feat(settings): add scoped time discovery interfaces (#273) | S1-07 |
| `0c97c83` | 2026-09-08 | feat(settings): validate finite QML time observations (#274) | S1-08 |
| `38eef6a` | 2026-09-08 | feat(settings): reconcile time-service owner arrivals (#275) | S1-08 |
| `3c9f0fe` | 2026-09-08 | feat(settings): sample visible network time status (#276) | S1-08 |
| `d6f028f` | 2026-09-08 | feat(settings): add bounded local information readers (#277) | S2-01 |
| `30dc7fb` | 2026-09-08 | feat(settings): add bounded hardware information reads (#278) | S2-01 |
| `95ca81a` | 2026-09-08 | feat(settings): add bounded filesystem information reads (#279) | S2-01 |
| `b40c832` | 2026-09-08 | feat(system): add bounded security status readers (#280) | S2-02 |
| `8e4ad74` | 2026-09-08 | feat(system): add bounded root encryption evidence (#281) | S2-02 |
| `92c4543` | 2026-09-08 | feat(system): reuse bounded automatic screen-lock status | S2-03 |
| `76d0739` | 2026-09-08 | fix(power): validate and scope automatic-lock evidence | S2-03 |
| `2fe6f7d` | 2026-09-08 | fix(power): keep unverified lock state unknown in the UI | S2-03 |
| `378f06e` | 2026-09-08 | fix(install): avoid false validation failures (#283) | S4-04 |
| `5b246a0` | 2026-09-08 | feat(system): add bounded mount change monitor | S2-04 |
| `dbbfde1` | 2026-09-08 | fix(system): stop idle mount monitor when its reader closes | S2-04 |
| `c2a98ae` | 2026-09-08 | ci: allow the full Fedora validation job to finish | N/A (S4-07) |
| `7954c54` | 2026-09-08 | feat(system): assemble bounded information provider records | S2-05 |
| `994011f` | 2026-09-08 | fix(system): preserve read cancellation and reject mount overflow | S2-04 |
| `177e3c3` | 2026-09-08 | feat(system): activate bounded information snapshot lifecycle | S2-05 |
| `088069b` | 2026-09-08 | fix(system): watch socket hangup without treating input as closure | S2-04 |
| `cc96efd` | 2026-09-08 | feat(settings): show system information and recovery guidance | S2-06 |
| `6ac6f5a` | 2026-09-08 | fix(system): require observable pipe output for mount monitoring | S2-04 |
| `5237ad9` | 2026-09-08 | docs(system): record final pipe contract validation | S2-07 (docs) |
| `b19fb90` | 2026-09-08 | fix(system): isolate subscription callbacks and recovery reads | S2-05 |
| `fc5eeda` | 2026-09-08 | docs(system): record subscription and recovery qualification | S2-07 (docs) |
| `3232932` | 2026-09-08 | fix(system): retain optional diagnostics during core recovery | S2-05 |
| `aedc962` | 2026-09-08 | docs: complete Phase 6 system management qualification | S2-07 (docs) |
| `0c9d07c` | 2026-09-08 | fix(settings): keep Health navigation on the Settings screen | S2-06 |
| `4aee614` | 2026-09-08 | test(system): preserve snapshot modes through composed fixtures | S2-05 |
| `7bc9897` | 2026-09-08 | docs: qualify final Phase 6 navigation and capability inventory | S2-07 (docs) |
| `39ce924` | 2026-09-08 | test(system): wait for sampled reads before regional UI admission | S2-06 |
| `c76a124` | 2026-09-08 | docs: record final regional fixture validation follow-up | S2-07 (docs) |
| `c67db36` | 2026-09-08 | docs: record passing final Phase 6 suite and close evidence boundaries | S2-07 (docs) |
| `55dbd76` | 2026-09-09 | Add relative monitor placement and numbered display preview (#289) | S3-01 |
| `6b7548b` | 2026-09-09 | Add user-controlled docked and undocked display profiles (#290) | S3-02 |
| `902a138` | 2026-09-09 | feat(terminal): add first-class dwmterm integration (#255) | S4-05: **declined.** `dwmterm` is in neither the official Arch repositories nor the AUR (re-checked 2026-09-20), and making an unpackaged terminal the first probe would make `dwm-terminal` miss every time. Lyona's terminal stays `alacritty`. Only the incidental `check-deps.sh` terminal-list fix is ported |
| `40cbdc8` | 2026-09-10 | feat(branding): add dark Anaconda installer branding and dynamic vers… | N/A (S4-07) |
| `0c5daf0` | 2026-09-10 | fix(kickstart): prevent gearlever failure from aborting post phase (#… | N/A (S4-07) |
| `d359a4f` | 2026-09-10 | Fix Settings readiness and progress with local review gates (#291) | S1-09 + S3-05 |
| `080b39e` | 2026-09-10 | Reduce Settings startup work and tighten local review loops (#294) | S3-05 |
| `8df119c` | 2026-09-10 | test: await notification persistence before Settings restart (#295) | S3-05 |
| `44800ba` | 2026-09-10 | Finish Phase 7 Fedora image and desktop qualification | S3-06 + S4-04; rest N/A |
| `a218d63` | 2026-09-10 | Prepare v0.7.0 release notes and changelog | N/A (S4-07) |
| `536e4a5` | 2026-09-10 | Pin source upgrade instructions to the release tag | N/A (S4-07) |
| `975174d` | 2026-09-11 | Add offline system images and Cloudflare installation downloads | N/A (S4-07) |
| `c679937` | 2026-09-11 | Improve offline ISO performance and fresh-install defaults (#300) | S4-02 (MIME); rest N/A |
| `69240ea` | 2026-09-12 | Fix initial theme convergence and include icon themes in installer de… | S4-03 |
| `56ec27b` | 2026-09-12 | Polish Quickshell Power menu, Settings, and Self-Heal (#307) | S3-06 |
| `47b533f` | 2026-09-12 | Stabilize Picom Appearance controls and add opacity settings (#312) | S4-01 |
| `d907a02` | 2026-09-12 | Fix post-merge Picom review findings from PR 312 (#313) | S4-01 |
| `9859fb2` | 2026-09-13 | Fix Picom import rollback and explicit-root review findings (#314) | S4-01 |
| `e5d8325` | 2026-09-13 | Fix sxiv and Feh discovery in image defaults (#317) | S4-02 |
| `a1cb86c` | 2026-09-14 | update README (#316) | N/A (S4-07) |
| `fa74a18` | 2026-09-13 | Add desktop updates with progress to System Settings (#318) | S4-06 (D-8): mechanism covered by `lyona-update`; completion notification ported |
| `32011b8` | 2026-09-13 | Fix desktop update authorization visibility and live status (#319) | S4-06 (D-8): mechanism covered by `lyona-update` (status file, polkit) |
| `45063de` | 2026-09-13 | chore: trigger desktop update button test | N/A (empty chore) |
| `7a51070` | 2026-09-14 | fix: reuse one authorization for desktop updates | S4-06 (D-8): verified, nothing to port. Apply asks once (its two `run_privileged` sites are release vs checkout), rollback once; a failed step is not re-prompted. Pinned by `tests/test-lyona-update.sh` |
| `a08985a` | 2026-09-14 | chore: trigger desktop update button test | N/A (empty chore) |
| `fbee78f` | 2026-09-14 | feat: keep desktop update progress visible (#321) | S4-06 (D-8): UX ported as `UpdateProgressWindow.qml` and a `DwmPanel` indicator driven by `UpdateModel`; mechanism covered. Tested by `tests/test-quickshell-update-progress-xvfb.sh` |
| `639c5b4` | 2026-09-14 | chore: trigger desktop update button test | N/A (empty chore) |
| `42aefbe` | 2026-09-14 | fix: simplify desktop update actions (#322) | S4-06 (D-8): mechanism covered by `lyona-update` |
| `6097491` | 2026-09-14 | fix: simplify update progress and log actions (#323) | S4-06 (D-8): bounded log viewer ported. `lyona-update` did not write a log (the plan assumed it did), so it now writes `update.log`, and the model reads only its last 64 KiB |
| `c44dae4` | 2026-09-14 | fix: keep panel outside blurred popup surfaces (#324) | S3-08 |
| `2dec690` | 2026-09-14 | ci: bump github/codeql-action from 4.37.9 to 4.38.0 (#320) | N/A (S4-07) |
| `f956582` | 2026-09-14 | docs: update install guide for refreshed offline ISOs (#325) | N/A (S4-07) |
| `82abbf9` | 2026-09-14 | ci: replace full hosted validation with desktop smoke (#326) | Done already |
| `3d982b8` | 2026-09-14 | fix: seed Fedora media defaults without overwriting user choices | S4-02 |
| `5c875cc` | 2026-09-14 | test: remove obsolete hosted QML job assertions | N/A (S4-07) |
| `68a0d1f` | 2026-09-14 | fix: avoid decoding the full wallpaper collection on reload | S3-07 |
| `a5b829d` | 2026-09-16 | Simplify Appearance and unify desktop font scaling (#327) | S3-07 |
| `d4c6d89` | 2026-09-16 | fix: prevent XSETTINGS from retaining installation locks (#328) | S4-03: **not needed, pinned by a test.** Lyona has no `dwm-xsettings`, `theme-apply.sh` never starts `xsettingsd` (it edits the config and sends `SIGHUP`), and no install path holds a lock descriptor. Verified by running the real script under a held lock with real `gsettings`/`xfconf-query`: the lock is free afterwards and no process holds it. `tests/test-theme-apply-install-lock.sh` keeps it true |
| `5c7140f` | 2026-09-17 | fix: allow approved desktop updates to replace system contents (#329) | N/A (upstream's git-`main` updater, D-8) |
| `2e77c11` | 2026-09-18 | fix: make floating toggles visibly shrink windows (#331) | S5-03 (D-9) |
| `841d3cd` | 2026-09-18 | fix: shrink tiled windows when entering floating layout (#333) | S5-03 (D-9) |
| `f0abbdb` | 2026-09-18 | fix: preserve shared root and home in Fedora installer defaults | N/A (Fedora installer) |
| `dd64bbf` | 2026-09-18 | fix: prepare verified Flathub before Flatpak installs for 0.7.1 | S5-02 |
| `709bcd0` | 2026-09-18 | fix: stabilize Settings layout during initial provider reads | S5-01 |
| `f02d965` | 2026-09-18 | fix: require explicit disk selection in public installers | N/A (Fedora installer) |
| `af7cc1d` | 2026-09-18 | docs: clarify Anaconda disk preselection and storage review | N/A (Fedora installer) |
| `4b0d438` | 2026-09-18 | fix: wait for all initial Settings reads and queued refreshes | S5-01 |
| `222378b` | 2026-09-18 | docs: use stable Cloudflare ISO download names | N/A (Cloudflare ISO links) |
| `4e05248` | 2026-09-18 | docs: finalize 0.7.1 changelog | N/A (dwm-titus release notes) |
| `f31a7b9` | 2026-09-18 | docs: finish migrating ISO references to universal download URLs | N/A (Cloudflare ISO links) |

---

## Verification

Before any sprint item merges:

```bash
scripts/run-tests make clean all             # C build stays clean
scripts/run-tests make check-shell           # shellcheck, incl. every new shell helper
scripts/run-tests make check-format          # shfmt
scripts/run-tests make check-quickshell-qml  # configured QML lint
QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
```

Each sprint document lists its own gates. Before a sprint closes:

```bash
scripts/run-tests make check
```

Then run **Actions → Full suite (manual)** (added in Sprint 1 S1-01) on the
sprint branch, and record the run URL in `docs/evidence/`.

### Manual qualification

The only way to catch DPI, compositor and real-service interactions:

1. Fresh LightDM login on Arch/CachyOS, then a `startx` session.
2. Multi-monitor with mismatched DPI: change DPI in Settings and confirm the shell rescales without a restart. Repeat once per sprint that touches geometry (Sprints 1, 2, 3).
3. High contrast + reduced motion, then hot-reload a theme. The palette changes **and** the overrides survive.
4. Closed-CPU baseline: 30 s closed vs 30 s with Settings open and with the Control Center open. New watchers (time, locale, accounts, printers, mounts, Picom) must leave it flat.
5. `make install` / `make uninstall` round-trip, which proves every new helper reached `INSTALL_COMMANDS`.
6. Standard **and** NVIDIA ISO installs (Sprint 4).

## Commit and tracking

One branch and PR per sprint item, or per tightly coupled pair where a sprint
doc says so. Each item updates `TASKS.md`, `CHANGELOG.md` and
`docs/evidence/` **in the same PR** that delivers the behavior, per
`AGENTS.md`. Sync Phase 5 and #33 both missed this, and Sprint 1 S1-02
exists only to clean up after it.

When a sprint's items are all merged, delete its `SYNC-SPRINT-N-*.md`
document, per this project's convention that plans are removed once
implemented, and mark it ✅ in the sprint plan table above.

### Retired plan documents

Removed on 2026-09-16 once implemented. Code comments that still cite them
resolve from git history (`git show 92ec6e2:docs/<name>`):

`SYNC-P1-SYSTEM-PROVIDER-DECISION.md`, `SYNC-P2-UPDATE-SNAPSHOT.md`,
`SYNC-P3-SYSTEM-PANE.md`, `SYNC-P4-DISCOVERY-EVENTS.md`,
`SYNC-P5-OPERATION-JOURNAL.md`, `SYNC-P6-UPDATE-EXECUTION.md`,
`SYNC-P7-OPERATION-SURFACE.md`, `SYNC-P8-REGIONAL-READERS.md`,
`SYNC-P9-REGIONAL-MUTATION.md`, `P6-UPDATE-OVERVIEW.md`,
`P6-UPDATE-HELPER.md`, `P6-UPDATE-SURFACE.md`.

Earlier: `SYNC-P0-DPI-GATE.md`, `SYNC-P1-STANDALONE.md`,
`P5-PANEL-WIDGETS-PORT.md`, `P5-SETTINGS-LAYOUT-PORT.md`,
`SYNC-P4-A11Y-CAPABILITIES.md`, `SYNC-P5-CONTRAST-MOTION.md`,
`SYNC-P6-A11Y-CONTROLS.md`, `SYNC-P7-XKB-INPUT.md`, `SYNC-P8-NOTIFICATIONS.md`,
`SYNC-P9-DISPLAY-APPLY.md`, `SYNC-P10-SYSTEM-MANAGEMENT.md`,
`SYNC-P11-SECURITY-HARDENING.md`, `P6-UPDATE-PROVENANCE.md` — use the parent
of the commit that removed each one.

`docs/P6-SYSTEM-MANAGEMENT.md` is **kept**. It's the living protocol contract
for `dwm-system-management`, and Sprints 1–2 extend it.
