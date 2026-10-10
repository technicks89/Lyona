#!/usr/bin/env bash
# The CODE strings below are expanded by the inner shell, not here.
# shellcheck disable=SC2016
set -euo pipefail

# The image installer's keyboard and recovery (#265, #266):
# - the chosen keymap is applied to the console at once (loadkeys), so the
#   passwords are typed with it; the layouts offered are real console keymaps;
# - Esc in the timezone and mirror lists goes back to the question;
# - the summary can change one answer, and a new keyboard asks the passwords
#   again; Cancel is its first choice;
# - a failed archinstall shows the recovery menu with what state the disk is
#   in, and Retry runs archinstall again with the same answers;
# - the archinstall directory, credentials included, is removed on exit;
# - the postinstall says what state the machine is in from its first step.
#
# The wizard is loaded as a library. gum is a stub: each interactive call
# (choose, filter, input, confirm) takes the next line of answers, STATUS<TAB>TEXT;
# spin runs its command; style prints its text.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

root=$repo/archiso/airootfs/root
wizard=$root/lyona-install.sh
postinstall=$root/lyona-postinstall.sh

cat >"$work/bin/gum" <<'EOF'
#!/bin/bash
case $1 in
choose | filter | input | confirm)
	printf 'gum %s\n' "$*" >>"$STUB_DIR/gum.log"
	[[ $1 != filter ]] || cat >/dev/null
	line=$(head -n 1 "$STUB_DIR/answers")
	[[ -n $line ]] || { echo "no answer left for: gum $*" >>"$STUB_DIR/gum.log"; exit 99; }
	sed -i 1d "$STUB_DIR/answers"
	status=${line%%$'\t'*}
	text=${line#*$'\t'}
	[[ -z $text ]] || printf '%s\n' "$text"
	exit "$status"
	;;
spin)
	while (($# > 0)) && [[ $1 != -- ]]; do shift; done
	shift
	exec "$@"
	;;
style) printf '%s\n' "${@: -1}" ;;
*) exit 0 ;;
esac
EOF
cat >"$work/bin/loadkeys" <<'EOF'
#!/bin/sh
printf 'loadkeys %s\n' "$*" >>"$STUB_DIR/calls.log"
# STUB_LOADKEYS_FAILS: the one layout loadkeys cannot load.
[ "$1" != "${STUB_LOADKEYS_FAILS:-}" ]
EOF
cat >"$work/bin/localectl" <<'EOF'
#!/bin/sh
printf 'us\nde\nde-latin1\nfr\nsv-latin1\n'
EOF
for cmd in clear tput sleep umount cryptsetup lsblk; do
	printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >>"$STUB_DIR/calls.log"\n' "$cmd" >"$work/bin/$cmd"
done
chmod +x "$work/bin/"*

# answers LINE...: the gum answers, in order.
answers() {
	printf '%s\n' "$@" >"$work/answers"
}
# lib CODE: CODE with the wizard loaded as a library; its output in out.log.
lib() {
	: >"$work/gum.log"
	: >"$work/calls.log"
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/bin:$PATH" STUB_DIR="$work" LYONA_INSTALL_LIB=1 \
		LYONA_UI_LIB="$root/lyona-ui.sh" LYONA_NVIDIA_LIB="$root/lyona-nvidia.sh" \
		LYONA_WIFI_LIB="$root/lyona-wifi.sh" LYONA_LOGO_PATH=/nonexistent \
		LYONA_ZONEINFO="$work/zoneinfo" LOG_FILE="$work/install.log" \
		STUB_LOADKEYS_FAILS="${STUB_LOADKEYS_FAILS:-}" \
		bash -c '. "$1"; eval "$2"' bash "$wizard" "$1" >"$work/out.log" 2>&1
}
mkdir -p "$work/zoneinfo"
printf 'DE\t+5230+01322\tEurope/Berlin\n' >"$work/zoneinfo/zone.tab"
printf 'DE\tGermany\nJP\tJapan\n' >"$work/zoneinfo/iso3166.tab"

# ── #265: the keyboard ─────────────────────────────────────────────────────

# Every layout offered by name is a real console keymap (se, tr and si were
# not: archinstall would have been given a layout that does not exist).
if command -v localectl >/dev/null 2>&1 && [[ -n $(localectl list-keymaps 2>/dev/null) ]]; then
	known=$(localectl list-keymaps)
	codes=$(env PATH="$work/bin:$PATH" STUB_DIR="$work" LYONA_INSTALL_LIB=1 \
		LYONA_UI_LIB="$root/lyona-ui.sh" LYONA_NVIDIA_LIB="$root/lyona-nvidia.sh" \
		LYONA_WIFI_LIB="$root/lyona-wifi.sh" LYONA_LOGO_PATH=/nonexistent \
		bash -c '. "$1"; for e in "${KEYMAP_NAMES[@]}"; do printf "%s\n" "${e%%|*}"; done' bash "$wizard")
	while IFS= read -r code; do
		grep -Fxq -- "$code" <<<"$known" || fail "the keyboard list offers $code, which is not a console keymap"
	done <<<"$codes"
fi

# Chosen by name: the code, applied to this console, and said.
answers $'0\tGerman (de)'
lib 'ask_keymap; printf "KEYMAP=%s\n" "$KEYMAP"' || fail "choosing German failed: $(cat "$work/out.log")"
grep -Fxq 'KEYMAP=de' "$work/out.log" || fail "German did not give de: $(cat "$work/out.log")"
grep -Fxq 'loadkeys de' "$work/calls.log" || fail 'the chosen layout was not applied to the console'
grep -Fq 'the passwords below are typed with it' "$work/out.log" || fail 'applying the layout was not said'
grep -Fq 'type to search' "$work/gum.log" || fail 'the keyboard list is not searchable'

# Chosen by its code from the full list.
answers $'0\tfr'
lib 'ask_keymap; printf "KEYMAP=%s\n" "$KEYMAP"'
grep -Fxq 'KEYMAP=fr' "$work/out.log" || fail 'a keymap chosen by its code was not kept'

# Not a keymap here: asked again.
answers $'0\tnot-a-layout' $'0\tSwedish (sv-latin1)'
lib 'ask_keymap; printf "KEYMAP=%s\n" "$KEYMAP"'
grep -Fq 'not-a-layout is not a keyboard layout' "$work/out.log" || fail 'an unknown layout was not refused'
grep -Fxq 'KEYMAP=sv-latin1' "$work/out.log" || fail 'the layout was not asked again'

# loadkeys fails: the layout installed must be the one the passwords are typed
# with, so the user keeps the active layout or chooses another.
answers $'0\tGerman (de)' $'0\tKeep us (the layout this console has)'
STUB_LOADKEYS_FAILS=de lib 'ask_keymap; printf "KEYMAP=%s\n" "$KEYMAP"' || fail 'a failed loadkeys stopped the wizard'
grep -Fq 'Could not switch this console to de' "$work/out.log" || fail 'a failed loadkeys was not said'
grep -Fxq 'KEYMAP=us' "$work/out.log" || fail "keeping the active layout did not install it: $(cat "$work/out.log")"
answers $'0\tGerman (de)' $'0\tChoose another layout' $'0\tFrench (fr)'
STUB_LOADKEYS_FAILS=de lib 'ask_keymap; printf "KEYMAP=%s\n" "$KEYMAP"'
grep -Fxq 'KEYMAP=fr' "$work/out.log" || fail 'choosing another layout after a failure did not take it'
grep -Fxq 'loadkeys fr' "$work/calls.log" || fail 'the other layout was not applied'
# French active, then a change to German fails: French stays, for both.
answers $'0\tFrench (fr)' $'0\tGerman (de)' $'0\tKeep fr (the layout this console has)'
STUB_LOADKEYS_FAILS=de lib 'ask_keymap; ask_keymap; printf "KEYMAP=%s\n" "$KEYMAP"'
grep -Fxq 'KEYMAP=fr' "$work/out.log" || fail "the active layout was not the one kept: $(cat "$work/out.log")"

# ── #266: Esc goes back in the lists ──────────────────────────────────────

# Timezone: detect it, "No", Esc in the list, back at the question, "Yes".
answers $'0\t' $'1\t' $'1\t' $'0\t'
lib 'detect_timezone() { echo Europe/Berlin; }; ask_timezone; printf "TZ=%s\n" "$TIMEZONE"' ||
	fail "Esc in the timezone list ended the wizard: $(cat "$work/out.log")"
grep -Fxq 'TZ=Europe/Berlin' "$work/out.log" || fail 'Esc in the timezone list did not go back to the question'
[[ $(grep -c 'Detected timezone' "$work/gum.log") == 2 ]] || fail 'the timezone question was not asked again'

# Nothing detected: Esc in the list asks; "Choose from the list" goes back to
# it, Esc on the question too, and only "Cancel the installer" ends.
answers $'0\t' $'1\t' $'0\tChoose from the list' $'1\t' $'1\t' $'0\tEurope/Berlin'
lib 'detect_timezone() { return 1; }; choose_timezone() { local z; z=$(gum filter </dev/null) || return 1; printf "%s\n" "$z"; }
	ask_timezone; printf "TZ=%s\n" "$TIMEZONE"' || fail "Esc with no detected timezone ended the wizard: $(cat "$work/out.log")"
grep -Fxq 'TZ=Europe/Berlin' "$work/out.log" || fail "the list was not offered again: $(cat "$work/out.log")"
answers $'0\t' $'1\t' $'0\tCancel the installer'
if lib 'detect_timezone() { return 1; }; choose_timezone() { gum filter </dev/null >/dev/null || return 1; }; ask_timezone'; then
	fail 'Cancel the installer did not end it'
fi
grep -Fq 'Nothing on the disk was changed' "$work/out.log" || fail 'cancelling from the timezone did not say nothing changed'

# #328: the lookup runs only after a yes. "No" goes straight to the list, and
# nothing is looked up.
answers $'1\t' $'0\tEurope/Paris'
lib "detect_timezone() { : >\"$work/looked-up\"; echo Europe/Berlin; }
	choose_timezone() { local z; z=\$(gum filter </dev/null) || return 1; printf '%s\\n' \"\$z\"; }
	ask_timezone; printf 'TZ=%s\\n' \"\$TIMEZONE\"" || fail "declining the lookup ended the wizard: $(cat "$work/out.log")"
[[ ! -e $work/looked-up ]] || fail 'the timezone was looked up online after a no'
grep -Fxq 'TZ=Europe/Paris' "$work/out.log" || fail "declining the lookup did not offer the list: $(cat "$work/out.log")"
grep -Fq 'sends your IP address' "$work/gum.log" || fail 'the lookup question does not say it sends the IP address'

# Mirrors: "Choose another", Esc in the countries, back, "Choose another", Japan.
answers $'1\t' $'1\t' $'1\t' $'0\tJapan (JP)'
lib 'TIMEZONE=Europe/Berlin; ask_mirrors; printf "MIRRORS=%s\n" "$MIRROR_COUNTRY"' ||
	fail "Esc in the country list ended the wizard: $(cat "$work/out.log")"
grep -Fxq 'MIRRORS=JP' "$work/out.log" || fail "Esc in the country list did not go back: $(cat "$work/out.log")"
# Esc, then Yes: the timezone's country, not a half-chosen one.
answers $'1\t' $'1\t' $'0\t'
lib 'TIMEZONE=Europe/Berlin; ask_mirrors; printf "MIRRORS=%s\n" "$MIRROR_COUNTRY"'
grep -Fxq 'MIRRORS=DE' "$work/out.log" || fail 'going back did not restore the timezone'"'"'s country'

# ── #266: change an answer on the summary ─────────────────────────────────

summary_state='DISK=/dev/vda FILESYSTEM=btrfs ENCRYPT=0 HOSTNAME=old USERNAME=me KEYMAP=us TIMEZONE=Europe/Berlin MIRROR_COUNTRY=DE FIRMWARE=uefi NVIDIA_DETECTED=0'
answers $'0\tChange an answer...' $'0\tHostname' $'0\tnewhost' $'0\tWipe /dev/vda and install'
lib "$summary_state; confirm_and_proceed; printf 'HOST=%s\n' \"\$HOSTNAME\"" ||
	fail "changing an answer failed: $(cat "$work/out.log")"
grep -Fxq 'HOST=newhost' "$work/out.log" || fail "the hostname was not changed: $(cat "$work/out.log")"
[[ $(grep -c 'Hostname:   ' "$work/out.log") == 2 ]] || fail 'the summary was not shown again after the change'
grep -q '^gum choose --header Proceed? Cancel ' "$work/gum.log" || fail 'Cancel is not the first choice on the summary'
# Cancel: ends, nothing changed.
answers $'0\tCancel'
if lib "$summary_state; confirm_and_proceed"; then fail 'Cancel on the summary went on'; fi
grep -Fq 'Nothing on the disk was changed' "$work/out.log" || fail 'Cancel did not say nothing changed'
# A new keyboard asks the passwords again, with it.
answers $'0\tChange an answer...' $'0\tKeyboard' $'0\tFrench (fr)' $'0\tme' $'0\tpw' $'0\tpw' \
	$'0\tWipe /dev/vda and install'
lib "$summary_state; confirm_and_proceed; printf 'KEYMAP=%s\n' \"\$KEYMAP\"" ||
	fail "changing the keyboard failed: $(cat "$work/out.log")"
grep -Fxq 'KEYMAP=fr' "$work/out.log" || fail 'the keyboard was not changed'
grep -Fq 'Type the passwords again with the new layout' "$work/out.log" || fail 'a new keyboard did not ask the passwords again'
grep -q 'gum input --password --header Password (keyboard: fr):' "$work/gum.log" ||
	fail 'the password was not asked again, with the new layout named'

# ── #266: a failed archinstall, retried ───────────────────────────────────

cat >"$work/bin/archinstall" <<'EOF'
#!/bin/sh
printf 'archinstall\n' >>"$STUB_DIR/calls.log"
n=$(cat "$STUB_DIR/archinstall-runs" 2>/dev/null || echo 0)
echo $((n + 1)) >"$STUB_DIR/archinstall-runs"
[ "$n" -ge "${STUB_ARCHINSTALL_FAILS:-0}" ]
EOF
printf '#!/bin/sh\nexit 0\n' >"$work/bin/mountpoint"
chmod +x "$work/bin/archinstall" "$work/bin/mountpoint"
rm -f "$work/archinstall-runs"
answers $'0\tRetry'
STUB_ARCHINSTALL_FAILS=1 lib 'DISK=/dev/vda; WORK_DIR=$(mktemp -d -p "$STUB_DIR"); CONFIG_JSON=c; CREDS_JSON=d
	run_archinstall; [[ ! -e $WORK_DIR ]] && echo WORK-DIR-REMOVED' ||
	fail "a retried archinstall failed: $(cat "$work/out.log")"
[[ $(grep -c '^archinstall$' "$work/calls.log") == 2 ]] || fail 'Retry did not run archinstall again'
grep -Fq '/dev/vda may already be erased' "$work/out.log" || fail 'the recovery menu did not say what state the disk is in'
grep -Fq 'Retry' "$work/gum.log" || fail 'no recovery menu after a failed archinstall'
grep -Fxq 'umount -R /mnt' "$work/calls.log" || fail 'the target was not released before the retry'
grep -Fxq 'WORK-DIR-REMOVED' "$work/out.log" || fail 'the archinstall directory was not removed after success'
[[ $(grep -c 'Detected timezone\|Select the disk' "$work/gum.log") == 0 ]] || fail 'Retry asked the questions again'

# Exit to shell: ends with archinstall's status.
rm -f "$work/archinstall-runs"
answers $'0\tExit to shell'
status=0
STUB_ARCHINSTALL_FAILS=9 lib 'DISK=/dev/vda; WORK_DIR=$(mktemp -d -p "$STUB_DIR"); CONFIG_JSON=c; CREDS_JSON=d
	run_archinstall' || status=$?
((status != 0)) || fail 'Exit to shell after a failed archinstall went on'

# The work directory, credentials included, goes however the run ends.
lib 'trap lyona_cleanup_files EXIT; d=$(mktemp -d -p "$STUB_DIR"); echo "$d" >"$STUB_DIR/workdir"
	: >"$d/creds.json"; LYONA_CLEANUP_FILES+=("$d"); exit 3' || :
[[ ! -e $(cat "$work/workdir") ]] || fail 'the archinstall directory was left behind on exit'
grep -Fq 'LYONA_CLEANUP_FILES+=("$WORK_DIR")' "$wizard" || fail 'generate_configs does not register its directory for cleanup'

# ── #266: the postinstall says what state the machine is in from step 1 ──

first_step=$(grep -n '^run_logged ' "$postinstall" | head -n 1 | cut -d: -f1)
first_hint=$(grep -n '^LYONA_RECOVER_HINT=' "$postinstall" | head -n 1 | cut -d: -f1)
[[ -n $first_hint && $first_hint -lt $first_step ]] || fail 'the postinstall has no recovery hint before its first step'

printf 'Image installer keyboard and recovery (keymap, back, change, retry, cleanup, hints): PASS\n'
