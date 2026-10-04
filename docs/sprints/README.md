# Sync sprints

The upstream-sync sprint plans: what each sprint set out to do, the decisions
it needed, how it was verified, and what it actually delivered.

- **[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md)** is the index: every sprint's
  status, the sprint plan, and the decisions (`D-n`).
- **This folder** holds the sprints still open: code complete but waiting on a
  qualification, hardware or live-session check, or an open decision.
- **[`completed/`](completed/)** holds the sprints that are done.
- **[`sync-sprints-github.sh`](sync-sprints-github.sh)** creates each sprint's
  GitHub milestone and issues from the tables in these docs. Run it with
  `--dry-run` first.

When every check a sprint still waits on is done, move its document into
`completed/`. Then update its row in `UPSTREAM-SYNC.md` and its entry in
`sync-sprints-github.sh`, and run `tests/test-shell-contracts.sh`, which fails
on any cited `docs/` path that no longer exists.

The evidence a sprint records is in [`../evidence/`](../evidence/). Dated
whole-repo reviews are in [`../reviews/`](../reviews/).
