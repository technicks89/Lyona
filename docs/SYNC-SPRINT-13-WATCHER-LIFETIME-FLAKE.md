# Sync Sprint 13 -- Watchers that outlive the shell under load

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Independent of every other sprint.
It comes from Sprint 12 S12-13, whose full-suite runs kept stopping on one
test.

**Status:** planned 2026-09-29, not started, awaiting maintainer review. No
decision gates it. GitHub: milestone "Sync Sprint 13 - Watcher lifetime under
load" (due 2026-10-25), issue `#197`.

| Item | Issue | Kind | Gate |
| --- | --- | --- | --- |
| [S13-01](#s13-01-a-watchers-children-end-with-the-shell-however-busy-the-machine) | `#197` | Bug, test reliability | none |

---

## S13-01: A watcher's children end with the shell, however busy the machine

### The symptom

`check-quickshell-watcher-lifetime-xvfb` (`tests/test-quickshell-watcher-lifetime-xvfb.py`,
added in S12-09) failed in 3 of the 9 full-suite runs during S12-13.
- It SIGKILLs Quickshell and requires every process Quickshell started to be gone
  within 3 s (`DWM_WATCHER_LIFETIME_GRACE`).
- Every failure had the same one or two survivors:
  - `xprop -root -spy DWM_TAG_UPDATE ...`, from `dwm-quickshell-state watch`;
  - `inotifywait -m -P -e ...`, from `dwm-settings-appearance` (line 1330) or
    `dwm-accessibility-settings` (line 200).
- Rerun alone, the test passed every time: 3 of 3 after each failure, 12 runs
  in all. The failures came under the full suite's load, twice with a staged
  install running alongside.
- The first failure was on S12-13 step 1, which touched none of these scripts,
  so the fault predates S12-13. `make check` stops at its first failure, so each
  failure also hid every test after it.

### What is known

- `Commands.watchCommand` (S12-09) execs each resident watcher under `setpriv
  --pdeathsig TERM`, behind a PPID guard. The watcher, not its children, gets
  the signal when Quickshell dies.
- The watchers trap TERM as `exit 143` and stop their children in the EXIT trap
  (`dwm-quickshell-state`'s `watch_cleanup`, and `inventory_watch_cleanup` in
  `dwm-settings-appearance`).
- The children are not parent-bound themselves. Until that trap runs, and
  reaches them, they are orphans that live on.

### What is not known (step 1 decides)

The two survivors can come from either of two faults, and they need different
fixes:
1. **Slow:** under load, the watcher's TERM handler or its `kill` of the child
   takes more than 3 s. A longer grace would hide this, but a real shell crash
   would still leave the child running a while.
2. **Missed:** the cleanup never reaches the child. For example:
   - a child started, or restarted by a watch loop, after the cleanup read its
     PID;
   - a child held in a pipeline or process substitution whose PID the cleanup
     does not have.

   Then the child lives until X or the session ends, which is a real leak.

### Steps

1. **Make the test say which.** When a survivor is found, record for each one:
   - its parent PID and whether that parent is still alive;
   - its state (`/proc/PID/stat`);
   - whether it is still there after another 10 s.

   A survivor that goes on its own within seconds is fault 1; one still there is
   fault 2. Reproduce under load with the suite's own load: a loop running the
   test while `scripts/run-tests` runs, or `--each --jobs 4` in
   `scripts/ci-local.sh`, whose docs already warn it is timing-sensitive.
2. **Fix what step 1 finds.** Whichever fault it is, the likely fix is to bind
   each long-lived child to its watcher's death as well: start the `xprop -spy`
   and `inotifywait` children under the same `setpriv --pdeathsig` guard. The
   kernel then ends a child the moment its watcher dies, with no trap in the
   path.
   - `dwm-watchdog.sh`'s `run_parent_bound` already holds that guard. None of
     the three watchers sources `dwm-watchdog.sh` today; they would source it
     (from `$lyona_lib`, S12-13) rather than write a second copy.
   - For fault 2, also fix the race or the missing PID in the cleanup itself.
3. **Keep the 3 s grace** unless step 1 shows the fix cannot meet it on the CI
   runner. The test exists to catch leaks, and a longer grace weakens it for
   every watcher.
4. **Test.**
   - The lifetime test passes 20 runs in a row under the load that reproduced
     it.
   - It still fails, naming the child, against a watcher whose child is not
     bound (a mutation in a scratch copy).
   - The full suite passes.

### Not in scope

The one-shot helpers (the test's `ONE_SHOT` allowlist, with their 20 s grace)
and the watchers' polling behaviour (S12-07) are unchanged.
