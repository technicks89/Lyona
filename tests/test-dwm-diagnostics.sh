#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
HELPER="$repo/scripts/dwm-diagnostics"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home/.config"

for cmd in cc make Xorg startx xrandr xset xsetroot xclip xdotool alacritty; do
	cat >"$work/bin/$cmd" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
	chmod +x "$work/bin/$cmd"
done

cat >"$work/bin/pkg-config" <<'SCRIPT'
#!/bin/sh
test "$1" = "--exists"
case "$2" in
	x11|xft|xinerama|xrender|imlib2|x11-xcb|xcb|xcb-res)
		exit 0
		;;
esac
exit 1
SCRIPT
chmod +x "$work/bin/pkg-config"

# pacman -T: 0 when installed, 127 when not (Sync Sprint 15 S15-01).
cat >"$work/bin/pacman" <<'SCRIPT'
#!/bin/sh
test "$1" = "-T" || exit 1
case " ${FAKE_PACMAN_MISSING:-} " in
*" $2 "*) printf '%s\n' "$2"; exit 127 ;;
esac
exit "${FAKE_PACMAN_STATUS:-0}"
SCRIPT
chmod +x "$work/bin/pacman"
for cmd in tr cut; do
	ln -s "$(command -v "$cmd")" "$work/bin/$cmd"
done

env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/ok"
grep -Fqx "  required_failures=0" "$work/ok"
grep -Fqx "  ok      gnome-keyring" "$work/ok"
# A missing keyring is a warning, as for the rest of the desktop group (D-24).
env HOME="$work/home" PATH="$work/bin" FAKE_PACMAN_MISSING=gnome-keyring \
	"$BASH_BIN" "$HELPER" >"$work/keyring-missing"
grep -Fqx "  degraded gnome-keyring" "$work/keyring-missing"
grep -Fqx "  required_failures=0" "$work/keyring-missing"
env HOME="$work/home" PATH="$work/bin" FAKE_PACMAN_MISSING=gnome-keyring \
	"$BASH_BIN" "$HELPER" --format health-tsv >"$work/keyring-missing.tsv"
grep -F "$(printf '\twarn\tdependency-package-gnome-keyring\tgnome-keyring\tInstall gnome-keyring for secret storage')" \
	"$work/keyring-missing.tsv" >/dev/null ||
	fail "no warn row for a missing gnome-keyring in health-tsv"
env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" --format health-tsv >"$work/keyring-ok.tsv"
grep -F "$(printf '\tok\tdependency-package-gnome-keyring\t')" "$work/keyring-ok.tsv" >/dev/null ||
	fail "no ok row for an installed gnome-keyring in health-tsv"
# A failed query is reported as such, never as installed.
env HOME="$work/home" PATH="$work/bin" FAKE_PACMAN_STATUS=1 \
	"$BASH_BIN" "$HELPER" --format health-tsv >"$work/keyring-error.tsv"
grep -F "Could not check gnome-keyring (pacman -T failed)" "$work/keyring-error.tsv" >/dev/null ||
	fail "a failed pacman -T was not reported"
grep -Fq "Optional desktop" "$work/ok"
grep -Fq "degraded quickshell" "$work/ok"
grep -Fq "degraded maim" "$work/ok"
# The developer override is always reported (Sync Sprint 12 S12-13).
grep -Fqx "  LYONA_DEV_SCRIPTS not set (installed helpers)" "$work/ok"
env HOME="$work/home" PATH="$work/bin" LYONA_DEV_SCRIPTS="$work/checkout/scripts" \
	"$BASH_BIN" "$HELPER" >"$work/dev"
grep -Fqx "  LYONA_DEV_SCRIPTS=$work/checkout/scripts (helpers from a development checkout)" "$work/dev"

rm -f "$work/bin/alacritty" "$work/bin/Xorg"

if env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/fail" 2>"$work/err"; then
	echo "diagnostics passed despite missing required commands" >&2
	exit 1
fi

grep -Fq "missing X11 server" "$work/fail"
grep -Fq "missing terminal" "$work/fail"
grep -Fq "Required failures must be fixed" "$work/err"
