#!/bin/sh
# Test double for dwm-xdg-autostart, installed by test-quickshell-queued-run-xvfb.sh:
# `snapshot` is a slow read that leaves a line in the log; `watch` just idles.
case $1 in
snapshot)
	printf 'snapshot\n' >>"$QUEUED_RUN_LOG"
	sleep 0.5
	;;
watch)
	while :; do sleep 1; done
	;;
esac
