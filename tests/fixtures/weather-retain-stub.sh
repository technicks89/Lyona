#!/bin/sh
set -eu

# lyona-weather for tests/test-quickshell-weather-retain-xvfb.sh: no network.
# Each `current` answers the next line of $WEATHER_STUB_DIR/script, "ok TEMP
# PLACE" or "fail", and logs it; `status` and `set-location` keep the location
# in $WEATHER_STUB_DIR/location.
dir=${WEATHER_STUB_DIR:?}
case ${1:-} in
status)
	printf 'weather-settings-protocol\t1\t0\n'
	printf 'setting\tlocation\t%s\n' "$(cat "$dir/location")"
	printf 'setting\tunits\tauto\nsetting\tresolved-units\tcelsius\ncomplete\tstatus\n'
	;;
current)
	count=$(($(cat "$dir/count" 2>/dev/null || printf 0) + 1))
	printf '%s\n' "$count" >"$dir/count"
	line=$(sed -n "${count}p" "$dir/script")
	printf '%s %s\n' "$count" "$line" >>"$dir/current.log"
	printf 'weather-protocol\t1\t0\n'
	case $line in
	ok\ *)
		# shellcheck disable=SC2086 # the line's words are the fields
		set -- $line
		printf 'state\tavailable\tUpdated\n'
		printf 'weather\t%s\tC\t1\tMainly clear\t%s\t2026-11-14T12:00\n' "$2" "$3"
		;;
	*) printf 'state\tunavailable\tCould not reach the weather service\n' ;;
	esac
	printf 'complete\tcurrent\n'
	;;
set-location)
	printf '%s\n' "$2" >"$dir/location"
	printf 'weather-action-protocol\t1\t0\nresult\tset-location\tok\n'
	;;
*) exit 2 ;;
esac
