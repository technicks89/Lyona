#!/usr/bin/env bash
set -Eeuo pipefail

# The Raspberry Pi image's first boot (ARM3-02). The image is lyona installed
# without a user (scripts/build-lyona-rpi-image.sh); this runs once, as root,
# on tty1, before LightDM (lyona-firstboot.service):
#   1. the machine's own state: the root partition grown to the card, the
#      pacman keyring and the SSH host keys made for this machine;
#   2. the install medium's questions (archiso/airootfs/root/lyona-install.sh,
#      loaded as a library): keymap, network (Wi-Fi through NetworkManager),
#      user and password, hostname, timezone;
#   3. the answers applied, the user created in wheel, and lyona's per-user
#      half installed as that user, from the image's copy of the source;
#   4. the done marker, and the unit disabled. LightDM starts only once the
#      marker exists.
# An interrupted run starts again at the next boot: the user a run created
# is removed first, so nothing is left half-made.

LYONA_SRC=${LYONA_SRC:-/usr/local/src/lyona}
# Every file this writes is under FB_ROOT, which the tests set; empty on a Pi.
FB_ROOT=${LYONA_FIRSTBOOT_ROOT:-}
FB_STATE=$FB_ROOT/var/lib/lyona
FB_DONE=$FB_STATE/firstboot-done
# The user this run created, until the run is done.
FB_PENDING_USER=$FB_STATE/firstboot-user
FB_SELF=${LYONA_FIRSTBOOT_SELF:-$0}
FB_SYS_BLOCK=${LYONA_SYS_BLOCK:-/sys/class/block}
export LOG_FILE=${LOG_FILE:-/var/log/lyona-firstboot.log}

wizard_dir=$LYONA_SRC/archiso/airootfs/root
export LYONA_UI_LIB=${LYONA_UI_LIB:-$wizard_dir/lyona-ui.sh}
export LYONA_NVIDIA_LIB=${LYONA_NVIDIA_LIB:-$wizard_dir/lyona-nvidia.sh}
export LYONA_WIFI_LIB=${LYONA_WIFI_LIB:-$wizard_dir/lyona-wifi.sh}
export LYONA_LOGO_PATH=${LYONA_LOGO_PATH:-$wizard_dir/lyona-logo.txt}
export LYONA_CONSOLE_THEME=${LYONA_CONSOLE_THEME:-/usr/local/lib/lyona/firstboot-console.sh}
# shellcheck source=archiso/airootfs/root/lyona-install.sh
LYONA_INSTALL_LIB=1 source "${LYONA_WIZARD_LIB:-$wizard_dir/lyona-install.sh}"

# The wizard's own words are about a disk that is not touched until the end;
# here an answer can always be given again.
cancelled() {
	err "cancelled${1:+ -- $1}. Starting the questions again."
	exec "$FB_SELF"
}

# --- 1. This machine's own state ------------------------------------------------

# The root partition, to the end of the card or drive. The image's is just
# large enough for its files. Nothing when it already fills the disk.
grow_root() {
	local source partition disk number start size disk_size
	source=$(findmnt -no SOURCE /) || return 1
	partition=${source##*/}
	disk=$(lsblk -no PKNAME "$source") || return 1
	[[ -n $disk ]] || return 1
	number=$(<"$FB_SYS_BLOCK/$partition/partition")
	start=$(<"$FB_SYS_BLOCK/$partition/start")
	size=$(<"$FB_SYS_BLOCK/$partition/size")
	disk_size=$(<"$FB_SYS_BLOCK/$disk/size")
	# Sectors of 512 bytes: less than 16 MiB left over is full.
	if ((disk_size - start - size < 32768)); then
		printf 'The root partition already fills /dev/%s.\n' "$disk"
		return 0
	fi
	printf 'Growing /dev/%s to the end of /dev/%s...\n' "$partition" "$disk"
	printf ', +\n' | sfdisk --no-reread --no-tell-kernel -N "$number" "/dev/$disk"
	partx -u -n "$number" "/dev/$disk"
	resize2fs "$source"
}

# pacman's keyring, made here so each Pi has its own master key: the image
# ships none (ARM3-01, F-1). Then Arch Linux ARM's keys, which its packages are
# signed with.
make_keyring() {
	if [[ ! -s $FB_ROOT/etc/pacman.d/gnupg/pubring.gpg && ! -s $FB_ROOT/etc/pacman.d/gnupg/pubring.kbx ]]; then
		pacman-key --init
	fi
	pacman-key --populate archlinuxarm
}

make_machine_state() {
	run_logged "Growing the root partition to the card..." grow_root
	run_logged "Making this Pi's package keyring..." make_keyring
	if command -v ssh-keygen >/dev/null 2>&1; then
		run_logged "Making this Pi's SSH host keys..." ssh-keygen -A
	fi
	# systemd makes the machine-id itself when the file says uninitialized;
	# this is for a boot where that did not happen.
	if [[ ! -s $FB_ROOT/etc/machine-id || $(<"$FB_ROOT/etc/machine-id") == uninitialized ]]; then
		systemd-machine-id-setup
	fi
}

# A run that stopped after it created its user: that user, and its sudo rule,
# are removed, and the questions asked again.
undo_half_made_user() {
	local user
	[[ -s $FB_PENDING_USER ]] || return 0
	user=$(<"$FB_PENDING_USER")
	if [[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && getent passwd "$user" >/dev/null 2>&1; then
		printf 'Removing %s, which an interrupted first boot created...\n' "$user"
		userdel -r "$user" || :
	fi
	rm -f -- "$FB_PENDING_USER"
}

# --- 2. The questions --------------------------------------------------------------

# Wi-Fi through NetworkManager, which the Pi runs; the install medium's wizard
# talks to iwd. The same screens: a network from the scan, or a hidden one; the
# passphrase never in a process's arguments (a keyfile, as wifi_carry_over
# writes one).
LYONA_NM_PROFILE=${LYONA_NM_PROFILE:-$FB_ROOT/etc/NetworkManager/system-connections/lyona-wifi.nmconnection}

# The scan, as SSID<TAB>SIGNAL<TAB>SECURITY lines: nmcli's terse output with
# its escaped colons and backslashes undone.
nm_wifi_networks() {
	local line field
	local -a fields
	nmcli -t -e yes -f SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null |
		while IFS= read -r line; do
			line=${line//\\\\/$'\x1e'}
			line=${line//\\:/$'\x1f'}
			IFS=: read -r -a fields <<<"$line"
			for field in "${!fields[@]}"; do
				fields[field]=${fields[field]//$'\x1f'/:}
				fields[field]=${fields[field]//$'\x1e'/\\}
			done
			[[ -n ${fields[0]:-} ]] || continue
			printf '%s\t%s\t%s\n' "${fields[0]}" "${fields[1]:-0}" "${fields[2]:-}"
		done
}

# nmcli's SECURITY column as the wizard's type: open, psk, or unsupported.
nm_security_type() {
	case $1 in
	'' | -- | none) printf 'open' ;;
	*802.1X* | *EAP*) printf '8021x' ;;
	*WPA* | *SAE*) printf 'psk' ;;
	*WEP*) printf 'wep' ;;
	*) printf '%s' "$1" ;;
	esac
}

# Writes the profile and brings it up. On a failure the profile is removed and
# the reason left in WIFI_MESSAGE.
nm_connect() { # SSID PASSPHRASE HIDDEN
	local uuid tmp=$LYONA_NM_PROFILE.lyona-tmp
	read -r uuid </proc/sys/kernel/random/uuid || return 1
	(
		umask 077
		mkdir -p -- "${LYONA_NM_PROFILE%/*}" || exit 1
		wifi_nm_keyfile "$1" "$2" "$3" "$uuid" >"$tmp" || exit 1
		mv -f -- "$tmp" "$LYONA_NM_PROFILE"
	) || {
		rm -f -- "$tmp"
		WIFI_MESSAGE="Could not save the Wi-Fi network."
		return 1
	}
	say "Connecting to $(wifi_display_name "$1")..."
	if nmcli connection load "$LYONA_NM_PROFILE" >/dev/null 2>&1 &&
		nmcli --wait 30 connection up uuid "$uuid" >/dev/null 2>&1; then
		return 0
	fi
	nmcli connection delete uuid "$uuid" >/dev/null 2>&1 || :
	rm -f -- "$LYONA_NM_PROFILE"
	WIFI_MESSAGE="Could not connect to $(wifi_display_name "$1"). Check the name and the passphrase."
	return 1
}

connect_wifi() {
	local -a rows labels
	local -A networks=()
	local row ssid signal security type label choice header pass
	WIFI_MESSAGE=
	while true; do
		show_logo
		say "Scanning for Wi-Fi networks..."
		mapfile -t rows < <(nm_wifi_networks || :)
		labels=()
		networks=()
		for row in "${rows[@]}"; do
			IFS=$'\t' read -r ssid signal security <<<"$row"
			[[ $signal =~ ^[0-9]+$ ]] || signal=0
			type=$(nm_security_type "$security")
			label="$(wifi_display_name "$ssid")  ${signal}%  $(wifi_security_words "$type")"
			[[ -z ${networks[$label]:-} ]] || continue
			networks[$label]="$ssid"$'\t'"$type"
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
			ssid=$(gum input --header "Network name (SSID):") || continue
			[[ -n $ssid ]] || continue
			choice=$(gum choose --header "Security for $(wifi_display_name "$ssid"):" \
				"WPA passphrase" "Open network") || continue
			pass=
			if [[ $choice == "WPA passphrase" ]]; then
				pass=$(ask_wifi_passphrase "$(wifi_display_name "$ssid")") || continue
			fi
			nm_connect "$ssid" "$pass" true && return 0
			continue
			;;
		esac
		row=${networks[$choice]:-}
		[[ -n $row ]] || continue
		ssid=${row%%$'\t'*}
		type=${row#*$'\t'}
		case $type in
		open) pass= ;;
		psk) pass=$(ask_wifi_passphrase "$(wifi_display_name "$ssid")") || continue ;;
		*)
			WIFI_MESSAGE="$(wifi_display_name "$ssid") uses $(wifi_security_words "$type") security; choose another network."
			continue
			;;
		esac
		nm_connect "$ssid" "$pass" false && return 0
	done
}

firstboot_welcome() {
	show_logo
	say "Welcome to lyona on your Raspberry Pi. A few questions, then lyona"
	say "finishes setting up, and the login screen comes up."
	echo
}

firstboot_summary() {
	show_logo
	say --bold "Ready to set up lyona:"
	say "  Keyboard:  $KEYMAP"
	say "  User:      $USERNAME (an administrator, through sudo)"
	say "  Hostname:  $HOSTNAME"
	say "  Timezone:  $TIMEZONE"
	say "  Wi-Fi country: $(wifi_country_summary "$TIMEZONE")"
	echo
	gum confirm --affirmative "Set up" --negative "Change the answers" "Set up lyona with these answers?"
}

ask_questions() {
	apply_console_theme
	show_logo
	say --foreground "$COLOR_DIM" "Checking the network connection..."
	log_step "require_network"
	require_network
	firstboot_welcome
	log_step "ask_keymap"
	ask_keymap
	show_logo
	log_step "ask_user_creds"
	ask_user_creds
	show_logo
	log_step "ask_hostname"
	ask_hostname
	show_logo
	log_step "ask_timezone"
	ask_timezone
	log_step "summary"
	firstboot_summary || cancelled
}

# --- 3. The answers, and the user ---------------------------------------------------

# The Wi-Fi regulatory country, from the timezone (#365), in the file the
# install medium's postinstall writes (set_wifi_country).
set_regdom() {
	local country conf=$FB_ROOT/etc/modprobe.d/lyona-regdom.conf
	country=$(timezone_country "$TIMEZONE") || country=
	if [[ -z $country ]]; then
		rm -f -- "$conf"
		return 0
	fi
	install -d -m 0755 "${conf%/*}"
	printf '# Written by the lyona installer: the Wi-Fi regulatory country (#365).\noptions cfg80211 ieee80211_regdom=%s\n' \
		"$country" >"$conf"
	chmod 0644 "$conf"
}

apply_system_answers() {
	# Console and X11 alike: localectl converts the console keymap.
	localectl set-keymap "$KEYMAP"
	hostnamectl set-hostname "$HOSTNAME"
	timedatectl set-timezone "$TIMEZONE"
	timedatectl set-ntp true
	set_regdom
}

# The user, an administrator through wheel, as archinstall's sudo: true is on
# the install medium. The password goes to chpasswd on stdin.
create_user() {
	local rule=$FB_ROOT/etc/sudoers.d/10-lyona-wheel
	mkdir -p -- "$FB_STATE"
	printf '%s\n' "$USERNAME" >"$FB_PENDING_USER"
	useradd -m -G wheel -s /bin/bash "$USERNAME"
	printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
	if [[ ! -f $rule ]]; then
		install -d -m 0750 "${rule%/*}"
		printf '%s\n' '# Written by the lyona first boot: members of wheel administer through sudo.' \
			'%wheel ALL=(ALL:ALL) ALL' >"$rule.lyona-tmp"
		chmod 0440 "$rule.lyona-tmp"
		visudo -cf "$rule.lyona-tmp" >/dev/null
		mv -f -- "$rule.lyona-tmp" "$rule"
	fi
}

as_user() {
	runuser -u "$USERNAME" -- env -u DBUS_SESSION_BUS_ADDRESS \
		HOME="$USER_HOME" USER="$USERNAME" LOGNAME="$USERNAME" "$@"
}

# install.sh's wallpapers, from its own pinned repository and commit (the same
# fetch, beside the folder, then moved in whole).
user_wallpapers() {
	local url ref
	url=$(awk -F'"' '$1 == "WALLPAPERS_URL=" { print $2; exit }' "$LYONA_SRC/install.sh")
	ref=$(awk -F'"' '$1 == "WALLPAPERS_REF=" { print $2; exit }' "$LYONA_SRC/install.sh")
	[[ -n $url && -n $ref ]] || return 1
	# shellcheck disable=SC2016 # expanded by the user's shell
	as_user bash -c '
		set -e
		bg=$HOME/Pictures/backgrounds
		[[ ! -d $bg ]] || exit 0
		mkdir -p "$HOME/Pictures"
		tmp=$(mktemp -d "$HOME/Pictures/.wallpapers.XXXXXX")
		trap "rm -rf -- \"\$tmp\"" EXIT
		git -C "$tmp" init --quiet
		git -C "$tmp" fetch --quiet --depth 1 "$1" "$2"
		git -C "$tmp" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
		rm -rf -- "$tmp/.git"
		mv -- "$tmp" "$bg"
		trap - EXIT
	' bash "$url" "$ref"
}

# lyona's per-user half, as install.sh's full profile does it in the home: the
# prompt (mybash), the user folders, the wallpapers, then make install-user,
# which lyona-update also runs. The source is the user's own copy, where
# install.sh keeps it (~/.local/src/lyona).
install_user_half() {
	local checkout commit profile
	USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
	[[ -n $USER_HOME && -d $USER_HOME ]] || return 1
	export USER_HOME
	checkout=$USER_HOME/.local/src/lyona
	as_user mkdir -p "$USER_HOME/.local/src" "$USER_HOME/.config" "$USER_HOME/.local/state/lyona"
	rm -rf -- "$checkout"
	cp -a -- "$LYONA_SRC" "$checkout"
	chown -R "$USERNAME:" -- "$checkout"
	commit=$(awk -F= '$1 == "LYONA_ISO_COMMIT" { print $2; exit }' "$FB_ROOT/etc/lyona-iso-release" 2>/dev/null) ||
		commit=
	profile=$(awk -F= '$1 == "LYONA_INSTALL_PROFILE" { print $2; exit }' "$FB_ROOT/etc/lyona-iso-release" 2>/dev/null) ||
		profile=
	if ! run_logged "Setting up the shell prompt..." as_user "$checkout/scripts/install-mybash"; then
		note_firstboot_warning "The shell prompt (mybash) was not set up; after logging in, run ~/.local/src/lyona/scripts/install-mybash."
	fi
	as_user xdg-user-dirs-update || :
	if ! run_logged "Downloading the wallpapers..." user_wallpapers; then
		note_firstboot_warning "The wallpapers were not downloaded; add your own to ~/Pictures/backgrounds."
	fi
	# The build, as install.sh does it before make install-user: config.h from
	# the defaults, then make, which builds the helpers install-user uses
	# (lyona-toml: without it the theme step failed, ARM3-02).
	run_logged "Building lyona for $USERNAME..." as_user bash -c \
		'cd "$1" && scripts/configure-build.sh --non-interactive && make clean && make' bash "$checkout"
	# The profile the image was built with, recorded for the account as
	# install.sh records it (#273): make install-user reads it back, and without
	# it treated a full image's account as recommended (found on the Pi 4).
	if [[ -z $profile ]] ||
		! run_logged "Recording the $profile profile..." as_user \
			XDG_CONFIG_HOME="$USER_HOME/.config" XDG_DATA_HOME="$USER_HOME/.local/share" \
			XDG_STATE_HOME="$USER_HOME/.local/state" "$checkout/scripts/lyona-reconcile-user" --profile "$profile"; then
		note_firstboot_warning "The install profile was not recorded; after logging in, run ~/.local/src/lyona/scripts/lyona-reconcile-user --profile full."
	fi
	run_logged "Installing lyona for $USERNAME..." as_user make -C "$checkout" install-user \
		USER_HOME="$USER_HOME" OWNER="$USERNAME" \
		XDG_CONFIG_HOME="$USER_HOME/.config" XDG_DATA_HOME="$USER_HOME/.local/share" \
		XDG_STATE_HOME="$USER_HOME/.local/state" LYONA_SOURCE=iso LYONA_COMMIT="${commit:-unknown}"
	# The first keys, shown once at the first login (#295).
	as_user touch "$USER_HOME/.local/state/lyona/first-login-keys"
}

FB_WARNINGS=()
note_firstboot_warning() {
	FB_WARNINGS+=("$1")
	log_step "warning: $1"
}

# --- 4. Done ----------------------------------------------------------------------

finish() {
	mkdir -p -- "$FB_STATE"
	: >"$FB_DONE"
	rm -f -- "$FB_PENDING_USER"
	systemctl disable lyona-firstboot.service
	show_logo
	say --foreground "$COLOR_OK" --bold "lyona is set up. The login screen comes up next."
	local warning
	for warning in "${FB_WARNINGS[@]}"; do
		say --foreground "$COLOR_DANGER" "  $warning"
	done
	if ((${#FB_WARNINGS[@]} > 0)); then
		sleep "${LYONA_FIRSTBOOT_WARNING_SECONDS:-10}"
	fi
}

# A failure after the questions: the same run again, or power off. Either way
# the next start removes the half-made user first.
firstboot_failed() {
	local choice
	trap - ERR
	show_logo
	say --foreground "$COLOR_DANGER" --bold "Setting up lyona failed."
	say "The details are in $LOG_FILE."
	echo
	choice=$(gum choose --header "What would you like to do?" "Start again" "Power off") || choice="Start again"
	if [[ $choice == "Power off" ]]; then
		systemctl poweroff
		exit 1
	fi
	exec "$FB_SELF"
}

main() {
	if [[ -e $FB_DONE ]]; then
		printf 'lyona-firstboot: already done (%s).\n' "$FB_DONE"
		systemctl disable lyona-firstboot.service || :
		return 0
	fi
	require_gum
	: >>"$LOG_FILE"
	undo_half_made_user
	make_machine_state
	ask_questions
	trap firstboot_failed ERR
	# run_logged runs each step in a new bash: what the steps use is exported.
	# Not the password: create_user runs here, so it is in no process's
	# arguments or environment.
	export KEYMAP HOSTNAME TIMEZONE USERNAME
	run_logged "Applying the keyboard, hostname and timezone..." apply_system_answers
	create_user
	install_user_half
	trap - ERR
	finish
}

export FB_ROOT FB_STATE FB_SYS_BLOCK LYONA_SRC LYONA_ZONEINFO
export -f grow_root make_keyring apply_system_answers set_regdom timezone_country as_user user_wallpapers

if [[ ${LYONA_FIRSTBOOT_LIB:-0} != 1 ]]; then
	main "$@"
fi
