#!/bin/sh
# Test double for dwm-settings-picom, installed by test-quickshell-picom-model-xvfb.sh.
# `status` logs the call and answers from the files in $PICOM_STUB_DIR; `watch`
# speaks the watcher protocol the way the scenario named in $PICOM_SCENARIO says.
ctl=$PICOM_STUB_DIR

wait_for() {
	while [ ! -e "$ctl/$1" ]; do sleep 0.02; done
}

case $1 in
status)
	# The revision is what the file holds when the read starts (it is taken before
	# the call is logged, which is what the scenarios wait for); a slow read (the
	# first one only) answers late with that older revision.
	revision=$(cat "$ctl/revision")
	printf 'status\n' >>"$ctl/status.log"
	case $PICOM_SCENARIO in
	slow-*) [ "$(wc -l <"$ctl/status.log")" -ne 1 ] || sleep 1 ;;
	esac
	case $PICOM_SCENARIO in
	failed-read)
		if [ "$(wc -l <"$ctl/status.log")" -eq 1 ]; then
			printf 'Picom status failed\n' >&2
			exit 1
		fi
		;;
	esac
	printf '{"protocol":1,"editable":true,"installed":true,"running":true,"active":100,"inactive":100,"policy":"auto","effective":"","override":"","revision":"%s","path":"/tmp/picom.conf","detail":"","copyable":false}\n' "$revision"
	: >"$ctl/status.done"
	;;
watch)
	case $PICOM_SCENARIO in
	unchanged)
		wait_for status.done
		sleep 0.3
		printf 'ready\tr1\n'
		;;
	edited)
		# An edit lands after the first read and before the watcher is live.
		wait_for status.done
		printf 'r2\n' >"$ctl/revision"
		sleep 0.3
		printf 'ready\tr2\n'
		;;
	slow-unchanged)
		wait_for status.log
		printf 'ready\tr1\n'
		;;
	slow-edited)
		# The edit lands while the first read is still running.
		wait_for status.log
		printf 'r2\n' >"$ctl/revision"
		printf 'ready\tr2\n'
		;;
	failed-read)
		# The first read failed and the watcher cannot say what it saw: two empty
		# revisions must not look like a match.
		wait_for status.log
		sleep 0.3
		printf 'ready\n'
		;;
	bare-ready)
		# A watcher that cannot say what it saw: the model must read again.
		wait_for status.done
		sleep 0.3
		printf 'ready\n'
		;;
	changed-only | changed-real)
		wait_for status.done
		sleep 0.3
		printf 'ready\tr1\n'
		sleep 0.3
		printf 'r3\n' >"$ctl/revision"
		printf 'changed\n'
		# The real helper re-arms and says ready again, with the new revision.
		[ "$PICOM_SCENARIO" = changed-only ] || {
			sleep 0.05
			printf 'ready\tr3\n'
		}
		;;
	esac
	# Stay alive like the real watcher, until the model stops it.
	while :; do sleep 1; done
	;;
esac
