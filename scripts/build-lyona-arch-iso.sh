#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: sudo scripts/build-lyona-arch-iso.sh [--output DIR] [--version VERSION]

Build a lyona Arch Linux install medium by layering this checkout and
archiso/ onto the system's archiso releng profile, then running mkarchiso.
Requires the archiso package and root (mkarchiso builds as root).

The image carries the release version from config.mk unless --version
overrides it, producing lyona-VERSION-x86_64.iso and recording the build
in /etc/lyona-iso-release on the live medium.

Options:
  --output DIR            Write the ISO to DIR (default: ./out).
  --version VERSION       Stamp VERSION instead of the config.mk VERSION.
                          Accepts 0.1.0 or v0.1.0.
  --profile-only          Stage and stamp the archiso profile under
                          DIR/profile, then stop without running mkarchiso.
                          Does not require root.
  -h, --help              Show this help.

LYONA_RELENG_DIR overrides the archiso releng profile location
(default: /usr/share/archiso/configs/releng).

The live medium auto-logs into a root shell on tty1. After completing a base
Arch install to /mnt (e.g. with `archinstall`), run
/root/lyona-postinstall.sh from that shell to finish installing lyona.

Verified to produce a bootable ISO on Arch Linux. Still needs VM
boot-qualification (base install + first boot) before being treated as
release-ready; see docs/RELEASING.md.
EOF
}

err() {
	printf 'build-lyona-arch-iso: %s\n' "$*" >&2
}

output_dir="$PWD/out"
iso_version=
profile_only=false

while (($# > 0)); do
	case "$1" in
	--output)
		if (($# < 2)); then
			err "--output requires a value."
			exit 1
		fi
		output_dir=$2
		shift 2
		;;
	--output=*)
		output_dir=${1#*=}
		shift
		;;
	--version)
		if (($# < 2)); then
			err "--version requires a value."
			exit 1
		fi
		iso_version=$2
		shift 2
		;;
	--version=*)
		iso_version=${1#*=}
		shift
		;;
	--profile-only)
		profile_only=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		err "unknown argument: $1"
		usage >&2
		exit 1
		;;
	esac
done

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_mk="$repo_dir/config.mk"

if [[ -z $iso_version ]]; then
	[[ -f $config_mk ]] || {
		err "missing config.mk at $config_mk"
		exit 1
	}
	iso_version="$(
		awk -F= '
			$1 ~ /^[[:space:]]*VERSION[[:space:]]*$/ {
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
				print $2
				exit
			}
		' "$config_mk"
	)"
	[[ -n $iso_version ]] || {
		err "could not read VERSION from config.mk"
		exit 1
	}
fi

iso_version=${iso_version#v}
if [[ ! $iso_version =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
	err "version must look like MAJOR.MINOR or MAJOR.MINOR.PATCH: $iso_version"
	exit 1
fi

iso_label="LYONA_${iso_version//./_}"

if [[ $profile_only != true ]]; then
	if [[ $EUID -ne 0 ]]; then
		err "mkarchiso must run as root."
		exit 1
	fi

	command -v mkarchiso >/dev/null 2>&1 || {
		err "mkarchiso not found. Install the archiso package first."
		exit 1
	}
fi

# The palette the boot splash is generated from. The installed system can
# follow the user's chosen theme later; the ISO has no user yet.
splash_palette="${LYONA_SPLASH_PALETTE:-tokyonight}"
releng_dir="${LYONA_RELENG_DIR:-/usr/share/archiso/configs/releng}"
[[ -d $releng_dir ]] || {
	err "releng profile not found at $releng_dir. Reinstall the archiso package."
	exit 1
}

work_dir="$(mktemp -d -p /var/tmp)"
trap 'rm -rf "$work_dir"' EXIT

if [[ $profile_only == true ]]; then
	mkdir -p "$output_dir"
	profile_dir="$output_dir/profile"
	rm -rf "$profile_dir"
else
	profile_dir="$work_dir/profile"
fi

info() { printf 'build-lyona-arch-iso: %s\n' "$*"; }

info "Copying the releng base profile..."
cp -a "$releng_dir" "$profile_dir"

info "Layering lyona packages onto packages.x86_64..."
cat "$repo_dir/archiso/packages.x86_64" >>"$profile_dir/packages.x86_64"
sort -u -o "$profile_dir/packages.x86_64" "$profile_dir/packages.x86_64"

info "Applying lyona pacman.conf..."
cp -f "$repo_dir/archiso/pacman.conf" "$profile_dir/pacman.conf"

info "Rebranding profiledef.sh for lyona $iso_version..."
sed -i \
	-e 's/^iso_name=.*/iso_name="lyona"/' \
	-e "s/^iso_label=.*/iso_label=\"$iso_label\"/" \
	-e "s/^iso_version=.*/iso_version=\"$iso_version\"/" \
	-e 's|^iso_publisher=.*|iso_publisher="lyona <https://github.com/technicks89/dwm-titus>"|' \
	-e "s/^iso_application=.*/iso_application=\"lyona $iso_version Arch Linux install medium\"/" \
	"$profile_dir/profiledef.sh"

for key in iso_name iso_label iso_version iso_application; do
	grep -q "^$key=" "$profile_dir/profiledef.sh" || {
		err "releng profiledef.sh has no $key to rebrand; the archiso profile format changed."
		exit 1
	}
done

info "Quieting the primary boot entries' console output..."
sed -i \
	'/^options.*archisosearchuuid=%ARCHISO_UUID%$/ s/$/ quiet splash loglevel=3 vt.global_cursor_default=0/' \
	"$profile_dir/efiboot/loader/entries/01-archiso-linux.conf"
sed -i \
	'/^APPEND.*archisosearchuuid=%ARCHISO_UUID%$/ s/$/ quiet splash loglevel=3 vt.global_cursor_default=0/' \
	"$profile_dir/syslinux/archiso_sys-linux.cfg"

grep -q 'quiet splash loglevel=3 vt.global_cursor_default=0' "$profile_dir/efiboot/loader/entries/01-archiso-linux.conf" || {
	err "releng's UEFI boot entry has no matching options line to quiet; the archiso profile format changed."
	exit 1
}
grep -q 'quiet splash loglevel=3 vt.global_cursor_default=0' "$profile_dir/syslinux/archiso_sys-linux.cfg" || {
	err "releng's BIOS boot entry has no matching APPEND line to quiet; the archiso profile format changed."
	exit 1
}

info "Booting straight into the installer, without a boot menu..."
# There is one thing to boot on this medium and it launches the installer on
# login, so a menu asking which is a step with no choice in it. Both loaders
# keep an escape hatch: systemd-boot shows the menu if a key is held during
# firmware handover, and the syslinux entries remain defined and reachable
# from its boot prompt.
loader_conf="$profile_dir/efiboot/loader/loader.conf"
grep -q '^timeout ' "$loader_conf" || {
	err "releng's loader.conf has no timeout to remove; the archiso profile format changed."
	exit 1
}
sed -i -e 's/^timeout .*/timeout 0/' -e 's/^beep .*/beep off/' "$loader_conf"
grep -Fqx 'timeout 0' "$loader_conf" || {
	err "the UEFI boot menu timeout was not disabled."
	exit 1
}

# vesamenu.c32 always draws, whatever the timeout, so the menu module itself
# has to go rather than just its countdown.
syslinux_head="$profile_dir/syslinux/archiso_head.cfg"
syslinux_sys="$profile_dir/syslinux/archiso_sys.cfg"
grep -q '^UI vesamenu.c32$' "$syslinux_head" || {
	err "releng's syslinux head has no vesamenu UI line; the archiso profile format changed."
	exit 1
}
grep -q '^TIMEOUT ' "$syslinux_sys" || {
	err "releng's syslinux config has no TIMEOUT to shorten; the archiso profile format changed."
	exit 1
}
sed -i 's/^UI vesamenu.c32$/PROMPT 0/' "$syslinux_head"
sed -i 's/^TIMEOUT .*/TIMEOUT 1/' "$syslinux_sys"
grep -Fqx 'PROMPT 0' "$syslinux_head" || {
	err "the BIOS boot menu was not disabled."
	exit 1
}
grep -Fqx 'TIMEOUT 1' "$syslinux_sys" || {
	err "the BIOS boot menu timeout was not shortened."
	exit 1
}

sed -i '/^file_permissions=($/a\
  ["/root/lyona-postinstall.sh"]="0:0:755"\
  ["/usr/local/bin/lyona-install"]="0:0:755"' \
	"$profile_dir/profiledef.sh"

info "Adding the plymouth hook to the initramfs..."
# Ordered right after udev, which is where plymouth needs to start to own the
# console before the boot messages the entries above just suppressed.
archiso_mkinitcpio="$profile_dir/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
[[ -f $archiso_mkinitcpio ]] || {
	err "releng has no airootfs/etc/mkinitcpio.conf.d/archiso.conf; the archiso profile format changed."
	exit 1
}
grep -q '^HOOKS=(base udev ' "$archiso_mkinitcpio" || {
	err "releng's HOOKS line does not start with base udev; the archiso profile format changed."
	exit 1
}
sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' "$archiso_mkinitcpio"
grep -q '^HOOKS=(base udev plymouth ' "$archiso_mkinitcpio" || {
	err "the plymouth hook was not inserted into the archiso HOOKS line."
	exit 1
}

info "Generating the lyona boot splash from the $splash_palette palette..."
"$repo_dir/scripts/lyona-plymouth-theme" generate "$splash_palette" \
	"$repo_dir/config/themes.toml" "$repo_dir/assets/logo" \
	"$profile_dir/airootfs/usr/share/plymouth/themes/lyona"
install -Dm644 "$repo_dir/archiso/airootfs/etc/plymouth/plymouthd.conf" \
	"$profile_dir/airootfs/etc/plymouth/plymouthd.conf"

info "Suppressing the optical-drive loopback attach on boot..."
install -Dm644 "$repo_dir/archiso/airootfs/etc/udev/rules.d/90-lyona-optical-no-loop.rules" \
	"$profile_dir/airootfs/etc/udev/rules.d/90-lyona-optical-no-loop.rules"

systemd_udev_rules=/usr/lib/udev/rules.d/99-systemd.rules
if [[ -f $systemd_udev_rules ]] &&
	! grep -q 'ID_PART_GPT_AUTO_ROOT_DISK_NEEDS_LOOP' "$systemd_udev_rules"; then
	info "note: this host's systemd no longer keys the optical loopback attach on"
	info "      ID_PART_GPT_AUTO_ROOT_DISK_NEEDS_LOOP; recheck"
	info "      archiso/airootfs/etc/udev/rules.d/90-lyona-optical-no-loop.rules."
fi

info "Embedding this checkout at /root/lyona in the live medium..."
mkdir -p "$profile_dir/airootfs/root"
rsync -a --delete \
	--exclude='.git/' \
	--exclude='.cache/' \
	--exclude='release/' \
	--exclude='config.h' \
	--exclude='*.o' \
	--exclude='dwm' \
	--exclude='out/' \
	--exclude='*.iso' \
	"$repo_dir/" "$profile_dir/airootfs/root/lyona/"

install -Dm755 "$repo_dir/archiso/airootfs/root/lyona-postinstall.sh" \
	"$profile_dir/airootfs/root/lyona-postinstall.sh"

info "Installing shared installer UI helpers..."
install -Dm644 "$repo_dir/archiso/airootfs/root/lyona-ui.sh" \
	"$profile_dir/airootfs/root/lyona-ui.sh"
install -Dm644 "$repo_dir/archiso/airootfs/root/lyona-logo.txt" \
	"$profile_dir/airootfs/root/lyona-logo.txt"

info "Generating the console palette from the $splash_palette palette..."
# The same palette the splash is generated from, so the console the installer
# runs on is a continuation of the boot screen rather than stock VGA.
"$repo_dir/scripts/lyona-console-theme" generate "$splash_palette" \
	"$repo_dir/config/themes.toml" \
	"$profile_dir/airootfs/root/lyona-console.sh"
chmod 644 "$profile_dir/airootfs/root/lyona-console.sh"

info "Installing lyona-install as a live-medium command..."
install -Dm755 "$repo_dir/archiso/airootfs/root/lyona-install.sh" \
	"$profile_dir/airootfs/usr/local/bin/lyona-install"

info "Auto-launching lyona-install on tty1 login..."
cat >>"$profile_dir/airootfs/root/.zlogin" <<'EOF'

if [[ $(tty) == "/dev/tty1" && ! -f /root/.lyona-install-done ]]; then
	# tty1's autologin uses --noclear (releng default, kept so diagnostic
	# text stays visible on ttys/logins this block doesn't cover), so
	# nothing has cleared the kernel/systemd boot text still sitting on
	# screen at this point -- do it here rather than waiting for
	# lyona-install's own first `clear` inside welcome(), which only
	# runs after require_network's curl round-trip.
	clear
	lyona-install
fi
EOF

info "Recording the release stamp at /etc/lyona-iso-release..."
build_commit="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
build_date="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" --utc +%Y-%m-%dT%H:%M:%SZ)"
install -Dm644 /dev/null "$profile_dir/airootfs/etc/lyona-iso-release"
cat >"$profile_dir/airootfs/etc/lyona-iso-release" <<EOF
LYONA_ISO_VERSION=$iso_version
LYONA_ISO_LABEL=$iso_label
LYONA_ISO_COMMIT=$build_commit
LYONA_ISO_BUILD_DATE=$build_date
EOF

if [[ $profile_only == true ]]; then
	info "Done. lyona $iso_version archiso profile is at $profile_dir"
	exit 0
fi

mkdir -p "$output_dir"
info "Running mkarchiso..."
mkarchiso -v -w "$work_dir/build" -o "$output_dir" "$profile_dir"
info "Done. lyona $iso_version ISO is under $output_dir"
