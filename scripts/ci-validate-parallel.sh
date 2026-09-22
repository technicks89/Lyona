#!/usr/bin/env bash
# Qualify ci-local parallel scheduling against one serial run. The comparison
# required by issue #86 is intentionally expensive: one serial --each run and
# five --each --jobs 4 runs, with every per-target outcome and timing retained.
set -euo pipefail

usage() {
	printf 'usage: %s REPORT_DIRECTORY\n' "${0##*/}"
}

(($# == 1)) || {
	usage >&2
	exit 2
}

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
report=$1
[[ ! -e $report ]] || {
	printf 'report path already exists: %s\n' "$report" >&2
	exit 2
}
mkdir -p -- "$report"
results=$report/results.tsv

# shellcheck source=scripts/ci-schedule.sh
source "$repo/scripts/ci-schedule.sh"

run_validation() {
	local label=$1
	shift
	local -a pipeline_status
	printf '\n==> Validation run: %s\n' "$label"
	set +e
	CI_LOCAL_VALIDATION_RESULTS="$results" CI_LOCAL_VALIDATION_RUN="$label" \
		"$repo/scripts/ci-local.sh" --each "$@" 2>&1 | tee "$report/$label.log"
	pipeline_status=("${PIPESTATUS[@]}")
	set -e
	((pipeline_status[0] == 0 && pipeline_status[1] == 0))
}

run_failed=0
run_validation serial || run_failed=1
for run in 1 2 3 4 5; do
	run_validation "parallel-$run" --jobs 4 || run_failed=1
done

set +e
ci_compare_runs "$results" 5 | tee "$report/comparison.tsv"
comparison_status=("${PIPESTATUS[@]}")
set -e
compare_status=${comparison_status[0]}
tee_status=${comparison_status[1]}

printf '\n==> Validation records: %s\n' "$results"
printf '==> Per-target comparison: %s\n' "$report/comparison.tsv"
if ((run_failed != 0 || compare_status != 0 || tee_status != 0)); then
	printf '==> Parallel validation FAILED; fix every outcome difference before merge or explicitly exclude that target from the parallel set.\n' >&2
	exit 1
fi
printf '==> Parallel validation PASSED (timing differences remain recorded in the comparison).\n'
