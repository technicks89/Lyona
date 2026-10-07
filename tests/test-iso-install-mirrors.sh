#!/usr/bin/env bash
set -euo pipefail

# The image installer downloads from mirrors near the user (#249):
# - the confirmed timezone gives a country (zone.tab, else zone1970.tab), and a
#   zone with no country (UTC, Etc/*) gives worldwide;
# - rank_mirrors replaces the live mirrorlist with the fastest mirrors in that
#   country, adds worldwide ones when it has fewer than three, and keeps the
#   mirrorlist the medium booted with when nothing could be ranked;
# - the summary screen names the mirrors, the postinstall copies the ranked
#   list to the new system, and both pacman configurations download 10
#   packages at a time;
# - install.sh only suggests ParallelDownloads = 10 on an existing system.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

root=$repo/archiso/airootfs/root
wizard=$root/lyona-install.sh
postinstall=$root/lyona-postinstall.sh

# A zoneinfo with one zone of each kind.
zoneinfo=$work/zoneinfo
mkdir -p "$zoneinfo"
printf '# comment\nDE\t+5230+01322\tEurope/Berlin\tmost of Germany\nJP\t+353916+1394441\tAsia/Tokyo\n' \
	>"$zoneinfo/zone.tab"
printf '# comment\nDE,DK,NO,SE,SJ\t+5230+01322\tEurope/Berlin\nSE,FI\t+0000+00000\tTest/Several\n' \
	>"$zoneinfo/zone1970.tab"
printf '# comment\nDE\tGermany\nJP\tJapan\nSE\tSweden\n' >"$zoneinfo/iso3166.tab"

# A reflector that writes STUB_<KIND>_SERVERS servers for a country, or for
# worldwide, and fails with STUB_FAIL=1. Each call goes to the log.
cat >"$work/bin/reflector" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
[[ ${STUB_FAIL:-0} == 1 ]] && exit 1
country= save=
while (($# > 0)); do
	case $1 in
	--country) country=$2; shift ;;
	--save) save=$2; shift ;;
	esac
	shift
done
if [[ -n $country ]]; then n=${STUB_COUNTRY_SERVERS:-0}; tag=$country; else n=${STUB_WORLD_SERVERS:-0}; tag=world; fi
{
	printf '# reflector output\n'
	for ((i = 1; i <= n; i++)); do printf 'Server = https://%s%d.example/$repo/os/$arch\n' "$tag" "$i"; done
	# A server both lists name, to check it is kept once.
	((n > 0)) && printf 'Server = https://shared.example/$repo/os/$arch\n'
} >"$save"
STUB
chmod +x "$work/bin/reflector"

# lib CODE: CODE with the wizard loaded as a library.
lib() {
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/bin:$PATH" LYONA_INSTALL_LIB=1 LYONA_UI_LIB="$root/lyona-ui.sh" \
		LYONA_NVIDIA_LIB="$root/lyona-nvidia.sh" LYONA_WIFI_LIB="$root/lyona-wifi.sh" \
		LYONA_LOGO_PATH=/nonexistent LYONA_ZONEINFO="$zoneinfo" \
		LYONA_MIRRORLIST="$work/mirrorlist" LYONA_MIRRORS_MARKER="$work/marker" \
		STUB_LOG="$work/reflector.log" bash -c '. "$1"; eval "$2"' bash "$wizard" "$1"
}

# The country from the timezone.
for case in 'Europe/Berlin DE' 'Asia/Tokyo JP' 'Test/Several SE'; do
	got=$(lib "timezone_country ${case% *}") || fail "no country for ${case% *}"
	[[ $got == "${case#* }" ]] || fail "${case% *} gave $got, not ${case#* }"
done
for zone in UTC Etc/GMT+5 Nowhere/Unknown; do
	if got=$(lib "timezone_country $zone"); then
		fail "$zone gave a country: $got"
	fi
done
[[ $(lib 'country_name DE') == Germany ]] || fail 'DE is not named Germany'
[[ $(lib 'country_name XX') == XX ]] || fail 'an unlisted code is not named by itself'
[[ $(lib 'MIRROR_COUNTRY=DE; mirror_summary') == 'Germany (DE), the fastest of them' ]] ||
	fail "the summary says: $(lib 'MIRROR_COUNTRY=DE; mirror_summary')"
[[ $(lib 'MIRROR_COUNTRY=; mirror_summary') == 'worldwide, the fastest from here' ]] ||
	fail 'the summary does not say worldwide without a country'

reset() {
	# shellcheck disable=SC2016 # the literal text of a mirrorlist
	printf 'Server = https://original.example/$repo/os/$arch\n' >"$work/mirrorlist"
	rm -f "$work/marker" "$work/reflector.log"
}
servers() { grep '^Server = ' "$work/mirrorlist" | sed 's#^Server = https://##; s#/.*##' | tr '\n' ' '; }

# Enough mirrors in the country: only those, fastest first, and no worldwide run.
reset
STUB_COUNTRY_SERVERS=4 lib 'rank_mirrors DE' >/dev/null || fail 'rank_mirrors failed'
[[ $(servers) == 'DE1.example DE2.example DE3.example DE4.example shared.example ' ]] ||
	fail "the ranked list is: $(servers)"
[[ $(wc -l <"$work/reflector.log") == 1 ]] || fail 'a worldwide ranking ran although the country had enough'
grep -q -- '--country DE' "$work/reflector.log" || fail 'the country was not passed to reflector'
for arg in '--protocol https' '--sort rate' '--latest 20'; do
	grep -q -- "$arg" "$work/reflector.log" || fail "reflector was not given $arg"
done
[[ -e $work/marker ]] || fail 'no marker for the postinstall'
head -n 1 "$work/mirrorlist" | grep -q '^# Ranked by lyona-install (reflector, DE)' || fail 'the list does not say where it came from'

# Too few: the country's first, then worldwide, each server once.
reset
STUB_COUNTRY_SERVERS=1 STUB_WORLD_SERVERS=2 lib 'rank_mirrors DE' >/dev/null
[[ $(servers) == 'DE1.example shared.example world1.example world2.example ' ]] ||
	fail "a country with too few mirrors gave: $(servers)"

# No country: worldwide alone.
reset
STUB_WORLD_SERVERS=3 lib 'rank_mirrors ""' >/dev/null
grep -q -- '--country' "$work/reflector.log" && fail 'a ranking without a country passed one'
[[ $(servers) == 'world1.example world2.example world3.example shared.example ' ]] ||
	fail "worldwide gave: $(servers)"

# Nothing ranked (offline, or reflector failed): the list stays, no failure.
reset
out=$(STUB_FAIL=1 lib 'rank_mirrors DE') || fail 'a failed ranking failed the install'
[[ $out == *'keeping the current mirrorlist'* ]] || fail "a failed ranking said: $out"
[[ $(servers) == 'original.example ' && ! -e $work/marker ]] || fail 'a failed ranking changed the mirrorlist'

# Each ranking is bounded, and the step runs before anything is downloaded.
[[ $(grep -c 'timeout 30 reflector' "$wizard") == 2 ]] || fail 'a reflector run is not bounded to 30 seconds'
order=$(grep -nE '^	(confirm_and_proceed|run_logged "Choosing the fastest package mirrors\.\.\." rank_mirrors|setup_cachyos_repositories|run_archinstall)' "$wizard" | cut -d: -f1 | tr '\n' ' ')
read -r confirm rank cachyos archinstall <<<"$order"
if [[ -z ${archinstall:-} ]] || ! ((confirm < rank && rank < cachyos && cachyos < archinstall)); then
	fail "the mirrors are not ranked between the summary and the first download: $order"
fi
# shellcheck disable=SC2016 # the literal text in the wizard
grep -q '^Mirrors:    \$(mirror_summary)$' "$wizard" || fail 'the summary screen does not show the mirrors'
grep -Eq '^	ask_mirrors$' "$wizard" || fail 'the wizard does not ask about the mirrors'

# The new system keeps the ranked list, only when there is one.
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fq 'if [[ -e $LYONA_MIRRORS_MARKER ]]; then' "$postinstall" || fail 'the postinstall does not check the marker'
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fq 'install -Dm644 /etc/pacman.d/mirrorlist "$TARGET/etc/pacman.d/mirrorlist"' "$postinstall" ||
	fail 'the postinstall does not copy the ranked mirrorlist'

# The medium's own pacman.conf (the pacman package's, with 5): 10, whether the
# line is set, commented out or missing; nothing else changes.
for case in 'ParallelDownloads = 5' '#ParallelDownloads = 5' ''; do
	printf '[options]\nHoldPkg = pacman glibc\n%s\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' "$case" >"$work/pacman.conf"
	LYONA_PACMAN_CONF=$work/pacman.conf lib "LOG_FILE=$work/install.log; use_parallel_downloads"
	if [[ $(grep -c 'ParallelDownloads' "$work/pacman.conf") != 1 ]] || ! grep -Fxq 'ParallelDownloads = 10' "$work/pacman.conf"; then
		fail "the live pacman.conf with '$case' became: $(cat "$work/pacman.conf")"
	fi
	if ! grep -Fxq 'HoldPkg = pacman glibc' "$work/pacman.conf" || ! grep -Fxq '[core]' "$work/pacman.conf"; then
		fail "use_parallel_downloads changed more than ParallelDownloads: $(cat "$work/pacman.conf")"
	fi
	awk '/^\[options\]$/ { o = 1; next } /^\[/ { o = 0 } o && /^ParallelDownloads = 10$/ { found = 1 } END { exit !found }' \
		"$work/pacman.conf" || fail "ParallelDownloads is not under [options] with '$case'"
done
grep -Eq '^	use_parallel_downloads$' "$wizard" || fail 'the wizard does not raise the medium'"'"'s ParallelDownloads'

# Ten downloads at a time, on the medium and on the new system.
grep -Fxq 'ParallelDownloads = 10' "$repo/archiso/pacman.conf" || fail 'the live medium does not download 10 at a time'
grep -Fq '"pacman_config": {"color": true, "parallel_downloads": 10}' "$wizard" ||
	fail 'the new system does not download 10 at a time'

# install.sh: a tip on an existing system, never a change.
awk '/^pacman_parallel_downloads_tip\(\) \{$/ { f = 1 } f { print } f && /^}$/ { exit }' "$repo/install.sh" >"$work/tip.sh"
[[ -s $work/tip.sh ]] || fail 'pacman_parallel_downloads_tip not found in install.sh'
for case in '5 tip' '1 tip' '10 none' '16 none'; do
	printf '#!/bin/sh\necho %s\n' "${case% *}" >"$work/bin/pacman-conf"
	chmod +x "$work/bin/pacman-conf"
	# shellcheck disable=SC2016 # expanded by the inner shell
	out=$(env PATH="$work/bin:$PATH" bash -c 'info() { printf "%s\n" "$1"; }; . "$1"; pacman_parallel_downloads_tip' bash "$work/tip.sh")
	if [[ ${case#* } == tip ]]; then
		[[ $out == "Tip: pacman downloads ${case% *} package(s) at a time."* ]] || fail "ParallelDownloads ${case% *} gave: $out"
	else
		[[ -z $out ]] || fail "ParallelDownloads ${case% *} still gave a tip: $out"
	fi
done
if grep -nE 'sed .*ParallelDownloads|ParallelDownloads.*>.*pacman\.conf' "$repo/install.sh" | grep -q .; then
	fail 'install.sh edits pacman.conf'
fi

echo "PASS: $test_name"
