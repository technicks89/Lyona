#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

[[ ${DWM_SECURITY_CONTAINER:-0} == 1 ]] || {
	printf 'SKIP: privileged display-helper security test is container-only\n'
	exit 77
}
[[ -e /.dockerenv || -e /run/.containerenv ]] || {
	printf 'Refusing to modify installed paths outside a disposable container\n' >&2
	exit 1
}
[[ $EUID == 0 ]] || {
	printf 'The container security test must run as root\n' >&2
	exit 1
}

work=$(mktemp -d)
custom_prefix=$(mktemp -d /opt/lyona-security-test.XXXXXX)
created_main_config=0
cleanup() {
	if [[ $created_main_config == 1 ]]; then
		rm -f /etc/X11/xorg.conf
	fi
	rm -rf "$work" "$custom_prefix"
}
trap cleanup EXIT
mkdir -p "$custom_prefix/bin" "$custom_prefix/libexec/lyona" \
	"$work/bin" "$work/home/display-profiles"

installed="$custom_prefix/libexec/lyona/dwm-settings-display-root"
setup="$custom_prefix/bin/dwm-display-setup"
sed "s|@PREFIX@|$custom_prefix|g" "$repo/scripts/dwm-settings-display-root" |
	install -o root -g root -m 0755 /dev/stdin "$installed"
install -o root -g root -m 0755 "$repo/scripts/dwm-display-setup" "$setup"
install -o root -g root -m 0755 "$repo/scripts/dwm-settings-display" \
	"$custom_prefix/bin/dwm-settings-display"

if env PKEXEC_UID=1000 "$repo/scripts/dwm-settings-display-root" rollback 2>"$work/repository.err"; then
	printf 'repository helper copy was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted installed path' "$work/repository.err"

chmod 0775 "$installed"
if env PKEXEC_UID=1000 "$installed" rollback 2>"$work/writable.err"; then
	printf 'writable installed helper was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted root-owned executable' "$work/writable.err"
chmod 0755 "$installed"

chown 65534:65534 "$installed"
if env PKEXEC_UID=1000 "$installed" rollback 2>"$work/owner.err"; then
	printf 'non-root-owned helper was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted root-owned executable' "$work/owner.err"
chown root:root "$installed"

mv "$installed" "$work/real-helper"
ln -s "$work/real-helper" "$installed"
if env PKEXEC_UID=1000 "$installed" rollback 2>"$work/symlink.err"; then
	printf 'symlinked helper was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted installed path' "$work/symlink.err"
rm -f "$installed"
sed "s|@PREFIX@|$custom_prefix|g" "$repo/scripts/dwm-settings-display-root" |
	install -o root -g root -m 0755 /dev/stdin "$installed"

if env PKEXEC_UID=1000 "$installed" install :99 '' "HDMI-1 --mode 1920x1080;touch $work/injected" \
	2>"$work/structured.err"; then
	printf 'unstructured display input was accepted\n' >&2
	exit 1
fi
grep -Fq 'invalid structured display record' "$work/structured.err"
[[ ! -e $work/injected ]]

if [[ ! -e /etc/X11/xorg.conf ]]; then
	install -Dm644 /dev/null /etc/X11/xorg.conf
	created_main_config=1
fi
if env PKEXEC_UID=1000 "$installed" install :99 '' "HDMI-1 --primary --mode 1920x1080 --rate 60 --pos 0x0 --rotate normal" \
	2>"$work/main-config.err"; then
	printf 'existing main Xorg configuration bypassed the conflict guard\n' >&2
	exit 1
fi
grep -Fq 'may conflict; migrate or remove it' "$work/main-config.err"
if [[ $created_main_config == 1 ]]; then
	rm -f /etc/X11/xorg.conf
	created_main_config=0
fi

cat >"$work/home/display-profiles/desk.conf" <<'EOF'
HDMI-1 --primary --mode 1920x1080 --rate 60 --pos 0x0 --rotate normal
EOF
cat >"$work/bin/pkexec" <<'EOF'
#!/bin/sh
printf 'authorization denied\n' >&2
exit 126
EOF
chmod 0755 "$work/bin/pkexec"

chmod 0644 "$installed"
if env PKEXEC_UID=1000 /usr/bin/bash "$installed" rollback 2>"$work/non-executable-root.err"; then
	printf 'non-executable installed helper was accepted by its trust check\n' >&2
	exit 1
fi
grep -Fq 'trusted root-owned executable' "$work/non-executable-root.err"
env PATH="$work/bin:$custom_prefix/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-settings-provider" discover >"$work/non-executable-provider"
grep -Fq $'capability\tdisplays\tdisplay-persistence\tPersistent display profiles\trestricted\tprivileged' \
	"$work/non-executable-provider"
if env DISPLAY=:99 HOME="$work/home" DWM_DISPLAY_PROFILE_DIR="$work/home/display-profiles" \
	PATH="$work/bin:$custom_prefix/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-settings-display" install-profile desk 2>"$work/non-executable-client.err"; then
	printf 'non-executable installed helper was accepted by the client\n' >&2
	exit 1
fi
grep -Fq 'trusted persistent-display helper is unavailable' "$work/non-executable-client.err"
chmod 0755 "$installed"

if env DISPLAY=:99 HOME="$work/home" DWM_DISPLAY_PROFILE_DIR="$work/home/display-profiles" \
	PATH="$work/bin:$custom_prefix/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-settings-display" install-profile desk 2>"$work/polkit.err"; then
	printf 'authorization denial reported success\n' >&2
	exit 1
fi
grep -Fq 'authorization denied' "$work/polkit.err"

chmod 0777 "$custom_prefix/libexec/lyona"
if env DISPLAY=:99 HOME="$work/home" DWM_DISPLAY_PROFILE_DIR="$work/home/display-profiles" \
	PATH="$work/bin:$custom_prefix/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-settings-display" install-profile desk 2>"$work/writable-parent.err"; then
	printf 'helper under a writable parent was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted persistent-display helper is unavailable' "$work/writable-parent.err"
chmod 0755 "$custom_prefix/libexec/lyona"

mv "$custom_prefix/libexec/lyona" "$work/real-libexec"
ln -s "$work/real-libexec" "$custom_prefix/libexec/lyona"
if env DISPLAY=:99 HOME="$work/home" DWM_DISPLAY_PROFILE_DIR="$work/home/display-profiles" \
	PATH="$work/bin:$custom_prefix/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-settings-display" install-profile desk 2>"$work/symlink-parent.err"; then
	printf 'helper under a symlinked parent was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted persistent-display helper is unavailable' "$work/symlink-parent.err"
rm -f "$custom_prefix/libexec/lyona"
mv "$work/real-libexec" "$custom_prefix/libexec/lyona"

chmod 0777 "$custom_prefix/bin"
if env PKEXEC_UID=1000 "$installed" rollback 2>"$work/writable-bin-parent.err"; then
	printf 'setup under a writable parent was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted dwm-display-setup is unavailable' "$work/writable-bin-parent.err"
chmod 0755 "$custom_prefix/bin"

mv "$custom_prefix/bin" "$work/real-bin"
ln -s "$work/real-bin" "$custom_prefix/bin"
if env PKEXEC_UID=1000 "$installed" rollback 2>"$work/symlink-bin-parent.err"; then
	printf 'setup under a symlinked parent was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted dwm-display-setup is unavailable' "$work/symlink-bin-parent.err"
rm -f "$custom_prefix/bin"
mv "$work/real-bin" "$custom_prefix/bin"

chmod 0644 "$setup"
if env PKEXEC_UID=1000 "$installed" rollback 2>"$work/non-executable-setup.err"; then
	printf 'non-executable display setup helper was accepted\n' >&2
	exit 1
fi
grep -Fq 'trusted dwm-display-setup is unavailable' "$work/non-executable-setup.err"
env PATH="$work/bin:$custom_prefix/bin:/usr/bin:/bin" \
	"$repo/scripts/dwm-settings-provider" discover >"$work/non-executable-setup-provider"
grep -Fq $'capability\tdisplays\tdisplay-persistence\tPersistent display profiles\trestricted\tprivileged' \
	"$work/non-executable-setup-provider"
chmod 0755 "$setup"

if "$installed" rollback 2>"$work/direct-root.err"; then
	printf 'direct root execution without a polkit caller marker was accepted\n' >&2
	exit 1
fi
grep -Fq 'must run through polkit as root' "$work/direct-root.err"

if env PKEXEC_UID=1000 "$installed" rollback 2>"$work/custom-prefix.err"; then
	printf 'custom-prefix rollback unexpectedly found a backup\n' >&2
	exit 1
fi
grep -Fq 'no backup found' "$work/custom-prefix.err"

# GHSA-c897-2mjw-fwhh: the setup runs with root's own HOME, and with a
# root-owned copy of the user's X authority read with the user's permissions,
# never the user's own path. A stand-in setup records what it was given.
xuser=lyonadisplaytest
id -u "$xuser" >/dev/null 2>&1 || useradd -m "$xuser"
xuid=$(id -u "$xuser")
xhome=$(getent passwd "$xuser" | cut -d: -f6)
record=$work/setup.record
cat >"$work/setup-stub" <<EOF
#!/bin/sh
{
	printf 'HOME=%s\n' "\$HOME"
	printf 'XAUTH=%s\n' "\$XAUTHORITY"
	stat -c 'OWNER=%u MODE=%a' "\$XAUTHORITY"
	printf 'CONTENT=%s\n' "\$(cat "\$XAUTHORITY")"
} >$record
EOF
install -o root -g root -m 0755 "$work/setup-stub" "$setup"
rm -f /etc/X11/xorg.conf
xinstall() { # XAUTHORITY
	rm -f "$record"
	env PKEXEC_UID="$xuid" "$installed" install :99 "$1" "HDMI-1 --mode 1920x1080" 2>"$work/xauth.err" || {
		cat "$work/xauth.err" >&2
		printf 'the display install failed\n' >&2
		exit 1
	}
	[[ -s $record ]] || {
		printf 'the setup did not run\n' >&2
		exit 1
	}
}
expect_record() { # LINE MESSAGE
	grep -Fxq -- "$1" "$record" || {
		cat "$record" >&2
		printf '%s\n' "$2" >&2
		exit 1
	}
}
printf 'user-cookie\n' | install -o "$xuid" -g "$xuid" -m 0600 /dev/stdin "$xhome/.Xauthority"
xinstall "$xhome/.Xauthority"
expect_record 'HOME=/root' "the setup did not run with root's HOME"
expect_record 'OWNER=0 MODE=600' 'the X authority given to the setup is not a root-owned private copy'
expect_record 'CONTENT=user-cookie' 'the copy does not hold the user'"'"'s X authority'
if grep -Fxq "XAUTH=$xhome/.Xauthority" "$record"; then
	printf 'the setup was given the user'"'"'s own X authority path\n' >&2
	exit 1
fi
copy=$(sed -n 's/^XAUTH=//p' "$record")
[[ ! -e $copy ]] || {
	printf 'the X authority copy was left behind: %s\n' "$copy" >&2
	exit 1
}
# A link to a file only root can read: the copy is read as the user, so it is
# empty, never the file's contents.
ln -s /etc/shadow "$xhome/shadow-link"
chown -h "$xuid:$xuid" "$xhome/shadow-link"
xinstall "$xhome/shadow-link"
expect_record 'CONTENT=' 'root read a file through the user'"'"'s X authority link'
# None given: the user's ~/.Xauthority, as Xlib would have looked for it.
xinstall ''
expect_record 'CONTENT=user-cookie' 'without an X authority, the user'"'"'s ~/.Xauthority was not used'

printf 'Privileged display-helper trust and authorization denial: PASS\n'
