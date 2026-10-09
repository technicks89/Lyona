#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 16 R16-28: the installer's summary lists every change it makes
# before asking: the yay build, the mybash links, the wallpaper download,
# LightDM, the gamemode group. And [multilib] is Arch's own repository, not a
# third-party one. Run as dry runs, with a scratch home.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
if ! grep -Eqs '^ID=arch$' /etc/os-release; then
	printf 'SKIP: the installer dry run needs Arch Linux\n'
	exit 77
fi

mkdir -p "$work/home"
plan() { # PROFILE [ARGS...]
	local profile=$1
	shift
	env HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/home/.local/share" \
		"$repo/install.sh" --dry-run --non-interactive --profile "$profile" "$@" 2>&1
}
has() { # PLAN TEXT
	[[ $1 == *"$2"* ]] || fail "the summary does not say: $2"$'\n'"$1"
}
lacks() { # PLAN TEXT
	[[ $1 != *"$2"* ]] || fail "the summary says, but should not: $2"
}

core=$(plan core)
has "$core" '  AUR helper: '
# The dwm build (#289): what config.h will be, and the questions only on request.
if [[ -e $repo/config.h ]]; then
	has "$core" '  dwm build: your existing config.h, kept'
else
	has "$core" '  dwm build: config.def.h defaults (use --configure-build to choose)'
fi
if refused=$(plan core --configure-build); then
	fail '--configure-build was accepted with --non-interactive'
fi
has "$refused" 'cannot run with --non-interactive'
grep -Fq -- '--configure-build' <("$repo/install.sh" --help) || fail '--help does not list --configure-build'
# Without a config.h (a copy of the tracked files): DWM_* overrides are named,
# a dry run says when the questions would come, and answers given then declined
# at the summary leave no config.h behind (#289).
fresh=$work/fresh
mkdir -p "$fresh"
git -C "$repo" ls-files -z | (cd "$repo" && tar --null -T - -cf -) | tar -x -C "$fresh"
[[ ! -e $fresh/config.h ]] || fail 'the scratch copy has a config.h'
fresh_plan() {
	env HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/home/.local/share" \
		"$fresh/install.sh" --dry-run --non-interactive --profile core 2>&1
}
has "$(fresh_plan)" '  dwm build: config.def.h defaults (use --configure-build to choose)'
has "$(DWM_FONT_SIZE=14 DWM_MODKEY=alt fresh_plan)" '  dwm build: config.def.h defaults, with DWM_FONT_SIZE=14 DWM_MODKEY=alt'
if command -v script >/dev/null 2>&1; then
	in_terminal() { # INPUT ARGS...: install.sh in a terminal, fed INPUT
		local input=$1
		shift
		printf '%b' "$input" | env HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" \
			XDG_DATA_HOME="$work/home/.local/share" DWM_INSTALL_CACHYOS_REPOS=true DWM_INSTALL_CACHYOS_KERNEL=true \
			script -qec "$(printf '%q ' "$fresh/install.sh" --profile core "$@")" /dev/null 2>&1
	}
	dry=$(in_terminal '' --dry-run --configure-build) || fail "a dry run with --configure-build failed: $dry"
	has "$dry" 'the --configure-build answers, asked before this summary in a real install'
	declined=$(in_terminal '\n\n\n\n\n\n\n\nn\n' --configure-build) && fail 'a declined summary went on'
	has "$declined" 'your answers above, written to config.h once you continue'
	has "$declined" 'Installation cancelled'
	[[ ! -e $fresh/config.h ]] || fail 'answers declined at the summary still wrote config.h'
fi
# Every profile, whatever this machine's state (#258).
has "$core" '  Time synchronization: '
lacks "$core" 'Shell configuration: mybash'
lacks "$core" 'Wallpapers: '

recommended=$(plan recommended)
has "$recommended" 'Shell configuration: mybash replaces ~/.bashrc'
has "$recommended" '(previous files kept as .bak.<time>)'
lacks "$recommended" 'Wallpapers: '

full=$(plan full --enable-arch-gaming-repos)
has "$full" "  Wallpapers: downloaded into $work/home/Pictures/backgrounds (pinned commit)"
has "$full" '  Display manager: '
lacks "$full" 'Third-party repositories'
if [[ $full == *'Arch gaming packages:'* ]]; then
	has "$full" '  Arch [multilib] repository: '
	has "$full" "  gamemode group: $(id -un) is added to it"
fi
mkdir -p "$work/home/Pictures/backgrounds"
has "$(plan full)" "  Wallpapers: already present in $work/home/Pictures/backgrounds"

# The summary leads with the system changes, then the packages, then this
# account; no package command (it showed --noconfirm even when pacman asks)
# and no repeated header lines (#294).
for summary in "$core" "$recommended" "$full"; do
	order=$(grep -x -e 'System changes:' -e 'Packages:' -e 'For this account:' <<<"$summary" | paste -sd '|' -)
	[[ $order == 'System changes:|Packages:|For this account:' ]] ||
		fail "the summary sections are out of order: $order"
	lacks "$summary" 'Package manager:'
	lacks "$summary" '--noconfirm'
	lacks "$summary" '  Family:'
done
has "$recommended" '  System upgrade: every installed package'
has "$full" '  Required packages: '
# The CachyOS question comes after the plan, just before the confirmation,
# when it is asked at all (x86_64, repositories not configured yet).
if command -v script >/dev/null 2>&1; then
	# A pacman.conf without the CachyOS sections, so the question comes up even
	# on a machine that has them.
	printf '[options]\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$work/pacman.conf"
	asked=$(printf 'n\nn\n' | env HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" \
		XDG_DATA_HOME="$work/home/.local/share" LYONA_CACHYOS_PACMAN_CONF="$work/pacman.conf" \
		script -qec "$(printf '%q ' "$fresh/install.sh" --profile core)" /dev/null 2>&1) || :
	if [[ $asked == *'an interactive install asks after this summary'* ]]; then
		question=$(grep -n -m1 'Add the CachyOS repositories?' <<<"$asked" | cut -d: -f1)
		account=$(grep -n -m1 'For this account:' <<<"$asked" | cut -d: -f1)
		continue_at=$(grep -n -m1 'Continue with installation?' <<<"$asked" | cut -d: -f1)
		if [[ -z $question || -z $account || -z $continue_at ]] ||
			((account >= question || question > continue_at)); then
			fail "the CachyOS question is not between the summary and the confirmation"$'\n'"$asked"
		fi
	elif [[ $(uname -m) == x86_64 ]]; then
		fail "an interactive x86_64 run did not say the CachyOS question comes after the summary"$'\n'"$asked"
	fi
fi

# The closing screen lists the run's warnings (#290): warn() keeps them and
# print_completion_banner shows them, with another title. A clean run has none.
{
	sed -n '/^INSTALL_WARNINGS=()$/,/^}$/p' "$repo/install.sh"
	sed -n '/^print_completion_banner() {$/,/^}$/p' "$repo/install.sh"
} >"$work/banner.sh"
grep -q '^print_completion_banner() {$' "$work/banner.sh" || fail 'print_completion_banner not found in install.sh'
# shellcheck disable=SC2016 # expanded by the inner bash
clean=$(bash -c 'YELLOW= NC=; . "$1"; print_completion_banner' bash "$work/banner.sh")
has "$clean" 'Installation Complete!'
lacks "$clean" 'warning'
# shellcheck disable=SC2016 # expanded by the inner bash
warned=$(bash -c 'YELLOW= NC=; . "$1"; warn "Topgrade could not be installed." >/dev/null
	warn "LightDM was not enabled." >/dev/null; print_completion_banner' bash "$work/banner.sh")
lacks "$warned" 'Installation Complete!'
has "$warned" 'Installation finished, with warnings'
has "$warned" 'Finished with 2 warning(s):'
has "$warned" '  - Topgrade could not be installed.'
has "$warned" '  - LightDM was not enabled.'
grep -Fxq 'print_completion_banner' "$repo/install.sh" || fail 'install.sh does not end with print_completion_banner'
# A child script's warnings, from the file install.sh exports, join the list,
# each once though lyona-reconcile-user runs twice (#290).
printf '%s\n' 'AppImages have no default handler.' 'AppImages have no default handler.' >"$work/child-warnings"
# shellcheck disable=SC2016 # expanded by the inner bash
merged=$(LYONA_INSTALL_WARNINGS_FILE="$work/child-warnings" bash -c 'YELLOW= NC=; . "$1"
	warn "Topgrade could not be installed." >/dev/null; print_completion_banner' bash "$work/banner.sh")
has "$merged" 'Finished with 2 warning(s):'
has "$merged" '  - AppImages have no default handler.'
[[ $(grep -c 'AppImages have no default handler' <<<"$merged") == 1 ]] || fail "a repeated child warning was listed twice: $merged"

# NetworkManager (#292): enabled on recommended only when nothing else manages
# the network, and enabled, not started, mid-install. A systemctl stub answers
# from STUB_ENABLED (unit=state pairs) and STUB_ACTIVE (active units).
{
	sed -n '/^network_manager_state() {$/,/^}$/p' "$repo/install.sh"
	sed -n '/^configure_network_manager() {$/,/^}$/p' "$repo/install.sh"
} >"$work/nm.sh"
grep -q '^configure_network_manager() {$' "$work/nm.sh" || fail 'configure_network_manager not found in install.sh'
mkdir -p "$work/nm-bin" "$work/nm-units"
cat >"$work/nm-bin/systemctl" <<'STUB'
#!/bin/sh
case $1 in
is-enabled)
	for pair in $STUB_ENABLED; do
		[ "${pair%%=*}" = "$2" ] && { printf '%s\n' "${pair#*=}"; exit 0; }
	done
	printf 'disabled\n'
	exit 1
	;;
is-active)
	for unit in $STUB_ACTIVE; do [ "$unit" = "$3" ] && exit 0; done
	exit 3
	;;
list-units)
	for unit in $STUB_ACTIVE; do
		case $unit in netctl*) printf '%s loaded active running Profile\n' "$unit" ;; esac
	done
	;;
list-unit-files)
	for pair in $STUB_ENABLED; do
		case $pair in netctl*=enabled) printf '%s enabled disabled\n' "${pair%%=*}" ;; esac
	done
	;;
esac
exit 0
STUB
cat >"$work/nm-bin/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$NM_LOG"
STUB
# Not a chroot unless STUB_CHROOT says so, whatever the machine running this.
cat >"$work/nm-bin/systemd-detect-virt" <<'STUB'
#!/bin/sh
[ -n "${STUB_CHROOT:-}" ]
STUB
chmod +x "$work/nm-bin/systemctl" "$work/nm-bin/sudo" "$work/nm-bin/systemd-detect-virt"
nm_case() { # ENABLED ACTIVE: prints the state, then what configure did
	: >"$work/nm.log"
	# shellcheck disable=SC2016 # expanded by the inner bash
	env PATH="$work/nm-bin:$PATH" NM_LOG="$work/nm.log" STUB_ENABLED="$1" STUB_ACTIVE="$2" \
		LYONA_SYSTEMD_UNIT_DIR="${NM_UNIT_DIR:-$work/nm-units}" \
		${LYONA_SOURCE:+LYONA_SOURCE="$LYONA_SOURCE"} ${STUB_CHROOT:+STUB_CHROOT=1} \
		bash -c 'ok() { :; }; info() { :; }; warn() { :; }; . "$1"; network_manager_state; configure_network_manager' \
		bash "$work/nm.sh"
	cat "$work/nm.log"
}
[[ $(nm_case 'NetworkManager.service=enabled' '') == enabled ]] || fail 'an enabled NetworkManager was not recognised'
[[ $(nm_case 'NetworkManager.service=masked' '') == masked ]] || fail 'a masked NetworkManager was not left alone'
[[ $(nm_case 'systemd-networkd.service=enabled' '') == other:systemd-networkd.service ]] ||
	fail 'NetworkManager was enabled over an enabled systemd-networkd'
[[ $(nm_case '' 'iwd.service') == other:iwd.service ]] || fail 'NetworkManager was enabled over a running iwd'
[[ $(nm_case '' 'netctl@home.service') == other:netctl@home.service ]] ||
	fail 'NetworkManager was enabled over an active netctl profile'
# netctl enabled but not active now (no network in range): still its manager.
[[ $(nm_case 'netctl-auto@wlan0.service=enabled' '') == other:netctl-auto@wlan0.service ]] ||
	fail 'NetworkManager was enabled over an enabled, inactive netctl-auto'
mkdir -p "$work/nm-units-enabled/multi-user.target.wants"
ln -s /usr/lib/systemd/system/netctl@.service "$work/nm-units-enabled/multi-user.target.wants/netctl@office.service"
[[ $(NM_UNIT_DIR=$work/nm-units-enabled nm_case '' '') == other:netctl@office.service ]] ||
	fail 'NetworkManager was enabled over a netctl profile enabled for boot'
[[ $(nm_case '' '') == $'off\nsystemctl enable NetworkManager.service' ]] ||
	fail "NetworkManager was not enabled (and only enabled) when nothing manages the network: $(nm_case '' '')"
# The image install leaves it to its postinstall, which enables it; inside
# that chroot systemctl answers for the live medium (found in a VM).
[[ $(LYONA_SOURCE=iso nm_case 'systemd-networkd.service=enabled' 'systemd-networkd.service') == image ]] ||
	fail 'the image install judged NetworkManager by the live medium'
[[ $(STUB_CHROOT=1 nm_case '' '') == image ]] || fail 'a chroot was not left to the image installer'
has "$recommended" '  NetworkManager: '
lacks "$core" 'NetworkManager: '

# A non-interactive run answers makepkg's pacman prompt: behind the image
# install's spinner nothing else can, and it waited there forever (Sync Sprint
# 16, found in a VM).
yay_fn=$(sed -n '/^ensure_yay_installed() {$/,/^}$/p' "$repo/install.sh")
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq '[[ $NON_INTERACTIVE != true ]] || makepkg_args+=(--noconfirm)' <<<"$yay_fn" ||
	fail 'a non-interactive install does not answer makepkg'

printf 'Installer summary completeness: PASS\n'
