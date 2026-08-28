#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper="$repo/scripts/lyona-cachyos"
bin="$work/bin"
mkdir -p "$bin"

cat >"$bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat >"$bin/pacman" <<'EOF'
#!/bin/sh
printf 'pacman %s\n' "$*" >>"${LYONA_TEST_LOG:?}"
# installed-package queries answer from LYONA_TEST_INSTALLED
case "$1 $2" in
"-Qq "*)
	case " ${LYONA_TEST_INSTALLED:-} " in
	*" $2 "*) exit 0 ;;
	esac
	exit 1
	;;
esac
if [ -n "${LYONA_TEST_PACMAN_FAIL:-}" ]; then
	case " $* " in
	*" $LYONA_TEST_PACMAN_FAIL "*) exit 1 ;;
	esac
fi
exit 0
EOF
cat >"$bin/pacman-key" <<'EOF'
#!/bin/sh
printf 'pacman-key %s\n' "$*" >>"${LYONA_TEST_LOG:?}"
exit 0
EOF
cat >"$bin/grub-mkconfig" <<'EOF'
#!/bin/sh
printf 'grub-mkconfig %s\n' "$*" >>"${LYONA_TEST_LOG:?}"
exit 0
EOF
cat >"$bin/gcc" <<'EOF'
#!/bin/sh
printf '  -march=                    \t\t%s\n' "${LYONA_TEST_MARCH:-x86-64}"
exit 0
EOF
chmod +x "$bin"/*

make_ldso() {
	local path=$1 level=${2:-}
	cat >"$path" <<EOF
#!/bin/sh
cat <<'HELP'
Legacy HWCAP subdirectories under library search path directories:
  x86-64-v4
  x86-64-v3
HELP
EOF
	if [[ -n $level ]]; then
		printf 'printf "  %s (supported, searched)\\n"\n' "$level" >>"$path"
	fi
	chmod +x "$path"
}

fixture_pacman_conf() {
	cat >"$1" <<'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64
ParallelDownloads = 5

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
}

fail() {
	printf 'lyona-cachyos: %s\n' "$1" >&2
	[[ -n ${2:-} ]] && cat "$2" >&2
	exit 1
}

run_helper() {
	local case_dir=$1
	shift
	PATH="$bin:$PATH" \
		LYONA_TEST_LOG="$case_dir/calls.log" \
		LYONA_TEST_PACMAN_FAIL="${pacman_fail:-}" \
		LYONA_TEST_INSTALLED="${installed:-}" \
		LYONA_TEST_MARCH="${march:-x86-64}" \
		LYONA_CACHYOS_PACMAN_CONF="$case_dir/pacman.conf" \
		LYONA_CACHYOS_BOOT_DIR="$case_dir/boot" \
		LYONA_CACHYOS_LDSO="$case_dir/ldso" \
		LYONA_CACHYOS_NONINTERACTIVE=1 \
		"$helper" "$@"
}

new_case() {
	local name=$1 level=${2-x86-64-v3}
	local case_dir="$work/$name"
	mkdir -p "$case_dir/boot"
	fixture_pacman_conf "$case_dir/pacman.conf"
	make_ldso "$case_dir/ldso" "$level"
	: >"$case_dir/calls.log"
	printf '%s\n' "$case_dir"
}

section_order() {
	command grep -E '^\[' "$1" | tr '\n' ' '
}

# --- status reports an unconfigured system -----------------------------------
case_dir=$(new_case status)
run_helper "$case_dir" status >"$case_dir/out" 2>&1
grep -Fqx 'cachyos-repos: not configured' "$case_dir/out" ||
	fail 'status did not report an unconfigured system' "$case_dir/out"

# --- add-repos on a v3 machine ------------------------------------------------
case_dir=$(new_case v3)
cp "$case_dir/pacman.conf" "$case_dir/pacman.conf.orig"
run_helper "$case_dir" add-repos >"$case_dir/out" 2>&1 ||
	fail 'add-repos failed on a v3 fixture' "$case_dir/out"

expected_order='[cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3] [cachyos] [core] [extra] [multilib] '
[[ $(section_order "$case_dir/pacman.conf") == "[options] $expected_order" ]] ||
	fail "unexpected repository order: $(section_order "$case_dir/pacman.conf")"

grep -Fqx 'Include = /etc/pacman.d/cachyos-v3-mirrorlist' "$case_dir/pacman.conf" ||
	fail 'the v3 blocks do not include the v3 mirrorlist'
grep -Fqx 'Architecture = auto' "$case_dir/pacman.conf" ||
	fail 'Architecture was not switched to auto'
# shellcheck disable=SC2016 # the literal pacman variables are what we look for
grep -Fq 'Server = https://cdn77.cachyos.org/repo/$arch/$repo' "$case_dir/pacman.conf" &&
	fail 'the bootstrap Server line was left in the final configuration'

backup=$(printf '%s\n' "$case_dir/pacman.conf.lyona-backup-"* | head -n1)
[[ -f $backup ]] || fail 'add-repos did not back up pacman.conf'
cmp -s "$backup" "$case_dir/pacman.conf.orig" ||
	fail 'the backup does not match the original pacman.conf'

grep -Fq 'pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com' \
	"$case_dir/calls.log" || fail 'the signing key was not received' "$case_dir/calls.log"
grep -Fq 'pacman-key --lsign-key F3B607488DB35A47' "$case_dir/calls.log" ||
	fail 'the signing key was not locally signed' "$case_dir/calls.log"

mapfile -t pacman_calls < <(grep '^pacman ' "$case_dir/calls.log")
[[ ${pacman_calls[0]} == 'pacman -Sy' ]] ||
	fail "first pacman call was ${pacman_calls[0]}"
[[ ${pacman_calls[1]} == 'pacman -S --needed --noconfirm cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist' ]] ||
	fail "keyring install call was ${pacman_calls[1]}"
[[ ${pacman_calls[2]} == 'pacman -S --needed --noconfirm cachyos/pacman' ]] ||
	fail "pacman replacement call was ${pacman_calls[2]}"
[[ ${pacman_calls[3]} == 'pacman -Syu --noconfirm' ]] ||
	fail "upgrade call was ${pacman_calls[3]}"

# --- --no-upgrade syncs but does not upgrade the running system --------------
case_dir=$(new_case no-upgrade)
run_helper "$case_dir" add-repos --no-upgrade >"$case_dir/out" 2>&1 ||
	fail 'add-repos --no-upgrade failed' "$case_dir/out"
grep -Fq 'pacman -Syu' "$case_dir/calls.log" &&
	fail '--no-upgrade still upgraded the system' "$case_dir/calls.log"
grep -Fqx 'pacman -Sy' "$case_dir/calls.log" ||
	fail '--no-upgrade did not sync the databases' "$case_dir/calls.log"
[[ $(section_order "$case_dir/pacman.conf") == '[options] [cachyos-v3] [cachyos-core-v3] [cachyos-extra-v3] [cachyos] [core] [extra] [multilib] ' ]] ||
	fail "--no-upgrade did not add the repositories: $(section_order "$case_dir/pacman.conf")"

set +e
run_helper "$case_dir" add-repos --bogus >"$case_dir/bogus.out" 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail 'add-repos accepted an unknown option'

# --- add-repos is idempotent --------------------------------------------------
cp "$case_dir/pacman.conf" "$case_dir/pacman.conf.configured"
: >"$case_dir/calls.log"
run_helper "$case_dir" add-repos >"$case_dir/out2" 2>&1 ||
	fail 'a second add-repos failed' "$case_dir/out2"
grep -Fq 'already configured' "$case_dir/out2" ||
	fail 'a second add-repos did not report the existing configuration' "$case_dir/out2"
cmp -s "$case_dir/pacman.conf" "$case_dir/pacman.conf.configured" ||
	fail 'a second add-repos rewrote pacman.conf'
[[ ! -s $case_dir/calls.log ]] ||
	fail 'a second add-repos ran pacman' "$case_dir/calls.log"

run_helper "$case_dir" status >"$case_dir/out3" 2>&1
grep -Fqx 'cachyos-repos: configured' "$case_dir/out3" ||
	fail 'status did not report the configured system' "$case_dir/out3"

# --- v4 and znver4 detection --------------------------------------------------
case_dir=$(new_case v4 x86-64-v4)
run_helper "$case_dir" add-repos >"$case_dir/out" 2>&1 ||
	fail 'add-repos failed on a v4 fixture' "$case_dir/out"
[[ $(section_order "$case_dir/pacman.conf") == '[options] [cachyos-v4] [cachyos-core-v4] [cachyos-extra-v4] [cachyos] [core] [extra] [multilib] ' ]] ||
	fail "unexpected v4 repository order: $(section_order "$case_dir/pacman.conf")"
grep -Fqx 'Include = /etc/pacman.d/cachyos-v4-mirrorlist' "$case_dir/pacman.conf" ||
	fail 'the v4 blocks do not include the v4 mirrorlist'

case_dir=$(new_case znver4 x86-64-v4)
march=znver5 run_helper "$case_dir" add-repos >"$case_dir/out" 2>&1 ||
	fail 'add-repos failed on a znver4 fixture' "$case_dir/out"
[[ $(section_order "$case_dir/pacman.conf") == '[options] [cachyos-znver4] [cachyos-core-znver4] [cachyos-extra-znver4] [cachyos] [core] [extra] [multilib] ' ]] ||
	fail "unexpected znver4 repository order: $(section_order "$case_dir/pacman.conf")"
grep -Fqx 'Include = /etc/pacman.d/cachyos-v4-mirrorlist' "$case_dir/pacman.conf" ||
	fail 'the znver4 blocks do not include the v4 mirrorlist'

# --- a baseline machine gets the plain repository only ------------------------
case_dir=$(new_case baseline "")
run_helper "$case_dir" add-repos >"$case_dir/out" 2>&1 ||
	fail 'add-repos failed on a baseline fixture' "$case_dir/out"
[[ $(section_order "$case_dir/pacman.conf") == '[options] [cachyos] [core] [extra] [multilib] ' ]] ||
	fail "unexpected baseline repository order: $(section_order "$case_dir/pacman.conf")"
grep -Fq 'cachyos/pacman' "$case_dir/calls.log" &&
	fail 'a baseline machine should not need the CachyOS pacman build'

# --- a failed step restores pacman.conf --------------------------------------
case_dir=$(new_case rollback)
cp "$case_dir/pacman.conf" "$case_dir/pacman.conf.orig"
set +e
pacman_fail=cachyos-keyring run_helper "$case_dir" add-repos >"$case_dir/out" 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail 'add-repos reported success after a failed package install'
grep -Fq 'Restored' "$case_dir/out" || fail 'add-repos did not report the restore' "$case_dir/out"
cmp -s "$case_dir/pacman.conf" "$case_dir/pacman.conf.orig" ||
	fail 'pacman.conf was not restored after a failed add-repos'
grep -Fq 'pacman -Syu' "$case_dir/calls.log" &&
	fail 'add-repos upgraded the system after a failed step'

# --- install-kernel requires the repositories --------------------------------
case_dir=$(new_case kernel-without-repos)
set +e
run_helper "$case_dir" install-kernel >"$case_dir/out" 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail 'install-kernel ran without the CachyOS repositories'
grep -Fq 'add-repos' "$case_dir/out" ||
	fail 'install-kernel did not point at add-repos' "$case_dir/out"
[[ ! -s $case_dir/calls.log ]] ||
	fail 'install-kernel ran pacman without the repositories' "$case_dir/calls.log"

# --- install-kernel clones the systemd-boot entry ----------------------------
case_dir=$(new_case kernel-sdboot)
run_helper "$case_dir" add-repos >/dev/null 2>&1
mkdir -p "$case_dir/boot/loader/entries"
entries="$case_dir/boot/loader/entries"
cat >"$entries/2026-08-26_10-00-00_linux.conf" <<'EOF'
# Created by: archinstall
# Created on: 2026-08-26_10-00-00
title	Arch Linux (linux)
linux	/vmlinuz-linux
initrd	/initramfs-linux.img
options root=PARTUUID=1234 rw rootfstype=btrfs
EOF
cp "$entries/2026-08-26_10-00-00_linux.conf" "$case_dir/entry.orig"
: >"$case_dir/calls.log"
touch "$case_dir/boot/vmlinuz-linux-cachyos"
run_helper "$case_dir" install-kernel >"$case_dir/out" 2>&1 ||
	fail 'install-kernel failed with a systemd-boot layout' "$case_dir/out"

new_entry="$entries/2026-08-26_10-00-00_linux-cachyos.conf"
[[ -f $new_entry ]] || {
	printf 'entries: %s\n' "$(ls "$entries")" >&2
	fail 'install-kernel did not add a systemd-boot entry'
}
grep -Fqx 'linux	/vmlinuz-linux-cachyos' "$new_entry" ||
	fail 'the cloned entry does not point at the CachyOS kernel image' "$new_entry"
grep -Fqx 'initrd	/initramfs-linux-cachyos.img' "$new_entry" ||
	fail 'the cloned entry does not point at the CachyOS initramfs' "$new_entry"
grep -Fqx 'title	Arch Linux (linux-cachyos)' "$new_entry" ||
	fail 'the cloned entry kept the old title' "$new_entry"
grep -Fqx 'options root=PARTUUID=1234 rw rootfstype=btrfs' "$new_entry" ||
	fail 'the cloned entry lost the kernel command line' "$new_entry"
cmp -s "$entries/2026-08-26_10-00-00_linux.conf" "$case_dir/entry.orig" ||
	fail 'install-kernel modified the existing boot entry'
grep -Fq 'pacman -S --needed --noconfirm linux-cachyos' "$case_dir/calls.log" ||
	fail 'install-kernel did not install the kernel' "$case_dir/calls.log"
grep -Fq 'linux-cachyos-headers' "$case_dir/calls.log" &&
	fail 'install-kernel installed headers nothing asked for' "$case_dir/calls.log"

: >"$case_dir/calls.log"
run_helper "$case_dir" install-kernel >"$case_dir/out2" 2>&1 ||
	fail 'a second install-kernel failed' "$case_dir/out2"
grep -Fq 'already exists' "$case_dir/out2" ||
	fail 'a second install-kernel did not detect the existing entry' "$case_dir/out2"
[[ $(find "$entries" -name '*linux-cachyos*' | wc -l) -eq 1 ]] ||
	fail 'a second install-kernel added a duplicate boot entry'

# --- the default boot entry is pinned, never handed to the new kernel --------
case_dir=$(new_case kernel-default-pin)
run_helper "$case_dir" add-repos >/dev/null 2>&1
entries="$case_dir/boot/loader/entries"
mkdir -p "$entries"
cat >"$entries/2026-08-26_10-00-00_linux.conf" <<'EOF'
title	Arch Linux (linux)
linux	/vmlinuz-linux
initrd	/initramfs-linux.img
options root=PARTUUID=1234 rw
EOF
printf 'timeout 5\nconsole-mode keep\n' >"$case_dir/boot/loader/loader.conf"
run_helper "$case_dir" install-kernel >"$case_dir/out" 2>&1 ||
	fail 'install-kernel failed while pinning the default entry' "$case_dir/out"
grep -Fqx 'default 2026-08-26_10-00-00_linux.conf' "$case_dir/boot/loader/loader.conf" ||
	fail 'the default boot entry was not pinned to the existing kernel' "$case_dir/boot/loader/loader.conf"
grep -Fq 'timeout 5' "$case_dir/boot/loader/loader.conf" ||
	fail 'pinning the default entry discarded the existing loader.conf'

# --- an explicit default is left alone ---------------------------------------
case_dir=$(new_case kernel-default-kept)
run_helper "$case_dir" add-repos >/dev/null 2>&1
entries="$case_dir/boot/loader/entries"
mkdir -p "$entries"
cat >"$entries/2026-08-26_10-00-00_linux.conf" <<'EOF'
title	Arch Linux (linux)
linux	/vmlinuz-linux
initrd	/initramfs-linux.img
EOF
printf 'default 2026-08-26_10-00-00_linux.conf\ntimeout 3\n' \
	>"$case_dir/boot/loader/loader.conf"
cp "$case_dir/boot/loader/loader.conf" "$case_dir/loader.orig"
run_helper "$case_dir" install-kernel >"$case_dir/out" 2>&1 ||
	fail 'install-kernel failed with an explicit default entry' "$case_dir/out"
cmp -s "$case_dir/boot/loader/loader.conf" "$case_dir/loader.orig" ||
	fail 'install-kernel rewrote an explicit default boot entry'

# --- several kernels can be installed at once --------------------------------
case_dir=$(new_case kernel-multiple)
run_helper "$case_dir" add-repos >/dev/null 2>&1
entries="$case_dir/boot/loader/entries"
mkdir -p "$entries"
cat >"$entries/2026-08-26_10-00-00_linux.conf" <<'EOF'
title	Arch Linux (linux)
linux	/vmlinuz-linux
initrd	/initramfs-linux.img
EOF
: >"$case_dir/calls.log"
run_helper "$case_dir" install-kernel linux-cachyos linux-cachyos-lts \
	>"$case_dir/out" 2>&1 ||
	fail 'install-kernel failed with several kernels' "$case_dir/out"
grep -Fq 'pacman -S --needed --noconfirm linux-cachyos linux-cachyos-lts' \
	"$case_dir/calls.log" ||
	fail 'install-kernel did not install every kernel' "$case_dir/calls.log"
[[ -f $entries/2026-08-26_10-00-00_linux-cachyos.conf ]] ||
	fail 'no boot entry for linux-cachyos'
[[ -f $entries/2026-08-26_10-00-00_linux-cachyos-lts.conf ]] ||
	fail 'no boot entry for linux-cachyos-lts'
grep -Fqx 'default 2026-08-26_10-00-00_linux.conf' "$case_dir/boot/loader/loader.conf" ||
	fail 'installing several kernels changed the default boot entry'

# --- headers come only when asked for, or when DKMS is present ---------------
case_dir=$(new_case kernel-with-headers)
run_helper "$case_dir" add-repos >/dev/null 2>&1
: >"$case_dir/calls.log"
run_helper "$case_dir" install-kernel --with-headers >"$case_dir/out" 2>&1 ||
	fail 'install-kernel --with-headers failed' "$case_dir/out"
grep -Fq 'pacman -S --needed --noconfirm linux-cachyos linux-cachyos-headers' \
	"$case_dir/calls.log" ||
	fail '--with-headers did not install the headers' "$case_dir/calls.log"

case_dir=$(new_case kernel-dkms-present)
run_helper "$case_dir" add-repos >/dev/null 2>&1
: >"$case_dir/calls.log"
installed=dkms run_helper "$case_dir" install-kernel >"$case_dir/out" 2>&1 ||
	fail 'install-kernel failed with DKMS installed' "$case_dir/out"
grep -Fq 'pacman -S --needed --noconfirm linux-cachyos linux-cachyos-headers' \
	"$case_dir/calls.log" ||
	fail 'headers were not installed even though DKMS is present' "$case_dir/calls.log"

# --- install-kernel regenerates the GRUB configuration -----------------------
case_dir=$(new_case kernel-grub)
run_helper "$case_dir" add-repos >/dev/null 2>&1
mkdir -p "$case_dir/boot/grub"
: >"$case_dir/calls.log"
run_helper "$case_dir" install-kernel >"$case_dir/out" 2>&1 ||
	fail 'install-kernel failed with a GRUB layout' "$case_dir/out"
grep -Fq "grub-mkconfig -o $case_dir/boot/grub/grub.cfg" "$case_dir/calls.log" ||
	fail 'install-kernel did not regenerate the GRUB configuration' "$case_dir/calls.log"

# --- an unknown bootloader is reported, not guessed at -----------------------
case_dir=$(new_case kernel-unknown-bootloader)
run_helper "$case_dir" add-repos >/dev/null 2>&1
: >"$case_dir/calls.log"
run_helper "$case_dir" install-kernel >"$case_dir/out" 2>&1 ||
	fail 'install-kernel failed without a bootloader layout' "$case_dir/out"
grep -Fq 'No GRUB or systemd-boot layout' "$case_dir/out" ||
	fail 'install-kernel did not warn about the unknown bootloader' "$case_dir/out"

# --- install.sh exposes the options and defaults to leaving Arch alone -------
os_release="$work/os-release"
printf 'ID=arch\nPRETTY_NAME="Arch Linux"\n' >"$os_release"
clean_conf="$work/clean-pacman.conf"
fixture_pacman_conf "$clean_conf"
configured_conf="$work/configured-pacman.conf"
{
	printf '[options]\n\n[cachyos-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n\n'
	printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n'
} >"$configured_conf"

installer_summary() {
	local conf=$1
	shift
	DWM_TEST_MODE=1 DWM_OS_RELEASE="$os_release" \
		LYONA_CACHYOS_PACMAN_CONF="$conf" \
		"$repo/install.sh" --dry-run --profile full "$@" 2>&1
}

installer_summary "$clean_conf" >"$work/summary-default.out" ||
	fail 'install.sh --dry-run failed' "$work/summary-default.out"
grep -Fq 'CachyOS repositories: not requested' "$work/summary-default.out" ||
	fail 'the default summary does not report the CachyOS option' "$work/summary-default.out"
grep -Fq 'CachyOS kernel: not requested' "$work/summary-default.out" ||
	fail 'the default summary does not report the kernel option' "$work/summary-default.out"

installer_summary "$clean_conf" --enable-cachyos-repos >"$work/summary-repos.out" ||
	fail 'install.sh --enable-cachyos-repos failed' "$work/summary-repos.out"
grep -Fq 'CachyOS repositories: approved' "$work/summary-repos.out" ||
	fail '--enable-cachyos-repos was not recorded' "$work/summary-repos.out"
grep -Fq 'CachyOS kernel: not requested' "$work/summary-repos.out" ||
	fail '--enable-cachyos-repos should not select the kernel' "$work/summary-repos.out"

installer_summary "$clean_conf" --cachyos-kernel >"$work/summary-kernel.out" ||
	fail 'install.sh --cachyos-kernel failed' "$work/summary-kernel.out"
grep -Fq 'CachyOS repositories: approved' "$work/summary-kernel.out" ||
	fail '--cachyos-kernel does not imply the repositories' "$work/summary-kernel.out"
grep -Fq 'CachyOS kernel: linux-cachyos with a boot entry' "$work/summary-kernel.out" ||
	fail '--cachyos-kernel was not recorded' "$work/summary-kernel.out"

installer_summary "$configured_conf" >"$work/summary-configured.out" ||
	fail 'install.sh --dry-run failed on a configured system' "$work/summary-configured.out"
grep -Fq 'CachyOS repositories: already configured' "$work/summary-configured.out" ||
	fail 'an existing CachyOS setup was not detected' "$work/summary-configured.out"

set +e
DWM_TEST_MODE=1 DWM_OS_RELEASE="$os_release" DWM_INSTALL_CACHYOS_REPOS=bogus \
	"$repo/install.sh" --dry-run >"$work/summary-bogus.out" 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail 'install.sh accepted an invalid DWM_INSTALL_CACHYOS_REPOS'
grep -Fq 'Unsupported CACHYOS_REPOS_APPROVED value' "$work/summary-bogus.out" ||
	fail 'install.sh did not reject the invalid value' "$work/summary-bogus.out"

printf 'CachyOS repository and kernel helper: PASS\n'
