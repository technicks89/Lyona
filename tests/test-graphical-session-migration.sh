#!/bin/sh

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

home="$work/home"
config_home="$home/.config"
user_dir="$config_home/systemd/user"
state="$work/state"
mkdir -p "$work/bin" "$user_dir/default.target.wants" "$state"

cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TEST_STATE:?}/systemctl.log"
exit 0
EOF
chmod +x "$work/bin/systemctl"

write_legacy_unit() {
	cat >"$user_dir/dwm-graphical-session.service" <<'EOF'
[Unit]
Description=DWM Graphical Session
BindsTo=graphical-session.target
Wants=graphical-session.target xdg-desktop-autostart.target
After=basic.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true

[Install]
WantedBy=default.target
EOF
}

write_legacy_unit
ln -s ../dwm-graphical-session.service \
	"$user_dir/default.target.wants/dwm-graphical-session.service"
printf '%s\n' '# renamed graphical session service' \
	>"$user_dir/wm-graphical-session.service"
ln -s ../wm-graphical-session.service \
	"$user_dir/default.target.wants/wm-graphical-session.service"
printf '%s\n' '# unrelated service' >"$user_dir/custom.service"
ln -s ../custom.service "$user_dir/default.target.wants/custom.service"

HOME=$home \
	XDG_CONFIG_HOME=$config_home \
	TEST_STATE=$state \
	PATH="$work/bin:/usr/bin:/bin" \
	sh "$repo/scripts/migrate-graphical-session.sh"

test ! -e "$user_dir/dwm-graphical-session.service"
test ! -e "$user_dir/default.target.wants/dwm-graphical-session.service"
test -f "$user_dir/wm-graphical-session.service"
test ! -e "$user_dir/default.target.wants/wm-graphical-session.service"
test -f "$user_dir/custom.service"
test -L "$user_dir/default.target.wants/custom.service"
grep -Fqx -- '--user disable dwm-graphical-session.service' "$state/systemctl.log"
grep -Fqx -- '--user disable wm-graphical-session.service' "$state/systemctl.log"
grep -Fqx -- '--user daemon-reload' "$state/systemctl.log"

HOME=$home \
	XDG_CONFIG_HOME=$config_home \
	TEST_STATE=$state \
	PATH="$work/bin:/usr/bin:/bin" \
	sh "$repo/scripts/migrate-graphical-session.sh"

cat >"$user_dir/dwm-graphical-session.service" <<'EOF'
[Unit]
Description=Custom user graphical session

[Service]
Type=oneshot
ExecStart=/usr/bin/true

[Install]
WantedBy=default.target
EOF
ln -s ../dwm-graphical-session.service \
	"$user_dir/default.target.wants/dwm-graphical-session.service"

HOME=$home \
	XDG_CONFIG_HOME=$config_home \
	TEST_STATE=$state \
	PATH="$work/bin:/usr/bin:/bin" \
	sh "$repo/scripts/migrate-graphical-session.sh"

test -f "$user_dir/dwm-graphical-session.service"
test ! -e "$user_dir/default.target.wants/dwm-graphical-session.service"
grep -Fqx 'Description=Custom user graphical session' \
	"$user_dir/dwm-graphical-session.service"

printf '%s\n' "Graphical-session migration: PASS"
