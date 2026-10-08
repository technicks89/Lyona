# Step 2: Picom is required with the lyona desktop

Commit: "Treat Picom as part of the lyona desktop (#244)".

## What changes

- **Checks:** `picom` moves from the `desktop` command tier to a new
  `compositor` tier. `check-deps.sh` and `dwm-diagnostics` report it missing as
  a required failure when the lyona desktop is installed (Quickshell present),
  and as optional otherwise, so a core install is not flagged (decision 1).
- **Health report:** a stopped Picom is a warning that says previews are off; a
  missing one is an error with the desktop installed, and information without
  it.
- **Autostart:** unchanged when Picom starts. When it cannot start, or is not
  installed although the desktop is, the user gets **one** notification. It
  waits up to 30 seconds for Quickshell's notification service, then gives up:
  never a retry loop, and never anything that blocks the session.
- **Stop and toggle** stay troubleshooting actions (decision 4). The Control
  Center's `toggle-compositor` says which way it went, and that previews are off
  while Picom is stopped.

The installers need nothing: `picom` is in `arch:desktop`, which `install.sh`
puts in the required part of its one transaction for the recommended and full
profiles, and the image installs the full profile.

## `scripts/dwm-packages.sh`

```diff
 # Accepts one or more profiles and installs them as a single transaction.
 # The commands check-deps.sh and dwm-diagnostics check, by tier, so the two
 # agree (Sync Sprint 16 R16-45; SPEC 5.8). Required: the X11 session and the
 # tools core keybindings need, beside the build tools and a terminal, which
 # both check on their own. Desktop: the recommended desktop's commands, whose
-# absence degrades it but does not break the session.
-dwm_command_tier() { # required|desktop
+# absence degrades it but does not break the session. Compositor: Picom, part of
+# the lyona desktop, whose window previews need it (#244); required when the
+# desktop is installed (dwm_desktop_installed), optional in a core install.
+dwm_command_tier() { # required|desktop|compositor
 	case $1 in
 	required) printf '%s\n' startx xrandr xset xsetroot xclip xdotool ;;
 	desktop)
-		printf '%s\n' quickshell picom feh maim xdg-open notify-send amixer brightnessctl \
+		printf '%s\n' quickshell feh maim xdg-open notify-send amixer brightnessctl \
 			light-locker gsettings xprop jq bluetoothctl blueman-applet cosign
 		;;
+	compositor) printf '%s\n' picom ;;
 	*) return 2 ;;
 	esac
 }
+
+# Whether the lyona desktop, the managed Quickshell shell, is installed: then
+# the compositor tier is required (#244).
+dwm_desktop_installed() {
+	command -v quickshell >/dev/null 2>&1
+}
```

## `scripts/check-deps.sh`

After the desktop section:

```diff
 if command -v dex &>/dev/null || command -v dex-autostart &>/dev/null; then
 	printf "  ${GREEN}✓${NC} XDG autostart runner\n"
 else
 	printf "  ${YELLOW}!${NC} dex or dex-autostart ${YELLOW}(optional, missing)${NC}\n"
 fi
 echo ""
 
+# Picom is part of the lyona desktop: required with it, optional without (#244).
+echo "Compositor (required with the lyona desktop; window previews need it):"
+while IFS= read -r command; do
+	if dwm_desktop_installed; then
+		check_cmd "$command"
+	else
+		check_optional_cmd "$command"
+	fi
+done < <(dwm_command_tier compositor)
+echo ""
+
 echo "Terminal Emulators (at least one required):"
```

## `scripts/dwm-diagnostics`

Before the optional desktop section:

```diff
 	done < <(dwm_command_tier required)
 	check_terminal
 
+	# Picom is part of the lyona desktop: required with it, optional without
+	# (#244).
+	if [[ $format == human ]]; then
+		printf '\nCompositor\n'
+	fi
+	while IFS= read -r cmd; do
+		if dwm_desktop_installed; then
+			check_required_cmd "$cmd"
+		else
+			check_optional_cmd "$cmd"
+		fi
+	done < <(dwm_command_tier compositor)
+
 	if [[ $format == human ]]; then
 		printf '\nOptional desktop\n'
 	fi
```

## `scripts/dwm-system-health`

It does not source `dwm-packages.sh`, so the desktop test is inline, the same
`command -v quickshell`.

```diff
 	if command -v picom >/dev/null 2>&1; then
 		status=warn
 		pgrep -x picom >/dev/null 2>&1 && status=ok
-		emit_check desktop "$status" picom-process "Picom" "$([[ $status == ok ]] && printf running || printf stopped)" "Optional compositor" restart-picom "Restart Picom" user
+		emit_check desktop "$status" picom-process "Picom" "$([[ $status == ok ]] && printf running || printf 'stopped: window previews are off')" "The compositor, part of the lyona desktop" restart-picom "Restart Picom" user
+	elif command -v quickshell >/dev/null 2>&1; then
+		emit_check desktop error picom-process "Picom" "Not installed: window previews are off" "The lyona desktop needs the compositor (#244)" install-dependencies "Open dependency installer" user
 	else
-		emit_check desktop info picom-process "Picom" "Not installed" "The compositor is optional" install-dependencies "Open dependency installer" user
+		emit_check desktop info picom-process "Picom" "Not installed" "Needed only with the lyona desktop" install-dependencies "Open dependency installer" user
 	fi
```

## `scripts/autostart.sh`

The helper prints errors as plain text on stderr (`Picom failed to start; see
LOG`), which goes into the notification.

```diff
-# dwm-settings-picom picks the backend for this GPU and honours PICOM_BACKEND
-# as an override; it starts nothing if this display already has a compositor.
-if command -v picom >/dev/null 2>&1; then
-	picom_helper=$(command -v dwm-settings-picom 2>/dev/null || printf '%s' "${0%/*}/dwm-settings-picom")
-	"$picom_helper" start >/dev/null 2>&1 &
-fi
+# One notification about the session, once. Quickshell shows notifications and
+# may not be up yet, so it is tried for up to DWM_AUTOSTART_NOTIFY_TRIES (15)
+# times DWM_AUTOSTART_NOTIFY_INTERVAL (2) seconds, then given up: never a loop.
+notify_session_problem() {
+	command -v notify-send >/dev/null 2>&1 || return 0
+	tries=${DWM_AUTOSTART_NOTIFY_TRIES:-15}
+	while [ "$tries" -gt 0 ]; do
+		notify-send -a lyona -u critical -- "$1" "$2" >/dev/null 2>&1 && return 0
+		tries=$((tries - 1))
+		[ "$tries" -eq 0 ] || sleep "${DWM_AUTOSTART_NOTIFY_INTERVAL:-2}"
+	done
+	return 0
+}
+
+# Picom is part of the lyona desktop: the overview's window previews need it
+# (#244). dwm never depends on it. If it is missing or cannot start, the session
+# goes on, the overview keeps its icon-and-title cards, and the user is told
+# once. dwm-settings-picom picks the backend for this GPU and honours
+# PICOM_BACKEND as an override; it starts nothing if this display already has a
+# compositor.
+start_compositor() {
+	if ! command -v picom >/dev/null 2>&1; then
+		command -v quickshell >/dev/null 2>&1 || return 0
+		notify_session_problem "Picom is not installed" \
+			"Window previews in the overview are off. Install it with: sudo pacman -S picom"
+		return 0
+	fi
+	picom_helper=$(command -v dwm-settings-picom 2>/dev/null || printf '%s' "${0%/*}/dwm-settings-picom")
+	if ! picom_error=$("$picom_helper" start 2>&1 >/dev/null); then
+		notify_session_problem "Picom could not start" \
+			"Window previews in the overview are off. Try Restart Picom in the Control Center. $picom_error"
+	fi
+	return 0
+}
+start_compositor &
```

## `scripts/dwm-quickshell-controlcenter`

```diff
 toggle_compositor() {
 	picom_action toggle || return 1
-	notify "Compositor toggled"
+	# A troubleshooting action (#244): previews need Picom running.
+	if pgrep -x picom >/dev/null 2>&1; then
+		notify "Compositor started"
+	else
+		notify "Compositor stopped" "Window previews in the overview are off until Picom starts again."
+	fi
 }
```

`dwm-settings-picom stop` itself prints `Picom stopped`, which Settings shows;
it is not changed. The troubleshooting page says what stopping costs (step 3).

## `tests/test-dwm-diagnostics.sh`

The base run has no Quickshell stub, so Picom is optional there, as in a core
install.

```diff
 grep -Fq "Optional desktop" "$work/ok"
 grep -Fq "degraded quickshell" "$work/ok"
 grep -Fq "degraded maim" "$work/ok"
+# No Quickshell, as in a core install: Picom is optional (#244).
+grep -Fq "degraded picom" "$work/ok"
 # The developer override is always reported (Sync Sprint 12 S12-13).
 grep -Fqx "  LYONA_DEV_SCRIPTS not set (installed helpers)" "$work/ok"
 env HOME="$work/home" PATH="$work/bin" LYONA_DEV_SCRIPTS="$work/checkout/scripts" \
 	"$BASH_BIN" "$HELPER" >"$work/dev"
 grep -Fqx "  LYONA_DEV_SCRIPTS=$work/checkout/scripts (helpers from a development checkout)" "$work/dev"
 
+# #244: with the lyona desktop installed (Quickshell), Picom is required.
+for cmd in quickshell picom; do
+	printf '#!/bin/sh\nexit 0\n' >"$work/bin/$cmd"
+	chmod +x "$work/bin/$cmd"
+done
+env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/desktop-ok"
+grep -Fqx "  required_failures=0" "$work/desktop-ok" || fail "Picom installed with the desktop is not ok"
+rm -f "$work/bin/picom"
+if env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/desktop-no-picom"; then
+	fail "diagnostics passed with the lyona desktop installed and Picom missing"
+fi
+grep -Fqx "  missing picom" "$work/desktop-no-picom" || fail "a missing Picom is not a required failure with the desktop"
+rm -f "$work/bin/quickshell"
+
 rm -f "$work/bin/alacritty" "$work/bin/Xorg"
```

```diff
 for checker in "$repo/scripts/check-deps.sh" "$repo/scripts/dwm-diagnostics"; do
-	for tier in required desktop; do
+	for tier in required desktop compositor; do
 		grep -Fq "done < <(dwm_command_tier $tier)" "$checker" || fail "${checker##*/} does not check the $tier tier"
 	done
 	if grep -Eq '^[[:space:]]*(check_cmd|check_required_cmd|check_optional_cmd) "?(quickshell|picom|feh|xdotool|blueman-applet)"?$' "$checker"; then
 		fail "${checker##*/} still lists a tiered command by hand"
 	fi
 done
-for command in quickshell picom feh; do
+for command in quickshell feh; do
 	(. "$repo/scripts/dwm-packages.sh" && dwm_command_tier desktop) | grep -Fxq "$command" ||
 		fail "$command is not in the desktop tier"
 done
+# #244: Picom is the compositor tier, and only that.
+[[ $(. "$repo/scripts/dwm-packages.sh" && dwm_command_tier compositor) == picom ]] ||
+	fail "picom is not the compositor tier"
+if (. "$repo/scripts/dwm-packages.sh" && dwm_command_tier desktop) | grep -Fxq picom; then
+	fail "picom is still in the desktop tier"
+fi
```

## New: `tests/test-autostart-compositor.sh`

`notify_session_problem` and `start_compositor` are extracted from
`autostart.sh` and run against stubs, with a `PATH` holding only the stubs and
the two tools they use, so the host's own `picom`, `quickshell` and
`notify-send` are never reached.

```bash
#!/usr/bin/env bash
set -euo pipefail

# #244: autostart starts Picom through dwm-settings-picom, and says so once when
# it cannot: a missing Picom with the lyona desktop installed, or a failed start.
# The notification waits for the notification service a bounded number of times,
# then gives up; a core install (no Quickshell) is not told anything.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

{
	sed -n '/^notify_session_problem() {$/,/^}$/p' "$repo/scripts/autostart.sh"
	sed -n '/^start_compositor() {$/,/^}$/p' "$repo/scripts/autostart.sh"
} >"$work/compositor.sh"
grep -q '^start_compositor() {$' "$work/compositor.sh" || fail 'start_compositor not found in autostart.sh'
grep -q '^notify_session_problem() {$' "$work/compositor.sh" || fail 'notify_session_problem not found in autostart.sh'
grep -Fxq 'start_compositor &' "$repo/scripts/autostart.sh" || fail 'autostart.sh does not start the compositor in the background'

mkdir -p "$work/stubs"
for tool in sleep cat; do
	ln -s "$(command -v "$tool")" "$work/stubs/$tool"
done
cat >"$work/stubs/dwm-settings-picom" <<'EOF'
#!/bin/sh
[ "$1" = start ] || exit 2
if [ "${STUB_PICOM_FAILS:-0}" = 1 ]; then
	printf 'Picom failed to start; see /run/user/1000/lyona-picom/picom.log\n' >&2
	exit 1
fi
printf '{"protocol": 1, "message": "Picom active"}\n'
EOF
# Fails while the notification service is "not up yet": the first STUB_NOTIFY_DOWN calls.
cat >"$work/stubs/notify-send" <<'EOF'
#!/bin/sh
count=$(($(cat "$TEST_DIR/notify.count" 2>/dev/null || printf 0) + 1))
printf '%s\n' "$count" >"$TEST_DIR/notify.count"
[ "$count" -gt "${STUB_NOTIFY_DOWN:-0}" ] || exit 1
printf '%s\n' "$*" >>"$TEST_DIR/notify.log"
EOF
chmod +x "$work/stubs/dwm-settings-picom" "$work/stubs/notify-send"

run_case() { # HAVE-PICOM HAVE-QUICKSHELL
	local name
	rm -f "$work/notify.count" "$work/notify.log" "$work/stubs/picom" "$work/stubs/quickshell"
	for name in picom quickshell; do
		[[ $name == picom && $1 == yes || $name == quickshell && $2 == yes ]] || continue
		printf '#!/bin/sh\nexit 0\n' >"$work/stubs/$name"
		chmod +x "$work/stubs/$name"
	done
	env -i PATH="$work/stubs" TEST_DIR="$work" DWM_AUTOSTART_NOTIFY_INTERVAL=0 \
		STUB_PICOM_FAILS="${STUB_PICOM_FAILS:-0}" STUB_NOTIFY_DOWN="${STUB_NOTIFY_DOWN:-0}" \
		DWM_AUTOSTART_NOTIFY_TRIES="${DWM_AUTOSTART_NOTIFY_TRIES:-15}" \
		/bin/sh -c '. "$1" && start_compositor' sh "$work/compositor.sh"
}
notified() { # COUNT
	local lines=0
	[[ ! -f $work/notify.log ]] || lines=$(wc -l <"$work/notify.log")
	[[ $lines == "$1" ]]
}

# Picom starts: nothing to say.
run_case yes yes || fail 'a working start failed'
notified 0 || fail 'a working start sent a notification'

# The start fails: one notification, with the helper's message in it.
STUB_PICOM_FAILS=1 run_case yes yes || fail 'a failed start stopped autostart'
notified 1 || fail 'a failed start was not notified exactly once'
grep -Fq -- '-a lyona -u critical -- Picom could not start Window previews in the overview are off.' "$work/notify.log" ||
	fail 'the failed-start notification is not the expected one'
grep -Fq 'see /run/user/1000/lyona-picom/picom.log' "$work/notify.log" || fail 'the notification does not carry the log path'

# Picom missing with the desktop installed: one notification.
run_case no yes || fail 'a missing Picom stopped autostart'
notified 1 || fail 'a missing Picom was not notified exactly once'
grep -Fq 'Picom is not installed' "$work/notify.log" || fail 'the missing-Picom notification is not the expected one'

# A core install (no Quickshell, no Picom): nothing.
run_case no no || fail 'a core session failed'
notified 0 || fail 'a core session was told about Picom'

# The notification service comes up on the third try: delivered once.
STUB_PICOM_FAILS=1 STUB_NOTIFY_DOWN=2 run_case yes yes
notified 1 || fail 'a late notification service did not get the message once'
[[ $(cat "$work/notify.count") == 3 ]] || fail 'the notification was not retried until the service was up'

# It never comes up: given up after the tries, and autostart goes on.
STUB_PICOM_FAILS=1 STUB_NOTIFY_DOWN=99 DWM_AUTOSTART_NOTIFY_TRIES=4 run_case yes yes ||
	fail 'an absent notification service stopped autostart'
notified 0 || fail 'a notification was recorded without a service'
[[ $(cat "$work/notify.count") == 4 ]] || fail 'the notification was not given up after the tries'

printf 'Autostart compositor and its one message: PASS\n'
```

`Makefile`:

```diff
 check-session-guards:
 	tests/test-autostart.sh
+	tests/test-autostart-compositor.sh
 	tests/test-autostop.sh
```

`tests/test-autostart.sh` needs no change: its `dwm-settings-picom` stub
succeeds, so `start_compositor` sends nothing.

## Validation

- `make check-session-guards`, `tests/test-dwm-diagnostics.sh`,
  `make check-system-health` (or whichever target runs
  `tests/test-system-health.sh`), `make check-quickshell-controlcenter`.
- `shellcheck` and `shfmt` on every changed script.
- In the VM: with Picom uninstalled, log in. The session starts, the overview
  shows icon-and-title cards, and one notification says Picom is not installed.
  With `picom` replaced by a script that exits 1, one notification says it could
  not start, with the log path. Neither repeats.
