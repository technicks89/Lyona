#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT

snapshot_tree() {
	local root=$1 output=$2
	{
		find "$root" -printf 'entry\t%P\t%y\t%m\t%s\t%l\n'
		find "$root" -type f -exec sha256sum {} + |
			sed "s#  $root/#  #"
	} | sort >"$output"
}

cat >"$work/arch" <<'EOF'
ID=arch
PRETTY_NAME="Arch Linux"
EOF
cat >"$work/unsupported" <<'EOF'
ID=example
PRETTY_NAME="Unsupported Linux"
EOF

arch_family=$(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/arch" bash -c \
	'. "$1"; printf "%s" "$DISTRO_FAMILY"' sh "$repo/scripts/dwm-utils.sh")
[[ $arch_family == arch ]]

unsupported_family=$(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/unsupported" bash -c \
	'. "$1"; printf "%s" "$DISTRO_FAMILY"' sh "$repo/scripts/dwm-utils.sh")
[[ $unsupported_family == unknown ]]

mkdir -p "$work/bin" "$work/unsupported-home"
for command_name in chmod chown cp curl pacman git install ln make mkdir mv rm sudo systemctl tee touch unzip usermod; do
	cat >"$work/bin/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "${0##*/}" "$*" >>"${DWM_MUTATION_LOG:?}"
exit 99
EOF
done
/usr/bin/chmod +x "$work/bin/"*
snapshot_tree "$work/unsupported-home" "$work/home.before"
set +e
DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/unsupported" \
	DWM_MUTATION_LOG="$work/mutations.log" HOME="$work/unsupported-home" \
	PATH="$work/bin:$PATH" "$repo/install.sh" \
	--non-interactive --profile core >"$work/install-rejection.out" 2>&1
install_status=$?
set -e
if [[ $install_status -ne 1 ]]; then
	printf 'Unsupported installer exited with %s instead of 1.\n' "$install_status" >&2
	exit 1
fi
grep -Fq 'Unsupported distribution: Unsupported Linux (ID=example on ' "$work/install-rejection.out"
grep -Fq 'lyona supports Arch Linux, and Arch Linux ARM on aarch64 (experimental), only.' \
	"$work/install-rejection.out"
if [[ -e $work/mutations.log ]]; then
	printf 'Unsupported installer attempted a package or system mutation.\n' >&2
	exit 1
fi
snapshot_tree "$work/unsupported-home" "$work/home.after"
cmp "$work/home.before" "$work/home.after"

# shellcheck disable=SC2016
host_family=$(env -u DWM_TEST_MODE DWM_OS_RELEASE="$work/unsupported" bash -c \
	'. "$1"; printf "%s" "$DISTRO_FAMILY"' sh "$repo/scripts/dwm-utils.sh")
[[ $host_family == arch ]]

root_package_command=$(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/arch" bash -c \
	'. "$1"; printf "%s" "$PKG_CMD"' sh "$repo/scripts/dwm-utils.sh")
if [[ $EUID -eq 0 ]]; then
	[[ $root_package_command == 'pacman -S --needed --noconfirm' ]]
else
	[[ $root_package_command == 'sudo pacman -S --needed --noconfirm' ]]
fi

set +e
snapshot_tree "$work/unsupported-home" "$work/screensaver-home.before"
DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/unsupported" \
	DWM_MUTATION_LOG="$work/mutations.log" HOME="$work/unsupported-home" \
	PATH="$work/bin:$PATH" "$repo/scripts/xscreensaver-setup.sh" \
	>"$work/xscreensaver-rejection.out" 2>&1
screensaver_status=$?
set -e
if [[ $screensaver_status -ne 1 ]]; then
	printf 'Unsupported screensaver setup exited with %s instead of 1.\n' \
		"$screensaver_status" >&2
	exit 1
fi
grep -Fq 'lyona supports Arch Linux, and Arch Linux ARM on aarch64 (experimental), only.' \
	"$work/xscreensaver-rejection.out"
snapshot_tree "$work/unsupported-home" "$work/screensaver-home.after"
if [[ -e $work/mutations.log ]] ||
	! cmp "$work/screensaver-home.before" "$work/screensaver-home.after"; then
	printf 'Unsupported screensaver setup attempted a mutation.\n' >&2
	exit 1
fi

# --- The accepted identities (SPEC.md section 4, ARM64.md A-1) ---------------
cat >"$work/archarm" <<'EOF'
ID=archarm
ID_LIKE=arch
PRETTY_NAME="Arch Linux ARM"
EOF
cat >"$work/derivative" <<'EOF'
ID=example-arch
ID_LIKE=arch
PRETTY_NAME="Example Arch Derivative"
EOF

# family <os-release> <machine>: the family dwm-utils.sh resolves, and whether
# is_arch_family agrees.
family() {
	# shellcheck disable=SC2016
	DWM_TEST_MODE=1 DWM_OS_RELEASE="$1" DWM_MACHINE="$2" bash -c \
		'. "$1"; if is_arch_family; then a=yes; else a=no; fi
		printf "%s %s %s" "$DISTRO_FAMILY" "$a" "$DISTRO_MACHINE"' \
		sh "$repo/scripts/dwm-utils.sh"
}
expect_family() {
	local got
	got=$(family "$1" "$2")
	if [[ $got != "$3" ]]; then
		printf 'Identity %s on %s: expected "%s", got "%s".\n' "${1##*/}" "$2" "$3" "$got" >&2
		exit 1
	fi
}
expect_family "$work/arch" x86_64 'arch yes x86_64'
# Arch's own aarch64 port, if it ever ships, is still Arch.
expect_family "$work/arch" aarch64 'arch yes aarch64'
expect_family "$work/archarm" aarch64 'arch yes aarch64'
# 32-bit Arch Linux ARM is out of scope.
expect_family "$work/archarm" armv7l 'unknown no armv7l'
expect_family "$work/archarm" x86_64 'unknown no x86_64'
# ID_LIKE=arch is never enough.
expect_family "$work/derivative" x86_64 'unknown no x86_64'
expect_family "$work/derivative" aarch64 'unknown no aarch64'

# Arch Linux ARM on armv7 and a derivative are rejected before any change,
# naming the identity and the architecture found.
reject_install() {
	local release=$1 machine=$2 expect=$3 out=$work/reject-${1##*/}-$2.out status
	snapshot_tree "$work/unsupported-home" "$work/home.before"
	set +e
	DWM_TEST_MODE=1 DWM_OS_RELEASE="$release" DWM_MACHINE="$machine" \
		DWM_MUTATION_LOG="$work/mutations.log" HOME="$work/unsupported-home" \
		PATH="$work/bin:$PATH" "$repo/install.sh" \
		--non-interactive --profile core >"$out" 2>&1
	status=$?
	set -e
	if [[ $status -ne 1 ]] || ! grep -Fq "$expect" "$out"; then
		printf 'install.sh on %s/%s: exit %s, expected a rejection naming "%s".\n' \
			"${release##*/}" "$machine" "$status" "$expect" >&2
		cat "$out" >&2
		exit 1
	fi
	snapshot_tree "$work/unsupported-home" "$work/home.after"
	if [[ -e $work/mutations.log ]] || ! cmp -s "$work/home.before" "$work/home.after"; then
		printf 'install.sh on %s/%s attempted a mutation.\n' "${release##*/}" "$machine" >&2
		exit 1
	fi
}
reject_install "$work/archarm" armv7l 'Unsupported distribution: Arch Linux ARM (ID=archarm on armv7l)'
reject_install "$work/derivative" aarch64 \
	'Unsupported distribution: Example Arch Derivative (ID=example-arch on aarch64)'

# Arch Linux ARM on aarch64 gets past the identity check, and the CachyOS
# repositories, asked for, are skipped with their existing message.
DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/archarm" DWM_MACHINE=aarch64 \
	"$repo/install.sh" --dry-run --profile full --enable-cachyos-repos \
	>"$work/archarm-dry-run.out" 2>&1 || {
	printf 'install.sh --dry-run failed on Arch Linux ARM/aarch64.\n' >&2
	cat "$work/archarm-dry-run.out" >&2
	exit 1
}
grep -Fq 'Distribution: Arch Linux ARM' "$work/archarm-dry-run.out"
grep -Fq 'The CachyOS repositories are x86_64 Arch only; skipping them.' "$work/archarm-dry-run.out"
grep -Fq 'Dry run complete; no changes were made.' "$work/archarm-dry-run.out"

# The settings provider and the health check name Arch Linux ARM's family.
grep -Eq '^[[:space:]]*arch \| archarm\) printf' "$repo/scripts/dwm-settings-provider"
grep -Fq '[[ $id == arch || $id == archarm ]] && family=arch' "$repo/scripts/dwm-system-health"

printf 'Arch Linux platform contract (Arch Linux, Arch Linux ARM on aarch64): PASS\n'
