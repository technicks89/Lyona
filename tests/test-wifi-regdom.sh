#!/usr/bin/env bash
set -euo pipefail

# #365: the installed system has a wireless regulatory database and, from the
# image installer, a Wi-Fi country:
# - arch:network installs wireless-regdb (and iw), on both install paths;
# - the image postinstall writes options cfg80211 ieee80211_regdom=CC from the
#   timezone's country, the same file on every run, and none without one;
# - the wizard's summary names that country and hands it to the postinstall;
# - install.sh only suggests a country on an existing system with Wi-Fi.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

root=$repo/archiso/airootfs/root
wizard=$root/lyona-install.sh
postinstall=$root/lyona-postinstall.sh

# The package map.
# shellcheck source=scripts/dwm-packages.sh
. "$repo/scripts/dwm-packages.sh"
network=$(dwm_packages arch network)
for package in networkmanager wireless-regdb iw; do
	grep -Fqx "$package" <<<"$network" || fail "arch:network does not install $package: $network"
done
dwm_packages arch desktop | grep -Fqx wireless-regdb || fail 'the desktop profile does not install wireless-regdb'

# The postinstall step, on a scratch target.
sed -n '/^set_wifi_country() {$/,/^}$/p' "$postinstall" >"$work/regdom.sh"
grep -q '^set_wifi_country() {$' "$work/regdom.sh" || fail 'set_wifi_country not found in the postinstall'
grep -Fq 'run_logged "Setting the Wi-Fi country..." set_wifi_country' "$postinstall" ||
	fail 'the postinstall does not run set_wifi_country'
grep -Eq '^[[:space:]].* set_wifi_country \\$' "$postinstall" || fail 'set_wifi_country is not exported for run_logged'

# shellcheck disable=SC2034 # TARGET is read by the sourced function
run_regdom() { # COUNTRY: runs the step against $work/target
	(
		TARGET=$work/target
		export LYONA_WIFI_COUNTRY=$1
		# shellcheck source=/dev/null
		. "$work/regdom.sh"
		set_wifi_country
	)
}
conf=$work/target/etc/modprobe.d/lyona-regdom.conf
mkdir -p "$work/target"
run_regdom DE >/dev/null || fail 'the step failed for DE'
grep -Fqx 'options cfg80211 ieee80211_regdom=DE' "$conf" || fail "DE was not written: $(cat "$conf" 2>&1)"
[[ $(stat -c %a "$conf") == 644 ]] || fail "the file is mode $(stat -c %a "$conf")"
cp "$conf" "$work/first"
run_regdom DE >/dev/null || fail 'a second run failed'
cmp -s "$conf" "$work/first" || fail 'a second run wrote a different file'
run_regdom '' >/dev/null || fail 'the step failed with no country'
[[ ! -e $conf ]] || fail 'no country still left a regdom file'
run_regdom '' >/dev/null || fail 'the step failed with no country and no file'
if run_regdom 'de;x' >/dev/null 2>&1; then
	fail 'an invalid country code was accepted'
fi
[[ ! -e $conf ]] || fail 'an invalid country code was written'

# The wizard, loaded as a library, with a zoneinfo of one zone of each kind.
zoneinfo=$work/zoneinfo
mkdir -p "$zoneinfo"
printf 'DE\t+5230+01322\tEurope/Berlin\n' >"$zoneinfo/zone.tab"
: >"$zoneinfo/zone1970.tab"
printf 'DE\tGermany\n' >"$zoneinfo/iso3166.tab"
lib() {
	# shellcheck disable=SC2016 # expanded by the inner shell
	env LYONA_INSTALL_LIB=1 LYONA_UI_LIB="$root/lyona-ui.sh" \
		LYONA_NVIDIA_LIB="$root/lyona-nvidia.sh" LYONA_WIFI_LIB="$root/lyona-wifi.sh" \
		LYONA_LOGO_PATH=/nonexistent LYONA_ZONEINFO="$zoneinfo" \
		bash -c '. "$1"; eval "$2"' bash "$wizard" "$1"
}
[[ $(lib 'TIMEZONE=Europe/Berlin; wifi_country_summary') == 'Germany (DE)' ]] ||
	fail "the summary says: $(lib 'TIMEZONE=Europe/Berlin; wifi_country_summary')"
[[ $(lib 'TIMEZONE=UTC; wifi_country_summary') == "none, the access point's" ]] ||
	fail "the UTC summary says: $(lib 'TIMEZONE=UTC; wifi_country_summary')"
# shellcheck disable=SC2016 # the literal text in the wizard
grep -Fq 'Wi-Fi country: $(wifi_country_summary)' "$wizard" || fail 'the summary screen does not show the Wi-Fi country'
# shellcheck disable=SC2016 # the literal text in the wizard
grep -Fq 'LYONA_WIFI_COUNTRY=$(timezone_country "$TIMEZONE") || LYONA_WIFI_COUNTRY=' "$wizard" ||
	fail 'the wizard does not take the Wi-Fi country from the timezone'
grep -Fqx '	export LYONA_WIFI_COUNTRY' "$wizard" || fail 'the wizard does not hand the Wi-Fi country to the postinstall'

# install.sh's tip, against a scratch system root.
awk '/^wifi_country_tip\(\) \{$/ { f = 1 } f { print } f && /^}$/ { exit }' "$repo/install.sh" >"$work/tip.sh"
grep -q '^}$' "$work/tip.sh" || fail 'wifi_country_tip not found in install.sh'
grep -Fq '	wifi_country_tip' "$repo/install.sh" || fail 'install.sh does not call wifi_country_tip'
sys=$work/sys
tip() { # prints what the tip says for $sys
	(
		# shellcheck disable=SC2329 # called by the sourced tip
		info() { printf '%s\n' "$1"; }
		export LYONA_SYSROOT=$sys
		# shellcheck source=/dev/null
		. "$work/tip.sh"
		wifi_country_tip
	)
}
mkdir -p "$sys/sys/class/ieee80211" "$sys/proc" "$sys/etc/conf.d" "$sys/etc/modprobe.d"
printf 'BOOT_IMAGE=/vmlinuz root=UUID=x rw\n' >"$sys/proc/cmdline"
[[ -z $(tip) ]] || fail 'a machine with no Wi-Fi got the tip'
mkdir "$sys/sys/class/ieee80211/phy0"
printf '#WIRELESS_REGDOM="DE"\n#WIRELESS_REGDOM="US"\n' >"$sys/etc/conf.d/wireless-regdom"
[[ $(tip) == *'no Wi-Fi country is set'* ]] || fail "Wi-Fi with no country got no tip: $(tip)"
[[ -z $(LYONA_SOURCE=iso tip) ]] || fail 'the image install (which sets the country) got the tip'
printf '#WIRELESS_REGDOM="DE"\nWIRELESS_REGDOM="US"\n' >"$sys/etc/conf.d/wireless-regdom"
[[ -z $(tip) ]] || fail 'a country in /etc/conf.d/wireless-regdom was not seen'
printf '#WIRELESS_REGDOM="DE"\n' >"$sys/etc/conf.d/wireless-regdom"
printf 'options cfg80211 ieee80211_regdom=GB\n' >"$sys/etc/modprobe.d/wifi.conf"
[[ -z $(tip) ]] || fail 'a country in modprobe.d was not seen'
rm "$sys/etc/modprobe.d/wifi.conf"
printf 'root=UUID=x cfg80211.ieee80211_regdom=FR\n' >"$sys/proc/cmdline"
[[ -z $(tip) ]] || fail 'a country on the kernel command line was not seen'

printf 'Wi-Fi regulatory database and country (package, postinstall, wizard, install.sh tip): PASS\n'
