#!/usr/bin/env bash
set -Eeuo pipefail

POSTINSTALL=/root/lyona-postinstall.sh
CACHYOS_HELPER=/root/lyona/scripts/lyona-cachyos
CACHYOS_PACKAGES=
export LOG_FILE=/var/log/lyona-install.log

err() { printf 'lyona-install: %s\n' "$1" >&2; }
info() { printf 'lyona-install: %s\n' "$1"; }
fail() {
	err "$1"
	exit 1
}

# shellcheck source=lyona-ui.sh
source "${LYONA_UI_LIB:-/root/lyona-ui.sh}"

require_uefi() {
	if [[ ! -d /sys/firmware/efi ]]; then
		fail "this machine booted in BIOS/legacy mode. lyona-install requires UEFI (it installs systemd-boot). Use 'archinstall' followed by '$POSTINSTALL' instead -- see docs/RELEASING.md."
	fi
}

require_network() {
	while ! curl -4 -sf -m 5 https://archlinux.org >/dev/null 2>&1; do
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
		say "Wired: check the link is attached, or wait a moment for DHCP."
		say "Wi-Fi: Ctrl+C to drop to a shell, run iwctl (station <dev> connect <SSID>),"
		say "then re-run lyona-install."
		echo
		if gum confirm "Retry the connectivity check now?"; then
			continue
		fi
		gum confirm --default=false "Continue without confirmed internet access?" && return 0
		fail "aborted -- no internet connection."
	done
}

welcome() {
	show_logo
	say "Let's set up your machine. A handful of questions, then a fully"
	say "automated install: disk, base Arch (via archinstall), and lyona"
	say "itself. No desktop-environment picker -- this always installs lyona."
	echo
}

ask_keymap() {
	# shellcheck disable=SC1010
	local options=(us by ca cf cz de dk es et fa fi fr gr hu il it lt lv mk nl no pl ro ru se sg si tr ua uk)
	KEYMAP=$(gum choose "${options[@]}" --header "Select your keyboard layout:") || fail "aborted."
	[[ -n $KEYMAP ]] || fail "aborted."
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
	choice=$(gum choose "${disks[@]}" --header "Select the disk to install on:") || fail "aborted."
	[[ -n $choice ]] || fail "aborted."
	DISK=$(awk '{print $1}' <<<"$choice")
}

ask_filesystem() {
	local choice
	choice=$(gum choose \
		"btrfs (default)" "ext4" "btrfs + LUKS encryption" "ext4 + LUKS encryption" \
		--header "Select the root filesystem:") || fail "aborted."
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
	*) fail "aborted." ;;
	esac

	[[ $ENCRYPT == 1 ]] && ask_encryption_password
	return 0
}

ask_encryption_password() {
	local password1 password2

	while true; do
		password1=$(gum input --password --header "LUKS encryption password:") || fail "aborted."
		password2=$(gum input --password --header "Confirm encryption password:") || fail "aborted."
		[[ -n $password1 && $password1 == "$password2" ]] && break
		say --foreground $COLOR_DANGER "passwords empty or did not match"
	done
	ENCRYPTION_PASSWORD=$password1
}

ask_user_creds() {
	local username password1 password2

	while true; do
		username=$(gum input --header "Username:") || fail "aborted."
		[[ $username =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
		say --foreground $COLOR_DANGER "invalid username: $username"
	done
	USERNAME=$username

	while true; do
		password1=$(gum input --password --header "Password:") || fail "aborted."
		password2=$(gum input --password --header "Confirm password:") || fail "aborted."
		[[ -n $password1 && $password1 == "$password2" ]] && break
		say --foreground $COLOR_DANGER "passwords empty or did not match"
	done
	PASSWORD=$password1
}

ask_hostname() {
	local name
	name=$(gum input --header "Hostname:" --placeholder "lyona" --value "lyona") || true
	HOSTNAME=${name:-lyona}
}

ask_timezone() {
	local detected curl_status=0
	detected=$(curl -sfm 5 https://ipapi.co/timezone) || curl_status=$?

	if [[ $curl_status != 0 ]]; then
		say --foreground $COLOR_DANGER \
			"Could not reach https://ipapi.co (curl exit $curl_status) -- no network yet, or it's unreachable. Opening manual timezone selection."
	elif [[ -z $detected ]]; then
		say --foreground $COLOR_DANGER \
			"Timezone lookup returned an empty response. Opening manual timezone selection."
	elif [[ ! -f /usr/share/zoneinfo/$detected ]]; then
		say --foreground $COLOR_DANGER \
			"Timezone lookup returned '$detected', which isn't a recognized zone. Opening manual timezone selection."
	elif gum confirm "Detected timezone: '$detected'. Is this correct?"; then
		TIMEZONE=$detected
		return
	fi

	TIMEZONE=$(tzselect) || fail "aborted."
	[[ -n $TIMEZONE && -f /usr/share/zoneinfo/$TIMEZONE ]] || fail "unknown timezone: '$TIMEZONE'"
}

ask_nvidia() {
	NVIDIA_OPT_IN=0
	command -v lspci >/dev/null 2>&1 || return 0
	if ! lspci | grep -E "VGA|3D|Display" | grep -qE "NVIDIA|GeForce"; then
		return 0
	fi

	local choice
	choice=$(gum choose \
		"nouveau (open-source, default)" "nvidia (proprietary)" \
		--header "NVIDIA GPU detected. Select driver:") || true
	[[ $choice == "nvidia (proprietary)" ]] && NVIDIA_OPT_IN=1
	return 0
}

confirm_and_proceed() {
	gum style --border rounded --border-foreground $COLOR_ACCENT \
		--margin "0 0 0 $PADDING_LEFT" --padding "1 2" "$(
			cat <<EOF
Disk:       $DISK (ALL DATA ON THIS DISK WILL BE ERASED)
Filesystem: $FILESYSTEM$([[ $ENCRYPT == 1 ]] && echo " (LUKS encrypted)")
Hostname:   $HOSTNAME
Username:   $USERNAME
Keyboard:   $KEYMAP
Timezone:   $TIMEZONE
NVIDIA driver: $([[ $NVIDIA_OPT_IN == 1 ]] && echo "proprietary (opt-in)" || echo "nouveau (default)")
EOF
		)"
	echo
	gum confirm --default=false --affirmative "Wipe $DISK and install" --negative "Cancel" \
		"Proceed?" || fail "aborted."
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

generate_configs() {
	WORK_DIR=$(mktemp -d)
	CONFIG_JSON="$WORK_DIR/config.json"
	CREDS_JSON="$WORK_DIR/creds.json"

	local disk_bytes root_size_mib
	disk_bytes=$(blockdev --getsize64 "$DISK")
	root_size_mib=$((disk_bytes / 1024 / 1024 - 513 - 4))
	if ((root_size_mib < 4096)); then
		fail "$DISK is too small (need at least ~4.5GiB)."
	fi

	local pass_hash
	pass_hash=$(openssl passwd -6 "$PASSWORD")

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
  "bootloader_config": {"bootloader": "Systemd-boot", "uki": false, "removable": false},
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
            "fs_type": "fat32",
            "flags": ["boot", "esp"],
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
  "kernels": ["linux"],
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
  "pacman_config": {"color": true, "parallel_downloads": 5},
  "swap": {"enabled": true, "algorithm": "zstd"},
  "timezone": "$TIMEZONE",
  "version": "4.4"
}
EOF

	cat >"$CREDS_JSON" <<EOF
{
  "users": [{"sudo": true, "username": "$USERNAME", "enc_password": "$pass_hash"}],
  "root_enc_password": "$pass_hash"$([[ $ENCRYPT == 1 ]] && printf ',\n  "encryption_password": "%s"' "$ENCRYPTION_PASSWORD")
}
EOF
}

run_archinstall() {
	local status=0
	run_logged "Running archinstall (this can take several minutes)..." \
		archinstall --config "$CONFIG_JSON" --creds "$CREDS_JSON" --silent --skip-version-check ||
		status=$?

	((status == 0)) || fail "archinstall failed. Log: $LOG_FILE (archinstall's own log: /var/log/archinstall/install.log)"
	rm -rf "$WORK_DIR"
}

main() {
	require_gum
	: >"$LOG_FILE"
	install_error_trap "$@"

	require_uefi
	command -v archinstall >/dev/null 2>&1 || fail "archinstall not found on this live medium."
	[[ -x $POSTINSTALL ]] || fail "$POSTINSTALL not found or not executable."

	apply_console_theme
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
	log_step "ask_nvidia"
	ask_nvidia
	log_step "ask_nvidia done: NVIDIA_OPT_IN=$NVIDIA_OPT_IN"

	show_logo
	log_step "confirm_and_proceed"
	confirm_and_proceed
	log_step "confirm_and_proceed done"

	log_step "setup_cachyos_repositories"
	setup_cachyos_repositories
	log_step "setup_cachyos_repositories done: packages=${CACHYOS_PACKAGES:-none}"

	log_step "generate_configs"
	generate_configs
	log_step "generate_configs done"

	log_step "run_archinstall"
	run_archinstall

	if ! mountpoint -q /mnt; then
		fail "/mnt is not mounted after archinstall; not running the lyona install. Run $POSTINSTALL manually once /mnt is ready."
	fi

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
