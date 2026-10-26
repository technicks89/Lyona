#!/usr/bin/env bash
# The CODE strings below are expanded by the inner shell, not here.
# shellcheck disable=SC2016
set -euo pipefail

# The Raspberry Pi image's first boot (ARM3-02), stubbed: every command that
# would touch the machine is a stub that logs its arguments, and the files it
# writes go under a private root. A first boot:
# - grows the root partition when there is room, and makes the keyring;
# - asks the install medium's questions (gum answers from a file);
# - applies the keymap, hostname, timezone, NTP and Wi-Fi country;
# - creates the user in wheel, with the %wheel sudo rule, the password on
#   chpasswd's stdin and in no process's arguments;
# - installs lyona's per-user half as that user (mybash, user folders,
#   install.sh's pinned wallpapers, make install-user, the first-login keys);
# - writes the done marker and disables itself.
# Then: a second start does nothing; an interrupted run's user is removed
# before the questions; a cancelled question starts them again; a failed step
# offers to start again or power off, and is not marked done; Wi-Fi goes
# through NetworkManager with the passphrase in a keyfile, not in nmcli's
# arguments.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

firstboot=$repo/rpi/lyona-firstboot.sh
wizard_dir=$repo/archiso/airootfs/root
bash -n "$firstboot"
[[ -x $firstboot ]] || fail "rpi/lyona-firstboot.sh is not executable."

# The unit: on tty1, before LightDM and in place of tty1's getty, and with
# stderr on the terminal, where gum draws when its answer is captured (with
# stderr in the journal it had no terminal to size, and crashed).
unit=$repo/rpi/lyona-firstboot.service
# TERM too: the wizard's screens (clear, tput) need it, and a unit has none
# of its own; the runs below are given the same.
for line in StandardInput=tty StandardOutput=tty StandardError=tty TTYPath=/dev/tty1 Environment=TERM=linux \
	'Before=display-manager.service getty@tty1.service' Conflicts=getty@tty1.service \
	'ConditionPathExists=!/var/lib/lyona/firstboot-done' ExecStart=/usr/local/libexec/lyona/lyona-firstboot; do
	grep -Fqx -- "$line" "$unit" || fail "lyona-firstboot.service lacks: $line"
done
# Nothing starts tty1's getty after it: Arch's LightDM conflicts with getty@tty1,
# and an ExecStopPost that started it cancelled LightDM's start.
if grep -n 'start getty@tty1' "$unit"; then
	fail "lyona-firstboot.service starts getty@tty1, which cancels LightDM."
fi
grep -Fqx 'ConditionPathExists=/var/lib/lyona/firstboot-done' "$repo/rpi/lightdm-after-firstboot.conf" ||
	fail "LightDM's drop-in does not wait for the first boot."

# A logging stub for each command: its arguments, one call per line.
stub_log() { # NAME [EXIT]
	printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"$STUB_DIR/calls.log"\nexit %s\n' "$1" "${2:-0}" >"$work/bin/$1"
	chmod +x "$work/bin/$1"
}
for command in sfdisk partx resize2fs pacman-key ssh-keygen systemd-machine-id-setup \
	localectl hostnamectl timedatectl userdel visudo loadkeys xdg-user-dirs-update chown sleep; do
	stub_log "$command"
done
# localectl also lists the keymaps the wizard checks the choice against.
cat >"$work/bin/localectl" <<'EOF'
#!/bin/bash
if [[ $1 == list-keymaps ]]; then printf '%s\n' de us; exit 0; fi
printf 'localectl %s\n' "$*" >>"$STUB_DIR/calls.log"
EOF
cat >"$work/bin/timedatectl" <<'EOF'
#!/bin/bash
if [[ $1 == list-timezones ]]; then printf '%s\n' Europe/Berlin America/New_York; exit 0; fi
printf 'timedatectl %s\n' "$*" >>"$STUB_DIR/calls.log"
EOF
# The network is up: the wizard checks it with curl.
stub_log curl
# systemctl: logged; STUB_SYSTEMCTL_FAIL makes poweroff and the rest fail.
stub_log systemctl
# findmnt and lsblk: the root is mmcblk0p2 on mmcblk0.
printf '#!/bin/sh\necho /dev/mmcblk0p2\n' >"$work/bin/findmnt"
printf '#!/bin/sh\necho mmcblk0\n' >"$work/bin/lsblk"
# useradd makes the home getent then names; chpasswd keeps its stdin.
cat >"$work/bin/useradd" <<'EOF'
#!/bin/bash
printf 'useradd %s\n' "$*" >>"$STUB_DIR/calls.log"
mkdir -p "$STUB_DIR/home/${*: -1}"
printf '%s\n' "${*: -1}" >"$STUB_DIR/users"
EOF
cat >"$work/bin/getent" <<'EOF'
#!/bin/bash
[[ $1 == passwd && -s $STUB_DIR/users ]] && grep -Fqx "$2" "$STUB_DIR/users" || exit 2
printf '%s:x:1000:1000::%s:/bin/bash\n' "$2" "$STUB_DIR/home/$2"
EOF
cat >"$work/bin/chpasswd" <<'EOF'
#!/bin/bash
printf 'chpasswd %s\n' "$*" >>"$STUB_DIR/calls.log"
cat >"$STUB_DIR/chpasswd.stdin"
EOF
# runuser: logged, then the command run, without the user switch.
cat >"$work/bin/runuser" <<'EOF'
#!/bin/bash
printf 'runuser %s\n' "$*" >>"$STUB_DIR/calls.log"
while (($# > 0)) && [[ $1 != -- ]]; do shift; done
shift
exec "$@"
EOF
# make: install-user's call logged; STUB_MAKE_FAIL fails it.
cat >"$work/bin/make" <<'EOF'
#!/bin/bash
printf 'make %s\n' "$*" >>"$STUB_DIR/calls.log"
[[ -z ${STUB_MAKE_FAIL:-} ]]
EOF
# git: the wallpaper fetch, logged; the checkout leaves a file.
cat >"$work/bin/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >>"$STUB_DIR/calls.log"
[[ " $* " != *" checkout "* ]] || : >"$2/wallpaper.png"
mkdir -p "$2/.git"
exit 0
EOF
# The script restarting itself: logged, and the run ends there.
printf '#!/bin/sh\necho restarted >>"$STUB_DIR/calls.log"\n' >"$work/bin/lyona-firstboot-self"
chmod +x "$work/bin/"*
# gum, as the install wizard's tests have it: each interactive call takes the
# next line of answers, STATUS<TAB>TEXT; none left fails with 99.
cat >"$work/bin/gum" <<'EOF'
#!/bin/bash
case $1 in
choose | filter | input | confirm)
	printf 'gum %s\n' "$*" >>"$STUB_DIR/gum.log"
	[[ -t 0 ]] || cat >/dev/null
	line=$(head -n 1 "$STUB_DIR/answers" 2>/dev/null) || line=
	[[ -n $line ]] || exit 99
	sed -i 1d "$STUB_DIR/answers"
	status=${line%%$'\t'*}
	text=${line#*$'\t'}
	[[ -z $text ]] || printf '%s\n' "$text"
	exit "$status"
	;;
style) printf '%s\n' "${@: -1}" ;;
*) exit 0 ;;
esac
EOF
chmod +x "$work/bin/gum"

# The image's source: install.sh's wallpaper pins, the mybash script, the
# wizard's files, and the release stamp's commit.
src=$work/src
mkdir -p "$src/scripts" "$src/archiso/airootfs/root"
cp "$wizard_dir"/lyona-{install,ui,nvidia,wifi}.sh "$src/archiso/airootfs/root/"
grep -E '^WALLPAPERS_(URL|REF)=' "$repo/install.sh" >"$src/install.sh"
printf '#!/bin/sh\necho mybash >>"$STUB_DIR/calls.log"\n' >"$src/scripts/install-mybash"
printf '#!/bin/sh\necho "configure-build $*" >>"$STUB_DIR/calls.log"\n' >"$src/scripts/configure-build.sh"
chmod +x "$src/scripts/install-mybash" "$src/scripts/configure-build.sh"
wallpapers_url=$(awk -F'"' '$1 == "WALLPAPERS_URL=" { print $2 }' "$repo/install.sh")
wallpapers_ref=$(awk -F'"' '$1 == "WALLPAPERS_REF=" { print $2 }' "$repo/install.sh")
[[ -n $wallpapers_url && -n $wallpapers_ref ]] || fail "install.sh's wallpaper pins were not found."

# A fresh first boot's state: the private root, /sys with a 32 GiB card and a
# root partition of 6 GiB, and the answers.
reset_case() {
	rm -rf -- "${work:?}/root" "${work:?}/home" "${work:?}/sys" "${work:?}/users" "$work/calls.log" "$work/gum.log" \
		"$work/chpasswd.stdin" "$work/log"
	mkdir -p "$work/root/etc" "$work/root/var/lib" "$work/home" "$work/sys/mmcblk0p2" "$work/sys/mmcblk0"
	printf 'uninitialized\n' >"$work/root/etc/machine-id"
	printf 'LYONA_ISO_COMMIT=abc1234\n' >"$work/root/etc/lyona-iso-release"
	printf '2\n' >"$work/sys/mmcblk0p2/partition"
	printf '%s\n' 1056768 >"$work/sys/mmcblk0p2/start"
	printf '%s\n' 12582912 >"$work/sys/mmcblk0p2/size"
	printf '%s\n' 67108864 >"$work/sys/mmcblk0/size"
	: >"$work/calls.log"
}
answers() { printf '%s\n' "$@" >"$work/answers"; }
# The answers in the order the questions come: keymap, username, password
# twice, hostname, no online lookup, the timezone, then "Set up".
standard_answers() {
	answers $'0\tGerman (de)' $'0\tpi' $'0\tsecret-pass-42' $'0\tsecret-pass-42' \
		$'0\tlyona-pi' $'1\t' $'0\tEurope/Berlin' $'0\t'
}
# run [VAR=VALUE...]: the first boot, as main runs it, with the unit's TERM.
run() {
	env PATH="$work/bin:$PATH" STUB_DIR="$work" TERM=linux "$@" \
		LYONA_SRC="$src" LYONA_FIRSTBOOT_ROOT="$work/root" LYONA_SYS_BLOCK="$work/sys" \
		LYONA_FIRSTBOOT_SELF="$work/bin/lyona-firstboot-self" LYONA_FIRSTBOOT_WARNING_SECONDS=0 \
		LYONA_LOGO_PATH=/nonexistent LYONA_CONSOLE_THEME=/nonexistent LOG_FILE="$work/log" \
		LYONA_ZONEINFO=/usr/share/zoneinfo \
		bash "$firstboot" >"$work/out.log" 2>&1 </dev/null
}
called() { grep -Fqx -- "$1" "$work/calls.log" || fail "not called: $1"$'\n'"$(cat "$work/calls.log")"; }
not_called() { ! grep -Fq -- "$1" "$work/calls.log" || fail "called: $1"$'\n'"$(cat "$work/calls.log")"; }

[[ -f /usr/share/zoneinfo/zone.tab && -f /usr/share/zoneinfo/Europe/Berlin ]] ||
	fail "this test needs the host's tzdata (/usr/share/zoneinfo)."

# --- A first boot -------------------------------------------------------------
reset_case
standard_answers
run || fail "the first boot failed: $(cat "$work/out.log")"$'\n'"$(cat "$work/log" 2>/dev/null)"
# The machine's own state.
called 'sfdisk --no-reread --no-tell-kernel -N 2 /dev/mmcblk0'
called 'partx -u -n 2 /dev/mmcblk0'
called 'resize2fs /dev/mmcblk0p2'
called 'pacman-key --init'
called 'pacman-key --populate archlinuxarm'
called 'ssh-keygen -A'
called 'systemd-machine-id-setup '
# The answers.
called 'localectl set-keymap de'
called 'hostnamectl set-hostname lyona-pi'
called 'timedatectl set-timezone Europe/Berlin'
called 'timedatectl set-ntp true'
grep -Fqx 'options cfg80211 ieee80211_regdom=DE' "$work/root/etc/modprobe.d/lyona-regdom.conf" ||
	fail "the Wi-Fi country is not DE."
# The postinstall writes the same line (set_wifi_country).
grep -Fq "options cfg80211 ieee80211_regdom=%s" "$wizard_dir/lyona-postinstall.sh" ||
	fail "the postinstall's Wi-Fi country line changed; keep rpi/lyona-firstboot.sh's the same."
# The user, an administrator, with the password on stdin only.
called 'useradd -m -G wheel -s /bin/bash pi'
[[ $(<"$work/chpasswd.stdin") == 'pi:secret-pass-42' ]] || fail "chpasswd did not get the password."
if grep -rFq 'secret-pass-42' "$work/calls.log" "$work/log" "$work/gum.log"; then
	fail "the password is in a command's arguments or the log."
fi
rule=$work/root/etc/sudoers.d/10-lyona-wheel
grep -Fqx '%wheel ALL=(ALL:ALL) ALL' "$rule" || fail "no %wheel sudo rule."
[[ $(stat -c %a "$rule") == 440 ]] || fail "the sudo rule is not mode 440."
grep -Eq '^visudo -cf .*10-lyona-wheel\.lyona-tmp$' "$work/calls.log" || fail "the sudo rule was not checked with visudo."
# lyona's per-user half, as the user, from the user's own copy of the source.
home=$work/home/pi
called 'mybash'
called 'xdg-user-dirs-update '
[[ -f $home/Pictures/backgrounds/wallpaper.png && ! -e $home/Pictures/backgrounds/.git ]] ||
	fail "the wallpapers were not put in ~/Pictures/backgrounds without their repository."
grep -Eq "^git -C $home/Pictures/\.wallpapers\.[^ ]+ fetch --quiet --depth 1 $wallpapers_url $wallpapers_ref\$" \
	"$work/calls.log" || fail "the wallpapers were not fetched from install.sh's pinned repository and commit."
# Built first, as install.sh does: config.h from the defaults, make clean, make.
called 'configure-build --non-interactive'
called 'make clean'
called 'make '
[[ $(grep -n '^configure-build ' "$work/calls.log" | cut -d: -f1) -lt $(grep -n '^make -C .* install-user ' "$work/calls.log" | cut -d: -f1) ]] ||
	fail "lyona was not built before make install-user."
called "make -C $home/.local/src/lyona install-user USER_HOME=$home OWNER=pi XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share XDG_STATE_HOME=$home/.local/state LYONA_SOURCE=iso LYONA_COMMIT=abc1234"
grep -Eq "^runuser -u pi -- env -u DBUS_SESSION_BUS_ADDRESS HOME=$home USER=pi LOGNAME=pi make " "$work/calls.log" ||
	fail "make install-user did not run as the user."
[[ -x $home/.local/src/lyona/scripts/install-mybash ]] || fail "the user has no copy of the source."
[[ -e $home/.local/state/lyona/first-login-keys ]] || fail "no first-login-keys marker."
# Done, and disabled.
[[ -e $work/root/var/lib/lyona/firstboot-done ]] || fail "the first boot is not marked done."
[[ ! -e $work/root/var/lib/lyona/firstboot-user ]] || fail "the pending-user record is left."
called 'systemctl disable lyona-firstboot.service'
not_called 'userdel'

# --- Done already: nothing again ------------------------------------------------
: >"$work/calls.log"
answers
run || fail "a second start failed: $(cat "$work/out.log")"
grep -Fq 'already done' "$work/out.log" || fail "a second start did not say it was done."
not_called 'useradd'
not_called 'pacman-key'
called 'systemctl disable lyona-firstboot.service'

# --- The root already fills the card ---------------------------------------------
reset_case
printf '%s\n' $((67108864 - 1056768)) >"$work/sys/mmcblk0p2/size"
standard_answers
run || fail "the first boot failed on a full card: $(cat "$work/out.log")"
not_called 'sfdisk'
not_called 'resize2fs'

# --- An interrupted run: its user is removed, then the questions again ----------
reset_case
mkdir -p "$work/root/var/lib/lyona"
printf 'pi\n' >"$work/root/var/lib/lyona/firstboot-user"
printf 'pi\n' >"$work/users"
standard_answers
run || fail "the first boot after an interrupted one failed: $(cat "$work/out.log")"
called 'userdel -r pi'
[[ $(grep -n '^userdel -r pi$' "$work/calls.log" | cut -d: -f1) -lt $(grep -n '^useradd ' "$work/calls.log" | cut -d: -f1) ]] ||
	fail "the half-made user was not removed before the new one was created."
[[ -e $work/root/var/lib/lyona/firstboot-done ]] || fail "the first boot after an interrupted one is not done."

# --- A cancelled question starts them again ---------------------------------------
reset_case
answers $'1\t'
run || :
called 'restarted'
not_called 'useradd'
[[ ! -e $work/root/var/lib/lyona/firstboot-done ]] || fail "a cancelled first boot is marked done."

# --- "Change the answers" at the summary starts them again --------------------------
reset_case
answers $'0\tGerman (de)' $'0\tpi' $'0\tsecret-pass-42' $'0\tsecret-pass-42' \
	$'0\tlyona-pi' $'1\t' $'0\tEurope/Berlin' $'1\t'
run || :
called 'restarted'
not_called 'useradd'

# --- A failed step: power off, not done, and the user left for the next start ------
reset_case
standard_answers
printf '%s\n' $'0\tPower off' >>"$work/answers"
run STUB_MAKE_FAIL=1 || :
called 'systemctl poweroff'
[[ ! -e $work/root/var/lib/lyona/firstboot-done ]] || fail "a failed first boot is marked done."
[[ $(<"$work/root/var/lib/lyona/firstboot-user") == pi ]] ||
	fail "a failed first boot does not record its user for the next start to remove."
not_called 'systemctl disable lyona-firstboot.service'
# "Start again" instead.
reset_case
standard_answers
printf '%s\n' $'0\tStart again' >>"$work/answers"
run STUB_MAKE_FAIL=1 || :
called 'restarted'
not_called 'systemctl poweroff'

# --- Wi-Fi through NetworkManager ---------------------------------------------------
# The scan's terse output, with an escaped colon and backslash in the SSIDs.
cat >"$work/bin/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli %s\n' "$*" >>"$STUB_DIR/calls.log"
case "$*" in
"-t -e yes -f SSID,SIGNAL,SECURITY device wifi list --rescan yes")
	printf '%s\n' 'Home\:Net:80:WPA2' 'Cafe:40:' 'Back\\slash:55:WPA1 WPA2' 'Corp:70:WPA2 802.1X' ':30:WPA2'
	;;
"--wait 30 connection up"*) [[ -z ${STUB_NM_FAIL:-} ]] ;;
esac
EOF
chmod +x "$work/bin/nmcli"
wifi() { # CODE
	env PATH="$work/bin:$PATH" STUB_DIR="$work" TERM=linux LYONA_FIRSTBOOT_LIB=1 \
		LYONA_SRC="$src" LYONA_FIRSTBOOT_ROOT="$work/root" LYONA_LOGO_PATH=/nonexistent \
		LOG_FILE="$work/log" bash -c '. "$1"; eval "$2"' bash "$firstboot" "$1" 2>&1 </dev/null
}
reset_case
networks=$(wifi nm_wifi_networks)
[[ $networks == $'Home:Net\t80\tWPA2\nCafe\t40\t\nBack\\slash\t55\tWPA1 WPA2\nCorp\t70\tWPA2 802.1X' ]] ||
	fail "the scan was not parsed: $networks"
[[ $(wifi 'printf "%s-" "$(nm_security_type "")" "$(nm_security_type WPA2)" "$(nm_security_type "WPA2 802.1X")" "$(nm_security_type WEP)"') == open-psk-8021x-wep- ]] ||
	fail "nmcli's security column is not mapped to the wizard's types."
# A WPA network from the list, its passphrase typed once.
answers $'0\tHome:Net  80%  WPA' $'0\twifi-pass-123'
wifi 'connect_wifi' >"$work/out.log" || fail "connecting to Wi-Fi failed: $(cat "$work/out.log")"
profile=$work/root/etc/NetworkManager/system-connections/lyona-wifi.nmconnection
[[ -f $profile && $(stat -c %a "$profile") == 600 ]] || fail "the Wi-Fi profile is missing or not mode 600."
grep -Fqx 'ssid=Home:Net' "$profile" && grep -Fqx 'psk=wifi-pass-123' "$profile" ||
	fail "the Wi-Fi profile does not hold the network and its passphrase."
called "nmcli connection load $profile"
grep -Eq '^nmcli --wait 30 connection up uuid [0-9a-f-]{36}$' "$work/calls.log" || fail "the profile was not brought up."
! grep -Fq 'wifi-pass-123' "$work/calls.log" || fail "the Wi-Fi passphrase is in nmcli's arguments."
# A failed connection removes the profile and says so, then Back.
reset_case
answers $'0\tHome:Net  80%  WPA' $'0\twrong-pass-123' $'0\tBack'
out=$(STUB_NM_FAIL=1 wifi 'connect_wifi' || echo "status=$?")
[[ $out == *'status=1'* ]] || fail "a failed Wi-Fi connection did not fail: $out"
[[ ! -e $profile ]] || fail "a failed Wi-Fi connection left its profile."
grep -Fq 'Could not connect to Home:Net' "$work/gum.log" || fail "a failed Wi-Fi connection was not explained."
# An enterprise network is explained, not tried.
reset_case
answers $'0\tCorp  70%  enterprise (not supported)' $'0\tBack'
wifi 'connect_wifi || :' >/dev/null
not_called 'connection load'
grep -Fq 'uses enterprise (not supported) security' "$work/gum.log" || fail "an enterprise network was not explained."

printf 'Raspberry Pi first boot: PASS\n'
