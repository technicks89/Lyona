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

# ci_record_run RUN MODE WORKERS LOG
# Converts one ci-local --each result log into validation records. MODE is
# "serial" or "parallel"; the output is tab-separated so several runs can be
# appended to one file without losing their individual timings.
ci_record_run() {
	local run=$1 mode=$2 workers=$3 log=$4
	[[ $run =~ ^[A-Za-z0-9_.-]+$ ]] || {
		printf 'invalid validation run name: %s\n' "$run" >&2
		return 2
	}
	[[ $mode == serial || $mode == parallel ]] || {
		printf 'invalid validation mode: %s\n' "$mode" >&2
		return 2
	}
	[[ $workers =~ ^[1-9][0-9]*$ && -r $log ]] || {
		printf 'cannot record validation run %s from %s\n' "$run" "$log" >&2
		return 2
	}
	awk -v run="$run" -v mode="$mode" -v workers="$workers" '
		BEGIN { OFS = "\t" }
		$1 == "PASS" || $1 == "FAIL" {
			if (NF != 3 || $2 !~ /^[A-Za-z0-9_.-]+$/ || $3 !~ /^[0-9]+s$/ || seen[$2]++) {
				bad = 1
				next
			}
			seconds = $3
			sub(/s$/, "", seconds)
			print run, mode, workers, $2, $1, seconds
			count++
		}
		END { if (bad || count == 0) exit 1 }
	' "$log"
}

# ci_compare_runs RESULTS_FILE [MIN_PARALLEL_RUNS]
# Prints one TSV row per target with the serial result/timing and every
# parallel result/timing. Exactly one serial run and at least five four-worker
# runs are required by default. Outcome differences (or any non-pass result)
# fail the comparison; timing-only differences are reported but are not by
# themselves failures.
ci_compare_runs() {
	local results=$1 minimum=${2:-5}
	[[ -r $results && $minimum =~ ^[1-9][0-9]*$ ]] || {
		printf 'cannot compare CI validation results in %s\n' "$results" >&2
		return 2
	}
	awk -v minimum="$minimum" '
		BEGIN { FS = "\t"; OFS = "\t" }
		NF != 6 { malformed = 1; next }
		{
			run = $1
			if (!(run in run_seen)) {
				run_seen[run] = 1
				runs[++run_count] = run
				run_mode[run] = $2
				run_workers[run] = $3
			} else if (run_mode[run] != $2 || run_workers[run] != $3) {
				malformed = 1
			}
			if ($4 !~ /^[A-Za-z0-9_.-]+$/ || ($5 != "PASS" && $5 != "FAIL") ||
				$6 !~ /^[0-9]+$/ || ((run SUBSEP $4) in value_seen)) {
				malformed = 1
				next
			}
			value_seen[run SUBSEP $4] = 1
			outcome[run SUBSEP $4] = $5
			seconds[run SUBSEP $4] = $6
			if (!($4 in target_seen)) {
				target_seen[$4] = 1
				targets[++target_count] = $4
			}
		}
		END {
			for (i = 1; i <= run_count; i++) {
				run = runs[i]
				if (run_mode[run] == "serial" && run_workers[run] == 1) {
					serial_count++
					serial = run
				} else if (run_mode[run] == "parallel" && run_workers[run] == 4) {
					parallel[++parallel_count] = run
				} else {
					malformed = 1
				}
			}
			if (malformed || serial_count != 1 || parallel_count < minimum) {
				printf "validation needs exactly one serial run and at least %d parallel --jobs 4 runs (found %d and %d)\n", minimum, serial_count, parallel_count > "/dev/stderr"
				exit 2
			}
			printf "target\t%s_outcome\t%s_seconds", serial, serial
			for (i = 1; i <= parallel_count; i++)
				printf "\t%s_outcome\t%s_seconds", parallel[i], parallel[i]
			printf "\toutcome_difference\ttiming_difference\n"
			for (t = 1; t <= target_count; t++) {
				target = targets[t]
				base_outcome = outcome[serial SUBSEP target]
				base_seconds = seconds[serial SUBSEP target]
				if (base_outcome == "") base_outcome = "MISSING"
				if (base_seconds == "") base_seconds = "MISSING"
				outcome_diff = (base_outcome == "MISSING")
				timing_diff = (base_seconds == "MISSING")
				printf "%s\t%s\t%s", target, base_outcome, base_seconds
				if (base_outcome != "PASS") failed = 1
				for (i = 1; i <= parallel_count; i++) {
					run = parallel[i]
					current_outcome = outcome[run SUBSEP target]
					current_seconds = seconds[run SUBSEP target]
					if (current_outcome == "") current_outcome = "MISSING"
					if (current_seconds == "") current_seconds = "MISSING"
					printf "\t%s\t%s", current_outcome, current_seconds
					if (current_outcome != base_outcome) outcome_diff = 1
					if (current_seconds != base_seconds) timing_diff = 1
					if (current_outcome != "PASS") failed = 1
				}
				printf "\t%s\t%s\n", outcome_diff ? "yes" : "no", timing_diff ? "yes" : "no"
				if (outcome_diff) failed = 1
			}
			exit failed ? 1 : 0
		}
	' "$results"
}
