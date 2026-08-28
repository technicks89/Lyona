#!/bin/sh

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

view_body=$(sed -n '/^view(const Arg \*arg)/,/^}$/p' "$repo/dwm.c")

printf '%s\n' "$view_body" | grep -q 'selmon = targetmon;'
printf '%s\n' "$view_body" | grep -q 'focus(NULL);'
printf '%s\n' "$view_body" | grep -q 'focusfirsttagged(arg->ui);'
printf '%s\n' "$view_body" | grep -q 'updatecurrentdesktop();'

# The focus-and-warp that view() used to inline twice.
focus_first_tagged_body=$(
	sed -n '/^focusfirsttagged(unsigned int tags)/,/^}$/p' "$repo/dwm.c"
)
printf '%s\n' "$focus_first_tagged_body" | grep -q '(c->tags & tags) && ISVISIBLE(c)'
printf '%s\n' "$focus_first_tagged_body" | grep -q 'focus(c);'
printf '%s\n' "$focus_first_tagged_body" | grep -q 'XWarpPointer(dpy, None, c->win'
printf '%s\n' "$focus_first_tagged_body" | grep -q 'XWarpPointer(dpy, None, root'
# The monitor-centre fallback must stay outside the loop, so it only fires
# when no client matched.
fallback_block=$(
	printf '%s\n' "$focus_first_tagged_body" | sed -n '/^\t}$/,$p'
)
printf '%s\n' "$fallback_block" | grep -q 'XWarpPointer(dpy, None, root'

same_tag_block=$(printf '%s\n' "$view_body" |
	sed -n '/== selmon->tagset\[selmon->seltags\]/,/return;/p')
printf '%s\n' "$same_tag_block" | grep -q 'arrange(selmon);'
printf '%s\n' "$same_tag_block" | grep -q 'focus(NULL);'
printf '%s\n' "$same_tag_block" | grep -q 'focusfirsttagged(arg->ui);'
printf '%s\n' "$same_tag_block" | grep -q 'updatecurrentdesktop();'

update_current_body=$(sed -n '/^updatecurrentdesktop(void)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$update_current_body" | grep -q 'getmonlogicalindex(m)'
printf '%s\n' "$update_current_body" | grep -q 'netatom\[NetDwmMonitorDesktops\]'
grep -q 'XInternAtom(dpy, "_DWM_MONITOR_DESKTOPS", False)' "$repo/dwm.c"

configure_body=$(sed -n '/^configurenotify(XEvent \*e)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$configure_body" | grep -q 'reconcilemonitortags();'
reconcile_line=$(printf '%s\n' "$configure_body" | grep -n 'reconcilemonitortags();' | cut -d: -f1)
scan_bars_line=$(printf '%s\n' "$configure_body" | grep -n 'scanaltbars();' | cut -d: -f1)
client_list_line=$(printf '%s\n' "$configure_body" |
	grep -n 'updateclientlist();' | cut -d: -f1 | sed -n '1p')
publish_line=$(printf '%s\n' "$configure_body" | grep -n 'updatecurrentdesktop();' | cut -d: -f1)
test "$reconcile_line" -lt "$scan_bars_line"
test "$scan_bars_line" -lt "$client_list_line"
test "$reconcile_line" -lt "$client_list_line"
test "$client_list_line" -lt "$publish_line"
test "$reconcile_line" -lt "$publish_line"
managed_client_line=$(printf '%s\n' "$configure_body" |
	grep -n '!wintoclient(ev->window)' | cut -d: -f1)
attributes_line=$(printf '%s\n' "$configure_body" |
	grep -n 'XGetWindowAttributes(dpy, ev->window, &wa)' | cut -d: -f1)
test "$managed_client_line" -lt "$attributes_line"
printf '%s\n' "$configure_body" | grep -q 'isaltbar(ev->window, &wa)'
printf '%s\n' "$configure_body" | grep -q 'm = recttomon(wa.x, wa.y, wa.width, wa.height);'
printf '%s\n' "$configure_body" | grep -q 'm = oldm;'
printf '%s\n' "$configure_body" | grep -q 'oldm->barwin = 0;'
printf '%s\n' "$configure_body" | grep -q 'oldm->bh = 0;'
printf '%s\n' "$configure_body" | grep -q 'arrange(oldm);'

reconcile_body=$(sed -n '/^reconcilemonitortags(void)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$reconcile_body" | grep -q 'updatemonitorcount();'
printf '%s\n' "$reconcile_body" | grep -q 'm->tagset\[s\] &= montags;'
printf '%s\n' "$reconcile_body" | grep -q 'm->tagset\[s\] = fallbacktag;'
printf '%s\n' "$reconcile_body" | grep -q 'c->tags & getmontagmask(owner->num)'
printf '%s\n' "$reconcile_body" | grep -q 'c->mon = owner;'
printf '%s\n' "$reconcile_body" | grep -q 'c->tags &= getmontagmask(owner->num);'
printf '%s\n' "$reconcile_body" | grep -q 'c->tags &= montags;'
printf '%s\n' "$reconcile_body" | grep -q 'c->x = owner->mx + c->x - m->mx;'
printf '%s\n' "$reconcile_body" | grep -q 'wasselected = c == m->sel;'
printf '%s\n' "$reconcile_body" | grep -q 'wasfocused = wasselected && m == selmon;'
printf '%s\n' "$reconcile_body" | grep -q 'owner->sel = c;'
printf '%s\n' "$reconcile_body" | grep -q 'selmon = owner;'
printf '%s\n' "$reconcile_body" | grep -q 'm->tagset\[m->seltags\] == montags'
printf '%s\n' "$reconcile_body" | grep -q 'm->pertag->curtag == 0'
printf '%s\n' "$reconcile_body" | grep -q 'm->nmaster = m->pertag->nmasters\[m->pertag->curtag\];'
printf '%s\n' "$reconcile_body" | grep -q 'm->mfact = m->pertag->mfacts\[m->pertag->curtag\];'
printf '%s\n' "$reconcile_body" | grep -q 'm->lt\[m->sellt\] = m->pertag->ltidxs'
printf '%s\n' "$reconcile_body" | grep -q 'm->showbar = m->pertag->showbars\[m->pertag->curtag\];'

update_client_list_body=$(sed -n '/^updateclientlist(void)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$update_client_list_body" | grep -q 'PropModeReplace'
printf '%s\n' "$update_client_list_body" | grep -q 'memcmp(clients, clientlistcache'
scan_alt_bars_body=$(sed -n '/^scanaltbars(void)/,/^}$/p' "$repo/dwm.c")
query_tree_line=$(printf '%s\n' "$scan_alt_bars_body" |
	grep -n 'XQueryTree' | cut -d: -f1)
clear_bars_line=$(printf '%s\n' "$scan_alt_bars_body" |
	grep -n 'm->barwin = 0;' | cut -d: -f1)
test "$query_tree_line" -lt "$clear_bars_line"
printf '%s\n' "$scan_alt_bars_body" | grep -q 'knownbars\[i\] = m->barwin;'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'm->barwin = 0;'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'wa.map_state != IsViewable'
printf '%s\n' "$scan_alt_bars_body" | grep -q '!isaltbar(wins\[i\], &wa)'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'knownbars\[j\] == wins\[i\]'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'INTERSECT(wa.x, wa.y, wa.width, wa.height, m) <= 0'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'm = oldm;'
printf '%s\n' "$scan_alt_bars_body" | grep -q 'updatealtbar(m, wins\[i\], &wa);'
update_alt_bar_body=$(sed -n '/^updatealtbar(Monitor \*m, Window win, XWindowAttributes \*wa)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$update_alt_bar_body" | grep -q 'changed = m->barwin != win'
printf '%s\n' "$update_alt_bar_body" | grep -q 'return changed;'
manage_alt_bar_body=$(sed -n '/^managealtbar(Window win, XWindowAttributes \*wa)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$manage_alt_bar_body" | grep -q 'changed = updatealtbar(m, win, wa);'
printf '%s\n' "$manage_alt_bar_body" | grep -q 'if (changed)'
printf '%s\n' "$manage_alt_bar_body" | grep -q 'XMapWindow(dpy, win);'
changed_arrange_block=$(printf '%s\n' "$manage_alt_bar_body" |
	sed -n '/if (changed)/,/arrange(m);/p')
if printf '%s\n' "$changed_arrange_block" | grep -q 'XMapWindow'; then
	printf '%s\n' "XMapWindow must remain outside the changed-geometry branch." >&2
	exit 1
fi
grep -q 'ewmh_replace_root_cardinal(dwmtagupdateatom, data, 1)' "$repo/dwm.c"
grep -q 'm->barwin, m->wx, m->by, m->ww, m->bh' "$repo/dwm.c"
grep -q 'selmon->barwin, selmon->wx, selmon->by, selmon->ww, selmon->bh' "$repo/dwm.c"
set_fullscreen_body=$(sed -n '/^setfullscreen(Client \*c, int fullscreen)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$set_fullscreen_body" | grep -q 'actualfullscreenchanged'
printf '%s\n' "$set_fullscreen_body" | grep -q 'wasactualfullscreen'
printf '%s\n' "$set_fullscreen_body" | grep -q 'updatefullscreenmonitors();'
visible_fullscreen_body=$(sed -n '/^isvisiblefullscreen(Client \*c)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$visible_fullscreen_body" | grep -q 'c->isfullscreen'
printf '%s\n' "$visible_fullscreen_body" | grep -q 'c->fakefullscreen != 1'
printf '%s\n' "$visible_fullscreen_body" | grep -q 'ISVISIBLE(c)'
monitor_has_fullscreen_body=$(sed -n '/^monitorhasfullscreen(Monitor \*m)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$monitor_has_fullscreen_body" | grep -q 'isvisiblefullscreen(c)'
fullscreen_monitors_body=$(sed -n '/^updatefullscreenmonitors(void)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$fullscreen_monitors_body" | grep -q 'monitorhasfullscreen(m)'
printf '%s\n' "$fullscreen_monitors_body" | grep -q 'getmonlogicalindex(m)'
printf '%s\n' "$fullscreen_monitors_body" | grep -q 'dwmfullscreenmonitorsatom'
priority_body=$(sed -n '/^restackprioritywindows(void)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$priority_body" | grep -q 'raisealwaysontopclients(m->stack)'
printf '%s\n' "$priority_body" | grep -q '!monitorhasfullscreen(m)'
printf '%s\n' "$priority_body" | grep -q 'ow->raise'
printf '%s\n' "$priority_body" | grep -q 'raisefullscreenclients(m->stack)'
printf '%s\n' "$priority_body" | grep -q 'focusfullscreenforoverride(focused)'
override_line=$(printf '%s\n' "$priority_body" |
	grep -n 'for (ow = overridewindows' | cut -d: -f1)
fullscreen_line=$(printf '%s\n' "$priority_body" |
	grep -n 'raisefullscreenclients(m->stack)' | cut -d: -f1)
test "$override_line" -lt "$fullscreen_line"
raise_fullscreen_clients_body=$(sed -n '/^raisefullscreenclients(Client \*c)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$raise_fullscreen_clients_body" | grep -q 'raisefullscreenclients(c->snext);'
printf '%s\n' "$raise_fullscreen_clients_body" | grep -q 'isvisiblefullscreen(c)'
property_notify_body=$(sed -n '/^propertynotify(XEvent \*e)/,/^}$/p' "$repo/dwm.c")
override_property_block=$(printf '%s\n' "$property_notify_body" |
	sed -n '/for (ow = overridewindows/,/if ((ev->window == root)/p')
printf '%s\n' "$override_property_block" | grep -q 'updateoverridewindow(ev->window);'
printf '%s\n' "$override_property_block" | grep -q 'XA_WM_TRANSIENT_FOR'
printf '%s\n' "$override_property_block" | grep -q 'restackprioritywindows();'
update_override_line=$(printf '%s\n' "$override_property_block" |
	grep -n 'updateoverridewindow(ev->window);' | cut -d: -f1)
restack_override_line=$(printf '%s\n' "$override_property_block" |
	grep -n 'restackprioritywindows();' | cut -d: -f1)
test "$update_override_line" -lt "$restack_override_line"
update_override_body=$(sed -n '/^updateoverridewindow(Window win)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$update_override_body" | grep -q 'istransientforbar(win)'
transient_bar_body=$(sed -n '/^istransientforbar(Window win)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$transient_bar_body" | grep -q 'XGetTransientForHint'
printf '%s\n' "$transient_bar_body" | grep -q 'isaltbar(trans, &wa)'
map_notify_body=$(sed -n '/^mapnotify(XEvent \*e)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$map_notify_body" | grep -q 'trackoverridewindow(ev->window);'
printf '%s\n' "$map_notify_body" | grep -q 'restackprioritywindows();'
focus_in_body=$(sed -n '/^focusin(XEvent \*e)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$focus_in_body" | grep -q 'focusfullscreenforoverride(ev->window)'
printf '%s\n' "$focus_in_body" | grep -q 'istransientforbar(ev->window)'
track_override_body=$(sed -n '/^trackoverridewindow(Window win)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$track_override_body" | grep -q 'FocusChangeMask'
tagmon_body=$(sed -n '/^tagmon(const Arg \*arg)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$tagmon_body" | grep -q 'c->isfullscreen = 1;'
printf '%s\n' "$tagmon_body" | grep -q 'updatefullscreenmonitors();'
reconcile_body=$(sed -n '/^reconcilemonitortags(void)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$reconcile_body" | grep -q 'dwmfullscreenmonitorsatom != None'
printf '%s\n' "$reconcile_body" | grep -q 'updatefullscreenmonitors();'
grep -q 'XInternAtom(dpy, "_DWM_FULLSCREEN_MONITORS", False)' "$repo/dwm.c"
grep -q 'XInternAtom(dpy, "_DWM_SELECTED_MONITOR", False)' "$repo/dwm.c"
focus_body=$(sed -n '/^focus(Client \*c)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$focus_body" | grep -q 'updateselectedmonitor();'
selected_monitor_body=$(sed -n '/^updateselectedmonitor(void)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$selected_monitor_body" | grep -q 'selectedmonitorcachevalid && logicalindex == selectedmonitorcache'
printf '%s\n' "$selected_monitor_body" | grep -q 'selectedmonitorcachevalid = 1;'
configure_notify_body=$(sed -n '/^configurenotify(XEvent \*e)/,/^}$/p' "$repo/dwm.c")
printf '%s\n' "$configure_notify_body" | grep -q 'selectedmonitorcachevalid = 0;'
grep -q 'XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_COMBO", False)' "$repo/dwm.c"

mkdir -p "$work/bin"
cat >"$work/bin/xprop" <<'SH'
#!/bin/sh
# Answers each requested property, the way real xprop does when several are
# named in one call. Exits 1 only when nothing requested exists.
found=0
skip_next=0
for arg in "$@"; do
	if [ "$skip_next" = 1 ]; then
		skip_next=0
		continue
	fi
	case $arg in
	-id)
		skip_next=1
		continue
		;;
	-*) continue ;;
	esac
	case $arg in
	_DWM_FULLSCREEN_MONITORS)
		[ "${DWM_TEST_FULLSCREEN_MONITORS+x}" = x ] || continue
		printf '_DWM_FULLSCREEN_MONITORS(CARDINAL) = %s\n' "$DWM_TEST_FULLSCREEN_MONITORS"
		found=1
		;;
	_DWM_MONITOR_DESKTOPS)
		[ "${DWM_TEST_MONITOR_DESKTOPS+x}" = x ] || continue
		printf '_DWM_MONITOR_DESKTOPS(CARDINAL) = %s\n' "$DWM_TEST_MONITOR_DESKTOPS"
		found=1
		;;
	_DWM_SELECTED_MONITOR)
		[ "${DWM_TEST_SELECTED_MONITOR+x}" = x ] || continue
		printf '_DWM_SELECTED_MONITOR(CARDINAL) = %s\n' "$DWM_TEST_SELECTED_MONITOR"
		found=1
		;;
	_NET_CURRENT_DESKTOP)
		printf '_NET_CURRENT_DESKTOP(CARDINAL) = 4\n'
		found=1
		;;
	_NET_NUMBER_OF_DESKTOPS)
		printf '_NET_NUMBER_OF_DESKTOPS(CARDINAL) = 9\n'
		found=1
		;;
	_NET_DESKTOP_NAMES)
		printf '_NET_DESKTOP_NAMES(UTF8_STRING) = "1", "2", "3", "4", "5", "6", "7", "8", "9"\n'
		found=1
		;;
	_NET_ACTIVE_WINDOW)
		printf '_NET_ACTIVE_WINDOW(WINDOW): window id # 0x0\n'
		found=1
		;;
	_NET_CLIENT_LIST)
		printf '_NET_CLIENT_LIST(WINDOW): window id #\n'
		found=1
		;;
	WM_NAME)
		printf 'WM_NAME(STRING) = "VOL 50%%"\n'
		found=1
		;;
	esac
done
[ "$found" = 1 ] || exit 1
exit 0
SH
cat >"$work/bin/xdotool" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$work/bin/xprop" "$work/bin/xdotool"

DWM_TEST_FULLSCREEN_MONITORS='0, 1' \
	DWM_TEST_MONITOR_DESKTOPS='2560, 0, 2560, 1440, 0, 0, 0, 2560, 1440, 4' \
	DWM_TEST_SELECTED_MONITOR=1 \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-state" state >"$work/state.out"
grep -Fqx 'monitor_desktops=2560,0,2560,1440,0,0,0,2560,1440,4' "$work/state.out"
grep -Fqx 'focused_monitor=1' "$work/state.out"
grep -Fqx 'fullscreen_monitors=0|1' "$work/state.out"

PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-state" state >"$work/fallback.out"
grep -Fqx 'monitor_desktops=4' "$work/fallback.out"

mkdir -p "$work/switchbin"
cat >"$work/switchbin/xdotool" <<SH
#!/bin/sh
printf 'xdotool %s\\n' "\$*" >>"$work/switch.log"
SH
cat >"$work/switchbin/wmctrl" <<SH
#!/bin/sh
printf 'wmctrl %s\\n' "\$*" >>"$work/switch.log"
SH
chmod +x "$work/switchbin/xdotool" "$work/switchbin/wmctrl"

: >"$work/switch.log"
PATH="$work/switchbin:$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-state" switch 4
grep -Fqx 'xdotool set_desktop 4' "$work/switch.log"
grep -q '^wmctrl ' "$work/switch.log" && exit 1

: >"$work/switch.log"
PATH="$work/switchbin:$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-state" focus 0x2400003
grep -Fqx 'xdotool windowactivate 0x2400003' "$work/switch.log"

mkdir -p "$work/wmctrlbin"
mv "$work/switchbin/wmctrl" "$work/wmctrlbin/wmctrl"
: >"$work/switch.log"
PATH="$work/wmctrlbin" \
	"$repo/scripts/dwm-quickshell-state" switch 4
grep -Fqx 'wmctrl -s 4' "$work/switch.log"

mkdir -p "$work/emptybin"
switch_status=0
PATH="$work/emptybin" \
	"$repo/scripts/dwm-quickshell-state" switch 4 2>"$work/switch.err" ||
	switch_status=$?
test "$switch_status" -eq 127
grep -q 'xdotool or wmctrl is required' "$work/switch.err"

printf '%s\n' "Monitor tag-switch source guard: PASS"
