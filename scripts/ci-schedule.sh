#!/usr/bin/env bash
# Scheduling for scripts/ci-local.sh --each --jobs N: which target runs on which
# parallel worker. Sourced, not run; pure bash, no Docker.

# ci_schedule WORKERS DURATIONS_FILE TARGET...
# Prints "WORKER TARGET" lines, WORKER being 1..WORKERS. The file has one
# "TARGET SECONDS" pair per line (what an earlier run measured; it may be
# missing). Targets are dealt longest first to whichever worker has the least
# work so far (ties go to the lowest worker), so the workers finish at about the
# same time. A target with no recorded time counts as the average of the known
# ones; with no history at all every target counts the same, which deals them
# round robin. One worker keeps the order it was given.
ci_schedule() {
	local workers=$1 durations=$2
	shift 2
	local -A seconds load
	local target known=0 total=0 average=1 worker best index=0
	if [[ -r $durations ]]; then
		local name value
		while read -r name value; do
			[[ -n $name && $value =~ ^[0-9]+$ ]] && seconds[$name]=$value
		done <"$durations"
	fi
	for target in "$@"; do
		if [[ -n ${seconds[$target]:-} ]]; then
			known=$((known + 1))
			total=$((total + seconds[$target]))
		fi
	done
	((known == 0)) || average=$((total / known))
	((average >= 1)) || average=1
	for ((worker = 1; worker <= workers; worker++)); do load[$worker]=0; done
	if ((workers == 1)); then
		for target in "$@"; do printf '1 %s\n' "$target"; done
		return 0
	fi
	# Longest first; equal weights keep the order given.
	while read -r _ _ target; do
		best=1
		for ((worker = 2; worker <= workers; worker++)); do
			((load[$worker] < load[$best])) && best=$worker
		done
		printf '%d %s\n' "$best" "$target"
		load[$best]=$((load[$best] + ${seconds[$target]:-$average}))
	done < <(
		for target in "$@"; do
			index=$((index + 1))
			printf '%d %d %s\n' "${seconds[$target]:-$average}" "$index" "$target"
		done | LC_ALL=C sort -k1,1nr -k2,2n
	)
}

# ci_clamp_jobs REQUESTED CORES TARGETS
# The number of workers to use: at least one, and no more than the cores or the
# targets there are (more only oversubscribes the machine).
ci_clamp_jobs() {
	local jobs=$1 cores=$2 targets=$3
	((jobs <= cores)) || jobs=$cores
	((jobs <= targets)) || jobs=$targets
	((jobs >= 1)) || jobs=1
	printf '%d\n' "$jobs"
}
