# Sync Sprint 4 — Picom controls, fresh-install defaults, update UX, qualification

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Upstream surveyed at `d4c6d89`.
S4-01 depends on [Sprint 3's S3-07](SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md#s3-07-appearance-simplification-and-desktop-typography),
which removes the old Picom rows from Appearance. Everything else here is
independent.

**Goal:** finish the upstream backlog, decide the upstream features that don't
map onto Arch, and re-qualify the whole desktop with the manual full-suite
workflow from Sprint 1.

| Item | Upstream | Kind | Size |
| --- | --- | --- | --- |
| [S4-01](#s4-01-configuration-backed-picom-controls) | `#312` `47b533f`, `#313` `d907a02`, `#314` `9859fb2` — closes issue `#309` | Port | ~+2,900 |
| [S4-02](#s4-02-media-and-image-defaults-on-fresh-installs) | issue **`#308` (open)**, `3d982b8`, `#317` `e5d8325`, `c679937` (MIME hunk) | Port + new work | ~+350 |
| [S4-03](#s4-03-icon-themes-and-first-login-theme-convergence) | `#301` `69240ea`, `#328` `d4c6d89` | Port | ~+40 |
| [S4-04](#s4-04-installer-and-session-fixes) | `#283` `378f06e`, `44800ba` (autostart hunk) | Port | ~+90 |
| [S4-05](#s4-05-terminal-dwmterm) | `#255` `902a138` | **Decline, partial port** | ~+10 |
| [S4-06](#s4-06-desktop-update-experience) | `#318`, `#319`, `7a51070`, `#321`, `#322`, `#323` — issue `#311` | Decline mechanism, port UX (D-8 decided) | ~+700 |
| [S4-07](#s4-07-declined-fedora-image-and-release-work) | `#292`, `#293`, `44800ba`, `a218d63`, `536e4a5`, `975174d`, `#300` (image half), `#316`, `#325`, `#320`, `c2a98ae`, `5c875cc`, chores | Record as N/A | docs only |
| [S4-08](#s4-08-re-survey-and-release-qualification) | — | Qualification | — |

---

## S4-01: Configuration-backed Picom controls

Upstream issue `#309`: *"Picom theme mutation controls keep appearing and
disappearing … Use the Picom configuration file as the source of truth …
sliders for foreground and background opacity … account for the GPU in use
when choosing the backend."*

### What upstream built

- `scripts/dwm-settings-picom` — **new**, Python, ~1,250 lines after `#313`/`#314`.
  Commands: `status | watch | start | restart | reload | stop | toggle` plus
  mutations. Uses a JSON protocol (version 1). It edits `picom.conf` while
  **preserving comments and unrelated libconfig values**, writes a managed
  block between `# dwm-titus opacity defaults begin/end`, validates candidates
  with `picom --diagnostics`, and imports an existing config into
  `~/.config/picom/include/dwm-titus-import/` with rollback.
- **GPU-aware backend** (`renderer()`/`backend()`): read `picom
  --diagnostics` for the GL vendor and renderer. `auto` → `glx` on
  accelerated Intel/AMD, otherwise `xrender`. NVIDIA gets `xrender` plus
  `--xrender-sync-fence`. If `glx` fails at launch under `auto`, fall back to
  `xrender`.
- `config/quickshell/appearance/PicomModel.qml` (127) and
  `config/quickshell/settings/PicomSettingsPane.qml` (146): foreground and
  background opacity sliders, backend selector, start/stop.
- `AppearanceModel.qml` −42, `dwm-settings-appearance` −71: the old checks are removed.
- `scripts/autostart.sh`: start via `dwm-settings-picom start` instead of `picom --backend "$PICOM_BACKEND"`.
- `scripts/theme-apply.sh`: `dwm-settings-picom reload` after a theme applies, so opacity follows the theme.
- `scripts/dwm-quickshell-controlcenter`: `restart-picom`/`toggle-compositor` delegate to the helper.
- Tests: `tests/test-picom.py` (431 + 94 + 192), `tests/test-picom-xvfb.py` (557 + 42).

### Port

```bash
for c in 47b533f d907a02 9859fb2; do
  git -C "$U" show "$c" -- scripts/dwm-settings-picom config/quickshell/appearance/PicomModel.qml \
    config/quickshell/settings/PicomSettingsPane.qml tests/test-picom.py tests/test-picom-xvfb.py
done
```

Take those five files from upstream at `9859fb2`, then apply the Lyona adaptations:

```diff
-BEGIN = "# dwm-titus opacity defaults begin"
-END = "# dwm-titus opacity defaults end"
+BEGIN = "# lyona opacity defaults begin"
+END = "# lyona opacity defaults end"
```

Change every `"dwm-titus/picom"` and `"dwm-titus-import"` path segment to
`"lyona/picom"` and `"lyona-import"`. Run `grep -n dwm-titus
scripts/dwm-settings-picom tests/test-picom*.py` and expect **zero** hits.

**Existing-config migration:** a user who already ran upstream's helper
won't exist on Lyona, so no legacy-marker migration is needed.

**`scripts/autostart.sh`** (Lyona `:352` and `:528`):

```diff
-PICOM_BACKEND=${PICOM_BACKEND:-xrender}
 …
-start_detached_once picom picom --backend "$PICOM_BACKEND"
+if command -v picom >/dev/null 2>&1; then
+	picom_helper=$(command -v dwm-settings-picom 2>/dev/null || printf '%s' "${0%/*}/dwm-settings-picom")
+	"$picom_helper" start >/dev/null 2>&1 &
+fi
```

`PICOM_BACKEND` stays honored. The helper reads it as an override.

**`scripts/theme-apply.sh`**, at the end of the non-transactional path:

```diff
+# Opacity is global. Reapply the current configuration without writing it into
+# theme transactions or their rollback archives. A stopped compositor stays stopped.
+if [[ $TRANSACTIONAL_APPLY == 0 && -n ${DISPLAY:-} ]] && command -v picom &>/dev/null; then
+	PICOM_HELPER=${DWM_APPEARANCE_PICOM_HELPER:-$script_dir/dwm-settings-picom}
+	if [[ -x $PICOM_HELPER ]]; then
+		"$PICOM_HELPER" reload >/dev/null ||
+			echo 'theme-apply: Picom reload failed; see Appearance > Compositor' >&2
+	fi
+fi
```

**`scripts/dwm-quickshell-controlcenter`** (Lyona `:1472`, `:1554`):

```diff
 restart_picom() {
-	pkill -x picom 2>/dev/null || true
-	if command -v picom >/dev/null 2>&1; then
-		launch_background picom
-		notify "Picom restarted"
-	else
+	if ! command -v picom >/dev/null 2>&1; then
 		printf 'picom is not installed\n' >&2
 		return 1
 	fi
+	dwm-settings-picom restart >/dev/null && notify "Picom restarted"
 }
 …
 toggle_compositor() {
-	if pgrep -x picom >/dev/null 2>&1; then
-		pkill -x picom
-		notify "Compositor stopped"
-	else
-		restart_picom
-	fi
+	dwm-settings-picom toggle >/dev/null && notify "Compositor toggled"
 }
```

(Lyona's current `launch_background picom` starts Picom **without**
`--backend`, which is inconsistent with `autostart.sh`. The helper fixes that
as a side effect.)

**`Makefile`**:

```diff
 INSTALL_COMMANDS = \
+	scripts/dwm-settings-picom \
 …
+check-picom:
+	$(call run_managed_test,/usr/bin/python3 tests/test-picom.py)
+
+check-picom-xvfb:
+	$(call run_managed_test,/usr/bin/python3 tests/test-picom-xvfb.py)
+
 check:
 …
+	$(MAKE) check-picom
+	$(MAKE) check-picom-xvfb
```

(and `.PHONY`). Python helper, so no `check-shell`/`check-format` entry. Add it
to `UPSTREAM-SYNC.md`'s Python-helper exception list.

**Lyona NVIDIA image:** the NVIDIA ISO variant (`AGENTS.md` "Arch Image
Rules") is exactly where `renderer()` returns `nvidia`. On that image,
verify on real hardware that `auto` resolves to `xrender` +
`--xrender-sync-fence` and that tearing is acceptable. Record the result in
`docs/evidence/`. Also confirm `picom --diagnostics` works without a
running compositor on the NVIDIA proprietary driver.

`tests/test-quickshell-design-system.sh` +3/−2 (`#314`) and
`tests/test-autostart.sh` +7 ride along.

---

## S4-02: Media and image defaults on fresh installs

Upstream issue **`#308`, still open**. Upstream `3d982b8` implemented it for
Fedora only. `#317` fixed discovery for `NoDisplay=true` viewers (sxiv's
`.desktop` sets it). `c679937` added three image MIME types.

All three packages are in Arch `extra`: `celluloid` 0.30, `mpv`, and `sxiv`
26. `nsxiv` 34 also exists and is the maintained fork, but `#308` names
`sxiv`, so keep parity. Revisit in `ROADMAP.md` Future Evaluation.

**`scripts/dwm-packages.sh`**:

```diff
+	arch:media)
+		# Fresh-install media and image defaults (upstream #308).
+		printf '%s\n' celluloid mpv sxiv desktop-file-utils
+		;;
 …
 	arch:recommended)
 		dwm_packages "$family" desktop
+		dwm_packages "$family" media
 		dwm_packages "$family" system-management
```

Add the same three packages to `archiso/packages.x86_64`. The ISO's
postinstall runs `install.sh --profile full`, which pulls `recommended`, so
no archiso script change is needed. `tests/test-arch-iso-builder.sh` checks
that the files stay in sync.

**`scripts/dwm-default-apps`** — `#317` applies cleanly:

```diff
 desktop_usable() {
 	local file=$1
-	local type hidden nodisplay try_exec exec_value exec_command
+	local type hidden try_exec exec_value exec_command
 	parse_desktop_file "$file" || return 1
 	type=$desktop_parsed_type
 	hidden=$desktop_parsed_hidden
-	nodisplay=$desktop_parsed_nodisplay
 	try_exec=$desktop_parsed_try_exec
-	[[ $type == Application && $hidden != true && $nodisplay != true ]] || return 1
+	# NoDisplay hides menu entries, but still permits MIME associations.
+	[[ $type == Application && $hidden != true ]] || return 1
 …
 parsed_desktop_matches_role() {
 	local role=$1
+	# Preserve menu visibility filtering for the browser, file-manager and terminal roles.
+	[[ $desktop_parsed_nodisplay != true ]] || return 1
```

…and `c679937`'s MIME list:

```diff
 supported_mimes=(
 …
+	image/gif
+	image/bmp
+	image/tiff
```

`tests/test-dwm-default-apps.sh` +48/−2.

**New file `scripts/seed-default-apps.sh`**: upstream's script, adapted.
Browser seeding is dropped because Lyona doesn't ship `brave-origin`, and the
file-manager entry is kept:

```bash
#!/bin/bash
# Seed fresh accounts with media/image defaults; never replace existing preferences.
set -euo pipefail
[[ $(id -u) != 0 ]]
[[ $# == 0 ]]
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
# Desktop-specific files take precedence over the generic MIME file too.
shopt -s nullglob
for file in "$config_home/mimeapps.list" "$config_home/"*-mimeapps.list \
	"$data_home/applications/mimeapps.list" "$data_home/applications/"*-mimeapps.list \
	"$data_home/applications/defaults.list"; do
	if [[ -e $file || -L $file ]]; then
		printf 'Preserving existing application defaults: %s\n' "$file"
		exit 0
	fi
done
# Resolve installed XDG entries, validate all handlers before writing, and
# advertise only the media/image formats supported by those entries.
associations=$(
	python3 - <<'PY'
import configparser
import os
from pathlib import Path
import shutil
import sys

roots = [Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))]
roots += [Path(p) for p in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':') if p]

def entry(desktop, command, prefixes, required=True):
    path = next((root / 'applications' / desktop for root in roots
                 if (root / 'applications' / desktop).is_file()), None)
    if path is None or shutil.which(command) is None:
        if required:
            sys.exit(f'Missing default application: {desktop} ({command})')
        return
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(path)
    app = parser['Desktop Entry']
    if app.get('Hidden', 'false').lower() == 'true' or app.get('Type') != 'Application':
        sys.exit(f'Unusable default application: {desktop}')
    mimes = [m for m in app.get('MimeType', '').split(';') if m.startswith(prefixes)]
    if not mimes:
        sys.exit(f'No supported MIME types advertised by {desktop}')
    for mime in mimes:
        print(f'{mime}={desktop};')

entry('io.github.celluloid_player.Celluloid.desktop', 'celluloid', ('audio/', 'video/', 'application/'))
entry('sxiv.desktop', 'sxiv', ('image/',))
entry('thunar.desktop', 'thunar', ('inode/directory',), required=False)
PY
)
# Atomic publication avoids leaving a partial MIME file after an error.
mkdir -p "$config_home"
target=$(mktemp "$config_home/.lyona-mimeapps.XXXXXX")
trap 'rm -f "$target"' EXIT
printf '[Default Applications]\n%s\n' "$associations" >"$target"
# Link the complete file without replacing a preference written since the
# initial check. A rename would silently overwrite that concurrent choice.
if ! ln -T -- "$target" "$config_home/mimeapps.list"; then
	if [[ -e $config_home/mimeapps.list || -L $config_home/mimeapps.list ]]; then
		printf 'Preserving existing application defaults: %s\n' "$config_home/mimeapps.list"
		exit 0
	fi
	printf 'Could not publish application defaults: %s\n' "$config_home/mimeapps.list" >&2
	exit 1
fi
printf 'Configured fresh-account media, image, and file-manager defaults.\n'
```

Verify the desktop-file IDs on Arch before merging:
`pacman -Fl celluloid sxiv | grep '\.desktop$'`. Arch's `sxiv` may install
`sxiv.desktop` under a different ID.

**`install.sh`**: seed **before** Gear Lever, which writes its own AppImage
MIME preference file, and only on a fresh account. Lyona's Gear Lever block
is at `:756`–`:783`, and `make install-user` is at `:940`:

```diff
 make install-user \
 …
+# Seed before Gear Lever creates its AppImage MIME preference file.
+if install_recommended_profile; then
+	bash "$REPO_DIR/scripts/seed-default-apps.sh" ||
+		warn "Media/image defaults were not seeded; set them in Settings > Defaults."
+fi
```

Move the existing `if install_recommended_profile; then … install-gearlever …`
block to **after** this call (upstream `3d982b8` does the same move).

**`Makefile`**: add `scripts/seed-default-apps.sh` to `check-shell` and
`check-format`, since it's a shell script. It's install-time only, so not
`INSTALL_COMMANDS`. Add a `tests/test-seed-default-apps.sh` modeled on
upstream's `tests/test-image-user-defaults.sh` (+84) to `check-default-apps`.
It should cover: existing `mimeapps.list` is preserved, a missing required
handler exits non-zero without writing anything, and a concurrent file
created between check and link is preserved.

**`#308`'s own acceptance, on Lyona:** a fresh ISO install (standard **and**
NVIDIA) and an existing-system `install.sh` both open `.mkv` in Celluloid and
`.png` in sxiv from Thunar, and still do after logout and reboot.

---

## S4-03: Icon themes and first-login theme convergence

**`#301`** (`69240ea`):

```diff
 	arch:theme)
-		printf '%s\n' dconf
+		printf '%s\n' dconf adwaita-icon-theme papirus-icon-theme
 		;;
```

(+ `archiso/packages.x86_64`). And in `Makefile` `install-user`, before the
success banner:

```diff
+	@echo "==> Applying initial theme convergence..."
+	HOME="${USER_HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" scripts/theme-apply.sh
```

`USER_HOME` and `XDG_CONFIG_HOME` are defined the same way in Lyona's
`Makefile` (`:9`–`:10`), and `scripts/theme-apply.sh` is already installed
(`Makefile:94`).

**`#328`** (`d4c6d89`): upstream's `dwm-xsettings` started `xsettingsd` with
inherited `flock` descriptors from `make install`, so the install lock was
never released. **Lyona has no `dwm-xsettings`.** It starts `xsettingsd`
only from `scripts/autostart.sh:400`–`:406`, never from an install path, so
the bug doesn't exist today. **It appears the moment the `#301` hunk above
makes `install-user` run `theme-apply.sh`**, if S3-06's cursor work makes
`theme-apply.sh` start or reload `xsettingsd`. Guard both with the same fix
upstream used:

```diff
-		setsid -f xsettingsd -c "${XDG_CONFIG_HOME:-$HOME/.config}/lyona/xsettingsd.conf" \
+		# Install guards pass lock descriptors through make and theme convergence.
+		# Close every inherited descriptor before starting the session daemon.
+		python3 -c 'import subprocess, sys
+subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL,
+                 close_fds=True, start_new_session=True)' \
+			xsettingsd -c "${XDG_CONFIG_HOME:-$HOME/.config}/lyona/xsettingsd.conf" \
```

Apply this wherever `xsettingsd` is launched after S3-06. Port upstream's
`tests/test-dwm-xsettings.sh` +13 case into `tests/test-autostart.sh`:
start under an open `flock` fd 9 and assert the lock is released after the
launcher returns.

---

## S4-04: Installer and session fixes

**`#283`** (`378f06e`). Lyona's `scripts/dev-sync-install.sh:386` has the
exact pre-fix code:

```diff
 	if [ -n "$dwm_pid" ]; then
-		running_executable=$(readlink "/proc/$dwm_pid/exe" 2>/dev/null || true)
-		case $running_executable in
-		*" (deleted)") dwm_restart_required=1 ;;
-		esac
-		if [ "$dwm_restart_required" -eq 0 ] &&
-			! cmp -s "/proc/$dwm_pid/exe" "$binary_target"; then
+		# Reinstallation can unlink the running executable without changing its
+		# bytes. Proc still exposes that inode; compare it even when deleted.
+		if ! cmp -s "/proc/$dwm_pid/exe" "$binary_target"; then
 			dwm_restart_required=1
 		fi
 	fi
```

`tests/test-dev-sync-install.sh` +71/−1 (a reinstall with identical bytes
doesn't demand a dwm restart). Upstream's `tests/test-fedora-packages.sh` hunk
is N/A.

**`44800ba` autostart hunk:** refresh generated user units before starting the
graphical-session target, so installer-seeded autostart exclusions apply on
the first login:

```diff
+# Refresh generated entries first: an installer may have seeded user exclusions
+# after this user manager started, even when the wm shim already exists.
-	if systemctl --user start "$WM_GRAPHICAL_SESSION" 2>/dev/null ||
-		{
-			systemctl --user daemon-reload 2>/dev/null &&
-				systemctl --user start "$WM_GRAPHICAL_SESSION" 2>/dev/null
-		}; then
+	if systemctl --user daemon-reload 2>/dev/null &&
+		systemctl --user start "$WM_GRAPHICAL_SESSION" 2>/dev/null; then
```

The anchor is Lyona's `scripts/autostart.sh:500`–`:504`. Update
`tests/test-autostart.sh` (+2/−1).

---

## S4-05: Terminal dwmterm

Upstream `#255` (by a contributor, not Chris) makes `dwmterm` the first
default terminal, adds a window rule, theme colors and `SIGUSR1` reload.
**`dwmterm` isn't packaged for Arch**: it's in neither the official
repositories nor the AUR (checked 2026-09-16). **Decline** the dwmterm
integration: Lyona's terminal is `alacritty` (`arch:terminal-primary`), and
promoting an unpackaged terminal first would make `dwm-terminal`'s first
probe always miss.

Port only the incidental fix, which widens `scripts/check-deps.sh`'s terminal
fallback list (Lyona `:130`, `:137`), without `dwmterm`:

```diff
-for term in alacritty kitty st; do
+for term in alacritty kitty st warp-terminal xterm; do
 …
-	printf "  ${RED}✗${NC} No supported terminal found ${YELLOW}(install alacritty, kitty, or st)${NC}\n"
+	printf "  ${RED}✗${NC} No supported terminal found ${YELLOW}(install alacritty, kitty, st, warp-terminal, or xterm)${NC}\n"
```

Record the decline in `UPSTREAM-SYNC.md`.

---

## S4-06: Desktop update experience

### What upstream built (`#318`–`#323`, closing issue `#311`)

A GUI updater for **dwm-titus itself against `main`**: it compares managed
file hashes and a git revision, builds in a sandbox, and installs through one
polkit authorization with a root-owned helper. It adds a separate **progress
window that survives Quickshell restarts**, a **panel indicator**, a
**completion notification**, and a **bounded log viewer**. About 5,500 lines,
~2,100 of them tests.

### What Lyona already has

`lyona-update` (UPDATE-001…003, done): check / apply / rollback against
**signed release tarballs**, with SHA-256 verification against the GitHub
release asset digest, staging, backups, a restart-surviving status file
(`scripts/lyona-update:56`), and Settings/Control Center surfaces
(`config/quickshell/system/UpdateModel.qml`).

### Decision D-8 — decided, asked of the user directly

Upstream's *mechanism* (git `main`, hash manifest, sandboxed build) solves
issue `#311` differently from Lyona's release-tarball design, and would make
Lyona track an unreleased branch. **Decided (2026-09-16): decline the
mechanism, port the UX.** Record `#318`, `#319`, `7a51070`, `#321`, `#322`
and `#323` as "mechanism covered by `lyona-update`; UX ported below". Issue
`#311`'s acceptance ("up-to-date reports none; outdated offers it; defer
leaves config unchanged; network failure is graceful") is already met by
`tests/test-lyona-update.sh` — re-verify each point and record it, but no new
code is needed for the acceptance criteria themselves.

**UX port:** four user-visible ideas, taken onto `UpdateModel.qml` with no
mechanism change:

| Idea | Upstream source | Lyona shape |
| --- | --- | --- |
| Progress stays visible across the Quickshell restart that `apply` triggers | `#321` `fbee78f` | Settings already rereads `lyona-update`'s status file on open. Add a small `UpdateProgressWindow.qml` that opens on `shell.qml` start when that status is `restarting` or in progress |
| Panel indicator while an update runs | `#321` | One `IconText` in `DwmPanel.qml` bound to `UpdateModel.busy`; click reopens progress |
| Completion notification | `#318` | `notify-send` from `lyona-update` on `succeeded`/`failed`, which is where status is written |
| Bounded log viewer | `#323` `6097491` | "View log" reading the last 64 KiB of the log `lyona-update` already writes |
| One authorization per update | `7a51070` | `lyona-update` escalates with `pkexec` once (`scripts/lyona-update:463`). Verify apply does exactly one prompt; nothing to port if so |

About 700 lines with tests. Each row is independent — land them as separate
commits, one per idea, so the progress window doesn't block the smaller
notification/log-viewer additions if it needs more design work than
expected.

---

## S4-07: Declined Fedora, image and release work

Record in `UPSTREAM-SYNC.md`'s exclusions table. No code.

| Upstream | Why N/A |
| --- | --- |
| `#292` `0c5daf0` | Fedora kickstart `%post` only |
| `#293` `40cbdc8` | Anaconda installer branding. Lyona uses archiso + its own GRUB/Plymouth themes |
| `44800ba` | Fedora 44 image qualification. The non-Fedora hunks went to S3-06 and S4-04 |
| `a218d63`, `536e4a5` | dwm-titus v0.7.0 release notes |
| `975174d`, `f956582` (`#325`) | Offline Fedora system images on Cloudflare downloads. Lyona releases ISOs through `build-iso.yml` on GitHub releases |
| `c679937` (`#300`), image half | `scripts/image/*`, `build-dwm-fedora-*`, PackageKit image checks. The MIME hunk went to S4-02. **Review** `config/starship/starship.toml` (+18): Lyona's shell profile is `technicks89/mybash`, so take it only if that config lacks the same prompt module |
| `#316` `a1cb86c` | dwm-titus README |
| `#320` `2dec690`, `c2a98ae`, `5c875cc` | CodeQL bump, Fedora CI job, hosted QML-job assertions. Lyona has no CodeQL, and its CI is its own |
| `#326` `82abbf9` | **Already done** in Lyona: `CHANGELOG.md` "Reduce hosted CI to one Arch build and desktop smoke job" |
| `45063de`, `a08985a`, `639c5b4` | Empty "trigger desktop update button test" chores |
| `d359a4f`/`080b39e` AGENTS/CONTRIBUTING/PR-template hunks | Upstream's own agent review workflow |

---

## S4-08: Re-survey and release qualification

1. **Re-survey upstream** before closing the sprint:

   ```bash
   git -C "$U" fetch && git -C "$U" log --no-merges --format='%h %ad %s' --date=short d4c6d89..origin/main
   ```

   Also re-list Chris's issues and PRs:
   `https://api.github.com/repos/ChrisTitusTech/dwm-titus/issues?creator=ChrisTitusTech&state=all&since=2026-09-16T00:00:00Z`.
   Anything new becomes a Sprint 5, if needed (the plan allows five), with a
   new survey SHA in `UPSTREAM-SYNC.md`.
2. **Manual full suite:** run **Actions → Full suite (manual)** on the sprint
   branch and on `main` after merge. Record both run URLs.
3. **Hardware and VM qualification**, from `UPSTREAM-SYNC.md`'s "Manual
   qualification" list, plus this sprint's own:
   - Standard **and** NVIDIA ISO → fresh install → media defaults (S4-02), icon themes (S4-03), Picom `auto` backend (S4-01).
   - Theme switch → Picom opacity follows it and the sliders reflect the result.
   - Existing Picom config with comments → import → comments are byte-identical outside the managed block.
4. `ROADMAP.md`: add the D-5 firewall limitation, the D-8 decision, and the
   Self-Heal default from S3-06 as limitations or Future Evaluation items.

## Verification

```bash
scripts/run-tests make clean all check-shell check-format check-quickshell-qml
scripts/run-tests make check-picom check-picom-xvfb check-appearance check-quickshell-appearance-model \
  check-quickshell-controlcenter check-quickshell-design-system check-default-apps \
  check-arch-packages check-archiso check-install check-install-preservation \
  check-dev-sync-install check-lyona-update
scripts/run-tests make check     # then the manual workflow
```

## Closes

Upstream `#301`, `#312`–`#314` (issue `#309`), `#317`, `#283`, `#328`,
`3d982b8`, the `c679937` MIME hunk, the `44800ba` autostart hunk, issue `#308`
(for Lyona); decisions for `#255`, `#318`–`#323` / issue `#311`, and every
Fedora-only commit since `dd55e58`.
