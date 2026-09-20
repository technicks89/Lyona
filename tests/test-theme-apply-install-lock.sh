#!/usr/bin/env bash
# `make install-user` runs theme-apply.sh once, so first login already has a
# converged theme. An installer may hold a lock descriptor while it does. That
# must never be kept alive by anything theme-apply starts: upstream's
# dwm-xsettings launched xsettingsd with those descriptors inherited, so an
# install lock was never released (upstream #328).
#
# Lyona has no such launcher, and this pins why: theme-apply.sh only edits the
# xsettingsd configuration and signals a running daemon. It never starts one
# (autostart.sh does, at login), so nothing can outlive it holding the lock.
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

command -v flock >/dev/null 2>&1 || {
	printf 'SKIP: flock is unavailable\n'
	exit 0
}

home=$work/home
runtime=$work/run
bin=$work/bin
mkdir -p "$home/.config/lyona" "$home/.local/share" "$home/.local/state" \
	"$runtime" "$bin"
chmod 700 "$runtime"
cp "$repo/config/themes.toml" "$home/.config/lyona/themes.toml"

# Everything that could touch the developer's real session is a stub. The
# daemon stub records that it was launched and then stays alive, as a real one
# would, so a launch that leaked the lock would be caught by the holder scan.
cat >"$bin/xsettingsd" <<'SH'
#!/bin/sh
printf 'launched %s\n' "$*" >>"$DWM_TEST_XSETTINGSD_LOG"
sleep 30
SH
cat >"$bin/pkill" <<'SH'
#!/bin/sh
printf 'pkill %s\n' "$*" >>"$DWM_TEST_PKILL_LOG"
SH
for name in gsettings xfconf-query systemctl dbus-update-activation-environment; do
	printf '#!/bin/sh\nexit 0\n' >"$bin/$name"
done
chmod +x "$bin"/*

lock=$work/install.lock
: >"$work/xsettingsd.log"
: >"$work/pkill.log"

# The subshell stands in for the installer: it takes the lock on fd 9 and runs
# the real script with that descriptor inherited.
(
	exec 9>"$lock"
	flock -n 9 || exit 3
	HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
		XDG_STATE_HOME=$home/.local/state XDG_RUNTIME_DIR=$runtime \
		PATH=$bin:/usr/bin:/bin \
		DWM_TEST_XSETTINGSD_LOG=$work/xsettingsd.log DWM_TEST_PKILL_LOG=$work/pkill.log \
		"$repo/scripts/theme-apply.sh" >"$work/apply.out" 2>&1
) || {
	cat "$work/apply.out" >&2 || true
	fail 'theme-apply.sh failed while the installer held a lock'
}

grep -Fq "theme-apply: applied theme" "$work/apply.out" ||
	fail 'theme-apply.sh did not report applying a theme'

# 1. The lock is free again the moment the script returns.
flock -n "$lock" true ||
	fail 'the installer lock is still held after theme-apply.sh returned'

# 2. No process anywhere keeps the lock file open.
holders=
for proc in /proc/[0-9]*; do
	for descriptor in "$proc"/fd/*; do
		if [[ $(readlink "$descriptor" 2>/dev/null) == "$lock" ]]; then
			holders+=" ${proc#/proc/}"
		fi
	done
done
[[ -z $holders ]] || fail "processes still hold the installer lock:$holders"

# 3. It never started the daemon, only edited its file and signalled it.
[[ ! -s $work/xsettingsd.log ]] ||
	fail "theme-apply.sh started xsettingsd: $(cat "$work/xsettingsd.log")"
assert_file "$home/.config/lyona/xsettingsd.conf"
grep -Fq -- '-HUP' "$work/pkill.log" ||
	fail 'theme-apply.sh did not signal a running xsettingsd to reload'

printf 'Install-time theme convergence releases the installer lock: PASS\n'
