#!/usr/bin/env bash
set -Eeuo pipefail

POSTINSTALL=/root/lyona-postinstall.sh
# The package mirrors (#249): the zoneinfo tables the country comes from, the
# live mirrorlist archinstall copies to the new system, and the marker that
# says it was ranked here.
LYONA_ZONEINFO=${LYONA_ZONEINFO:-/usr/share/zoneinfo}
export LYONA_MIRRORLIST=${LYONA_MIRRORLIST:-/etc/pacman.d/mirrorlist}
export LYONA_MIRRORS_MARKER=${LYONA_MIRRORS_MARKER:-/run/lyona-mirrors-ranked}
# This medium's own pacman configuration, which archinstall downloads with.
LYONA_PACMAN_CONF=${LYONA_PACMAN_CONF:-/etc/pacman.conf}
MIRROR_COUNTRY=
CACHYOS_HELPER=/root/lyona/scripts/lyona-cachyos
CACHYOS_PACKAGES=
export LOG_FILE=${LOG_FILE:-/var/log/lyona-install.log}

err() { printf 'lyona-install: %s\n' "$1" >&2; }
info() { printf 'lyona-install: %s\n' "$1"; }
fail() {
	err "$1"
	exit 1
}

# The wizard was cancelled: nothing has been changed, and it can be run again
# (Sync Sprint 16 R16-30).
cancelled() {
	err "cancelled${1:+ -- $1}. Nothing on the disk was changed; run lyona-install to start again."
	exit 1
}

# shellcheck source=lyona-ui.sh
source "${LYONA_UI_LIB:-/root/lyona-ui.sh}"
# shellcheck source=lyona-nvidia.sh
source "${LYONA_NVIDIA_LIB:-/root/lyona-nvidia.sh}"
# shellcheck source=lyona-wifi.sh
source "${LYONA_WIFI_LIB:-/root/lyona-wifi.sh}"

# GRUB boots both (#235): UEFI, from an EFI system partition, and legacy BIOS,
# from an MBR disk, which archinstall uses when the medium booted without UEFI.
# systemd-boot, before, refused every legacy-BIOS machine.
detect_firmware() {
	if [[ -d /sys/firmware/efi ]]; then
		FIRMWARE=uefi
	else
		FIRMWARE=bios
	fi
}

firmware_summary() {
	if [[ $FIRMWARE == uefi ]]; then
		echo "UEFI (GRUB)"
	else
		echo "legacy BIOS (GRUB)"
	fi
}

network_online() {
	curl -4 -sf -m 5 https://archlinux.org >/dev/null 2>&1
}

# Up to about twenty seconds for DHCP once Wi-Fi is connected.
wait_for_network() {
	local i
	for ((i = 0; i < 10; i++)); do
		network_online && return 0
		sleep 2
	done
	return 1
}

# The passphrase for SSID, on stdout (a pipe, never argv), or a failure when
# the prompt is cancelled.
ask_wifi_passphrase() { # SSID-FOR-DISPLAY
	local passphrase
	while true; do
		passphrase=$(gum input --password --header "Passphrase for $1:") || return 1
		wifi_valid_passphrase "$passphrase" && break
		# To the terminal: stdout is the passphrase.
		say --foreground $COLOR_DANGER "A WPA passphrase is 8 to 63 characters." >&2
	done
	printf '%s' "$passphrase"
}

# Connects to one network from the list. On a wrong passphrase or any other
# failure, the profile written for it is removed, and the reason is in
# WIFI_MESSAGE for the list to show.
connect_wifi_network() { # NETWORK-PATH TYPE
	local path=$1 type=$2 ssid display passphrase profile='' error
	ssid=$(iwd_property "$path" Network Name) || ssid=
	[[ -n $ssid ]] || {
		WIFI_MESSAGE="That network is gone; scan again."
		return 1
	}
	display=$(wifi_display_name "$ssid")
	case $type in
	open) ;;
	psk)
		# A profile from an earlier try (or from iwctl) is used as it is.
		if [[ ! -f $(wifi_profile_path "$ssid" psk) ]]; then
			passphrase=$(ask_wifi_passphrase "$display") || {
				WIFI_MESSAGE=
				return 1
			}
			profile=$(wifi_write_profile "$ssid" "$passphrase" false) || {
				WIFI_MESSAGE="Could not save the passphrase for $display."
				return 1
			}
			passphrase=
		else
			profile=$(wifi_profile_path "$ssid" psk)
		fi
		;;
	*)
		WIFI_MESSAGE="$display uses $(wifi_security_words "$type") security, which the installer cannot set up. Use another network or a wired connection."
		return 1
		;;
	esac
	say "Connecting to $display..."
	if ! error=$(wifi_iwd_connect "$path"); then
		[[ -z $profile ]] || rm -f -- "$profile"
		log_step "wifi: connect failed: ${error//$'\n'/ }"
		WIFI_MESSAGE="Could not connect to $display. Check the passphrase and try again."
		return 1
	fi
	return 0
}

# A network that does not broadcast its name.
connect_hidden_wifi() { # STATION
	local ssid display passphrase profile error
	ssid=$(gum input --header "Network name (SSID):") || return 1
	[[ -n $ssid && ${#ssid} -le 32 ]] || {
		WIFI_MESSAGE="A network name is 1 to 32 characters."
		return 1
	}
	display=$(wifi_display_name "$ssid")
	while true; do
		passphrase=$(gum input --password --header "Passphrase for $display (empty for an open network):") ||
			return 1
		# Empty is an open network.
		if [[ -z $passphrase ]] || wifi_valid_passphrase "$passphrase"; then
			break
		fi
		say --foreground $COLOR_DANGER "A WPA passphrase is 8 to 63 characters."
	done
	profile=$(wifi_write_profile "$ssid" "$passphrase" true) || {
		WIFI_MESSAGE="Could not save the passphrase for $display."
		return 1
	}
	passphrase=
	say "Connecting to $display..."
	if ! error=$(wifi_iwd_connect_hidden "$1" "$ssid"); then
		rm -f -- "$profile"
		log_step "wifi: hidden connect failed: ${error//$'\n'/ }"
		WIFI_MESSAGE="Could not connect to $display. Check the name and the passphrase."
		return 1
	fi
	return 0
}

# Pick a network and connect (#237). Succeeds once connected; fails when the
# user goes back, or when the device has no station (said in WIFI_MESSAGE).
WIFI_MESSAGE=
connect_wifi() {
	local -a interfaces labels rows
	local -A networks=()
	local interface station row path name type signal label choice header
	mapfile -t interfaces < <(wifi_interfaces)
	if ((${#interfaces[@]} > 1)); then
		interface=$(gum choose --header "Which Wi-Fi device?" "${interfaces[@]}") || return 1
	else
		interface=${interfaces[0]}
	fi
	say "Turning on $interface..."
	if ! station=$(wifi_station "$interface"); then
		WIFI_MESSAGE="$interface did not come up for Wi-Fi (iwd has no station for it)."
		return 1
	fi
	WIFI_MESSAGE=
	while true; do
		show_logo
		say "Scanning for Wi-Fi networks..."
		wifi_scan "$station"
		rows=()
		mapfile -t rows < <(wifi_networks "$station" || :)
		labels=()
		networks=()
		for row in "${rows[@]}"; do
			IFS=$'\t' read -r path name type signal <<<"$row"
			[[ -n $path && $signal =~ ^-?[0-9]+$ ]] || continue
			label="$(wifi_display_name "$name")  $(wifi_bars "$signal")  $(wifi_security_words "$type")"
			[[ -z ${networks[$label]:-} ]] || continue
			networks[$label]="$path"$'\t'"$type"
			labels+=("$label")
		done
		labels+=("Other (hidden network)" "Scan again" "Back")
		header="Choose a Wi-Fi network:"
		[[ -z $WIFI_MESSAGE ]] || header="$WIFI_MESSAGE"$'\n\n'"$header"
		show_logo
		choice=$(gum choose --header "$header" "${labels[@]}") || return 1
		WIFI_MESSAGE=
		case $choice in
		"Scan again") continue ;;
		Back) return 1 ;;
		"Other (hidden network)")
			connect_hidden_wifi "$station" && return 0
			continue
			;;
		esac
		row=${networks[$choice]:-}
		[[ -n $row ]] || continue
		connect_wifi_network "${row%%$'\t'*}" "${row#*$'\t'}" && return 0
	done
}

require_network() {
	local choice has_wifi hint
	while ! network_online; do
		show_logo
		say --foreground $COLOR_DANGER --bold "No internet connection detected."
		say "archinstall needs working internet to download packages, and this wizard"
		say "uses it to auto-detect your timezone."
		echo
		say --foreground $COLOR_DIM "Current network interfaces:"
		ip -br addr 2>/dev/null | while IFS= read -r line; do
			say --foreground $COLOR_DIM "  $line"
		done
		echo
		has_wifi=false
		[[ -z $(wifi_interfaces) ]] || has_wifi=true
		if [[ -n $WIFI_MESSAGE ]]; then
			say --foreground $COLOR_DANGER "$WIFI_MESSAGE"
			echo
			WIFI_MESSAGE=
		fi
		if $has_wifi; then
			say "Wired: check the cable is plugged in, or wait a moment for DHCP."
			echo
			choice=$(gum choose --header "What would you like to do?" \
				"Connect to Wi-Fi" "Retry" "Continue without internet") || cancelled "no internet connection"
			case $choice in
			"Connect to Wi-Fi")
				log_step "wifi: connecting"
				WIFI_MESSAGE=
				if connect_wifi; then
					log_step "wifi: connected"
					show_logo
					say "Connected. Waiting for an address..."
					wait_for_network || :
				fi
				continue
				;;
			Retry) continue ;;
			esac
		else
			say "Wired: check the cable is plugged in, or wait a moment for DHCP."
			hint=$(wifi_driver_hint)
			if [[ -n $hint ]]; then
				echo
				while IFS= read -r line; do
					say --foreground $COLOR_DANGER "$line"
				done <<<"$hint"
			fi
			echo
			if gum confirm "Retry the connectivity check now?"; then
				continue
			fi
		fi
		gum confirm --default=false "Continue without confirmed internet access?" && return 0
		$has_wifi && continue
		cancelled "no internet connection"
	done
}

welcome() {
	show_logo
	say "Let's set up your machine. A handful of questions, then a fully"
	say "automated install: disk, base Arch (via archinstall), and lyona"
	say "itself. No desktop-environment picker -- this always installs lyona."
	echo
}

# The common keyboard layouts, by name, then every console keymap (#265). The
# codes are console keymaps, which is what archinstall's kb_layout takes.
KEYMAP_NAMES=(
	"us|English (US)" "uk|English (UK)" "de|German" "de-latin1|German (latin1)"
	"fr|French" "fr-latin1|French (latin1)" "be-latin1|Belgian" "es|Spanish"
	"la-latin1|Latin American" "it|Italian" "pt-latin1|Portuguese"
	"br-abnt2|Portuguese (Brazil)" "ca|Canadian (multilingual)" "cf|Canadian French"
	"sg|Swiss German" "fr_CH|Swiss French" "nl|Dutch" "dk|Danish" "no|Norwegian"
	"sv-latin1|Swedish" "fi|Finnish" "pl|Polish" "cz|Czech" "hu|Hungarian"
	"ro|Romanian" "gr|Greek" "ru|Russian" "ua|Ukrainian" "by|Belarusian"
	"trq|Turkish" "il|Hebrew" "fa|Persian" "et|Estonian" "lt|Lithuanian"
	"lv|Latvian" "slovene|Slovenian" "mk|Macedonian" "jp106|Japanese"
	"dvorak|Dvorak (US)" "colemak|Colemak (US)"
)

keymap_options() {
	local entry
	for entry in "${KEYMAP_NAMES[@]}"; do
		printf '%s (%s)\n' "${entry#*|}" "${entry%%|*}"
	done
	localectl list-keymaps 2>/dev/null || :
}

# The layout is applied to this console at once: the disk and user passwords
# below are typed with it, as they will be at the LUKS prompt and the login
# screen. Typed with US keys instead, they would differ there.
ask_keymap() {
	local choice known
	while true; do
		choice=$(keymap_options | gum filter --header "Keyboard layout (type to search):" \
			--placeholder "e.g. German, French, dvorak, fr") || cancelled
		case $choice in
		*" ("*")") KEYMAP=${choice##* (} KEYMAP=${KEYMAP%)} ;;
		*) KEYMAP=$choice ;;
		esac
		known=$(localectl list-keymaps 2>/dev/null || :)
		if [[ $KEYMAP =~ ^[A-Za-z0-9_.-]+$ ]] && { [[ -z $known ]] || grep -Fxq -- "$KEYMAP" <<<"$known"; }; then
			break
		fi
		say --foreground $COLOR_DANGER "$KEYMAP is not a keyboard layout on this medium; choose another."
	done
	apply_keymap
}

apply_keymap() {
	if loadkeys "$KEYMAP" >/dev/null 2>&1; then
		say --foreground $COLOR_DIM "Keyboard set to $KEYMAP: the passwords below are typed with it."
	else
		say --foreground $COLOR_DANGER "Could not switch this console to $KEYMAP. Type the passwords below as on a US keyboard, or choose another layout."
	fi
}

ask_disk() {
	local -a disks
	local exclude_disk=""

	if [[ -d /run/archiso/bootmnt ]]; then
		local boot_src
		boot_src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
		if [[ -n $boot_src ]]; then
			exclude_disk=$(lsblk -no PKNAME "$boot_src" 2>/dev/null || true)
		fi
	fi

	mapfile -t disks < <(lsblk -dn --output PATH,SIZE,MODEL -e 7,11 |
		awk -v excl="$exclude_disk" '{dev=$1; sub("^/dev/", "", dev); if (dev != excl) print}')

	if ((${#disks[@]} == 0)); then
		fail "no candidate disks found."
	fi

	say --foreground $COLOR_DANGER --bold "THIS WILL FORMAT AND ERASE ALL DATA ON THE SELECTED DISK."
	local choice
	choice=$(gum choose "${disks[@]}" --header "Select the disk to install on:") || cancelled
	[[ -n $choice ]] || cancelled
	DISK=$(awk '{print $1}' <<<"$choice")
}

ask_filesystem() {
	local choice
	choice=$(gum choose \
		"btrfs (default)" "ext4" "btrfs + LUKS encryption" "ext4 + LUKS encryption" \
		--header "Select the root filesystem:") || cancelled
	case $choice in
	"btrfs (default)")
		FILESYSTEM=btrfs
		ENCRYPT=0
		;;
	ext4)
		FILESYSTEM=ext4
		ENCRYPT=0
		;;
	"btrfs + LUKS encryption")
		FILESYSTEM=btrfs
		ENCRYPT=1
		;;
	"ext4 + LUKS encryption")
		FILESYSTEM=ext4
		ENCRYPT=1
		;;
	*) cancelled ;;
	esac

	[[ $ENCRYPT == 1 ]] && ask_encryption_password
	return 0
}

ask_encryption_password() {
	local password1 password2

	while true; do
		password1=$(gum input --password --header "LUKS encryption password (keyboard: $KEYMAP):") || cancelled
		password2=$(gum input --password --header "Confirm encryption password (keyboard: $KEYMAP):") || cancelled
		[[ -n $password1 && $password1 == "$password2" ]] && break
		say --foreground $COLOR_DANGER "passwords empty or did not match"
	done
	ENCRYPTION_PASSWORD=$password1
}

ask_user_creds() {
	local username password1 password2

	while true; do
		username=$(gum input --header "Username:") || cancelled
		[[ $username =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
		say --foreground $COLOR_DANGER "invalid username: $username"
	done
	USERNAME=$username

	while true; do
		password1=$(gum input --password --header "Password (keyboard: $KEYMAP):") || cancelled
		password2=$(gum input --password --header "Confirm password (keyboard: $KEYMAP):") || cancelled
		[[ -n $password1 && $password1 == "$password2" ]] && break
		say --foreground $COLOR_DANGER "passwords empty or did not match"
	done
	PASSWORD=$password1
}

# An RFC 1123 host name: dot-separated labels of 1 to 63 letters, digits and
# hyphens, neither starting nor ending with a hyphen, 253 characters in all. It
# goes into the archinstall configuration and /etc/hostname (Sync Sprint 16
# R16-17).
valid_hostname() {
	local label
	local -a labels
	((${#1} >= 1 && ${#1} <= 253)) || return 1
	# The whole string, before read splits it: read stops at a newline.
	[[ $1 =~ ^[A-Za-z0-9.-]+$ ]] || return 1
	[[ $1 != .* && $1 != *. && $1 != *..* ]] || return 1
	IFS=. read -r -a labels <<<"$1"
	for label in "${labels[@]}"; do
		[[ $label =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || return 1
	done
}

ask_hostname() {
	local name
	while true; do
		name=$(gum input --header "Hostname:" --placeholder "lyona" --value "lyona") || cancelled
		name=${name:-lyona}
		valid_hostname "$name" && break
		say --foreground $COLOR_DANGER "invalid hostname: use letters, digits and hyphens (not at either end), up to 63 per part"
	done
	HOSTNAME=$name
}

# The timezone, detected from the connection and confirmed with a yes or no
# (decision R16-19). One service alone failed too often: ipapi.co answers 429
# when its free tier is used up, and the wizard then fell back to tzselect's
# numbered menus. Each provider is tried in turn, over HTTPS, and only a zone
# this medium knows is offered.
detect_timezone() {
	local url zone
	for url in https://ipinfo.io/timezone https://ipapi.co/timezone; do
		zone=$(curl -sfm 5 "$url" 2>/dev/null) || continue
		zone=${zone//[[:space:]]/}
		[[ -n $zone && $zone != *..* && -f /usr/share/zoneinfo/$zone ]] || continue
		printf '%s\n' "$zone"
		return 0
	done
	return 1
}

# Every zone, to type a few letters of and pick.
choose_timezone() {
	local zone
	zone=$(timedatectl list-timezones 2>/dev/null |
		gum filter --header "Type to find your timezone (a city or region):" \
			--placeholder "e.g. New_York, Berlin, Tokyo") || return 1
	[[ -n $zone && -f /usr/share/zoneinfo/$zone ]] || fail "unknown timezone: '$zone'"
	printf '%s\n' "$zone"
}

# Esc in the list goes back to the detected timezone's question (#266); with
# nothing detected there is nothing to go back to, and it cancels.
ask_timezone() {
	local detected zone
	detected=$(detect_timezone) || detected=
	while true; do
		if [[ -n $detected ]]; then
			if gum confirm --affirmative "Yes" --negative "No" "Detected timezone: $detected. Is this correct?"; then
				TIMEZONE=$detected
				return
			fi
		else
			say --foreground "$COLOR_DIM" "Could not detect the timezone from the connection; choose it from the list."
		fi
		if zone=$(choose_timezone); then
			TIMEZONE=$zone
			return
		fi
		[[ -n $detected ]] || cancelled
	done
}

# timezone_country ZONE: the country package mirrors are chosen from (#249),
# as an ISO 3166 code. zone.tab names one country per zone; a zone only in
# zone1970.tab, which can name several, gives its first. Nothing for a zone with
# no country, such as UTC or Etc/*.
timezone_country() {
	local code table
	for table in zone.tab zone1970.tab; do
		code=$(awk -F'\t' -v zone="$1" '!/^#/ && $3 == zone { print $1; exit }' \
			"$LYONA_ZONEINFO/$table" 2>/dev/null) || code=
		[[ -n $code ]] && break
	done
	code=${code%%,*}
	[[ $code =~ ^[A-Z]{2}$ ]] || return 1
	printf '%s\n' "$code"
}

# country_name CODE: "Germany", from iso3166.tab; the code itself if it is not
# listed there.
country_name() {
	local name
	name=$(awk -F'\t' -v code="$1" '$1 == code { print $2; exit }' "$LYONA_ZONEINFO/iso3166.tab" 2>/dev/null) || name=
	printf '%s\n' "${name:-$1}"
}

mirror_summary() {
	if [[ -n $MIRROR_COUNTRY ]]; then
		echo "$(country_name "$MIRROR_COUNTRY") ($MIRROR_COUNTRY), the fastest of them"
	else
		echo "worldwide, the fastest from here"
	fi
}

# Every country, to type a few letters of and pick, or worldwide.
choose_mirror_country() {
	local choice
	choice=$({
		echo "Worldwide"
		awk -F'\t' '!/^#/ && NF >= 2 { print $2 " (" $1 ")" }' "$LYONA_ZONEINFO/iso3166.tab" 2>/dev/null | sort
	} | gum filter --header "Type to find the country to download packages from:" \
		--placeholder "e.g. Germany, Japan") || return 1
	case $choice in
	Worldwide) MIRROR_COUNTRY= ;;
	*" ("[A-Z][A-Z]")") MIRROR_COUNTRY=${choice: -3:2} ;;
	*) return 1 ;;
	esac
}

# The package mirrors, from the confirmed timezone's country (#249). A slow or
# distant mirror slows every download of the install, which is most of it.
# Esc in the country list goes back to the question (#266).
ask_mirrors() {
	local question status country
	country=$(timezone_country "$TIMEZONE") || country=
	if [[ -n $country ]]; then
		question="Download packages from mirrors in $(country_name "$country")?"
	else
		question="Download packages from the fastest mirrors worldwide?"
	fi
	while true; do
		MIRROR_COUNTRY=$country
		status=0
		gum confirm --affirmative "Yes" --negative "Choose another" "$question" || status=$?
		case $status in
		0) return 0 ;;
		1) choose_mirror_country && return 0 ;;
		*) cancelled ;;
		esac
	done
}

# rank_mirrors [COUNTRY]: the live mirrorlist, replaced by the fastest recently
# synced HTTPS mirrors in COUNTRY, as measured from here. Worldwide ones are
# added after them when the country has fewer than three, and used alone with no
# country. Each ranking is bounded to 30 seconds. Never fails: without a usable
# result the mirrorlist the medium booted with stays, with a warning.
rank_mirrors() {
	local country=${1:-} work list=() count=0
	local -a args=(--protocol https --age 24 --latest 20 --sort rate --threads 10
		--connection-timeout 5 --download-timeout 5)
	command -v reflector >/dev/null 2>&1 || {
		printf 'lyona-install: reflector is not on this medium; keeping the current mirrorlist.\n'
		return 0
	}
	work=$(mktemp -d) || return 0
	if [[ -n $country ]]; then
		printf 'Ranking the mirrors in %s...\n' "$country"
		timeout 30 reflector "${args[@]}" --country "$country" --save "$work/country" ||
			printf 'lyona-install: ranking the mirrors in %s failed.\n' "$country"
		[[ -s $work/country ]] && list+=("$work/country")
		count=$(cat "${list[@]}" /dev/null | grep -c '^Server = ') || count=0
	fi
	if ((count < 3)); then
		[[ -z $country ]] || printf 'Only %s mirrors in %s; adding the fastest worldwide.\n' "$count" "$country"
		timeout 30 reflector "${args[@]}" --save "$work/world" ||
			printf 'lyona-install: ranking the worldwide mirrors failed.\n'
		[[ -s $work/world ]] && list+=("$work/world")
	fi
	# One list, the country's first, each server once.
	cat "${list[@]}" /dev/null | awk '/^Server = / && !seen[$0]++' >"$work/mirrorlist"
	count=$(grep -c '^Server = ' "$work/mirrorlist") || count=0
	if ((count == 0)); then
		printf 'lyona-install: no mirrors were ranked; keeping the current mirrorlist.\n'
		rm -rf -- "$work"
		return 0
	fi
	{
		printf '# Ranked by lyona-install (reflector, %s) on %s.\n' "${country:-worldwide}" "$(date -u +%F)"
		cat "$work/mirrorlist"
	} >"$work/out"
	install -m 0644 "$work/out" "$LYONA_MIRRORLIST"
	: >"$LYONA_MIRRORS_MARKER"
	rm -rf -- "$work"
	printf 'Using %s ranked mirrors, fastest first.\n' "$count"
}
export -f rank_mirrors

# Ten downloads at a time on this medium (#249), as on the new system. The
# medium's /etc/pacman.conf is the pacman package's own, with 5:
# archiso/pacman.conf configures only the image build. It is this live system's
# file, gone at the reboot, never the user's.
use_parallel_downloads() {
	[[ -w $LYONA_PACMAN_CONF ]] || return 0
	if grep -Eq '^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=' "$LYONA_PACMAN_CONF"; then
		sed -i -E 's/^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=.*/ParallelDownloads = 10/' \
			"$LYONA_PACMAN_CONF" || return 0
	else
		sed -i 's/^\[options\]$/&\nParallelDownloads = 10/' "$LYONA_PACMAN_CONF" || return 0
	fi
	log_step "ParallelDownloads = 10 in $LYONA_PACMAN_CONF"
}

# One image for every GPU (D-17a, Sync Sprint 12 S12-17): on an NVIDIA GPU a
# packaged driver supports, the proprietary driver is the recommended choice and
# nouveau the alternative. Which driver comes from the card's device ID (Sync
# Sprint 14 S14-02): nvidia-open, or the legacy 580xx or 470xx driver for an
# older card. A card no packaged driver supports keeps nouveau without asking.
# Like every other prompt here, a dismissed or failed prompt aborts.
ask_nvidia() {
	NVIDIA_OPT_IN=0
	NVIDIA_DETECTED=0
	NVIDIA_BRANCH=
	command -v lspci >/dev/null 2>&1 || return 0
	if ! lspci | grep -E "VGA|3D|Display" | grep -qE "NVIDIA|GeForce"; then
		return 0
	fi
	NVIDIA_DETECTED=1
	read -r NVIDIA_BRANCH _ < <(nvidia_gpu_branch || printf 'unsupported\n')
	[[ $NVIDIA_BRANCH != unsupported ]] || return 0

	local choice proprietary="nvidia (proprietary, recommended)"
	[[ $NVIDIA_BRANCH == open ]] ||
		proprietary="nvidia $NVIDIA_BRANCH (proprietary legacy driver, recommended)"
	choice=$(gum choose "$proprietary" "nouveau (open-source)" \
		--header "NVIDIA GPU detected. Select driver:") || cancelled
	case $choice in
	"$proprietary") NVIDIA_OPT_IN=1 ;;
	"nouveau (open-source)") ;;
	*) cancelled ;;
	esac
	return 0
}

nvidia_summary() {
	if [[ ${NVIDIA_DETECTED:-0} != 1 ]]; then
		echo "not needed (no NVIDIA GPU detected)"
	elif [[ $NVIDIA_OPT_IN == 1 && $NVIDIA_BRANCH == open ]]; then
		echo "proprietary (recommended)"
	elif [[ $NVIDIA_OPT_IN == 1 ]]; then
		echo "proprietary $NVIDIA_BRANCH legacy driver (from CachyOS, or built from the AUR)"
	elif [[ $NVIDIA_BRANCH == unsupported ]]; then
		echo "nouveau (no packaged NVIDIA driver supports this GPU)"
	else
		echo "nouveau"
	fi
}

show_summary() {
	gum style --border rounded --border-foreground $COLOR_ACCENT \
		--margin "0 0 0 $PADDING_LEFT" --padding "1 2" "$(
			cat <<EOF
Disk:       $DISK (ALL DATA ON THIS DISK WILL BE ERASED)
Filesystem: $FILESYSTEM$([[ $ENCRYPT == 1 ]] && echo " (LUKS encrypted)")
Hostname:   $HOSTNAME
Username:   $USERNAME
Keyboard:   $KEYMAP
Timezone:   $TIMEZONE
Mirrors:    $(mirror_summary)
Boot:       $(firmware_summary)
NVIDIA driver: $(nvidia_summary)
EOF
		)"
	echo
}

# The summary, until it is confirmed: any answer can be changed there (#266),
# instead of cancelling and answering everything again. Cancel is first, so
# Enter alone never wipes the disk.
confirm_and_proceed() {
	local choice
	while true; do
		show_summary
		choice=$(gum choose --header "Proceed?" "Cancel" "Change an answer..." "Wipe $DISK and install") ||
			cancelled
		case $choice in
		"Wipe $DISK and install") return 0 ;;
		"Change an answer...") change_answer ;;
		*) cancelled ;;
		esac
		show_logo
	done
}

# One answer asked again; Esc goes back to the summary.
change_answer() {
	local field
	field=$(gum choose --header "Which answer?" "Keyboard" "Disk" "Filesystem" "User and password" \
		"Hostname" "Timezone" "Mirrors" "NVIDIA driver") || return 0
	show_logo
	case $field in
	Keyboard)
		ask_keymap
		# Typed with the old layout, they would differ at login.
		say "Type the passwords again with the new layout."
		[[ $ENCRYPT != 1 ]] || ask_encryption_password
		ask_user_creds
		;;
	Disk) ask_disk ;;
	Filesystem) ask_filesystem ;;
	"User and password") ask_user_creds ;;
	Hostname) ask_hostname ;;
	Timezone)
		ask_timezone
		# The mirrors come from the timezone's country.
		ask_mirrors
		;;
	Mirrors) ask_mirrors ;;
	"NVIDIA driver") ask_nvidia ;;
	esac
}

setup_cachyos_repositories() {
	CACHYOS_PACKAGES=

	if [[ ! -x $CACHYOS_HELPER ]]; then
		info "CachyOS helper not found at $CACHYOS_HELPER; installing from the stock Arch repositories."
		return 0
	fi

	# Adding the repositories here rather than after the install means
	# pacstrap fetches the optimized packages directly, instead of installing
	# Arch builds and replacing them afterwards. pacstrap verifies signatures
	# against this medium's keyring, which is where add-repos puts the key.
	if ! run_logged "Adding the CachyOS repositories..." \
		env LYONA_CACHYOS_NONINTERACTIVE=1 "$CACHYOS_HELPER" add-repos --no-upgrade; then
		say --foreground $COLOR_DANGER \
			"CachyOS repository setup failed; continuing with the stock Arch repositories."
		return 0
	fi

	# The installed system inherits this medium's pacman.conf, so it needs the
	# mirrorlists those repository sections include, and the keyring package
	# whose install scriptlet populates its own keyring.
	CACHYOS_PACKAGES='"cachyos-keyring", "cachyos-mirrorlist", "cachyos-v3-mirrorlist", "cachyos-v4-mirrorlist"'
	return 0
}

# The one kernel archinstall installs (#246): linux-cachyos when the CachyOS
# repositories were set up above, so the new system never carries the stock
# kernel beside it; the stock linux otherwise. Microcode is archinstall's own:
# it adds intel-ucode or amd-ucode with the base system on real hardware, before
# the first initramfs, and none in a virtual machine.
base_kernel() {
	if [[ -n $CACHYOS_PACKAGES ]]; then
		echo linux-cachyos
	else
		echo linux
	fi
}

generate_configs() {
	WORK_DIR=$(mktemp -d)
	# It holds the credentials file: removed however the run ends (#266).
	LYONA_CLEANUP_FILES+=("$WORK_DIR")
	CONFIG_JSON="$WORK_DIR/config.json"
	CREDS_JSON="$WORK_DIR/creds.json"

	local disk_bytes root_size_mib
	disk_bytes=$(blockdev --getsize64 "$DISK")
	root_size_mib=$((disk_bytes / 1024 / 1024 - 513 - 4))
	if ((root_size_mib < 4096)); then
		fail "$DISK is too small (need at least ~4.5GiB)."
	fi

	# /boot, outside any encryption, where GRUB reads the kernels: the EFI system
	# partition on UEFI, an ext4 partition on legacy BIOS.
	local boot_fs=fat32 boot_flags='["boot", "esp"]'
	if [[ $FIRMWARE == bios ]]; then
		boot_fs=ext4
		boot_flags='["boot"]'
	fi

	local pass_hash
	# The password on stdin, never in argv, where other processes can read it.
	pass_hash=$(printf '%s\n' "$PASSWORD" | openssl passwd -6 -stdin)

	local esp_id root_id
	esp_id=$(cat /proc/sys/kernel/random/uuid)
	root_id=$(cat /proc/sys/kernel/random/uuid)

	local disk_encryption_json=""
	if [[ $ENCRYPT == 1 ]]; then
		read -r -d '' disk_encryption_json <<EOF || true
  "disk_encryption": {
    "encryption_type": "luks",
    "partitions": ["$root_id"],
    "lvm_volumes": []
  },
EOF
	fi

	cat >"$CONFIG_JSON" <<EOF
{
  "archinstall-language": "English",
  "audio_config": {"audio": "pipewire"},
  "bootloader_config": {"bootloader": "Grub", "uki": false, "removable": true},
  "debug": false,
  "disk_config": {
    "config_type": "default_layout",
    "device_modifications": [
      {
        "device": "$DISK",
        "wipe": true,
        "partitions": [
          {
            "status": "create",
            "type": "primary",
            "fs_type": "$boot_fs",
            "flags": $boot_flags,
            "mountpoint": "/boot",
            "mount_options": [],
            "btrfs": [],
            "dev_path": null,
            "obj_id": "$esp_id",
            "start": {"unit": "MiB", "value": 1, "sector_size": {"value": 512, "unit": "B"}},
            "size": {"unit": "MiB", "value": 512, "sector_size": {"value": 512, "unit": "B"}}
          },
          {
            "status": "create",
            "type": "primary",
            "fs_type": "$FILESYSTEM",
            "flags": [],
            "mountpoint": "/",
            "mount_options": [],
            "btrfs": [],
            "dev_path": null,
            "obj_id": "$root_id",
            "start": {"unit": "MiB", "value": 513, "sector_size": {"value": 512, "unit": "B"}},
            "size": {"unit": "MiB", "value": $root_size_mib, "sector_size": {"value": 512, "unit": "B"}}
          }
        ]
      }
    ]
  },
${disk_encryption_json}  "hostname": "$HOSTNAME",
  "kernels": ["$(base_kernel)"],
  "locale_config": {"kb_layout": "$KEYMAP", "sys_enc": "UTF-8", "sys_lang": "en_US"},
  "mirror_config": {
    "mirror_regions": {},
    "custom_servers": [],
    "optional_repositories": ["multilib"],
    "custom_repositories": []
  },
  "network_config": {"type": "nm"},
  "no_pkg_lookups": false,
  "ntp": true,
  "offline": false,
  "packages": [$CACHYOS_PACKAGES],
  "pacman_config": {"color": true, "parallel_downloads": 10},
  "swap": {"enabled": true, "algorithm": "zstd"},
  "timezone": "$TIMEZONE",
  "version": "4.4"
}
EOF

	write_credentials_json "$pass_hash" >"$CREDS_JSON"
}

# The credentials archinstall reads, built by jq rather than by interpolation
# (Sync Sprint 12 S12-11): a passphrase with a '"' broke the file, and one with a
# backslash escape silently became a different passphrase, which locked the user
# out of the new install. Every value is a jq string, never parsed as JSON. The
# hash and the disk passphrase come in on stdin, NUL-separated, so they are
# never in argv, where any process can read them; the username is not secret.
write_credentials_json() {
	local encrypt=false
	[[ $ENCRYPT != 1 ]] || encrypt=true
	printf '%s\0%s' "$1" "${ENCRYPTION_PASSWORD:-}" |
		jq -Rs --arg user "$USERNAME" --argjson encrypt "$encrypt" '
			split("\u0000") as [$hash, $passphrase]
			| {users: [{sudo: true, username: $user, enc_password: $hash}]}
			+ (if $encrypt then {encryption_password: $passphrase} else {} end)'
}

# What archinstall left mounted or open on the disk, released before a retry.
release_target() {
	local name type
	umount -R /mnt 2>/dev/null || :
	while read -r name type; do
		[[ $type != crypt ]] || cryptsetup close "$name" 2>/dev/null || :
	done < <(lsblk -nrpo NAME,TYPE -- "$DISK" 2>/dev/null || :)
}

# archinstall until it has installed the base system on /mnt. A failure shows
# the recovery menu (#266), with what state the disk is in; Retry runs it again
# with the same answers, not the whole wizard.
run_archinstall() {
	local status
	LYONA_RECOVER_HINT="$DISK may already be erased and partly installed; nothing else on this machine was changed. Retry runs archinstall again with your answers. archinstall's own log: /var/log/archinstall/install.log"
	while true; do
		status=0
		run_logged "Running archinstall (this can take several minutes)..." \
			archinstall --config "$CONFIG_JSON" --creds "$CREDS_JSON" --silent --skip-version-check ||
			status=$?
		if ((status == 0)) && mountpoint -q /mnt; then
			break
		fi
		if ((status == 0)); then
			err "/mnt is not mounted after archinstall."
			status=1
		else
			err "archinstall failed (exit $status)."
		fi
		lyona_recover_menu "$status"
		release_target
	done
	rm -rf "$WORK_DIR"
	LYONA_RECOVER_HINT=
}

main() {
	require_gum
	: >"$LOG_FILE"
	install_error_trap "$@"
	reset_step_times

	detect_firmware
	command -v archinstall >/dev/null 2>&1 || fail "archinstall not found on this live medium."
	[[ -x $POSTINSTALL ]] || fail "$POSTINSTALL not found or not executable."

	apply_console_theme
	# The first screen, straight after the splash: the network check can take
	# a few seconds, which used to leave the console blank.
	show_logo
	say --foreground $COLOR_DIM "Checking the network connection..."
	log_step "require_network"
	require_network
	log_step "require_network done"

	log_step "welcome"
	welcome
	log_step "ask_keymap"
	ask_keymap
	log_step "ask_keymap done: KEYMAP=$KEYMAP"

	show_logo
	log_step "ask_disk"
	ask_disk
	log_step "ask_disk done: DISK=$DISK"

	show_logo
	log_step "ask_filesystem"
	ask_filesystem
	log_step "ask_filesystem done: FILESYSTEM=$FILESYSTEM ENCRYPT=$ENCRYPT"

	show_logo
	log_step "ask_user_creds"
	ask_user_creds
	log_step "ask_user_creds done: USERNAME=$USERNAME"

	show_logo
	log_step "ask_hostname"
	ask_hostname
	log_step "ask_hostname done: HOSTNAME=$HOSTNAME"

	show_logo
	log_step "ask_timezone"
	ask_timezone
	log_step "ask_timezone done: TIMEZONE=$TIMEZONE"

	show_logo
	log_step "ask_mirrors"
	ask_mirrors
	log_step "ask_mirrors done: MIRROR_COUNTRY=${MIRROR_COUNTRY:-worldwide}"

	show_logo
	log_step "ask_nvidia"
	ask_nvidia
	log_step "ask_nvidia done: NVIDIA_OPT_IN=$NVIDIA_OPT_IN"

	show_logo
	log_step "confirm_and_proceed"
	confirm_and_proceed
	log_step "confirm_and_proceed done"

	# Before anything is downloaded: archinstall, and the new system after it, use
	# this medium's mirrorlist.
	use_parallel_downloads
	run_logged "Choosing the fastest package mirrors..." rank_mirrors "$MIRROR_COUNTRY"

	log_step "setup_cachyos_repositories"
	setup_cachyos_repositories
	log_step "setup_cachyos_repositories done: packages=${CACHYOS_PACKAGES:-none}"

	log_step "generate_configs"
	generate_configs
	log_step "generate_configs done"

	log_step "run_archinstall"
	run_archinstall

	touch /root/.lyona-install-done

	info "base install complete. Finishing the lyona install..."
	if [[ $NVIDIA_OPT_IN == 1 ]]; then
		export LYONA_NVIDIA_DRIVER=1
	fi
	exec "$POSTINSTALL"
}

if [[ ${LYONA_INSTALL_LIB:-0} != 1 ]]; then
	main "$@"
fi
