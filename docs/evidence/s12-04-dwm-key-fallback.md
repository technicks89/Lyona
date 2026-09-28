# S12-04 -- dwm always starts with working keys, and a config file cannot hang it

Plan: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-04-dwm-always-starts-with-working-keys-and-a-config-file-cannot-hang-it`.
Issue `#167`.

## Change

- **Fallback to the default, or to the previous config** (`dwm.c`). The plan diff
  always fell back to the default. It was changed so a live reload keeps what already
  works, which is what the runtime test already relied on.
  - `toml_load_with_fallback` now takes a usability check and whether a config is
    already in use.
  - A user file that does not parse, is empty, or holds nothing usable is reported.
  - At startup the shipped default is loaded ("invalid config - loaded defaults").
  - On a live reload the current config is kept ("invalid config - kept the previous
    config").
  - `notify_bad_config` now takes the whole message, so the text matches what
    happened. It used to append "- loaded defaults" even when dwm kept the old config.
- **"Usable" for hotkeys** (`hotkeys_doc_usable`): at least one `keys` entry with a
  known key and function, or one `tag_keys` entry with a known key and a tag in
  0-8. A file of comments, or of entries that bind nothing, counts as unusable. A
  `spawn` binding counts only with something to run (`exec` or `cmd`, the test
  `build_spawn_arg` applies, shared as `spawn_has_command`); otherwise a file whose only
  binding is an empty spawn passed the check, the loader refused it, and, having
  already reused the key arena, dwm dropped the keys in use even on a live reload (from
  review).
- **Emergency keys.** If neither the user file nor the default loads at startup, or
  every binding is refused:
  - Super+x runs `dwm-terminal`, and Super+Shift+q quits.
  - dwm prints and sends a notification that says so.
- **The parser opens files safely** (`tomlparser.c`, `toml_open`).
  - `open(O_RDONLY|O_NONBLOCK|O_CLOEXEC)`, so a FIFO cannot block.
  - `fstat` requires a regular file of at most 1 MiB; then non-blocking mode is
    cleared and the fd is handed to `fdopen`.
  - `toml_parse` also counts the bytes it reads and fails past the same 1 MiB, so a
    file that grows after the check is not read without end (from review).
  - A symlink to `/dev/zero` is refused and falls back to the default.
- **Tag range.** `tag_keys` with a tag outside `0 .. LENGTH(tags)-1` is skipped with a
  message instead of computing `1 << tag` out of range.
- **Signal race.** Handled with a self-pipe, not `pselect`: blocking SIGUSR1/SIGUSR2
  would be inherited by every child dwm forks. That includes the terminals `spawn`
  starts, and programs that rely on SIGUSR1.
  - `sig_wake_setup` makes a non-blocking, close-on-exec pipe before the handlers are
    installed.
  - The SIGUSR1 and SIGUSR2 handlers write one byte to it.
  - `run()` adds the read end to its `select()` set and drains it.
  - A signal that lands between the loop's checks and `select()` therefore wakes it at
    once. If the pipe cannot be made, dwm behaves as before.
- **Docs.**
  - `docs/src/configuration.md` describes the fallback.
  - `docs/src/troubleshooting.md` no longer says invalid TOML fails silently, and
    drops its advice to add a fallback key in `config.h` (there is no key table there
    any more). It gives the emergency keys and where dwm logs skipped entries.

## Results (2026-09-27, CachyOS, working tree, nothing committed)

- **Build.** `make` with the repo's flags, and a scratch build adding `-Wextra`
  (sign-compare and the existing unused-parameter noise excluded), give no new
  warnings.
- **`tests/test-dwm-config-fallback.sh`** (new, `make check-dwm-config-fallback`,
  part of `make check`): PASS.
  - A fresh dwm on an isolated Xvfb is started for each `hotkeys.toml` below. In each,
    Super+2 switches to the second tag and the "loaded defaults" notification is
    captured:
    - empty;
    - only comments;
    - entries with nothing bindable (a tag of 40);
    - one binding, a `spawn` with nothing to run;
    - a symlink to `/dev/zero`;
    - over 1 MiB;
    - a FIFO.
  - A live reload from the shipped keys to the spawn-only file keeps the keys in use
    (Super+2 still works) and says "kept the previous config".
  - Every run quits within 5 s of SIGUSR2.
  - dwm publishes `_NET_CURRENT_DESKTOP` before it grabs the keys, so the test presses
    Super+2 (and Super+Shift+q) again every half second while it waits, instead of
    once (from review). A binding that is really missing still fails after every
    press: the mutations below were rerun against the retrying test.
  - With an invalid user file and no default, the "no usable hotkeys" notification is
    sent, and Super+Shift+q quits dwm.
- **`tests/test-xvfb-runtime.sh`** (`check-xvfb-runtime`): PASS. Its live-reload case
  now expects "kept the previous config". It already showed the keys still work after
  a broken save.
- **Mutation checks.** All caught:
  - never falling back at startup;
  - dropping the usability check;
  - dropping the emergency keys;
  - dropping the spawn check;
  - dropping both size limits (dropping either one alone is covered by the other);
  - accepting non-regular files (the `/dev/zero` case never starts);
  - a blocking open (the FIFO case never starts).

## Not verified

- A file growing while it is read. The byte counter stops it, but the growth cannot be
  timed in a test; the oversized case exercises the same limit on a static file.

- The signal race itself. A SIGUSR2 sent while dwm is idle already interrupted
  `select()` before this change, and the window the pipe closes is too narrow to hit
  on purpose. The pipe path runs on every SIGUSR2 in the new test, but is not proven
  necessary by it.
- The out-of-range tag skip alone. The test file with a tag of 40 is refused as a
  whole by the usability check, so the per-entry skip in the loader is covered only
  by review.
- Super+x in the emergency table (it would start a real terminal).
