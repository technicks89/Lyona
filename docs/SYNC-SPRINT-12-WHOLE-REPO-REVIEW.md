# Sync Sprint 12 -- Whole-repository review: security, efficiency, engineering, architecture

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Independent of Sprints 1 to 11.
It comes from four parallel reviews of `main` at `5e5faad` (2026-09-27), one per
perspective: software architecture, software engineering, efficiency (CPU, RAM,
GPU, power) and cyber security. The engineering and architecture reviews were
static. The efficiency and security reviews also ran the real dwm, Quickshell and
Picom in an isolated Xvfb session (own display, `dbus-run-session`, private HOME
and XDG directories; never the live desktop), so their measurements are real,
though on llvmpipe with no PipeWire, UPower or playerctl.

**This document records every finding, unreviewed.** The maintainer asked for all
of them to be written down first and reviewed afterwards, so nothing here is
approved, and no item has started. Items marked with a decision gate need that
decision before implementation.

Source of each finding: **A** architecture, **E** engineering, **F** efficiency,
**S** security. **Verified** means the finding was re-checked against the code
by the coordinating session after the reviews came back; **measured** means a
reviewer reproduced it at runtime; **reported** means it comes from one review
and has not been independently re-checked yet: check it first when the item
starts.

| Item | Issue | Area | Severity | Gate |
| --- | --- | --- | --- | --- |
| [S12-01](#s12-01-rollback-restores-only-what-root-has-checked) | `#164` | Security, root helper | High | none |
| [S12-02](#s12-02-release-install-hashes-and-builds-one-root-owned-copy) | `#165` | Security, root helper | Medium-High | none (D-14 declined for now; step 3 deferred) |
| [S12-03](#s12-03-the-root-helper-writes-and-builds-nothing-through-user-paths) | `#166` | Security, root helper | Medium-High | none (D-15 decided) |
| [S12-04](#s12-04-dwm-always-starts-with-working-keys-and-a-config-file-cannot-hang-it) | `#167` | Robustness, dwm | High | none |
| [S12-05](#s12-05-the-toml-parser-handles-comments-same-line-arrays-and-booleans) | `#168` | Correctness, dwm | Medium | none |
| [S12-06](#s12-06-untrusted-text-renders-as-plain-text) | `#169` | Security, shell | High | none |
| [S12-07](#s12-07-watchers-stop-polling-for-their-parent) | `#170` | Efficiency | High | none |
| [S12-08](#s12-08-the-state-bridge-coalesces-events-and-stops-forking-per-window) | `#171` | Efficiency | High | none |
| [S12-09](#s12-09-stop-needless-work-on-events) | `#172` | Efficiency | Medium | none |
| [S12-10](#s12-10-power-and-memory-defaults) | `#173` | Efficiency, power | High | none (D-13 decided) |
| [S12-11](#s12-11-install-and-update-correctness) | `#174` | Correctness, installer | Medium | none |
| [S12-12](#s12-12-overview-close-asks-the-window-hidden-windows-and-thumbnail-tests) | `#175` | Correctness, overview | Medium | none |
| [S12-13](#s12-13-one-runtime-source-for-helpers) | `#176` | Architecture | Medium | none (D-16 decided) |
| [S12-14](#s12-14-one-reader-per-shared-format-one-copy-of-shared-safety-logic) | `#177` | Architecture | Medium | none |
| [S12-15](#s12-15-privileged-helper-consistency-the-package-map-and-lint-coverage) | `#178` | Architecture, security | Medium | none |
| [S12-16](#s12-16-split-dwm-system-management-and-move-test-ipc-out-of-the-shell) | `#179` | Architecture | Low | none |
| [S12-17](#s12-17-docs-and-specs-agree-with-the-code) | `#180` | Docs | Medium | none (D-17a, D-17b decided) |
| [S12-18](#s12-18-smaller-hardening) | `#181` | Security, hardening | Low | none |
| [S12-19](#s12-19-release-updates-can-install-the-published-release-asset) | `#184` | Correctness, updater | High | none |
| [S12-20](#s12-20-calendar-and-weather-panel-widgets) | `#193` | Feature, panel | Low | D-19 (weather only) |
| [S12-21](#s12-21-a-staged-helper-always-brings-its-libraries) | `#199` | Test reliability | Medium | none |

**Suggested order:** S12-01 to S12-03 first (the privileged update helper, found
independently by three reviews), then S12-04 and S12-06, then the idle-cost items
S12-07, S12-08 and S12-10, then the rest. S12-13 and S12-14 are the largest; they
reduce the surface the others touch, but nothing else depends on them.

**Threat model for the security items.** Both polkit actions are `auth_admin`, so
nothing reaches root without an administrator password. The realistic attacker is
code already running as the desktop user (a compromised application, extension or
package). Findings S12-01 to S12-03 let that code plant something that runs as
root the next time the user authenticates a routine update or rollback.

## New decisions

| ID | Question | Blocks | Recommendation |
| --- | --- | --- | --- |
| **D-13** | Turn DPMS (screen blanking) on by default, 600 s? Today it is off, so screens never blank | S12-10 | **Decided (2026-09-27), asked of the user directly:** yes. After 10 minutes idle the screen turns off and the desktop locks. Users can change or turn off both in the Control Center |
| **D-14** | Sign releases (minisign or GPG) and verify the signature in the root helper? | S12-02 step 3 | **Decided (2026-09-27), asked of the user directly:** no, not now; maybe in a future release. S12-02 steps 1, 2 and 4 go ahead; step 3 is deferred and the docs say the digest only detects corruption |
| **D-15** | Keep `lyona-update-root install-system checkout` (root runs `make` from a user-owned checkout)? | S12-03 | **Decided (2026-09-27), asked of the user directly:** option A, remove it. Developers use `sudo make install-system` or `dev-sync-install.sh`. Updates and rollbacks without root are a future sprint (`ROADMAP.md` Future Evaluation) |
| **D-16** | Make `/usr` (or `libexec/lyona`) the only runtime source for helpers, instead of also `~/.local/share/lyona/scripts`? | S12-13 | **Decided (2026-09-27), asked of the user directly:** option 3, the system copy is the only runtime source, plus one explicit developer override for live testing from a checkout |
| **D-17a** | One ISO, or separate standard and NVIDIA images? | S12-17 item 2 | **Decided (2026-09-27), asked of the user directly:** one ISO that detects NVIDIA hardware and installs the proprietary driver when it is needed. AGENTS.md and SPEC 9.4 change to match SPEC section 4 |
| **D-18** | Build the system-wide dwm with the updating user's `config.h`? (S12-02 step 4) | S12-02 | **Decided (2026-09-27), asked of the user directly:** yes, keep it, and make the runtime TOML files the documented way to customise; `config.h` is for the few compile-time options only |
| **D-17b** | Per-screen `Variants` panels (SPEC.md) or one `PanelWindow` (AGENTS.md)? | S12-17 item 1 | **Decided (2026-09-27), asked of the user directly:** keep per-screen panels (every monitor needs a bar; state is already shared); AGENTS.md changes to match SPEC.md |
| **D-20** | What is the one `themes.toml` reader for scripts? | S12-14 part 1 | **Decided (2026-09-29), asked of the user directly:** a C tool, `lyona-toml`, built from dwm's own `tomlparser.c` |
| **D-21** | Do the root helpers source the shared trust checks? | S12-14 part 3 | **Decided (2026-09-29), asked of the user directly:** no; they keep a self-contained copy that a contract test pins to the library |
| **D-19** | Weather widget: which provider, where the location comes from, and whether it is on by default? It is the shell's first feature that sends data (a location) to a third party | S12-20 weather half | **Open.** Recommendation: off by default, a location the user types (never IP geolocation), one keyless HTTPS provider (Open-Meteo, or wttr.in as upstream's prototype uses), refreshed at most every 30 minutes, and the calendar shipped without waiting for this |

---

## S12-01: Rollback restores only what root has checked

**Source:** S (High), E (High). **Verified.** **Implemented (2026-09-27)** as the
longer-term fix below, not the first diff: root makes and keeps the system backups
in `/var/lib/lyona/backups/<id>/`, and `restore-system` takes an id. The first diff
would have left the archive's contents under the user's control, and refusing
`libexec` members would have failed every genuine rollback. Evidence, and a new
finding (the published release asset cannot be installed by `lyona-update`):
`docs/evidence/s12-01-rollback-restore.md`.

`lyona-update-root restore-system` restores `system-files.tar` from the user's own
`~/.local/state/lyona/live-update-backups/<id>/`, as root:

- `scripts/lyona-update-root:297` extracts with `tar -C / -xpf`, which as root
  keeps the owner and mode stored in the archive. `--numeric-owner` is only on the
  listing (`:295`).
- The member allowlist (`:255-294`) checks paths only. It accepts any regular file
  under `$PREFIX/bin/` (first in root's `PATH` and in sudo's `secure_path`), any
  file under `$PREFIX/libexec/lyona/` including `lyona-update-root` itself, and any
  mode that is not setuid, setgid or sticky (so 0777 files and directories).
- The archive is read twice, once by `tar -tvf` and once by `tar -xpf`, so it can
  be replaced between validation and extraction.
- The `SHA256SUMS` check (`:243`) sits in the same user-writable directory; the
  comment at `:238-245` already says it is not a security control.
- `scripts/lyona-update` picks the newest backup by name (`sort -r`), so a planted
  directory that sorts last is the one a routine `rollback` uses.

**Scenario:** code running as the user writes a backup directory with its own
archive and checksum. The user later runs `lyona-update rollback` and approves the
genuine prompt. The archive installs a root-owned trojan in `/usr/local/bin` or
replaces the root helper.

**Fix.** Copy once into a root-owned directory, validate and extract only that
copy, never keep archive ownership or modes, and never restore the privileged
helpers from a user archive (reinstall them from a verified release instead).

```diff
 		system_archive=$backup_dir/system-files.tar
 		if [[ -e $system_archive ]]; then
 			[[ -f $system_archive && ! -L $system_archive ]] || die "unsafe system-files archive"
+			# Validate and extract one root-owned copy: the original sits in a
+			# directory the invoking user can write to, and may change between reads.
+			restore_dir=$(mktemp -d) || die "could not create a scratch directory"
+			chmod 700 "$restore_dir"
+			trap 'rm -rf "$restore_dir"' EXIT
+			cp --no-preserve=all -- "$system_archive" "$restore_dir/system-files.tar" ||
+				die "could not copy the backup archive"
+			system_archive=$restore_dir/system-files.tar
```

```diff
-			"$libexec_dir_rel/"*/*) die "backup archive contains a nested path under a flat directory: $member_path" ;;
-			"$libexec_dir_rel/" | "$libexec_dir_rel/"*) ;;
+			# The privileged helpers are never restored from a user-writable
+			# archive; a rollback reinstalls them from the verified release.
+			"$libexec_dir_rel/"*) die "backup archive contains a privileged helper: $member_path" ;;
```

```diff
-		if ! tar -C / -xpf "$system_archive"; then
+		# Never keep the archive's owners, and apply umask 022 to its modes, so
+		# nothing lands group- or world-writable. (setuid/setgid/sticky members are
+		# already refused by the listing check above.)
+		umask 022
+		if ! tar -C / --no-same-owner --no-same-permissions -xf "$system_archive"; then
 			log_outcome restore-system unknown "$backup_dir" failed
 			die "restoring system-files.tar failed"
 		fi
```

The longer-term fix is to have the root helper write system backups itself into a
root-only `/var/lib/lyona/backups` (0700), so the user never holds them. That is
a larger change to `lyona-update`'s backup step and `dev-sync-install.sh:339-349`;
record the choice in the evidence file.

**Verification:** a root-in-container test (the `display-security` job pattern
from S10-03) that restores (a) a planted archive with a 0777 file, a 0777
directory and a uid-1000 owner, and asserts everything lands `0:0` and at most
0755; (b) an archive holding `libexec/lyona/lyona-update-root`, and asserts
refusal; (c) an archive swapped after the copy, and asserts the copy is what was
extracted.

## S12-02: Release install hashes and builds one root-owned copy

**Source:** S (Medium), E (High). **Verified** (the double read and the caller-supplied digest).

**Implemented (2026-09-27): steps 1 and 2.** Step 1 goes further than the diff below:
root reads the tarball and `config.h` with the invoking user's permissions
(`runuser -u "$invoking_user" -- cat`) into its own copies, so a path or symlink can
never make root read a file the user could not. Step 3 is deferred (D-14). **Step 4 decided (D-18, 2026-09-27, asked of the user
directly):** keep building with the updating user's `config.h`, and make the TOML files
the documented way to customise (`docs/src/configuration.md`). While documenting it,
it turned out a `config.h` was only picked up when `lyona-update` ran from a checkout;
fixed here: it now builds with `~/.config/lyona/config.h` first, and `install-user`
copies a customised checkout `config.h` there once. Evidence:
`docs/evidence/s12-02-release-install.md`.

`install-system release` (`scripts/lyona-update-root:124-186`):

- `expected_sha256` is argv from the unprivileged caller, so root checks the
  tarball against whatever the caller claims.
- `sha256sum -- "$tarball_path"` (`:139`) and `tar -xzf "$tarball"` (`:114`) open
  the user-owned path separately; the file can be renamed in between.
  `user_owned_file` is a path check, not a file-descriptor check. The comments at
  `:102-111` and `:140-146` claim more than the code does.
- The unprivileged side caches `assetUrl` and `checksum` in the user-writable
  `~/.cache/lyona/update-index.json` for 300 s (`scripts/lyona-update:307-331`), so
  session malware can poison a genuine update.
- Root then runs `make all install-system` on that tree: arbitrary root code.
- The user's `config.h` (arbitrary C) is compiled into the system-wide dwm for
  every user, which the comment at `:167-172` says it prevents.

**Fix.**

1. Copy the tarball into the root-owned `verified_dir` first; hash and extract only
   that copy.

```diff
 		verified_dir=$(mktemp -d) || die "could not create a scratch directory"
 		chmod 700 "$verified_dir"
 		trap 'rm -rf "$verified_dir"' EXIT
+		verified_tarball=$verified_dir.tar.gz
+		cp --no-preserve=all -- "$tarball_path" "$verified_tarball" ||
+			die "could not copy the release tarball"
+		trap 'rm -rf "$verified_dir" "$verified_tarball"' EXIT
+		actual_sha256=$(sha256sum -- "$verified_tarball" | awk '{ print $1 }')
+		[[ ${actual_sha256,,} == "${expected_sha256,,}" ]] ||
+			die "tarball checksum does not match the expected release digest; refusing to install"

-		extract_verified_tree "$tarball_path" "$verified_dir"
+		extract_verified_tree "$verified_tarball" "$verified_dir"
```

   and remove the earlier hash of `$tarball_path` (`:139-146`), whose comment
   becomes untrue.
2. Say plainly in the helper and in `docs/src/` that the digest only detects
   corruption, and that `auth_admin` is the boundary, until step 3.
3. **Deferred (D-14: not now).** Ship a release-signing public key and verify a
   detached signature of `SHA256SUMS` in the root helper, so the digest itself is
   trusted. Until then, step 2 is what users are told.
4. On a machine with more than one user, build the system dwm from
   `config.def.h`, not the invoking user's `config.h`, or say in the prompt text
   that the user's `config.h` becomes every user's dwm.

**Verification:** extend `tests/test-lyona-update-root*` (or add one) so a tarball
replaced after the copy is not what gets built, and a wrong digest is refused
before any extraction.

## S12-03: The root helper writes and builds nothing through user paths

**Source:** S (Medium), A (High), E. **Verified** (log write, checkout mode).

**Implemented (2026-09-27):** all three parts. The log is written as the invoking
user, checkout mode is removed on both sides (D-15), and `install-cursors` installs
root-owned files. Evidence: `docs/evidence/s12-03-root-helper-paths.md`.

1. **Log through a user symlink.** `log_outcome` (`scripts/lyona-update-root:62-70`)
   runs `mkdir -p` and `>>"$log_file"` as root on
   `$state_home/lyona/update.log` (`:98`), inside the user's home. A symlink there,
   or on its parent, makes root create or append to any path, with partly
   controlled content (paths may contain newlines).

```diff
 log_outcome() {
 	local verb=$1 version=$2 target=$3 outcome=$4
 	[[ -n $log_file ]] || return 0
-	umask 077
-	mkdir -p "$(dirname -- "$log_file")" 2>/dev/null || return 0
-	printf '%s\t%s\t%s\t%s\t%s\n' \
-		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$verb" "$version" "$target" "$outcome" \
-		>>"$log_file" 2>/dev/null || :
+	# Written as the invoking user, never as root: the log lives in their home,
+	# where they control every path component.
+	target=${target//[$'\n\r\t']/?}
+	printf '%s\t%s\t%s\t%s\t%s\n' \
+		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$verb" "$version" "$target" "$outcome" |
+		runuser -u "$invoking_user" -- sh -c \
+			'umask 077; mkdir -p "${1%/*}" && cat >>"$1"' sh "$log_file" 2>/dev/null || :
 }
```

2. **Checkout mode runs a user-writable Makefile as root** (`:189-217`, D-15). After
   authorization the helper runs `make -C "$staging_dir" install-system`; the
   directory only has to be user-owned, so its `Makefile`, `config.mk` and
   `scripts/lyona-gtk-theme` (called by `install-gtk-themes`) run as root. AGENTS.md:
   "Repository or user-writable helper copies must never be elevated". The comment
   says this is the same trust as `sudo make`, which is true, but it turns an
   allowlisted polkit action into "run any code as root", and the `.policy` text
   does not say so. **D-15 decided: remove it.** Delete the `checkout)` branch of
   `install-system` (`scripts/lyona-update-root:189-217`) and its usage text;
   remove `--from-checkout` from `scripts/lyona-update` (`:28`, `:544-595`, the
   `install_mode=checkout` path at `:735`, and the `checkout.txt` backup record at
   `:772-774`, keeping rollback of older backups that carry one working); drop the
   option from `docs/src/updating.md:92-94`; rewrite the `--from-checkout` cases in
   `tests/test-lyona-update.sh` (`:262-426`) as tests that the option is refused.
   `lyona-update status` must still report an install that came from a checkout
   (`LYONA_SOURCE=checkout`, `:444-446`), since `sudo make install-system` keeps
   producing those. Developers use `sudo make install-system` or
   `dev-sync-install.sh`, where they type the command that runs as root themselves.
   Updating and rolling back without root is a separate, future sprint.
3. **`install-cursors` keeps the builder's ownership.** `cp -a` (`Makefile`
   `install-cursors`) as root, in checkout or `sudo make install` mode, likely
   leaves files under `$DATADIR/icons` owned by the building user (reported, not
   verified). Use `cp -a --no-preserve=ownership`, as `install-grub-theme` already
   does.

## S12-04: dwm always starts with working keys, and a config file cannot hang it

**Source:** E (High), S (Low, measured). **Verified.**

**Implemented (2026-09-27):** all four parts. Deviations from the diff below: the
fallback is to the default at startup but to the previous config on a live reload
(so a half-saved edit never removes keys), a hotkeys file with entries but nothing
bindable counts as unusable, the parser also refuses a FIFO (opened without
blocking), and the signal race uses a self-pipe rather than `pselect`, because
blocking the signals would be inherited by every child dwm forks. Evidence:
`docs/evidence/s12-04-dwm-key-fallback.md`.

1. **No keys at all from a bad hotkeys file.** `toml_load_with_fallback`
   (`dwm.c:3632-3654`) returns 0 when the user file exists but does not parse or
   has no entries, without trying `default_path`. `load_hotkeys_toml` (`:3658`)
   then returns, and `load_hotkeys_toml` also returns when `total <= 0` (`:3667`).
   There is no compiled-in `keys[]`, so at startup `grabkeys()` grabs nothing: no
   terminal, no quit. `notify_bad_config` (`:3496`) meanwhile says "loaded
   defaults". On a live reload the old keys survive, so this bites at login.

```diff
 	if (user_path && user_path[0] && access(user_path, F_OK) == 0) {
 		parsed = toml_parse(user_path, doc) && doc->n > 0;
-		if (!parsed) {
-			/* The user wrote this file, so say so rather than
-			 * silently falling back to the shipped default. */
-			notify_bad_config(user_path, "invalid config");
-			return 0;
-		}
+		/* The user wrote this file, so say so, then fall back to the
+		 * shipped default rather than to nothing. */
+		if (!parsed)
+			notify_bad_config(user_path, "invalid config");
 	}
```

   The same `return 0` path serves `themes` and `window-rules`, and on a live
   reload the right message is "kept the previous config", not "loaded
   defaults". Pass the outcome into `notify_bad_config` instead of fixing the text.
   `tests/test-xvfb-runtime.sh` asserts the current message (S11-04), so it changes
   with this. As a last resort, when nothing loads and `rt_keys == NULL`, install a
   two-entry built-in table (spawn the terminal, quit).
2. **A non-regular file hangs dwm** (measured). With `hotkeys.toml` a symlink to
   `/dev/zero`, `toml_parse`'s `fgets` loop (`tomlparser.c:133-146`) never ends; dwm
   sat at about 54% CPU and stopped managing windows. `fopen`, then `fstat` the
   stream, require `S_ISREG`, and cap the size (1 MiB).
3. **Unchecked tag shift** (reported, code verified). `dwm.c:3719` computes
   `1 << vtag->i` with no range check; `tag >= 31` or negative is undefined
   behaviour. Add `if (vtag->i < 0 || vtag->i >= (int)LENGTH(tags)) continue;`.
4. **A signal can wait for the next X event** (reported). Between
   `runtime_config_reload_if_pending()` and `select()` (`dwm.c:2789-2801`) a SIGHUP
   (reload) or SIGUSR2 (quit) is not acted on until another X event arrives. Use a
   self-pipe added to the `select` set, or `pselect` with those signals blocked.

**Verification:** extend `tests/test-xvfb-runtime.sh`: an empty and an all-comment
`hotkeys.toml` at startup still leave the shipped bindings grabbed (check with
`xdotool key` against a known binding); a `/dev/zero` symlink is refused and dwm
still manages a new window.

## S12-05: The TOML parser handles comments, same-line arrays and booleans

**Source:** E (Medium, confirmed by the reviewer with a test program). **Code verified.**

**Implemented (2026-09-27):** all four fixes, plus two found while writing the test:
an array whose first table is on the opening line lost every later line, and a `#`
after an escaped quote cut a string short. Evidence:
`docs/evidence/s12-05-toml-parser.md`.

`tomlparser.c` (used for all three runtime files):

1. In a multi-line array (`ml_active`, `:149-161`) comments are not stripped, so
   `{ class="a", isfloating=1 }, # see {docs}` produces a phantom table. The rule
   has no class, instance or title, so `applyrules` (`dwm.c:561-568`) matches every
   window and resets `isterminal`, `noswallow`, `isfloating` and `alwaysontop`,
   cancelling every earlier matching rule (terminal swallowing, for example).
2. A line that closes the array after its last table (`{ ... } ]`) never clears
   `ml_active`, so every later line is treated as array content and later sections
   (`[active] theme = ...`) are dropped.
3. Booleans: `isfloating=true` becomes `TOML_FLOAT 0` inside inline tables (`:119`
   sets FLOAT even when `strtod` fails) and a string at top level; the loaders only
   accept INT.

**Fix.** Strip `#` outside strings before scanning an array line (the same loop
already used for values at `:200-206`); after the last `}` on a line, treat a `]`
as the end of the array; parse `true`/`false` as INT 1/0 in both places; make
`load_rules_toml` skip a rule with no class, instance or title.

**Verification:** a new C unit test, `tests/test-tomlparser.c` built by a
`check-tomlparser` target, covering each case above plus the existing shipped
files round-tripping unchanged. Today no test exercises the parser directly.

## S12-06: Untrusted text renders as plain text

**Source:** S (Medium, measured). **Verified.**

**Implemented (2026-09-27)** more widely than listed below: rather than choosing
which elements show outside text, every `Text` in the managed shell sets
`Text.PlainText` (91 elements in 23 files, `UiText` and `SectionLabel` included),
since nothing uses markup, and a static test keeps it that way. Evidence:
`docs/evidence/s12-06-plain-text.md`.

Notification summaries and bodies, window titles, the overview card title and
SSIDs are drawn with Qt's default `Text.AutoText`, which renders markup:

- `config/quickshell/core/UiText.qml` sets no `textFormat` (used for the active
  title at `panel/DwmPanel.qml:131-139`).
- `notifications/NotificationCard.qml:59-76`, `NotificationHistoryWindow.qml:141-156`,
  `overview/OverviewCard.qml:123`.
- In the isolated session, `notify-send` with `<img src="http://127.0.0.1:PORT/...">`
  in the summary or body made Quickshell request both URLs. `NotificationServer`
  advertises `bodyMarkupSupported: false` (`NotificationModel.qml:356`), so clients
  do not escape. Effects: tracking and presence leaks, remote images fed to Qt's
  decoders, and spoofed bold or red "password required" styling in the panel.

Nothing in the shell relies on markup (no `text:` with tags; five Settings views
already set `Text.PlainText`).

```diff
 Text {
     color: Theme.text
     font.family: Theme.fontFamily
     font.pixelSize: Theme.panelFontSize
     renderType: Text.NativeRendering
+    // Titles, notifications and SSIDs come from other programs: never markup.
+    textFormat: Text.PlainText
     verticalAlignment: Text.AlignVCenter
 }
```

and `textFormat: Text.PlainText` on the plain `Text` elements in
`NotificationCard.qml`, `NotificationHistoryWindow.qml`, `OverviewCard.qml` and any
other `Text` that shows a window title, class, notification or network name.

**Verification:** a pin in `tests/test-quickshell-accessibility.sh` (or a new
`test-quickshell-plain-text.sh`) that every `Text` bound to one of those sources
sets `Text.PlainText`; an xvfb case that sends a notification with an `<img>` to a
local listener and asserts no request arrives.

## S12-07: Watchers stop polling for their parent

**Source:** F (High, measured). **Verified.**

**Implemented (2026-09-27)** as the plan's "better still" target rather than its
diff: program children run under `setpriv --pdeathsig TERM`, so they end with their
helper without any polling, and only a crash backstop loop remains (builtins, every
5 s, itself pdeathsig-bound). There are four callers, not two (`pactl subscribe` and
the power watcher too). Mpris was not adopted: `playerctl` stays. Evidence:
`docs/evidence/s12-07-watcher-polling.md`.

`run_parent_bound` (`scripts/dwm-watchdog.sh:63-73`) checks every 0.25 s whether
its parent is alive by running `sed`, `awk` and `sleep`: about 12 process starts
and 4 wakeups a second, for the whole session, per always-on watcher. The callers
are `nmcli monitor` (`dwm-quickshell-network:294`, started with `running: true` at
`NetworkModel.qml:503`) and `playerctl --follow` (`dwm-quickshell-controls:511`,
`ControlsModel.qml:549`). Measured: 1.72% of a core idle with one loop (network
only). A real install with playerctl runs two. It also keeps a laptop out of deep
C-states.

**Fix.** Read `/proc` with shell builtins and back off, so a tick costs one `sleep`
and nothing else:

```diff
 	(
 		while :; do
-			current_record=$(sed 's/^.*) //' "/proc/$parent_pid/stat" 2>/dev/null |
-				awk '{ print $1 " " $20 }' || true)
-			current_state=${current_record%% *}
-			current_identity=${current_record#* }
+			stat_line=
+			IFS= read -r stat_line <"/proc/$parent_pid/stat" 2>/dev/null || :
+			# After the last ") ": field 1 is the state, field 20 the start time.
+			# shellcheck disable=SC2086 # word splitting is the point
+			set -- ${stat_line##*) }
+			current_state=${1:-}
+			current_identity=${20:-}
 			[ "$current_state" != Z ] && [ "$current_identity" = "$parent_identity" ] || {
 				kill -TERM "$child_pid" 2>/dev/null || :
 				exit 0
 			}
-			sleep 0.25
+			sleep 2
 		done
```

`parent_identity` must be computed the same way where it is set, and `set --`
replaces the watchdog subshell's positional parameters, so check nothing after it
reads `"$@"`. The 2 s interval means a child outlives a dead parent by up to 2 s
instead of 0.25 s. Better still,
and the real target: make the child notice its parent's death without polling
(an inherited pipe whose EOF means "parent gone"), and move media to Quickshell's
native Mpris service instead of `playerctl --follow`.

Also in this item:

- **Media watcher respawns forever without playerctl** (reported, code verified).
  `media-watch` prints "unavailable" and exits (`dwm-quickshell-controls:505-508`);
  `ControlsModel.qml:555-566` restarts it every 3 s for the whole session. Stop
  restarting after the helper reports unavailable, or back off exponentially.
- **Network refresh without debounce** (reported, code verified). Every
  `nmcli monitor` line calls `refresh()` directly (`NetworkModel.qml:507`); lines
  that arrive mid-snapshot are dropped instead of merged. Add a settle timer like
  `BluetoothModel`'s.

**Verification:** extend `tests/test-overview-load-xvfb.py`'s CPU method into a
standing idle-cost test for the full shell with the network watcher running:
children's CPU (not only Quickshell's own) within 0.5 points of zero over 30 s.

## S12-08: The state bridge coalesces events and stops forking per window

**Source:** F (High, measured), A (Medium). **Verified** (code paths).

**Implemented (2026-09-28)**, steps 1-3. The script moved to bash (a fixed 50 ms
drain, and per-window watchers kept in an associative array). The overview gates its
card `Repeater` on visibility rather than gating `groups`, which the `windowCount`
IPC reads. Step 4 is not done. Evidence: `docs/evidence/s12-08-state-bridge.md`.

1. `dwm-quickshell-state watch` (`scripts/dwm-quickshell-state:441-447`) runs a full
   `show_state` for every line any `xprop -spy` prints. That costs about N+8
   process starts for N windows (a root `xprop`, `xdotool`, two `xprop` for the
   active window, one per client, plus `awk`, `sed` and `tr`), and it parses
   `xprop`'s human-oriented output (AGENTS.md: avoid it when a machine interface
   exists).
2. `watch_clients` (`:450-465`) restarts one resident `xprop -spy` per window on
   every client-list change, and each restart prints about 4 initial lines, so
   opening the Nth window triggers about 4N full rebuilds of N forks each: work
   that grows with N squared. Measured: 9.7% CPU in the 30 s after opening 10
   windows; one title change a second cost about 36 ms of CPU per rebuild with 10
   windows. Title-changing apps (terminals, browsers, players) keep it busy.
3. dwm adds events: `updatefullscreenmonitors()` (`dwm.c:5110`) writes its property
   on every call with no cache (unlike `updatelayoutprop`; verified), and
   `setclientdesktop` (`dwm.c:3185`) writes three properties (reported), so one tag
   switch fires 3 or 4 spied events.
4. `DwmState.parseState` (`state/DwmState.qml:44-94`) reassigns `runningApps`,
   `windowStates`, `monitorWorkspaceRows` and the rest unconditionally, so every
   binding fires and each panel `Repeater` (`RunningAppsArea.qml:12`) rebuilds.
   `OverviewModel.groups`/`flatCards` are "always live" (`OverviewModel.qml:32-60`),
   and the closed overview's nested Repeaters (`WindowOverview.qml:293-309`)
   recreate every card on every rebuild: a resident hidden model, which AGENTS.md
   rules out.

**Fix, in steps.**

1. Coalesce: after reading one event, drain the fifo for about 50 ms, then run one
   `show_state`.

```diff
 	while IFS= read -r event <&3; do
-		case $event in
-		_NET_CLIENT_LIST*) watch_clients ;;
-		esac
+		clients_changed=0
+		case $event in _NET_CLIENT_LIST*) clients_changed=1 ;; esac
+		# One rebuild per burst: a tag switch alone fires 3-4 property events.
+		deadline_us=$(( ${EPOCHREALTIME/./} + 50000 ))
+		while :; do
+			remaining_us=$((deadline_us - ${EPOCHREALTIME/./}))
+			(( remaining_us > 0 )) || break
+			printf -v read_timeout '0.%06d' "$remaining_us"
+			IFS= read -r -t "$read_timeout" event <&3 || break
+			case $event in _NET_CLIENT_LIST*) clients_changed=1 ;; esac
+		done
+		[ "$clients_changed" = 0 ] || watch_clients
 		show_state
 		printf '\n'
 	done
```

   Fractional `read -t` and `EPOCHREALTIME` need bash 5+; the script is POSIX
   `sh` today, so either move it to bash (AGENTS.md allows bash when a feature
   needs it) or use a `timeout`-free equivalent. Also have `watch_clients`
   start watchers only for new windows and stop them only for gone ones, instead
   of restarting all.
2. Cache `updatefullscreenmonitors` like `updatelayoutprop` (write only on change),
   and collapse `setclientdesktop`'s writes where they are redundant.
3. In `DwmState.parseState`, compare each key's raw text with the last one and skip
   identical values. Gate `OverviewModel.groups` on `visible`, or wrap the
   overview content in a `Loader { active: overviewModel.visible }`.
4. Longer term (A): have dwm publish one compact, structured root property with the
   whole state, or replace the shell script with a small xcb watcher binary, the
   precedent being `dwm-window-thumb.c`.

**Verification:** a measured case in the load test: open 10 windows, then count
`show_state` runs (log them under a test flag) and child CPU over 30 s; assert a
tag switch causes one rebuild, not four.

## S12-09: Stop needless work on events

**Source:** F (Medium), E (Low), A (Low). **Verified.**

**Implemented (2026-09-28)**, items 1-6. Items 5 and 6 were added while planning,
from a cleanup of this repository's test leftovers. Evidence:
`docs/evidence/s12-09-needless-work.md`.

1. **`dwm-status` rewrites WM_NAME when nothing changed** (`scripts/dwm-status:176-186`,
   loop at `:328-362`). It publishes every 30 s and on every `pactl` sink event
   (dragging a volume slider is dozens a second), about 6 process starts each, and
   every rewrite triggers a full state rebuild (S12-08). `DwmState.qml:257-258`
   discards the `VOL` and `NET` segments, and dwm's own bar is compiled out
   (`dwm.c:1227`), so the volume half is unused.

```diff
 publish() {
-	local power volume
+	local power text
 
 	power=$(power_text)
-	volume=$(volume_text)
-
+	text=$power
+	# Only a change is published: every write wakes the shell's state bridge.
+	[ "$text" != "${last_published-}" ] || return 0
 	if ! timeout --kill-after=0.2 "$publish_timeout" \
-		xsetroot -name "$power | $volume" 2>/dev/null; then
+		xsetroot -name "$text" 2>/dev/null; then
 		((signal_exit != 0)) && return 0
 		return 1
 	fi
+	last_published=$text
 }
```

   then remove `volume_text` and the `pactl` source, and read battery through
   UPower or udev only. Check first that no consumer other than `DwmState.qml`
   reads `VOL`/`NET` (the diagnostics and `dwm-status` tests).

   **Found while planning (2026-09-28): the rewrite is also `dwm-status`'s only
   liveness check.** Today an orphaned `dwm-status` (its X server gone, as after the
   Xvfb smoke test, which kills dwm rather than quitting it, so `autostop.sh` never
   runs) exits on its next `xsetroot` failure. Publishing only changes would leave it
   running forever. The 30 s power tick stays (battery capacity is a sampled value),
   and on a tick with nothing to publish it checks the display without writing to it:

```diff
+	# Nothing to publish: still notice a display that has gone away.
+	[ "$text" != "${last_published-}" ] || {
+		timeout --kill-after=0.2 "$publish_timeout" xprop -root -notype WM_NAME \
+			>/dev/null 2>&1 && return 0
+		((signal_exit != 0)) && return 0
+		return 1
+	}
```

   The restart and churn cases in `tests/test-dwm-status.sh` drive the `pactl`
   source today; they move to the `udevadm` source, which shares the restart code.
2. **Every config reload runs `theme-apply.sh`** (`dwm.c:3930-3943`), including for
   a change to `window-rules.toml` or `hotkeys.toml` only. It is serialised with
   `flock`, so it is safe, just wasted work. Fork it only when `themes.toml` changed
   (the inotify handler knows which file).
3. **`popen("pidof ...")` in a key handler for a component Lyona does not ship.**
   `sigstatusbar` (`dwm.c:4380-4391`) calls `getstatusbarpid()` (`:1664-1690`), which
   falls back to `popen("pidof -s dwmblocks")` (`config.def.h:41`) in the event loop.
   `dwmblocks` is not in the package map and nothing in `hotkeys.toml` binds
   `sigstatusbar`. Remove the dwmblocks support, or at least drop the `popen`.
4. **Redundant round trips in `dwm-window-thumb`.** `dwm-window-thumb.c:225-226`
   calls `XSync` after each `XGetImage`, which is already synchronous: about 640
   extra round trips per capture. Remove the `XSync` and check `x_error` once after
   the loop.
5. **Tests leave files and processes behind** (added 2026-09-28, from a cleanup of
   `~/tmp` and `/tmp`: 19 folders in `~/tmp`, about 270 entries in `/tmp` and 156
   orphaned processes, all from this repository's tests).
   - **`scripts/quickshell-qmllint` ends with `exec "$qmllint" "$@"`,** so its
     `trap 'rm -rf "$tmp"' EXIT` never runs: every `make check-quickshell-qml`
     leaves a `tmp.*/qs` import tree (114 of them in `/tmp`).

```diff
-exec "$qmllint" "$@"
+status=0
+"$qmllint" "$@" || status=$?
+exit "$status"
```

   - **Tests run outside `scripts/run-tests` write to `/tmp`.** `run-tests` exports
     `TMPDIR` to its workspace, but a plain `make check-...` does not, so `mktemp`
     and Python's `tempfile` fall back to `/tmp` (`plain-text.*`, `idle-watchers-*`,
     the `xrandr`/`xinput` stub files, `lyona-ci-local.*`). AGENTS.md requires
     `${DWM_TEST_TMP_ROOT:-$HOME/tmp}`. `tests/lib.sh` sets `TMPDIR` to that root
     when it is unset; the Python tests and `scripts/ci-local.sh` use the same root.
   - **Xvfb tests stop their session's first process and leave the rest.** dwm's
     autostart detaches its children (`setsid`), and helpers started by a killed
     Quickshell are orphaned. The smoke test left `dwm-status` and `udevadm monitor`
     running against its dead display; the Settings test left its `busctl` stub
     looping `sleep 1` for good, and those processes recreated the deleted folders.
     `tests/lib.sh` gains `kill_session_tree HOME`, which stops every process whose
     environment has that `HOME`: the test's own marker, never the real session's.
     `test-desktop-smoke-xvfb.sh`, `test-quickshell-settings-xvfb.sh` and
     `test-quickshell-system-management-xvfb.sh` call it in their cleanup.
6. **Most resident shell watchers are not bound to Quickshell** (added 2026-09-28,
   found through item 5). S12-07 bound the four `run_parent_bound` callers; ten more
   are started straight from QML and outlive a Quickshell that crashes or is killed:
   `BluetoothModel` (`busctl --system monitor org.bluez`, inline), and the `watch`
   actions of `dwm-settings-picom`, `dwm-settings-appearance` (`watch-inventory`),
   the autostart, defaults, display, input, accessibility and notification (`busctl
   --user monitor`) helpers, and `dwm-quickshell-state watch`. Each leaks a process
   (and often an `inotifywait` or a D-Bus match rule) until logout. Fix in one place:
   `Commands.watchCommand(command)` starts a watcher through the S12-07 guard
   (`setpriv --pdeathsig TERM`, then a check that its parent is still the one that
   started it), and each watcher's own TERM handling is checked to stop its children.
   Verification: start the full shell under Xvfb, SIGKILL Quickshell, and assert that
   no process it started is left within the TERM grace period.

   The display and input watchers (`scripts/dwm-simple-watch.sh`) also poll: a
   `read -t 0.1` loop checks their owner is alive, 10 wake-ups a second each while
   the section is open. The 0.1 s is also how quickly they stop: their TERM trap only
   records the signal, and bash runs such a trap without ending a blocked `read`
   (measured: `read -t 5` returned after 5 s). Once they are bound, the traps exit
   (the EXIT cleanup still runs) and the owner check becomes a backstop every
   `LYONA_PARENT_BOUND_INTERVAL` seconds (default 5, as in S12-07).

## S12-10: Power and memory defaults

**Source:** F (High for DPMS). **Verified.** **D-13 decided:** after 10 minutes
idle the screen turns off and the desktop locks.

**Implemented (2026-09-28):** item 1. Item 2 is tabled and item 3 is dropped, both
asked of the user directly. Evidence: `docs/evidence/s12-10-power-memory-defaults.md`.

1. **Screens never blank by default.** `read_power_config`
   (`scripts/dwm-quickshell-controlcenter:84-85`) defaults `power_dpms_enabled=0`, so
   `power-apply` runs `xset -dpms` (`:295-302`), and `autostart.sh:322-326` does the
   same (`xset s off`, `s noblank`, `-dpms`) when the helper is missing. Monitors
   and laptop panels stay lit indefinitely: very likely the largest power cost in
   the review.

```diff
 read_power_config() {
-	power_dpms_enabled=0
+	# D-13: after 10 minutes idle the screen turns off and the desktop locks,
+	# unless the user changes it in the Control Center.
+	power_dpms_enabled=1
 	power_dpms_timeout=600
-	power_lock_enabled=0
+	power_lock_enabled=1
 	power_lock_managed=0
 	power_lock_timeout=600
 	power_lock_after=5
```

   With lock enabled, `power_apply_lock_settings` (`:305-341`) sets the X
   screensaver to `lock_timeout` (600 s) and starts light-locker (already in the
   `arch:desktop` package map) with `lock-after-screensaver` 5, so the desktop locks
   5 seconds after the screen blanks at 10 minutes; moving the mouse in those 5
   seconds cancels without a password. `lock_after=0` would lock with no grace.
   Check that the Control Center's power pane shows both new defaults as on, and
   that `dwm-lock` (the explicit lock action) and light-locker do not both prompt.

```diff
 	if command -v xset >/dev/null 2>&1; then
-		xset s off
-		xset s noblank
-		xset -dpms
+		# Only reached when no Control Center helper exists: blank at 10
+		# minutes. Locking needs light-locker, which the helper starts.
+		xset s 600
+		xset +dpms
+		xset dpms 600 600 600
 	fi
```

   This changes two defaults, so the same change updates the Control Center docs
   (`docs/src/control-center.md`) and adds a migration note to `CHANGELOG.md`
   (AGENTS.md). A user who already saved `dpms_enabled` or `lock_enabled` in their
   power config keeps their choice: the defaults only apply without a saved value.
   `tests/test-quickshell-controlcenter.sh` and the power tests pin the old
   defaults and change with it.
2. **No Picom config is shipped.** The system `/etc/xdg/picom.conf` applies (shadows
   and fading on), and NVIDIA falls back to xrender (`dwm-settings-picom:563`).
   Consider a lean default (no blur, fading off, `vsync` on, `glx` where it works).
   Needs a by-eye check; S10-07 already tracks the NVIDIA backend on real hardware.
   **Tabled (2026-09-28), asked of the user directly:** not in this sprint. It changes
   how the desktop looks, and it needs a by-eye check on real hardware.
3. **Settings panes stay loaded after Settings closes.** `DeferredSettingsPane.qml:14-19`
   keeps `visited` true for the session, on purpose, to keep drafts and scroll
   positions; measured, opening all four popups took Quickshell from 289 MB to
   418 MB and it never returned. Release panes a grace period (say 5 minutes) after
   the Settings window closes, keeping any pane that has an unsaved draft.
   **Dropped (2026-09-28), asked of the user directly, after measuring.** It was built:
   each pane reported unsaved input, and a pane without any was unloaded after
   Settings closed. The release worked (all 9 panes unloaded in the full shell), but
   Quickshell's RSS did not come down.
   - Under Xvfb: 156 MiB idle, 183 MiB with every section opened, and 183 MiB after
     the release. `main` measured 152, 178 and 179 MiB.
   - Neither eager glibc trimming nor a forced `gc()` changed it. The memory is held
     by the QML engine (compiled component types, the JS heap, the allocator), not by
     the pane objects.
   - Unloading would only have cost a reload and lost scroll positions, for no gain
     that could be measured. `docs/evidence/s12-10-power-memory-defaults.md` has the
     numbers.

## S12-11: Install and update correctness

**Source:** E (Medium, Low), A (High for 2), S (Low for 7). **Verified** unless noted.

**Implemented (2026-09-28)**, all items. Item 2, decided with the maintainer: refuse
and list the fix (`sudo pacman -S --needed ...`) for the required groups, and only warn
for desktop packages. There is no privileged package installation, and the install
profile is not recorded. Item 4 matches the file name part: releases list assets by
their build path, so `$2 == want` would have broken them. Evidence:
`docs/evidence/s12-11-install-update.md`.

1. **Partial upgrade.** `install.sh:418` runs `sudo pacman -Sy` after enabling
   multilib, and later installs with `pacman -S --needed`
   (`scripts/dwm-utils.sh:26-28`). Arch does not support `-Sy` without `-u`.

```diff
-	if ! sudo pacman -Sy; then
-		warn "Could not refresh pacman databases after enabling multilib."
+	info "Upgrading the system to sync the new multilib repository (pacman -Syu)..."
+	if ! sudo pacman -Syu; then
+		warn "Could not upgrade the system after enabling multilib."
 		return 1
 	fi
```

   (A full upgrade inside the installer must stay visible to the user; AGENTS.md.)
2. **`lyona-update` never reconciles package dependencies.** `scripts/lyona-update`
   never calls `dwm_packages` or `check-deps`, so a release that adds a required
   package installs helpers that fail at runtime. SPEC 5.5 calls the update path the
   complete supported install path. Diff the new release's `arch:required` and
   `arch:desktop` lists against `pacman -Q` before applying, then install the
   missing packages (visibly) or refuse.
3. **Rollback extracts user trees over the current ones** (`scripts/lyona-update:914-919`),
   so files the newer version added stay behind; that breaks "the quickshell
   directory is replaced wholesale". Extract into a temporary directory next to the
   target and swap it in.
4. **Loose checksum match** (`scripts/lyona-update:385`): `$0 ~ want"$"` treats the
   `.` in the asset name as "any character" and is unanchored at the start. Use
   `$2 == want || $2 == "*" want`.
5. **Templates seeded into `~/.config`.** The seeding loop in `install-user`
   (`Makefile`, `for dir in config/*/`) skips only `quickshell`, so
   `config/polkit/*.policy` (with `@PREFIX@` unexpanded) and `config/systemd/` land
   in `~/.config/polkit/` and `~/.config/systemd/`. Skip `polkit` (and check whether
   `systemd` is meant to be seeded).
6a. **`--file` from outside the updates directory (historical; fixed).** Found during
   S12-03: an earlier updater passed the `--file` path itself to `lyona-update-root
   install-system release`, which accepts only tarballs under
   `~/.local/state/lyona/updates/`. The current updater (`75bb338`) copies an external
   archive into that directory as `lyona-<version>.tar.gz` before calling the helper,
   and reuses an archive already staged there; `tests/test-lyona-update.sh` covers
   both. Nothing left to do here.
6. **The offline hint is wrong** (reported). `lyona-update:606` suggests `--file` for
   an offline install, but `--file` still calls `resolve_release` for a checksum
   (`:611-640`) and refuses without one. Say so, or accept a `--sha256`.
7. **ISO installer credentials** (S). `archiso/airootfs/root/lyona-install.sh:331-335`
   builds the credentials JSON by interpolation: a passphrase containing `"` breaks
   the install, and one containing a backslash escape silently becomes a different
   passphrase, locking the user out of a fresh install. `openssl passwd -6
   "$PASSWORD"` (`:250`) puts the password in argv. Build the JSON with
   `jq -n --arg`, and use `openssl passwd -6 -stdin`.

## S12-12: Overview close asks the window, hidden windows, and thumbnail tests

**Source:** S (Low), E (Medium). **Verified.**

**Implemented (2026-09-28)**, all three items. Item 1 also needed dwm: with a window
manager running, `xdotool windowquit` sends `_NET_CLOSE_WINDOW`, which dwm ignored.
It now handles it through `closeclient`, shared with the close key. Item 2 lists
every managed window. Evidence: `docs/evidence/s12-12-overview-close.md`.

1. **Close destroys the window.** `close_window` (`scripts/dwm-quickshell-state:549`)
   runs `xdotool windowclose`, which the xdotool manual defines as "destroy the
   window" without asking the client. The comment at `:533-539` promises
   `WM_DELETE_WINDOW`. Unsaved work can be lost. The installed xdotool
   (4.20260303.1) has `windowquit`, which sends the graceful request.

```diff
 	if command -v xdotool >/dev/null 2>&1; then
-		xdotool windowclose "$target"
+		# windowquit sends WM_DELETE_WINDOW; windowclose destroys the window.
+		xdotool windowquit "$target"
```

   `tests/test-quickshell-state-close.sh` pins the command, so it changes too.
2. **A window can hide from the overview and task list** by setting `_NET_WM_PID`
   to a root-owned PID: the snapshot's `owner_uid(pid) == 0` filter
   (`dwm-quickshell-state:127-133`) drops it. Filter on something the client cannot
   choose (for example, only the shell's own layer windows by class), or show such
   windows anyway.
3. **The thumbnail tests never run.** `tests/test-window-thumb-xvfb.py` and
   `tests/test-overview-thumbnails-xvfb.py` are referenced by no Makefile target, CI
   script or workflow, and are mode 0644. Add `check-window-thumb-xvfb` and
   `check-overview-thumbnails-xvfb` (exit-77 skip convention, like
   `check-qt-palette-xvfb`) to `check`, and `chmod +x` them.

## S12-13: One runtime source for helpers

**Source:** A (High). **D-16 decided: option 3.** **Implemented (2026-09-28 to
2026-09-29): steps 1-6** of `docs/SYNC-SPRINT-12-S12-13-RUNTIME-SOURCE.md`, which
records each step's deviations and the whole-item verification.
- The system copy (`PREFIX/bin`, `PREFIX/lib/lyona`, `PREFIX/share/lyona`) is the
  only runtime source, with `LYONA_DEV_SCRIPTS` as the one developer override.
- Verified on a staged install and in the CI container for a fresh account that
  never ran `install-user`.
- `lyona-update apply` and `rollback` on a real system are not verified.
- Found while testing: the watcher-lifetime flake, now Sprint 13 S13-01.

dwm runs autostart from `$XDG_DATA_HOME/lyona/scripts/` (`dwm.c:383-386,2825-2860`),
and `core/Commands.qml:6-24` prefers that per-user copy for nearly every helper
(`preferManaged`), while `state/DwmState.qml:262-309` uses `PATH`. So every helper
exists twice, in `/usr/bin` and in `~/.local/share/lyona/scripts` (`Makefile`
`install-user` copies `scripts/` there), the two drift, an account that never ran
`install-user` gets a broken session, and `dev-sync-install.sh` and `lyona-update`
each carry verification code only to detect the drift.

Related (A, Low):

- `lyona-update` sources the developer tool `dev-sync-install.sh` as a library
  (`scripts/lyona-update:717,935`).
- Library and developer files (`dwm-packages.sh`, `dwm-paths.sh`,
  `dev-sync-install.sh`) are installed into `/usr/bin` (`Makefile` `INSTALL_COMMANDS`).
- 14 scripts compute XDG paths inline; only 9 source `dwm-paths.sh`.

**Decided direction (D-16, option 3).**

- The system copy (`$PREFIX/bin`, with shared shell code and non-command helpers in
  `$PREFIX/lib/lyona/`, not `bin/`) is the only runtime source. dwm runs autostart
  from it, and `Commands.qml` and `DwmState.qml` resolve helpers one way.
- `~/.local/share/lyona/` keeps only user-owned seed data; `install-user` stops
  copying `scripts/` there, and an existing copy is removed (or ignored) by a
  migration step with a note in `CHANGELOG.md`.
- **One developer override:** an environment variable (for example
  `LYONA_DEV_SCRIPTS=/path/to/checkout/scripts`) that dwm and `Commands.qml` check
  first. It is never set by any install path, applies only to the account that sets
  it (in `~/.xinitrc` or the session environment), and is reported by
  `dwm-diagnostics` and `lyona-update status` so a forgotten override is visible.
  It must never be honoured by anything running as root.
- `lyona-update` stops sourcing `dev-sync-install.sh`; the shared functions move to
  `lib/`. (Scripts that compute XDG paths inline sourcing `dwm-paths.sh` instead moved
  to S12-14, 2026-09-28.)

**Step-by-step plan:** `docs/SYNC-SPRINT-12-S12-13-RUNTIME-SOURCE.md`.
- `dev-sync-install.sh` and `lyona-update` lose the verification code that exists
  only to detect drift between the two copies.

This is the largest item; write its step-by-step plan (with the migration for
existing installs) in its own file before starting, as its first task.

## S12-14: One reader per shared format, one copy of shared safety logic

**Source:** A (Medium). **Implemented (2026-09-29 to 2026-09-30): all seven steps**
of `docs/SYNC-SPRINT-12-S12-14-SHARED-LOGIC.md`, whose notes record each step's
deviations and the whole-item verification. That file is the step-by-step plan (2026-09-29), with decisions D-20 (the
canonical reader is `lyona-toml`, built from dwm's `tomlparser.c`) and D-21 (the root
helpers keep test-pinned copies of the trust checks).

1. **At least seven `themes.toml` parsers:** `tomlparser.c`,
   `scripts/theme-apply.sh:143`, `scripts/dwm-settings-theme:156,380`,
   `scripts/dwm-settings-appearance:255`, `scripts/lyona-gtk-theme:472`,
   `scripts/dwm-quickshell-controlcenter:1440`, and the `uninstall` awk in `Makefile`.
   Each has its own grammar for comments, quoting and duplicate sections, so a file
   can apply in dwm while Settings rejects it. Add one canonical reader (for
   example `dwm-settings-theme dump --json`) and have the scripts use it. S12-05's
   parser test gives the reference behaviour.
2. **The preview and rollback state machine is copied by hand.**
   `scripts/dwm-settings-font:384-760` and `scripts/dwm-settings-toolkit:460-836`
   differ in 54 of about 377 lines; variants live in `dwm-settings-display`,
   `-input`, `-wallpaper` and `-theme`. On the QML side there are five or more
   countdown timers (`appearance/AppearanceModel.qml:1905-2010`,
   `settings/SettingsModel.qml:1132`). This is safety logic (locks, tokens, expiry);
   a fix in one copy does not reach the others. Extract a shared shell library
   (like `dwm-simple-watch.sh`) and one QML `PreviewSession` component.
3. **Trust-chain checks re-implemented in six scripts** (`trusted_parent_chain`,
   `trusted_file`). One sourced library, installed root-owned.
4. **`WatchedProcess.qml`** is the right abstraction for watchers, but 4 of about 95
   `Process` uses adopt it. Move the resident watchers to it (it also gives S12-07's
   back-off one home).


**Added from S12-13 (2026-09-28, asked of the user directly): XDG paths from one place.**

`dwm-paths.sh` gains `lyona_xdg_dirs`, which sets `config_home`, `data_home`,
`state_home` and `cache_home` from the XDG variables or `$HOME`. It uses the
validation `lyona-update:41-48` does today: an absolute path or the fallback. The 32
scripts that compute them inline switch to it:

`theme-apply.sh` (26 sites), `autostart.sh`, `lyona-update`, `dwm-settings-toolkit`,
`dwm-system-health`, `dwm-settings-theme`, `dwm-settings-appearance`,
`dwm-default-apps`, `dev-sync-install.sh`, `seed-default-apps.sh`, `lyona-version`,
`dwm-settings-wallpaper`, `dwm-settings`, `dwm-settings-font`, `dwm-session-launch`,
`dwm-quickshell-controlcenter`, `dwm-keybinds`, `dwm-controlcenter`,
`seed-autostart-overrides.sh`, `migrate-graphical-session.sh`, `dwm-xdg-autostart`,
`dwm-terminal`, `dwm-settings-provider`, `dwm-settings-input`, `dwm-settings-display`,
`dwm-screenshot`, `dwm-quickshell-launcher`, `dwm-panel-settings`,
`dwm-display-profile`, `dwm-diagnostics`, `dwm-accessibility-settings`, `ci-local.sh`.

POSIX `sh` scripts cannot source a bash library. For them it is a small
`dwm-paths-posix.sh`, or they stay inline with a comment; that is decided per script
when the step starts. This step changes no behaviour, only where the code lives, and
it moved here from S12-13 to keep that item smaller.

## S12-15: Privileged-helper consistency, the package map, and lint coverage

**Source:** A (Medium), S. **Verified** (lint list, system-health, package names).
**Implemented (2026-09-30), all three parts.** Where it differs from the text below:

- **Part 1:**
  - New `scripts/dwm-system-health-root` (in `PRIVILEGED_HELPERS`) and
    `config/polkit/com.lyona.system-health.policy` (in `POLKIT_ACTIONS`, with
    `exec.path` pinned).
  - The helper carries the D-21 pinned copy of the trust checks, which
    `test-shell-contracts.sh` now checks in all three root helpers. It makes the
    display helper's self-checks.
  - It allows `scan-system`, and `repair-system` with an allowlisted action whose
    unit matches `^[A-Za-z0-9:_.@\\-]+[.]service$`. It runs
    `@PREFIX@/bin/dwm-system-health`, which must pass `trusted_file`, under
    `env -i`.
  - `dwm-system-health`'s `trusted_system_helper` now finds the root helper
    instead of its own `/usr/bin` copy.
  - New `tests/test-system-health-root-security.sh`
    (`make check-system-health-root-security`) runs root-only in a container,
    added to the `display-security` CI job. It covers the repository copy, a
    missing `PKEXEC_UID`, writable copies, eight malformed requests and the
    accepted ones with their clean environment. Run with
    `docker run --network none -e DWM_SECURITY_CONTAINER=1` on the CI image, it
    passed, and it fails with `valid_repair` gutted.
- **Part 2:**
  - Profiles `arch:microcode-intel`, `-amd`, `gpu-nvidia`, `gpu-nvidia-dkms`,
    `gpu-amd`, `gpu-intel`, `network`, `vm-guest`, `mybash-bootstrap` and
    `xscreensaver`, each with exactly the names the scripts used.
  - The NVIDIA DKMS driver's `-headers` stay computed from the installed kernels.
  - **The NVIDIA profiles use `nvidia-open` and `nvidia-open-dkms`.**
    `check-no-aur` found that Arch had dropped `nvidia` and `nvidia-dkms`. The
    user chose to switch: the open modules need Turing or newer, and older cards
    stay on nouveau. The installer prompt, `docs/RELEASING.md` and the
    TASKS.md NVIDIA item say so.
  - The postinstall sources the map from the checkout on the medium and exports
    `dwm_packages` to its `run_logged` steps.
  - `install-mybash` is POSIX, and the map is Bash, so it asks `bash` for the
    list.
  - `test-arch-iso-builder.sh` requires each profile to exist and be used, and no
    `pacman` line to name its packages. It fails if `xf86-video-amdgpu` is put
    back literally.
- **Part 3:**
  - `SHELL_SCRIPTS` in the `Makefile` is `scripts/*.sh` plus every `scripts/*`
    whose shebang names `sh` or `bash`: 84 files.
  - The 13 newly covered scripts: five were reformatted, whitespace only apart
    from shfmt splitting one-line `case` arms, and three SC2155s were fixed in
    `webapp-create`.
- **Not verified:** a real polkit prompt for the new action in a live session.

1. **Three privileged patterns.** Display and update use `libexec/lyona` with an
   explicit polkit action and `exec.path`. `dwm-system-health` is installed in
   `/usr/bin`, acts as its own unprivileged client, and runs `pkexec` on itself
   (`scripts/dwm-system-health:797-815`) with no `.policy` file, so the prompt is the
   generic one and there is no `exec.path` pin. Move it to `libexec/lyona` with its
   own action.
2. **Package names outside the shared map** (AGENTS.md: keep them in
   `scripts/dwm-packages.sh`): `archiso/airootfs/root/lyona-postinstall.sh:26,28,35,106,114,136,139`
   (microcode, NVIDIA, GPU drivers, and NetworkManager/QEMU per the review),
   `scripts/install-mybash:24`, `scripts/xscreensaver-setup.sh:37`. Add `arch:gpu-*`,
   `arch:nvidia` and `arch:vm-guest` profiles to the map, and extend
   `tests/test-arch-iso-builder.sh`'s parity check to them.
3. **Lint coverage has holes.** The hand-kept lists in `check-shell` and
   `check-format` (`Makefile`) omit 13 shell scripts, including the privileged
   `scripts/dwm-settings-display-root`: `active-audio`, `disable-powersaving`,
   `dwm-controlcenter`, `dwm-polkit`, `dwm-screenshot`, `dwm-settings-display`,
   `dwm-settings-display-root`, `dwm-settings-input`, `lyona-release`, `nvidia-gpu`,
   `nvidia-temp`, `protonrestart`, `webapp-create`. Derive the list from shebangs
   (`scripts/*` whose first line names `sh` or `bash`) instead, then fix what
   ShellCheck reports on the newly covered files.

## S12-16: Split dwm-system-management and move test IPC out of the shell

**Source:** A (Medium, Low). **Verified** (size, docstring).
**Implemented (2026-10-02), all three steps.** The plan, the split tool and the
details are in [`SYNC-SPRINT-12-S12-16-SPLIT.md`](SYNC-SPRINT-12-S12-16-SPLIT.md).

- **Step 1:** `scripts/dwm-system-management` is a launcher over the
  `lyona_system_management` package, installed to `PREFIX/lib/lyona/python`,
  and the docstring is corrected.
- **Step 2:** the package is 14 modules, one per domain, behind a read-only
  facade. Tests patch the module that defines a name; patching the package
  raises.
- **Step 3:** the `settings` IPC target keeps its six product commands. The
  tests' 159 getters and drivers are on `settingsTest`
  (`settings/SettingsTestIpc.qml`), created only when `LYONA_SHELL_TEST_IPC=1`.
- **Validation:**
  - 691 unit tests (686 and 5 new) pass.
  - Before and after the split, five commands' output agrees.
  - The install, release and lint checks pass.
  - The four Xvfb shell tests pass.
  - The real shell in Xvfb has no `settingsTest` target without the flag, and
    idles at 0.000% CPU.
  - The full suite passes, except for the known watcher-lifetime flake (S13-01, `#197`). It showed its usual
    signature: one `xprop -root -spy DWM_TAG_UPDATE` outlived Quickshell. The test passed in its own run on this
    branch. `make check` stops at the first failure, so the 59 targets after it were run one by one, and all pass.
- **Not tested:** a desktop session on real hardware. The shell ran only under
  Xvfb.

1. `scripts/dwm-system-management` is one 10,379-line Python file covering updates,
   PackageKit transactions, regional and time settings, accounts, printers, storage
   and security. Its docstring (`:2-12`) still calls it a read-only provider with
   "no mutation", but it calls `UpdatePackages` (`:8346`, `:8506`). Split it into a
   package with one module per domain, installed as a package directory, and fix
   the docstring. Keep `tests/test-system-management.py` (686 tests) green at every
   step.
2. `shell.qml` has 239 functions; its `settings` IPC handler (`shell.qml:605-1347`,
   about 740 lines) is mostly getters for tests, shipped in the production shell.
   Move them to a test-only IPC target or component loaded only under a test flag.

## S12-17: Docs and specs agree with the code

**Source:** A (Medium), F, S. **Verified.** D-17a and D-17b decided.

1. **Per-screen panels. D-17b decided: keep them.** SPEC.md `:118-121` requires a
   per-screen Quickshell `Variants` panel (which `shell.qml:1398` implements);
   AGENTS.md `:150` says to avoid per-screen `Variants` and prefer one
   `PanelWindow`. Change AGENTS.md: per-screen panels are the design, each must
   share state (no per-panel models or `Process` watchers), and the idle-CPU check
   after Quickshell changes covers a multi-screen session.
2. **NVIDIA image. D-17a decided: one ISO that detects NVIDIA hardware and installs
   the driver when it is needed.** SPEC.md `:55` already says one image; AGENTS.md
   `:72-73` ("Preserve separate standard and NVIDIA image variants") and SPEC 9.4
   change to match, as do `docs/RELEASING.md` and the AGENTS.md "Arch Support
   Contract" paragraph. The installer already detects the GPU
   (`archiso/airootfs/root/lyona-install.sh:178-192`) but defaults to nouveau and
   makes the proprietary driver an opt-in; flip the default so a detected NVIDIA GPU
   gets the proprietary driver, keeping nouveau as the alternative:

```diff
 	local choice
 	choice=$(gum choose \
-		"nouveau (open-source, default)" "nvidia (proprietary)" \
+		"nvidia (proprietary, recommended)" "nouveau (open-source)" \
 		--header "NVIDIA GPU detected. Select driver:") || true
-	[[ $choice == "nvidia (proprietary)" ]] && NVIDIA_OPT_IN=1
+	[[ $choice == "nouveau (open-source)" ]] || NVIDIA_OPT_IN=1
 	return 0
```

   and the summary line at `:203`. Also check, when implementing, which package
   `install_nvidia_driver` (`lyona-postinstall.sh:97-115`) should pick: Arch's NVIDIA
   packaging changed during 2025 (open kernel modules for newer GPUs, older GPU
   generations dropped from the current driver), so it may need to choose by GPU
   generation and keep nouveau for cards the current driver no longer supports.
   A detected-but-unsupported card must not end with no working driver. The real
   hardware check stays in S10-07's ledger.
3. **Fedora package names.** SPEC.md 5.8 (`:421`, `:425`) lists `libX11-devel` and
   `imlib2-devel`; the Arch names are `libx11` and `imlib2`.
4. **Deleted design records still cited.** 15 source files cite 10 docs that no
   longer exist anywhere in the tree (not in `attic/` either):
   `docs/P6-UPDATE-SURFACE.md`, `docs/SYNC-P0-DPI-GATE.md`,
   `docs/SYNC-P2-UPDATE-SNAPSHOT.md`, `docs/SYNC-P3-SYSTEM-PANE.md`,
   `docs/SYNC-P4-DISCOVERY-EVENTS.md`, `docs/SYNC-P5-CONTRAST-MOTION.md`,
   `docs/SYNC-P6-UPDATE-EXECUTION.md`, `docs/SYNC-P7-OPERATION-SURFACE.md`,
   `docs/SYNC-P9-REGIONAL-DELEGATION.md`, `docs/SYNC-P9-REGIONAL-MUTATION.md`.
   Restore them from git history into `attic/`, or replace the references with the
   commit that removed them.
5. **Comments that claim more than the code does:** `lyona-update-root:102-111`,
   `:140-146` and `:167-172` (S12-02), `:238-245` (S12-01), and
   `dwm-quickshell-state:533-539` (S12-12). They change with those items.

## S12-18: Smaller hardening

**Source:** S (Low). **Reported** unless noted.

1. **Xorg config written from X-server strings.** `scripts/dwm-display-setup:519-556`
   and `:736-843` copy `flags`, `clock` and the other timing fields from
   `xrandr --verbose` into `/etc/X11/xorg.conf.d` unvalidated; any X client in the
   session can create a RandR mode whose name carries extra tokens. The profile
   records themselves are well validated (`dwm-settings-display-root:47-72`). Check
   that timing fields are numeric and flags are in
   `{+,-}{HSync,VSync}|Interlace|DoubleScan`.
2. **Notification history is world-readable** (measured). The `FileView` at
   `NotificationModel.qml:334` writes `~/.cache/lyona/notification-history.json` as
   0644. Create it 0600 (write through a helper with `umask 077`, or `chmod` after
   the first write).
3. **`webapp-create`** (`scripts/webapp-create:28-37`): the `wget` fallback lacks
   `--https-only` (curl has `--proto '=https'`), and `Exec=$browser $url` is not
   quoted per the desktop-entry spec. Same-user input only.
4. **`install-mybash`** (opt-in) clones `mybash` at HEAD, unpinned
   (`scripts/install-mybash:34`), and links it as `~/.bashrc` (`:142`; the old file is
   moved to `.bashrc.bak` only if no backup exists yet). Pin a commit, as `yay-bin`
   is.
5. **`lyona-cachyos`** receives the signing key by long ID and checks only the
   `tail -n1` of the listing (`scripts/lyona-cachyos:164-173`). Receive by the full
   fingerprint and compare with `--with-colons` output.

## S12-19: Release updates can install the published release asset

**Source:** found while testing S12-01 (2026-09-27). **Verified.** Not one of the four
reviews' findings.

`scripts/lyona-release` publishes the output of `make release` as
`lyona-<version>.tar.gz` (`scripts/lyona-release:194,249-252`). That archive is a
runtime bundle: the built `dwm`, `dwm.desktop`, `.xinitrc`, `assets/`, `config/` and
`scripts/` (`Makefile` `release`), with no `Makefile`, `config.mk` or C sources;
`make release-check` (`Makefile:881-905`) pins exactly that layout. But both halves of
the updater treat the asset as a source tree:

- `lyona-update apply` extracts it into `~/.local/state/lyona/updates/<version>/` and
  runs `make -C "$staging_dir" clean`, then `make all` (`scripts/lyona-update:656-683`).
- `lyona-update-root install-system release` reads `VERSION` from `config.mk`, then
  runs `make clean all install-system` on the extracted tree
  (`scripts/lyona-update-root`, `install-system release`).

So installing a published release through `lyona-update` (or the Settings update
pane) fails at the first `make`, and it cannot have worked since the release asset
took this form. Nothing else consumes the bundle: the ISO builds from a copy of the
repository. `tests/test-lyona-update.sh` exercises apply with `--from-checkout`
(removed by S12-03) and never with a real release asset, which is why no test caught
it; S12-01's container test builds a source tarball for the same reason.

**Options.**

1. **Publish a source archive and install from it (recommended).** Make the release
   asset a source tree (every tracked file, no `config.h`, objects or `release/`),
   built reproducibly the way `make release` is now, and change `release-check` to pin
   `config.mk`, `Makefile` and the sources, and to reject a built `dwm`. The updater
   and the root helper already build from source, so they need no change. The cost is
   that a release is built on the user's machine, which it already is.
2. **Install the bundle as built.** Keep the bundle, and teach the updater and the root
   helper to install its prebuilt files without `make`. That removes building as root,
   but it means a second install path beside `make install-system` that has to install
   exactly what the Makefile does, and it gives up building against the user's
   `config.h`.

The ROADMAP's future plan (a signed pacman package) replaces this path; option 1 is
the small fix until then.

**Verification:** a test that runs `lyona-update apply --file` against the output of
the real release target (not a hand-made tarball), with the root helper stubbed as in
`tests/test-lyona-update.sh`, and asserts it builds and reaches the privileged install
step; and the S12-01 container test switched to the real release archive.

---

## S12-20: Calendar and weather panel widgets

**Issue:** `#193`. **Source:** upstream feature request [ChrisTitusTech/dwm-titus#358](https://github.com/ChrisTitusTech/dwm-titus/issues/358)
(2026-09-28). Added on request, not one of the four reviews' findings. **Verified** against
the code. The reporter shared a working local prototype as a reference, not as a patch:
Calendar and Weather buttons on the panel, On/Off toggles in Control Center, Bar Widgets,
and a popup for each (a month calendar; current weather from wttr.in).

**The request, checked against Lyona:**

- **Bar Widgets** has five switches, and `scripts/dwm-panel-settings` knows exactly five
  ids (`readonly widget_ids='workspaces volume bluetooth network power'`, `:18`, validated at
  `:46`). An unknown id makes `panel-widgets.conf` malformed. That is why the prototype
  kept the calendar and weather switches in QML-only state. Here the two ids go into the
  helper, its protocol and its tests, so the choice persists like the other five.
- **The panel already shows a clock** (`panel/DwmPanel.qml:147-159`, `ClockModel.panelText`).
  The calendar opens from the clock: click the clock pill to open a month calendar in a
  popup. A second calendar icon would only duplicate it.
- **Popups** follow the existing pattern: a model with `open()`/`toggle()`, a window on the
  `ClickAwayPopup` pattern of Bluetooth and Network, and `selectPanelPopup` in `shell.qml`.
  Only one panel popup is open at a time.

**Steps.**

1. **Calendar** (no gate).
   - `CalendarModel` holds the shown month, today and the first weekday from the locale.
     There is no timer while the popup is closed; the clock already ticks, and the month
     grid is computed when the popup opens.
   - The popup has previous and next month and a "today" button, and full keyboard
     navigation like the overview.
   - Text is plain (S12-06).
   - A `calendar` id in `dwm-panel-settings`, the Bar Widgets list and `widgetIds`. When
     it is off, clicking the clock does nothing, as today.
2. **Weather** (gated by D-19).
   - A helper does the fetching, not QML: a new `lyona-weather` action with a bounded
     `curl` timeout. It prints one parsed line and caches the result under
     `$XDG_CACHE_HOME`.
   - It refreshes at most every 30 minutes, and only while the widget is on, so there
     is no request at all when it is off.
   - Failure is visible and harmless: a panel pill that shows "unavailable" never
     blocks or retries in a loop.
   - The location is a user setting. There is no IP geolocation.
   - The provider and the default follow D-19.
   - AGENTS.md: network downloads are optional, clearly reported and failure-tolerant.
3. **Settings and docs.** Both switches in Control Center, Bar Widgets. The weather
   location field goes in Settings. The user guide and `CHANGELOG.md`.

**Verification.**

- `tests/test-quickshell-panel-settings.sh` covers the two new ids: a file listing them is valid,
  and a missing id defaults to on for the original five and off for weather.
- An Xvfb test opens the clock's calendar and moves between months, and checks the popup
  closes on Escape and on a click outside.
- A stub `curl` checks the weather helper's timeout, cache and failure output, and that
  nothing is fetched while the widget is off.
- The idle cost with both popups closed is unchanged (the S12-07 measurement).

## S12-21: A staged helper always brings its libraries

**Issue:** `#199`. **Source:** found while implementing S12-14 (2026-09-30), added on request. **Verified**
three times in that item.

**The problem.** Tests that run a helper from their own layout copy it by hand: a fake
checkout (`$data_home/checkout/scripts/`, named by `LYONA_DEV_SCRIPTS`), a hand-built
`PREFIX` (`bin`, `lib/lyona`, `share/lyona`), or a stub directory. Each copy lists the
libraries the helper sources, and nothing checks the list. When a helper gains a library
(S12-13 and S12-14 added `dwm-xdg.sh`, `dwm-trust.sh`, `dwm-preview.sh` and
`lyona-toml`), every list that copies it goes stale. The helper then fails at load. The
shell shows its feature as "unavailable", and the test often still passes, because it
never looked at that feature.

- **S12-14 step 2:** `test-quickshell-system-management-xvfb.sh` had passed since step 1
  with the provider, health and display helpers failing at load.
- **S12-14 step 4:** the Control Center listed no themes, and the appearance provider fell
  back to its linter, in six fake checkouts without `lyona-toml`.
- **S12-14 step 5:** `test-quickshell-settings-xvfb.sh` failed only because it happened to
  check font readiness.

13 tests stage copies this way: `test-autostart.sh`, `test-dwm-settings-appearance.sh`,
`test-dwm-settings-theme.sh`, `test-dwm-settings-toolkit.sh`, `test-lyona-toml.sh`,
`test-quickshell-controlcenter.sh`, `test-quickshell-health-xvfb.sh`,
`test-quickshell-idle-watchers-xvfb.py`, `test-quickshell-large-surfaces-xvfb.sh`,
`test-quickshell-settings-xvfb.sh`, `test-quickshell-system-management-xvfb.sh`,
`test-quickshell-watcher-lifetime-xvfb.py` and `test-settings.sh`. Those that copy all of
`scripts/` are safe from this, but not from a missing built `lyona-toml`.

**Steps.**

1. **One staging helper in `tests/lib.sh`**, `stage_helpers LAYOUT DEST HELPER...`:
   - `LAYOUT` is `checkout` or `prefix`;
   - it copies each helper, then every library the helper sources through
     `$lyona_lib/...` (followed recursively, since libraries source libraries);
   - in a checkout, it puts `lyona-toml` beside `scripts/`; in a prefix, in
     `lib/lyona`.

   The list of libraries a helper sources is read from its source the way
   `test-shell-contracts.sh` already reads it. The Python tests get the same helper
   in `tests/lyona_tmp.py`, or call the shell one.
2. **The 13 tests switch to it** in place of their hand-written lists. A test that
   stages a stub instead of a real helper keeps doing so; only the libraries' part
   changes.
3. **A load check.** After staging, `stage_helpers` runs each staged helper once with a
   harmless argument (`--help`, or a usage error, which still proves it loaded). It fails
   the test at once if a helper cannot load, rather than leaving the shell to show
   "unavailable".
4. **A contract check** in `test-shell-contracts.sh`: no test outside `tests/lib.sh`
   copies a single `scripts/dwm-*.sh` or `lyona-*.sh` library by name, so a new
   hand-written list is caught in review.

**Test.**

- Remove `dwm-xdg.sh` from a scratch copy of `scripts/`. Every test that stages a helper
  sourcing it must fail at staging, naming the helper and the missing file, not further
  on.
- The full suite passes.

## Not in scope

- The review's positive findings, kept here so they are not "fixed" by accident:
  hostile titles, icons, properties and TOML produced no crash or command
  execution (measured); QML launches helpers from argv arrays only; the thumbnail
  helper's privacy checks all held (measured); the display root helper validates
  tightly; downloads (Herdr, Meslo, Starship, yay-bin, flathub) are pinned and
  GitHub Actions are SHA-pinned; dwm blocks in `select()` at about 0% CPU; every
  popup returns to baseline CPU after closing (measured); QML repeating timers are
  gated on visibility; the screen lock fails closed.
- A days-old zombie `picom` on the review machine (parent: an unrelated
  `sleep infinity`). Not from this repository's code as far as the review could
  tell; not tracked here.

## Verification (whole sprint)

Same gates as every sprint: `scripts/run-tests make clean all`, `check-shell`
(which S12-15 widens), `check-format`, `check-quickshell-qml`, then `make check`,
plus the **Full suite (manual)** workflow on the sprint branch and on `main`. The
security items (S12-01 to S12-03) need a root-in-container test job; the pattern is
S10-03's `display-security` job. Each item records its evidence in
`docs/evidence/s12-*.md`, and what could not be tested (real hardware, a real
polkit prompt) goes into S10-07's ledger.
