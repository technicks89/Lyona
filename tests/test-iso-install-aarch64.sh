#!/usr/bin/env bash
# The CODE strings below are expanded by the inner shell, not here.
# shellcheck disable=SC2016
set -euo pipefail

# The image installer on aarch64 (ARM2-03), the experimental Arch Linux ARM
# medium. One wizard and one postinstall for both architectures; on aarch64:
# - no CachyOS (x86_64 only): neither the wizard nor the postinstall runs the
#   helper, or warns that it failed;
# - no NVIDIA question (its driver profiles are x86_64 only);
# - archinstall's configuration has no [multilib], keeps kernels ["linux"],
#   which Arch Linux ARM's linux-aarch64 provides, and installs
#   archlinuxarm-keyring, so the new system trusts Arch Linux ARM's packages;
# - the new system gets the hook that keeps /boot/vmlinuz-linux a copy of
#   linux-aarch64's /boot/Image, which GRUB pairs with initramfs-linux.img;
# - a firmware boot entry for GRUB's removable path, replacing an earlier one;
# - the kernel console on the display (console=tty0), not only the firmware's
#   serial port, and Plymouth drawing despite that port, through a GRUB
#   drop-in;
# - Arch Linux ARM's mirrors (ARM2-04): the question names them, the country
#   list is the countries Arch Linux ARM's mirrorlist has, and the chosen
#   mirrorlist is the country's mirrors, then the geo-balanced one; reflector is
#   never run or mentioned;
# - Arch Linux ARM's keys in the new system, checked before its first download,
#   and added once more when missing.
# On both architectures (ARM2-04): the wizard waits for the medium's keyring
# (pacman-init.service) and checks it before anything is downloaded, and the
# first mirror's name must resolve before the first download, in the wizard
# (Retry, Continue anyway, Cancel) and in the postinstall (a failed step).
# x86_64 keeps the rest as before.
#
# The wizard is loaded as a library, the postinstall's functions are taken from
# it, and every command that would touch the machine is a stub.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

root=$repo/archiso/airootfs/root
wizard=$root/lyona-install.sh
postinstall=$root/lyona-postinstall.sh

# gum: each interactive call takes the next line of $STUB_DIR/answers,
# STATUS<TAB>TEXT, and fails with 99 when there is none; a list piped to it is
# kept in choices.log.
cat >"$work/bin/gum" <<'EOF'
#!/bin/bash
case $1 in
choose | filter | input | confirm)
	printf 'gum %s\n' "$*" >>"$STUB_DIR/gum.log"
	[[ -t 0 ]] || cat >"$STUB_DIR/choices.log"
	line=$(head -n 1 "$STUB_DIR/answers" 2>/dev/null) || line=
	[[ -n $line ]] || exit 99
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
# An NVIDIA card: on x86_64 the wizard would ask about its driver.
# lspci's two forms: the description, and the IDs nvidia_gpu_branch reads.
cat >"$work/bin/lspci" <<'EOF'
#!/bin/sh
case "$*" in
"-n -mm -d 10de::0300") printf '%s\n' '01:00.0 "0300" "10de" "2786" -ra1 "10de" "16fa"' ;;
-n*) ;;
*) printf '%s\n' '01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [GeForce RTX 4070] [10de:2786] (rev a1)' ;;
esac
EOF
cat >"$work/bin/blockdev" <<'EOF'
#!/bin/sh
echo 34359738368
EOF
# The CachyOS helper must not run on aarch64.
cat >"$work/bin/lyona-cachyos" <<'EOF'
#!/bin/sh
printf 'lyona-cachyos %s\n' "$*" >>"$STUB_DIR/calls.log"
EOF
# Arch Linux ARM's keyring checks (ARM2-04): pacman-key has a key when its
# fingerprint is in keys, and --populate NAME adds NAME's with
# STUB_POPULATE_WORKS=1. systemctl reports pacman-init.service as
# STUB_INIT_STATES, one state per call, the last one then on.
cat >"$work/bin/pacman-key" <<'EOF'
#!/bin/bash
printf 'pacman-key %s\n' "$*" >>"$STUB_DIR/calls.log"
case $1 in
--list-keys) grep -Fxq -- "$2" "$STUB_DIR/keys" 2>/dev/null ;;
--populate)
	[[ ${STUB_POPULATE_WORKS:-0} == 1 ]] || exit 1
	shift
	for name; do awk -F: '!/^#/ && NF { print $1 }' "$STUB_KEYRINGS/$name-trusted" >>"$STUB_DIR/keys"; done
	;;
esac
EOF
cat >"$work/bin/systemctl" <<'EOF'
#!/bin/bash
read -r -a states <<<"${STUB_INIT_STATES:-active}"
n=$(cat "$STUB_DIR/systemctl.count" 2>/dev/null) || n=0
case $* in
*ActiveState*)
	((n < ${#states[@]})) || n=$((${#states[@]} - 1))
	printf '%s\n' "${states[n]}"
	echo $((n + 1)) >"$STUB_DIR/systemctl.count"
	;;
*Job*) ;;
esac
EOF
# getent ahosts HOST resolves the hosts listed in resolvable.
cat >"$work/bin/getent" <<'EOF'
#!/bin/sh
printf 'getent %s\n' "$*" >>"$STUB_DIR/calls.log"
[ "$1" = ahosts ] && grep -Fxq -- "$2" "$STUB_DIR/resolvable" 2>/dev/null
EOF
# reflector must never run on aarch64.
cat >"$work/bin/reflector" <<'EOF'
#!/bin/sh
printf 'reflector %s\n' "$*" >>"$STUB_DIR/calls.log"
exit 1
EOF
for cmd in clear tput sleep; do
	printf '#!/bin/sh\nexit 0\n' >"$work/bin/$cmd"
done
chmod +x "$work/bin/"*

# The medium's zoneinfo tables, mirrorlist and keyrings, as fixtures. Arch Linux
# ARM's mirrorlist as pacman-mirrorlist ships it: the geo-balanced server
# enabled, the countries' commented out; Atlantis is not in iso3166.tab.
zoneinfo=$work/zoneinfo
mkdir -p "$zoneinfo" "$work/keyrings"
printf '# comment\nDE\t+5230+01322\tEurope/Berlin\nJP\t+353916+1394441\tAsia/Tokyo\n' >"$zoneinfo/zone.tab"
: >"$zoneinfo/zone1970.tab"
printf '# comment\nDE\tGermany\nJP\tJapan\nUS\tUnited States\n' >"$zoneinfo/iso3166.tab"
cat >"$work/alarm-mirrorlist" <<'EOF'
#
# Arch Linux ARM repository mirrorlist
#

## Geo-IP based mirror selection and load balancing
Server = http://mirror.archlinuxarm.org/$arch/$repo

### Mirrors by country

### Atlantis
# Server = http://at.mirror.example/$arch/$repo

### Germany
## Aachen
# Server = http://de3.mirror.archlinuxarm.org/$arch/$repo
## Berlin
# Server = http://de.mirror.archlinuxarm.org/$arch/$repo

### United States
## California
# Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
EOF
printf 'AAAA1111:4:\n' >"$work/keyrings/archlinux-trusted"
printf '# comment\nBBBB2222:4:\nBBBB3333:4:\n' >"$work/keyrings/archlinuxarm-trusted"
printf 'search lan\nnameserver 192.0.2.53\nnameserver 192.0.2.54\n' >"$work/resolv.conf"
printf 'nameserver 10.0.2.3\n' >"$work/resolved.conf"

# wizard ARCH CODE: CODE with the wizard loaded as a library on ARCH. The
# answers file is the caller's, used up by gum.
wizard() {
	: >"$work/gum.log"
	: >"$work/calls.log"
	: >"$work/choices.log"
	rm -f "$work/systemctl.count"
	env PATH="$work/bin:$PATH" STUB_DIR="$work" LYONA_INSTALL_LIB=1 ARCH="$1" \
		LYONA_UI_LIB="$root/lyona-ui.sh" LYONA_NVIDIA_LIB="$root/lyona-nvidia.sh" \
		LYONA_WIFI_LIB="$root/lyona-wifi.sh" LYONA_LOGO_PATH=/nonexistent \
		LOG_FILE="$work/install.log" LYONA_ZONEINFO="$zoneinfo" \
		LYONA_MIRRORLIST="$work/mirrorlist" LYONA_ALARM_MIRRORLIST="$work/mirrorlist.archlinuxarm" \
		LYONA_MIRRORS_MARKER="$work/marker" LYONA_KEYRINGS="$work/keyrings" STUB_KEYRINGS="$work/keyrings" \
		LYONA_RESOLV_CONF="$work/resolv.conf" LYONA_RESOLVED_CONF="$work/resolved.conf" \
		bash -c '. "$1"; CACHYOS_HELPER=$2; eval "$3"' bash "$wizard" "$work/bin/lyona-cachyos" "$2" \
		>"$work/out.log" 2>&1 </dev/null
}
# answers LINE...: the gum answers, in order.
answers() {
	printf '%s\n' "$@" >"$work/answers"
}
# servers: the hosts the live mirrorlist downloads from, in order.
servers() {
	sed -n 's|^Server = http://\([^/]*\)/.*|\1|p' "$work/mirrorlist" | tr '\n' ' '
}
: >"$work/answers"
cp "$work/alarm-mirrorlist" "$work/mirrorlist"

# --- The wizard -------------------------------------------------------------

wizard aarch64 'setup_cachyos_repositories; printf "PACKAGES=[%s]\n" "$CACHYOS_PACKAGES"' ||
	fail "the CachyOS step failed on aarch64: $(cat "$work/out.log")"
grep -Fxq 'PACKAGES=[]' "$work/out.log" || fail "aarch64 got CachyOS packages: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "the CachyOS helper ran on aarch64: $(cat "$work/calls.log")"
grep -Fq 'CachyOS is x86_64 only' "$work/out.log" || fail 'skipping CachyOS on aarch64 was not said'
! grep -Fq 'setup failed' "$work/out.log" || fail 'skipping CachyOS on aarch64 was reported as a failure'
wizard x86_64 'setup_cachyos_repositories; printf "PACKAGES=[%s]\n" "$CACHYOS_PACKAGES"' ||
	fail "the CachyOS step failed on x86_64: $(cat "$work/out.log")"
grep -Fxq 'lyona-cachyos add-repos --no-upgrade --baseline' "$work/calls.log" ||
	fail 'the CachyOS helper no longer runs on x86_64'

wizard aarch64 'ask_nvidia; printf "OPT_IN=%s DETECTED=%s\n" "$NVIDIA_OPT_IN" "$NVIDIA_DETECTED"' ||
	fail "the NVIDIA step failed on aarch64: $(cat "$work/out.log")"
grep -Fxq 'OPT_IN=0 DETECTED=0' "$work/out.log" || fail "aarch64 took up the NVIDIA card: $(cat "$work/out.log")"
[[ ! -s $work/gum.log ]] || fail "the NVIDIA question was asked on aarch64: $(cat "$work/gum.log")"
# On x86_64 the same card is asked about (the stubbed answer cancels).
wizard x86_64 'ask_nvidia' || true
grep -Fq 'NVIDIA GPU detected' "$work/gum.log" || fail 'the NVIDIA question is no longer asked on x86_64'

configure='detect_firmware() { :; }; FIRMWARE=uefi DISK=/dev/vda FILESYSTEM=ext4 ENCRYPT=0
	HOSTNAME=host KEYMAP=us TIMEZONE=UTC USERNAME=user PASSWORD=pass
	generate_configs; cp "$CONFIG_JSON" "$STUB_DIR/config.json"'
wizard aarch64 "$configure" || fail "the configuration failed on aarch64: $(cat "$work/out.log")"
python3 -c 'import json, sys
c = json.load(open(sys.argv[1]))
repos, kernels = c["mirror_config"]["optional_repositories"], c["kernels"]
if repos != []:
    sys.exit("aarch64 optional repositories: %r" % repos)
if kernels != ["linux"]:
    sys.exit("aarch64 kernels: %r" % kernels)
if c["packages"] != ["archlinuxarm-keyring"]:
    sys.exit("aarch64 packages: %r" % c["packages"])' \
	"$work/config.json" || fail 'the aarch64 archinstall configuration is wrong'
wizard x86_64 "$configure" || fail "the configuration failed on x86_64: $(cat "$work/out.log")"
python3 -c 'import json, sys
c = json.load(open(sys.argv[1]))
repos = c["mirror_config"]["optional_repositories"]
if repos != ["multilib"]:
    sys.exit("x86_64 optional repositories: %r" % repos)
if "archlinuxarm-keyring" in c["packages"]:
    sys.exit("x86_64 packages: %r" % c["packages"])' \
	"$work/config.json" || fail 'the x86_64 archinstall configuration lost [multilib]'

# --- Arch Linux ARM's mirrors (ARM2-04) ------------------------------------

wizard aarch64 'alarm_mirrors' || fail "listing Arch Linux ARM's mirrors failed: $(cat "$work/out.log")"
expected=$(printf '%s\t%s\t%s\n' DE Germany 'http://de3.mirror.archlinuxarm.org/$arch/$repo' \
	DE Germany 'http://de.mirror.archlinuxarm.org/$arch/$repo' \
	US 'United States' 'http://ca.us.mirror.archlinuxarm.org/$arch/$repo')
[[ $(cat "$work/out.log") == "$expected" ]] || fail "Arch Linux ARM's mirrors were read as: $(cat "$work/out.log")"
wizard aarch64 'alarm_geo_server'
[[ $(cat "$work/out.log") == 'http://mirror.archlinuxarm.org/$arch/$repo' ]] ||
	fail "the geo-balanced mirror was read as: $(cat "$work/out.log")"

# The timezone's country, when Arch Linux ARM has mirrors there.
answers $'0\t'
wizard aarch64 'TIMEZONE=Europe/Berlin; ask_mirrors; printf "MIRRORS=%s\n" "$MIRROR_COUNTRY"; mirror_summary' ||
	fail "the aarch64 mirror question failed: $(cat "$work/out.log")"
grep -Fq "Download packages from Arch Linux ARM's mirrors in Germany?" "$work/gum.log" ||
	fail "the aarch64 mirror question was: $(cat "$work/gum.log")"
grep -Fxq 'MIRRORS=DE' "$work/out.log" || fail "the timezone's country was not taken: $(cat "$work/out.log")"
grep -Fxq "Germany (DE), Arch Linux ARM's mirrors there" "$work/out.log" ||
	fail "the aarch64 summary says: $(cat "$work/out.log")"
grep -Fq 'not ranked by speed' "$work/out.log" || fail 'the aarch64 mirror question does not say what it does'
# A country without them: the geo-balanced mirror.
answers $'0\t'
wizard aarch64 'TIMEZONE=Asia/Tokyo; ask_mirrors; printf "MIRRORS=[%s]\n" "$MIRROR_COUNTRY"; mirror_summary'
grep -Fq "Download packages from Arch Linux ARM's nearest mirror, mirror.archlinuxarm.org?" "$work/gum.log" ||
	fail "with no mirrors in the country the question was: $(cat "$work/gum.log")"
grep -Fxq 'MIRRORS=[]' "$work/out.log" || fail "a country without mirrors was taken: $(cat "$work/out.log")"
grep -Fxq "Arch Linux ARM's nearest, mirror.archlinuxarm.org" "$work/out.log" ||
	fail "the aarch64 summary says: $(cat "$work/out.log")"
# Choose another: Esc in the list goes back to the question; the list is the
# nearest mirror and Arch Linux ARM's countries.
answers $'1\t' $'1\t' $'1\t' $'0\tUnited States (US)'
wizard aarch64 'TIMEZONE=Europe/Berlin; ask_mirrors; printf "MIRRORS=%s\n" "$MIRROR_COUNTRY"' ||
	fail "Esc in the aarch64 country list ended the wizard: $(cat "$work/out.log")"
grep -Fxq 'MIRRORS=US' "$work/out.log" || fail "the chosen country was not taken: $(cat "$work/out.log")"
[[ $(cat "$work/choices.log") == $'Nearest (mirror.archlinuxarm.org)\nGermany (DE)\nUnited States (US)' ]] ||
	fail "the aarch64 country list is: $(cat "$work/choices.log")"
answers $'1\t' $'0\tNearest (mirror.archlinuxarm.org)'
wizard aarch64 'TIMEZONE=Europe/Berlin; ask_mirrors; printf "MIRRORS=[%s]\n" "$MIRROR_COUNTRY"'
grep -Fxq 'MIRRORS=[]' "$work/out.log" || fail "the nearest mirror was not taken: $(cat "$work/out.log")"
# Esc on the question cancels, as on x86_64.
answers $'130\t'
if wizard aarch64 'TIMEZONE=Europe/Berlin; ask_mirrors'; then
	fail 'Esc on the aarch64 mirror question did not cancel'
fi
: >"$work/answers"

# The chosen mirrorlist: the country's, then the geo-balanced one; no reflector.
wizard aarch64 'select_alarm_mirrors DE' || fail "choosing the mirrors failed: $(cat "$work/out.log")"
[[ $(servers) == 'de3.mirror.archlinuxarm.org de.mirror.archlinuxarm.org mirror.archlinuxarm.org ' ]] ||
	fail "the mirrors chosen for DE are: $(servers)"
[[ -e $work/marker ]] || fail 'the chosen mirrorlist is not marked for the postinstall'
grep -Fxq 'Using 2 Arch Linux ARM mirrors in DE, then mirror.archlinuxarm.org.' "$work/out.log" ||
	fail "choosing the mirrors said: $(cat "$work/out.log")"
! grep -q '^reflector' "$work/calls.log" || fail 'reflector ran on aarch64'
! grep -qi 'reflector' "$work/out.log" || fail "the aarch64 mirror step mentions reflector: $(cat "$work/out.log")"
# Again (a Retry), from the list the medium booted with, not the chosen one.
wizard aarch64 'select_alarm_mirrors US'
[[ $(servers) == 'ca.us.mirror.archlinuxarm.org mirror.archlinuxarm.org ' ]] ||
	fail "after a first choice, the mirrors chosen for US are: $(servers)"
wizard aarch64 'select_alarm_mirrors'
[[ $(servers) == 'mirror.archlinuxarm.org ' ]] || fail "the nearest mirror alone is: $(servers)"
wizard aarch64 'select_alarm_mirrors JP'
[[ $(servers) == 'mirror.archlinuxarm.org ' ]] || fail "a country without mirrors gave: $(servers)"
grep -Fq 'Arch Linux ARM has no mirror in JP' "$work/out.log" || fail "a country without mirrors said: $(cat "$work/out.log")"
cmp -s "$work/alarm-mirrorlist" "$work/mirrorlist.archlinuxarm" || fail "Arch Linux ARM's mirrorlist was not kept as it was"
# The wizard runs it on aarch64 only, rank_mirrors elsewhere.
grep -Pzq '\n\tif \[\[ \$MACHINE_ARCH == aarch64 \]\]; then\n\t\trun_logged "Choosing Arch Linux ARM'"'"'s package mirrors\.\.\." select_alarm_mirrors "\$MIRROR_COUNTRY"\n\telse\n\t\trun_logged "Choosing the fastest package mirrors\.\.\." rank_mirrors "\$MIRROR_COUNTRY"\n\tfi\n' \
	"$wizard" || fail 'the wizard does not choose the mirrors by architecture'

# --- The medium's keyring and the mirror's name (both architectures) ---------

: >"$work/keys"
printf 'AAAA1111\nBBBB2222\n' >"$work/keys"
wizard aarch64 'wait_for_keyring' || fail "a ready keyring failed: $(cat "$work/out.log")"
! grep -q -- '--populate' "$work/calls.log" || fail 'a ready keyring was populated'
# Still being set up: the wizard waits, and says so.
STUB_INIT_STATES='activating activating active' wizard aarch64 'wait_for_keyring' ||
	fail "waiting for the keyring failed: $(cat "$work/out.log")"
grep -Fq "Waiting for pacman's keyring to be set up..." "$work/out.log" || fail 'waiting for the keyring was not said'
[[ $(cat "$work/systemctl.count") == 3 ]] || fail "pacman-init.service was asked $(cat "$work/systemctl.count") times"
# Arch Linux ARM's keys missing: populated once more.
printf 'AAAA1111\n' >"$work/keys"
STUB_POPULATE_WORKS=1 STUB_INIT_STATES=failed wizard aarch64 'wait_for_keyring' ||
	fail "populating a missing keyring failed: $(cat "$work/out.log")"
grep -Fxq 'pacman-key --populate archlinuxarm' "$work/calls.log" || fail "the missing keyring was populated with: $(cat "$work/calls.log")"
# And still missing: the wizard stops, before any download.
printf 'AAAA1111\n' >"$work/keys"
if STUB_INIT_STATES=failed wizard aarch64 'wait_for_keyring; echo DOWNLOADING'; then
	fail 'a keyring without its keys passed'
fi
grep -Fq "pacman's keyring has no archlinuxarm keys (pacman-init.service failed)" "$work/out.log" ||
	fail "a keyring without its keys said: $(cat "$work/out.log")"
! grep -Fxq DOWNLOADING "$work/out.log" || fail 'the wizard went on without the keyring'
# x86_64's medium has the archlinux keyring only.
mv "$work/keyrings/archlinuxarm-trusted" "$work/archlinuxarm-trusted"
: >"$work/keys"
if wizard x86_64 'wait_for_keyring'; then fail 'an x86_64 keyring without its keys passed'; fi
grep -Fq "pacman's keyring has no archlinux keys" "$work/out.log" || fail "the x86_64 keyring said: $(cat "$work/out.log")"
mv "$work/archlinuxarm-trusted" "$work/keyrings/archlinuxarm-trusted"

# The mirror's name: resolving, nothing is asked.
printf 'de3.mirror.archlinuxarm.org\n' >"$work/resolvable"
wizard aarch64 'select_alarm_mirrors DE; require_mirror_dns; printf "SKIP=%s\n" "$LYONA_MIRROR_DNS_SKIP"' ||
	fail "a resolving mirror failed: $(cat "$work/out.log")"
[[ ! -s $work/gum.log ]] || fail "a resolving mirror asked: $(cat "$work/gum.log")"
grep -Fxq 'SKIP=0' "$work/out.log" || fail 'a resolving mirror skipped the postinstall check'
# Not resolving: Retry checks again, Continue anyway goes on and tells the
# postinstall; the screen names the host and the name servers.
: >"$work/resolvable"
answers $'0\tRetry' $'0\tContinue anyway'
wizard aarch64 'select_alarm_mirrors DE; require_mirror_dns; printf "SKIP=%s\n" "$LYONA_MIRROR_DNS_SKIP"' ||
	fail "continuing without the mirror's name failed: $(cat "$work/out.log")"
[[ $(grep -c '^getent ahosts de3.mirror.archlinuxarm.org$' "$work/calls.log") == 2 ]] ||
	fail "Retry did not check again: $(cat "$work/calls.log")"
grep -Fq "The package mirror's name does not resolve: de3.mirror.archlinuxarm.org" "$work/out.log" ||
	fail "the unresolved mirror was not named: $(cat "$work/out.log")"
grep -Fq '192.0.2.53, 192.0.2.54' "$work/out.log" || fail "the name servers were not shown: $(cat "$work/out.log")"
grep -Fq 'gum choose --header What would you like to do? Retry Continue anyway Cancel the installer' "$work/gum.log" ||
	fail "the unresolved mirror offered: $(cat "$work/gum.log")"
grep -Fxq 'SKIP=1' "$work/out.log" || fail 'Continue anyway was not passed on to the postinstall'
grep -Fq 'export LYONA_WIFI_COUNTRY LYONA_MIRROR_DNS_SKIP' "$wizard" || fail 'the postinstall is not told about Continue anyway'
# Behind systemd-resolved's stub, the servers it asks are named too.
cp "$work/resolv.conf" "$work/resolv.conf.saved"
printf 'nameserver 127.0.0.53\noptions edns0\n' >"$work/resolv.conf"
wizard aarch64 'name_servers'
[[ $(cat "$work/out.log") == '127.0.0.53, systemd-resolved, which asks: 10.0.2.3' ]] ||
	fail "behind systemd-resolved the name servers were: $(cat "$work/out.log")"
mv "$work/resolv.conf.saved" "$work/resolv.conf"
# Cancel, and Esc, cancel the wizard.
for answer in $'0\tCancel the installer' $'130\t'; do
	answers "$answer"
	if wizard aarch64 'select_alarm_mirrors DE; require_mirror_dns'; then
		fail "an unresolved mirror went on after: $answer"
	fi
	grep -Fq 'Nothing on the disk was changed' "$work/out.log" || fail "cancelling at the unresolved mirror said: $(cat "$work/out.log")"
done
# x86_64 checks its own first mirror.
printf 'Server = https://de.arch.example/$repo/os/$arch\n' >"$work/mirrorlist"
printf 'de.arch.example\n' >"$work/resolvable"
wizard x86_64 'require_mirror_dns' || fail "an x86_64 resolving mirror failed: $(cat "$work/out.log")"
grep -Fxq 'getent ahosts de.arch.example' "$work/calls.log" || fail "x86_64 checked: $(cat "$work/calls.log")"
: >"$work/answers"
# Before the first download: the keyring before the mirror step, the name after
# it, both before the CachyOS step and archinstall.
order=$(grep -nE '^	+(confirm_and_proceed|wait_for_keyring|use_parallel_downloads|require_mirror_dns|setup_cachyos_repositories|run_archinstall)$' "$wizard" | cut -d: -f1 | tr '\n' ' ')
read -r confirm keyring parallel dns cachyos archinstall <<<"$order"
if [[ -z ${archinstall:-} ]] || ! ((confirm < keyring && keyring < parallel && parallel < dns && dns < cachyos && cachyos < archinstall)); then
	fail "the keyring and name checks are not between the summary and the first download: $order"
fi

# --- The postinstall --------------------------------------------------------

# The postinstall's functions, without the script around them.
for function in note_warning add_cachyos_repositories install_cachyos_kernel drop_fallback_initramfs \
	check_mirror_dns trust_alarm_keyring keep_vmlinuz_linux add_firmware_boot_entry use_display_console; do
	sed -n "/^$function() {\$/,/^}\$/p" "$postinstall"
done >"$work/postinstall-functions.sh"
for function in add_cachyos_repositories check_mirror_dns trust_alarm_keyring keep_vmlinuz_linux \
	add_firmware_boot_entry use_display_console; do
	grep -q "^$function() {\$" "$work/postinstall-functions.sh" || fail "the postinstall has no $function"
done
# post ARCH CODE: CODE with those functions on ARCH, TARGET a fake new system.
post() {
	: >"$work/calls.log"
	env PATH="$work/bin:$PATH" STUB_DIR="$work" MACHINE_ARCH="$1" TARGET="$work/target" \
		REPO_SRC="$repo" CACHYOS_HELPER=/usr/local/bin/lyona-cachyos \
		CACHYOS_MARKER="$work/cachyos-ready" CACHYOS_KERNEL=linux-cachyos \
		LYONA_WARNINGS="$work/warnings" LYONA_SYSFS="$work/sys" \
		LYONA_RESOLV_CONF="$work/resolv.conf" LYONA_RESOLVED_CONF="$work/resolved.conf" \
		bash -c '. "$1"; eval "$2"' bash "$work/postinstall-functions.sh" "$2" >"$work/out.log" 2>&1
}
# In the new system, pacman-key has a key when its fingerprint is in
# target-keys, and --populate archlinuxarm adds them with STUB_POPULATE_WORKS=1.
cat >"$work/bin/arch-chroot" <<'EOF'
#!/bin/bash
printf 'arch-chroot %s\n' "$*" >>"$STUB_DIR/calls.log"
[[ ${2:-} == pacman-key ]] || exit 0
case $3 in
--list-keys) grep -Fxq -- "$4" "$STUB_DIR/target-keys" 2>/dev/null ;;
--populate)
	[[ ${STUB_POPULATE_WORKS:-0} == 1 ]] || exit 0
	awk -F: '!/^#/ && NF { print $1 }' "$1/usr/share/pacman/keyrings/$4-trusted" >>"$STUB_DIR/target-keys"
	;;
esac
EOF
chmod +x "$work/bin/arch-chroot"
mkdir -p "$work/target/boot" "$work/target/etc/mkinitcpio.d"

post aarch64 'add_cachyos_repositories' || fail "the CachyOS step failed on aarch64: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "the postinstall ran CachyOS on aarch64: $(cat "$work/calls.log")"
[[ ! -e $work/target/usr/local/bin/lyona-cachyos ]] || fail 'the CachyOS helper was installed on aarch64'
[[ ! -s $work/warnings ]] || fail "skipping CachyOS on aarch64 left a warning: $(cat "$work/warnings")"
post aarch64 'install_cachyos_kernel' || fail "the kernel step failed on aarch64: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "the kernel step ran CachyOS on aarch64: $(cat "$work/calls.log")"
grep -Fq 'keeping the stock kernel' "$work/out.log" || fail 'keeping the stock kernel on aarch64 was not said'

# The kernel copy GRUB boots, and the hook that keeps it current.
hook=etc/pacman.d/hooks/lyona-vmlinuz-linux.hook
printf 'kernel 1\n' >"$work/target/boot/Image"
post aarch64 'keep_vmlinuz_linux' || fail "the kernel copy failed: $(cat "$work/out.log")"
cmp -s "$repo/archiso-aarch64/airootfs/$hook" "$work/target/$hook" || fail 'the new system did not get the kernel-name hook'
cmp -s "$work/target/boot/Image" "$work/target/boot/vmlinuz-linux" || fail '/boot/vmlinuz-linux is not a copy of /boot/Image'
# A stale copy is replaced; a current one is left alone.
printf 'kernel 2\n' >"$work/target/boot/Image"
post aarch64 'keep_vmlinuz_linux' || fail "replacing a stale kernel copy failed: $(cat "$work/out.log")"
grep -Fxq 'kernel 2' "$work/target/boot/vmlinuz-linux" || fail 'a stale /boot/vmlinuz-linux was kept'
post aarch64 'keep_vmlinuz_linux' || fail "a current kernel copy failed: $(cat "$work/out.log")"
! grep -Fq 'Copied' "$work/out.log" || fail 'a current /boot/vmlinuz-linux was copied again'
# Nothing to boot is a failure.
rm -f "$work/target/boot/Image" "$work/target/boot/vmlinuz-linux"
if post aarch64 'keep_vmlinuz_linux'; then
	fail 'a new system with no kernel passed'
fi
grep -Fq 'no /boot/vmlinuz-linux to boot' "$work/out.log" || fail "a missing kernel was not said: $(cat "$work/out.log")"

# The firmware boot entry.
mkdir -p "$work/target/boot/EFI/BOOT" "$work/sys/firmware/efi/efivars" "$work/sys/class/block/vda1"
: >"$work/target/boot/EFI/BOOT/BOOTAA64.EFI"
printf '1\n' >"$work/sys/class/block/vda1/partition"
cat >"$work/bin/findmnt" <<'EOF'
#!/bin/sh
[ "$*" = "-n -o SOURCE --target $TARGET/boot" ] || exit 1
echo /dev/vda1
EOF
cat >"$work/bin/lsblk" <<'EOF'
#!/bin/sh
[ "$*" = "-n -d -o PKNAME /dev/vda1" ] || exit 1
echo vda
EOF
# An earlier run's entry (Boot0003) beside the firmware's own; tabs as
# efibootmgr prints them.
cat >"$work/bin/efibootmgr" <<'EOF'
#!/bin/sh
printf 'efibootmgr %s\n' "$*" >>"$STUB_DIR/calls.log"
[ $# -eq 0 ] || exit 0
printf 'BootCurrent: 0001\nBootOrder: 0003,0001,0000\n'
printf 'Boot0000* UiApp\tFvVol(64074afe)/FvFile(462caa21)\n'
printf 'Boot0001* UEFI Misc Device\tPciRoot(0x0)/Pci(0x1,0x0)\n'
printf 'Boot0003* lyona\tHD(1,GPT,0b8e,0x800,0x100000)/\\EFI\\BOOT\\BOOTAA64.EFI\n'
printf 'Boot0004* lyona-old\tHD(1,GPT,0b8e,0x800,0x100000)/\\EFI\\BOOT\\BOOTAA64.EFI\n'
EOF
chmod +x "$work/bin/findmnt" "$work/bin/lsblk" "$work/bin/efibootmgr"
post aarch64 'add_firmware_boot_entry' || fail "the firmware boot entry failed: $(cat "$work/out.log")"
expected=$(printf '%s\n' 'efibootmgr ' 'efibootmgr -q -b 0003 -B' \
	'efibootmgr -q --create --disk /dev/vda --part 1 --label lyona --loader \EFI\BOOT\BOOTAA64.EFI')
[[ $(cat "$work/calls.log") == "$expected" ]] ||
	fail "the firmware boot entry was made with: $(cat "$work/calls.log")"
# Not booted with UEFI: nothing to add, and no failure.
rm -rf "$work/sys/firmware/efi"
post aarch64 'add_firmware_boot_entry' || fail "a non-UEFI boot failed the firmware step: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "efibootmgr ran without UEFI: $(cat "$work/calls.log")"
# No GRUB at the removable path is a failure.
mkdir -p "$work/sys/firmware/efi/efivars"
rm -f "$work/target/boot/EFI/BOOT/BOOTAA64.EFI"
if post aarch64 'add_firmware_boot_entry'; then
	fail 'a firmware boot entry was added for a missing GRUB'
fi

# The new system's first mirror's name, before its first download.
mkdir -p "$work/target/etc/pacman.d"
printf '# Chosen by lyona-install\nServer = http://de3.mirror.archlinuxarm.org/$arch/$repo\n' \
	>"$work/target/etc/pacman.d/mirrorlist"
printf 'de3.mirror.archlinuxarm.org\n' >"$work/resolvable"
post aarch64 'check_mirror_dns' || fail "a resolving mirror failed the postinstall: $(cat "$work/out.log")"
: >"$work/resolvable"
if post aarch64 'check_mirror_dns'; then fail 'the postinstall went on with an unresolved mirror'; fi
grep -Fq "the package mirror's name does not resolve: de3.mirror.archlinuxarm.org (name servers: 192.0.2.53, 192.0.2.54)" \
	"$work/out.log" || fail "an unresolved mirror said: $(cat "$work/out.log")"
cp "$work/resolv.conf" "$work/resolv.conf.saved"
printf 'nameserver 127.0.0.53\n' >"$work/resolv.conf"
post aarch64 'check_mirror_dns' || :
mv "$work/resolv.conf.saved" "$work/resolv.conf"
grep -Fq '(name servers: 127.0.0.53, systemd-resolved, which asks: 10.0.2.3)' "$work/out.log" ||
	fail "behind systemd-resolved the postinstall said: $(cat "$work/out.log")"
LYONA_MIRROR_DNS_SKIP=1 post aarch64 'check_mirror_dns' || fail 'Continue anyway in the wizard did not skip the check'
! grep -q '^getent' "$work/calls.log" || fail 'the check ran after Continue anyway'
printf '# none\n' >"$work/target/etc/pacman.d/mirrorlist"
if post x86_64 'check_mirror_dns'; then fail 'a mirrorlist with no server passed'; fi

# Arch Linux ARM's keys in the new system.
mkdir -p "$work/target/usr/share/pacman/keyrings"
cp "$work/keyrings/archlinuxarm-trusted" "$work/target/usr/share/pacman/keyrings/"
printf 'BBBB2222\n' >"$work/target-keys"
post aarch64 'trust_alarm_keyring' || fail "keys already there failed: $(cat "$work/out.log")"
! grep -q -- '--populate' "$work/calls.log" || fail 'keys already there were added again'
: >"$work/target-keys"
STUB_POPULATE_WORKS=1 post aarch64 'trust_alarm_keyring' || fail "adding the missing keys failed: $(cat "$work/out.log")"
grep -Fxq "arch-chroot $work/target pacman-key --populate archlinuxarm" "$work/calls.log" ||
	fail "the missing keys were added with: $(cat "$work/calls.log")"
: >"$work/target-keys"
if post aarch64 'trust_alarm_keyring'; then fail 'the new system went on without the keys'; fi
grep -Fq 'still not in the new system' "$work/out.log" || fail "keys still missing said: $(cat "$work/out.log")"
rm -f "$work/target/usr/share/pacman/keyrings/archlinuxarm-trusted"
if post aarch64 'trust_alarm_keyring'; then fail 'a new system without archlinuxarm-keyring passed'; fi

# The console on the display.
post aarch64 'use_display_console' || fail "the console step failed: $(cat "$work/out.log")"
expected='GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} console=tty0 plymouth.ignore-serial-consoles"'
[[ $(grep -v '^#' "$work/target/etc/default/grub.d/90-lyona-console.cfg") == "$expected" ]] ||
	fail "the console drop-in is: $(cat "$work/target/etc/default/grub.d/90-lyona-console.cfg")"
# install.sh's GRUB theme step regenerates grub.cfg, once (#246).
[[ ! -s $work/calls.log ]] || fail "the console step ran a command in the new system: $(cat "$work/calls.log")"
# Run again (a Retry), it is the same one line.
post aarch64 'use_display_console' || fail "the console step failed a second time: $(cat "$work/out.log")"
[[ $(grep -vc '^#' "$work/target/etc/default/grub.d/90-lyona-console.cfg") == 1 ]] ||
	fail 'a second console step added its line again'

# The aarch64 steps run on aarch64 only, before and after the system update.
grep -Pzq '\nrun_logged "Checking the package mirror'"'"'s name\.\.\." check_mirror_dns\nrun_logged "Adding the CachyOS repositories\.\.\."' \
	"$postinstall" || fail 'the mirror name is not checked first, before the CachyOS step'
grep -Pzq '\nif \[\[ \$MACHINE_ARCH == aarch64 \]\]; then\n\trun_logged "Keeping the kernel where GRUB finds it\.\.\." keep_vmlinuz_linux\n\trun_logged "Checking Arch Linux ARM'"'"'s keys\.\.\." trust_alarm_keyring\nfi\nrun_logged "Updating the new system\.\.\."' \
	"$postinstall" || fail 'the kernel copy and the keys are not checked on aarch64 just before the system update'
grep -Fq 'run_logged "Adding a firmware boot entry..." add_firmware_boot_entry' "$postinstall" ||
	fail 'the postinstall does not add the firmware boot entry'
grep -B1 'run_logged "Adding a firmware boot entry..."' "$postinstall" | grep -Fq '[[ $MACHINE_ARCH == aarch64 ]]' ||
	fail 'the firmware boot entry is not for aarch64 only'
grep -Pzq '\nif \[\[ \$MACHINE_ARCH == aarch64 \]\]; then\n\trun_logged "Putting the console on the display\.\.\." use_display_console\nfi\n' \
	"$postinstall" || fail 'the console step is not for aarch64 only'
grep -Fq 'check_mirror_dns trust_alarm_keyring keep_vmlinuz_linux add_firmware_boot_entry use_display_console \' "$postinstall" ||
	fail 'the aarch64 steps are not exported for run_logged'

printf 'Image installer, aarch64 path: PASS\n'
