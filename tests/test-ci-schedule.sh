#!/usr/bin/env bash
set -euo pipefail

# scripts/ci-schedule.sh deals the check targets across parallel workers
# (ci-local.sh --each --jobs N). Pure bash: no Docker.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
# shellcheck source=scripts/ci-schedule.sh
source "$repo/scripts/ci-schedule.sh"

durations=$work/durations
printf '%s\n' 'check-a 400' 'check-b 300' 'check-c 100' 'check-d 100' 'check-e 50' 'check-f 50' >"$durations"

# Every target is assigned exactly once, and only to a worker that exists.
assigned=$(ci_schedule 3 "$durations" check-a check-b check-c check-d check-e check-f)
[[ $(printf '%s\n' "$assigned" | wc -l) -eq 6 ]] || fail 'not every target was assigned'
for target in check-a check-b check-c check-d check-e check-f; do
	[[ $(printf '%s\n' "$assigned" | awk -v t="$target" '$2 == t' | wc -l) -eq 1 ]] ||
		fail "$target was not assigned exactly once"
done
if printf '%s\n' "$assigned" | awk '$1 < 1 || $1 > 3 { bad = 1 } END { exit !bad }'; then
	fail 'a target went to a worker outside 1..3'
fi

# The two heaviest go to different workers, and the load is balanced: 400 | 300 | 100+100+50+50.
worker_a=$(printf '%s\n' "$assigned" | awk '$2 == "check-a" { print $1 }')
worker_b=$(printf '%s\n' "$assigned" | awk '$2 == "check-b" { print $1 }')
[[ $worker_a != "$worker_b" ]] || fail 'the two heaviest targets share a worker'
imbalance=$(printf '%s\n' "$assigned" | awk -v d="$durations" '
	BEGIN { while ((getline line < d) > 0) { split(line, p, " "); w[p[1]] = p[2] } }
	{ sum[$1] += w[$2] }
	END { max = 0; min = 1e9; for (k in sum) { if (sum[k] > max) max = sum[k]; if (sum[k] < min) min = sum[k] } print max - min }')
((imbalance <= 100)) || fail "the workers' loads differ by $imbalance seconds; expected a balanced split"

# The same inputs always give the same answer.
[[ $assigned == "$(ci_schedule 3 "$durations" check-a check-b check-c check-d check-e check-f)" ]] ||
	fail 'scheduling is not deterministic'

# One worker takes everything, in the order given.
one=$(ci_schedule 1 "$durations" check-c check-a check-b)
[[ $one == $'1 check-c\n1 check-a\n1 check-b' ]] || fail "a single worker should keep the recipe order: $one"

# Without any history the split is round robin (equal weights keep the order given,
# ties go to the lowest worker), and more workers than targets is fine.
none=$(ci_schedule 2 "$work/missing" t1 t2 t3 t4)
[[ $none == $'1 t1\n2 t2\n1 t3\n2 t4' ]] || fail "no history should deal round robin: $none"
few=$(ci_schedule 4 "$durations" check-a check-b)
[[ $(printf '%s\n' "$few" | wc -l) -eq 2 ]] || fail 'more workers than targets lost a target'

# A target with no recorded time counts as about the average one, not as free.
unknown=$(ci_schedule 2 "$durations" check-a check-b check-new)
worker_new=$(printf '%s\n' "$unknown" | awk '$2 == "check-new" { print $1 }')
worker_heavy=$(printf '%s\n' "$unknown" | awk '$2 == "check-a" { print $1 }')
[[ $worker_new != "$worker_heavy" ]] || fail 'an unknown target was put on top of the heaviest one'
# ...and the average is what it weighs: with 300, 200, 200 known it weighs about 233,
# so it pairs with the 200 rather than joining the 300 (a weight of 1 would do the opposite).
printf '%s\n' 'big 300' 'mid1 200' 'mid2 200' >"$work/avg"
average=$(ci_schedule 2 "$work/avg" big mid1 mid2 fresh)
worker_fresh=$(printf '%s\n' "$average" | awk '$2 == "fresh" { print $1 }')
worker_big=$(printf '%s\n' "$average" | awk '$2 == "big" { print $1 }')
worker_mid=$(printf '%s\n' "$average" | awk '$2 == "mid1" { print $1 }')
[[ $worker_fresh == "$worker_mid" && $worker_fresh != "$worker_big" ]] ||
	fail "an unknown target should weigh the average of the known ones: $average"

# A history file with junk lines is ignored line by line, not trusted.
printf '%s\n' 'check-a 400' 'check-b abc' 'check-c 1x' 'lonely' '' 'check-d -5' >"$work/junk"
junk=$(ci_schedule 2 "$work/junk" check-a check-b check-c check-d)
[[ $(printf '%s\n' "$junk" | wc -l) -eq 4 ]] || fail "a junk history file lost a target: $junk"

# Worker counts are capped by the cores and by the number of targets.
[[ $(ci_clamp_jobs 64 4 100) -eq 4 ]] || fail 'jobs above the core count were not capped'
[[ $(ci_clamp_jobs 8 16 3) -eq 3 ]] || fail 'jobs above the target count were not capped'
[[ $(ci_clamp_jobs 2 16 100) -eq 2 ]] || fail 'a reasonable job count was changed'
[[ $(ci_clamp_jobs 0 16 100) -eq 1 ]] || fail 'zero jobs should become one'

printf 'CI schedule: PASS\n'
