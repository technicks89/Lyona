# shellcheck shell=bash
# Wi-Fi for the install wizard and the postinstall (#237). Sourced, not run.
#
# The live medium connects with iwd (from releng; systemd-networkd then runs
# DHCP on the link). Everything here goes through iwd's D-Bus API with
# `busctl --json`, not iwctl's coloured, human-oriented output.
#
# The passphrase never reaches argv, the install log or the terminal. It goes
# from gum's password prompt into iwd's own profile, /var/lib/iwd/SSID.psk
# (mode 600), written with bash builtins, and iwd connects from that file. The
# postinstall reads it back from there to give the new system a NetworkManager
# profile (mode 600), so the first boot is online too.
#
# Every function returns a status the caller tests, so the installer's ERR trap
# (lyona-ui.sh) never mistakes "no Wi-Fi" for a failed install.

readonly LYONA_IWD=net.connman.iwd
LYONA_IWD_DIR=${LYONA_IWD_DIR:-/var/lib/iwd}
LYONA_SYS_NET=${LYONA_SYS_NET:-/sys/class/net}
LYONA_SYS_PCI=${LYONA_SYS_PCI:-/sys/bus/pci/devices}
# Seconds between checks while waiting for iwd, a scan or DHCP.
LYONA_WIFI_TICK=${LYONA_WIFI_TICK:-0.5}

# The wireless interfaces, by name, one per line.
wifi_interfaces() {
	local dir
	for dir in "$LYONA_SYS_NET"/*/wireless; do
		[[ -d $dir ]] || continue
		dir=${dir%/wireless}
		printf '%s\n' "${dir##*/}"
	done
	return 0
}

# Every iwd object with its properties: GetManagedObjects as JSON.
iwd_objects() {
	busctl --json=short call "$LYONA_IWD" / org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null
}

iwd_property() { # PATH INTERFACE PROPERTY
	busctl --json=short get-property "$LYONA_IWD" "$1" "$LYONA_IWD.$2" "$3" 2>/dev/null | jq -r '.data'
}

# The iwd profile for an SSID: the name itself when it is only letters, digits,
# '-' and '_', otherwise '=' and the SSID's bytes in lowercase hex (iwd's
# storage rule). SUFFIX is psk or open.
wifi_profile_path() { # SSID SUFFIX
	local name=$1 hex
	if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
		hex=$(printf '%s' "$name" | od -An -tx1 -v | tr -d ' \n')
		name="=$hex"
	fi
	printf '%s/%s.%s\n' "$LYONA_IWD_DIR" "$name" "$2"
}

# A WPA passphrase: 8 to 63 printable ASCII characters.
wifi_valid_passphrase() {
	local LC_ALL=C
	[[ $1 =~ ^[[:print:]]{8,63}$ ]]
}

# Writes iwd's profile for SSID. PASSPHRASE empty means an open network.
# printf is a builtin: the passphrase is in no process's arguments.
wifi_write_profile() { # SSID PASSPHRASE HIDDEN(true|false)
	local file tmp
	if [[ -n $2 ]]; then
		file=$(wifi_profile_path "$1" psk)
	else
		file=$(wifi_profile_path "$1" open)
	fi
	tmp=$file.lyona-tmp
	(
		umask 077
		mkdir -p -- "$LYONA_IWD_DIR" || exit 1
		{
			if [[ -n $2 ]]; then
				printf '[Security]\nPassphrase=%s\n' "$2"
			fi
			if [[ $3 == true ]]; then
				printf '[Settings]\nHidden=true\n'
			fi
		} >"$tmp" || exit 1
		mv -f -- "$tmp" "$file"
	) || {
		rm -f -- "$tmp"
		return 1
	}
	printf '%s\n' "$file"
}

# The station object for INTERFACE, once iwd has one: it unblocks the radio and
# powers the adapter and the device on first, as a soft-blocked or powered-off
# card has no station. Fails after about ten seconds without one.
wifi_station() { # INTERFACE
	local objects station device adapter i
	rfkill unblock wlan >/dev/null 2>&1 || :
	systemctl is-active --quiet iwd.service 2>/dev/null || systemctl start iwd.service >/dev/null 2>&1 || :
	for ((i = 0; i < 20; i++)); do
		if objects=$(iwd_objects) && [[ -n $objects ]]; then
			station=$(jq -r --arg name "$1" '
				[.data[0] | to_entries[]
					| select(.value["net.connman.iwd.Device"].Name.data == $name)
					| select(.value | has("net.connman.iwd.Station")) | .key] | first // empty' <<<"$objects") ||
				station=
			if [[ -n $station ]]; then
				printf '%s\n' "$station"
				return 0
			fi
			device=$(jq -r --arg name "$1" '
				[.data[0] | to_entries[]
					| select(.value["net.connman.iwd.Device"].Name.data == $name)] | first // empty
				| "\(.key)\t\(.value["net.connman.iwd.Device"].Adapter.data // "")"' <<<"$objects") || device=
			if [[ -n $device ]]; then
				adapter=${device#*$'\t'}
				device=${device%%$'\t'*}
				[[ -z $adapter ]] ||
					busctl set-property "$LYONA_IWD" "$adapter" "$LYONA_IWD.Adapter" Powered b true >/dev/null 2>&1 || :
				busctl set-property "$LYONA_IWD" "$device" "$LYONA_IWD.Device" Powered b true >/dev/null 2>&1 || :
				busctl set-property "$LYONA_IWD" "$device" "$LYONA_IWD.Device" Mode s station >/dev/null 2>&1 || :
			fi
		fi
		sleep "$LYONA_WIFI_TICK"
	done
	return 1
}

# Starts a scan and waits, up to about fifteen seconds, for it to finish. A
# scan already running (iwd answers Busy) is waited for the same way.
wifi_scan() { # STATION
	local i
	busctl call "$LYONA_IWD" "$1" "$LYONA_IWD.Station" Scan >/dev/null 2>&1 || :
	for ((i = 0; i < 30; i++)); do
		[[ $(iwd_property "$1" Station Scanning) != false ]] || return 0
		sleep "$LYONA_WIFI_TICK"
	done
	return 0
}

# The networks STATION sees, strongest first: PATH, NAME, TYPE and SIGNAL (dBm
# times 100), tab-separated, one per line. TYPE is open, psk, wep or 8021x.
wifi_networks() { # STATION
	local objects ordered
	objects=$(iwd_objects) || return 1
	ordered=$(busctl --json=short call "$LYONA_IWD" "$1" "$LYONA_IWD.Station" GetOrderedNetworks 2>/dev/null) ||
		return 1
	jq -rn --argjson objects "$objects" --argjson ordered "$ordered" '
		$ordered.data[0][] as [$path, $signal]
		| $objects.data[0][$path]["net.connman.iwd.Network"] as $network
		| select($network != null)
		| [$path, $network.Name.data, $network.Type.data, ($signal | tostring)] | @tsv'
}

# Four bars at -60 dBm or better, down to one below -75 dBm.
wifi_bars() { # SIGNAL
	local signal=$1
	if ((signal >= -6000)); then
		printf '####'
	elif ((signal >= -6700)); then
		printf '###-'
	elif ((signal >= -7500)); then
		printf '##--'
	else
		printf '#---'
	fi
}

wifi_security_words() { # TYPE
	case $1 in
	open) printf 'open' ;;
	psk) printf 'WPA' ;;
	wep) printf 'WEP (not supported)' ;;
	8021x) printf 'enterprise (not supported)' ;;
	*) printf '%s' "$1" ;;
	esac
}

# An SSID as it is safe to draw: ASCII control characters become '?', and
# everything else, UTF-8 included, is kept.
wifi_display_name() {
	printf '%s' "${1//[$'\001'-$'\037'$'\177']/?}"
}

# Connects to a network object, from the profile iwd already has (or none, for
# an open network). Prints iwd's error on failure.
wifi_iwd_connect() { # NETWORK-PATH
	local out i
	for ((i = 0; i < 2; i++)); do
		# iwd reads a new profile from its directory as it appears; give it a
		# moment and try once more if it still asks for an agent.
		if out=$(busctl --timeout=60 call "$LYONA_IWD" "$1" "$LYONA_IWD.Network" Connect 2>&1); then
			return 0
		fi
		[[ $out == *NoAgent* || $out == *'No Agent'* ]] || break
		sleep 2
	done
	printf '%s\n' "$out"
	return 1
}

wifi_iwd_connect_hidden() { # STATION SSID
	local out i
	for ((i = 0; i < 2; i++)); do
		if out=$(busctl --timeout=60 call "$LYONA_IWD" "$1" "$LYONA_IWD.Station" ConnectHiddenNetwork s "$2" 2>&1); then
			return 0
		fi
		[[ $out == *NoAgent* || $out == *'No Agent'* ]] || break
		sleep 2
	done
	printf '%s\n' "$out"
	return 1
}

# A PCI network controller with no driver bound, said with its IDs. Broadcom
# chips, such as those in older Macs, may need broadcom-wl, which the medium
# does not carry. Prints nothing when every controller has a driver.
wifi_driver_hint() {
	local dev class vendor device
	for dev in "$LYONA_SYS_PCI"/*; do
		[[ -r $dev/class ]] || continue
		read -r class <"$dev/class" || continue
		[[ $class == 0x0280* ]] || continue
		[[ ! -e $dev/driver && ! -L $dev/driver ]] || continue
		read -r vendor <"$dev/vendor" || vendor=unknown
		read -r device <"$dev/device" || device=unknown
		printf 'A Wi-Fi chip (%s:%s) has no driver on this live medium.\n' "${vendor#0x}" "${device#0x}"
		if [[ $vendor == 0x14e4 ]]; then
			printf 'Broadcom chips, such as those in older Macs, may need broadcom-wl, which this medium does not carry.\n'
		fi
		printf 'Use a wired connection, or USB tethering from a phone, to install.\n'
	done
	return 0
}

# A string as a GLib key-file value: backslashes, control characters and a
# leading space escaped.
wifi_keyfile_escape() {
	local value=${1//\\/\\\\}
	value=${value//$'\n'/\\n}
	value=${value//$'\t'/\\t}
	value=${value//$'\r'/\\r}
	[[ $value != ' '* ]] || value="\\s${value# }"
	printf '%s' "$value"
}

# A NetworkManager keyfile for a WPA-PSK or open network.
wifi_nm_keyfile() { # SSID PASSPHRASE HIDDEN UUID
	local ssid
	ssid=$(wifi_keyfile_escape "$1")
	printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\n\n[wifi]\nmode=infrastructure\nssid=%s\n' \
		"$ssid" "$4" "$ssid"
	if [[ $3 == true ]]; then
		printf 'hidden=true\n'
	fi
	if [[ -n $2 ]]; then
		printf '\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n' "$(wifi_keyfile_escape "$2")"
	fi
	printf '\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n'
}

# The postinstall: the network the live medium is connected to, as a
# NetworkManager profile on the new system, so its first boot is online. Says
# what it did; nothing when the medium is not on Wi-Fi.
wifi_carry_over() { # TARGET
	local objects path ssid type file pass='' hidden=false line key value uuid profile tmp
	command -v busctl >/dev/null 2>&1 || return 0
	objects=$(iwd_objects) || return 0
	[[ -n $objects ]] || return 0
	path=$(jq -r '[.data[0][] | .["net.connman.iwd.Station"].ConnectedNetwork.data // empty] | first // empty' \
		<<<"$objects") || return 0
	[[ -n $path ]] || return 0
	ssid=$(jq -r --arg path "$path" '.data[0][$path]["net.connman.iwd.Network"].Name.data // empty' <<<"$objects") ||
		return 0
	type=$(jq -r --arg path "$path" '.data[0][$path]["net.connman.iwd.Network"].Type.data // empty' <<<"$objects") ||
		return 0
	[[ -n $ssid ]] || return 0
	case $type in
	psk | open) file=$(wifi_profile_path "$ssid" "$type") ;;
	*)
		printf 'The Wi-Fi network uses %s security, which is not carried over; connect again after the first boot.\n' \
			"$(wifi_security_words "$type")"
		return 0
		;;
	esac
	# Read with the read builtin: the passphrase is in no process's arguments.
	# Whole lines, split at the first "=": read with IFS='=' drops a trailing
	# "=" from the value, which a passphrase may end with (#270).
	if [[ -r $file ]]; then
		while IFS= read -r line; do
			key=${line%%=*}
			value=${line#*=}
			case $key in
			Passphrase) pass=$value ;;
			PreSharedKey) [[ -n $pass ]] || pass=$value ;;
			Hidden) [[ $value != true ]] || hidden=true ;;
			esac
		done <"$file"
	fi
	if [[ $type == psk && -z $pass ]]; then
		printf 'No saved passphrase for the Wi-Fi network; connect again after the first boot.\n'
		return 0
	fi
	read -r uuid </proc/sys/kernel/random/uuid || return 1
	profile=$1/etc/NetworkManager/system-connections/lyona-wifi.nmconnection
	tmp=$profile.lyona-tmp
	(
		umask 077
		mkdir -p -- "${profile%/*}" || exit 1
		wifi_nm_keyfile "$ssid" "$pass" "$hidden" "$uuid" >"$tmp" || exit 1
		chown 0:0 -- "$tmp" 2>/dev/null || :
		mv -f -- "$tmp" "$profile"
	) || {
		rm -f -- "$tmp"
		printf 'Could not save the Wi-Fi network for the new system; connect again after the first boot.\n'
		return 1
	}
	printf 'Saved the Wi-Fi network for the new system (NetworkManager).\n'
}
