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

ask_keymap() {
	# shellcheck disable=SC1010
	local options=(us by ca cf cz de dk es et fa fi fr gr hu il it lt lv mk nl no pl ro ru se sg si tr ua uk)
	KEYMAP=$(gum choose "${options[@]}" --header "Select your keyboard layout:") || cancelled
	[[ -n $KEYMAP ]] || cancelled
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
		password1=$(gum input --password --header "LUKS encryption password:") || cancelled
		password2=$(gum input --password --header "Confirm encryption password:") || cancelled
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
		password1=$(gum input --password --header "Password:") || cancelled
		password2=$(gum input --password --header "Confirm password:") || cancelled
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
		name=$(gum input --header "Hostname:" --placeholder "lyona" --value "lyona") || true
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
			--placeholder "e.g. New_York, Berlin, Tokyo") || cancelled
	[[ -n $zone && -f /usr/share/zoneinfo/$zone ]] || fail "unknown timezone: '$zone'"
	printf '%s\n' "$zone"
}

ask_timezone() {
	local detected
	if detected=$(detect_timezone); then
		if gum confirm --affirmative "Yes" --negative "No" "Detected timezone: $detected. Is this correct?"; then
			TIMEZONE=$detected
			return
		fi
	else
		say --foreground "$COLOR_DIM" "Could not detect the timezone from the connection; choose it from the list."
	fi
	TIMEZONE=$(choose_timezone)
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
NVIDIA driver: $(nvidia_summary)
EOF
		)"
	echo
	gum confirm --default=false --affirmative "Wipe $DISK and install" --negative "Cancel" \
		"Proceed?" || cancelled
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
