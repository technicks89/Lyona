#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-20 (decision D-19): scripts/lyona-weather against a stub
# curl. Nothing is fetched without a location; a fetch is HTTPS-only and bounded;
# a result is reused for 30 minutes; a failure is reported and not retried at
# once; a place name cannot break the protocol; units follow the locale unless
# set; and the settings and cache are private.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}

helper=$repo/scripts/lyona-weather
stub=$work/stub
mkdir -p "$stub/bin"
cat >"$stub/bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/log"
[ ! -e "$STUB_DIR/fail" ] || exit 22
for url; do :; done
case $url in
*geocoding-api.open-meteo.com*) cat "$STUB_DIR/geo.json" ;;
*api.open-meteo.com/v1/forecast*) cat "$STUB_DIR/forecast.json" ;;
*) exit 6 ;;
esac
EOF
chmod +x "$stub/bin/curl"
geo() { printf '{"results":[{"name":"%s","admin1":"Stockholm","country_code":"SE","latitude":59.33,"longitude":18.07}]}\n' "$1" >"$stub/geo.json"; }
forecast() { printf '{"current":{"time":"2026-10-02T12:00","temperature_2m":%s,"weather_code":%s}}\n' "$1" "$2" >"$stub/forecast.json"; }
geo Stockholm
forecast 11.5 61

reset_state() {
	rm -rf "$work/config" "$work/cache" "$stub/log" "$stub/fail"
	: >"$stub/log"
}
weather() {
	env STUB_DIR="$stub" PATH="$stub/bin:$PATH" XDG_CONFIG_HOME="$work/config" \
		XDG_CACHE_HOME="$work/cache" LANG="${weather_lang:-de_DE.UTF-8}" LC_ALL= LC_MEASUREMENT= \
		"$helper" "$@"
}
fetches() { grep -c . "$stub/log" || true; }
field() { awk -F '\t' -v n="$1" '$1 == "weather" { print $n }'; }

# ── no location: nothing is sent anywhere ───────────────────────────────
reset_state
out=$(weather current)
assert_string_contains "$out" $'state\tunconfigured\t'
assert_equals 0 "$(fetches)" 'fetches without a location'

# ── the first fetch: geocoding once, then the forecast, HTTPS-only and bounded ──
weather set-location Stockholm >/dev/null
out=$(weather current)
assert_string_contains "$out" $'state\tavailable\tUpdated'
assert_equals 11.5 "$(field 2 <<<"$out")" 'temperature'
assert_equals C "$(field 3 <<<"$out")" 'unit for de_DE'
assert_equals 'Rain' "$(field 5 <<<"$out")" 'description of code 61'
assert_equals 'Stockholm, Stockholm, SE' "$(field 6 <<<"$out")" 'place'
assert_equals 2 "$(fetches)" 'fetches for the first result'
while IFS= read -r call; do
	assert_string_contains "$call" "--proto =https"
	assert_string_contains "$call" "--max-time 10"
	assert_string_contains "$call" "--max-filesize"
done <"$stub/log"
grep -Fq 'temperature_unit=celsius' "$stub/log" || fail 'the forecast did not ask for Celsius'

# ── a result is reused for 30 minutes ───────────────────────────────────
out=$(weather current)
assert_string_contains "$out" $'state\tavailable\tCached'
assert_equals 2 "$(fetches)" 'a cached result fetched again'

# ── units: the locale, then the setting, which refreshes the result ─────
assert_string_contains "$(weather_lang=en_US.UTF-8 weather status)" $'setting\tresolved-units\tfahrenheit'
assert_string_contains "$(weather status)" $'setting\tresolved-units\tcelsius'
weather set-units fahrenheit >/dev/null
forecast 52.7 0
out=$(weather current)
assert_equals F "$(field 3 <<<"$out")" 'unit after set-units fahrenheit'
assert_equals 'Clear sky' "$(field 5 <<<"$out")" 'description of code 0'
grep -Fq 'temperature_unit=fahrenheit' "$stub/log" || fail 'the forecast did not ask for Fahrenheit'

# ── the settings and the cache are private ──────────────────────────────
assert_equals 600 "$(stat -c %a "$work/config/lyona/weather.conf")" 'weather.conf mode'
assert_equals 700 "$(stat -c %a "$work/cache/lyona/weather")" 'cache directory mode'
assert_equals 600 "$(stat -c %a "$work/cache/lyona/weather/current.tsv")" 'cache file mode'

# ── a failure is reported, and not retried at once ──────────────────────
reset_state
weather set-location Stockholm >/dev/null
: >"$stub/fail"
out=$(weather current)
assert_string_contains "$out" $'state\tunavailable\tCould not reach the weather service'
assert_string_contains "$out" $'complete\tcurrent'
before=$(fetches)
out=$(weather current)
assert_string_contains "$out" 'it will be retried shortly'
assert_equals "$before" "$(fetches)" 'a retry inside the wait'

# ── no such place, and an unexpected answer ─────────────────────────────
reset_state
weather set-location Nowhere >/dev/null
printf '{"generationtime_ms":0.5}\n' >"$stub/geo.json"
assert_string_contains "$(weather current)" $'state\tunavailable\tNo place matches "Nowhere"'
reset_state
geo Stockholm
forecast '"hot"' 61
weather set-location Stockholm >/dev/null
assert_string_contains "$(weather current)" 'The weather service sent an unexpected answer'

# ── a place name with a tab and a newline cannot add fields or lines ────
reset_state
forecast 3 71
geo $'Odd\\tPlace\\nweather\\t99'
weather set-location Odd >/dev/null
out=$(weather current)
assert_equals 4 "$(grep -c . <<<"$out")" 'lines in the result'
assert_equals 7 "$(awk -F '\t' '$1 == "weather" { print NF }' <<<"$out")" 'fields in the weather line'

# ── set-location refuses control characters and long text ───────────────
if weather set-location $'two\nlines' 2>/dev/null; then fail 'a location with a newline was accepted'; fi
if weather set-location "$(printf '%0101d' 0)" 2>/dev/null; then fail 'a 101-character location was accepted'; fi
if weather set-units kelvin 2>/dev/null; then fail 'unknown units were accepted'; fi
weather set-location '' >/dev/null
assert_string_contains "$(weather current)" $'state\tunconfigured\t'

printf 'Weather helper (stub curl): PASS\n'
