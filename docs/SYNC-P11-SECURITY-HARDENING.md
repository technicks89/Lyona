# Sync Phase 11 — security hardening

No single upstream commit — this phase is Lyona's own, from a read-only security
audit of `scripts/`, `config/`, `install.sh`, and `config.mk`. Index:
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

**Runs early, out of file-number order** — see
[`UPSTREAM-SYNC.md`'s recommended execution order](UPSTREAM-SYNC.md#recommended-execution-order).
Zero file overlap with any other phase, and two of its findings are live risks in
the *default* install path and in a shipped, misleadingly-named lock script — higher
real-world impact than any feature-parity work in Phases 1–9.

Threat model: **single-user enthusiast desktop**, not a multi-tenant server. Local
privilege escalation and supply-chain risk matter most; theoretical
multi-tenant-isolation concerns don't apply here and aren't in scope.

Every finding below was confirmed by direct inspection of the current file — not
just carried over from the audit that found it.

---

## Severity key

- **P0 — fix before next release.** Local code-exec-as-root or lock-bypass,
  reachable in a default/recommended path.
- **P1 — fix soon.** Real supply-chain or trust gap, lower likelihood or opt-in.
- **P2 — worth doing.** Defense-in-depth that costs little.

---

## 11a (P0). `scripts/install-mybash` — `curl | sudo sh`, unpinned `git clone` + `sudo <script from it>`

**Files:** `scripts/install-mybash`

Confirmed live at `:68` (`curl -sSL https://starship.rs/install.sh | sudo sh`) and
`:80-81` (`git clone --depth 1 ... ~/.fzf && sudo ~/.fzf/install`), reachable
through `install.sh`'s `install_recommended_profile` path (`install.sh:829`) — the
profile most users pick.

### Context

On any transient `pacman` failure (mirror hiccup, a held `db.lck` — both common on
a rolling release like CachyOS), the `starship` fallback silently pipes a remote
script into `sudo sh`: whoever controls `starship.rs`'s DNS/CDN/TLS termination at
that moment gets root, no checksum, no pin. The `fzf` fallback is worse in a
different shape — an **unpinned** `git clone`, then `sudo ~/.fzf/install` runs a
script from a repo whose exact commit was never verified, as root, seconds after
cloning it. `zoxide`'s fallback (`:97`) is `curl | sh` — not root, but still
unpinned and unverified.

The file's own header comment already documents that this branch is reachable and
dangerous — it was written to explain a bug fix that made the branch *less* likely
to trigger, not to remove the pattern:

```sh
# Without it every call returned "command not found", which is falsy, so each
# `! command_exists X` was always true: the "already installed" branches were
# unreachable and the installers ran on every pass. That matters because
# `_install_pkg ... || curl | sudo sh` then became reachable even on a machine
# that already had the tool, where a transient pacman failure would pipe a
# remote script into sudo sh.
```

Directly contradicts `SPEC.md:634-638` — *"Do not execute remote scripts through a
shell as part of the required installation path. Do not download or execute
unverified binaries."* `scripts/install-herdr` (see "Already hardened," below)
shows the project already knows the correct pattern; `install-mybash` was never
brought up to that standard.

### Fix

```diff
--- a/scripts/install-mybash
+++ b/scripts/install-mybash
@@
+STARSHIP_VERSION="1.20.1"
+STARSHIP_INSTALLER_SHA256="<pin from a reviewed download of https://starship.rs/install.sh>"
+FZF_REF="0.55.0"
+
 installStarshipAndFzf() {
 	if ! command_exists starship; then
 		printf "%b\n" "Installing Starship..."
 		_install_pkg starship 2>/dev/null || {
-			printf "%b\n" "Package manager install failed, using curl..."
-			curl -sSL https://starship.rs/install.sh | sudo sh || {
-				printf "%b\n" "Failed to install starship!"
-				exit 1
-			}
+			printf "%b\n" "Package manager install failed; installing the pinned, checksum-verified release..."
+			tmp=$(mktemp) || exit 1
+			trap 'rm -f "$tmp"' EXIT
+			curl --fail --location --show-error --silent \
+				"https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/install.sh" \
+				--output "$tmp" || { printf "%b\n" "Failed to download the Starship installer!"; exit 1; }
+			printf '%s  %s\n' "$STARSHIP_INSTALLER_SHA256" "$tmp" | sha256sum --check --status || {
+				printf "%b\n" "Starship installer checksum verification failed!"
+				exit 1
+			}
+			sh "$tmp" -- --yes || { printf "%b\n" "Failed to install starship!"; exit 1; }
 		}
 	else
 		printf "%b\n" "Starship already installed"
 	fi
 
 	if ! command_exists fzf; then
 		printf "%b\n" "Installing fzf..."
 		_install_pkg fzf 2>/dev/null || {
-			printf "%b\n" "Package manager install failed, using git..."
-			git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
-			sudo ~/.fzf/install
+			printf "%b\n" "Package manager install failed; cloning the pinned fzf release..."
+			git clone --branch "$FZF_REF" --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
+			~/.fzf/install --bin --no-update-rc
 		}
 	else
 		printf "%b\n" "Fzf already installed"
 	fi
 }
```

`~/.fzf/install --bin` installs only the `fzf` binary into `~/.fzf/bin` for the
current user — it never needs `sudo`; dropping `sudo` closes the root-exec angle
even before the pin lands. Apply the same pin-or-drop treatment to `installZoxide`'s
`curl -sSL .../install.sh | sh` (`:97`) — simplest fix is to drop the curl fallback
entirely and rely on `_install_pkg zoxide` alone: it's in the official Arch repos,
and `SPEC.md` targets Arch only, so the non-Arch fallback path serves no supported
configuration anyway.

---

## 11b (P0). `scripts/xscreensaver-setup.sh` — ships a "screensaver" that never locks, and `dwm-lock` never talks to it

**Files:** `scripts/xscreensaver-setup.sh`, `scripts/dwm-lock`

Confirmed: `scripts/xscreensaver-setup.sh:60-77` writes exactly this into
`~/.xscreensaver`:

```
mode:         blank
timeout:      0:10:00
cycle:        0:10:00
lock:         False
lockTimeout:  0:00:00
dpmsEnabled:  False
```

and autostarts the daemon unconditionally via a generated autostart `.desktop`
entry plus `xscreensaver --no-splash &`.

Confirmed: `scripts/dwm-lock`'s locker fallback chain — the *only* thing Lyona
calls to actually lock a session — tries, in order: `light-locker-command`,
`xdg-screensaver`, `loginctl lock-session`, `mate-screensaver-command`,
`xfce4-screensaver-command`, `cinnamon-screensaver-command`,
`gnome-screensaver-command`, then `i3lock`/`slock`/`xlock`. **`xscreensaver` never
appears in that chain.**

### Context

A user runs `xscreensaver-setup.sh` — a command Lyona ships and installs
(`Makefile`, `INSTALL_COMMANDS`) under a name that reads as "configure my lock
screen." After 10 minutes idle the screen blanks, which looks exactly like a
locked screen — but `lock: False` means dismissing it requires no password.
Anyone who walks up and presses a key is back in the session. This is the
realistic threat this class of machine actually faces (walk-up/shoulder access on
a personal desktop), created by a script whose entire purpose implies the
opposite of what it does. It's opt-in — not run by `install.sh` — which is the
only reason this isn't ranked above 11a, but nothing else in the codebase warns
the user that xscreensaver's blank is not a lock.

### Fix

Either wire it into the real lock chain, or stop implying it locks. Wiring it in
is the straightforward fix and matches what every other locker in the chain
already does:

```diff
--- a/scripts/xscreensaver-setup.sh
+++ b/scripts/xscreensaver-setup.sh
@@
 cat >"$XSCREENSAVER_CONFIG" <<'EOF'
 # XScreenSaver configuration — generated by lyona xscreensaver-setup.sh
 
 mode:         blank
 timeout:      0:10:00
 cycle:        0:10:00
-lock:         False
-lockTimeout:  0:00:00
+lock:         True
+lockTimeout:  0:00:00
 dpmsEnabled:  False
 EOF
```

```diff
--- a/scripts/dwm-lock
+++ b/scripts/dwm-lock
@@
+if command -v xscreensaver-command >/dev/null 2>&1 &&
+	pgrep -x xscreensaver >/dev/null 2>&1 &&
+	try_lock xscreensaver-command -lock; then
+	exit 0
+fi
+
 for locker in i3lock slock xlock; do
```

The `pgrep -x xscreensaver` guard matters: without it, `dwm-lock` would try to
drive a daemon that isn't running whenever xscreensaver is merely installed but
not the active session's screen-blanker.

If the intent is instead that xscreensaver stays blank-only and locking is always
handled elsewhere (e.g. light-locker), the setup script must say so loudly at run
time — `warn "xscreensaver will blank the screen but NOT lock it; install
light-locker for lock-on-idle."` — instead of silently writing `lock: False` with
no comment.

---

## 11c (P1). `scripts/lyona-cachyos` — signing key trusted by keyserver lookup, no fingerprint pin

**Files:** `scripts/lyona-cachyos`

Confirmed at `:4-5`:

```sh
KEY_ID=F3B607488DB35A47
KEYSERVER=keyserver.ubuntu.com
```

and at `:156-166`:

```sh
import_key() {
	info "Importing the CachyOS package signing key..."
	run_root pacman-key --recv-keys "$KEY_ID" --keyserver "$KEYSERVER" || {
		err "Could not receive the CachyOS signing key $KEY_ID."
		return 1
	}
	run_root pacman-key --lsign-key "$KEY_ID" || {
		err "Could not locally sign the CachyOS signing key $KEY_ID."
		return 1
	}
}
```

### Context

A 64-bit key ID is better than the classically-spoofable 32-bit short ID, but the
script still trusts *whatever key the keyserver hands back* for that ID and
locally signs it immediately — no fingerprint, creation-date, or second-source
check. A poisoned keyserver response here (keyserver poisoning, or a targeted
MITM before TLS is established to a non-pinned host) results in
`pacman-key --lsign-key` trusting an attacker key. Every future `pacman -Syu`
against the `[cachyos]` repo this same script adds moments later — as root, no
further prompt — then installs attacker-signed packages. This is the single trust
root every later privileged action in the script depends on: kernel installs,
mirrorlist/package installs, all of it.

### Fix

```diff
--- a/scripts/lyona-cachyos
+++ b/scripts/lyona-cachyos
@@
 KEY_ID=F3B607488DB35A47
 KEYSERVER=keyserver.ubuntu.com
+# Full fingerprint, cross-checked against https://wiki.cachyos.org and the key
+# CachyOS ships in cachyos-keyring — verify this again on rotation.
+KEY_FINGERPRINT="<fill in from an out-of-band check before this lands>"
@@
 import_key() {
 	info "Importing the CachyOS package signing key..."
 	run_root pacman-key --recv-keys "$KEY_ID" --keyserver "$KEYSERVER" || {
 		err "Could not receive the CachyOS signing key $KEY_ID."
 		return 1
 	}
+	local received_fp
+	received_fp=$(run_root pacman-key --list-keys "$KEY_ID" 2>/dev/null |
+		command grep -A1 '^pub' | tail -n1 | tr -d '[:space:]')
+	if [[ ${received_fp^^} != ${KEY_FINGERPRINT//[[:space:]]/} ]]; then
+		err "CachyOS key fingerprint mismatch — refusing to trust it."
+		run_root pacman-key --delete "$KEY_ID" 2>/dev/null || true
+		return 1
+	fi
 	run_root pacman-key --lsign-key "$KEY_ID" || {
 		err "Could not locally sign the CachyOS signing key $KEY_ID."
 		return 1
 	}
 }
```

**Do not land with the placeholder fingerprint.** `KEY_FINGERPRINT` must come from
a real out-of-band verification against CachyOS's published key before this
commit is made — not copied from this document as-is.

---

## 11d (P1). `install.sh` — unpinned `git clone` of yay-bin, `makepkg -si --noconfirm`

**Files:** `install.sh`

Confirmed at `:452-465`:

```sh
info "Installing yay as a standing AUR helper..."
tmp_dir="$(mktemp -d)"
if ! git clone --depth 1 "$YAY_BIN_URL" "$tmp_dir/yay-bin" 2>/dev/null; then
	rm -rf "$tmp_dir"
	warn "Could not download yay; continuing without an AUR helper."
	return 1
fi
if ! (cd "$tmp_dir/yay-bin" && makepkg -si --noconfirm); then
	rm -rf "$tmp_dir"
	warn "yay build failed; continuing without an AUR helper."
	return 1
fi
```

with `YAY_BIN_URL="https://aur.archlinux.org/yay-bin.git"` (`:62`).

### Context

This is the standard, widely-used way to bootstrap an AUR helper — cloning from
the official `aur.archlinux.org` namespace, which is itself package-scoped — so
it's materially lower risk than 11a. But it still clones an **unpinned** ref and
immediately builds+installs it with `--noconfirm`, which suppresses `makepkg`'s
normal "review the PKGBUILD" pause. If the `yay-bin` AUR page is ever compromised
(AUR account takeover is a known incident category), this installs and runs its
`PKGBUILD` — arbitrary shell — as the invoking user, then as root via `makepkg`'s
internal `sudo pacman -U`, with no human ever seeing the diff.

### Fix

```diff
--- a/install.sh
+++ b/install.sh
@@
 YAY_BIN_URL="https://aur.archlinux.org/yay-bin.git"
+YAY_BIN_REF="<commit hash reviewed for this release>"
@@
 	tmp_dir="$(mktemp -d)"
-	if ! git clone --depth 1 "$YAY_BIN_URL" "$tmp_dir/yay-bin" 2>/dev/null; then
+	if ! git clone "$YAY_BIN_URL" "$tmp_dir/yay-bin" 2>/dev/null ||
+		! git -C "$tmp_dir/yay-bin" checkout --quiet "$YAY_BIN_REF"; then
 		rm -rf "$tmp_dir"
 		warn "Could not download yay; continuing without an AUR helper."
 		return 1
 	fi
-	if ! (cd "$tmp_dir/yay-bin" && makepkg -si --noconfirm); then
+	if ! (cd "$tmp_dir/yay-bin" && makepkg -si); then
 		rm -rf "$tmp_dir"
 		warn "yay build failed; continuing without an AUR helper."
 		return 1
 	fi
```

Re-pin `YAY_BIN_REF` on each release after reviewing the diff since the last pin —
the same discipline the project already applies to
`MESLO_SHA256`/`HERDR_*_SHA256`. Dropping `--noconfirm` means an unattended
install now pauses for PKGBUILD review; if that's unacceptable for a scripted/CI
install path, gate it behind an explicit `--unattended`-style flag rather than
silently keeping `--noconfirm` for everyone.

---

## 11e (P2). `config.mk` — no compiler hardening flags

**Files:** `config.mk`

Confirmed, full relevant block at `:15-19`:

```make
OPTIMISATIONS ?= -O2
NATIVE_OPTIMISATIONS ?= -O3 -march=native -mtune=native -flto=auto

CPPFLAGS += -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -DVERSION=\"${VERSION}\" ${XINERAMAFLAGS} ${INCS}
CFLAGS ?= ${OPTIMISATIONS} -std=c99 -pedantic -Wall -Wno-deprecated-declarations
LDLIBS += ${LIBS}
```

### Context

`dwm` parses X11 properties (window titles, class/instance hints, EWMH/ICCCM
atoms) from every client on the X server, including anything a downloaded or
untrusted binary the user runs decides to set — attacker-influenced input
reaching C string-handling code (`updatetitle`, `gettextprop`, the TOML parser in
`tomlparser.c`). None of the standard Linux hardening flags are set: no
`-D_FORTIFY_SOURCE=2` (buffer-overflow checks in libc string functions), no
`-fstack-protector-strong` (stack canaries), no `-fPIE`/`-pie` (ASLR for the
executable), no `-Wl,-z,relro,-z,now` (GOT/PLT write-protection), no
`-Wformat -Wformat-security` (format-string bugs caught at compile time). Free
defense-in-depth with no functional cost — the biggest single gap found in this
audit even though no exploitable bug exists in the current `sprintf`/`strcpy`
call sites (see "Already hardened," below).

### Fix

```diff
--- a/config.mk
+++ b/config.mk
@@
 OPTIMISATIONS ?= -O2
 NATIVE_OPTIMISATIONS ?= -O3 -march=native -mtune=native -flto=auto
 
-CPPFLAGS += -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -DVERSION=\"${VERSION}\" ${XINERAMAFLAGS} ${INCS}
-CFLAGS ?= ${OPTIMISATIONS} -std=c99 -pedantic -Wall -Wno-deprecated-declarations
-LDLIBS += ${LIBS}
+CPPFLAGS += -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -D_FORTIFY_SOURCE=2 \
+	-DVERSION=\"${VERSION}\" ${XINERAMAFLAGS} ${INCS}
+CFLAGS ?= ${OPTIMISATIONS} -std=c99 -pedantic -Wall -Wno-deprecated-declarations \
+	-Wformat -Wformat-security -fstack-protector-strong -fPIE
+LDFLAGS += -pie -Wl,-z,relro,-z,now
+LDLIBS += ${LIBS}
```

(`-D_FORTIFY_SOURCE=2` requires `-O1` or higher, which `OPTIMISATIONS` already
satisfies; `NATIVE_OPTIMISATIONS`'s `-O3` is unaffected.)

---

## 11f (P2). `scripts/webapp-create` — unsanitized `$name`/`$url` interpolated into a `.desktop` file

**Files:** `scripts/webapp-create`

Confirmed, relevant excerpt at `:19-40`:

```sh
local clean_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
local desktop_file="$APPS_DIR/${clean_name}.desktop"
local icon_path="$ICONS_DIR/${clean_name}.png"

if [[ -n "$icon_url" ]]; then
    echo "Downloading icon..."
    if command -v curl >/dev/null 2>&1; then
        curl -s -o "$icon_path" "$icon_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$icon_path" "$icon_url"
    fi
fi

cat > "$desktop_file" << EOF
[Desktop Entry]
Name=$name
Exec=$browser $url
Icon=$icon_path
...
EOF
```

### Context

`clean_name` is sanitized down to `[a-z0-9-]`, but `$name` (used verbatim in
`Name=$name`) and `$url` (used verbatim in `Exec=$browser $url`) are not. A
newline embedded in either injects arbitrary additional `.desktop` keys — e.g. a
crafted `$url` containing `\nExec=some-other-command` overrides the `Exec=` line
that follows it in the heredoc. Since this is a user-invoked local convenience
tool (the user supplies both arguments to their own command), the realistic path
is a user pasting a copy-pasted "add this as a webapp" one-liner from an
untrusted site/README without reading it — low-likelihood but real, and cheap to
close. The icon download also has no `--proto`/size restriction, so `http://`
URLs are silently accepted with no TLS enforcement and no size cap.

### Fix

```diff
--- a/scripts/webapp-create
+++ b/scripts/webapp-create
@@
+    case "$name" in *$'\n'*|*$'\r'*) echo "Name must not contain newlines" >&2; exit 1 ;; esac
+    case "$url"  in *$'\n'*|*$'\r'*) echo "URL must not contain newlines" >&2; exit 1 ;; esac
+
     if [[ -n "$icon_url" ]]; then
         echo "Downloading icon..."
         if command -v curl >/dev/null 2>&1; then
-            curl -s -o "$icon_path" "$icon_url"
+            curl -s --proto '=https' --max-filesize 10485760 -o "$icon_path" "$icon_url"
         elif command -v wget >/dev/null 2>&1; then
             wget -q -O "$icon_path" "$icon_url"
         fi
     fi
```

---

## 11g (P2). Privileged `pkexec` helpers have no dedicated polkit `.policy` action

**Files:** `scripts/dwm-settings-display`, `scripts/dwm-settings-display-root`,
new `config/polkit/com.lyona.settings-display.policy`

Confirmed by repo-wide search: `find . -iname "*.policy"` returns nothing.
`scripts/dwm-settings-display:468-482`:

```sh
command -v pkexec >/dev/null 2>&1 || die "pkexec is unavailable"
...
pkexec "$helper" install "${DISPLAY:-}" "${XAUTHORITY:-}" "${records[@]}"
```

### Context

Calling `pkexec <path>` with no matching `.policy` action falls back to polkit's
generic `org.freedesktop.policykit.exec` action — a generic "Authenticate to run
`/usr/local/libexec/lyona/dwm-settings-display-root`" prompt rather than a scoped,
human-readable description, and inherits whatever the distro's default policy is
for that generic action (typically `auth_admin`, i.e. it does still require a
password — this is not exploitable today, just under-specified). It also means
there's no single place to tighten policy later (e.g. an `allow_active` check, or
non-caching auth) without touching the helper's own argument parsing. The
helper-side validation (`trusted_file`, `trusted_parent_chain`, `PKEXEC_UID` shape
check) is already solid — this is polish, not a hole.

### Fix

```diff
--- /dev/null
+++ b/config/polkit/com.lyona.settings-display.policy
@@
+<?xml version="1.0" encoding="UTF-8"?>
+<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
+ "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
+<policyconfig>
+  <action id="com.lyona.settings-display.manage">
+    <description>Manage the Lyona display configuration</description>
+    <message>Authentication is required to change the system display configuration</message>
+    <icon_name>video-display</icon_name>
+    <defaults>
+      <allow_any>no</allow_any>
+      <allow_inactive>no</allow_inactive>
+      <allow_active>auth_admin</allow_active>
+    </defaults>
+    <annotate key="org.freedesktop.policykit.exec.path">@PREFIX@/libexec/lyona/dwm-settings-display-root</annotate>
+  </action>
+</policyconfig>
```

Install to `/usr/share/polkit-1/actions/` from `Makefile`'s `install-system`
target, next to the existing privileged-helper install step.

---

## Already hardened — confirmed, not gaps

Recorded so a future pass doesn't re-discover these:

- **`scripts/install-herdr`** (whole file) — the project's own correct pattern:
  pinned version (`HERDR_VERSION`), pinned installer SHA-256
  (`HERDR_INSTALLER_SHA256_DEFAULT`), pinned per-arch binary SHA-256
  (`HERDR_X86_64_SHA256`/`HERDR_AARCH64_SHA256`), download-then-verify-then-stage
  (`mktemp -d`), atomic `mv -fT` into place, explicit refusal to run as root
  (`:48-51`). Every fix above matches this file's standard, not a new one.
- **The `mktemp` + `chmod 600/700` + atomic-`mv` convention**, used consistently
  across nearly all of `scripts/` — `dwm-settings-display`, `dwm-settings-theme`,
  `dwm-settings-font`, `dwm-settings-wallpaper`, `dwm-settings-input`,
  `dwm-default-apps`, `dwm-xdg-autostart`, `dwm-quickshell-controlcenter`,
  `dwm-status`, `dwm-session-launch`, `dwm-paths.sh`, `theme-apply.sh`. All of
  these also validate ownership/symlink status of any pre-existing path under the
  shared `${XDG_RUNTIME_DIR:-/tmp/lyona-$UID}` fallback before touching it — the
  TOCTOU-safe pattern any new script should be held to.
- **`scripts/dwm-quickshell-network`'s Wi-Fi password handling** — read from
  **stdin**, never a CLI argument (which would leak via `/proc/<pid>/cmdline` to
  any local user), written to a `umask 077`+`mktemp` temp file, cleaned up via
  `trap` on exit/signal, and the NetworkManager connection is deleted on failure
  so no half-configured secret profile is left behind.
- **`scripts/dwm-settings-display-root`, `scripts/dwm-system-health`'s
  `trusted_file`/`trusted_parent_chain`/`trusted_system_command` functions** —
  before trusting any privileged helper or system command: canonical path
  resolution (`readlink -f`) matches the expected installed path, every directory
  in the parent chain is root-owned and not group/world-writable, the target file
  itself is root-owned, non-symlink, and not group/world-writable, and (for the
  display-root helper) `PKEXEC_UID` is numeric and any `XAUTHORITY` path is owned
  by that same uid. Privileged repair actions in `dwm-system-health` are
  allowlisted by exact `case` match, unit names are regex-validated
  (`^[^[:space:]/\|]+[.]service$`), and every privileged command runs via an
  argument array — never a shell string — so there's no injection surface even
  though the inputs originate from a QML settings UI.
- **`archiso/pacman.conf`** — `SigLevel = Required DatabaseOptional` is the
  correct default trust posture; no repository is configured with a weakened
  `SigLevel`.
- **No embedded secrets** — a repo-wide grep for API-key/token/password-shaped
  literals across `scripts/` and `config/` found nothing.
- **No custom D-Bus service surface** — `config/quickshell` registers no
  `DBusInterface`/service on the session or system bus; the only IPC surface is
  Quickshell's built-in `IpcHandler` blocks in `shell.qml`, which communicate over
  Quickshell's own Unix socket under `XDG_RUNTIME_DIR` — already scoped to the
  invoking user.
- **`dwm.c`'s `sprintf`/`strcpy` call sites are not vulnerabilities** —
  `runautoscript()` allocates every buffer with `ecalloc()` sized to exactly fit
  the `sprintf` that follows it; `updatestatus()`/`updatetitle()` `strcpy` either a
  fixed version string or the 6-byte constant `broken[] = "broken"` into
  fixed-size buffers, never attacker-controlled data of unbounded length. Ruled
  out after reading the surrounding code, not from the grep hit alone.

---

## Verification

```bash
scripts/run-tests make clean all             # required after 11e's flag change
scripts/run-tests make check-shell
scripts/run-tests make check-format
```

Per item:

| Item | Verification |
| --- | --- |
| 11a | Stub `pacman` to fail; confirm `install-mybash` now downloads-and-verifies rather than piping to `sh`, and confirm a deliberately corrupted checksum aborts cleanly |
| 11b | Run `xscreensaver-setup.sh`, idle past `timeout` in a nested session; confirm a password prompt appears. Confirm `dwm-lock`'s new branch is only taken when the daemon is actually running (`pgrep -x xscreensaver`) |
| 11c | Re-run key import against the pinned fingerprint; deliberately corrupt the expected fingerprint locally and confirm the script refuses and deletes the untrusted key rather than signing it |
| 11d | Confirm `makepkg -si` (no `--noconfirm`) still completes wherever it's expected to run unattended, or document that interactive PKGBUILD review is now expected there |
| 11e | `scripts/run-tests make clean all` — no new warnings from `-Wformat-security`; confirm the built binary is PIE (`file dwm` reports "pie executable") and has RELRO (`readelf -d dwm \| grep BIND_NOW`) |
| 11f | `webapp-create` with a `$'\n'`-embedded name/URL — confirm rejection before any file is written |
| 11g | `pkexec` prompt shows the scoped message/icon from the new `.policy` file instead of the generic exec-path prompt |

## Closes

No existing `TASKS.md` checkbox — add a new one under a Phase 5 (or later) security
line, and add a `SECURITY.md` changelog-style note per item, matching that file's
existing "Security Boundaries" commitments.
