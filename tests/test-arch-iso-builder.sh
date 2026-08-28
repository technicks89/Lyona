#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

# shellcheck source=scripts/dwm-utils.sh
# shellcheck disable=SC1091
source "$repo/scripts/dwm-utils.sh"
# shellcheck source=scripts/dwm-packages.sh
# shellcheck disable=SC1091
source "$repo/scripts/dwm-packages.sh"

mapfile -t expected < <(
	{
		dwm_packages arch required
		dwm_packages arch desktop
		dwm_packages arch iso
	} | awk 'NF' | sort -u
)
mapfile -t actual < <(awk 'NF' "$repo/archiso/packages.x86_64" | sort -u)

if [[ "${expected[*]}" != "${actual[*]}" ]]; then
	printf 'archiso/packages.x86_64 is out of sync with the arch required+desktop package map.\n' >&2
	printf 'Regenerate with:\n' >&2
	printf '  source scripts/dwm-packages.sh && { dwm_packages arch required; dwm_packages arch desktop; dwm_packages arch iso; } | sort -u > archiso/packages.x86_64\n' >&2
	exit 1
fi

bash -n "$repo/archiso/airootfs/root/lyona-postinstall.sh"
[[ -x "$repo/archiso/airootfs/root/lyona-postinstall.sh" ]]

bash -n "$repo/archiso/airootfs/root/lyona-install.sh"
[[ -x "$repo/archiso/airootfs/root/lyona-install.sh" ]]

postinstall="$repo/archiso/airootfs/root/lyona-postinstall.sh"

# shellcheck disable=SC2016 # the literal shell source text is what we look for

grep -Fq 'install -Dm755 "$REPO_SRC/scripts/lyona-cachyos" "$TARGET$CACHYOS_HELPER"' \
	"$postinstall" || {
	printf 'lyona-postinstall.sh does not install the CachyOS helper into the target.\n' >&2
	exit 1
}
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq '"$CACHYOS_HELPER" add-repos' "$postinstall" || {
	printf 'lyona-postinstall.sh does not add the CachyOS repositories.\n' >&2
	exit 1
}
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq '"$CACHYOS_HELPER" install-kernel "${kernels[@]}"' "$postinstall" || {
	printf 'lyona-postinstall.sh does not install the CachyOS kernel.\n' >&2
	exit 1
}

# The repositories go on before archinstall runs, so pacstrap fetches the
# optimized packages once instead of installing Arch builds and replacing them.
installer="$repo/archiso/airootfs/root/lyona-install.sh"
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq '"$CACHYOS_HELPER" add-repos --no-upgrade' "$installer" || {
	printf 'lyona-install.sh does not add the CachyOS repositories before archinstall.\n' >&2
	exit 1
}
setup_line=$(grep -n 'setup_cachyos_repositories$' "$installer" | tail -1 | cut -d: -f1)
archinstall_line=$(grep -n '^	run_archinstall$' "$installer" | tail -1 | cut -d: -f1)
[[ -n $setup_line && -n $archinstall_line && $setup_line -lt $archinstall_line ]] || {
	printf 'the CachyOS repository step must run before archinstall.\n' >&2
	exit 1
}
for package in cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist; do
	grep -Fq "$package" "$installer" || {
		printf 'lyona-install.sh does not carry %s onto the installed system.\n' \
			"$package" >&2
		exit 1
	}
done
# A pacman.conf that Includes a missing file fails to parse, so the
# mirrorlists must reach the target even if the package has not landed yet.
grep -Fq 'cachyos*-mirrorlist' "$postinstall" || {
	printf 'lyona-postinstall.sh does not carry the CachyOS mirrorlists onto the target.\n' >&2
	exit 1
}
grep -Fq 'pacman-key --populate cachyos' "$postinstall" || {
	printf 'lyona-postinstall.sh does not populate the target CachyOS keyring.\n' >&2
	exit 1
}

iso_kernels=$(awk -F'"' '/^export CACHYOS_KERNELS=/{print $2; exit}' "$postinstall")
for kernel in linux-cachyos linux-cachyos-lts; do
	case " $iso_kernels " in
	*" $kernel "*) ;;
	*)
		printf 'lyona-postinstall.sh does not install %s (kernels: %s).\n' \
			"$kernel" "$iso_kernels" >&2
		exit 1
		;;
	esac
done

step_total=$(awk '/^set_total_steps /{print $2; exit}' "$postinstall")
step_calls=$(grep -c '^run_logged ' "$postinstall")
[[ $step_total == "$step_calls" ]] || {
	printf 'lyona-postinstall.sh reports %s steps but runs %s.\n' "$step_total" "$step_calls" >&2
	exit 1
}

cachyos_step=$(grep -n '^run_logged "Installing the CachyOS kernel' "$postinstall" | cut -d: -f1)
gpu_step=$(grep -n '^run_logged "Installing GPU drivers' "$postinstall" | cut -d: -f1)
[[ -n $cachyos_step && -n $gpu_step && $cachyos_step -lt $gpu_step ]] || {
	printf 'the CachyOS kernel must be installed before the GPU drivers so DKMS builds for it.\n' >&2
	exit 1
}

# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'nvidia-dkms nvidia-utils "${headers[@]}"' "$postinstall" || {
	printf 'lyona-postinstall.sh does not build the NVIDIA driver for every installed kernel.\n' >&2
	exit 1
}

awk '
	/^\[multilib\]$/ { found = 1; next }
	found && /^Include = \/etc\/pacman.d\/mirrorlist$/ { ok = 1 }
	END { exit !ok }
' "$repo/archiso/pacman.conf" || {
	printf 'archiso/pacman.conf does not enable [multilib] for the installed system.\n' >&2
	exit 1
}

installer_bin="$work/installer-bin"
mkdir -p "$installer_bin"
cat >"$installer_bin/blockdev" <<'EOF'
#!/bin/sh
printf '%s\n' 68719476736
EOF
cat >"$installer_bin/openssl" <<'EOF'
#!/bin/sh
printf '%s\n' '$6$stub$hash'
EOF
chmod +x "$installer_bin/blockdev" "$installer_bin/openssl"

generate_installer_configs() {
	local encrypt=$1 out_dir=$2
	mkdir -p "$out_dir"
	PATH="$installer_bin:$PATH" \
		LYONA_INSTALL_LIB=1 \
		LYONA_UI_LIB="$repo/archiso/airootfs/root/lyona-ui.sh" \
		ENCRYPT="$encrypt" OUT_DIR="$out_dir" \
		TEST_CACHYOS_PACKAGES="${cachyos_packages:-}" \
		bash -c '
			source "$1"
			DISK=/dev/sda
			CACHYOS_PACKAGES=$TEST_CACHYOS_PACKAGES
			FILESYSTEM=btrfs
			HOSTNAME=lyona
			USERNAME=tester
			PASSWORD=secret
			KEYMAP=us
			TIMEZONE=UTC
			ENCRYPTION_PASSWORD=luks-secret
			generate_configs
			cp "$CONFIG_JSON" "$OUT_DIR/config.json"
			cp "$CREDS_JSON" "$OUT_DIR/creds.json"
			rm -rf "$WORK_DIR"
		' sh "$repo/archiso/airootfs/root/lyona-install.sh"
}

for encrypt in 0 1; do
	config_dir="$work/installer-config-$encrypt"
	cachyos_packages='"cachyos-keyring", "cachyos-mirrorlist"' \
		generate_installer_configs "$encrypt" "$config_dir"

	python3 -m json.tool "$config_dir/config.json" >/dev/null || {
		printf 'lyona-install generated invalid archinstall JSON (ENCRYPT=%s).\n' "$encrypt" >&2
		cat "$config_dir/config.json" >&2
		exit 1
	}
	python3 -m json.tool "$config_dir/creds.json" >/dev/null || {
		printf 'lyona-install generated invalid credentials JSON (ENCRYPT=%s).\n' "$encrypt" >&2
		exit 1
	}

	python3 - "$config_dir/config.json" "$encrypt" <<'EOF' || exit 1
import json
import sys

config = json.load(open(sys.argv[1]))
encrypt = sys.argv[2] == "1"
repos = config.get("mirror_config", {}).get("optional_repositories", [])
if "multilib" not in repos:
	print("archinstall config does not request the multilib repository", file=sys.stderr)
	sys.exit(1)
mirror_config = config["mirror_config"]
if mirror_config.get("mirror_regions") or mirror_config.get("custom_servers"):
	print("archinstall config must not override the live mirrorlist", file=sys.stderr)
	sys.exit(1)
if encrypt != ("disk_encryption" in config):
	print("disk_encryption does not follow the ENCRYPT selection", file=sys.stderr)
	sys.exit(1)
if "cachyos-keyring" not in config.get("packages", []):
	print("the CachyOS packages did not reach the archinstall config", file=sys.stderr)
	sys.exit(1)
EOF
done

bash -n "$repo/scripts/build-lyona-arch-iso.sh"

"$repo/scripts/build-lyona-arch-iso.sh" --help >"$work/help.out"
grep -Fq 'Usage: sudo scripts/build-lyona-arch-iso.sh' "$work/help.out"
grep -Fq -- '--version VERSION' "$work/help.out"
grep -Fq -- '--profile-only' "$work/help.out"

set +e
"$repo/scripts/build-lyona-arch-iso.sh" --bogus-flag >"$work/bogus.out" 2>&1
bogus_status=$?
set -e
if [[ $bogus_status -eq 0 ]]; then
	printf 'build-lyona-arch-iso.sh accepted an unknown flag.\n' >&2
	exit 1
fi

expect_failure() {
	local label=$1 expected_text=$2 status
	shift 2
	set +e
	"$@" >"$work/fail.out" 2>&1
	status=$?
	set -e
	if [[ $status -eq 0 ]]; then
		printf 'build-lyona-arch-iso.sh accepted %s.\n' "$label" >&2
		exit 1
	fi
	grep -Fq "$expected_text" "$work/fail.out" || {
		printf 'build-lyona-arch-iso.sh did not report %s.\n' "$label" >&2
		cat "$work/fail.out" >&2
		exit 1
	}
}

expect_failure 'a malformed version' 'version must look like' \
	"$repo/scripts/build-lyona-arch-iso.sh" --profile-only --version 1.2.3.4
expect_failure 'a non-numeric version' 'version must look like' \
	"$repo/scripts/build-lyona-arch-iso.sh" --profile-only --version latest
expect_failure 'a valueless --version' 'requires a value' \
	"$repo/scripts/build-lyona-arch-iso.sh" --version

config_version=$(
	awk -F= '
		$1 ~ /^[[:space:]]*VERSION[[:space:]]*$/ {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
			print $2
			exit
		}
	' "$repo/config.mk"
)
[[ -n $config_version ]] || {
	printf 'could not read VERSION from config.mk.\n' >&2
	exit 1
}

releng="$work/releng"
mkdir -p "$releng/airootfs/root" "$releng/airootfs/etc/mkinitcpio.conf.d"
# The HOOKS line as releng ships it. The splash needs plymouth inserted into
# it, so the shape the builder patches is pinned here.
cat >"$releng/airootfs/etc/mkinitcpio.conf.d/archiso.conf" <<'EOF'
HOOKS=(base udev microcode modconf kms memdisk archiso archiso_loop_mnt archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs block filesystems keyboard)
COMPRESSION="xz"
COMPRESSION_OPTIONS=(-9e)
EOF
cat >"$releng/profiledef.sh" <<'EOF'
#!/usr/bin/env bash
iso_name="archlinux"
iso_label="ARCH_$(date +%Y%m)"
iso_publisher="Arch Linux <https://archlinux.org>"
iso_application="Arch Linux Live/Rescue CD"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
EOF
printf 'base\n' >"$releng/packages.x86_64"
printf '[options]\n' >"$releng/pacman.conf"

mkdir -p "$releng/efiboot/loader/entries" "$releng/syslinux"
# The boot-menu shapes the builder patches, as releng ships them.
cat >"$releng/efiboot/loader/loader.conf" <<'EOF'
timeout 15
default 01-archiso-linux.conf
beep on
EOF
cat >"$releng/syslinux/archiso_head.cfg" <<'EOF'
SERIAL 0 115200
UI vesamenu.c32
MENU TITLE Arch Linux
MENU CLEAR
EOF
cat >"$releng/syslinux/archiso_sys.cfg" <<'EOF'
INCLUDE archiso_head.cfg

DEFAULT arch
TIMEOUT 150

INCLUDE archiso_sys-linux.cfg
EOF
cat >"$releng/efiboot/loader/entries/01-archiso-linux.conf" <<'EOF'
title    Arch Linux install medium (%ARCH%, UEFI)
sort-key 01
linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID%
EOF
cat >"$releng/efiboot/loader/entries/02-archiso-speech-linux.conf" <<'EOF'
title    Arch Linux install medium (%ARCH%, UEFI) with speech
sort-key 02
linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% accessibility=on
EOF
cat >"$releng/syslinux/archiso_sys-linux.cfg" <<'EOF'
LABEL arch
MENU LABEL Arch Linux install medium (%ARCH%, BIOS)
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID%

LABEL archspeech
MENU LABEL Arch Linux install medium (%ARCH%, BIOS) with ^speech
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% accessibility=on
EOF

LYONA_RELENG_DIR="$releng" \
	"$repo/scripts/build-lyona-arch-iso.sh" --profile-only --output "$work/staged" \
	>"$work/profile.out" 2>&1

profiledef="$work/staged/profile/profiledef.sh"
# Mirrors the volume-label rule in build-lyona-arch-iso.sh: an ISO9660 volume
# identifier admits only A-Z, 0-9 and _, so a pre-release suffix loses its
# punctuation -- 2026.08.0-beta.1 becomes LYONA_2026_08_0_BETA1.
expected_label="LYONA_${config_version%%-*}"
expected_label="${expected_label//./_}"
if [[ $config_version == *-* ]]; then
	config_prerelease=${config_version#*-}
	expected_label="${expected_label}_${config_prerelease//./}"
fi
expected_label=${expected_label^^}
grep -Fqx 'iso_name="lyona"' "$profiledef" || {
	printf 'staged profiledef.sh does not set iso_name to lyona.\n' >&2
	exit 1
}
grep -Fqx "iso_version=\"$config_version\"" "$profiledef" || {
	printf 'staged profiledef.sh does not set iso_version to %s.\n' "$config_version" >&2
	exit 1
}
grep -Fqx "iso_label=\"$expected_label\"" "$profiledef" || {
	printf 'staged profiledef.sh does not set iso_label to %s.\n' "$expected_label" >&2
	exit 1
}
grep -Fq "lyona $config_version Arch Linux install medium" "$profiledef" || {
	printf 'staged profiledef.sh does not version iso_application.\n' >&2
	exit 1
}

[[ $expected_label =~ ^[A-Z0-9_]{1,32}$ ]] || {
	printf 'iso_label %s is not a valid ISO9660 volume identifier.\n' "$expected_label" >&2
	exit 1
}

uefi_main="$work/staged/profile/efiboot/loader/entries/01-archiso-linux.conf"
uefi_speech="$work/staged/profile/efiboot/loader/entries/02-archiso-speech-linux.conf"
bios_cfg="$work/staged/profile/syslinux/archiso_sys-linux.cfg"

grep -Fq 'options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 vt.global_cursor_default=0' \
	"$uefi_main" || {
	printf 'staged UEFI boot entry was not quieted.\n' >&2
	exit 1
}
grep -Fqx 'options  archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% accessibility=on' \
	"$uefi_speech" || {
	printf 'staged UEFI speech/accessibility entry should be left untouched.\n' >&2
	exit 1
}
grep -Fq 'APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash loglevel=3 vt.global_cursor_default=0' \
	"$bios_cfg" || {
	printf 'staged BIOS boot entry was not quieted.\n' >&2
	exit 1
}
grep -Fqx 'APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% accessibility=on' \
	"$bios_cfg" || {
	printf 'staged BIOS speech/accessibility entry should be left untouched.\n' >&2
	exit 1
}

# The installer is centred as one block against the wordmark.
#
# gum's interactive widgets take no --padding argument, so the only way to
# indent the widget itself -- rather than just the header printed above it --
# is the per-command GUM_<COMMAND>_PADDING variable each one reads.
ui_lib=$repo/archiso/airootfs/root/lyona-ui.sh
logo=$repo/archiso/airootfs/root/lyona-logo.txt
[[ -f $logo ]] || {
	printf 'the installer wordmark is missing.\n' >&2
	exit 1
}

# The logo is a paint map: two characters per cell, the top pixel's colour then
# the bottom's, drawn as a half block so one character row carries two pixel
# rows. LOGO_WIDTH is what the centring is computed from, so it has to describe
# the rendered width rather than the file's.
logo_chars=$(awk '{ n = length($0); if (n > max) max = n } END { print max + 0 }' "$logo")
declared_width=$(awk -F= '$1 == "LOGO_WIDTH" { print $2; exit }' "$ui_lib")
[[ $((logo_chars / 2)) == "$declared_width" ]] || {
	printf 'LOGO_WIDTH is %s but the logo renders %s columns wide.\n' \
		"$declared_width" "$((logo_chars / 2))" >&2
	exit 1
}

# An odd-length row would pair a pixel with the next row's, shearing the image.
awk -v width="$logo_chars" '
	length($0) != width { print NR; exit 1 }
	length($0) % 2 != 0 { print NR; exit 1 }
' "$logo" || {
	printf 'the logo has a row that is not a whole number of cells.\n' >&2
	exit 1
}

# Every character in the map has to have a colour, or it renders as a blank
# hole in the middle of the artwork.
while IFS= read -r logo_line; do
	printf '%s\n' "$logo_line" | grep -o . | while IFS= read -r logo_char; do
		[[ $logo_char == . ]] && continue
		grep -Fq "[$logo_char]=" "$ui_lib" || {
			printf 'the logo uses %s but LOGO_COLORS has no entry for it.\n' \
				"$logo_char" >&2
			exit 1
		}
	done || exit 1
done <"$logo"

# The diamond needs all four quadrant colours and the cross; a map that lost
# one would still render, just wrong.
for logo_char in g b t v w; do
	grep -Fq "$logo_char" "$logo" || {
		printf 'the logo lost its %s cells.\n' "$logo_char" >&2
		exit 1
	}
done

for widget in CHOOSE CONFIRM FILTER INPUT SPIN TABLE WRITE; do
	grep -q "export GUM_${widget}_PADDING=" "$ui_lib" || {
		printf 'gum %s is not indented, so it would sit at the left edge.\n' \
			"$widget" >&2
		exit 1
	}
done

# gum confirm draws one column further right than the other widgets at the
# same padding, so it is offset by one to line up with them.
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'confirm_padding=$((PADDING_LEFT - 1))' "$ui_lib" || {
	printf 'the gum confirm off-by-one compensation is gone.\n' >&2
	exit 1
}

# A bare `gum style` call bypasses the indent, which is exactly the bug this
# replaced: the prose sat at column 0 while the widgets were centred.
for script_file in "$repo/archiso/airootfs/root/lyona-install.sh" \
	"$repo/archiso/airootfs/root/lyona-postinstall.sh"; do
	if ! awk '
		/gum style/ { pending = 2 }
		pending > 0 { window = window $0; pending-- }
		pending == 0 && window != "" {
			if (window !~ /--margin/) { bad = 1 }
			window = ""
		}
		END { exit(bad ? 1 : 0) }
	' "$script_file"; then
		printf '%s calls gum style without an offset instead of say.\n' "$script_file" >&2
		exit 1
	fi
done

# The console palette, generated from the same theme as the splash so the
# installer is a continuation of the boot screen rather than stock VGA.
staged_console=$work/staged/profile/airootfs/root/lyona-console.sh
[[ -f $staged_console ]] || {
	printf 'the console palette was not generated onto the live medium.\n' >&2
	exit 1
}
bash -n "$staged_console" || {
	printf 'the generated console palette is not valid shell.\n' >&2
	exit 1
}
# Slot 0 is the console background, and it has to be the palette's background
# rather than its color0, or the console does not match the splash.
grep -Fq '\033]P01a1b26' "$staged_console" || {
	printf 'the console background is not the tokyonight background.\n' >&2
	exit 1
}
grep -Fq 'lyona_console_colors()' "$staged_console" || {
	printf 'the generated console palette defines no entry point.\n' >&2
	exit 1
}

# Asking permission to be asked questions is a screen with one answer on it.
if grep -q 'Ready to begin' "$repo/archiso/airootfs/root/lyona-install.sh"; then
	printf 'the installer still asks whether to begin.\n' >&2
	exit 1
fi
# The disk confirmation is a different matter and must stay.
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'Wipe $DISK and install' "$repo/archiso/airootfs/root/lyona-install.sh" || {
	printf 'the installer no longer confirms before wiping the disk.\n' >&2
	exit 1
}

# The wordmark has to reach the medium, or show_logo falls back to plain text.
[[ -f $work/staged/profile/airootfs/root/lyona-logo.txt ]] || {
	printf 'the wordmark was not staged onto the live medium.\n' >&2
	exit 1
}

# No boot menu: there is one thing to boot and it launches the installer on
# login, so a menu asking which is a step with no choice in it.
#
# A timeout alone is not enough on BIOS: vesamenu.c32 always draws, so the
# module itself has to be replaced rather than just its countdown shortened.
staged_loader=$work/staged/profile/efiboot/loader/loader.conf
grep -Fqx 'timeout 0' "$staged_loader" || {
	printf 'the UEFI boot menu still has a countdown.\n' >&2
	exit 1
}
grep -Fqx 'default 01-archiso-linux.conf' "$staged_loader" || {
	printf 'disabling the UEFI menu lost the default entry, so nothing would boot.\n' >&2
	exit 1
}
staged_head=$work/staged/profile/syslinux/archiso_head.cfg
if grep -q '^UI vesamenu.c32$' "$staged_head"; then
	printf 'the BIOS boot menu module is still drawn.\n' >&2
	exit 1
fi
grep -Fqx 'PROMPT 0' "$staged_head" || {
	printf 'the BIOS boot prompt was not suppressed.\n' >&2
	exit 1
}
grep -Fqx 'TIMEOUT 1' "$work/staged/profile/syslinux/archiso_sys.cfg" || {
	printf 'the BIOS boot menu still has a countdown.\n' >&2
	exit 1
}
# The entries themselves must survive: they are what the loaders boot, and on
# UEFI they remain reachable by holding a key.
grep -Fqx 'DEFAULT arch' "$work/staged/profile/syslinux/archiso_sys.cfg" || {
	printf 'disabling the BIOS menu lost the default entry, so nothing would boot.\n' >&2
	exit 1
}

# The boot splash.
#
# The ISO already booted with quiet and a hidden cursor, which turned the whole
# boot into a black screen that reads as a hang. The splash gives that same
# silence something to show, so `splash` and the plymouth hook have to travel
# together with it: the kernel flag alone, without the hook, is a no-op, and
# the hook without a theme falls back to whatever plymouth ships.
staged_hooks=$work/staged/profile/airootfs/etc/mkinitcpio.conf.d/archiso.conf
grep -q '^HOOKS=(base udev plymouth ' "$staged_hooks" || {
	printf 'the plymouth hook is not in the staged HOOKS line, or not directly after udev.\n' >&2
	exit 1
}
grep -q '^HOOKS=.*archiso_pxe_nfs block filesystems keyboard)' "$staged_hooks" || {
	printf 'inserting the plymouth hook disturbed the rest of the HOOKS line.\n' >&2
	exit 1
}

for entry in \
	"$work/staged/profile/efiboot/loader/entries/01-archiso-linux.conf" \
	"$work/staged/profile/syslinux/archiso_sys-linux.cfg"; do
	grep -q 'quiet splash loglevel=3' "$entry" || {
		printf 'the primary boot entry in %s does not request the splash.\n' "$entry" >&2
		exit 1
	}
done

staged_theme=$work/staged/profile/airootfs/usr/share/plymouth/themes/lyona
for name in lyona.plymouth lyona.script logo.png; do
	[[ -f $staged_theme/$name ]] || {
		printf 'the staged boot splash is missing %s.\n' "$name" >&2
		exit 1
	}
done
grep -Fqx 'Theme=lyona' "$work/staged/profile/airootfs/etc/plymouth/plymouthd.conf" || {
	printf 'plymouthd.conf does not select the generated lyona theme.\n' >&2
	exit 1
}
# The theme is generated from the palette rather than checked in, so the
# background has to actually be the palette's, not plymouth's default black.
grep -Fq 'ConsoleLogBackgroundColor=0x1a1b26' "$staged_theme/lyona.plymouth" || {
	printf 'the staged boot splash does not use the tokyonight background.\n' >&2
	exit 1
}
# The hook is inert without the package.
grep -Fqx plymouth "$repo/archiso/packages.x86_64" || {
	printf 'plymouth is not in the ISO package list.\n' >&2
	exit 1
}

# Coloured pacman output, on the live medium and on the installed system.
# Two settings are needed, not one: the ISO's own pacman.conf covers the live
# medium, and archinstall's PacmanConfig.configure() rewrites the *target's*
# Color line from the JSON flag, so a false there silently comments out what
# the conf enabled.
assert_line "$repo/archiso/pacman.conf" 'Color'
assert_contains "$repo/archiso/airootfs/root/lyona-install.sh" '"color": true'
if grep -Fq '"color": false' "$repo/archiso/airootfs/root/lyona-install.sh"; then
	fail 'archinstall is configured to disable pacman colour on the installed system'
fi

udev_rule="$work/staged/profile/airootfs/etc/udev/rules.d/90-lyona-optical-no-loop.rules"
[[ -f $udev_rule ]] || {
	printf 'staged profile does not carry the optical-drive loopback rule.\n' >&2
	exit 1
}
# The rule has to clear the flag before systemd's own 99-systemd.rules reads
# it, so both the property name and the sort order matter.
grep -Fq 'ENV{ID_PART_GPT_AUTO_ROOT_DISK_NEEDS_LOOP}="0"' "$udev_rule" || {
	printf 'the optical-drive rule does not clear ID_PART_GPT_AUTO_ROOT_DISK_NEEDS_LOOP.\n' >&2
	exit 1
}
[[ $(basename "$udev_rule") < 99-systemd.rules ]] || {
	printf 'the optical-drive rule does not sort before 99-systemd.rules.\n' >&2
	exit 1
}
if command -v udevadm >/dev/null 2>&1; then
	udevadm verify "$udev_rule" >/dev/null || {
		printf 'the optical-drive rule is not valid udev syntax.\n' >&2
		exit 1
	}
fi

zlogin="$work/staged/profile/airootfs/root/.zlogin"
grep -Fq 'clear' "$zlogin" || {
	printf '.zlogin does not clear the screen before launching lyona-install.\n' >&2
	exit 1
}

stamp="$work/staged/profile/airootfs/etc/lyona-iso-release"
[[ -f $stamp ]] || {
	printf 'staged profile has no /etc/lyona-iso-release stamp.\n' >&2
	exit 1
}
grep -Fqx "LYONA_ISO_VERSION=$config_version" "$stamp" || {
	printf 'release stamp does not record version %s.\n' "$config_version" >&2
	cat "$stamp" >&2
	exit 1
}
grep -Eq '^LYONA_ISO_COMMIT=[0-9a-f]{40}$|^LYONA_ISO_COMMIT=unknown$' "$stamp" || {
	printf 'release stamp does not record a build commit.\n' >&2
	exit 1
}

LYONA_RELENG_DIR="$releng" \
	"$repo/scripts/build-lyona-arch-iso.sh" --profile-only --version v9.9.9 \
	--output "$work/staged-override" >"$work/override.out" 2>&1
grep -Fqx 'iso_version="9.9.9"' "$work/staged-override/profile/profiledef.sh"
grep -Fqx 'iso_label="LYONA_9_9_9"' "$work/staged-override/profile/profiledef.sh"
grep -Fqx 'LYONA_ISO_VERSION=9.9.9' \
	"$work/staged-override/profile/airootfs/etc/lyona-iso-release"

# A pre-release keeps its suffix in the version but not in the volume label.
LYONA_RELENG_DIR="$releng" \
	"$repo/scripts/build-lyona-arch-iso.sh" --profile-only --version v9.9.9-beta.2 \
	--output "$work/staged-prerelease" >"$work/prerelease.out" 2>&1
grep -Fqx 'iso_version="9.9.9-beta.2"' "$work/staged-prerelease/profile/profiledef.sh"
grep -Fqx 'iso_label="LYONA_9_9_9_BETA2"' "$work/staged-prerelease/profile/profiledef.sh"
grep -Fqx 'LYONA_ISO_VERSION=9.9.9-beta.2' \
	"$work/staged-prerelease/profile/airootfs/etc/lyona-iso-release"

expect_failure 'a malformed pre-release suffix' 'version must look like' \
	"$repo/scripts/build-lyona-arch-iso.sh" --profile-only --version 9.9.9-beta
expect_failure 'an unknown pre-release channel' 'version must look like' \
	"$repo/scripts/build-lyona-arch-iso.sh" --profile-only --version 9.9.9-snapshot.1

if [[ $EUID -ne 0 ]]; then
	mkdir -p "$work/bin"
	cat >"$work/bin/mkarchiso" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$work/bin/mkarchiso"
	set +e
	PATH="$work/bin:$PATH" "$repo/scripts/build-lyona-arch-iso.sh" >"$work/norun.out" 2>&1
	norun_status=$?
	set -e
	if [[ $norun_status -eq 0 ]]; then
		printf 'build-lyona-arch-iso.sh did not require root even with mkarchiso present.\n' >&2
		exit 1
	fi
	grep -Fq 'mkarchiso must run as root.' "$work/norun.out"
fi

printf 'Arch ISO builder structural checks: PASS\n'
