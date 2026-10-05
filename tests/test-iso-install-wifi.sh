#!/usr/bin/env bash
set -euo pipefail

# #237: the install wizard offers Wi-Fi when there is no wired connection, and
# the postinstall carries the network over to the new system.
#
# archiso/airootfs/root/lyona-wifi.sh and the wizard's connect_wifi run against
# a stub busctl serving iwd's D-Bus objects as JSON, a stub gum answering the
# prompts, and fake sysfs and iwd directories.
#
# - Wireless interfaces and driverless Wi-Fi chips come from sysfs.
# - Networks are listed strongest first, with signal and security.
# - The passphrase goes into iwd's profile (mode 600, the name iwd expects) and
#   never into any command's arguments or the install log; a failed connection
#   removes it and says so; enterprise networks are refused with a reason.
# - The postinstall writes a NetworkManager profile (mode 600) with the SSID
#   and passphrase, escaped for a key file, and nothing when not on Wi-Fi.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}

root=$repo/archiso/airootfs/root
export STUB_DIR=$work
export LYONA_IWD_DIR=$work/iwd LYONA_SYS_NET=$work/sys-net LYONA_SYS_PCI=$work/sys-pci LYONA_WIFI_TICK=0

# iwd's objects: one adapter, a station wlan0, and three networks.
station=/net/connman/iwd/0/3
home=$station/486f6d65_psk
cafe=$station/436166c3a9_open
corp=$station/436f7270_8021x
objects() { # CONNECTED-NETWORK-PATH
	jq -n --arg station "$station" --arg home "$home" --arg cafe "$cafe" --arg corp "$corp" \
		--arg connected "${1:-}" '
		def s($v): {type: "s", data: $v};
		def net($name; $type): {"net.connman.iwd.Network": {Name: s($name), Type: s($type),
			Device: {type: "o", data: $station}}};
		{type: "a{oa{sa{sv}}}", data: [{
			"/net/connman/iwd/0": {"net.connman.iwd.Adapter": {Powered: {type: "b", data: true}}},
			($station): ({"net.connman.iwd.Device": {Name: s("wlan0"), Adapter: {type: "o", data: "/net/connman/iwd/0"}},
				"net.connman.iwd.Station": {Scanning: {type: "b", data: false}}}
				| if $connected != "" then .["net.connman.iwd.Station"].ConnectedNetwork = {type: "o", data: $connected} else . end),
			($home): net("Home"; "psk"),
			($cafe): net("Café Wi-Fi"; "open"),
			($corp): net("Corp"; "8021x")
		}]}'
}
objects >"$work/objects.json"
jq -n --arg home "$home" --arg cafe "$cafe" --arg corp "$corp" \
	'{type: "a(on)", data: [[[$home, -5200], [$cafe, -7000], [$corp, -8000]]]}' >"$work/ordered.json"

# busctl: logs every call; answers from the files above. STUB_CONNECT=fail
# fails Connect and ConnectHiddenNetwork as a wrong passphrase does.
mkdir -p "$work/bin"
cat >"$work/bin/busctl" <<'EOF'
#!/bin/bash
printf 'busctl %s\n' "$*" >>"$STUB_DIR/busctl.log"
case $* in
*GetManagedObjects*)
	[[ -s $STUB_DIR/objects.json ]] || exit 1
	cat "$STUB_DIR/objects.json"
	;;
*GetOrderedNetworks*) cat "$STUB_DIR/ordered.json" ;;
*'get-property'*Scanning*) printf '{"type":"b","data":false}\n' ;;
*'get-property'*' Name')
	for arg; do [[ $arg == /net/* ]] && path=$arg; done
	jq -c --arg path "$path" '.data[0][$path]["net.connman.iwd.Network"].Name' "$STUB_DIR/objects.json"
	;;
*' Connect' | *ConnectHiddenNetwork*)
	# What iwd would read: the profiles there when it is asked to connect.
	cat "$LYONA_IWD_DIR"/* >>"$STUB_DIR/profiles-at-connect" 2>/dev/null
	if [[ ${STUB_CONNECT:-} == fail ]]; then
		printf 'Call failed: Operation failed\n' >&2
		exit 1
	fi
	;;
esac
exit 0
EOF
# gum: `input` answers from inputs (a line each), `choose` from choices;
# `style` prints its text; confirm answers no.
cat >"$work/bin/gum" <<'EOF'
#!/bin/bash
next() { # FILE
	local line
	line=$(head -n 1 "$1")
	sed -i 1d "$1"
	printf '%s' "$line"
	[[ -n $line ]]
}
case $1 in
input) printf 'gum %s\n' "$*" >>"$STUB_DIR/gum.log"; next "$STUB_DIR/inputs" ;;
choose)
	printf 'gum %s\n' "$*" >>"$STUB_DIR/gum.log"
	next "$STUB_DIR/choices"
	;;
style) printf '%s\n' "${@: -1}" ;;
confirm) exit 1 ;;
*) exit 0 ;;
esac
EOF
for cmd in rfkill systemctl clear tput sleep; do
	printf '#!/bin/sh\nexit 0\n' >"$work/bin/$cmd"
done
chmod +x "$work/bin/"*
export PATH=$work/bin:$PATH

# shellcheck source=/dev/null # the live medium's library, not a check-shell input
. "$root/lyona-wifi.sh"

# ── sysfs: wireless interfaces, and Wi-Fi chips without a driver ─────────

mkdir -p "$work/sys-net/eth0" "$work/sys-net/wlan0/wireless" "$work/sys-net/lo"
[[ $(wifi_interfaces) == wlan0 ]] || fail "the wireless interfaces: $(wifi_interfaces)"
pci_device() { # NAME CLASS VENDOR DEVICE DRIVER(yes|no)
	mkdir -p "$work/sys-pci/$1"
	printf '%s\n' "$2" >"$work/sys-pci/$1/class"
	printf '%s\n' "$3" >"$work/sys-pci/$1/vendor"
	printf '%s\n' "$4" >"$work/sys-pci/$1/device"
	[[ $5 == no ]] || ln -s /nonexistent "$work/sys-pci/$1/driver"
}
pci_device 0000:00:1f.6 0x020000 0x8086 0x15bc no
pci_device 0000:02:00.0 0x028000 0x8086 0x2723 yes
[[ -z $(wifi_driver_hint) ]] || fail "a hint with every Wi-Fi chip driven: $(wifi_driver_hint)"
pci_device 0000:03:00.0 0x028000 0x14e4 0x4331 no
hint=$(wifi_driver_hint)
[[ $hint == *'A Wi-Fi chip (14e4:4331) has no driver on this live medium.'* ]] || fail "the driver hint: $hint"
[[ $hint == *broadcom-wl* ]] || fail "no broadcom-wl note for a Broadcom chip: $hint"

# ── iwd: the station, and its networks strongest first ───────────────────

[[ $(wifi_station wlan0) == "$station" ]] || fail 'the station for wlan0 was not found'
if wifi_station wlan9 >/dev/null; then fail 'a station was found for a device iwd does not have'; fi
mapfile -t rows < <(wifi_networks "$station")
[[ ${#rows[@]} == 3 ]] || fail "the networks: ${rows[*]}"
[[ ${rows[0]} == "$home"$'\tHome\tpsk\t-5200' ]] || fail "the strongest network first: ${rows[0]}"
[[ ${rows[1]} == "$cafe"$'\tCafé Wi-Fi\topen\t-7000' ]] || fail "the second network: ${rows[1]}"
[[ $(wifi_bars -5200) == '####' && $(wifi_bars -7000) == '##--' && $(wifi_bars -8000) == '#---' ]] ||
	fail 'the signal bars'
[[ $(wifi_display_name $'evil\e[2Jname') == 'evil?[2Jname' ]] || fail 'control characters reach the screen'

# ── iwd's profile names and contents ─────────────────────────────────────

[[ $(wifi_profile_path Home_net-1 psk) == "$work/iwd/Home_net-1.psk" ]] || fail 'a plain SSID profile name'
[[ $(wifi_profile_path 'Café Wi-Fi' open) == "$work/iwd/=436166c3a92057692d4669.open" ]] ||
	fail "a hex-encoded profile name: $(wifi_profile_path 'Café Wi-Fi' open)"
for good in 12345678 'correct horse battery staple' "$(printf 'x%.0s' {1..63})"; do
	wifi_valid_passphrase "$good" || fail "a valid passphrase was refused: $good"
done
for bad in 1234567 "$(printf 'x%.0s' {1..64})" $'tab\there1' ''; do
	if wifi_valid_passphrase "$bad"; then fail "an invalid passphrase was accepted: $bad"; fi
done

# ── the wizard: connect with a passphrase ────────────────────────────────

wizard() { # FUNCTION ARGS...: runs it with the installer sourced as a library
	LYONA_INSTALL_LIB=1 LYONA_UI_LIB="$root/lyona-ui.sh" LYONA_NVIDIA_LIB="$root/lyona-nvidia.sh" \
		LYONA_WIFI_LIB="$root/lyona-wifi.sh" LYONA_LOGO_PATH=/nonexistent bash -c '
		. "$1"
		LOG_FILE=$STUB_DIR/install.log
		shift
		status=0
		"$@" || status=$?
		printf "%s\n" "$WIFI_MESSAGE" >"$STUB_DIR/message"
		exit "$status"' _ "$root/lyona-install.sh" "$@"
}
reset() {
	rm -rf "${work:?}/iwd" "$work/busctl.log" "$work/gum.log" "$work/profiles-at-connect" "$work/install.log"
	: >"$work/inputs"
	: >"$work/choices"
}
secret='s3cret pass\word='

reset
printf '%s\n' 'Home  ####  WPA' >"$work/choices"
printf '%s\n' short "$secret" >"$work/inputs"
wizard connect_wifi >"$work/out" 2>&1 || fail "connecting to Home failed: $(cat "$work/out")"
grep -Fq 'A WPA passphrase is 8 to 63 characters.' "$work/out" || fail 'a short passphrase was not refused'
profile=$work/iwd/Home.psk
[[ -f $profile ]] || fail 'no iwd profile was written'
[[ $(stat -c %a "$profile") == 600 ]] || fail "the iwd profile is mode $(stat -c %a "$profile")"
[[ $(sed -n 's/^Passphrase=//p' "$profile") == "$secret" ]] || fail "the passphrase in the profile: $(cat "$profile")"
grep -Fqx "Passphrase=$secret" "$work/profiles-at-connect" || fail 'the profile was not there when iwd connected'
grep -Fq "call net.connman.iwd $home net.connman.iwd.Network Connect" "$work/busctl.log" ||
	fail "Home was not connected: $(cat "$work/busctl.log")"
grep -q 'Choose a Wi-Fi network:.*Home  ####  WPA' "$work/gum.log" || fail "the list: $(cat "$work/gum.log")"
grep -q 'Café Wi-Fi  ##--  open.*Corp  #---  enterprise (not supported).*Other (hidden network)' "$work/gum.log" ||
	fail "the list order or its entries: $(cat "$work/gum.log")"
for file in "$work/busctl.log" "$work/install.log" "$work/out" "$work/gum.log"; do
	if [[ -f $file ]] && grep -Fq "$secret" "$file"; then fail "the passphrase reached $file"; fi
done

# A wrong passphrase: the profile goes, the reason is shown, the list comes back.
reset
printf '%s\n' 'Home  ####  WPA' Back >"$work/choices"
printf '%s\n' 'wrong passphrase' >"$work/inputs"
if STUB_CONNECT=fail wizard connect_wifi >"$work/out" 2>&1; then fail 'a failed connection was reported as connected'; fi
[[ ! -e $work/iwd/Home.psk ]] || fail 'the profile with the wrong passphrase was kept'
grep -q 'Could not connect to Home. Check the passphrase' "$work/gum.log" ||
	fail "the failure was not shown with the list: $(cat "$work/gum.log")"
grep -Fq 'wifi: connect failed: Call failed: Operation failed' "$work/install.log" || fail 'the failure was not logged'

# An open network: no passphrase, no profile written by the wizard.
reset
printf '%s\n' 'Café Wi-Fi  ##--  open' >"$work/choices"
wizard connect_wifi >"$work/out" 2>&1 || fail "connecting to an open network failed: $(cat "$work/out")"
[[ ! -s $work/inputs && -z $(find "$work/iwd" -type f 2>/dev/null) ]] || fail 'an open network asked for a passphrase'

# Enterprise: refused with a reason, nothing asked or connected.
reset
printf '%s\n' 'Corp  #---  enterprise (not supported)' Back >"$work/choices"
if wizard connect_wifi >/dev/null 2>&1; then fail 'an enterprise network was connected'; fi
grep -q 'Corp uses enterprise (not supported) security, which the installer cannot set up' "$work/gum.log" ||
	fail "no reason for refusing an enterprise network: $(cat "$work/gum.log")"
! grep -q ' Connect' "$work/busctl.log" || fail 'an enterprise network was connected to'

# A hidden network: the profile is marked hidden, and iwd connects by name.
reset
printf '%s\n' 'Other (hidden network)' >"$work/choices"
printf '%s\n' Attic 'hidden passphrase' >"$work/inputs"
wizard connect_wifi >"$work/out" 2>&1 || fail "connecting to a hidden network failed: $(cat "$work/out")"
grep -Fqx 'Hidden=true' "$work/iwd/Attic.psk" || fail 'the hidden network profile is not marked hidden'
grep -Fq "call net.connman.iwd $station net.connman.iwd.Station ConnectHiddenNetwork s Attic" "$work/busctl.log" ||
	fail "the hidden network was not connected by name: $(cat "$work/busctl.log")"
if grep -Fq 'hidden passphrase' "$work/busctl.log"; then fail 'the hidden passphrase reached argv'; fi

# No iwd station: the reason comes back to the network check.
reset
mv "$work/objects.json" "$work/objects.saved"
if wizard connect_wifi >/dev/null 2>&1; then fail 'connected without an iwd station'; fi
grep -q 'wlan0 did not come up for Wi-Fi' "$work/message" || fail "no reason without a station: $(cat "$work/message")"
mv "$work/objects.saved" "$work/objects.json"

# ── the postinstall: a NetworkManager profile for the new system ─────────

target=$work/target
profile=$target/etc/NetworkManager/system-connections/lyona-wifi.nmconnection
reset
objects "" >"$work/objects.json"
wifi_carry_over "$target" >"$work/out" || fail 'carrying over without Wi-Fi failed'
[[ ! -e $profile && ! -s $work/out ]] || fail 'a profile was written while not on Wi-Fi'

objects "$home" >"$work/objects.json"
mkdir -p "$work/iwd"
nm_secret=' leading\back=slash'
printf '[Security]\nPassphrase=%s\nPreSharedKey=%s\n' "$nm_secret" "$(printf 'ab%.0s' {1..32})" >"$work/iwd/Home.psk"
wifi_carry_over "$target" >"$work/out" || fail "carrying over Home failed: $(cat "$work/out")"
[[ -f $profile ]] || fail 'no NetworkManager profile was written'
[[ $(stat -c %a "$profile") == 600 ]] || fail "the NetworkManager profile is mode $(stat -c %a "$profile")"
grep -Fqx 'ssid=Home' "$profile" || fail "the SSID: $(cat "$profile")"
grep -Fqx 'key-mgmt=wpa-psk' "$profile" || fail 'the profile is not WPA-PSK'
grep -Fqx 'psk=\sleading\\back=slash' "$profile" || fail "the passphrase, escaped: $(grep '^psk=' "$profile")"
grep -Eqx 'uuid=[0-9a-f-]{36}' "$profile" || fail 'the profile has no UUID'
! grep -q '^hidden=' "$profile" || fail 'a broadcast network was marked hidden'
if grep -Fq "$nm_secret" "$work/out"; then fail 'the passphrase was printed'; fi

# Hidden and open: no security section, hidden kept.
objects "$cafe" >"$work/objects.json"
printf '[Settings]\nHidden=true\n' >"$work/iwd/=436166c3a92057692d4669.open"
wifi_carry_over "$target" >/dev/null || fail 'carrying over an open network failed'
grep -Fqx 'ssid=Café Wi-Fi' "$profile" || fail "the open network's SSID: $(cat "$profile")"
grep -Fqx 'hidden=true' "$profile" || fail 'the hidden open network was not marked hidden'
! grep -q 'wifi-security' "$profile" || fail 'an open network got a security section'

# Enterprise: said, and nothing written.
rm -f "$profile"
objects "$corp" >"$work/objects.json"
out=$(wifi_carry_over "$target")
[[ $out == *'not carried over'* && ! -e $profile ]] || fail "an enterprise network: $out"

# ── wiring ───────────────────────────────────────────────────────────────

# shellcheck disable=SC2016 # the literal text in the wizard
grep -Fqx 'source "${LYONA_WIFI_LIB:-/root/lyona-wifi.sh}"' "$root/lyona-install.sh" ||
	fail 'the wizard does not source lyona-wifi.sh'
grep -Fqx 'source /root/lyona-wifi.sh' "$root/lyona-postinstall.sh" || fail 'the postinstall does not source lyona-wifi.sh'
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fq 'if ! wifi_carry_over "$TARGET" >>"$LOG_FILE" 2>&1; then' "$root/lyona-postinstall.sh" ||
	fail 'the postinstall does not carry the Wi-Fi network over'
nm=$(grep -n 'run_logged "Configuring NetworkManager..." install_networkmanager' "$root/lyona-postinstall.sh" | cut -d: -f1)
# shellcheck disable=SC2016 # the literal text in the postinstall
carry=$(grep -n 'wifi_carry_over "$TARGET"' "$root/lyona-postinstall.sh" | cut -d: -f1)
if [[ -z $nm || -z $carry ]] || ((carry <= nm)); then
	fail 'the Wi-Fi network is carried over before NetworkManager is set up'
fi
grep -Fq '"Connect to Wi-Fi" "Retry" "Continue without internet"' "$root/lyona-install.sh" ||
	fail 'the network check does not offer Wi-Fi'

printf 'ISO install Wi-Fi: PASS\n'
