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
grep -Fq 'Unsupported distribution: Unsupported Linux' "$work/install-rejection.out"
grep -Fq 'lyona supports Arch Linux only.' "$work/install-rejection.out"
if [[ -e $work/mutations.log ]]; then
	printf 'Unsupported installer attempted a package or system mutation.\n' >&2
	exit 1
fi
snapshot_tree "$work/unsupported-home" "$work/home.after"
cmp "$work/home.before" "$work/home.after"

awk -v os_release="$work/unsupported" '
	$0 == "OS_RELEASE_FILE=/etc/os-release" {
		print "OS_RELEASE_FILE=" os_release
		next
	}
	{ print }
' "$repo/scripts/power-management.sh" >"$work/power-management-unsupported"
grep -Fqx "OS_RELEASE_FILE=$work/unsupported" \
	"$work/power-management-unsupported"
chmod +x "$work/power-management-unsupported"
set +e
"$work/power-management-unsupported" --apply >"$work/power-rejection.out" 2>&1
power_status=$?
set -e
if [[ $power_status -ne 1 ]]; then
	printf 'Unsupported power mutation exited with %s instead of 1.\n' \
		"$power_status" >&2
	exit 1
fi
grep -Fq -- '--apply and --apply-tlp support Arch Linux only.' \
	"$work/power-rejection.out"
if grep -Fq 'System Identity' "$work/power-rejection.out"; then
	printf 'Unsupported power mutation continued into the status report.\n' >&2
	exit 1
fi

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
grep -Fq 'lyona supports Arch Linux only.' "$work/xscreensaver-rejection.out"
snapshot_tree "$work/unsupported-home" "$work/screensaver-home.after"
if [[ -e $work/mutations.log ]] ||
	! cmp "$work/screensaver-home.before" "$work/screensaver-home.after"; then
	printf 'Unsupported screensaver setup attempted a mutation.\n' >&2
	exit 1
fi

printf 'Arch Linux-only platform contract: PASS\n'
